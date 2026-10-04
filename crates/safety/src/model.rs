//! Typed safety values. Closed tokens stay strings until validation accepts them.

use helpmemove_domain::DomainInstant;

/// Directory loader mode. The committed tree is synthetic and rejects `approved`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SyntheticOnly;

/// Rule-set identifier. Underscores are allowed. This is not a subject id.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct RuleSetId(String);

impl RuleSetId {
    pub(crate) fn parse(raw: &str) -> Result<Self, super::SafetyError> {
        if is_rule_id(raw) {
            Ok(Self(raw.to_owned()))
        } else {
            Err(super::SafetyError::InvalidId)
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

pub(crate) fn is_rule_id(raw: &str) -> bool {
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

pub(crate) fn is_token(raw: &str) -> bool {
    let bytes = raw.as_bytes();
    !bytes.is_empty()
        && bytes.len() <= 64
        && bytes
            .iter()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'_')
}

/// Product spec section 7 outcome. Declaration order is least to most restrictive.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum TriageLevel {
    Green,
    Yellow,
    Orange,
    Red,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Eligibility {
    Eligible,
    Ineligible,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Escalation {
    None,
    Evaluation,
    Emergency,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InterruptAction {
    Continue,
    Reduce,
    Pause,
    Abort,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InterruptDecision {
    pub action: InterruptAction,
    pub fail_closed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ScreenDecision {
    Eligible,
    Denied(DeniedReason),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DeniedReason {
    GenerationDenied,
    Contraindicated,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActiveIssue {
    pub id: String,
    pub restrictions: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ApprovalKind {
    Synthetic,
    Approved,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MatchRow {
    pub token: String,
    pub equals: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TriageRow {
    pub token: String,
    pub equals: String,
    pub level: TriageLevel,
    pub restrictions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct InterruptRow {
    pub token: String,
    pub action: InterruptAction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct EmergencyRow {
    pub region: String,
    pub display: String,
}

/// One validated rule document.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleSet {
    pub(crate) id: RuleSetId,
    pub(crate) version: u32,
    pub(crate) approval: ApprovalKind,
    pub(crate) valid_for_days: u32,
    pub(crate) rescreen_tokens: Vec<String>,
    pub(crate) eligibility: Vec<MatchRow>,
    pub(crate) triage: Vec<TriageRow>,
    pub(crate) interrupts: Vec<InterruptRow>,
    pub(crate) emergency_rows: Vec<EmergencyRow>,
}

impl RuleSet {
    pub fn id(&self) -> &RuleSetId {
        &self.id
    }

    pub fn version(&self) -> u32 {
        self.version
    }
}

/// Rule documents read from one directory.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuleLibrary {
    rules: Vec<RuleSet>,
}

impl RuleLibrary {
    pub(crate) fn from_rules(rules: Vec<RuleSet>) -> Self {
        Self { rules }
    }

    pub fn len(&self) -> usize {
        self.rules.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rules.is_empty()
    }

    pub fn rules(&self) -> &[RuleSet] {
        &self.rules
    }
}

/// One classification. `valid_for_days` on the rule is not a clinical cadence.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Classification {
    pub rule_set_id: RuleSetId,
    pub rule_set_version: u32,
    pub eligibility: Eligibility,
    pub level: Option<TriageLevel>,
    pub restrictions: Vec<String>,
    pub permits_ordinary_generation: bool,
    pub permits_progression: bool,
    pub escalation: Escalation,
    pub classified_at: DomainInstant,
    pub screening_required: bool,
}
