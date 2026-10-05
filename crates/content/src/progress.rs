//! Synthetic counts of stored sessions. The document is not a clinical milestone.

use std::collections::HashSet;

use serde_json::{Map, Number, Value};

use super::model::Exercise;
use super::session::parse_session;

const RULE_ID: &str = "syn-progress-core";
const ENTRY_KEYS: [&str; 3] = ["document_json", "session_id", "updated_at_ms"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgressError {
    Invalid,
    LibraryRejected,
}

struct Entry {
    document_json: String,
    session_id: String,
    updated_at_ms: i64,
}

struct Newest {
    session_id: String,
    updated_at_ms: i64,
    reported_pain: Option<u8>,
}

/// Count terminal sessions already stored on this device.
///
/// `library` is the caller-supplied fixture list. An empty list is rejected
/// before the entry text is read. This function does not open a session,
/// screen an exercise, or classify intake.
pub fn summarize_progress(
    entries_json: &str,
    library: &[Exercise],
) -> Result<String, ProgressError> {
    if library.is_empty() {
        return Err(ProgressError::LibraryRejected);
    }
    let value: Value = serde_json::from_str(entries_json).map_err(|_| ProgressError::Invalid)?;
    let Some(entries) = value.as_array() else {
        return Err(ProgressError::Invalid);
    };
    let mut rows = Vec::with_capacity(entries.len());
    let mut seen = HashSet::with_capacity(entries.len());
    for entry in entries {
        rows.push(read_entry(entry, &mut seen)?);
    }

    let mut completed_count: i32 = 0;
    let mut abandoned_count: i32 = 0;
    let mut safety_stopped_count: i32 = 0;
    let mut newest: Option<Newest> = None;
    for row in &rows {
        let session =
            parse_session(&row.document_json, library).map_err(|_| ProgressError::Invalid)?;
        if session.session_id != row.session_id {
            return Err(ProgressError::Invalid);
        }
        let Some(outcome) = session.outcome.as_deref() else {
            continue;
        };
        match outcome {
            "completed" => {
                completed_count = completed_count
                    .checked_add(1)
                    .ok_or(ProgressError::Invalid)?;
            }
            "abandoned" => {
                abandoned_count = abandoned_count
                    .checked_add(1)
                    .ok_or(ProgressError::Invalid)?;
            }
            "safety_stopped" => {
                safety_stopped_count = safety_stopped_count
                    .checked_add(1)
                    .ok_or(ProgressError::Invalid)?;
            }
            _ => return Err(ProgressError::Invalid),
        }
        if session.reported_pain.is_some_and(|value| value > 10) {
            return Err(ProgressError::Invalid);
        }
        let replace = match &newest {
            None => true,
            Some(current) => {
                row.updated_at_ms > current.updated_at_ms
                    || (row.updated_at_ms == current.updated_at_ms
                        && row.session_id.as_bytes() > current.session_id.as_bytes())
            }
        };
        if replace {
            newest = Some(Newest {
                session_id: row.session_id.clone(),
                updated_at_ms: row.updated_at_ms,
                reported_pain: session.reported_pain,
            });
        }
    }

    let copied_pain = match newest.as_ref().and_then(|item| item.reported_pain) {
        Some(value) => Value::Number(Number::from(value)),
        None => Value::Null,
    };
    let mut root = Map::new();
    root.insert(
        "abandoned_count".to_owned(),
        Value::Number(Number::from(abandoned_count)),
    );
    root.insert(
        "completed_count".to_owned(),
        Value::Number(Number::from(completed_count)),
    );
    root.insert("copied_pain".to_owned(), copied_pain);
    root.insert(
        "record_version".to_owned(),
        Value::Number(Number::from(1_i32)),
    );
    root.insert("rule_id".to_owned(), Value::String(RULE_ID.to_owned()));
    root.insert(
        "rule_version".to_owned(),
        Value::Number(Number::from(1_i32)),
    );
    root.insert(
        "safety_stopped_count".to_owned(),
        Value::Number(Number::from(safety_stopped_count)),
    );
    serde_json::to_string(&Value::Object(root)).map_err(|_| ProgressError::Invalid)
}

fn read_entry(entry: &Value, seen: &mut HashSet<String>) -> Result<Entry, ProgressError> {
    let Some(object) = entry.as_object() else {
        return Err(ProgressError::Invalid);
    };
    if object.len() != ENTRY_KEYS.len() || ENTRY_KEYS.iter().any(|key| !object.contains_key(*key)) {
        return Err(ProgressError::Invalid);
    }
    let Some(document_json) = object.get("document_json").and_then(Value::as_str) else {
        return Err(ProgressError::Invalid);
    };
    let Some(session_id) = object.get("session_id").and_then(Value::as_str) else {
        return Err(ProgressError::Invalid);
    };
    if session_id.is_empty() {
        return Err(ProgressError::Invalid);
    }
    let Some(updated_at_ms) = object.get("updated_at_ms").and_then(Value::as_i64) else {
        return Err(ProgressError::Invalid);
    };
    if updated_at_ms < 0 {
        return Err(ProgressError::Invalid);
    }
    if !seen.insert(session_id.to_owned()) {
        return Err(ProgressError::Invalid);
    }
    Ok(Entry {
        document_json: document_json.to_owned(),
        session_id: session_id.to_owned(),
        updated_at_ms,
    })
}
