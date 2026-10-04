//! Versioned safety rules and an offline decision engine.
//!
//! The committed rule file is a schema fixture. It is not a clinician-approved instrument.

mod error;
mod evaluate;
mod model;

pub use error::SafetyError;
pub use evaluate::{
    classify, emergency_display, evaluate_interrupt, load_rule_dir, parse_rule_set, refresh,
    screen_exercise,
};
pub use helpmemove_domain::DomainInstant;
pub use model::{
    ActiveIssue, Classification, DeniedReason, Eligibility, Escalation, InterruptAction,
    InterruptDecision, RuleLibrary, RuleSet, RuleSetId, ScreenDecision, SyntheticOnly, TriageLevel,
};
