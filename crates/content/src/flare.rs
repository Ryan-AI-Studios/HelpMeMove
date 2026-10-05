//! Synthetic follow-up after a stored workout. The match table is not a clinical flare rule.

use serde_json::{Map, Number, Value};

use super::ContentError;
use super::model::{Exercise, Tempo};
use super::session::{open_session, parse_session};

const RULE_ID: &str = "syn-flare-core";
const PAUSE_REASON: &str = "Today's check says to wait. The exercises stay the same.";
const KEEP_REASON: &str = "Today's check keeps the same exercises.";
const RULE_KEYS: [&str; 4] = ["matches", "record_version", "rule_id", "rule_version"];
const MATCH_KEYS: [&str; 3] = ["action", "choice", "reason"];
const FOLLOWUP_KEYS: [&str; 6] = [
    "choice",
    "record_version",
    "recorded_at_ms",
    "rule_id",
    "rule_version",
    "session_id",
];
const MAX_RECORDED_AT_MS: u64 = 9_223_372_036_854_775_807;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FollowupChoice {
    WorseToday,
    Same,
    Settled,
}

impl FollowupChoice {
    fn parse(token: &str) -> Option<Self> {
        Some(match token {
            "worse_today" => Self::WorseToday,
            "same" => Self::Same,
            "settled" => Self::Settled,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MatchRow {
    choice: FollowupChoice,
    action: &'static str,
    reason: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FlareRule {
    matches: [MatchRow; 3],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FollowupDocument {
    pub recorded_at_ms: u64,
    pub session_id: String,
    pub choice: FollowupChoice,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlareDecision {
    Ready(String),
    Withheld(&'static str),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FlareError {
    Invalid,
    ProgramRejected,
    WorkoutRejected,
}

/// Accept the committed match table. Any other shape is [`ContentError::InvalidDocument`].
pub fn parse_flare_rule(text: &str) -> Result<FlareRule, ContentError> {
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
        (FollowupChoice::WorseToday, "pause_today", PAUSE_REASON),
        (FollowupChoice::Same, "keep_program", KEEP_REASON),
        (FollowupChoice::Settled, "keep_program", KEEP_REASON),
    ];
    let mut matches = [MatchRow {
        choice: FollowupChoice::WorseToday,
        action: "pause_today",
        reason: PAUSE_REASON,
    }; 3];
    for (index, row) in rows.iter().enumerate() {
        let Some(row) = row.as_object() else {
            return Err(ContentError::InvalidDocument);
        };
        if row.len() != MATCH_KEYS.len() || MATCH_KEYS.iter().any(|key| !row.contains_key(*key)) {
            return Err(ContentError::InvalidDocument);
        }
        let Some(choice) = row
            .get("choice")
            .and_then(Value::as_str)
            .and_then(FollowupChoice::parse)
        else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(action) = row.get("action").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(reason) = row.get("reason").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let (expected_choice, expected_action, expected_reason) = expected[index];
        if choice != expected_choice || action != expected_action || reason != expected_reason {
            return Err(ContentError::InvalidDocument);
        }
        matches[index] = MatchRow {
            choice,
            action: expected_action,
            reason: expected_reason,
        };
    }
    Ok(FlareRule { matches })
}

/// Accept the follow-up document in spec §3.2. Extra keys and an out-of-range clock fail.
pub fn parse_followup(text: &str) -> Result<FollowupDocument, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.len() != FOLLOWUP_KEYS.len()
        || FOLLOWUP_KEYS.iter().any(|key| !object.contains_key(*key))
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
    let Some(choice) = object
        .get("choice")
        .and_then(Value::as_str)
        .and_then(FollowupChoice::parse)
    else {
        return Err(ContentError::InvalidDocument);
    };
    Ok(FollowupDocument {
        recorded_at_ms,
        session_id: session_id.to_owned(),
        choice,
    })
}

/// Match the follow-up choice and copy the program doses. Pain is copied and does not select the action.
pub fn decide_flare(
    workout_json: &str,
    program_json: &str,
    followup_json: &str,
    rule_json: &str,
    library: &[Exercise],
    eligible_ids: &[&str],
    permits_progression: bool,
) -> Result<FlareDecision, FlareError> {
    if program_json.is_empty() {
        return Ok(FlareDecision::Withheld("no_program"));
    }
    if workout_json.is_empty() {
        return Ok(FlareDecision::Withheld("no_terminal_workout"));
    }
    if followup_json.is_empty() {
        return Ok(FlareDecision::Withheld("followup_unusable"));
    }
    let rule = parse_flare_rule(rule_json).map_err(|_| FlareError::Invalid)?;
    let followup = parse_followup(followup_json).map_err(|_| FlareError::Invalid)?;
    let program = open_session(program_json, library, 0, "flare-probe")
        .map_err(|_| FlareError::ProgramRejected)?;
    let workout = parse_session(workout_json, library).map_err(|_| FlareError::WorkoutRejected)?;
    if workout.session_id != followup.session_id {
        return Err(FlareError::Invalid);
    }
    match workout.outcome.as_deref() {
        Some("safety_stopped") => {
            return Ok(FlareDecision::Withheld("safety_stopped"));
        }
        Some("completed" | "abandoned") => {}
        _ => return Err(FlareError::Invalid),
    }
    if !permits_progression {
        return Ok(FlareDecision::Withheld("progression_denied"));
    }
    for exercise in &program.exercises {
        if exercise.exercise_id.is_empty()
            || !eligible_ids
                .iter()
                .any(|candidate| *candidate == exercise.exercise_id)
        {
            return Ok(FlareDecision::Withheld("exercise_denied"));
        }
    }
    let Some(matched) = rule
        .matches
        .iter()
        .find(|row| row.choice == followup.choice)
    else {
        return Err(FlareError::Invalid);
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
    let document = serde_json::to_string(&Value::Object(root)).map_err(|_| FlareError::Invalid)?;
    Ok(FlareDecision::Ready(document))
}

/// One stored envelope. Key order is alphabetical.
pub fn flare_followup_envelope(
    followup_json: &str,
    decision_json: &str,
) -> Result<String, ContentError> {
    let followup: Value =
        serde_json::from_str(followup_json).map_err(|_| ContentError::InvalidDocument)?;
    let decision: Value =
        serde_json::from_str(decision_json).map_err(|_| ContentError::InvalidDocument)?;
    if !followup.is_object() || !decision.is_object() {
        return Err(ContentError::InvalidDocument);
    }
    let mut root = Map::new();
    root.insert("decision".to_owned(), decision);
    root.insert("followup".to_owned(), followup);
    root.insert(
        "record_version".to_owned(),
        Value::Number(Number::from_u128(1).ok_or(ContentError::InvalidDocument)?),
    );
    serde_json::to_string(&Value::Object(root)).map_err(|_| ContentError::InvalidDocument)
}

fn copied_exercise(
    exercise_id: &str,
    sets: u32,
    reps: u32,
    tempo: Tempo,
) -> Result<Value, FlareError> {
    if exercise_id.is_empty() {
        return Err(FlareError::Invalid);
    }
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

fn json_number(value: u64) -> Result<Number, FlareError> {
    Number::from_u128(u128::from(value)).ok_or(FlareError::Invalid)
}

fn exact_i64(value: Option<&Value>, expected: i64) -> bool {
    value.and_then(Value::as_i64) == Some(expected)
}
