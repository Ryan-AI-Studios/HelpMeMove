use helpmemove_bridge::api::bridge::{
    BridgeError, compose_starting_plan, exercise_display, load_committed_program_rule,
    select_program,
};
use helpmemove_content::{
    AssessedArea, Equipment, Exercise, Goal, MovementRating, ProgramRule, Region, parse_exercise,
    parse_program_rule,
};
use helpmemove_domain::DomainInstant;
use helpmemove_safety::{Classification, Eligibility, TriageLevel, classify, parse_rule_set};

const PROGRAM_RULE: &str = include_str!("../../../content/programs/syn-program-core.json");
const SAFETY_RULE: &str = include_str!("../../../content/rules/syn-safety-core.json");
const GREEN_SHOULDER: &str =
    include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");

#[test]
fn green_bodyweight_includes_only_the_isometric_fixture() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    assert_eq!(classification.eligibility, Eligibility::Eligible);
    assert!(classification.restrictions.is_empty());
    assert!(!classification.screening_required);
    assert!(classification.permits_ordinary_generation);
    let selection = select_shoulder(
        &classification,
        &[Equipment::Bodyweight],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "ready");
    assert_isometric_document(&selection.document_json);
    assert!(!selection.document_json.contains("limited"));
    assert!(!selection.document_json.contains("unreviewed_synthetic"));
    assert!(!selection.document_json.contains("syn-shoulder-band"));
}

#[test]
fn band_and_bodyweight_keep_id_order() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    let selection = select_shoulder(
        &classification,
        &[Equipment::ResistanceBand, Equipment::Bodyweight],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "ready");
    let band = selection
        .document_json
        .find("syn-shoulder-band")
        .expect("band");
    let isometric = selection
        .document_json
        .find("syn-shoulder-isometric")
        .expect("isometric");
    assert!(band < isometric);
    assert_eq!(count(&selection.document_json, "\"exercise_id\""), 2);
    assert_reason_cycles(&selection.document_json, 2);
}

#[test]
fn unable_still_includes_the_isometric_fixture() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    let selection = select_shoulder(
        &classification,
        &[Equipment::Bodyweight],
        MovementRating::Unable,
        committed_rule(),
    );
    assert_eq!(selection.code, "ready");
    assert_isometric_document(&selection.document_json);
    assert!(!selection.document_json.contains("unable"));
}

#[test]
fn yellow_has_no_candidate_because_every_fixture_is_contraindicated() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_yellow", "present")]);
    let selection = select_shoulder(
        &classification,
        &[
            Equipment::Bodyweight,
            Equipment::ResistanceBand,
            Equipment::Chair,
        ],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "no_candidate");
    assert!(selection.document_json.is_empty());
}

#[test]
fn orange_includes_the_isometric_fixture_while_progression_stays_paused() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_orange", "present")]);
    assert!(!classification.permits_progression);
    let selection = select_shoulder(
        &classification,
        &[Equipment::Bodyweight],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "ready");
    assert_isometric_document(&selection.document_json);
}

#[test]
fn forged_red_level_denies_generation() {
    let mut classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    classification.level = Some(TriageLevel::Red);
    assert!(classification.permits_ordinary_generation);
    let selection = select_shoulder(
        &classification,
        &[Equipment::Bodyweight],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "generation_denied");
    assert!(selection.document_json.is_empty());
}

#[test]
fn one_exercise_cap_keeps_the_earlier_shoulder_id() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    let mut rule = committed_rule();
    rule.max_exercises = 1;
    let selection = select_shoulder(
        &classification,
        &[Equipment::Bodyweight, Equipment::ResistanceBand],
        MovementRating::Limited,
        rule,
    );
    assert_eq!(selection.code, "ready");
    assert!(selection.document_json.contains("syn-shoulder-band"));
    assert!(!selection.document_json.contains("syn-shoulder-isometric"));
    assert_eq!(count(&selection.document_json, "\"exercise_id\""), 1);
}

#[test]
fn bodyweight_is_not_implied() {
    let classification = classified(&[("schema_ack", "yes"), ("schema_green", "present")]);
    let selection = select_shoulder(
        &classification,
        &[Equipment::Chair],
        MovementRating::Limited,
        committed_rule(),
    );
    assert_eq!(selection.code, "no_candidate");
    assert!(selection.document_json.is_empty());
}

#[test]
fn compose_withholds_the_production_answer() {
    let intake = r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder","laterality":"left"}],"note":"quiet","severity":4}"#;
    let assessment = r#"{"stopped":false,"complete":true,"areas":[{"region":"shoulder","laterality":"left","rating":"limited"}]}"#;
    let plan = compose_starting_plan(intake.to_owned(), assessment.to_owned(), 1_767_225_600_000);
    assert_eq!(plan.outcome, "withheld");
    assert_eq!(plan.withhold_code, "generation_denied");
    assert_eq!(plan.document_json, "");
}

#[test]
fn compose_reports_a_bad_intake_before_the_unmatched_classifier() {
    let plan = compose_starting_plan("{}".to_owned(), "{}".to_owned(), 0);
    assert_eq!(plan.withhold_code, "intake_unusable");
    assert_eq!(plan.document_json, "");
}

#[test]
fn compose_reports_an_incomplete_check_before_the_unmatched_classifier() {
    let intake =
        r#"{"goals":["control"],"equipment":["bodyweight"],"areas":[{"region":"shoulder"}]}"#;
    let assessment = r#"{"stopped":true,"complete":false,"areas":[]}"#;
    let plan = compose_starting_plan(intake.to_owned(), assessment.to_owned(), 0);
    assert_eq!(plan.withhold_code, "assessment_incomplete");
    assert_eq!(plan.document_json, "");
}

#[test]
fn load_committed_program_rule_returns_id_and_version() {
    let view = load_committed_program_rule().expect("program rule");
    assert_eq!(view.rule_id, "syn-program-core");
    assert_eq!(view.rule_version, 1);
}

#[test]
fn exercise_display_hides_an_unknown_id() {
    let display = exercise_display("syn-shoulder-isometric".to_owned()).expect("fixture");
    assert_eq!(display.name, "Synthetic syn shoulder isometric");
    assert_eq!(
        display.written_instructions,
        "Synthetic fixture. Not an exercise prescription."
    );
    let raw = "not-a-fixture";
    match exercise_display(raw.to_owned()) {
        Err(error) => {
            assert_eq!(error, BridgeError::InvalidProgram);
            assert_eq!(error.to_string(), "invalid-program");
            assert!(!error.to_string().contains(raw));
        }
        Ok(_) => panic!("accepted unknown exercise"),
    }
}

fn select_shoulder(
    classification: &Classification,
    equipment: &[Equipment],
    rating: MovementRating,
    rule: ProgramRule,
) -> helpmemove_bridge::api::bridge::ProgramSelection {
    select_program(
        classification,
        &[Goal::Control],
        equipment,
        &[AssessedArea {
            region: Region::Shoulder,
            rating,
        }],
        &fixtures(),
        &rule,
    )
}

fn committed_rule() -> ProgramRule {
    parse_program_rule(PROGRAM_RULE).expect("program rule")
}

fn classified(answers: &[(&str, &str)]) -> Classification {
    let rule = parse_rule_set(SAFETY_RULE.as_bytes()).expect("safety rule");
    classify(
        &rule,
        answers,
        DomainInstant::from_unix_millis(1_767_225_600_000),
        &[],
    )
    .expect("classification")
}

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

fn assert_isometric_document(document: &str) {
    assert_eq!(document, GREEN_SHOULDER.trim());
    assert_eq!(count(document, "\"exercise_id\""), 1);
    assert_reason_cycles(document, 1);
}

fn assert_reason_cycles(document: &str, times: usize) {
    let codes = [
        "region_match",
        "equipment_match",
        "goal_match",
        "screen_clear",
        "fixture_defaults",
    ];
    let mut last = 0;
    for _ in 0..times {
        for code in codes {
            let found = document[last..].find(code).expect(code);
            last += found + code.len();
        }
    }
}

fn count(haystack: &str, needle: &str) -> usize {
    haystack.match_indices(needle).count()
}
