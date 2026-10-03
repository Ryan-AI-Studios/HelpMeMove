use helpmemove_domain::{
    BRIDGE_VERSION, Confidence, DomainError, DomainInstant, Laterality, SubjectId,
    elapsed_millis as domain_elapsed_millis, length_mm_to_inch_thousandths,
    observe_cancel as domain_observe_cancel, require_version as domain_require_version,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeError {
    InvalidSubjectId,
    InvalidLaterality,
    InvalidConfidence,
    InvalidLength,
    ClockWentBackwards,
    VersionMismatch,
    Cancelled,
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
