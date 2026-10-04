//! Synthetic manual session over a stored program. Not a clinical workout.

use helpmemove_bridge::api::bridge::{apply_workout_event, open_workout};

const GREEN_SHOULDER: &str =
    include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const OPENED: &str = include_str!("../../../apps/mobile/test/workout/opened_shoulder_session.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";

fn ready(document: &str, event: &str, now: i64) -> String {
    let view = apply_workout_event(document.to_owned(), event.to_owned(), now);
    assert_eq!(view.outcome, "ready", "{}", view.error_code);
    assert_eq!(view.error_code, "");
    assert!(!view.document_json.is_empty());
    view.document_json
}

#[test]
fn open_workout_matches_the_golden_shoulder_session() {
    let view = open_workout(GREEN_SHOULDER.to_owned(), 1000, SESSION_ID.to_owned());
    assert_eq!(view.outcome, "ready");
    assert_eq!(view.error_code, "");
    assert_eq!(view.document_json, OPENED);
}

#[test]
fn negative_and_empty_opens_are_invalid_session() {
    let negative = open_workout(GREEN_SHOULDER.to_owned(), -1, SESSION_ID.to_owned());
    assert_eq!(negative.outcome, "unavailable");
    assert_eq!(negative.error_code, "invalid-session");
    assert_eq!(negative.document_json, "");
    let empty = open_workout(GREEN_SHOULDER.to_owned(), 1000, String::new());
    assert_eq!(empty.error_code, "invalid-session");
    assert_eq!(empty.document_json, "");
    assert!(!empty.error_code.contains("syn-"));
}

#[test]
fn production_substitute_is_denied_and_closed_clocks_keep_their_codes() {
    let opened = open_workout(GREEN_SHOULDER.to_owned(), 1000, SESSION_ID.to_owned());
    let demonstrating = ready(&opened.document_json, r#"{"name":"ready"}"#, 1000);
    let active = ready(&demonstrating, r#"{"name":"ready"}"#, 1000);
    let pain = ready(
        &active,
        r#"{"name":"report_pain","reported_pain":10,"symptom":"numbness_tingling"}"#,
        1000,
    );
    assert!(pain.contains("pain_check"));
    assert!(pain.contains("numbness_tingling"));
    let denied = apply_workout_event(
        pain,
        r#"{"name":"select_substitute","exercise_id":"syn-shoulder-band"}"#.to_owned(),
        1000,
    );
    assert_eq!(denied.outcome, "unavailable");
    assert_eq!(denied.error_code, "invalid-session");
    assert_eq!(denied.document_json, "");
    assert!(!denied.error_code.contains("syn-"));
    assert!(!denied.error_code.contains("10"));

    let backwards = apply_workout_event(active.clone(), r#"{"name":"pause"}"#.to_owned(), 999);
    assert_eq!(backwards.error_code, "clock-went-backwards");
    assert_eq!(backwards.document_json, "");

    let done = ready(&active, r#"{"name":"complete_rep"}"#, 1000);
    assert!(done.contains("\"outcome\":\"completed\""));
    let closed = apply_workout_event(done, r#"{"name":"pause"}"#.to_owned(), 1000);
    assert_eq!(closed.error_code, "session-closed");
    assert_eq!(closed.document_json, "");
}
