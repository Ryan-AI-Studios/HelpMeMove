//! Bridge entry for the synthetic next-session check. Production intake withholds.

use helpmemove_bridge::api::bridge::{apply_workout_event, open_workout, prepare_adaptation};

const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";
const MAINTAIN_REASON: &str = "Today's check keeps the same exercises.";
const ASSESSMENT: &str = r#"{"record_version":1,"instrument_id":"syn-assessment-core","stopped":false,"complete":true,"areas":[{"region":"shoulder","laterality":"left","rating":"unable"}],"note":"ignored"}"#;

fn advance(document: &str, event: &str, now: i64) -> String {
    let view = apply_workout_event(document.to_owned(), event.to_owned(), now);
    assert_eq!(view.outcome, "ready", "{}", view.error_code);
    view.document_json
}

fn completed_workout(pain: u8) -> String {
    let opened = open_workout(PROGRAM.to_owned(), 1000, SESSION_ID.to_owned());
    assert_eq!(opened.outcome, "ready", "{}", opened.error_code);
    let demonstrating = advance(&opened.document_json, r#"{"name":"ready"}"#, 1000);
    let active = advance(&demonstrating, r#"{"name":"ready"}"#, 1100);
    let pain_event =
        format!(r#"{{"name":"report_pain","reported_pain":{pain},"symptom":"mild_discomfort"}}"#);
    let checking = advance(&active, &pain_event, 1100);
    let paused = advance(&checking, r#"{"name":"continue_after_pain"}"#, 1100);
    let resumed = advance(&paused, r#"{"name":"resume"}"#, 1200);
    advance(&resumed, r#"{"name":"complete_rep"}"#, 1200)
}

fn readiness(soreness: &str) -> String {
    format!(
        r#"{{"record_version":1,"recorded_at_ms":1000,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"{SESSION_ID}","soreness":"{soreness}"}}"#
    )
}

fn intake(triage: Option<&str>) -> String {
    match triage {
        Some(token) => format!(
            r#"{{"goals":["control"],"equipment":["bodyweight"],"areas":[{{"region":"shoulder"}}],"schema_ack":"yes","{token}":"present"}}"#
        ),
        None => {
            r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes"}"#
                .to_owned()
        }
    }
}

#[test]
fn green_intake_maintains_and_ack_only_withholds() {
    let workout = completed_workout(4);
    let ready = prepare_adaptation(
        intake(Some("schema_green")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout.clone(),
        readiness("low"),
    );
    assert_eq!(ready.outcome, "ready");
    assert_eq!(ready.withhold_code, "");
    assert!(ready.document_json.contains("\"action\":\"maintain\""));
    assert!(ready.document_json.contains(MAINTAIN_REASON));
    assert!(ready.document_json.contains("\"sets\":1"));
    assert!(ready.document_json.contains("\"reps\":1"));

    let withheld = prepare_adaptation(
        intake(None),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout,
        readiness("low"),
    );
    assert_eq!(withheld.outcome, "withheld");
    assert_eq!(withheld.withhold_code, "progression_denied");
    assert!(withheld.document_json.is_empty());
}

#[test]
fn yellow_intake_withholds_exercise_denied_and_empty_readiness_is_unusable() {
    let workout = completed_workout(4);
    let yellow = prepare_adaptation(
        intake(Some("schema_yellow")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout,
        readiness("high"),
    );
    assert_eq!(yellow.outcome, "withheld");
    assert_eq!(yellow.withhold_code, "exercise_denied");
    assert!(yellow.document_json.is_empty());

    let empty = prepare_adaptation(
        intake(Some("schema_green")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        completed_workout(4),
        String::new(),
    );
    assert_eq!(empty.outcome, "withheld");
    assert_eq!(empty.withhold_code, "readiness_unusable");
}
