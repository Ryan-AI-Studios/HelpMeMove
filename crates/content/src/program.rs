//! Synthetic starting-plan fixture. Not a clinician-approved protocol.

use serde_json::{Map, Number, Value};

use helpmemove_domain::Laterality;

use super::ContentError;
use super::assessment::MovementRating;
use super::model::{Equipment, Goal, Region, Tempo};

const RULE_ID: &str = "syn-program-core";
const SAFETY_RULE_ID: &str = "syn-safety-core";
const RULE_KEYS: [&str; 4] = [
    "max_exercises",
    "rule_id",
    "rule_version",
    "session_minutes",
];

/// Parsed `syn-program-core` fixture. `session_minutes` is display-only.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProgramRule {
    pub rule_id: &'static str,
    pub rule_version: u32,
    pub session_minutes: u32,
    pub max_exercises: u32,
}

/// Intake fields the selector reads. The note and severity are not stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgramIntake {
    pub goals: Vec<Goal>,
    pub equipment: Vec<Equipment>,
    pub regions: Vec<Region>,
}

/// One assessed region and its saved rating. The rating is not a dose.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AssessedArea {
    pub region: Region,
    pub rating: MovementRating,
}

/// One included exercise before it is rendered. Counts are fixture defaults.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StartingExercise {
    pub exercise_id: String,
    pub regions: Vec<Region>,
    pub sets: u8,
    pub reps: u8,
    pub tempo: Tempo,
    pub region: Region,
    pub equipment: Equipment,
    pub goal: Goal,
}

/// Accept only the committed id, version 1, 15 minutes, and a cap of 4.
///
/// Any other shape is [`ContentError::InvalidDocument`]. The error does not include the document.
pub fn parse_program_rule(text: &str) -> Result<ProgramRule, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.len() != RULE_KEYS.len() || RULE_KEYS.iter().any(|key| !object.contains_key(*key)) {
        return Err(ContentError::InvalidDocument);
    }
    let Some(rule_id) = object.get("rule_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidDocument);
    };
    if rule_id != RULE_ID
        || !exact_i64(object.get("rule_version"), 1)
        || !exact_i64(object.get("session_minutes"), 15)
        || !exact_i64(object.get("max_exercises"), 4)
    {
        return Err(ContentError::InvalidDocument);
    }
    Ok(ProgramRule {
        rule_id: RULE_ID,
        rule_version: 1,
        session_minutes: 15,
        max_exercises: 4,
    })
}

/// Read goals, equipment, and regions. Extra keys are ignored. Laterality is checked and unused.
pub fn read_program_intake(text: &str) -> Result<ProgramIntake, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    let goals = parse_tokens(object.get("goals"), Goal::parse)?;
    let equipment = parse_tokens(object.get("equipment"), Equipment::parse)?;
    let Some(areas) = object.get("areas").and_then(Value::as_array) else {
        return Err(ContentError::InvalidDocument);
    };
    if areas.is_empty() {
        return Err(ContentError::InvalidDocument);
    }
    let mut regions = Vec::with_capacity(areas.len());
    for area in areas {
        let Some(area) = area.as_object() else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(token) = area.get("region").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(region) = Region::parse(token) else {
            return Err(ContentError::InvalidDocument);
        };
        if let Some(laterality) = area.get("laterality") {
            let Some(token) = laterality.as_str() else {
                return Err(ContentError::InvalidDocument);
            };
            if Laterality::parse(token).is_err() {
                return Err(ContentError::InvalidDocument);
            }
        }
        regions.push(region);
    }
    Ok(ProgramIntake {
        goals,
        equipment,
        regions,
    })
}

/// Read a finished check. `stopped`, an incomplete flag, or a null rating rejects the document.
pub fn read_program_assessment(text: &str) -> Result<Vec<AssessedArea>, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.get("stopped").and_then(Value::as_bool) != Some(false)
        || object.get("complete").and_then(Value::as_bool) != Some(true)
    {
        return Err(ContentError::InvalidDocument);
    }
    let Some(areas) = object.get("areas").and_then(Value::as_array) else {
        return Err(ContentError::InvalidDocument);
    };
    if areas.is_empty() {
        return Err(ContentError::InvalidDocument);
    }
    let mut assessed = Vec::with_capacity(areas.len());
    for area in areas {
        let Some(area) = area.as_object() else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(token) = area.get("region").and_then(Value::as_str) else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(region) = Region::parse(token) else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(rating_value) = area.get("rating") else {
            return Err(ContentError::InvalidDocument);
        };
        if rating_value.is_null() {
            return Err(ContentError::InvalidDocument);
        }
        let Some(rating_token) = rating_value.as_str() else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(rating) = MovementRating::parse(rating_token) else {
            return Err(ContentError::InvalidDocument);
        };
        assessed.push(AssessedArea { region, rating });
    }
    Ok(assessed)
}

/// Render the stored plan. Reason text is the five closed codes, not a sentence.
pub fn render_starting_program(
    rule: &ProgramRule,
    exercises: &[StartingExercise],
) -> Result<String, ContentError> {
    let rendered = exercises.iter().map(exercise_value).collect();
    let mut root = Map::new();
    root.insert("record_version".to_owned(), json_u32(1));
    root.insert("rule_id".to_owned(), json_str(RULE_ID));
    root.insert("rule_version".to_owned(), json_u32(1));
    root.insert("safety_rule_id".to_owned(), json_str(SAFETY_RULE_ID));
    root.insert("safety_rule_version".to_owned(), json_u32(1));
    root.insert("session_minutes".to_owned(), json_u32(rule.session_minutes));
    root.insert("exercises".to_owned(), Value::Array(rendered));
    serde_json::to_string(&Value::Object(root)).map_err(|_| ContentError::InvalidDocument)
}

fn exercise_value(exercise: &StartingExercise) -> Value {
    let reasons = vec![
        reason_value("region_match", Some(exercise.region.as_str()), None, None),
        reason_value(
            "equipment_match",
            None,
            Some(exercise.equipment.as_str()),
            None,
        ),
        reason_value("goal_match", None, None, Some(exercise.goal.as_str())),
        reason_value("screen_clear", None, None, None),
        reason_value("fixture_defaults", None, None, None),
    ];
    let regions = exercise
        .regions
        .iter()
        .map(|region| json_str(region.as_str()))
        .collect();
    let mut tempo = Map::new();
    tempo.insert(
        "eccentric".to_owned(),
        json_u32(u32::from(exercise.tempo.eccentric)),
    );
    tempo.insert(
        "pause".to_owned(),
        json_u32(u32::from(exercise.tempo.pause)),
    );
    tempo.insert(
        "concentric".to_owned(),
        json_u32(u32::from(exercise.tempo.concentric)),
    );
    let mut object = Map::new();
    object.insert("exercise_id".to_owned(), json_str(&exercise.exercise_id));
    // Parsed exercises are version 1. The record repeats that fixed version.
    object.insert("exercise_version".to_owned(), json_u32(1));
    object.insert("regions".to_owned(), Value::Array(regions));
    object.insert("sets".to_owned(), json_u32(u32::from(exercise.sets)));
    object.insert("reps".to_owned(), json_u32(u32::from(exercise.reps)));
    object.insert("tempo".to_owned(), Value::Object(tempo));
    object.insert("reasons".to_owned(), Value::Array(reasons));
    Value::Object(object)
}

fn reason_value(
    code: &str,
    region: Option<&str>,
    equipment: Option<&str>,
    goal: Option<&str>,
) -> Value {
    let mut object = Map::new();
    object.insert("code".to_owned(), json_str(code));
    object.insert("region".to_owned(), optional_str(region));
    object.insert("equipment".to_owned(), optional_str(equipment));
    object.insert("goal".to_owned(), optional_str(goal));
    Value::Object(object)
}

fn parse_tokens<T>(
    value: Option<&Value>,
    parse: fn(&str) -> Option<T>,
) -> Result<Vec<T>, ContentError> {
    let Some(items) = value.and_then(Value::as_array) else {
        return Err(ContentError::InvalidDocument);
    };
    if items.is_empty() {
        return Err(ContentError::InvalidDocument);
    }
    let mut parsed = Vec::with_capacity(items.len());
    for item in items {
        let Some(token) = item.as_str() else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(value) = parse(token) else {
            return Err(ContentError::InvalidDocument);
        };
        parsed.push(value);
    }
    Ok(parsed)
}

fn exact_i64(value: Option<&Value>, expected: i64) -> bool {
    value.and_then(Value::as_i64) == Some(expected)
}

fn json_u32(value: u32) -> Value {
    Value::Number(Number::from(value))
}

fn json_str(value: &str) -> Value {
    Value::String(value.to_owned())
}

fn optional_str(value: Option<&str>) -> Value {
    match value {
        Some(value) => json_str(value),
        None => Value::Null,
    }
}
