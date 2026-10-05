//! Synthetic follow-up. Doses stay on the fixture. This is not a clinical flare rule.

use serde_json::Value;

use helpmemove_content::{
    ContentError, Exercise, FlareDecision, FlareError, Session, apply_session_event, decide_flare,
    open_session, parse_exercise, parse_flare_rule, parse_followup, read_session_event,
    render_session,
};

const RULE: &str = include_str!("../../../content/flares/syn-flare-core.json");
const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";
const PAUSE_REASON: &str = "Today's check says to wait. The exercises stay the same.";
const KEEP_REASON: &str = "Today's check keeps the same exercises.";

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

fn followup(choice: &str, session_id: &str) -> String {
    format!(
        r#"{{"choice":"{choice}","record_version":1,"recorded_at_ms":1000,"rule_id":"syn-flare-core","rule_version":1,"session_id":"{session_id}"}}"#
    )
}

fn decide(
    workout: &str,
    program: &str,
    follow: &str,
    eligible: bool,
) -> Result<FlareDecision, FlareError> {
    let ids: Vec<&str> = if eligible {
        vec!["syn-shoulder-isometric"]
    } else {
        Vec::new()
    };
    decide_flare(workout, program, follow, RULE, &fixtures(), &ids, true)
}

fn document(decision: FlareDecision) -> Value {
    let FlareDecision::Ready(text) = decision else {
        panic!("withheld");
    };
    serde_json::from_str(&text).expect("json")
}

#[test]
fn committed_rule_parses() {
    let rule = parse_flare_rule(RULE).expect("rule");
    let again = parse_flare_rule(
        &std::fs::read_to_string(format!(
            "{}/../../content/flares/syn-flare-core.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .expect("read"),
    )
    .expect("file");
    assert_eq!(rule, again);
}

#[test]
fn worse_pauses_and_same_or_settled_keeps_the_program() {
    let session = completed_session(4);
    let workout = render_session(&session).expect("render");
    let worse = document(
        decide(
            &workout,
            PROGRAM,
            &followup("worse_today", SESSION_ID),
            true,
        )
        .expect("worse"),
    );
    assert_eq!(worse["action"], "pause_today");
    assert_eq!(worse["reason"], PAUSE_REASON);
    let same =
        document(decide(&workout, PROGRAM, &followup("same", SESSION_ID), true).expect("same"));
    assert_eq!(same["action"], "keep_program");
    assert_eq!(same["reason"], KEEP_REASON);
    let settled = document(
        decide(&workout, PROGRAM, &followup("settled", SESSION_ID), true).expect("settled"),
    );
    assert_eq!(settled["action"], "keep_program");
    assert_eq!(settled["reason"], KEEP_REASON);
}

#[test]
fn pain_ten_with_settled_stays_keep_program_and_copies_fixture_doses() {
    let session = completed_session(10);
    assert_eq!(session.reported_pain, Some(10));
    let workout = render_session(&session).expect("render");
    let value =
        document(decide(&workout, PROGRAM, &followup("settled", SESSION_ID), true).expect("ready"));
    assert_eq!(value["action"], "keep_program");
    assert_eq!(value["reason"], KEEP_REASON);
    assert_eq!(value["reported_pain"], 10);
    assert_eq!(value["session_id"], SESSION_ID);
    assert_eq!(value["rule_id"], "syn-flare-core");
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
}

#[test]
fn safety_stopped_withholds_before_progression_and_a_bad_dose_is_rejected() {
    let session = completed_session(4);
    let workout = render_session(&session).expect("render");
    let stopped = workout
        .replace(
            "\"outcome\":\"completed\"",
            "\"outcome\":\"safety_stopped\"",
        )
        .replace("\"state\":\"completed\"", "\"state\":\"safety_stopped\"");
    assert_eq!(
        decide_flare(
            &stopped,
            PROGRAM,
            &followup("settled", SESSION_ID),
            RULE,
            &fixtures(),
            &["syn-shoulder-isometric"],
            false,
        )
        .expect("stopped"),
        FlareDecision::Withheld("safety_stopped")
    );
    let mismatched = PROGRAM.replace("\"sets\":1", "\"sets\":2");
    assert_eq!(
        decide(&workout, &mismatched, &followup("same", SESSION_ID), true).expect_err("dose"),
        FlareError::ProgramRejected
    );
}

#[test]
fn extra_key_and_overflow_clock_are_invalid() {
    let extra = r#"{"choice":"same","record_version":1,"recorded_at_ms":1000,"rule_id":"syn-flare-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111","extra":1}"#;
    assert_eq!(
        parse_followup(extra).expect_err("extra"),
        ContentError::InvalidDocument
    );
    let overflow = r#"{"choice":"same","record_version":1,"recorded_at_ms":9223372036854775808,"rule_id":"syn-flare-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111"}"#;
    assert_eq!(
        parse_followup(overflow).expect_err("clock"),
        ContentError::InvalidDocument
    );
    let bound = r#"{"choice":"settled","record_version":1,"recorded_at_ms":9223372036854775807,"rule_id":"syn-flare-core","rule_version":1,"session_id":"11111111-1111-4111-8111-111111111111"}"#;
    assert_eq!(
        parse_followup(bound).expect("bound").recorded_at_ms,
        9_223_372_036_854_775_807
    );
}

#[test]
fn progression_and_missing_eligible_id_withhold() {
    let session = completed_session(0);
    let workout = render_session(&session).expect("render");
    let follow = followup("same", SESSION_ID);
    assert_eq!(
        decide_flare(
            &workout,
            PROGRAM,
            &follow,
            RULE,
            &fixtures(),
            &["syn-shoulder-isometric"],
            false,
        )
        .expect("progression"),
        FlareDecision::Withheld("progression_denied")
    );
    assert_eq!(
        decide(&workout, PROGRAM, &follow, false).expect("eligible"),
        FlareDecision::Withheld("exercise_denied")
    );
}

#[test]
fn empty_documents_withhold_in_order() {
    let follow = followup("same", SESSION_ID);
    assert_eq!(
        decide_flare("session", "", &follow, RULE, &[], &[], true).expect("program"),
        FlareDecision::Withheld("no_program")
    );
    assert_eq!(
        decide_flare("", PROGRAM, &follow, RULE, &fixtures(), &[], true).expect("workout"),
        FlareDecision::Withheld("no_terminal_workout")
    );
    assert_eq!(
        decide_flare("session", PROGRAM, "", RULE, &fixtures(), &[], true).expect("follow"),
        FlareDecision::Withheld("followup_unusable")
    );
}
