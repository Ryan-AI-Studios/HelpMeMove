//! Signed synthetic pack evaluation. The fixture verifying key is not a production root.

use std::collections::HashSet;
use std::path::{Component, Path};

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use helpmemove_domain::BRIDGE_VERSION;
use serde::Deserialize;
use sha2::{Digest, Sha256};

use super::error::ContentError;
use super::model::{ApprovalStatus, is_exercise_id};
use super::validate::parse_exercise;

/// Public half of the test-only seed in `crates/content/tests/pack.rs`.
pub const FIXTURE_PACK_VERIFYING_KEY: [u8; 32] = [
    148, 107, 20, 36, 153, 119, 43, 83, 115, 3, 68, 251, 219, 77, 131, 192, 56, 77, 251, 78, 198,
    124, 202, 234, 94, 16, 133, 78, 215, 13, 138, 116,
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PackDecision {
    Accept,
    InvalidKey,
    InvalidSignature,
    InvalidManifest,
    IncompatibleEngine,
    PathEscape,
    HashMismatch,
    Rollback,
    Recalled,
    SyntheticViolation,
    Clock,
    Stale,
}

impl PackDecision {
    pub fn code(self) -> &'static str {
        match self {
            Self::Accept => "accept",
            Self::InvalidKey => "invalid-key",
            Self::InvalidSignature => "invalid-signature",
            Self::InvalidManifest => "invalid-manifest",
            Self::IncompatibleEngine => "incompatible-engine",
            Self::PathEscape => "path-escape",
            Self::HashMismatch => "hash-mismatch",
            Self::Rollback => "rollback",
            Self::Recalled => "recalled",
            Self::SyntheticViolation => "synthetic-violation",
            Self::Clock => "clock",
            Self::Stale => "stale",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DisableList {
    schema_version: u32,
    entries: Vec<DisableEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(deny_unknown_fields)]
struct DisableEntry {
    kind: String,
    id: String,
    version: u32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackManifest {
    schema_version: u32,
    pack_id: String,
    pack_version: u32,
    engine_compat: String,
    rule_set_ids: Vec<String>,
    exercise_ids: Vec<String>,
    files: Vec<PackFile>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct PackFile {
    path: String,
    sha256: String,
}

pub fn parse_signature_hex(hex: &str) -> Result<[u8; 64], ContentError> {
    parse_lower_hex(hex).map_err(|_| ContentError::InvalidSignature)
}

pub fn verify_disable_list(
    json_bytes: &[u8],
    signature_bytes: &[u8],
    verifying_key: &[u8; 32],
) -> Result<DisableList, ContentError> {
    let key = VerifyingKey::from_bytes(verifying_key).map_err(|_| ContentError::InvalidKey)?;
    let signature =
        Signature::try_from(signature_bytes).map_err(|_| ContentError::InvalidSignature)?;
    key.verify(json_bytes, &signature)
        .map_err(|_| ContentError::InvalidSignature)?;
    parse_disable_list(json_bytes)
}

pub fn parse_disable_list(json_bytes: &[u8]) -> Result<DisableList, ContentError> {
    let list: DisableList =
        serde_json::from_slice(json_bytes).map_err(|_| ContentError::InvalidManifest)?;
    if list.schema_version != 1 {
        return Err(ContentError::InvalidManifest);
    }
    let mut seen = HashSet::new();
    for entry in &list.entries {
        if entry.kind != "pack" && entry.kind != "rule" {
            return Err(ContentError::InvalidManifest);
        }
        if !is_exercise_id(&entry.id) || entry.version < 1 {
            return Err(ContentError::InvalidManifest);
        }
        if !seen.insert((entry.kind.as_str(), entry.id.as_str(), entry.version)) {
            return Err(ContentError::InvalidManifest);
        }
    }
    Ok(list)
}

#[allow(clippy::too_many_arguments)]
pub fn evaluate_pack(
    manifest_bytes: &[u8],
    signature_bytes: &[u8],
    files: &[(String, Vec<u8>)],
    verifying_key: &[u8; 32],
    floor_version: u32,
    disable_list: &DisableList,
    now_ms: i64,
    last_verified_at_ms: i64,
    max_offline_age_ms: Option<i64>,
) -> PackDecision {
    let Ok(key) = VerifyingKey::from_bytes(verifying_key) else {
        return PackDecision::InvalidKey;
    };
    let Ok(signature) = Signature::try_from(signature_bytes) else {
        return PackDecision::InvalidSignature;
    };
    if key.verify(manifest_bytes, &signature).is_err() {
        return PackDecision::InvalidSignature;
    }
    let Ok(manifest) = serde_json::from_slice::<PackManifest>(manifest_bytes) else {
        return PackDecision::InvalidManifest;
    };
    if let Err(decision) = check_manifest_fields(&manifest) {
        return decision;
    }
    for file in &manifest.files {
        if !path_ok(&file.path) {
            return PackDecision::PathEscape;
        }
    }
    let mut provided: HashSet<&str> = HashSet::new();
    for (path, _) in files {
        if !provided.insert(path.as_str()) {
            return PackDecision::HashMismatch;
        }
    }
    if manifest.files.len() != files.len() {
        return PackDecision::HashMismatch;
    }
    for file in &manifest.files {
        let Some((_, bytes)) = files.iter().find(|(path, _)| path == &file.path) else {
            return PackDecision::HashMismatch;
        };
        if encode_lower_hex(&Sha256::digest(bytes)) != file.sha256 {
            return PackDecision::HashMismatch;
        }
    }
    if manifest.pack_version < floor_version {
        return PackDecision::Rollback;
    }
    if disable_list.entries.iter().any(|entry| {
        entry.kind == "pack"
            && entry.id == manifest.pack_id
            && entry.version == manifest.pack_version
    }) {
        return PackDecision::Recalled;
    }
    for (path, bytes) in files {
        if !path.ends_with(".json") {
            continue;
        }
        if let Ok(exercise) = parse_exercise(bytes)
            && exercise.approval_status == ApprovalStatus::Approved
        {
            return PackDecision::SyntheticViolation;
        }
    }
    if now_ms < 0 || last_verified_at_ms < 0 {
        return PackDecision::Clock;
    }
    if let Some(age) = max_offline_age_ms {
        if age < 0 {
            return PackDecision::Clock;
        }
        if now_ms < last_verified_at_ms {
            return PackDecision::Clock;
        }
        if now_ms - last_verified_at_ms > age {
            return PackDecision::Stale;
        }
    }
    PackDecision::Accept
}

pub fn recalled_sessions(documents: &[String], disable_list: &DisableList) -> Vec<String> {
    let mut ids = Vec::new();
    for document in documents {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(document) else {
            continue;
        };
        let Some(object) = value.as_object() else {
            continue;
        };
        let Some(rule_id) = object.get("rule_id").and_then(serde_json::Value::as_str) else {
            continue;
        };
        let version = object
            .get("record_version")
            .and_then(serde_json::Value::as_u64)
            .filter(|value| *value >= 1)
            .unwrap_or(1);
        let Some(session_id) = object
            .get("session_id")
            .and_then(serde_json::Value::as_str)
            .filter(|id| !id.is_empty())
        else {
            continue;
        };
        let matched = disable_list.entries.iter().any(|entry| {
            entry.kind == "rule" && entry.id == rule_id && u64::from(entry.version) == version
        });
        if matched {
            ids.push(session_id.to_owned());
        }
    }
    ids
}

fn check_manifest_fields(manifest: &PackManifest) -> Result<(), PackDecision> {
    if manifest.schema_version != 1 {
        return Err(PackDecision::InvalidManifest);
    }
    if !is_exercise_id(&manifest.pack_id) || manifest.pack_version < 1 {
        return Err(PackDecision::InvalidManifest);
    }
    if manifest.engine_compat != BRIDGE_VERSION {
        return Err(PackDecision::IncompatibleEngine);
    }
    if !unique_ids(&manifest.rule_set_ids) || !unique_ids(&manifest.exercise_ids) {
        return Err(PackDecision::InvalidManifest);
    }
    if manifest.files.is_empty() {
        return Err(PackDecision::InvalidManifest);
    }
    let mut paths = HashSet::new();
    for file in &manifest.files {
        if !paths.insert(file.path.as_str()) {
            return Err(PackDecision::InvalidManifest);
        }
        if !is_sha256_hex(&file.sha256) {
            return Err(PackDecision::InvalidManifest);
        }
    }
    Ok(())
}

fn unique_ids(ids: &[String]) -> bool {
    let mut seen = HashSet::new();
    ids.iter()
        .all(|id| is_exercise_id(id) && seen.insert(id.as_str()))
}

fn path_ok(path: &str) -> bool {
    if path.is_empty() || path.contains('\\') || path.starts_with('/') {
        return false;
    }
    let mut any = false;
    for component in Path::new(path).components() {
        match component {
            Component::Normal(_) => any = true,
            _ => return false,
        }
    }
    any
}

fn is_sha256_hex(hex: &str) -> bool {
    hex.len() == 64
        && hex
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

fn parse_lower_hex<const N: usize>(hex: &str) -> Result<[u8; N], ()> {
    if hex.len() != N * 2 {
        return Err(());
    }
    let mut out = [0_u8; N];
    let bytes = hex.as_bytes();
    for (index, slot) in out.iter_mut().enumerate() {
        let high = hex_nibble(bytes[index * 2])?;
        let low = hex_nibble(bytes[index * 2 + 1])?;
        *slot = (high << 4) | low;
    }
    Ok(out)
}

fn hex_nibble(byte: u8) -> Result<u8, ()> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        _ => Err(()),
    }
}

pub fn encode_lower_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}
