//! Parse rule documents and evaluate them from caller-supplied instants.
//!
//! Day length is a document multiplier. It is not a clinical re-screen cadence.

use std::collections::BTreeSet;
use std::fmt;
use std::fs;
use std::path::Path;

use helpmemove_content::Exercise;
use helpmemove_domain::{DomainInstant, elapsed_millis};
use serde::Deserialize;
use serde::de::{self, Deserializer, MapAccess, SeqAccess, Visitor};
use serde_json::{Map, Value};

use crate::error::SafetyError;
use crate::model::{
    ActiveIssue, ApprovalKind, Classification, DeniedReason, Eligibility, EmergencyRow, Escalation,
    InterruptAction, InterruptDecision, InterruptRow, MatchRow, RuleLibrary, RuleSet, RuleSetId,
    ScreenDecision, SyntheticOnly, TriageLevel, TriageRow, is_rule_id, is_token,
};

const DAY_MS: u64 = 86_400_000;
const SYNTHETIC_TOKEN: &str = "unreviewed_synthetic";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawRuleSet {
    schema_version: u32,
    rule_set_id: String,
    rule_set_version: u32,
    approval_status: String,
    author: String,
    reviewer: String,
    clinical_approver: String,
    approval_date: String,
    last_reviewed: String,
    evidence_references: Vec<RawEvidence>,
    populations: Vec<String>,
    valid_for_days: u32,
    rescreen_tokens: Vec<String>,
    eligibility: Vec<RawMatch>,
    triage: Vec<RawTriage>,
    interrupts: Vec<RawInterrupt>,
    emergency_rows: Vec<RawEmergency>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawEvidence {
    title: String,
    citation: String,
    #[serde(default)]
    locator: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawMatch {
    token: String,
    equals: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawTriage {
    token: String,
    equals: String,
    level: String,
    restrictions: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawInterrupt {
    token: String,
    action: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawEmergency {
    region: String,
    display: String,
}

/// Validate one rule document. This does not apply the synthetic directory gate.
pub fn parse_rule_set(bytes: &[u8]) -> Result<RuleSet, SafetyError> {
    let raw = parse_raw_document(bytes)?;
    validate_raw(raw)
}

/// Read `*.json` in `path` only. Nested directories are ignored. Approved documents are rejected.
pub fn load_rule_dir(path: &Path, mode: SyntheticOnly) -> Result<RuleLibrary, SafetyError> {
    let SyntheticOnly = mode;
    let mut files = Vec::new();
    let entries = fs::read_dir(path).map_err(|_| SafetyError::Io)?;
    for entry in entries {
        let entry = entry.map_err(|_| SafetyError::Io)?;
        let file_type = entry.file_type().map_err(|_| SafetyError::Io)?;
        if !file_type.is_file() {
            continue;
        }
        let file_path = entry.path();
        if file_path
            .extension()
            .and_then(|extension| extension.to_str())
            != Some("json")
        {
            continue;
        }
        files.push(file_path);
    }
    files.sort();

    let mut rules = Vec::with_capacity(files.len());
    let mut seen = BTreeSet::new();
    for file_path in files {
        let bytes = fs::read(&file_path).map_err(|_| SafetyError::Io)?;
        let rule = parse_rule_set(&bytes)?;
        let stem = file_path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .ok_or(SafetyError::InvalidId)?;
        if stem != rule.id.as_str() {
            return Err(SafetyError::InvalidId);
        }
        if rule.approval != ApprovalKind::Synthetic {
            return Err(SafetyError::SyntheticViolation {
                field: "approval_status",
            });
        }
        if !seen.insert(rule.id.as_str().to_owned()) {
            return Err(SafetyError::Duplicate);
        }
        rules.push(rule);
    }
    Ok(RuleLibrary::from_rules(rules))
}

/// Match answers at `now`. `valid_for_days` is the document window, not a clinical cadence.
pub fn classify(
    rule: &RuleSet,
    answers: &[(&str, &str)],
    now: DomainInstant,
    triggers: &[&str],
) -> Result<Classification, SafetyError> {
    let mut seen = BTreeSet::new();
    for (token, value) in answers {
        if !is_token(token) || !is_token(value) {
            return Err(SafetyError::InvalidToken);
        }
        if !seen.insert(*token) {
            return Err(SafetyError::Duplicate);
        }
        if !declares(rule, token) {
            return Err(SafetyError::UnknownAnswer);
        }
    }

    if !rule
        .eligibility
        .iter()
        .all(|row| answer_matches(answers, &row.token, &row.equals))
    {
        return finish(
            rule,
            Eligibility::Ineligible,
            None,
            Vec::new(),
            now,
            triggers,
        );
    }

    let mut level: Option<TriageLevel> = None;
    let mut restrictions = BTreeSet::new();
    for row in &rule.triage {
        if !answer_matches(answers, &row.token, &row.equals) {
            continue;
        }
        level = Some(match level {
            Some(current) => current.max(row.level),
            None => row.level,
        });
        for token in &row.restrictions {
            restrictions.insert(token.clone());
        }
    }
    let Some(level) = level else {
        return Err(SafetyError::Unmatched);
    };
    finish(
        rule,
        Eligibility::Eligible,
        Some(level),
        restrictions.into_iter().collect(),
        now,
        triggers,
    )
}

/// Recompute staleness from the stored instant and `now`. This does not read a clock.
///
/// A classification that already requires screening stays that way until `classify`.
pub fn refresh(
    rule: &RuleSet,
    classification: &Classification,
    now: DomainInstant,
    triggers: &[&str],
) -> Result<Classification, SafetyError> {
    if classification.rule_set_id != rule.id {
        return Err(SafetyError::InvalidId);
    }
    if classification.rule_set_version != rule.version {
        return Err(SafetyError::RuleVersion);
    }
    let elapsed =
        elapsed_millis(classification.classified_at, now).map_err(|_| SafetyError::Clock)?;
    let elapsed_ms = u64::try_from(elapsed).map_err(|_| SafetyError::Clock)?;
    let window = window_millis(rule.valid_for_days)?;
    let mut next = classification.clone();
    if classification.screening_required
        || elapsed_ms >= window
        || rescreen_triggered(rule, triggers)
    {
        next.screening_required = true;
        next.permits_ordinary_generation = false;
        next.permits_progression = false;
    } else {
        restore_current(&mut next);
    }
    Ok(next)
}

/// Screen one exercise against the classification and every active issue.
pub fn screen_exercise(
    classification: &Classification,
    issues: &[ActiveIssue],
    exercise: &Exercise,
) -> Result<ScreenDecision, SafetyError> {
    let mut seen = BTreeSet::new();
    let mut union = BTreeSet::new();
    for token in &classification.restrictions {
        union.insert(token.as_str());
    }
    for issue in issues {
        if !is_rule_id(&issue.id) {
            return Err(SafetyError::InvalidId);
        }
        if !seen.insert(issue.id.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        for token in &issue.restrictions {
            if !is_token(token) {
                return Err(SafetyError::InvalidToken);
            }
            union.insert(token.as_str());
        }
    }
    let proceed = classification.eligibility == Eligibility::Eligible
        && !classification.screening_required
        && matches!(
            classification.level,
            Some(TriageLevel::Green | TriageLevel::Yellow | TriageLevel::Orange)
        );
    if !proceed {
        return Ok(ScreenDecision::Denied(DeniedReason::GenerationDenied));
    }
    if exercise
        .contraindications
        .iter()
        .any(|token| union.contains(token.as_str()))
    {
        return Ok(ScreenDecision::Denied(DeniedReason::Contraindicated));
    }
    Ok(ScreenDecision::Eligible)
}

/// Resolve an interrupt token. Unknown and empty tokens abort.
pub fn evaluate_interrupt(rule: &RuleSet, token: &str) -> InterruptDecision {
    for row in &rule.interrupts {
        if row.token == token {
            return InterruptDecision {
                action: row.action,
                fail_closed: false,
            };
        }
    }
    InterruptDecision {
        action: InterruptAction::Abort,
        fail_closed: true,
    }
}

/// Return the document display for a two-letter region. No default number is substituted.
pub fn emergency_display<'a>(rule: &'a RuleSet, region: &str) -> Result<&'a str, SafetyError> {
    if !is_region_code(region) {
        return Err(SafetyError::Region);
    }
    for row in &rule.emergency_rows {
        if row.region == region {
            return Ok(row.display.as_str());
        }
    }
    Err(SafetyError::UnknownRegion)
}

fn validate_raw(raw: RawRuleSet) -> Result<RuleSet, SafetyError> {
    if raw.schema_version != 1 {
        return Err(SafetyError::SchemaVersion);
    }
    if raw.rule_set_version != 1 {
        return Err(SafetyError::RuleVersion);
    }
    let id = RuleSetId::parse(&raw.rule_set_id)?;
    if !(1..=3650).contains(&raw.valid_for_days) {
        return Err(SafetyError::Limit);
    }
    let approval = match raw.approval_status.as_str() {
        "synthetic" => ApprovalKind::Synthetic,
        "approved" => ApprovalKind::Approved,
        _ => return Err(SafetyError::ApprovalStatus),
    };
    match approval {
        ApprovalKind::Synthetic => validate_synthetic(&raw)?,
        ApprovalKind::Approved => validate_approved(&raw)?,
    }
    Ok(RuleSet {
        id,
        version: raw.rule_set_version,
        approval,
        valid_for_days: raw.valid_for_days,
        rescreen_tokens: token_list(&raw.rescreen_tokens)?,
        eligibility: parse_matches(&raw.eligibility)?,
        triage: parse_triage(&raw.triage)?,
        interrupts: parse_interrupts(&raw.interrupts)?,
        emergency_rows: parse_emergency(&raw.emergency_rows)?,
    })
}

fn validate_synthetic(raw: &RawRuleSet) -> Result<(), SafetyError> {
    require_empty(&raw.author, "author")?;
    require_empty(&raw.reviewer, "reviewer")?;
    require_empty(&raw.clinical_approver, "clinical_approver")?;
    require_empty(&raw.approval_date, "approval_date")?;
    require_empty(&raw.last_reviewed, "last_reviewed")?;
    if !raw.evidence_references.is_empty() {
        return Err(SafetyError::SyntheticViolation {
            field: "evidence_references",
        });
    }
    if raw.populations.as_slice() == [SYNTHETIC_TOKEN] {
        Ok(())
    } else {
        Err(SafetyError::SyntheticViolation {
            field: "populations",
        })
    }
}

fn validate_approved(raw: &RawRuleSet) -> Result<(), SafetyError> {
    require_non_empty(&raw.author, "author")?;
    require_non_empty(&raw.reviewer, "reviewer")?;
    require_non_empty(&raw.clinical_approver, "clinical_approver")?;
    require_calendar_date(&raw.approval_date)?;
    require_calendar_date(&raw.last_reviewed)?;
    require_approved_evidence(&raw.evidence_references)?;
    require_approved_populations(&raw.populations)
}

fn require_approved_evidence(references: &[RawEvidence]) -> Result<(), SafetyError> {
    if references.is_empty() {
        return Err(SafetyError::ProductionField {
            field: "evidence_references",
        });
    }
    for reference in references {
        if reference.title.is_empty() {
            return Err(SafetyError::ProductionField { field: "title" });
        }
        if reference.citation.is_empty() {
            return Err(SafetyError::ProductionField { field: "citation" });
        }
        if !locator_ok(reference.locator.as_deref()) {
            return Err(SafetyError::InvalidDocument);
        }
    }
    Ok(())
}

fn locator_ok(locator: Option<&str>) -> bool {
    match locator {
        None => true,
        Some(value) => value.starts_with("https://") || value.starts_with("doi:"),
    }
}

fn require_approved_populations(values: &[String]) -> Result<(), SafetyError> {
    if values.is_empty() {
        return Err(SafetyError::ProductionField {
            field: "populations",
        });
    }
    let mut seen = BTreeSet::new();
    for value in values {
        if value.is_empty() {
            return Err(SafetyError::ProductionField {
                field: "populations",
            });
        }
        if value == SYNTHETIC_TOKEN {
            return Err(SafetyError::SyntheticViolation {
                field: "populations",
            });
        }
        if !seen.insert(value.as_str()) {
            return Err(SafetyError::Duplicate);
        }
    }
    Ok(())
}

fn require_empty(value: &str, field: &'static str) -> Result<(), SafetyError> {
    if value.is_empty() {
        Ok(())
    } else {
        Err(SafetyError::SyntheticViolation { field })
    }
}

fn require_non_empty(value: &str, field: &'static str) -> Result<(), SafetyError> {
    if value.is_empty() {
        Err(SafetyError::ProductionField { field })
    } else {
        Ok(())
    }
}

fn require_calendar_date(value: &str) -> Result<(), SafetyError> {
    if is_calendar_date(value) {
        Ok(())
    } else {
        Err(SafetyError::Date)
    }
}

fn is_calendar_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    let Some(year) = parse_digits(&bytes[0..4]) else {
        return false;
    };
    let Some(month) = parse_digits(&bytes[5..7]) else {
        return false;
    };
    let Some(day) = parse_digits(&bytes[8..10]) else {
        return false;
    };
    let max_day = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => return false,
    };
    (1..=max_day).contains(&day)
}

fn is_leap_year(year: u32) -> bool {
    year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
}

fn parse_digits(bytes: &[u8]) -> Option<u32> {
    if bytes.is_empty() {
        return None;
    }
    let mut value = 0u32;
    for byte in bytes {
        if !byte.is_ascii_digit() {
            return None;
        }
        let next = value.checked_mul(10)?;
        value = next + u32::from(*byte - b'0');
    }
    Some(value)
}

fn token_list(values: &[String]) -> Result<Vec<String>, SafetyError> {
    let mut out = Vec::with_capacity(values.len());
    let mut seen = BTreeSet::new();
    for value in values {
        if !is_token(value) {
            return Err(SafetyError::InvalidToken);
        }
        if !seen.insert(value.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        out.push(value.clone());
    }
    Ok(out)
}

fn parse_matches(rows: &[RawMatch]) -> Result<Vec<MatchRow>, SafetyError> {
    if rows.is_empty() {
        return Err(SafetyError::ProductionField {
            field: "eligibility",
        });
    }
    let mut out = Vec::with_capacity(rows.len());
    let mut seen = BTreeSet::new();
    for row in rows {
        if !is_token(&row.token) || !is_token(&row.equals) {
            return Err(SafetyError::InvalidToken);
        }
        if !seen.insert(row.token.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        out.push(MatchRow {
            token: row.token.clone(),
            equals: row.equals.clone(),
        });
    }
    Ok(out)
}

fn parse_triage(rows: &[RawTriage]) -> Result<Vec<TriageRow>, SafetyError> {
    if rows.is_empty() {
        return Err(SafetyError::ProductionField { field: "triage" });
    }
    let mut out = Vec::with_capacity(rows.len());
    let mut seen = BTreeSet::new();
    for row in rows {
        if !is_token(&row.token) || !is_token(&row.equals) {
            return Err(SafetyError::InvalidToken);
        }
        if !seen.insert(row.token.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        let level = match row.level.as_str() {
            "green" => TriageLevel::Green,
            "yellow" => TriageLevel::Yellow,
            "orange" => TriageLevel::Orange,
            "red" => TriageLevel::Red,
            _ => return Err(SafetyError::InvalidToken),
        };
        out.push(TriageRow {
            token: row.token.clone(),
            equals: row.equals.clone(),
            level,
            restrictions: token_list(&row.restrictions)?,
        });
    }
    Ok(out)
}

fn parse_interrupts(rows: &[RawInterrupt]) -> Result<Vec<InterruptRow>, SafetyError> {
    if rows.is_empty() {
        return Err(SafetyError::ProductionField {
            field: "interrupts",
        });
    }
    let mut out = Vec::with_capacity(rows.len());
    let mut seen = BTreeSet::new();
    for row in rows {
        if !is_token(&row.token) {
            return Err(SafetyError::InvalidToken);
        }
        if !seen.insert(row.token.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        let action = match row.action.as_str() {
            "continue" => InterruptAction::Continue,
            "reduce" => InterruptAction::Reduce,
            "pause" => InterruptAction::Pause,
            "abort" => InterruptAction::Abort,
            _ => return Err(SafetyError::InvalidToken),
        };
        out.push(InterruptRow {
            token: row.token.clone(),
            action,
        });
    }
    Ok(out)
}

fn parse_emergency(rows: &[RawEmergency]) -> Result<Vec<EmergencyRow>, SafetyError> {
    let mut out = Vec::with_capacity(rows.len());
    let mut seen = BTreeSet::new();
    for row in rows {
        if !is_region_code(&row.region) {
            return Err(SafetyError::Region);
        }
        if !is_visible_ascii(&row.display) {
            return Err(SafetyError::InvalidDocument);
        }
        if !seen.insert(row.region.as_str()) {
            return Err(SafetyError::Duplicate);
        }
        out.push(EmergencyRow {
            region: row.region.clone(),
            display: row.display.clone(),
        });
    }
    Ok(out)
}

fn is_region_code(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    bytes.len() == 2 && bytes.iter().all(|byte| byte.is_ascii_uppercase())
}

fn is_visible_ascii(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    (1..=32).contains(&bytes.len()) && bytes.iter().all(|byte| byte.is_ascii_graphic())
}

fn window_millis(days: u32) -> Result<u64, SafetyError> {
    u64::from(days)
        .checked_mul(DAY_MS)
        .ok_or(SafetyError::Limit)
}

fn declares(rule: &RuleSet, token: &str) -> bool {
    rule.eligibility.iter().any(|row| row.token == token)
        || rule.triage.iter().any(|row| row.token == token)
}

fn answer_matches(answers: &[(&str, &str)], token: &str, equals: &str) -> bool {
    answers
        .iter()
        .any(|(answer, value)| *answer == token && *value == equals)
}

fn rescreen_triggered(rule: &RuleSet, triggers: &[&str]) -> bool {
    triggers.iter().any(|token| {
        rule.rescreen_tokens
            .iter()
            .any(|candidate| candidate == token)
    })
}

fn outcome(level: TriageLevel) -> (bool, bool, Escalation) {
    match level {
        TriageLevel::Green | TriageLevel::Yellow => (true, true, Escalation::None),
        TriageLevel::Orange => (true, false, Escalation::Evaluation),
        TriageLevel::Red => (false, false, Escalation::Emergency),
    }
}

fn finish(
    rule: &RuleSet,
    eligibility: Eligibility,
    level: Option<TriageLevel>,
    restrictions: Vec<String>,
    now: DomainInstant,
    triggers: &[&str],
) -> Result<Classification, SafetyError> {
    let (generation, progression, escalation) = match (eligibility, level) {
        (Eligibility::Eligible, Some(level)) => outcome(level),
        _ => (false, false, Escalation::None),
    };
    let mut classification = Classification {
        rule_set_id: rule.id.clone(),
        rule_set_version: rule.version,
        eligibility,
        level,
        restrictions,
        permits_ordinary_generation: generation,
        permits_progression: progression,
        escalation,
        classified_at: now,
        screening_required: false,
    };
    if rescreen_triggered(rule, triggers) {
        classification.screening_required = true;
        classification.permits_ordinary_generation = false;
        classification.permits_progression = false;
    }
    Ok(classification)
}

fn restore_current(classification: &mut Classification) {
    let (generation, progression, escalation) =
        match (classification.eligibility, classification.level) {
            (Eligibility::Eligible, Some(level)) => outcome(level),
            _ => (false, false, Escalation::None),
        };
    classification.permits_ordinary_generation = generation;
    classification.permits_progression = progression;
    classification.escalation = escalation;
    classification.screening_required = false;
}

fn parse_raw_document(bytes: &[u8]) -> Result<RawRuleSet, SafetyError> {
    reject_duplicate_keys(bytes)?;
    let value: Value = serde_json::from_slice(bytes).map_err(|_| SafetyError::InvalidDocument)?;
    let Some(root) = value.as_object() else {
        return Err(SafetyError::InvalidDocument);
    };
    inspect_object(root, ROOT_FIELDS, ROOT_REQUIRED)?;
    inspect_object_array(
        root,
        "evidence_references",
        EVIDENCE_FIELDS,
        EVIDENCE_REQUIRED,
    )?;
    inspect_object_array(root, "eligibility", MATCH_FIELDS, MATCH_REQUIRED)?;
    inspect_object_array(root, "triage", TRIAGE_FIELDS, TRIAGE_REQUIRED)?;
    inspect_object_array(root, "interrupts", INTERRUPT_FIELDS, INTERRUPT_REQUIRED)?;
    inspect_object_array(root, "emergency_rows", EMERGENCY_FIELDS, EMERGENCY_REQUIRED)?;
    serde_json::from_value(value).map_err(|_| SafetyError::InvalidDocument)
}

const ROOT_FIELDS: &[&str] = &[
    "schema_version",
    "rule_set_id",
    "rule_set_version",
    "approval_status",
    "author",
    "reviewer",
    "clinical_approver",
    "approval_date",
    "last_reviewed",
    "evidence_references",
    "populations",
    "valid_for_days",
    "rescreen_tokens",
    "eligibility",
    "triage",
    "interrupts",
    "emergency_rows",
];

const ROOT_REQUIRED: &[&str] = ROOT_FIELDS;

const EVIDENCE_FIELDS: &[&str] = &["title", "citation", "locator"];
const EVIDENCE_REQUIRED: &[&str] = &["title", "citation"];
const MATCH_FIELDS: &[&str] = &["token", "equals"];
const MATCH_REQUIRED: &[&str] = MATCH_FIELDS;
const TRIAGE_FIELDS: &[&str] = &["token", "equals", "level", "restrictions"];
const TRIAGE_REQUIRED: &[&str] = TRIAGE_FIELDS;
const INTERRUPT_FIELDS: &[&str] = &["token", "action"];
const INTERRUPT_REQUIRED: &[&str] = INTERRUPT_FIELDS;
const EMERGENCY_FIELDS: &[&str] = &["region", "display"];
const EMERGENCY_REQUIRED: &[&str] = EMERGENCY_FIELDS;

fn inspect_object_array(
    root: &Map<String, Value>,
    field: &str,
    allowed: &[&str],
    required: &[&'static str],
) -> Result<(), SafetyError> {
    let Some(value) = root.get(field) else {
        return Ok(());
    };
    let Some(items) = value.as_array() else {
        return Err(SafetyError::InvalidDocument);
    };
    for item in items {
        let Some(object) = item.as_object() else {
            return Err(SafetyError::InvalidDocument);
        };
        inspect_object(object, allowed, required)?;
    }
    Ok(())
}

fn inspect_object(
    object: &Map<String, Value>,
    allowed: &[&str],
    required: &[&'static str],
) -> Result<(), SafetyError> {
    for key in object.keys() {
        if allowed.contains(&key.as_str()) {
            continue;
        }
        return Err(unknown_key(key));
    }
    for field in required {
        if !object.contains_key(*field) {
            return Err(SafetyError::MissingField { name: field });
        }
    }
    Ok(())
}

fn unknown_key(key: &str) -> SafetyError {
    if key.len() > 64 || key.bytes().any(|byte| !byte.is_ascii_graphic()) {
        SafetyError::InvalidDocument
    } else {
        SafetyError::UnknownField {
            name: key.to_owned(),
        }
    }
}

fn reject_duplicate_keys(bytes: &[u8]) -> Result<(), SafetyError> {
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    deserializer
        .deserialize_any(JsonWalk)
        .map_err(|_| SafetyError::InvalidDocument)?;
    deserializer.end().map_err(|_| SafetyError::InvalidDocument)
}

struct JsonValue;

impl<'de> Deserialize<'de> for JsonValue {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        deserializer.deserialize_any(JsonWalk)?;
        Ok(Self)
    }
}

struct JsonWalk;

impl<'de> Visitor<'de> for JsonWalk {
    type Value = ();

    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        formatter.write_str("a json value")
    }

    fn visit_bool<E: de::Error>(self, _value: bool) -> Result<(), E> {
        Ok(())
    }

    fn visit_i64<E: de::Error>(self, _value: i64) -> Result<(), E> {
        Ok(())
    }

    fn visit_u64<E: de::Error>(self, _value: u64) -> Result<(), E> {
        Ok(())
    }

    fn visit_f64<E: de::Error>(self, _value: f64) -> Result<(), E> {
        Ok(())
    }

    fn visit_str<E: de::Error>(self, _value: &str) -> Result<(), E> {
        Ok(())
    }

    fn visit_unit<E: de::Error>(self) -> Result<(), E> {
        Ok(())
    }

    fn visit_seq<A: SeqAccess<'de>>(self, mut access: A) -> Result<(), A::Error> {
        while access.next_element::<JsonValue>()?.is_some() {}
        Ok(())
    }

    fn visit_map<A: MapAccess<'de>>(self, mut access: A) -> Result<(), A::Error> {
        let mut seen = BTreeSet::new();
        while let Some(key) = access.next_key::<String>()? {
            if !seen.insert(key) {
                return Err(de::Error::custom("duplicate"));
            }
            access.next_value::<JsonValue>()?;
        }
        Ok(())
    }
}
