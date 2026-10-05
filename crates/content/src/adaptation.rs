//! Synthetic next-session check. The match table is not a clinical progression rule.

use serde_json::{Map, Number, Value};

use super::ContentError;
use super::model::{Exercise, Tempo};
use super::program::read_program_intake;
use super::session::{open_session, parse_session};

const RULE_ID: &str = "syn-adaptation-core";
const HIGH_REASON: &str = "Today's check says to wait. The exercises stay the same.";
const MAINTAIN_REASON: &str = "Today's check keeps the same exercises.";
const RULE_KEYS: [&str; 4] = ["matches", "record_version", "rule_id", "rule_version"];
const MATCH_KEYS: [&str; 3] = ["action", "reason", "soreness"];
const READINESS_KEYS: [&str; 6] = [
    "record_version",
    "recorded_at_ms",
    "rule_id",
    "rule_version",
    "session_id",
    "soreness",
];
const TRIAGE_KEYS: [&str; 4] = [
    "schema_green",
    "schema_yellow",
    "schema_orange",
    "schema_red",
];
const MAX_RECORDED_AT_MS: u64 = 9_223_372_036_854_775_807;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Soreness {
    Low,
    Moderate,
    High,
}

impl Soreness {
    fn parse(token: &str) -> Option<Self> {
        Some(match token {
            "low" => Self::Low,
            "moderate" => Self::Moderate,
            "high" => Self::High,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MatchRow {
    soreness: Soreness,
    action: &'static str,
    reason: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AdaptationRule {
    matches: [MatchRow; 3],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadinessDocument {
    pub recorded_at_ms: u64,
    pub session_id: String,
    pub soreness: Soreness,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AdaptationDecision {
    Ready(String),
    Withheld(&'static str),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdaptationError {
    Invalid,
    ProgramRejected,
    WorkoutRejected,
}

/// Accept the committed match table. Any other shape is [`ContentError::InvalidDocument`].
pub fn parse_adaptation_rule(text: &str) -> Result<AdaptationRule, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.len() != RULE_KEYS.len() || RULE_KEYS.iter().any(|key| !object.contains_key(*key)) {
        return Err(ContentError::InvalidDocument);
    }
    if object.get("rule_id").and_then(Value::as_str) != Some(RULE_ID)
        || !exact_i64(object.get("record_version"), 1)
        || !exact_i64(object.get("rule_version"), 1)
    {
        return Err(ContentError::InvalidDocument);
    }
    let Some(rows) = object.get("matches").and_then(Value::as_array) else {
        return Err(ContentError::InvalidDocument);
    };
    if rows.len() != 3 {
        return Err(ContentError::InvalidDocument);
    }
    let expected = [
        (Soreness::High, "pause_today", HIGH_REASON),
        (Soreness::Moderate, "maintain", MAINTAIN_REASON),
        (Soreness::Low, "maintain", MAINTAIN_REASON),
    ];
    let mut matches = [MatchRow {
        soreness: Soreness::High,
        action: "pause_today",
        reason: HIGH_REASON,
    }; 3];
    for (index, row) in rows.iter().enumerate() {
        let Some(row) = row.as_object() else {
            return Err(ContentError::InvalidDocument);
        };
        if row.len() != MATCH_KEYS.len() || MATCH_KEYS.iter().any(|key| !row.contains_key(*key)) {
            return Err(ContentError::InvalidDocument);
        }
        let Some(soreness) = row
            .get("soreness")
            .and_then(Value::as_str)
            .and_then(Soreness::parse)
        else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(action) = row.get("action").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(reason) = row.get("reason").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let (expected_soreness, expected_action, expected_reason) = expected[index];
        if soreness != expected_soreness || action != expected_action || reason != expected_reason {
            return Err(ContentError::InvalidDocument);
        }
        matches[index] = MatchRow {
            soreness,
            action: expected_action,
            reason: expected_reason,
        };
    }
    Ok(AdaptationRule { matches })
}

/// Accept the readiness document in spec §3.2. Extra keys and an out-of-range clock fail.
pub fn parse_readiness(text: &str) -> Result<ReadinessDocument, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.len() != READINESS_KEYS.len()
        || READINESS_KEYS.iter().any(|key| !object.contains_key(*key))
    {
        return Err(ContentError::InvalidDocument);
    }
    if !exact_i64(object.get("record_version"), 1)
        || object.get("rule_id").and_then(Value::as_str) != Some(RULE_ID)
        || !exact_i64(object.get("rule_version"), 1)
    {
        return Err(ContentError::InvalidDocument);
    }
    let Some(recorded_at_ms) = object.get("recorded_at_ms").and_then(Value::as_u64) else {
        return Err(ContentError::InvalidDocument);
    };
    if recorded_at_ms > MAX_RECORDED_AT_MS {
        return Err(ContentError::InvalidDocument);
    }
    let Some(session_id) = object.get("session_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidDocument);
    };
    if session_id.is_empty() {
        return Err(ContentError::InvalidDocument);
    }
    let Some(soreness) = object
        .get("soreness")
        .and_then(Value::as_str)
        .and_then(Soreness::parse)
    else {
        return Err(ContentError::InvalidDocument);
    };
    Ok(ReadinessDocument {
        recorded_at_ms,
        session_id: session_id.to_owned(),
        soreness,
    })
}

/// Read `schema_ack` and at most one triage token. Intake shape is checked first.
pub fn read_intake_safety_answers(text: &str) -> Result<Vec<(String, String)>, ContentError> {
    read_program_intake(text)?;
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    let Some(ack) = object.get("schema_ack").and_then(Value::as_str) else {
        return Err(ContentError::InvalidDocument);
    };
    let mut triage: Option<(&str, String)> = None;
    for key in TRIAGE_KEYS {
        let Some(value) = object.get(key) else {
            continue;
        };
        if triage.is_some() {
            return Err(ContentError::InvalidDocument);
        }
        let Some(token) = value.as_str() else {
            return Err(ContentError::InvalidDocument);
        };
        triage = Some((key, token.to_owned()));
    }
    let mut answers = vec![("schema_ack".to_owned(), ack.to_owned())];
    if let Some((key, token)) = triage {
        answers.push((key.to_owned(), token));
    }
    Ok(answers)
}

/// Match soreness and copy the program doses. Pain is copied and does not select the action.
pub fn decide_adaptation(
    workout_json: &str,
    program_json: &str,
    readiness_json: &str,
    rule_json: &str,
    library: &[Exercise],
    eligible_ids: &[&str],
    permits_progression: bool,
) -> Result<AdaptationDecision, AdaptationError> {
    if program_json.is_empty() {
        return Ok(AdaptationDecision::Withheld("no_program"));
    }
    if workout_json.is_empty() {
        return Ok(AdaptationDecision::Withheld("no_terminal_workout"));
    }
    let rule = parse_adaptation_rule(rule_json).map_err(|_| AdaptationError::Invalid)?;
    let readiness = parse_readiness(readiness_json).map_err(|_| AdaptationError::Invalid)?;
    let program = open_session(program_json, library, 0, "adaptation-probe")
        .map_err(|_| AdaptationError::ProgramRejected)?;
    let workout =
        parse_session(workout_json, library).map_err(|_| AdaptationError::WorkoutRejected)?;
    if workout.session_id != readiness.session_id {
        return Err(AdaptationError::Invalid);
    }
    match workout.outcome.as_deref() {
        Some("safety_stopped") => {
            return Ok(AdaptationDecision::Withheld("safety_stopped"));
        }
        Some("completed" | "abandoned") => {}
        _ => return Err(AdaptationError::Invalid),
    }
    if !permits_progression {
        return Ok(AdaptationDecision::Withheld("progression_denied"));
    }
    for exercise in &program.exercises {
        if !eligible_ids
            .iter()
            .any(|candidate| *candidate == exercise.exercise_id)
        {
            return Ok(AdaptationDecision::Withheld("exercise_denied"));
        }
    }
    let Some(matched) = rule
        .matches
        .iter()
        .find(|row| row.soreness == readiness.soreness)
    else {
        return Err(AdaptationError::Invalid);
    };
    let mut exercises = Vec::with_capacity(program.exercises.len());
    for exercise in &program.exercises {
        exercises.push(copied_exercise(
            &exercise.exercise_id,
            exercise.sets,
            exercise.reps,
            exercise.tempo,
        )?);
    }
    let pain = match workout.reported_pain {
        Some(value) if value <= 10 => Value::Number(json_number(u64::from(value))?),
        _ => Value::Null,
    };
    let mut root = Map::new();
    root.insert(
        "action".to_owned(),
        Value::String(matched.action.to_owned()),
    );
    root.insert("exercises".to_owned(), Value::Array(exercises));
    root.insert(
        "reason".to_owned(),
        Value::String(matched.reason.to_owned()),
    );
    root.insert("record_version".to_owned(), Value::Number(json_number(1)?));
    root.insert("reported_pain".to_owned(), pain);
    root.insert("rule_id".to_owned(), Value::String(RULE_ID.to_owned()));
    root.insert("rule_version".to_owned(), Value::Number(json_number(1)?));
    root.insert(
        "session_id".to_owned(),
        Value::String(workout.session_id.clone()),
    );
    let document =
        serde_json::to_string(&Value::Object(root)).map_err(|_| AdaptationError::Invalid)?;
    Ok(AdaptationDecision::Ready(document))
}

fn copied_exercise(
    exercise_id: &str,
    sets: u32,
    reps: u32,
    tempo: Tempo,
) -> Result<Value, AdaptationError> {
    let mut tempo_object = Map::new();
    tempo_object.insert(
        "eccentric".to_owned(),
        Value::Number(json_number(u64::from(tempo.eccentric))?),
    );
    tempo_object.insert(
        "pause".to_owned(),
        Value::Number(json_number(u64::from(tempo.pause))?),
    );
    tempo_object.insert(
        "concentric".to_owned(),
        Value::Number(json_number(u64::from(tempo.concentric))?),
    );
    let mut object = Map::new();
    object.insert(
        "exercise_id".to_owned(),
        Value::String(exercise_id.to_owned()),
    );
    object.insert(
        "sets".to_owned(),
        Value::Number(json_number(u64::from(sets))?),
    );
    object.insert(
        "reps".to_owned(),
        Value::Number(json_number(u64::from(reps))?),
    );
    object.insert("tempo".to_owned(), Value::Object(tempo_object));
    Ok(Value::Object(object))
}

fn json_number(value: u64) -> Result<Number, AdaptationError> {
    Number::from_u128(u128::from(value)).ok_or(AdaptationError::Invalid)
}

fn exact_i64(value: Option<&Value>, expected: i64) -> bool {
    value.and_then(Value::as_i64) == Some(expected)
}
