//! Repository fixtures and the negative cases from track 0006.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use helpmemove_content::{
    ApprovalStatus, ContentError, Equipment, ExerciseLibrary, LicenseType, LinkKind, Region,
    SyntheticOnly, link_library, load_exercise_dir,
};

fn repo_exercises() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../content/exercises")
}

fn fixture(relative: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(relative)
}

fn load_linked(relative: &str) -> Result<ExerciseLibrary, ContentError> {
    let loaded = load_exercise_dir(&fixture(relative), SyntheticOnly)?;
    link_library(loaded)
}

fn assert_load_err(relative: &str, expected: ContentError) {
    let error = load_exercise_dir(&fixture(relative), SyntheticOnly).expect_err(relative);
    assert_eq!(error, expected, "{relative}");
}

#[test]
fn committed_library_is_the_four_synthetic_ids() {
    let dir = repo_exercises();
    let mut files: Vec<_> = fs::read_dir(&dir)
        .expect("exercises dir")
        .map(|entry| {
            entry
                .expect("entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    files.sort();
    assert_eq!(
        files,
        vec![
            "syn-knee-sit-to-stand.json",
            "syn-shoulder-band.json",
            "syn-shoulder-isometric.json",
            "syn-torso-pelvic-tilt.json",
        ]
    );

    let library =
        link_library(load_exercise_dir(&dir, SyntheticOnly).expect("synthetic directory"))
            .expect("links");
    let mut ids: Vec<_> = library
        .exercises()
        .iter()
        .map(|exercise| exercise.id.as_str().to_owned())
        .collect();
    ids.sort();
    assert_eq!(
        ids,
        vec![
            "syn-knee-sit-to-stand",
            "syn-shoulder-band",
            "syn-shoulder-isometric",
            "syn-torso-pelvic-tilt",
        ]
    );
    assert_eq!(library.len(), 4);

    let by_id = |id: &str| {
        library
            .exercises()
            .iter()
            .find(|exercise| exercise.id.as_str() == id)
            .unwrap_or_else(|| panic!("missing {id}"))
    };
    let isometric = by_id("syn-shoulder-isometric");
    assert_eq!(isometric.regions, vec![Region::Shoulder]);
    assert_eq!(isometric.laterality.as_str(), "bilateral");
    assert_eq!(isometric.equipment, vec![Equipment::Bodyweight]);
    assert_eq!(
        isometric
            .progressions
            .iter()
            .map(|id| id.as_str())
            .collect::<Vec<_>>(),
        vec!["syn-shoulder-band"]
    );
    let band = by_id("syn-shoulder-band");
    assert_eq!(band.regions, vec![Region::Shoulder]);
    assert_eq!(band.equipment, vec![Equipment::ResistanceBand]);
    assert_eq!(
        band.regressions
            .iter()
            .map(|id| id.as_str())
            .collect::<Vec<_>>(),
        vec!["syn-shoulder-isometric"]
    );
    let knee = by_id("syn-knee-sit-to-stand");
    assert_eq!(knee.regions, vec![Region::Leg]);
    assert_eq!(knee.equipment, vec![Equipment::Chair]);
    assert!(knee.progressions.is_empty());
    let torso = by_id("syn-torso-pelvic-tilt");
    assert_eq!(torso.regions, vec![Region::Torso]);
    assert_eq!(torso.equipment, vec![Equipment::Bodyweight]);
    assert!(torso.regressions.is_empty() && torso.substitutions.is_empty());
    for exercise in library.exercises() {
        let expected_name = format!("Synthetic {}", exercise.id.as_str().replace('-', " "));
        assert_eq!(exercise.name, expected_name);
        assert_eq!(exercise.approval_status, ApprovalStatus::Synthetic);
        assert_eq!(exercise.license.license_type, LicenseType::Unset);
        assert!(exercise.media.video_mp4.is_none());
        assert_eq!(
            exercise.populations,
            vec!["unreviewed_synthetic".to_owned()]
        );
        assert_eq!(
            exercise.written_instructions,
            "Synthetic fixture. Not an exercise prescription."
        );
    }
}

#[test]
fn graph_and_document_rejects_match_the_schema() {
    let progression = load_linked("progression_cycle").expect_err("progression cycle");
    assert_eq!(
        progression,
        ContentError::GraphCycle {
            kind: LinkKind::Progression,
            ids: vec![
                "cycle-a".to_owned(),
                "cycle-b".to_owned(),
                "cycle-a".to_owned(),
            ],
        }
    );
    let regression = load_linked("regression_cycle").expect_err("regression cycle");
    assert_eq!(
        regression,
        ContentError::GraphCycle {
            kind: LinkKind::Regression,
            ids: vec![
                "cycle-a".to_owned(),
                "cycle-b".to_owned(),
                "cycle-a".to_owned(),
            ],
        }
    );
    assert_eq!(
        load_linked("orphan_progression").expect_err("orphan progression"),
        ContentError::OrphanLink {
            kind: LinkKind::Progression,
            from: "cycle-a".to_owned(),
            to: "missing-exercise".to_owned(),
        }
    );
    assert_eq!(
        load_linked("orphan_substitution").expect_err("orphan substitution"),
        ContentError::OrphanLink {
            kind: LinkKind::Substitution,
            from: "cycle-a".to_owned(),
            to: "missing-exercise".to_owned(),
        }
    );
    assert_eq!(
        load_linked("self_substitution").expect_err("self substitution"),
        ContentError::SelfLink {
            kind: LinkKind::Substitution,
            id: "cycle-a".to_owned(),
        }
    );
    assert_eq!(
        load_linked("contradictory").expect_err("contradictory"),
        ContentError::ContradictoryLink {
            from: "cycle-a".to_owned(),
            id: "cycle-b".to_owned(),
        }
    );

    assert_load_err("schema_version", ContentError::SchemaVersion);
    assert_load_err("exercise_version", ContentError::ExerciseVersion);
    assert_load_err("laterality_both", ContentError::InvalidLaterality);
    assert_load_err("equipment_kettlebell", ContentError::InvalidEquipment);
    assert_load_err("media_parent", ContentError::MediaPath);
    assert_load_err("media_mkv", ContentError::MediaExtension);
    assert_load_err("approved_missing_video", ContentError::MediaMissing);
    assert_load_err(
        "approved_empty_approver",
        ContentError::ProductionField {
            field: "clinical_approver",
        },
    );
    assert_load_err("approved_unset_license", ContentError::License);
    assert_load_err(
        "approved_in_synthetic",
        ContentError::SyntheticViolation {
            field: "approval_status",
        },
    );
}

#[test]
fn nested_directories_and_non_json_files_are_skipped() {
    let library = load_linked("non_json_and_nested").expect("skip nested");
    let ids: Vec<_> = library
        .exercises()
        .iter()
        .map(|exercise| exercise.id.as_str())
        .collect();
    assert_eq!(ids, vec!["skip-notes"]);
}

#[test]
fn validate_content_prints_ok_and_uses_the_exit_codes() {
    let bin = Path::new(env!("CARGO_BIN_EXE_validate-content"));
    let ok = Command::new(bin)
        .arg(repo_exercises())
        .output()
        .expect("run validator");
    assert!(ok.status.success(), "status {:?}", ok.status.code());
    assert_eq!(String::from_utf8_lossy(&ok.stdout), "ok 4\n");

    let missing = Command::new(bin).output().expect("no args");
    assert_eq!(missing.status.code(), Some(2));

    let extra = Command::new(bin)
        .arg(repo_exercises())
        .arg(repo_exercises())
        .output()
        .expect("extra arg");
    assert_eq!(extra.status.code(), Some(2));

    let bad = Command::new(bin)
        .arg(fixture("progression_cycle"))
        .output()
        .expect("cycle");
    assert_eq!(bad.status.code(), Some(1));
    let stdout = String::from_utf8_lossy(&bad.stdout);
    assert!(
        stdout.starts_with("error graph-cycle progression"),
        "{stdout}"
    );
    assert!(!stdout.contains('{'), "{stdout}");
}
