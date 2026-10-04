use helpmemove_bridge::api::bridge::{
    BridgeError, SafetyAnswer, accept_equipment, accept_goal, accept_region,
    classify_committed_rule, intake_vocabulary,
};

fn answer(token: &str, value: &str) -> SafetyAnswer {
    SafetyAnswer {
        token: token.to_owned(),
        value: value.to_owned(),
    }
}

fn classify(
    answers: Vec<SafetyAnswer>,
    triggers: Vec<&str>,
    emergency_region: &str,
) -> helpmemove_bridge::api::bridge::SafetyView {
    classify_committed_rule(
        answers,
        1_767_225_600_000,
        triggers.into_iter().map(str::to_owned).collect(),
        emergency_region.to_owned(),
    )
}

#[test]
fn vocabulary_is_sorted_content_tokens() {
    let vocabulary = intake_vocabulary();
    assert_eq!(
        vocabulary.regions,
        vec![
            "arm",
            "foot",
            "head_neck",
            "leg",
            "pelvis",
            "shoulder",
            "torso"
        ]
    );
    assert_eq!(
        vocabulary.goals,
        vec![
            "conditioning",
            "control",
            "mobility",
            "stability",
            "strength"
        ]
    );
    assert_eq!(
        vocabulary.equipment,
        vec![
            "bodyweight",
            "chair",
            "dumbbell",
            "mat",
            "resistance_band",
            "towel",
            "wall"
        ]
    );
    assert_eq!(vocabulary.lateralities, vec!["bilateral", "left", "right"]);
}

#[test]
fn accept_rejects_unknown_tokens_without_echoing_them() {
    assert_eq!(accept_region("arm".to_owned()).as_deref(), Ok("arm"));
    match accept_region("elbow".to_owned()) {
        Err(error) => {
            assert_eq!(error, BridgeError::InvalidRegion);
            assert_eq!(error.code(), "invalid-region");
            assert!(!error.to_string().contains("elbow"));
        }
        Ok(value) => panic!("accepted region {value}"),
    }
    match accept_goal("not-a-goal".to_owned()) {
        Err(error) => {
            assert_eq!(error.code(), "invalid-goal");
            assert!(!error.to_string().contains("not-a-goal"));
        }
        Ok(value) => panic!("accepted goal {value}"),
    }
    match accept_equipment("kettlebell".to_owned()) {
        Err(error) => {
            assert_eq!(error.code(), "invalid-equipment");
            assert!(!error.to_string().contains("kettlebell"));
        }
        Ok(value) => panic!("accepted equipment {value}"),
    }
}

#[test]
fn missing_ack_is_ineligible_and_ack_alone_is_unmatched() {
    let ineligible = classify(Vec::new(), Vec::new(), "");
    assert_eq!(ineligible.code, "ineligible");
    assert_eq!(ineligible.level, "");
    assert!(!ineligible.permits_ordinary_generation);
    assert_eq!(ineligible.emergency_code, "region");
    assert_eq!(ineligible.emergency_display, "");

    let unmatched = classify(vec![answer("schema_ack", "yes")], Vec::new(), "");
    assert_eq!(unmatched.code, "unmatched");
    assert_eq!(unmatched.level, "");
    assert_eq!(unmatched.escalation, "");
    assert!(!unmatched.permits_ordinary_generation);
    assert_eq!(unmatched.emergency_display, "");
    assert_eq!(unmatched.emergency_code, "region");
}

#[test]
fn green_and_red_keep_the_engine_generation_flag() {
    let green = classify(
        vec![
            answer("schema_ack", "yes"),
            answer("schema_green", "present"),
        ],
        Vec::new(),
        "AA",
    );
    assert_eq!(green.code, "green");
    assert_eq!(green.level, "green");
    assert_eq!(green.escalation, "none");
    assert!(green.permits_ordinary_generation);
    assert_eq!(green.emergency_display, "schema-emergency");
    assert_eq!(green.emergency_code, "ok");

    let red = classify(
        vec![answer("schema_ack", "yes"), answer("schema_red", "present")],
        Vec::new(),
        "US",
    );
    assert_eq!(red.code, "red");
    assert_eq!(red.level, "red");
    assert_eq!(red.escalation, "emergency");
    assert!(!red.permits_ordinary_generation);
    assert_eq!(red.emergency_display, "");
    assert_eq!(red.emergency_code, "unknown-region");
}

#[test]
fn yellow_and_orange_keep_the_engine_outcome_flags() {
    let yellow = classify(
        vec![
            answer("schema_ack", "yes"),
            answer("schema_yellow", "present"),
        ],
        Vec::new(),
        "",
    );
    assert_eq!(yellow.code, "yellow");
    assert_eq!(yellow.level, "yellow");
    assert_eq!(yellow.escalation, "none");
    assert!(yellow.permits_ordinary_generation);

    let orange = classify(
        vec![
            answer("schema_ack", "yes"),
            answer("schema_orange", "present"),
        ],
        Vec::new(),
        "",
    );
    assert_eq!(orange.code, "orange");
    assert_eq!(orange.level, "orange");
    assert_eq!(orange.escalation, "evaluation");
    assert!(orange.permits_ordinary_generation);
}

#[test]
fn screening_clears_generation_and_bad_regions_have_no_number() {
    let screened = classify(
        vec![
            answer("schema_ack", "yes"),
            answer("schema_green", "present"),
        ],
        vec!["new_region"],
        "AA",
    );
    assert_eq!(screened.code, "green");
    assert!(!screened.permits_ordinary_generation);

    let bad = classify(vec![answer("schema_ack", "yes")], Vec::new(), "911");
    assert_eq!(bad.code, "unmatched");
    assert_eq!(bad.emergency_display, "");
    assert_eq!(bad.emergency_code, "region");
    assert!(!bad.emergency_display.contains("911"));
    assert!(!bad.emergency_code.contains("911"));
}
