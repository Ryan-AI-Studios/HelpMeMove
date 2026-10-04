//! Versioned exercise documents, the synthetic assessment fixture, and a library validator.
//!
//! The committed fixtures are schema examples. They are not a clinician-approved library.

mod assessment;
mod error;
mod model;
mod validate;

pub use assessment::{AssessmentInstrument, MovementRating, parse_assessment_instrument};
pub use error::{ContentError, LinkKind};
pub use model::{
    ApprovalStatus, CameraView, Equipment, EvidenceReference, Exercise, ExerciseId,
    ExerciseLibrary, Goal, License, LicenseType, Media, Position, Region, SyntheticOnly, Tempo,
    TrackedMetric,
};
pub use validate::{check_media, link_library, load_exercise_dir, parse_exercise};
