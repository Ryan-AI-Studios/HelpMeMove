//! Bridge entry for the synthetic follow-up. Production intake withholds.

use helpmemove_bridge::api::bridge::{apply_workout_event, open_workout, prepare_flare_followup};

const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";
const KEEP_REASON: &str = "Today's check keeps the same exercises.";
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

fn followup(choice: &str) -> String {
    format!(
        r#"{{"choice":"{choice}","record_version":1,"recorded_at_ms":1000,"rule_id":"syn-flare-core","rule_version":1,"session_id":"{SESSION_ID}"}}"#
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
fn green_intake_keeps_the_program_and_ack_only_withholds() {
    let workout = completed_workout(4);
    let ready = prepare_flare_followup(
        intake(Some("schema_green")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout.clone(),
        followup("settled"),
    );
    assert_eq!(ready.outcome, "ready");
    assert_eq!(ready.withhold_code, "");
    assert!(ready.document_json.contains("\"action\":\"keep_program\""));
    assert!(ready.document_json.contains(KEEP_REASON));
    assert!(ready.document_json.contains("\"sets\":1"));
    assert!(ready.document_json.contains("\"reps\":1"));
    assert!(ready.document_json.contains("\"choice\":\"settled\""));
    assert!(ready.document_json.contains("\"record_version\":1"));

    let withheld = prepare_flare_followup(
        intake(None),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout,
        followup("same"),
    );
    assert_eq!(withheld.outcome, "withheld");
    assert_eq!(withheld.withhold_code, "progression_denied");
    assert!(withheld.document_json.is_empty());
}

#[test]
fn yellow_withholds_and_empty_inputs_use_their_codes() {
    let workout = completed_workout(4);
    let yellow = prepare_flare_followup(
        intake(Some("schema_yellow")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout.clone(),
        followup("worse_today"),
    );
    assert_eq!(yellow.outcome, "withheld");
    assert_eq!(yellow.withhold_code, "exercise_denied");
    assert!(yellow.document_json.is_empty());

    let orange = prepare_flare_followup(
        intake(Some("schema_orange")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        workout,
        followup("settled"),
    );
    assert_eq!(orange.outcome, "withheld");
    assert_eq!(orange.withhold_code, "progression_denied");

    let assessment = prepare_flare_followup(
        intake(Some("schema_green")),
        String::new(),
        PROGRAM.to_owned(),
        completed_workout(4),
        followup("same"),
    );
    assert_eq!(assessment.outcome, "withheld");
    assert_eq!(assessment.withhold_code, "assessment_incomplete");

    let empty = prepare_flare_followup(
        intake(Some("schema_green")),
        ASSESSMENT.to_owned(),
        PROGRAM.to_owned(),
        completed_workout(4),
        String::new(),
    );
    assert_eq!(empty.outcome, "withheld");
    assert_eq!(empty.withhold_code, "followup_unusable");
}
