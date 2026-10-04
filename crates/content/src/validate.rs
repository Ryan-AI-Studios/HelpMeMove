//! Parse exercise documents, reject approved files in a synthetic directory, and link the graph.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs;
use std::path::{Component, Path};

use helpmemove_domain::Laterality;
use serde::Deserialize;
use serde::de::{self, Deserializer, Visitor};

use crate::error::{ContentError, LinkKind};
use crate::model::{
    ApprovalStatus, CameraView, Equipment, EvidenceReference, Exercise, ExerciseId,
    ExerciseLibrary, Goal, License, LicenseType, Media, Position, Region, SyntheticOnly, Tempo,
    TrackedMetric, is_exercise_id,
};

// Schema bounds, not clinical doses.
const DIFFICULTY_MIN: u32 = 1;
const DIFFICULTY_MAX: u32 = 5;
const SETS_MIN: u32 = 1;
const SETS_MAX: u32 = 10;
const REPS_MIN: u32 = 1;
const REPS_MAX: u32 = 30;
const TEMPO_MAX: u8 = 10;

const SYNTHETIC_TOKEN: &str = "unreviewed_synthetic";

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawExercise {
    schema_version: u32,
    exercise_id: String,
    exercise_version: u32,
    name: String,
    regions: Vec<String>,
    laterality: String,
    targets: Vec<String>,
    goals: Vec<String>,
    difficulty: u32,
    equipment: Vec<String>,
    positions: Vec<String>,
    progressions: Vec<String>,
    regressions: Vec<String>,
    substitutions: Vec<String>,
    contraindications: Vec<String>,
    camera_views: Vec<String>,
    tracked_metrics: Vec<String>,
    default_sets: u32,
    default_reps: u32,
    tempo: RawTempo,
    spoken_instructions: Vec<String>,
    written_instructions: String,
    common_mistakes: Vec<String>,
    modifications: Vec<String>,
    approval_status: String,
    author: String,
    reviewer: String,
    clinical_approver: String,
    approval_date: String,
    last_reviewed: String,
    evidence_references: Vec<RawEvidence>,
    populations: Vec<String>,
    license: RawLicense,
    media: RawMedia,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawTempo {
    eccentric: u32,
    pause: u32,
    concentric: u32,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawEvidence {
    title: String,
    citation: String,
    locator: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawLicense {
    license_type: String,
    copyright_holder: String,
    attribution_notice: String,
    talent_release_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RawMedia {
    video_mp4: RequiredNullable,
    start_image_webp: RequiredNullable,
    end_image_webp: RequiredNullable,
    animation_riv: RequiredNullable,
}

/// A media key that must be present. The value may be a string or JSON null.
#[derive(Debug)]
struct RequiredNullable(Option<String>);

impl RequiredNullable {
    fn as_deref(&self) -> Option<&str> {
        self.0.as_deref()
    }
}

impl<'de> Deserialize<'de> for RequiredNullable {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        deserializer.deserialize_any(NullableStringVisitor)
    }
}

struct NullableStringVisitor;

impl<'de> Visitor<'de> for NullableStringVisitor {
    type Value = RequiredNullable;

    fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
        formatter.write_str("a string or null")
    }

    fn visit_str<E: de::Error>(self, value: &str) -> Result<Self::Value, E> {
        Ok(RequiredNullable(Some(value.to_owned())))
    }

    fn visit_string<E: de::Error>(self, value: String) -> Result<Self::Value, E> {
        Ok(RequiredNullable(Some(value)))
    }

    fn visit_unit<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(RequiredNullable(None))
    }

    fn visit_none<E: de::Error>(self) -> Result<Self::Value, E> {
        Ok(RequiredNullable(None))
    }
}

enum EmptyList {
    Allow,
    Reject(&'static str),
}

/// Validate one document. This does not resolve links or read media files.
pub fn parse_exercise(bytes: &[u8]) -> Result<Exercise, ContentError> {
    let raw: RawExercise = serde_json::from_slice(bytes).map_err(map_serde)?;
    validate_raw(raw)
}

/// Read `*.json` in `path` only. Nested directories are ignored. Approved documents are rejected.
pub fn load_exercise_dir(
    path: &Path,
    mode: SyntheticOnly,
) -> Result<ExerciseLibrary, ContentError> {
    let SyntheticOnly = mode;
    let mut files = Vec::new();
    let entries = fs::read_dir(path).map_err(|_| ContentError::Io)?;
    for entry in entries {
        let entry = entry.map_err(|_| ContentError::Io)?;
        let file_type = entry.file_type().map_err(|_| ContentError::Io)?;
        if !file_type.is_file() {
            continue;
        }
        let file_path = entry.path();
        if file_path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        files.push(file_path);
    }
    files.sort();

    let mut exercises = Vec::with_capacity(files.len());
    for file_path in files {
        let bytes = fs::read(&file_path).map_err(|_| ContentError::Io)?;
        let exercise = parse_exercise(&bytes)?;
        let stem = file_path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .ok_or(ContentError::InvalidId)?;
        if stem != exercise.id.as_str() {
            return Err(ContentError::InvalidId);
        }
        check_media(path, &exercise)?;
        if exercise.approval_status != ApprovalStatus::Synthetic {
            return Err(ContentError::SyntheticViolation {
                field: "approval_status",
            });
        }
        exercises.push(exercise);
    }
    Ok(ExerciseLibrary::from_exercises(exercises))
}

/// Require unique ids, existing targets, no self links, no progression/regression contradiction, and two DAGs.
///
/// Substitution edges may cycle, and a substitution does not require the reverse edge.
pub fn link_library(library: ExerciseLibrary) -> Result<ExerciseLibrary, ContentError> {
    let exercises = library.into_exercises();
    let mut seen = BTreeSet::new();
    for exercise in &exercises {
        if !seen.insert(exercise.id.as_str().to_owned()) {
            return Err(ContentError::DuplicateId {
                id: exercise.id.as_str().to_owned(),
            });
        }
    }

    for_each_edge(&exercises, |kind, exercise, target| {
        if target.as_str() == exercise.id.as_str() {
            return Err(ContentError::SelfLink {
                kind,
                id: exercise.id.as_str().to_owned(),
            });
        }
        Ok(())
    })?;

    for exercise in &exercises {
        let progressions: BTreeSet<&str> = exercise
            .progressions
            .iter()
            .map(ExerciseId::as_str)
            .collect();
        for target in &exercise.regressions {
            if progressions.contains(target.as_str()) {
                return Err(ContentError::ContradictoryLink {
                    from: exercise.id.as_str().to_owned(),
                    id: target.as_str().to_owned(),
                });
            }
        }
    }

    let ids: BTreeSet<&str> = exercises
        .iter()
        .map(|exercise| exercise.id.as_str())
        .collect();
    for_each_edge(&exercises, |kind, exercise, target| {
        if ids.contains(target.as_str()) {
            Ok(())
        } else {
            Err(ContentError::OrphanLink {
                kind,
                from: exercise.id.as_str().to_owned(),
                to: target.as_str().to_owned(),
            })
        }
    })?;

    ensure_acyclic(&exercises, LinkKind::Progression, |exercise| {
        &exercise.progressions
    })?;
    ensure_acyclic(&exercises, LinkKind::Regression, |exercise| {
        &exercise.regressions
    })?;
    Ok(ExerciseLibrary::from_exercises(exercises))
}

/// Require each present media path to stay inside `exercises_dir` and name a regular file.
pub fn check_media(exercises_dir: &Path, exercise: &Exercise) -> Result<(), ContentError> {
    for relative in required_media_paths(&exercise.media) {
        require_regular_file(exercises_dir, relative)?;
    }
    Ok(())
}

fn required_media_paths(media: &Media) -> Vec<&str> {
    let mut paths = Vec::new();
    if let Some(path) = media.video_mp4.as_deref() {
        paths.push(path);
    }
    if let Some(path) = media.start_image_webp.as_deref() {
        paths.push(path);
    }
    if let Some(path) = media.end_image_webp.as_deref() {
        paths.push(path);
    }
    if let Some(path) = media.animation_riv.as_deref() {
        paths.push(path);
    }
    paths
}

fn validate_raw(raw: RawExercise) -> Result<Exercise, ContentError> {
    if raw.schema_version != 1 {
        return Err(ContentError::SchemaVersion);
    }
    if raw.exercise_version != 1 {
        return Err(ContentError::ExerciseVersion);
    }
    let id = ExerciseId::parse(&raw.exercise_id)?;
    let name = require_chars(&raw.name, "name", 1, 120)?;
    let regions = closed_set(
        &raw.regions,
        EmptyList::Reject("regions"),
        ContentError::InvalidRegion,
        parse_region,
    )?;
    let laterality =
        Laterality::parse(&raw.laterality).map_err(|_| ContentError::InvalidLaterality)?;
    let targets = target_tokens(&raw.targets)?;
    let goals = closed_set(
        &raw.goals,
        EmptyList::Reject("goals"),
        ContentError::InvalidGoal,
        parse_goal,
    )?;
    let difficulty = bounded_u8(
        raw.difficulty,
        DIFFICULTY_MIN,
        DIFFICULTY_MAX,
        ContentError::InvalidDifficulty,
    )?;
    let equipment = closed_set(
        &raw.equipment,
        EmptyList::Reject("equipment"),
        ContentError::InvalidEquipment,
        parse_equipment,
    )?;
    let positions = closed_set(
        &raw.positions,
        EmptyList::Reject("positions"),
        ContentError::InvalidPosition,
        parse_position,
    )?;
    let progressions = link_ids(&raw.progressions)?;
    let regressions = link_ids(&raw.regressions)?;
    let substitutions = link_ids(&raw.substitutions)?;
    let camera_views = closed_set(
        &raw.camera_views,
        EmptyList::Allow,
        ContentError::InvalidCameraView,
        parse_camera_view,
    )?;
    let tracked_metrics = closed_set(
        &raw.tracked_metrics,
        EmptyList::Allow,
        ContentError::InvalidMetric,
        parse_metric,
    )?;
    let default_sets = bounded_u8(
        raw.default_sets,
        SETS_MIN,
        SETS_MAX,
        ContentError::InvalidSetsReps,
    )?;
    let default_reps = bounded_u8(
        raw.default_reps,
        REPS_MIN,
        REPS_MAX,
        ContentError::InvalidSetsReps,
    )?;
    let tempo = Tempo {
        eccentric: tempo_part(raw.tempo.eccentric)?,
        pause: tempo_part(raw.tempo.pause)?,
        concentric: tempo_part(raw.tempo.concentric)?,
    };
    let spoken_instructions =
        require_text_list(&raw.spoken_instructions, "spoken_instructions", 200)?;
    let written_instructions =
        require_chars(&raw.written_instructions, "written_instructions", 1, 500)?;
    bound_chars(&raw.author, "author", 120)?;
    bound_chars(&raw.reviewer, "reviewer", 120)?;
    bound_chars(&raw.clinical_approver, "clinical_approver", 120)?;
    let populations = require_text_list(&raw.populations, "populations", 80)?;
    let contraindications = require_text_list(&raw.contraindications, "contraindications", 120)?;
    let common_mistakes = require_text_list(&raw.common_mistakes, "common_mistakes", 200)?;
    let modifications = require_text_list(&raw.modifications, "modifications", 200)?;
    let media = validate_media_shape(&raw.media)?;
    let license_type = parse_license_type(&raw.license.license_type)?;
    let approval_status = match raw.approval_status.as_str() {
        "synthetic" => ApprovalStatus::Synthetic,
        "approved" => ApprovalStatus::Approved,
        _ => return Err(ContentError::ApprovalStatus),
    };

    match approval_status {
        ApprovalStatus::Synthetic => {
            require_empty(&raw.author, "author")?;
            require_empty(&raw.reviewer, "reviewer")?;
            require_empty(&raw.clinical_approver, "clinical_approver")?;
            require_empty(&raw.approval_date, "approval_date")?;
            require_empty(&raw.last_reviewed, "last_reviewed")?;
            if !raw.evidence_references.is_empty() {
                return Err(ContentError::SyntheticViolation {
                    field: "evidence_references",
                });
            }
            require_synthetic_list(&populations, "populations")?;
            require_synthetic_list(&contraindications, "contraindications")?;
            require_synthetic_list(&common_mistakes, "common_mistakes")?;
            require_synthetic_list(&modifications, "modifications")?;
            if license_type != LicenseType::Unset
                || !raw.license.copyright_holder.is_empty()
                || !raw.license.attribution_notice.is_empty()
                || !raw.license.talent_release_id.is_empty()
            {
                return Err(ContentError::SyntheticViolation { field: "license" });
            }
            if media.video_mp4.is_some()
                || media.start_image_webp.is_some()
                || media.end_image_webp.is_some()
                || media.animation_riv.is_some()
            {
                return Err(ContentError::SyntheticViolation { field: "media" });
            }
        }
        ApprovalStatus::Approved => {
            require_non_empty(&raw.author, "author")?;
            require_non_empty(&raw.reviewer, "reviewer")?;
            require_non_empty(&raw.clinical_approver, "clinical_approver")?;
            require_calendar_date(&raw.approval_date)?;
            require_calendar_date(&raw.last_reviewed)?;
            let evidence_references = approved_evidence(&raw.evidence_references)?;
            if populations.iter().any(|item| item == SYNTHETIC_TOKEN) {
                return Err(ContentError::SyntheticViolation {
                    field: "populations",
                });
            }
            reject_exact_synthetic(&contraindications, "contraindications")?;
            reject_exact_synthetic(&common_mistakes, "common_mistakes")?;
            reject_exact_synthetic(&modifications, "modifications")?;
            if license_type == LicenseType::Unset {
                return Err(ContentError::License);
            }
            require_non_empty(&raw.license.copyright_holder, "copyright_holder")?;
            require_non_empty(&raw.license.attribution_notice, "attribution_notice")?;
            require_non_empty(&raw.license.talent_release_id, "talent_release_id")?;
            if media.video_mp4.is_none() {
                return Err(ContentError::ProductionField { field: "video_mp4" });
            }
            if media.start_image_webp.is_none() {
                return Err(ContentError::ProductionField {
                    field: "start_image_webp",
                });
            }
            if media.end_image_webp.is_none() {
                return Err(ContentError::ProductionField {
                    field: "end_image_webp",
                });
            }
            return Ok(Exercise {
                id,
                name,
                regions,
                laterality,
                targets,
                goals,
                difficulty,
                equipment,
                positions,
                progressions,
                regressions,
                substitutions,
                contraindications,
                camera_views,
                tracked_metrics,
                default_sets,
                default_reps,
                tempo,
                spoken_instructions,
                written_instructions,
                common_mistakes,
                modifications,
                approval_status,
                author: raw.author,
                reviewer: raw.reviewer,
                clinical_approver: raw.clinical_approver,
                approval_date: raw.approval_date,
                last_reviewed: raw.last_reviewed,
                evidence_references,
                populations,
                license: License {
                    license_type,
                    copyright_holder: raw.license.copyright_holder,
                    attribution_notice: raw.license.attribution_notice,
                    talent_release_id: raw.license.talent_release_id,
                },
                media,
            });
        }
    }

    Ok(Exercise {
        id,
        name,
        regions,
        laterality,
        targets,
        goals,
        difficulty,
        equipment,
        positions,
        progressions,
        regressions,
        substitutions,
        contraindications,
        camera_views,
        tracked_metrics,
        default_sets,
        default_reps,
        tempo,
        spoken_instructions,
        written_instructions,
        common_mistakes,
        modifications,
        approval_status,
        author: raw.author,
        reviewer: raw.reviewer,
        clinical_approver: raw.clinical_approver,
        approval_date: raw.approval_date,
        last_reviewed: raw.last_reviewed,
        evidence_references: Vec::new(),
        populations,
        license: License {
            license_type,
            copyright_holder: raw.license.copyright_holder,
            attribution_notice: raw.license.attribution_notice,
            talent_release_id: raw.license.talent_release_id,
        },
        media,
    })
}

fn approved_evidence(references: &[RawEvidence]) -> Result<Vec<EvidenceReference>, ContentError> {
    if references.is_empty() {
        return Err(ContentError::ProductionField {
            field: "evidence_references",
        });
    }
    let mut evidence = Vec::with_capacity(references.len());
    for reference in references {
        if reference.title.is_empty() || reference.citation.is_empty() {
            return Err(ContentError::ProductionField {
                field: "evidence_references",
            });
        }
        if !locator_ok(&reference.locator) {
            return Err(ContentError::ProductionField { field: "locator" });
        }
        evidence.push(EvidenceReference {
            title: reference.title.clone(),
            citation: reference.citation.clone(),
            locator: reference.locator.clone(),
        });
    }
    Ok(evidence)
}

fn locator_ok(locator: &str) -> bool {
    locator.is_empty() || locator.starts_with("https://") || locator.starts_with("doi:")
}

fn require_calendar_date(value: &str) -> Result<(), ContentError> {
    if is_calendar_date(value) {
        Ok(())
    } else {
        Err(ContentError::Date)
    }
}

fn is_calendar_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    let Some(year) = parse_digits(&bytes[0..4]) else {
        return false;
    };
    let Some(month) = parse_digits(&bytes[5..7]) else {
        return false;
    };
    let Some(day) = parse_digits(&bytes[8..10]) else {
        return false;
    };
    let max_day = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if is_leap_year(year) => 29,
        2 => 28,
        _ => return false,
    };
    (1..=max_day).contains(&day)
}

fn is_leap_year(year: u32) -> bool {
    year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400))
}

fn parse_digits(bytes: &[u8]) -> Option<u32> {
    if bytes.is_empty() {
        return None;
    }
    let mut value = 0u32;
    for byte in bytes {
        if !byte.is_ascii_digit() {
            return None;
        }
        let next = value.checked_mul(10)?;
        value = next + u32::from(*byte - b'0');
    }
    Some(value)
}

fn require_empty(value: &str, field: &'static str) -> Result<(), ContentError> {
    if value.is_empty() {
        Ok(())
    } else {
        Err(ContentError::SyntheticViolation { field })
    }
}

fn require_non_empty(value: &str, field: &'static str) -> Result<(), ContentError> {
    if value.is_empty() {
        Err(ContentError::ProductionField { field })
    } else {
        Ok(())
    }
}

fn require_synthetic_list(values: &[String], field: &'static str) -> Result<(), ContentError> {
    if values == [SYNTHETIC_TOKEN] {
        Ok(())
    } else {
        Err(ContentError::SyntheticViolation { field })
    }
}

fn reject_exact_synthetic(values: &[String], field: &'static str) -> Result<(), ContentError> {
    if values == [SYNTHETIC_TOKEN] {
        Err(ContentError::SyntheticViolation { field })
    } else {
        Ok(())
    }
}

fn validate_media_shape(raw: &RawMedia) -> Result<Media, ContentError> {
    Ok(Media {
        video_mp4: optional_media_path(raw.video_mp4.as_deref(), "mp4")?,
        start_image_webp: optional_media_path(raw.start_image_webp.as_deref(), "webp")?,
        end_image_webp: optional_media_path(raw.end_image_webp.as_deref(), "webp")?,
        animation_riv: optional_media_path(raw.animation_riv.as_deref(), "riv")?,
    })
}

fn optional_media_path(
    value: Option<&str>,
    extension: &str,
) -> Result<Option<String>, ContentError> {
    let Some(value) = value else {
        return Ok(None);
    };
    media_shape(value, extension)?;
    Ok(Some(value.to_owned()))
}

fn media_shape(value: &str, extension: &str) -> Result<(), ContentError> {
    if value.is_empty() {
        return Err(ContentError::MediaPath);
    }
    let path = Path::new(value);
    if path.is_absolute() {
        return Err(ContentError::MediaPath);
    }
    let mut saw_file = false;
    for component in path.components() {
        match component {
            Component::Normal(part) if !part.is_empty() => saw_file = true,
            Component::Normal(_)
            | Component::CurDir
            | Component::ParentDir
            | Component::RootDir
            | Component::Prefix(_) => return Err(ContentError::MediaPath),
        }
    }
    if !saw_file {
        return Err(ContentError::MediaPath);
    }
    if path.extension().and_then(|ext| ext.to_str()) == Some(extension) {
        Ok(())
    } else {
        Err(ContentError::MediaExtension)
    }
}

fn require_regular_file(root: &Path, relative: &str) -> Result<(), ContentError> {
    let relative_path = Path::new(relative);
    if relative_path.is_absolute() || !relative_stays_inside(relative_path) {
        return Err(ContentError::MediaPath);
    }
    let joined = root.join(relative_path);
    let metadata = match fs::symlink_metadata(&joined) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(ContentError::MediaMissing);
        }
        Err(_) => return Err(ContentError::Io),
    };
    let file_type = metadata.file_type();
    if file_type.is_symlink() || !file_type.is_file() {
        return Err(ContentError::MediaPath);
    }
    let root_canon = fs::canonicalize(root).map_err(|_| ContentError::Io)?;
    let file_canon = fs::canonicalize(&joined).map_err(|_| ContentError::Io)?;
    if file_canon.starts_with(&root_canon) {
        Ok(())
    } else {
        Err(ContentError::MediaPath)
    }
}

fn relative_stays_inside(path: &Path) -> bool {
    for component in path.components() {
        if !matches!(component, Component::Normal(part) if !part.is_empty()) {
            return false;
        }
    }
    true
}

fn link_ids(values: &[String]) -> Result<Vec<ExerciseId>, ContentError> {
    let mut ids = Vec::with_capacity(values.len());
    let mut seen = BTreeSet::new();
    for value in values {
        if !is_exercise_id(value) {
            return Err(ContentError::InvalidId);
        }
        if !seen.insert(value.as_str()) {
            return Err(ContentError::DuplicateId { id: value.clone() });
        }
        ids.push(ExerciseId::parse(value)?);
    }
    Ok(ids)
}

fn target_tokens(values: &[String]) -> Result<Vec<String>, ContentError> {
    if values.is_empty() {
        return Err(ContentError::ProductionField { field: "targets" });
    }
    let mut tokens = Vec::with_capacity(values.len());
    let mut seen = BTreeSet::new();
    for value in values {
        if !is_target_token(value) || !seen.insert(value.as_str()) {
            return Err(ContentError::ProductionField { field: "targets" });
        }
        tokens.push(value.clone());
    }
    Ok(tokens)
}

fn is_target_token(value: &str) -> bool {
    let bytes = value.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 64
        && bytes
            .iter()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_')
}

fn closed_set<T: Copy + PartialEq>(
    values: &[String],
    empty: EmptyList,
    invalid: ContentError,
    parse: fn(&str) -> Option<T>,
) -> Result<Vec<T>, ContentError> {
    if values.is_empty() {
        return match empty {
            EmptyList::Allow => Ok(Vec::new()),
            EmptyList::Reject(field) => Err(ContentError::ProductionField { field }),
        };
    }
    let mut parsed = Vec::with_capacity(values.len());
    for value in values {
        let Some(item) = parse(value) else {
            return Err(invalid.clone());
        };
        if parsed.contains(&item) {
            return Err(invalid.clone());
        }
        parsed.push(item);
    }
    Ok(parsed)
}

fn require_text_list(
    values: &[String],
    field: &'static str,
    max_chars: usize,
) -> Result<Vec<String>, ContentError> {
    if values.is_empty() {
        return Err(ContentError::ProductionField { field });
    }
    let mut texts = Vec::with_capacity(values.len());
    for value in values {
        texts.push(require_chars(value, field, 1, max_chars)?);
    }
    Ok(texts)
}

fn require_chars(
    value: &str,
    field: &'static str,
    min_chars: usize,
    max_chars: usize,
) -> Result<String, ContentError> {
    let count = value.chars().count();
    if count < min_chars || count > max_chars {
        return Err(ContentError::ProductionField { field });
    }
    Ok(value.to_owned())
}

fn bound_chars(value: &str, field: &'static str, max_chars: usize) -> Result<(), ContentError> {
    if value.chars().count() > max_chars {
        Err(ContentError::ProductionField { field })
    } else {
        Ok(())
    }
}

fn bounded_u8(value: u32, min: u32, max: u32, invalid: ContentError) -> Result<u8, ContentError> {
    let Ok(narrow) = u8::try_from(value) else {
        return Err(invalid);
    };
    if u32::from(narrow) < min || u32::from(narrow) > max {
        return Err(invalid);
    }
    Ok(narrow)
}

fn tempo_part(value: u32) -> Result<u8, ContentError> {
    let Ok(narrow) = u8::try_from(value) else {
        return Err(ContentError::InvalidTempo);
    };
    if narrow > TEMPO_MAX {
        return Err(ContentError::InvalidTempo);
    }
    Ok(narrow)
}

fn parse_region(value: &str) -> Option<Region> {
    Some(match value {
        "head_neck" => Region::HeadNeck,
        "shoulder" => Region::Shoulder,
        "arm" => Region::Arm,
        "torso" => Region::Torso,
        "pelvis" => Region::Pelvis,
        "leg" => Region::Leg,
        "foot" => Region::Foot,
        _ => return None,
    })
}

fn parse_goal(value: &str) -> Option<Goal> {
    Some(match value {
        "strength" => Goal::Strength,
        "mobility" => Goal::Mobility,
        "stability" => Goal::Stability,
        "conditioning" => Goal::Conditioning,
        "control" => Goal::Control,
        _ => return None,
    })
}

fn parse_equipment(value: &str) -> Option<Equipment> {
    Some(match value {
        "bodyweight" => Equipment::Bodyweight,
        "resistance_band" => Equipment::ResistanceBand,
        "dumbbell" => Equipment::Dumbbell,
        "chair" => Equipment::Chair,
        "wall" => Equipment::Wall,
        "towel" => Equipment::Towel,
        "mat" => Equipment::Mat,
        _ => return None,
    })
}

fn parse_position(value: &str) -> Option<Position> {
    Some(match value {
        "standing" => Position::Standing,
        "seated" => Position::Seated,
        "supine" => Position::Supine,
        "side_lying" => Position::SideLying,
        "prone" => Position::Prone,
        "quadruped" => Position::Quadruped,
        _ => return None,
    })
}

fn parse_camera_view(value: &str) -> Option<CameraView> {
    Some(match value {
        "front" => CameraView::Front,
        "side" => CameraView::Side,
        "oblique" => CameraView::Oblique,
        "back" => CameraView::Back,
        _ => return None,
    })
}

fn parse_metric(value: &str) -> Option<TrackedMetric> {
    Some(match value {
        "elbow_angle" => TrackedMetric::ElbowAngle,
        "shoulder_rotation" => TrackedMetric::ShoulderRotation,
        "trunk_rotation" => TrackedMetric::TrunkRotation,
        "repetition_count" => TrackedMetric::RepetitionCount,
        _ => return None,
    })
}

fn parse_license_type(value: &str) -> Result<LicenseType, ContentError> {
    match value {
        "unset" => Ok(LicenseType::Unset),
        "cc0" => Ok(LicenseType::Cc0),
        "cc-by-4.0" => Ok(LicenseType::CcBy40),
        "proprietary" => Ok(LicenseType::Proprietary),
        _ => Err(ContentError::License),
    }
}

fn for_each_edge(
    exercises: &[Exercise],
    mut visit: impl FnMut(LinkKind, &Exercise, &ExerciseId) -> Result<(), ContentError>,
) -> Result<(), ContentError> {
    for exercise in exercises {
        for target in &exercise.progressions {
            visit(LinkKind::Progression, exercise, target)?;
        }
        for target in &exercise.regressions {
            visit(LinkKind::Regression, exercise, target)?;
        }
        for target in &exercise.substitutions {
            visit(LinkKind::Substitution, exercise, target)?;
        }
    }
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WalkColor {
    White,
    Gray,
    Black,
}

fn ensure_acyclic(
    exercises: &[Exercise],
    kind: LinkKind,
    edges: impl Fn(&Exercise) -> &[ExerciseId],
) -> Result<(), ContentError> {
    let mut adjacency: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for exercise in exercises {
        let mut targets: Vec<&str> = edges(exercise).iter().map(ExerciseId::as_str).collect();
        targets.sort_unstable();
        adjacency.insert(exercise.id.as_str(), targets);
    }
    let mut color: BTreeMap<&str, WalkColor> = BTreeMap::new();
    for id in adjacency.keys().copied() {
        color.insert(id, WalkColor::White);
    }

    for start in adjacency.keys().copied() {
        if color.get(start).copied() != Some(WalkColor::White) {
            continue;
        }
        let mut stack: Vec<(&str, usize)> = vec![(start, 0)];
        color.insert(start, WalkColor::Gray);
        let mut path = vec![start];
        while let Some((node, index)) = stack.last().copied() {
            let neighbors = match adjacency.get(node) {
                Some(targets) => targets.as_slice(),
                None => &[],
            };
            if index == neighbors.len() {
                color.insert(node, WalkColor::Black);
                stack.pop();
                path.pop();
                continue;
            }
            if let Some(frame) = stack.last_mut() {
                frame.1 = index + 1;
            }
            let next = neighbors[index];
            let next_color = match color.get(next) {
                Some(color) => *color,
                None => WalkColor::White,
            };
            match next_color {
                WalkColor::Gray => {
                    let mut ids = Vec::new();
                    let mut recording = false;
                    for id in &path {
                        if *id == next {
                            recording = true;
                            ids.clear();
                        }
                        if recording {
                            ids.push((*id).to_owned());
                        }
                    }
                    ids.push((*next).to_owned());
                    return Err(ContentError::GraphCycle { kind, ids });
                }
                WalkColor::White => {
                    color.insert(next, WalkColor::Gray);
                    stack.push((next, 0));
                    path.push(next);
                }
                WalkColor::Black => {}
            }
        }
    }
    Ok(())
}

fn map_serde(error: serde_json::Error) -> ContentError {
    let message = error.to_string();
    if let Some(name) = backtick_after(&message, "missing field `") {
        if let Some(field) = known_field(name) {
            return ContentError::MissingField { name: field };
        }
        return ContentError::InvalidDocument;
    }
    if let Some(name) = backtick_after(&message, "unknown field `") {
        if let Some(field) = bounded_identifier(name) {
            return ContentError::UnknownField { name: field };
        }
        return ContentError::InvalidDocument;
    }
    ContentError::InvalidDocument
}

fn backtick_after<'a>(message: &'a str, prefix: &str) -> Option<&'a str> {
    let start = message.find(prefix)? + prefix.len();
    let rest = message.get(start..)?;
    let end = rest.find('`')?;
    rest.get(..end)
}

fn bounded_identifier(name: &str) -> Option<String> {
    if name.is_empty() || name.len() > 64 {
        return None;
    }
    if name.bytes().all(|byte| byte.is_ascii_graphic()) {
        Some(name.to_owned())
    } else {
        None
    }
}

fn known_field(name: &str) -> Option<&'static str> {
    Some(match name {
        "schema_version" => "schema_version",
        "exercise_id" => "exercise_id",
        "exercise_version" => "exercise_version",
        "name" => "name",
        "regions" => "regions",
        "laterality" => "laterality",
        "targets" => "targets",
        "goals" => "goals",
        "difficulty" => "difficulty",
        "equipment" => "equipment",
        "positions" => "positions",
        "progressions" => "progressions",
        "regressions" => "regressions",
        "substitutions" => "substitutions",
        "contraindications" => "contraindications",
        "camera_views" => "camera_views",
        "tracked_metrics" => "tracked_metrics",
        "default_sets" => "default_sets",
        "default_reps" => "default_reps",
        "tempo" => "tempo",
        "spoken_instructions" => "spoken_instructions",
        "written_instructions" => "written_instructions",
        "common_mistakes" => "common_mistakes",
        "modifications" => "modifications",
        "approval_status" => "approval_status",
        "author" => "author",
        "reviewer" => "reviewer",
        "clinical_approver" => "clinical_approver",
        "approval_date" => "approval_date",
        "last_reviewed" => "last_reviewed",
        "evidence_references" => "evidence_references",
        "populations" => "populations",
        "license" => "license",
        "media" => "media",
        "eccentric" => "eccentric",
        "pause" => "pause",
        "concentric" => "concentric",
        "title" => "title",
        "citation" => "citation",
        "locator" => "locator",
        "license_type" => "license_type",
        "copyright_holder" => "copyright_holder",
        "attribution_notice" => "attribution_notice",
        "talent_release_id" => "talent_release_id",
        "video_mp4" => "video_mp4",
        "start_image_webp" => "start_image_webp",
        "end_image_webp" => "end_image_webp",
        "animation_riv" => "animation_riv",
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;

    fn synthetic_document(id: &str) -> String {
        format!(
            r#"{{
                "schema_version": 1,
                "exercise_id": "{id}",
                "exercise_version": 1,
                "name": "Synthetic label",
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
                "contraindications": ["unreviewed_synthetic"],
                "camera_views": [],
                "tracked_metrics": [],
                "default_sets": 1,
                "default_reps": 1,
                "tempo": {{ "eccentric": 2, "pause": 1, "concentric": 2 }},
                "spoken_instructions": ["Synthetic fixture. Not an exercise prescription."],
                "written_instructions": "Synthetic fixture. Not an exercise prescription.",
                "common_mistakes": ["unreviewed_synthetic"],
                "modifications": ["unreviewed_synthetic"],
                "approval_status": "synthetic",
                "author": "",
                "reviewer": "",
                "clinical_approver": "",
                "approval_date": "",
                "last_reviewed": "",
                "evidence_references": [],
                "populations": ["unreviewed_synthetic"],
                "license": {{
                    "license_type": "unset",
                    "copyright_holder": "",
                    "attribution_notice": "",
                    "talent_release_id": ""
                }},
                "media": {{
                    "video_mp4": null,
                    "start_image_webp": null,
                    "end_image_webp": null,
                    "animation_riv": null
                }}
            }}"#
        )
    }

    fn approved_document(
        approval_date: &str,
        clinical_approver: &str,
        license_type: &str,
    ) -> String {
        format!(
            r#"{{
                "schema_version": 1,
                "exercise_id": "schema-approved",
                "exercise_version": 1,
                "name": "Schema approved shape",
                "regions": ["leg"],
                "laterality": "left",
                "targets": ["synthetic_target"],
                "goals": ["control"],
                "difficulty": 1,
                "equipment": ["chair"],
                "positions": ["seated"],
                "progressions": [],
                "regressions": [],
                "substitutions": [],
                "contraindications": ["schema-constraint"],
                "camera_views": ["front"],
                "tracked_metrics": ["repetition_count"],
                "default_sets": 1,
                "default_reps": 1,
                "tempo": {{ "eccentric": 0, "pause": 0, "concentric": 0 }},
                "spoken_instructions": ["Schema text."],
                "written_instructions": "Schema text.",
                "common_mistakes": ["schema-constraint"],
                "modifications": ["schema-constraint"],
                "approval_status": "approved",
                "author": "schema-author",
                "reviewer": "schema-reviewer",
                "clinical_approver": "{clinical_approver}",
                "approval_date": "{approval_date}",
                "last_reviewed": "2024-02-29",
                "evidence_references": [{{
                    "title": "Schema evidence",
                    "citation": "Schema citation",
                    "locator": "doi:10.0000/schema"
                }}],
                "populations": ["schema-population"],
                "license": {{
                    "license_type": "{license_type}",
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
        )
    }

    #[test]
    fn leap_day_is_a_calendar_date_and_the_non_leap_day_is_not() {
        let accepted =
            parse_exercise(approved_document("2024-02-29", "schema-approver", "cc0").as_bytes())
                .expect("leap day");
        assert_eq!(accepted.approval_date, "2024-02-29");
        let rejected =
            parse_exercise(approved_document("2023-02-29", "schema-approver", "cc0").as_bytes())
                .expect_err("non-leap");
        assert_eq!(rejected, ContentError::Date);
    }

    #[test]
    fn document_errors_do_not_echo_the_body() {
        let raw = br#"{"schema_version":"SENTINEL_BODY_SHOULD_NOT_LEAK"}"#;
        let error = parse_exercise(raw).expect_err("type");
        assert_eq!(error.to_string(), "invalid-document");
        assert!(!error.to_string().contains("SENTINEL"));
    }

    #[test]
    fn missing_and_unknown_fields_are_typed() {
        let missing = parse_exercise(br#"{"exercise_id":"a"}"#).expect_err("missing");
        assert_eq!(
            missing,
            ContentError::MissingField {
                name: "schema_version"
            }
        );
        let mut document = synthetic_document("schema-extra");
        document = document.replacen(
            "\"schema_version\": 1,",
            "\"schema_version\": 1, \"extra_field\": 1,",
            1,
        );
        let unknown = parse_exercise(document.as_bytes()).expect_err("unknown");
        assert_eq!(
            unknown,
            ContentError::UnknownField {
                name: "extra_field".to_owned()
            }
        );
    }

    #[test]
    fn schema_bounds_reject_zero_and_accept_tempo_zero() {
        let mut hard = synthetic_document("schema-bounds");
        hard = hard.replacen("\"difficulty\": 1", "\"difficulty\": 0", 1);
        assert_eq!(
            parse_exercise(hard.as_bytes()).expect_err("difficulty"),
            ContentError::InvalidDifficulty
        );
        let mut sets = synthetic_document("schema-bounds");
        sets = sets.replacen("\"default_sets\": 1", "\"default_sets\": 11", 1);
        assert_eq!(
            parse_exercise(sets.as_bytes()).expect_err("sets"),
            ContentError::InvalidSetsReps
        );
        let zero_tempo = parse_exercise(
            synthetic_document("schema-bounds")
                .replacen("\"eccentric\": 2", "\"eccentric\": 0", 1)
                .as_bytes(),
        )
        .expect("tempo zero");
        assert_eq!(zero_tempo.tempo.eccentric, 0);
    }

    #[test]
    fn duplicate_ids_and_asymmetric_substitutions() {
        let first = parse_exercise(synthetic_document("same-id").as_bytes()).expect("first");
        let second = parse_exercise(synthetic_document("same-id").as_bytes()).expect("second");
        let duplicate = link_library(ExerciseLibrary::from_exercises(vec![first, second]))
            .expect_err("duplicate");
        assert_eq!(
            duplicate,
            ContentError::DuplicateId {
                id: "same-id".to_owned()
            }
        );

        let mut left = synthetic_document("sub-left");
        left = left.replacen(
            "\"substitutions\": []",
            "\"substitutions\": [\"sub-right\"]",
            1,
        );
        let right = synthetic_document("sub-right");
        let library = link_library(ExerciseLibrary::from_exercises(vec![
            parse_exercise(left.as_bytes()).expect("left"),
            parse_exercise(right.as_bytes()).expect("right"),
        ]))
        .expect("asymmetric substitution");
        assert_eq!(library.len(), 2);

        let mut cycle_left = synthetic_document("cycle-left");
        cycle_left = cycle_left.replacen(
            "\"substitutions\": []",
            "\"substitutions\": [\"cycle-right\"]",
            1,
        );
        let mut cycle_right = synthetic_document("cycle-right");
        cycle_right = cycle_right.replacen(
            "\"substitutions\": []",
            "\"substitutions\": [\"cycle-left\"]",
            1,
        );
        link_library(ExerciseLibrary::from_exercises(vec![
            parse_exercise(cycle_left.as_bytes()).expect("cycle left"),
            parse_exercise(cycle_right.as_bytes()).expect("cycle right"),
        ]))
        .expect("substitution cycle");
    }

    #[test]
    fn omitted_media_keys_are_missing_fields() {
        let keys = [
            "video_mp4",
            "start_image_webp",
            "end_image_webp",
            "animation_riv",
        ];
        let inner = r#""video_mp4": null,
                    "start_image_webp": null,
                    "end_image_webp": null,
                    "animation_riv": null"#;
        for omitted in keys {
            let present = keys
                .iter()
                .filter(|key| **key != omitted)
                .map(|key| format!("\"{key}\": null"))
                .collect::<Vec<_>>()
                .join(", ");
            let document = synthetic_document("schema-media").replacen(inner, &present, 1);
            assert!(
                !document.contains(&format!("\"{omitted}\"")),
                "the omitted key must leave the document"
            );
            let error = parse_exercise(document.as_bytes()).expect_err(omitted);
            assert_eq!(
                error,
                ContentError::MissingField { name: omitted },
                "{omitted}"
            );
        }
        let empty = synthetic_document("schema-media").replacen(inner, "", 1);
        assert_eq!(
            parse_exercise(empty.as_bytes()).expect_err("empty media"),
            ContentError::MissingField { name: "video_mp4" }
        );
        parse_exercise(synthetic_document("schema-media").as_bytes()).expect("explicit nulls");
    }

    #[test]
    fn media_inside_the_directory_passes_and_a_linked_directory_cannot_escape() {
        let inside = Scratch::new("inside");
        for name in ["clip.mp4", "start.webp", "end.webp"] {
            fs::write(inside.root.join(name), b"").expect(name);
        }
        let approved = approved_document("2024-02-29", "schema-approver", "cc0");
        fs::write(inside.root.join("schema-approved.json"), &approved).expect("json");
        assert_eq!(
            load_exercise_dir(&inside.root, SyntheticOnly).expect_err("approved stays out"),
            ContentError::SyntheticViolation {
                field: "approval_status"
            }
        );

        let mut escaped = Scratch::new("escape");
        let outside = escaped.path.join("outside");
        fs::create_dir_all(&outside).expect("outside");
        fs::write(outside.join("clip.mp4"), b"").expect("outside clip");
        let link = escaped.root.join("escape");
        escaped.link = Some(link.clone());
        assert!(
            link_directory(&outside, &link),
            "the containment test requires a directory link"
        );
        let document = approved.replacen(
            "\"video_mp4\": \"clip.mp4\"",
            "\"video_mp4\": \"escape/clip.mp4\"",
            1,
        );
        fs::write(escaped.root.join("schema-approved.json"), document).expect("json");
        assert_eq!(
            load_exercise_dir(&escaped.root, SyntheticOnly).expect_err("linked directory"),
            ContentError::MediaPath
        );
    }

    struct Scratch {
        path: PathBuf,
        root: PathBuf,
        link: Option<PathBuf>,
    }

    impl Scratch {
        fn new(label: &str) -> Self {
            use std::sync::atomic::{AtomicU64, Ordering};
            static SEQUENCE: AtomicU64 = AtomicU64::new(0);
            let sequence = SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "hmm-content-{}-{}-{label}",
                std::process::id(),
                sequence
            ));
            let _ = fs::remove_dir_all(&path);
            let root = path.join("exercises");
            fs::create_dir_all(&root).expect("scratch");
            Self {
                path,
                root,
                link: None,
            }
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            if let Some(link) = self.link.take() {
                let _ = fs::remove_dir(&link);
            }
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn link_directory(target: &Path, link: &Path) -> bool {
        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(target, link).is_ok()
        }
        #[cfg(windows)]
        {
            if std::os::windows::fs::symlink_dir(target, link).is_ok() {
                return true;
            }
            // `mklink` is a cmd builtin. Pass the words separately so a path is not quoted twice.
            let output = std::process::Command::new("cmd")
                .arg("/c")
                .arg("mklink")
                .arg("/J")
                .arg(link)
                .arg(target)
                .output();
            match output {
                Ok(output) if output.status.success() => true,
                Ok(output) => {
                    eprintln!(
                        "mklink failed: {}{}",
                        String::from_utf8_lossy(&output.stdout),
                        String::from_utf8_lossy(&output.stderr)
                    );
                    false
                }
                Err(error) => {
                    eprintln!("mklink spawn failed: {error}");
                    false
                }
            }
        }
    }
}
