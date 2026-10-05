//! Synthetic next-session check. Doses stay on the fixture. This is not a clinical rule.

use serde_json::Value;

use helpmemove_content::{
    AdaptationDecision, AdaptationError, ContentError, Exercise, Session, apply_session_event,
    decide_adaptation, open_session, parse_adaptation_rule, parse_exercise, parse_readiness,
    read_intake_safety_answers, read_session_event, render_session,
};

const RULE: &str = include_str!("../../../content/adaptations/syn-adaptation-core.json");
const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";
const HIGH_REASON: &str = "Today's check says to wait. The exercises stay the same.";
const MAINTAIN_REASON: &str = "Today's check keeps the same exercises.";

fn fixtures() -> Vec<Exercise> {
    [
        include_str!("../../../content/exercises/syn-knee-sit-to-stand.json"),
        include_str!("../../../content/exercises/syn-shoulder-band.json"),
        include_str!("../../../content/exercises/syn-shoulder-isometric.json"),
        include_str!("../../../content/exercises/syn-torso-pelvic-tilt.json"),
    ]
    .into_iter()
    .map(|text| parse_exercise(text.as_bytes()).expect("fixture"))
    .collect()
}

fn event(text: &str) -> helpmemove_content::SessionEvent {
    read_session_event(text).expect("event")
}

fn completed_session(pain: u8) -> Session {
    let library = fixtures();
    let opened = open_session(PROGRAM, &library, 1000, SESSION_ID).expect("open");
    let demonstrating =
        apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 1000, &[], &library)
            .expect("demo");
    let active = apply_session_event(
        &demonstrating,
        &event(r#"{"name":"ready"}"#),
        1100,
        &[],
        &library,
    )
    .expect("active");
    let pain_event =
        format!(r#"{{"name":"report_pain","reported_pain":{pain},"symptom":"mild_discomfort"}}"#);
    let checking =
        apply_session_event(&active, &event(&pain_event), 1100, &[], &library).expect("pain");
    let paused = apply_session_event(
        &checking,
        &event(r#"{"name":"continue_after_pain"}"#),
        1100,
        &[],
        &library,
    )
    .expect("continue");
    let resumed = apply_session_event(&paused, &event(r#"{"name":"resume"}"#), 1200, &[], &library)
        .expect("resume");
    apply_session_event(
        &resumed,
        &event(r#"{"name":"complete_rep"}"#),
        1200,
        &[],
        &library,
    )
    .expect("complete")
}

fn readiness(soreness: &str, session_id: &str) -> String {
    format!(
        r#"{{"record_version":1,"recorded_at_ms":1000,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"{session_id}","soreness":"{soreness}"}}"#
    )
}

fn decide(
    workout: &str,
    program: &str,
    ready: &str,
    eligible: bool,
) -> Result<AdaptationDecision, AdaptationError> {
    let ids: Vec<&str> = if eligible {
        vec!["syn-shoulder-isometric"]
    } else {
        Vec::new()
    };
    decide_adaptation(workout, program, ready, RULE, &fixtures(), &ids, true)
}

fn document(decision: AdaptationDecision) -> Value {
    let AdaptationDecision::Ready(text) = decision else {
        panic!("withheld");
    };
    serde_json::from_str(&text).expect("json")
}

#[test]
fn committed_rule_parses() {
    let rule = parse_adaptation_rule(RULE).expect("rule");
    let again = parse_adaptation_rule(
        &std::fs::read_to_string(format!(
            "{}/../../content/adaptations/syn-adaptation-core.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .expect("read"),
    )
    .expect("file");
    assert_eq!(rule, again);
}

#[test]
fn high_soreness_pauses_and_low_or_moderate_maintain() {
    let session = completed_session(4);
    let workout = render_session(&session).expect("render");
    let high =
        document(decide(&workout, PROGRAM, &readiness("high", SESSION_ID), true).expect("high"));
    assert_eq!(high["action"], "pause_today");
    assert_eq!(high["reason"], HIGH_REASON);
    let low =
        document(decide(&workout, PROGRAM, &readiness("low", SESSION_ID), true).expect("low"));
    assert_eq!(low["action"], "maintain");
    assert_eq!(low["reason"], MAINTAIN_REASON);
    let moderate = document(
        decide(&workout, PROGRAM, &readiness("moderate", SESSION_ID), true).expect("moderate"),
    );
    assert_eq!(moderate["action"], "maintain");
    assert_eq!(moderate["reason"], MAINTAIN_REASON);
}

#[test]
fn pain_ten_with_low_soreness_stays_maintain_and_copies_fixture_doses() {
    let session = completed_session(10);
    assert_eq!(session.reported_pain, Some(10));
    let workout = render_session(&session).expect("render");
    let value =
        document(decide(&workout, PROGRAM, &readiness("low", SESSION_ID), true).expect("ready"));
    assert_eq!(value["action"], "maintain");
    assert_eq!(value["reason"], MAINTAIN_REASON);
    assert_eq!(value["reported_pain"], 10);
    assert_eq!(value["session_id"], SESSION_ID);
    let exercise = &value["exercises"][0];
    let keys: Vec<&str> = exercise
        .as_object()
        .expect("object")
        .keys()
        .map(String::as_str)
        .collect();
    assert_eq!(keys, ["exercise_id", "reps", "sets", "tempo"]);
    assert_eq!(exercise["exercise_id"], "syn-shoulder-isometric");
    assert_eq!(exercise["sets"], 1);
    assert_eq!(exercise["reps"], 1);
    assert_eq!(exercise["tempo"]["eccentric"], 2);
    assert_eq!(exercise["tempo"]["pause"], 1);
    assert_eq!(exercise["tempo"]["concentric"], 2);
    assert!(exercise.get("exercise_version").is_none());
    assert!(exercise.get("regions").is_none());
    assert!(exercise.get("reasons").is_none());
}

#[test]
fn safety_stopped_withholds_and_a_bad_dose_is_rejected() {
    let session = completed_session(4);
    let workout = render_session(&session).expect("render");
    let stopped = workout
        .replace(
            "\"outcome\":\"completed\"",
            "\"outcome\":\"safety_stopped\"",
        )
        .replace("\"state\":\"completed\"", "\"state\":\"safety_stopped\"");
    assert_eq!(
        decide(&stopped, PROGRAM, &readiness("low", SESSION_ID), true).expect("stopped"),
        AdaptationDecision::Withheld("safety_stopped")
    );
    let mismatched = PROGRAM.replace("\"sets\":1", "\"sets\":2");
    assert_eq!(
        decide(&workout, &mismatched, &readiness("low", SESSION_ID), true).expect_err("dose"),
        AdaptationError::ProgramRejected
    );
}

#[test]
fn extra_key_and_overflow_clock_are_invalid() {
    let extra = r#"{"record_version":1,"recorded_at_ms":1000,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","soreness":"low","extra":1}"#;
    assert_eq!(
        parse_readiness(extra).expect_err("extra"),
        ContentError::InvalidDocument
    );
    let overflow = r#"{"record_version":1,"recorded_at_ms":9223372036854775808,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","soreness":"low"}"#;
    assert_eq!(
        parse_readiness(overflow).expect_err("clock"),
        ContentError::InvalidDocument
    );
    let bound = r#"{"record_version":1,"recorded_at_ms":9223372036854775807,"rule_id":"syn-adaptation-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","soreness":"low"}"#;
    assert_eq!(
        parse_readiness(bound).expect("bound").recorded_at_ms,
        9_223_372_036_854_775_807
    );
}

#[test]
fn progression_and_missing_eligible_id_withhold() {
    let session = completed_session(0);
    let workout = render_session(&session).expect("render");
    let ready = readiness("low", SESSION_ID);
    assert_eq!(
        decide_adaptation(
            &workout,
            PROGRAM,
            &ready,
            RULE,
            &fixtures(),
            &["syn-shoulder-isometric"],
            false,
        )
        .expect("progression"),
        AdaptationDecision::Withheld("progression_denied")
    );
    assert_eq!(
        decide(&workout, PROGRAM, &ready, false).expect("eligible"),
        AdaptationDecision::Withheld("exercise_denied")
    );
}

#[test]
fn intake_answers_keep_schema_ack_then_one_triage_token() {
    let intake = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes","schema_green":"present"}"#;
    assert_eq!(
        read_intake_safety_answers(intake).expect("answers"),
        vec![
            ("schema_ack".to_owned(), "yes".to_owned()),
            ("schema_green".to_owned(), "present".to_owned()),
        ]
    );
    let ack_only = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes"}"#;
    assert_eq!(
        read_intake_safety_answers(ack_only).expect("ack"),
        vec![("schema_ack".to_owned(), "yes".to_owned())]
    );
    let two = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes","schema_green":"present","schema_yellow":"present"}"#;
    assert_eq!(
        read_intake_safety_answers(two).expect_err("two"),
        ContentError::InvalidDocument
    );
    let number = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}],"schema_ack":"yes","schema_green":1}"#;
    assert_eq!(
        read_intake_safety_answers(number).expect_err("number"),
        ContentError::InvalidDocument
    );
}
