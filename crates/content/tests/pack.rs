//! Fixture pack signatures. The seed is test-only and must not appear under src/.

use std::fs;
use std::path::{Path, PathBuf};

use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use helpmemove_content::{
    DisableList, FIXTURE_PACK_VERIFYING_KEY, PackDecision, encode_lower_hex, evaluate_pack,
    parse_disable_list, parse_signature_hex, recalled_sessions, verify_disable_list,
};
use sha2::{Digest, Sha256};

/// Test-only seed. Not a production signing root.
const TEST_PACK_SEED: [u8; 32] = [
    0x74, 0x65, 0x73, 0x74, 0x2d, 0x70, 0x61, 0x63, 0x6b, 0x2d, 0x73, 0x65, 0x65, 0x64, 0x2d, 0x30,
    0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
];

const EMPTY_LIST: &str = r#"{"schema_version":1,"entries":[]}"#;

fn signing_key() -> SigningKey {
    SigningKey::from_bytes(&TEST_PACK_SEED)
}

fn sign(bytes: &[u8]) -> [u8; 64] {
    signing_key().sign(bytes).to_bytes()
}

fn empty_list() -> DisableList {
    parse_disable_list(EMPTY_LIST.as_bytes()).expect("empty list")
}

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/packs")
}

fn repo_disable_list() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../content/packs/syn-disable-list.json")
}

fn read_committed_signature(path: &Path) -> [u8; 64] {
    let hex = fs::read_to_string(path).expect("sig");
    parse_signature_hex(hex.trim()).expect("hex")
}

type PackFiles = Vec<(String, Vec<u8>)>;

fn load_pack(name: &str) -> (Vec<u8>, [u8; 64], PackFiles) {
    let dir = fixtures().join(name);
    let manifest = fs::read(dir.join("manifest.json")).expect("manifest");
    let signature = read_committed_signature(&dir.join("manifest.sig"));
    let files = if name.ends_with("escape") {
        let bytes = fs::read(dir.join("exercises/syn-shoulder-isometric.json")).expect("exercise");
        vec![("../exercises/syn-shoulder-isometric.json".to_owned(), bytes)]
    } else {
        load_files(&dir)
    };
    (manifest, signature, files)
}

fn load_files(dir: &Path) -> PackFiles {
    let mut files = Vec::new();
    visit(dir, dir, &mut files);
    files.sort_by(|left, right| left.0.cmp(&right.0));
    files
}

fn visit(root: &Path, current: &Path, files: &mut PackFiles) {
    for entry in fs::read_dir(current).expect("read dir") {
        let entry = entry.expect("entry");
        let path = entry.path();
        if path.is_dir() {
            visit(root, &path, files);
            continue;
        }
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("");
        if name == "manifest.json" || name == "manifest.sig" {
            continue;
        }
        let relative = path
            .strip_prefix(root)
            .expect("relative")
            .to_string_lossy()
            .replace('\\', "/");
        files.push((relative, fs::read(&path).expect("file")));
    }
}

fn decide(
    name: &str,
    floor: u32,
    list: &DisableList,
    now_ms: i64,
    last_verified_at_ms: i64,
    max_offline_age_ms: Option<i64>,
) -> PackDecision {
    let (manifest, signature, files) = load_pack(name);
    evaluate_pack(
        &manifest,
        &signature,
        &files,
        &FIXTURE_PACK_VERIFYING_KEY,
        floor,
        list,
        now_ms,
        last_verified_at_ms,
        max_offline_age_ms,
    )
}

fn session(rule_id: &str, record_version: u64, session_id: &str) -> String {
    format!(
        r#"{{"rule_id":"{rule_id}","record_version":{record_version},"session_id":"{session_id}"}}"#
    )
}

#[test]
fn fixture_key_matches_seed() {
    let verifying = signing_key().verifying_key();
    assert_eq!(verifying.to_bytes(), FIXTURE_PACK_VERIFYING_KEY);
    assert_eq!(
        VerifyingKey::from_bytes(&FIXTURE_PACK_VERIFYING_KEY)
            .expect("key")
            .to_bytes(),
        verifying.to_bytes()
    );
}

#[test]
fn committed_disable_list_verifies() {
    let json = fs::read(repo_disable_list()).expect("disable list");
    let signature = read_committed_signature(&repo_disable_list().with_extension("sig"));
    verify_disable_list(&json, &signature, &FIXTURE_PACK_VERIFYING_KEY).expect("verify");
}

#[test]
fn v2_fixture_accepts_above_v1() {
    assert_eq!(
        decide("syn-shoulder-pack-v2", 2, &empty_list(), 10, 10, None),
        PackDecision::Accept
    );
}

#[test]
fn v1_fixture_accepts() {
    assert_eq!(
        decide("syn-shoulder-pack-v1", 1, &empty_list(), 10, 10, None),
        PackDecision::Accept
    );
}

#[test]
fn bad_signature_is_invalid_signature() {
    assert_eq!(
        decide("syn-shoulder-pack-bad-sig", 1, &empty_list(), 10, 10, None),
        PackDecision::InvalidSignature
    );
}

#[test]
fn wrong_sha_is_hash_mismatch() {
    assert_eq!(
        decide("syn-shoulder-pack-hash", 1, &empty_list(), 10, 10, None),
        PackDecision::HashMismatch
    );
}

#[test]
fn parent_path_is_path_escape() {
    assert_eq!(
        decide("syn-shoulder-pack-escape", 1, &empty_list(), 10, 10, None),
        PackDecision::PathEscape
    );
}

#[test]
fn other_engine_is_incompatible() {
    assert_eq!(
        decide("syn-shoulder-pack-engine", 1, &empty_list(), 10, 10, None),
        PackDecision::IncompatibleEngine
    );
}

#[test]
fn floor_above_pack_is_rollback() {
    assert_eq!(
        decide("syn-shoulder-pack-v1", 2, &empty_list(), 10, 10, None),
        PackDecision::Rollback
    );
}

#[test]
fn recalled_pack_version_is_recalled() {
    let list = parse_disable_list(
        br#"{"schema_version":1,"entries":[{"kind":"pack","id":"syn-shoulder-pack","version":1}]}"#,
    )
    .expect("list");
    assert_eq!(
        decide("syn-shoulder-pack-v1", 1, &list, 10, 10, None),
        PackDecision::Recalled
    );
}

#[test]
fn stale_and_clock() {
    assert_eq!(
        decide("syn-shoulder-pack-v1", 1, &empty_list(), 20, 0, Some(5)),
        PackDecision::Stale
    );
    assert_eq!(
        decide("syn-shoulder-pack-v1", 1, &empty_list(), 0, 10, Some(5)),
        PackDecision::Clock
    );
}

#[test]
fn invalid_key_and_manifest() {
    let (manifest, signature, files) = load_pack("syn-shoulder-pack-v1");
    let mut bad_key = [0_u8; 32];
    bad_key[31] = 1;
    assert_eq!(
        evaluate_pack(
            &manifest,
            &signature,
            &files,
            &bad_key,
            1,
            &empty_list(),
            10,
            10,
            None
        ),
        PackDecision::InvalidKey
    );
    let unknown = br#"{"schema_version":1,"pack_id":"syn-shoulder-pack","pack_version":1,"engine_compat":"helpmemove-bridge-1","rule_set_ids":[],"exercise_ids":[],"files":[{"path":"exercises/syn-shoulder-isometric.json","sha256":"8f744eb1dea45bc6ae94458677f6965bd971dfa5ea9bad4054e45fd66ff11330"}],"extra":true}"#;
    let signed = sign(unknown);
    assert_eq!(
        evaluate_pack(
            unknown,
            &signed,
            &files,
            &FIXTURE_PACK_VERIFYING_KEY,
            1,
            &empty_list(),
            10,
            10,
            None
        ),
        PackDecision::InvalidManifest
    );
    let duplicate = br#"{"schema_version":1,"pack_id":"syn-shoulder-pack","pack_version":1,"engine_compat":"helpmemove-bridge-1","rule_set_ids":[],"exercise_ids":[],"files":[{"path":"exercises/syn-shoulder-isometric.json","sha256":"8f744eb1dea45bc6ae94458677f6965bd971dfa5ea9bad4054e45fd66ff11330"},{"path":"exercises/syn-shoulder-isometric.json","sha256":"8f744eb1dea45bc6ae94458677f6965bd971dfa5ea9bad4054e45fd66ff11330"}]}"#;
    let signed_dup = sign(duplicate);
    assert_eq!(
        evaluate_pack(
            duplicate,
            &signed_dup,
            &files,
            &FIXTURE_PACK_VERIFYING_KEY,
            1,
            &empty_list(),
            10,
            10,
            None
        ),
        PackDecision::InvalidManifest
    );
}

#[test]
fn approved_exercise_is_synthetic_violation() {
    let approved = br#"{
                "schema_version": 1,
                "exercise_id": "schema-approved",
                "exercise_version": 1,
                "name": "Schema approved shape",
                "regions": ["leg"],
                "laterality": "left",
                "targets": ["synthetic_target"],
                "goals": ["control"],
                "difficulty": 1,
                "equipment": ["chair"],
                "positions": ["seated"],
                "progressions": [],
                "regressions": [],
                "substitutions": [],
                "contraindications": ["schema-constraint"],
                "camera_views": ["front"],
                "tracked_metrics": ["repetition_count"],
                "default_sets": 1,
                "default_reps": 1,
                "tempo": { "eccentric": 0, "pause": 0, "concentric": 0 },
                "spoken_instructions": ["Schema text."],
                "written_instructions": "Schema text.",
                "common_mistakes": ["schema-constraint"],
                "modifications": ["schema-constraint"],
                "approval_status": "approved",
                "author": "schema-author",
                "reviewer": "schema-reviewer",
                "clinical_approver": "schema-approver",
                "approval_date": "2024-02-29",
                "last_reviewed": "2024-02-29",
                "evidence_references": [{
                    "title": "Schema evidence",
                    "citation": "Schema citation",
                    "locator": "doi:10.0000/schema"
                }],
                "populations": ["schema-population"],
                "license": {
                    "license_type": "cc0",
                    "copyright_holder": "schema-holder",
                    "attribution_notice": "schema-notice",
                    "talent_release_id": "schema-release"
                },
                "media": {
                    "video_mp4": "clip.mp4",
                    "start_image_webp": "start.webp",
                    "end_image_webp": "end.webp",
                    "animation_riv": null
                }
            }"#;
    let sha = encode_lower_hex(&Sha256::digest(approved));
    let manifest = format!(
        r#"{{"schema_version":1,"pack_id":"syn-shoulder-pack","pack_version":1,"engine_compat":"helpmemove-bridge-1","rule_set_ids":[],"exercise_ids":["schema-approved"],"files":[{{"path":"exercises/schema-approved.json","sha256":"{sha}"}}]}}"#
    );
    let signed = sign(manifest.as_bytes());
    let files = vec![(
        "exercises/schema-approved.json".to_owned(),
        approved.to_vec(),
    )];
    assert_eq!(
        evaluate_pack(
            manifest.as_bytes(),
            &signed,
            &files,
            &FIXTURE_PACK_VERIFYING_KEY,
            1,
            &empty_list(),
            10,
            10,
            None
        ),
        PackDecision::SyntheticViolation
    );
    assert_eq!(
        PackDecision::SyntheticViolation.code(),
        "synthetic-violation"
    );
}

#[test]
fn parse_signature_hex_rejects_uppercase_and_length() {
    assert!(parse_signature_hex("AA").is_err());
    assert!(parse_signature_hex(&"a".repeat(128)).is_ok());
    assert!(parse_signature_hex(&"A".repeat(128)).is_err());
    assert!(parse_signature_hex(&format!("{} ", "a".repeat(127))).is_err());
}

#[test]
fn recalled_sessions_match_rule_version_one() {
    let matching = parse_disable_list(
        br#"{"schema_version":1,"entries":[{"kind":"rule","id":"syn-program-core","version":1}]}"#,
    )
    .expect("list");
    let version_two = parse_disable_list(
        br#"{"schema_version":1,"entries":[{"kind":"rule","id":"syn-program-core","version":2}]}"#,
    )
    .expect("list");
    let pack_only = parse_disable_list(
        br#"{"schema_version":1,"entries":[{"kind":"pack","id":"syn-shoulder-pack","version":1}]}"#,
    )
    .expect("list");
    let documents = vec![
        session("syn-program-core", 1, "session-one"),
        "not-json".to_owned(),
    ];
    assert_eq!(
        recalled_sessions(&documents, &matching),
        vec!["session-one".to_owned()]
    );
    assert!(recalled_sessions(&documents, &version_two).is_empty());
    assert!(recalled_sessions(&documents, &pack_only).is_empty());
    assert!(recalled_sessions(&documents, &empty_list()).is_empty());
}

#[test]
fn verify_disable_list_rejects_bad_signature() {
    let json = EMPTY_LIST.as_bytes();
    let good = sign(json);
    verify_disable_list(json, &good, &FIXTURE_PACK_VERIFYING_KEY).expect("good");
    let mut bad = good;
    bad[0] ^= 1;
    assert_eq!(
        verify_disable_list(json, &bad, &FIXTURE_PACK_VERIFYING_KEY)
            .expect_err("bad")
            .code(),
        "invalid-signature"
    );
}
