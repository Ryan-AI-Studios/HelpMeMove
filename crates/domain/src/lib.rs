//! Pure value objects for the bridge smoke. No I/O, clock, or FFI.

mod pose;

pub use pose::{PoseFrame, PosePoint, normalize_pose_frame};

/// Opaque fixture token. Not a person, account, or stored subject.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubjectId(String);

impl SubjectId {
    pub fn parse(raw: &str) -> Result<Self, DomainError> {
        let bytes = raw.as_bytes();
        if bytes.is_empty() || bytes.len() > 64 {
            return Err(DomainError::InvalidSubjectId);
        }
        let allowed = bytes
            .iter()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || *byte == b'-');
        if !allowed {
            return Err(DomainError::InvalidSubjectId);
        }
        Ok(Self(raw.to_owned()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Laterality {
    Left,
    Right,
    Bilateral,
}

impl Laterality {
    pub fn parse(raw: &str) -> Result<Self, DomainError> {
        match raw {
            "left" => Ok(Self::Left),
            "right" => Ok(Self::Right),
            "bilateral" => Ok(Self::Bilateral),
            _ => Err(DomainError::InvalidLaterality),
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Left => "left",
            Self::Right => "right",
            Self::Bilateral => "bilateral",
        }
    }
}

/// Unit interval for this value object. Not a clinical cutoff.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Confidence(f64);

impl Confidence {
    pub fn parse(value: f64) -> Result<Self, DomainError> {
        if value.is_finite() && (0.0..=1.0).contains(&value) {
            Ok(Self(value))
        } else {
            Err(DomainError::InvalidConfidence)
        }
    }

    pub fn value(self) -> f64 {
        self.0
    }
}

/// Millimeters as a unit primitive. The parse bound is a smoke limit, not a body measurement.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LengthMm(u32);

impl LengthMm {
    pub const MAX_MILLIMETERS: u32 = 10_000_000;

    pub fn parse(millimeters: u32) -> Result<Self, DomainError> {
        if millimeters > Self::MAX_MILLIMETERS {
            return Err(DomainError::InvalidLength);
        }
        Ok(Self(millimeters))
    }

    pub fn millimeters(self) -> u32 {
        self.0
    }
}

/// Caller-supplied Unix milliseconds. This type does not read the system clock.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DomainInstant(i64);

impl DomainInstant {
    pub fn from_unix_millis(millis: i64) -> Self {
        Self(millis)
    }

    pub fn unix_millis(self) -> i64 {
        self.0
    }
}

pub const BRIDGE_VERSION: &str = "helpmemove-bridge-1";

pub fn length_mm_to_inch_thousandths(millimeters: u32) -> Result<u32, DomainError> {
    let length = LengthMm::parse(millimeters)?;
    let thousandths = u64::from(length.millimeters()) * 10_000 / 254;
    u32::try_from(thousandths).map_err(|_| DomainError::InvalidLength)
}

pub fn elapsed_millis(earlier: DomainInstant, later: DomainInstant) -> Result<i64, DomainError> {
    if later.unix_millis() < earlier.unix_millis() {
        return Err(DomainError::ClockWentBackwards);
    }
    // A difference wider than i64 fails closed instead of panicking.
    later
        .unix_millis()
        .checked_sub(earlier.unix_millis())
        .ok_or(DomainError::ClockWentBackwards)
}

pub fn require_version(caller: &str) -> Result<(), DomainError> {
    if caller == BRIDGE_VERSION {
        Ok(())
    } else {
        Err(DomainError::VersionMismatch)
    }
}

pub fn observe_cancel(cancelled: bool) -> Result<(), DomainError> {
    if cancelled {
        Err(DomainError::Cancelled)
    } else {
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DomainError {
    InvalidSubjectId,
    InvalidLaterality,
    InvalidConfidence,
    InvalidLength,
    ClockWentBackwards,
    VersionMismatch,
    Cancelled,
    InvalidPoseFrame,
}

impl DomainError {
    pub fn code(self) -> &'static str {
        match self {
            Self::InvalidSubjectId => "invalid-subject-id",
            Self::InvalidLaterality => "invalid-laterality",
            Self::InvalidConfidence => "invalid-confidence",
            Self::InvalidLength => "invalid-length",
            Self::ClockWentBackwards => "clock-went-backwards",
            Self::VersionMismatch => "version-mismatch",
            Self::Cancelled => "cancelled",
            Self::InvalidPoseFrame => "invalid-pose-frame",
        }
    }
}

impl std::fmt::Display for DomainError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(self.code())
    }
}

impl std::error::Error for DomainError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn subject_smoke_token_is_accepted() {
        let id = SubjectId::parse("subject-smoke-1").expect("fixture");
        assert_eq!(id.as_str(), "subject-smoke-1");
    }

    #[test]
    fn subject_bounds_and_alphabet_are_rejected() {
        assert_eq!(
            SubjectId::parse("").unwrap_err().code(),
            "invalid-subject-id"
        );
        assert!(SubjectId::parse(&"a".repeat(65)).is_err());
        assert!(SubjectId::parse(&"a".repeat(64)).is_ok());
        assert!(SubjectId::parse("Left").is_err());
        assert!(SubjectId::parse("has space").is_err());
    }

    #[test]
    fn laterality_is_case_sensitive() {
        assert_eq!(Laterality::parse("left").expect("left"), Laterality::Left);
        assert_eq!(Laterality::parse("right").expect("right").as_str(), "right");
        assert_eq!(
            Laterality::parse("bilateral").expect("bilateral"),
            Laterality::Bilateral
        );
        assert_eq!(
            Laterality::parse("Left").unwrap_err().code(),
            "invalid-laterality"
        );
    }

    #[test]
    fn confidence_accepts_the_unit_interval_only() {
        assert_eq!(Confidence::parse(0.0).expect("zero").value(), 0.0);
        assert_eq!(Confidence::parse(1.0).expect("one").value(), 1.0);
        assert_eq!(
            Confidence::parse(f64::NAN).unwrap_err().code(),
            "invalid-confidence"
        );
        assert!(Confidence::parse(1.1).is_err());
        assert!(Confidence::parse(f64::INFINITY).is_err());
        assert!(Confidence::parse(-0.1).is_err());
    }

    #[test]
    fn length_converts_one_inch_and_rejects_the_smoke_bound() {
        assert_eq!(length_mm_to_inch_thousandths(254).expect("inch"), 10_000);
        assert_eq!(length_mm_to_inch_thousandths(0).expect("zero"), 0);
        assert_eq!(
            length_mm_to_inch_thousandths(10_000_001)
                .unwrap_err()
                .code(),
            "invalid-length"
        );
        assert!(length_mm_to_inch_thousandths(10_000_000).is_ok());
    }

    #[test]
    fn elapsed_uses_the_caller_clock() {
        let earlier = DomainInstant::from_unix_millis(10);
        let later = DomainInstant::from_unix_millis(25);
        assert_eq!(elapsed_millis(earlier, later).expect("delta"), 15);
        assert_eq!(
            elapsed_millis(later, earlier).unwrap_err().code(),
            "clock-went-backwards"
        );
    }

    #[test]
    fn version_is_an_exact_match() {
        assert!(require_version(BRIDGE_VERSION).is_ok());
        assert_eq!(
            require_version("helpmemove-bridge-0").unwrap_err().code(),
            "version-mismatch"
        );
    }

    #[test]
    fn cancel_flag_is_owned_by_the_caller() {
        assert!(observe_cancel(false).is_ok());
        assert_eq!(observe_cancel(true).unwrap_err().code(), "cancelled");
    }
}
