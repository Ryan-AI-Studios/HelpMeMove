//! Typed exercise values. Closed tokens stay strings until validation accepts them.

use helpmemove_domain::Laterality;

/// Directory loader mode. The committed tree is synthetic and rejects `approved`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SyntheticOnly;

/// Exercise identifier. Underscores are allowed. This is not a [`helpmemove_domain::SubjectId`].
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ExerciseId(String);

impl ExerciseId {
    pub(crate) fn parse(raw: &str) -> Result<Self, super::ContentError> {
        if is_exercise_id(raw) {
            Ok(Self(raw.to_owned()))
        } else {
            Err(super::ContentError::InvalidId)
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

pub(crate) fn is_exercise_id(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    if bytes.is_empty() || bytes.len() > 64 {
        return false;
    }
    let first = bytes[0];
    if !first.is_ascii_lowercase() && !first.is_ascii_digit() {
        return false;
    }
    bytes[1..].iter().all(|byte| {
        byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_' || *byte == b'-'
    })
}

/// Product spec section 5 region group. Body-map selector ids are not accepted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Region {
    HeadNeck,
    Shoulder,
    Arm,
    Torso,
    Pelvis,
    Leg,
    Foot,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Goal {
    Strength,
    Mobility,
    Stability,
    Conditioning,
    Control,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Equipment {
    Bodyweight,
    ResistanceBand,
    Dumbbell,
    Chair,
    Wall,
    Towel,
    Mat,
}

impl Region {
    /// Closed content token. Unknown strings, including joint names, are `None`.
    pub fn parse(raw: &str) -> Option<Self> {
        Some(match raw {
            "head_neck" => Self::HeadNeck,
            "shoulder" => Self::Shoulder,
            "arm" => Self::Arm,
            "torso" => Self::Torso,
            "pelvis" => Self::Pelvis,
            "leg" => Self::Leg,
            "foot" => Self::Foot,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::HeadNeck => "head_neck",
            Self::Shoulder => "shoulder",
            Self::Arm => "arm",
            Self::Torso => "torso",
            Self::Pelvis => "pelvis",
            Self::Leg => "leg",
            Self::Foot => "foot",
        }
    }
}

impl Goal {
    pub fn parse(raw: &str) -> Option<Self> {
        Some(match raw {
            "strength" => Self::Strength,
            "mobility" => Self::Mobility,
            "stability" => Self::Stability,
            "conditioning" => Self::Conditioning,
            "control" => Self::Control,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Strength => "strength",
            Self::Mobility => "mobility",
            Self::Stability => "stability",
            Self::Conditioning => "conditioning",
            Self::Control => "control",
        }
    }
}

impl Equipment {
    pub fn parse(raw: &str) -> Option<Self> {
        Some(match raw {
            "bodyweight" => Self::Bodyweight,
            "resistance_band" => Self::ResistanceBand,
            "dumbbell" => Self::Dumbbell,
            "chair" => Self::Chair,
            "wall" => Self::Wall,
            "towel" => Self::Towel,
            "mat" => Self::Mat,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Bodyweight => "bodyweight",
            Self::ResistanceBand => "resistance_band",
            Self::Dumbbell => "dumbbell",
            Self::Chair => "chair",
            Self::Wall => "wall",
            Self::Towel => "towel",
            Self::Mat => "mat",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Position {
    Standing,
    Seated,
    Supine,
    SideLying,
    Prone,
    Quadruped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CameraView {
    Front,
    Side,
    Oblique,
    Back,
}

/// Schema label for a later tracker. Not a measurement.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrackedMetric {
    ElbowAngle,
    ShoulderRotation,
    TrunkRotation,
    RepetitionCount,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApprovalStatus {
    Synthetic,
    Approved,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LicenseType {
    Unset,
    Cc0,
    CcBy40,
    Proprietary,
}

/// Eccentric, pause, and concentric counts. Each bound is a schema limit, not a dose.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tempo {
    pub eccentric: u8,
    pub pause: u8,
    pub concentric: u8,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EvidenceReference {
    pub title: String,
    pub citation: String,
    pub locator: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct License {
    pub license_type: LicenseType,
    pub copyright_holder: String,
    pub attribution_notice: String,
    pub talent_release_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Media {
    pub video_mp4: Option<String>,
    pub start_image_webp: Option<String>,
    pub end_image_webp: Option<String>,
    pub animation_riv: Option<String>,
}

/// One validated exercise document. Graph membership is checked separately.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Exercise {
    pub id: ExerciseId,
    pub name: String,
    pub regions: Vec<Region>,
    pub laterality: Laterality,
    pub targets: Vec<String>,
    pub goals: Vec<Goal>,
    pub difficulty: u8,
    pub equipment: Vec<Equipment>,
    pub positions: Vec<Position>,
    pub progressions: Vec<ExerciseId>,
    pub regressions: Vec<ExerciseId>,
    pub substitutions: Vec<ExerciseId>,
    pub contraindications: Vec<String>,
    pub camera_views: Vec<CameraView>,
    pub tracked_metrics: Vec<TrackedMetric>,
    pub default_sets: u8,
    pub default_reps: u8,
    pub tempo: Tempo,
    pub spoken_instructions: Vec<String>,
    pub written_instructions: String,
    pub common_mistakes: Vec<String>,
    pub modifications: Vec<String>,
    pub approval_status: ApprovalStatus,
    pub author: String,
    pub reviewer: String,
    pub clinical_approver: String,
    pub approval_date: String,
    pub last_reviewed: String,
    pub evidence_references: Vec<EvidenceReference>,
    pub populations: Vec<String>,
    pub license: License,
    pub media: Media,
}

/// Exercises read from one directory. Call [`crate::link_library`] before treating links as resolved.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExerciseLibrary {
    exercises: Vec<Exercise>,
}

impl ExerciseLibrary {
    pub(crate) fn from_exercises(exercises: Vec<Exercise>) -> Self {
        Self { exercises }
    }

    pub(crate) fn into_exercises(self) -> Vec<Exercise> {
        self.exercises
    }

    pub fn len(&self) -> usize {
        self.exercises.len()
    }

    pub fn is_empty(&self) -> bool {
        self.exercises.is_empty()
    }

    pub fn exercises(&self) -> &[Exercise] {
        &self.exercises
    }
}
