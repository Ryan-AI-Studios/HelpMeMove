use helpmemove_content::{
    AssessedArea, ContentError, Equipment, Goal, MovementRating, ProgramIntake, ProgramRule,
    Region, StartingExercise, Tempo, parse_program_rule, read_program_assessment,
    read_program_intake, render_starting_program,
};

const COMMITTED: &str = include_str!("../../../content/programs/syn-program-core.json");

#[test]
fn committed_program_rule_parses() {
    let rule = parse_program_rule(COMMITTED).expect("committed rule");
    assert_eq!(
        rule,
        ProgramRule {
            rule_id: "syn-program-core",
            rule_version: 1,
            session_minutes: 15,
            max_exercises: 4,
        }
    );
}

#[test]
fn extra_key_is_invalid_document_without_the_key() {
    let text = r#"{"rule_id":"syn-program-core","rule_version":1,"session_minutes":15,"max_exercises":4,"clinical":true}"#;
    let error = parse_program_rule(text).expect_err("extra key");
    assert_eq!(error, ContentError::InvalidDocument);
    assert_eq!(error.to_string(), "invalid-document");
    assert!(!error.to_string().contains("clinical"));
    assert!(!error.to_string().contains("syn-program-core"));
    assert!(!error.to_string().contains('{'));
}

#[test]
fn malformed_wrong_cap_and_wrong_minutes_stay_invalid_document() {
    let malformed = parse_program_rule("{").expect_err("brace");
    assert_eq!(malformed, ContentError::InvalidDocument);
    assert!(!malformed.to_string().contains('{'));

    let wrong_cap =
        r#"{"rule_id":"syn-program-core","rule_version":1,"session_minutes":15,"max_exercises":5}"#;
    let cap_error = parse_program_rule(wrong_cap).expect_err("cap");
    assert_eq!(cap_error, ContentError::InvalidDocument);
    assert!(!cap_error.to_string().contains('5'));

    let wrong_minutes =
        r#"{"rule_id":"syn-program-core","rule_version":1,"session_minutes":45,"max_exercises":4}"#;
    assert_eq!(
        parse_program_rule(wrong_minutes).expect_err("minutes"),
        ContentError::InvalidDocument
    );
}

#[test]
fn intake_reader_keeps_filters_and_ignores_the_note() {
    let text = r#"{"draft_version":1,"intent":"fitness","notice_id":"syn-notice-1","schema_ack":"yes","goals":["control"],"equipment":["bodyweight","resistance_band"],"areas":[{"region":"shoulder","laterality":"left","severity":9}],"note":"quiet note","severity":7,"step":"check"}"#;
    let intake = read_program_intake(text).expect("intake");
    assert_eq!(
        intake,
        ProgramIntake {
            goals: vec![Goal::Control],
            equipment: vec![Equipment::Bodyweight, Equipment::ResistanceBand],
            regions: vec![Region::Shoulder],
        }
    );
    let missing_side = r#"{"goals":["control"],"equipment":["chair"],"areas":[{"region":"leg"}]}"#;
    let leg = read_program_intake(missing_side).expect("no laterality");
    assert_eq!(leg.regions, vec![Region::Leg]);
}

#[test]
fn intake_reader_rejects_empty_lists_and_unknown_tokens() {
    let empty_goals = r#"{"goals":[],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}]}"#;
    assert_eq!(
        read_program_intake(empty_goals).expect_err("goals"),
        ContentError::InvalidDocument
    );
    let elbow = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"elbow"}]}"#;
    let error = read_program_intake(elbow).expect_err("region");
    assert_eq!(error, ContentError::InvalidDocument);
    assert!(!error.to_string().contains("elbow"));
    let bad_side = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder","laterality":"both"}]}"#;
    let side = read_program_intake(bad_side).expect_err("laterality");
    assert_eq!(side, ContentError::InvalidDocument);
    assert!(!side.to_string().contains("both"));
}

#[test]
fn assessment_reader_requires_a_finished_check() {
    let text = r#"{"record_version":1,"instrument_id":"syn-assessment-core","stopped":false,"complete":true,"areas":[{"region":"shoulder","laterality":"left","rating":"unable"}],"note":"ignored"}"#;
    let areas = read_program_assessment(text).expect("assessment");
    assert_eq!(
        areas,
        vec![AssessedArea {
            region: Region::Shoulder,
            rating: MovementRating::Unable,
        }]
    );
    let stopped =
        r#"{"stopped":true,"complete":true,"areas":[{"region":"shoulder","rating":"limited"}]}"#;
    assert_eq!(
        read_program_assessment(stopped).expect_err("stopped"),
        ContentError::InvalidDocument
    );
    let missing_rating = r#"{"stopped":false,"complete":true,"areas":[{"region":"shoulder"}]}"#;
    assert_eq!(
        read_program_assessment(missing_rating).expect_err("rating"),
        ContentError::InvalidDocument
    );
    let null_rating =
        r#"{"stopped":false,"complete":true,"areas":[{"region":"shoulder","rating":null}]}"#;
    let error = read_program_assessment(null_rating).expect_err("null");
    assert_eq!(error, ContentError::InvalidDocument);
    assert!(!error.to_string().contains("null"));
}

#[test]
fn render_writes_fixture_counts_and_five_reason_codes() {
    let rule = parse_program_rule(COMMITTED).expect("rule");
    let document = render_starting_program(
        &rule,
        &[StartingExercise {
            exercise_id: "syn-shoulder-isometric".to_owned(),
            regions: vec![Region::Shoulder],
            sets: 1,
            reps: 1,
            tempo: Tempo {
                eccentric: 2,
                pause: 1,
                concentric: 2,
            },
            region: Region::Shoulder,
            equipment: Equipment::Bodyweight,
            goal: Goal::Control,
        }],
    )
    .expect("render");
    assert!(document.contains("\"exercise_version\":1"));
    assert!(document.contains("\"sets\":1"));
    assert!(document.contains("\"reps\":1"));
    assert!(document.contains("\"session_minutes\":15"));
    let mut last = 0;
    for code in [
        "region_match",
        "equipment_match",
        "goal_match",
        "screen_clear",
        "fixture_defaults",
    ] {
        let found = document[last..].find(code).expect(code);
        last += found + code.len();
    }
    assert!(!document.contains("unable"));
    assert!(!document.contains("prescription"));
}
