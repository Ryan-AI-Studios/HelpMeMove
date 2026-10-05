//! Bridge entry for stored-session counts. An empty list is ready.

use helpmemove_bridge::api::bridge::{apply_workout_event, open_workout, prepare_progress_summary};

const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";

fn advance(document: &str, event: &str, now: i64) -> String {
    let view = apply_workout_event(document.to_owned(), event.to_owned(), now);
    assert_eq!(view.outcome, "ready", "{}", view.error_code);
    view.document_json
}

fn completed_workout() -> String {
    let opened = open_workout(PROGRAM.to_owned(), 1000, SESSION_ID.to_owned());
    assert_eq!(opened.outcome, "ready", "{}", opened.error_code);
    let demonstrating = advance(&opened.document_json, r#"{"name":"ready"}"#, 1000);
    let active = advance(&demonstrating, r#"{"name":"ready"}"#, 1100);
    let checking = advance(
        &active,
        r#"{"name":"report_pain","reported_pain":4,"symptom":"mild_discomfort"}"#,
        1100,
    );
    let paused = advance(&checking, r#"{"name":"continue_after_pain"}"#, 1100);
    let resumed = advance(&paused, r#"{"name":"resume"}"#, 1200);
    advance(&resumed, r#"{"name":"complete_rep"}"#, 1200)
}

fn json_string(value: &str) -> String {
    let mut encoded = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => encoded.push_str("\\\""),
            '\\' => encoded.push_str("\\\\"),
            '\n' => encoded.push_str("\\n"),
            '\r' => encoded.push_str("\\r"),
            other => encoded.push(other),
        }
    }
    encoded.push('"');
    encoded
}

fn one_entry(session_id: &str, document: &str, updated_at_ms: i64) -> String {
    format!(
        r#"[{{"document_json":{document},"session_id":{session_id},"updated_at_ms":{updated_at_ms}}}]"#,
        document = json_string(document),
        session_id = json_string(session_id),
    )
}

#[test]
fn an_empty_list_is_ready_and_an_empty_string_is_withheld() {
    let empty = prepare_progress_summary("[]".to_owned());
    assert_eq!(empty.outcome, "ready");
    assert_eq!(empty.withhold_code, "");
    assert_eq!(
        empty.document_json,
        r#"{"abandoned_count":0,"completed_count":0,"copied_pain":null,"record_version":1,"rule_id":"syn-progress-core","rule_version":1,"safety_stopped_count":0}"#
    );

    let missing = prepare_progress_summary(String::new());
    assert_eq!(missing.outcome, "withheld");
    assert_eq!(missing.withhold_code, "workout_unusable");
    assert_eq!(missing.document_json, "");
}

#[test]
fn a_stored_completion_is_counted_without_a_dose() {
    let document = completed_workout();
    let view = prepare_progress_summary(one_entry(SESSION_ID, &document, 40));
    assert_eq!(view.outcome, "ready");
    assert_eq!(view.withhold_code, "");
    assert!(view.document_json.contains(r#""completed_count":1"#));
    assert!(view.document_json.contains(r#""copied_pain":4"#));
    assert!(
        view.document_json
            .contains(r#""rule_id":"syn-progress-core""#)
    );
    assert!(!view.document_json.contains("syn-shoulder"));
    assert!(!view.document_json.contains("sets"));
}

#[test]
fn an_unreadable_entry_withholds_the_summary() {
    let view = prepare_progress_summary(one_entry(SESSION_ID, "{}", 1));
    assert_eq!(view.outcome, "withheld");
    assert_eq!(view.withhold_code, "workout_unusable");
    assert_eq!(view.document_json, "");
}
