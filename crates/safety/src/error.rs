//! Typed safety failures. Display text is a stable code and never the document or answers.

use std::fmt;

/// A document, decision, or I/O failure from the safety engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SafetyError {
    SchemaVersion,
    RuleVersion,
    InvalidId,
    InvalidToken,
    MissingField { name: &'static str },
    UnknownField { name: String },
    ApprovalStatus,
    SyntheticViolation { field: &'static str },
    ProductionField { field: &'static str },
    Date,
    Limit,
    Unmatched,
    UnknownAnswer,
    Duplicate,
    Clock,
    UnknownRegion,
    Region,
    Io,
    InvalidDocument,
}

impl SafetyError {
    pub fn code(&self) -> String {
        match self {
            Self::SchemaVersion => "schema-version".to_owned(),
            Self::RuleVersion => "rule-version".to_owned(),
            Self::InvalidId => "invalid-id".to_owned(),
            Self::InvalidToken => "invalid-token".to_owned(),
            Self::MissingField { name } => format!("missing-field {name}"),
            Self::UnknownField { name } => format!("unknown-field {name}"),
            Self::ApprovalStatus => "approval-status".to_owned(),
            Self::SyntheticViolation { field } => format!("synthetic-violation {field}"),
            Self::ProductionField { field } => format!("production-field {field}"),
            Self::Date => "date".to_owned(),
            Self::Limit => "limit".to_owned(),
            Self::Unmatched => "unmatched".to_owned(),
            Self::UnknownAnswer => "unknown-answer".to_owned(),
            Self::Duplicate => "duplicate".to_owned(),
            Self::Clock => "clock".to_owned(),
            Self::UnknownRegion => "unknown-region".to_owned(),
            Self::Region => "region".to_owned(),
            Self::Io => "io".to_owned(),
            Self::InvalidDocument => "invalid-document".to_owned(),
        }
    }
}

impl fmt::Display for SafetyError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.code())
    }
}

impl std::error::Error for SafetyError {}
