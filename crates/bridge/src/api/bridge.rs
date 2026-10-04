use helpmemove_content::{Equipment, Goal, Region};
use helpmemove_domain::{
    BRIDGE_VERSION, Confidence, DomainError, DomainInstant, Laterality, SubjectId,
    elapsed_millis as domain_elapsed_millis, length_mm_to_inch_thousandths,
    observe_cancel as domain_observe_cancel, require_version as domain_require_version,
};
use helpmemove_safety::{
    Classification, Eligibility, Escalation, SafetyError, TriageLevel, classify,
    emergency_display as safety_emergency_display, parse_rule_set,
};

const COMMITTED_RULE: &str = include_str!("../../../../content/rules/syn-safety-core.json");

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeError {
    InvalidSubjectId,
    InvalidLaterality,
    InvalidConfidence,
    InvalidLength,
    ClockWentBackwards,
    VersionMismatch,
    Cancelled,
    InvalidRegion,
    InvalidGoal,
    InvalidEquipment,
}

impl BridgeError {
    #[flutter_rust_bridge::frb(ignore)]
    pub fn code(self) -> &'static str {
        match self {
            Self::InvalidSubjectId => "invalid-subject-id",
            Self::InvalidLaterality => "invalid-laterality",
            Self::InvalidConfidence => "invalid-confidence",
            Self::InvalidLength => "invalid-length",
            Self::ClockWentBackwards => "clock-went-backwards",
            Self::VersionMismatch => "version-mismatch",
            Self::Cancelled => "cancelled",
            Self::InvalidRegion => "invalid-region",
            Self::InvalidGoal => "invalid-goal",
            Self::InvalidEquipment => "invalid-equipment",
        }
    }
}

impl From<DomainError> for BridgeError {
    fn from(error: DomainError) -> Self {
        match error {
            DomainError::InvalidSubjectId => Self::InvalidSubjectId,
            DomainError::InvalidLaterality => Self::InvalidLaterality,
            DomainError::InvalidConfidence => Self::InvalidConfidence,
            DomainError::InvalidLength => Self::InvalidLength,
            DomainError::ClockWentBackwards => Self::ClockWentBackwards,
            DomainError::VersionMismatch => Self::VersionMismatch,
            DomainError::Cancelled => Self::Cancelled,
        }
    }
}

impl std::fmt::Display for BridgeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.code())
    }
}

impl std::error::Error for BridgeError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IntakeVocabulary {
    pub regions: Vec<String>,
    pub goals: Vec<String>,
    pub equipment: Vec<String>,
    pub lateralities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafetyAnswer {
    pub token: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SafetyView {
    pub code: String,
    pub level: String,
    pub escalation: String,
    pub permits_ordinary_generation: bool,
    pub emergency_display: String,
    pub emergency_code: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn bridge_version() -> String {
    BRIDGE_VERSION.to_owned()
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_subject(raw: String) -> Result<String, BridgeError> {
    let subject = SubjectId::parse(&raw)?;
    Ok(subject.as_str().to_owned())
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_laterality(raw: String) -> Result<String, BridgeError> {
    Ok(Laterality::parse(&raw)?.as_str().to_owned())
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_confidence(value: f64) -> Result<f64, BridgeError> {
    Ok(Confidence::parse(value)?.value())
}

#[flutter_rust_bridge::frb(sync)]
pub fn convert_length_mm_to_inch_thousandths(millimeters: u32) -> Result<u32, BridgeError> {
    Ok(length_mm_to_inch_thousandths(millimeters)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn elapsed_millis(earlier: i64, later: i64) -> Result<i64, BridgeError> {
    Ok(domain_elapsed_millis(
        DomainInstant::from_unix_millis(earlier),
        DomainInstant::from_unix_millis(later),
    )?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn require_version(caller: String) -> Result<(), BridgeError> {
    Ok(domain_require_version(&caller)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn observe_cancel(cancelled: bool) -> Result<(), BridgeError> {
    Ok(domain_observe_cancel(cancelled)?)
}

#[flutter_rust_bridge::frb(sync)]
pub fn probe_contained_panic() -> String {
    panic!("helpmemove-bridge-probe");
}

#[flutter_rust_bridge::frb(sync)]
pub fn intake_vocabulary() -> IntakeVocabulary {
    IntakeVocabulary {
        regions: sorted([
            Region::HeadNeck.as_str(),
            Region::Shoulder.as_str(),
            Region::Arm.as_str(),
            Region::Torso.as_str(),
            Region::Pelvis.as_str(),
            Region::Leg.as_str(),
            Region::Foot.as_str(),
        ]),
        goals: sorted([
            Goal::Strength.as_str(),
            Goal::Mobility.as_str(),
            Goal::Stability.as_str(),
            Goal::Conditioning.as_str(),
            Goal::Control.as_str(),
        ]),
        equipment: sorted([
            Equipment::Bodyweight.as_str(),
            Equipment::ResistanceBand.as_str(),
            Equipment::Dumbbell.as_str(),
            Equipment::Chair.as_str(),
            Equipment::Wall.as_str(),
            Equipment::Towel.as_str(),
            Equipment::Mat.as_str(),
        ]),
        lateralities: sorted([
            Laterality::Left.as_str(),
            Laterality::Right.as_str(),
            Laterality::Bilateral.as_str(),
        ]),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_region(raw: String) -> Result<String, BridgeError> {
    match Region::parse(&raw) {
        Some(region) => Ok(region.as_str().to_owned()),
        None => Err(BridgeError::InvalidRegion),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_goal(raw: String) -> Result<String, BridgeError> {
    match Goal::parse(&raw) {
        Some(goal) => Ok(goal.as_str().to_owned()),
        None => Err(BridgeError::InvalidGoal),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn accept_equipment(raw: String) -> Result<String, BridgeError> {
    match Equipment::parse(&raw) {
        Some(equipment) => Ok(equipment.as_str().to_owned()),
        None => Err(BridgeError::InvalidEquipment),
    }
}

/// Classify the committed synthetic rule. The note and severity are not parameters.
#[flutter_rust_bridge::frb(sync)]
pub fn classify_committed_rule(
    answers: Vec<SafetyAnswer>,
    now_unix_millis: i64,
    triggers: Vec<String>,
    emergency_region: String,
) -> SafetyView {
    let now = DomainInstant::from_unix_millis(now_unix_millis);
    match parse_rule_set(COMMITTED_RULE.as_bytes()) {
        Ok(rule) => {
            let owned: Vec<(String, String)> = answers
                .iter()
                .map(|answer| (answer.token.clone(), answer.value.clone()))
                .collect();
            let pairs: Vec<(&str, &str)> = owned
                .iter()
                .map(|(token, value)| (token.as_str(), value.as_str()))
                .collect();
            let trigger_refs: Vec<&str> = triggers.iter().map(String::as_str).collect();
            let classified = classify(&rule, &pairs, now, &trigger_refs);
            let (code, level, escalation, permits) = decision_fields(classified);
            let (emergency_display, emergency_code) = emergency_fields(&rule, &emergency_region);
            SafetyView {
                code,
                level,
                escalation,
                permits_ordinary_generation: permits,
                emergency_display,
                emergency_code,
            }
        }
        Err(error) => SafetyView {
            code: error.code(),
            level: String::new(),
            escalation: String::new(),
            permits_ordinary_generation: false,
            emergency_display: String::new(),
            emergency_code: String::new(),
        },
    }
}

fn sorted<const N: usize>(values: [&'static str; N]) -> Vec<String> {
    let mut values = values;
    values.sort_unstable();
    values.into_iter().map(str::to_owned).collect()
}

fn decision_fields(result: Result<Classification, SafetyError>) -> (String, String, String, bool) {
    match result {
        Ok(classification) if classification.eligibility == Eligibility::Ineligible => (
            "ineligible".to_owned(),
            String::new(),
            escalation_name(classification.escalation),
            false,
        ),
        Ok(classification) => {
            let code = match classification.level {
                Some(level) => triage_name(level).to_owned(),
                None => "unmatched".to_owned(),
            };
            let level = match classification.level {
                Some(level) => triage_name(level).to_owned(),
                None => String::new(),
            };
            (
                code,
                level,
                escalation_name(classification.escalation),
                classification.permits_ordinary_generation,
            )
        }
        Err(error) => (error.code(), String::new(), String::new(), false),
    }
}

fn emergency_fields(rule: &helpmemove_safety::RuleSet, region: &str) -> (String, String) {
    match safety_emergency_display(rule, region) {
        Ok(display) => (display.to_owned(), "ok".to_owned()),
        Err(SafetyError::UnknownRegion) => (String::new(), "unknown-region".to_owned()),
        Err(SafetyError::Region) => (String::new(), "region".to_owned()),
        Err(error) => (String::new(), error.code()),
    }
}

fn triage_name(level: TriageLevel) -> &'static str {
    match level {
        TriageLevel::Green => "green",
        TriageLevel::Yellow => "yellow",
        TriageLevel::Orange => "orange",
        TriageLevel::Red => "red",
    }
}

fn escalation_name(escalation: Escalation) -> String {
    match escalation {
        Escalation::None => "none",
        Escalation::Evaluation => "evaluation",
        Escalation::Emergency => "emergency",
    }
    .to_owned()
}

#[cfg(test)]
mod tests {
    use super::probe_contained_panic;

    #[test]
    fn probe_panic_is_caught() {
        let caught = std::panic::catch_unwind(|| {
            let _unused = probe_contained_panic();
        });
        assert!(caught.is_err());
    }
}
