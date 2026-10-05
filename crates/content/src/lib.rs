//! Versioned exercise documents, synthetic assessment and program fixtures, and a library validator.
//!
//! The committed fixtures are schema examples. They are not a clinician-approved library.

mod adaptation;
mod assessment;
mod error;
mod model;
mod program;
mod session;
mod validate;

pub use adaptation::{
    AdaptationDecision, AdaptationError, AdaptationRule, ReadinessDocument, Soreness,
    decide_adaptation, parse_adaptation_rule, parse_readiness, read_intake_safety_answers,
};

pub use assessment::{AssessmentInstrument, MovementRating, parse_assessment_instrument};
pub use error::{ContentError, LinkKind};
pub use model::{
    ApprovalStatus, CameraView, Equipment, EvidenceReference, Exercise, ExerciseId,
    ExerciseLibrary, Goal, License, LicenseType, Media, Position, Region, SyntheticOnly, Tempo,
    TrackedMetric,
};
pub use program::{
    AssessedArea, ProgramIntake, ProgramRule, StartingExercise, parse_program_rule,
    read_program_assessment, read_program_intake, render_starting_program,
};
pub use session::{
    Session, SessionEvent, SessionExercise, SessionState, Symptom, apply_session_event,
    open_session, parse_session, read_session_event, render_session,
};
pub use validate::{check_media, link_library, load_exercise_dir, parse_exercise};
