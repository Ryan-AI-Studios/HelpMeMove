//! Synthetic safety rules and the decision table from track 0007.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use helpmemove_content::Exercise;
use helpmemove_safety::{
    ActiveIssue, Classification, DeniedReason, DomainInstant, Eligibility, Escalation,
    InterruptAction, RuleSet, SafetyError, ScreenDecision, SyntheticOnly, TriageLevel, classify,
    emergency_display, evaluate_interrupt, load_rule_dir, parse_rule_set, refresh, screen_exercise,
};

fn repo_rules() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../content/rules")
}

fn repo_exercises() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../content/exercises")
}

fn fixture(relative: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(relative)
}

fn core() -> RuleSet {
    let library = load_rule_dir(&repo_rules(), SyntheticOnly).expect("rules");
    assert_eq!(library.len(), 1);
    library.rules()[0].clone()
}

fn at_zero(rule: &RuleSet, answers: &[(&str, &str)]) -> Classification {
    classify(rule, answers, DomainInstant::from_unix_millis(0), &[]).expect("classify")
}

fn assert_parse_err(relative: &str, expected: SafetyError) {
    let bytes = fs::read(fixture(relative)).expect(relative);
    let error = parse_rule_set(&bytes).expect_err(relative);
    assert_eq!(error, expected, "{relative}");
    assert!(!error.to_string().contains("schema_ack"), "{relative}");
}

fn exercise_contraindicating(items: &str) -> Exercise {
    let json = format!(
        r#"{{
  "schema_version": 1,
  "exercise_id": "syn-screen-probe",
  "exercise_version": 1,
  "name": "Synthetic screen probe",
  "regions": ["leg"],
  "laterality": "bilateral",
  "targets": ["synthetic_target"],
  "goals": ["control"],
  "difficulty": 1,
  "equipment": ["chair"],
  "positions": ["standing"],
  "progressions": [],
  "regressions": [],
  "substitutions": [],
  "contraindications": [{items}],
  "camera_views": [],
  "tracked_metrics": [],
  "default_sets": 1,
  "default_reps": 1,
  "tempo": {{ "eccentric": 2, "pause": 1, "concentric": 2 }},
  "spoken_instructions": ["Synthetic fixture. Not an exercise prescription."],
  "written_instructions": "Synthetic fixture. Not an exercise prescription.",
  "common_mistakes": ["Reviewed schema label."],
  "modifications": ["Reviewed schema label."],
  "approval_status": "approved",
  "author": "schema-author",
  "reviewer": "schema-reviewer",
  "clinical_approver": "schema-approver",
  "approval_date": "2024-02-29",
  "last_reviewed": "2024-02-29",
  "evidence_references": [{{ "title": "Schema title", "citation": "Schema citation", "locator": "" }}],
  "populations": ["schema_population"],
  "license": {{
    "license_type": "cc0",
    "copyright_holder": "schema-holder",
    "attribution_notice": "schema-notice",
    "talent_release_id": "schema-release"
  }},
  "media": {{
    "video_mp4": "clip.mp4",
    "start_image_webp": "start.webp",
    "end_image_webp": "end.webp",
    "animation_riv": null
  }}
}}"#
    );
    helpmemove_content::parse_exercise(json.as_bytes())
        .unwrap_or_else(|error| panic!("exercise {error}"))
}

fn walk_rust(dir: &Path, hits: &mut Vec<String>) {
    for entry in fs::read_dir(dir).expect("read src") {
        let entry = entry.expect("entry");
        let path = entry.path();
        if path.is_dir() {
            walk_rust(&path, hits);
            continue;
        }
        if path.extension().and_then(|extension| extension.to_str()) != Some("rs") {
            continue;
        }
        let text = fs::read_to_string(&path).expect("utf8");
        for needle in [
            "911",
            "unwrap(",
            "expect(",
            "unsafe",
            "todo!",
            "unimplemented!",
            "SystemTime",
            "chrono",
        ] {
            if text.contains(needle) {
                hits.push(format!("{} contains {needle}", path.display()));
            }
        }
    }
}

#[test]
fn committed_directory_is_one_synthetic_rule() {
    let mut names: Vec<_> = fs::read_dir(repo_rules())
        .expect("rules dir")
        .map(|entry| {
            entry
                .expect("entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    names.sort();
    assert_eq!(names, vec!["syn-safety-core.json".to_owned()]);

    let rule = core();
    assert_eq!(rule.id().as_str(), "syn-safety-core");
    assert_eq!(rule.version(), 1);

    let approved =
        parse_rule_set(&fs::read(fixture("approved-sibling/approved-rule.json")).unwrap())
            .expect("approved document parses");
    assert_eq!(approved.id().as_str(), "approved-rule");
    let error = load_rule_dir(&fixture("approved-sibling"), SyntheticOnly).expect_err("sibling");
    assert_eq!(
        error,
        SafetyError::SyntheticViolation {
            field: "approval_status",
        }
    );
    assert_eq!(error.to_string(), "synthetic-violation approval_status");
}

#[test]
fn loader_ignores_nested_directories_and_non_json() {
    let library = load_rule_dir(&fixture("noise"), SyntheticOnly).expect("noise");
    assert_eq!(library.len(), 1);
    assert_eq!(library.rules()[0].id().as_str(), "syn-safety-core");
}

#[test]
fn file_stem_must_equal_rule_set_id() {
    let error = load_rule_dir(&fixture("stem-mismatch"), SyntheticOnly).expect_err("stem");
    assert_eq!(error, SafetyError::InvalidId);
}

#[test]
fn eligibility_and_triage_follow_the_document() {
    let rule = core();
    let missed = at_zero(&rule, &[]);
    assert_eq!(missed.eligibility, Eligibility::Ineligible);
    assert_eq!(missed.level, None);
    assert!(!missed.permits_ordinary_generation);
    assert!(!missed.permits_progression);
    assert_eq!(missed.escalation, Escalation::None);
    assert!(!missed.screening_required);

    let wrong = at_zero(&rule, &[("schema_ack", "no")]);
    assert_eq!(wrong.eligibility, Eligibility::Ineligible);
    assert!(!wrong.permits_ordinary_generation);

    let green = at_zero(&rule, &[("schema_ack", "yes"), ("schema_green", "present")]);
    assert_eq!(green.eligibility, Eligibility::Eligible);
    assert_eq!(green.level, Some(TriageLevel::Green));
    assert!(green.permits_ordinary_generation);
    assert!(green.permits_progression);
    assert_eq!(green.escalation, Escalation::None);
    assert!(green.restrictions.is_empty());
    assert_eq!(green.classified_at.unix_millis(), 0);

    let red = at_zero(&rule, &[("schema_ack", "yes"), ("schema_red", "present")]);
    assert_eq!(red.level, Some(TriageLevel::Red));
    assert!(!red.permits_ordinary_generation);
    assert!(!red.permits_progression);
    assert_eq!(red.escalation, Escalation::Emergency);
    assert_eq!(red.restrictions, vec!["unreviewed_synthetic".to_owned()]);

    let both = at_zero(
        &rule,
        &[
            ("schema_ack", "yes"),
            ("schema_green", "present"),
            ("schema_red", "present"),
        ],
    );
    assert_eq!(both.level, Some(TriageLevel::Red));
    assert!(!both.permits_ordinary_generation);
    assert_eq!(both.restrictions, vec!["unreviewed_synthetic".to_owned()]);

    let mixed = at_zero(
        &rule,
        &[
            ("schema_ack", "yes"),
            ("schema_yellow", "present"),
            ("schema_orange", "present"),
        ],
    );
    assert_eq!(mixed.level, Some(TriageLevel::Orange));
    assert_eq!(mixed.restrictions, vec!["unreviewed_synthetic".to_owned()]);
    assert!(mixed.permits_ordinary_generation);
    assert!(!mixed.permits_progression);
    assert_eq!(mixed.escalation, Escalation::Evaluation);

    let unmatched = classify(
        &rule,
        &[("schema_ack", "yes")],
        DomainInstant::from_unix_millis(0),
        &[],
    )
    .expect_err("unmatched");
    assert_eq!(unmatched, SafetyError::Unmatched);
    assert_eq!(unmatched.to_string(), "unmatched");

    let unknown = classify(
        &rule,
        &[("schema_ack", "yes"), ("not_declared", "present")],
        DomainInstant::from_unix_millis(0),
        &[],
    )
    .expect_err("unknown");
    assert_eq!(unknown, SafetyError::UnknownAnswer);
    assert_eq!(unknown.to_string(), "unknown-answer");

    let duplicate = classify(
        &rule,
        &[("schema_ack", "yes"), ("schema_ack", "yes")],
        DomainInstant::from_unix_millis(0),
        &[],
    )
    .expect_err("duplicate");
    assert_eq!(duplicate, SafetyError::Duplicate);
    assert_eq!(duplicate.to_string(), "duplicate");
}

#[test]
fn orange_allows_generation_and_issues_union_restrictions() {
    let rule = core();
    let orange = at_zero(
        &rule,
        &[("schema_ack", "yes"), ("schema_orange", "present")],
    );
    assert!(orange.permits_ordinary_generation);
    assert!(!orange.permits_progression);
    assert_eq!(orange.escalation, Escalation::Evaluation);

    let dir = repo_exercises();
    let library = helpmemove_content::load_exercise_dir(&dir, helpmemove_content::SyntheticOnly)
        .expect("exercises");
    let synthetic = &library.exercises()[0];
    assert_eq!(
        screen_exercise(&orange, &[], synthetic).expect("orange screen"),
        ScreenDecision::Eligible
    );
    let yellow = at_zero(
        &rule,
        &[("schema_ack", "yes"), ("schema_yellow", "present")],
    );
    assert_eq!(yellow.restrictions, vec!["unreviewed_synthetic".to_owned()]);
    assert_eq!(
        screen_exercise(&yellow, &[], synthetic).expect("yellow screen"),
        ScreenDecision::Denied(DeniedReason::Contraindicated)
    );

    let green = at_zero(&rule, &[("schema_ack", "yes"), ("schema_green", "present")]);
    let issues = [
        ActiveIssue {
            id: "issue-a".to_owned(),
            restrictions: vec!["unreviewed_synthetic".to_owned()],
        },
        ActiveIssue {
            id: "issue-b".to_owned(),
            restrictions: vec!["schema_other".to_owned()],
        },
    ];
    assert_eq!(
        screen_exercise(&green, &issues, synthetic).expect("synthetic issue"),
        ScreenDecision::Denied(DeniedReason::Contraindicated)
    );
    let other = exercise_contraindicating("\"schema_other\"");
    assert_eq!(
        screen_exercise(&green, &issues, &other).expect("other issue"),
        ScreenDecision::Denied(DeniedReason::Contraindicated)
    );
    let clear = exercise_contraindicating("\"schema_clear\"");
    assert_eq!(
        screen_exercise(&green, &issues, &clear).expect("clear issue"),
        ScreenDecision::Eligible
    );

    let red = at_zero(&rule, &[("schema_ack", "yes"), ("schema_red", "present")]);
    assert_eq!(
        screen_exercise(&red, &[], &clear).expect("red clear"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );
    assert_eq!(
        screen_exercise(&red, &[], synthetic).expect("red synthetic"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );
    let missed = at_zero(&rule, &[]);
    assert_eq!(
        screen_exercise(&missed, &[], &clear).expect("ineligible"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );

    let duplicate_issues = [
        ActiveIssue {
            id: "issue-a".to_owned(),
            restrictions: Vec::new(),
        },
        ActiveIssue {
            id: "issue-a".to_owned(),
            restrictions: Vec::new(),
        },
    ];
    assert_eq!(
        screen_exercise(&red, &duplicate_issues, &clear).expect_err("duplicate issue"),
        SafetyError::Duplicate
    );
    let bad_id = [ActiveIssue {
        id: "Bad".to_owned(),
        restrictions: Vec::new(),
    }];
    assert_eq!(
        screen_exercise(&red, &bad_id, &clear).expect_err("bad id"),
        SafetyError::InvalidId
    );
    let bad_token = [ActiveIssue {
        id: "issue-a".to_owned(),
        restrictions: vec!["Bad".to_owned()],
    }];
    assert_eq!(
        screen_exercise(&red, &bad_token, &clear).expect_err("bad token"),
        SafetyError::InvalidToken
    );
}

#[test]
fn refresh_uses_the_document_window_and_caller_triggers() {
    let rule = core();
    let green = at_zero(&rule, &[("schema_ack", "yes"), ("schema_green", "present")]);
    let earlier = refresh(
        &rule,
        &green,
        DomainInstant::from_unix_millis(86_399_999),
        &[],
    )
    .expect("earlier");
    assert!(!earlier.screening_required);
    assert!(earlier.permits_ordinary_generation);
    assert!(earlier.permits_progression);
    assert_eq!(earlier.level, Some(TriageLevel::Green));

    let boundary = refresh(
        &rule,
        &green,
        DomainInstant::from_unix_millis(86_400_000),
        &[],
    )
    .expect("boundary");
    assert!(boundary.screening_required);
    assert!(!boundary.permits_ordinary_generation);
    assert!(!boundary.permits_progression);
    assert_eq!(boundary.level, Some(TriageLevel::Green));
    assert_eq!(boundary.classified_at.unix_millis(), 0);
    let clear = exercise_contraindicating("\"schema_clear\"");
    assert_eq!(
        screen_exercise(&boundary, &[], &clear).expect("stale screen"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );

    let triggered = refresh(
        &rule,
        &green,
        DomainInstant::from_unix_millis(1),
        &["new_region"],
    )
    .expect("trigger");
    assert!(triggered.screening_required);
    assert!(!triggered.permits_ordinary_generation);
    assert!(!triggered.permits_progression);
    assert_eq!(triggered.level, Some(TriageLevel::Green));

    let reported = refresh(
        &rule,
        &green,
        DomainInstant::from_unix_millis(1),
        &["reported_change"],
    )
    .expect("reported");
    assert!(reported.screening_required);
    assert!(!reported.permits_ordinary_generation);

    let ignored = refresh(
        &rule,
        &green,
        DomainInstant::from_unix_millis(1),
        &["schema_other"],
    )
    .expect("ignored");
    assert!(!ignored.screening_required);
    assert!(ignored.permits_ordinary_generation);

    let clear = exercise_contraindicating("\"schema_clear\"");
    let held = refresh(&rule, &triggered, DomainInstant::from_unix_millis(2), &[]).expect("held");
    assert!(held.screening_required);
    assert!(!held.permits_ordinary_generation);
    assert!(!held.permits_progression);
    assert_eq!(held.level, Some(TriageLevel::Green));
    assert_eq!(
        screen_exercise(&held, &[], &clear).expect("held screen"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );
    let held_again =
        refresh(&rule, &held, DomainInstant::from_unix_millis(3), &[]).expect("held again");
    assert!(held_again.screening_required);
    assert!(!held_again.permits_ordinary_generation);

    let reported_held =
        refresh(&rule, &reported, DomainInstant::from_unix_millis(2), &[]).expect("reported held");
    assert!(reported_held.screening_required);
    assert!(!reported_held.permits_ordinary_generation);

    let backwards =
        refresh(&rule, &green, DomainInstant::from_unix_millis(-1), &[]).expect_err("clock");
    assert_eq!(backwards, SafetyError::Clock);
    assert_eq!(backwards.to_string(), "clock");

    let classified = classify(
        &rule,
        &[("schema_ack", "yes"), ("schema_green", "present")],
        DomainInstant::from_unix_millis(0),
        &["new_region"],
    )
    .expect("classify trigger");
    assert!(classified.screening_required);
    assert!(!classified.permits_ordinary_generation);
    let classified_held = refresh(&rule, &classified, DomainInstant::from_unix_millis(4), &[])
        .expect("classified held");
    assert!(classified_held.screening_required);
    assert_eq!(
        screen_exercise(&classified_held, &[], &clear).expect("classified screen"),
        ScreenDecision::Denied(DeniedReason::GenerationDenied)
    );

    let rescreened = at_zero(&rule, &[("schema_ack", "yes"), ("schema_green", "present")]);
    assert!(!rescreened.screening_required);
    assert!(rescreened.permits_ordinary_generation);
    assert_eq!(
        screen_exercise(&rescreened, &[], &clear).expect("new screening"),
        ScreenDecision::Eligible
    );
}

#[test]
fn interrupts_fail_closed_and_regions_have_no_default() {
    let rule = core();
    let continued = evaluate_interrupt(&rule, "schema_continue");
    assert_eq!(continued.action, InterruptAction::Continue);
    assert!(!continued.fail_closed);
    assert_eq!(
        evaluate_interrupt(&rule, "schema_reduce").action,
        InterruptAction::Reduce
    );
    assert_eq!(
        evaluate_interrupt(&rule, "schema_pause").action,
        InterruptAction::Pause
    );
    assert_eq!(
        evaluate_interrupt(&rule, "schema_abort").action,
        InterruptAction::Abort
    );
    assert!(!evaluate_interrupt(&rule, "schema_abort").fail_closed);

    let unknown = evaluate_interrupt(&rule, "not_in_table");
    assert_eq!(unknown.action, InterruptAction::Abort);
    assert!(unknown.fail_closed);
    let empty = evaluate_interrupt(&rule, "");
    assert_eq!(empty.action, InterruptAction::Abort);
    assert!(empty.fail_closed);

    assert_eq!(
        emergency_display(&rule, "AA").expect("known region"),
        "schema-emergency"
    );
    let unknown_region = emergency_display(&rule, "US").expect_err("unknown region");
    assert_eq!(unknown_region, SafetyError::UnknownRegion);
    assert_eq!(unknown_region.to_string(), "unknown-region");
    let bad_shape = emergency_display(&rule, "911").expect_err("bad shape");
    assert_eq!(bad_shape, SafetyError::Region);
    assert_eq!(bad_shape.to_string(), "region");
}

#[test]
fn parse_rejects_bad_documents() {
    assert_parse_err("schema-version-2.json", SafetyError::SchemaVersion);
    assert_parse_err(
        "missing-schema-version.json",
        SafetyError::MissingField {
            name: "schema_version",
        },
    );
    assert_parse_err(
        "approved-empty-approver.json",
        SafetyError::ProductionField {
            field: "clinical_approver",
        },
    );
    assert_parse_err("bad-leap-day.json", SafetyError::Date);
    assert_parse_err("valid-for-days-zero.json", SafetyError::Limit);

    let committed = fs::read_to_string(repo_rules().join("syn-safety-core.json")).expect("json");
    let negative = committed.replace("\"valid_for_days\": 1", "\"valid_for_days\": -1");
    assert_eq!(
        parse_rule_set(negative.as_bytes()).expect_err("negative"),
        SafetyError::InvalidDocument
    );
    let leap_ok = fs::read(fixture("approved-sibling/approved-rule.json")).expect("approved");
    parse_rule_set(&leap_ok).expect("2024-02-29 parses");

    let unknown = committed.replacen('{', "{\n  \"extra_field\": 1,", 1);
    assert_eq!(
        parse_rule_set(unknown.as_bytes()).expect_err("unknown"),
        SafetyError::UnknownField {
            name: "extra_field".to_owned(),
        }
    );
    let long_key = "a".repeat(65);
    let long = committed.replacen('{', &format!("{{\n  \"{long_key}\": 1,"), 1);
    assert_eq!(
        parse_rule_set(long.as_bytes()).expect_err("long"),
        SafetyError::InvalidDocument
    );
    let spaced = committed.replacen('{', "{\n  \"bad field\": 1,", 1);
    assert_eq!(
        parse_rule_set(spaced.as_bytes()).expect_err("space"),
        SafetyError::InvalidDocument
    );
    let poisoned = committed.replace(
        "\"schema_version\": 1",
        "\"schema_version\": \"unknown field `private_answer_yes`\"",
    );
    let poisoned_error = parse_rule_set(poisoned.as_bytes()).expect_err("poisoned type");
    assert_eq!(poisoned_error, SafetyError::InvalidDocument);
    assert!(!poisoned_error.to_string().contains("private_answer"));
    let backtick_key = format!("a`{}", "b".repeat(65));
    let backtick = committed.replacen('{', &format!("{{\n  \"{backtick_key}\": 1,"), 1);
    let backtick_error = parse_rule_set(backtick.as_bytes()).expect_err("backtick key");
    assert_eq!(backtick_error, SafetyError::InvalidDocument);
    assert!(!backtick_error.to_string().contains("private_answer"));
    assert!(!backtick_error.to_string().contains('`'));

    let repeated_version = committed.replace(
        "\"schema_version\": 1",
        "\"schema_version\": -1, \"schema_version\": 1",
    );
    let repeated_version_error =
        parse_rule_set(repeated_version.as_bytes()).expect_err("repeated version");
    assert_eq!(repeated_version_error, SafetyError::InvalidDocument);
    assert!(!repeated_version_error.to_string().contains("-1"));
    let repeated_level = committed.replace(
        "\"level\": \"red\"",
        "\"level\": \"red\", \"level\": \"green\"",
    );
    assert_eq!(
        parse_rule_set(repeated_level.as_bytes()).expect_err("repeated level"),
        SafetyError::InvalidDocument
    );

    let empty_key = committed.replacen('{', "{\n  \"\": 1,", 1);
    assert_eq!(
        parse_rule_set(empty_key.as_bytes()).expect_err("empty key"),
        SafetyError::UnknownField {
            name: String::new(),
        }
    );
    let nested_empty = committed.replace(
        "{ \"token\": \"schema_ack\", \"equals\": \"yes\" }",
        "{ \"token\": \"schema_ack\", \"equals\": \"yes\", \"\": 1 }",
    );
    assert_eq!(
        parse_rule_set(nested_empty.as_bytes()).expect_err("nested empty key"),
        SafetyError::UnknownField {
            name: String::new(),
        }
    );
}

#[test]
fn validate_rules_prints_ok_for_the_committed_directory() {
    let bin = Path::new(env!("CARGO_BIN_EXE_validate-rules"));
    let ok = Command::new(bin)
        .arg(repo_rules())
        .output()
        .expect("run validator");
    assert!(ok.status.success(), "status {:?}", ok.status.code());
    assert_eq!(String::from_utf8_lossy(&ok.stdout), "ok 1\n");

    let missing = Command::new(bin).output().expect("no args");
    assert_eq!(missing.status.code(), Some(2));
    let extra = Command::new(bin)
        .arg(repo_rules())
        .arg(repo_rules())
        .output()
        .expect("extra arg");
    assert_eq!(extra.status.code(), Some(2));

    let bad = Command::new(bin)
        .arg(fixture("approved-sibling"))
        .output()
        .expect("approved sibling");
    assert_eq!(bad.status.code(), Some(1));
    assert_eq!(
        String::from_utf8_lossy(&bad.stdout),
        "error synthetic-violation approval_status\n"
    );
}

#[test]
fn repo_exercises_screen_under_red_and_green() {
    let rule = core();
    let green = at_zero(&rule, &[("schema_ack", "yes"), ("schema_green", "present")]);
    let red = at_zero(&rule, &[("schema_ack", "yes"), ("schema_red", "present")]);
    let library =
        helpmemove_content::load_exercise_dir(&repo_exercises(), helpmemove_content::SyntheticOnly)
            .expect("exercises");
    assert_eq!(library.len(), 4);
    for exercise in library.exercises() {
        assert_eq!(
            screen_exercise(&green, &[], exercise).expect("green screen"),
            ScreenDecision::Eligible
        );
        assert_eq!(
            screen_exercise(&red, &[], exercise).expect("red screen"),
            ScreenDecision::Denied(DeniedReason::GenerationDenied)
        );
    }
}

#[test]
fn production_sources_keep_the_safety_boundary() {
    let mut hits = Vec::new();
    walk_rust(
        &PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src"),
        &mut hits,
    );
    assert!(hits.is_empty(), "{hits:?}");
}
