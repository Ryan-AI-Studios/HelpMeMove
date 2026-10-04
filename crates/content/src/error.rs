//! Typed content failures. Display text is a stable code and never the document body.

use std::fmt;

/// Which exercise-to-exercise edge failed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LinkKind {
    Progression,
    Regression,
    Substitution,
}

impl LinkKind {
    fn as_str(self) -> &'static str {
        match self {
            Self::Progression => "progression",
            Self::Regression => "regression",
            Self::Substitution => "substitution",
        }
    }
}

impl fmt::Display for LinkKind {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// A document, graph, media, or I/O failure from the content validator.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContentError {
    SchemaVersion,
    ExerciseVersion,
    InvalidId,
    DuplicateId {
        id: String,
    },
    MissingField {
        name: &'static str,
    },
    UnknownField {
        name: String,
    },
    InvalidLaterality,
    InvalidRegion,
    InvalidEquipment,
    InvalidGoal,
    InvalidPosition,
    InvalidCameraView,
    InvalidMetric,
    InvalidTempo,
    InvalidDifficulty,
    InvalidSetsReps,
    OrphanLink {
        kind: LinkKind,
        from: String,
        to: String,
    },
    GraphCycle {
        kind: LinkKind,
        ids: Vec<String>,
    },
    ContradictoryLink {
        from: String,
        id: String,
    },
    SelfLink {
        kind: LinkKind,
        id: String,
    },
    SyntheticViolation {
        field: &'static str,
    },
    ProductionField {
        field: &'static str,
    },
    MediaPath,
    MediaExtension,
    MediaMissing,
    ApprovalStatus,
    License,
    Date,
    Io,
    InvalidDocument,
    InvalidSession,
    SessionClosed,
    ClockWentBackwards,
}

impl ContentError {
    pub fn code(&self) -> String {
        match self {
            Self::SchemaVersion => "schema-version".to_owned(),
            Self::ExerciseVersion => "exercise-version".to_owned(),
            Self::InvalidId => "invalid-id".to_owned(),
            Self::DuplicateId { id } => format!("duplicate-id {id}"),
            Self::MissingField { name } => format!("missing-field {name}"),
            Self::UnknownField { name } => format!("unknown-field {name}"),
            Self::InvalidLaterality => "invalid-laterality".to_owned(),
            Self::InvalidRegion => "invalid-region".to_owned(),
            Self::InvalidEquipment => "invalid-equipment".to_owned(),
            Self::InvalidGoal => "invalid-goal".to_owned(),
            Self::InvalidPosition => "invalid-position".to_owned(),
            Self::InvalidCameraView => "invalid-camera-view".to_owned(),
            Self::InvalidMetric => "invalid-metric".to_owned(),
            Self::InvalidTempo => "invalid-tempo".to_owned(),
            Self::InvalidDifficulty => "invalid-difficulty".to_owned(),
            Self::InvalidSetsReps => "invalid-sets-reps".to_owned(),
            Self::OrphanLink { kind, from, to } => format!("orphan-link {kind} {from} {to}"),
            Self::GraphCycle { kind, ids } => {
                let mut code = format!("graph-cycle {kind}");
                for id in ids {
                    code.push(' ');
                    code.push_str(id);
                }
                code
            }
            Self::ContradictoryLink { from, id } => format!("contradictory-link {from} {id}"),
            Self::SelfLink { kind, id } => format!("self-link {kind} {id}"),
            Self::SyntheticViolation { field } => format!("synthetic-violation {field}"),
            Self::ProductionField { field } => format!("production-field {field}"),
            Self::MediaPath => "media-path".to_owned(),
            Self::MediaExtension => "media-extension".to_owned(),
            Self::MediaMissing => "media-missing".to_owned(),
            Self::ApprovalStatus => "approval-status".to_owned(),
            Self::License => "license".to_owned(),
            Self::Date => "date".to_owned(),
            Self::Io => "io".to_owned(),
            Self::InvalidDocument => "invalid-document".to_owned(),
            Self::InvalidSession => "invalid-session".to_owned(),
            Self::SessionClosed => "session-closed".to_owned(),
            Self::ClockWentBackwards => "clock-went-backwards".to_owned(),
        }
    }
}

impl fmt::Display for ContentError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.code())
    }
}

impl std::error::Error for ContentError {}
