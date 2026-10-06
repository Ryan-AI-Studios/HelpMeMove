//! Schema metric labels stay withheld. No degree is returned.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MetricLabel {
    ElbowAngle,
    ShoulderRotation,
    TrunkRotation,
    RepetitionCount,
}

impl MetricLabel {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ElbowAngle => "elbow_angle",
            Self::ShoulderRotation => "shoulder_rotation",
            Self::TrunkRotation => "trunk_rotation",
            Self::RepetitionCount => "repetition_count",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PresentedClaim {
    Withheld,
}

impl PresentedClaim {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Withheld => "withheld",
        }
    }
}

pub fn present_claim(exercise_id: &str, metric: MetricLabel) -> PresentedClaim {
    let _ = exercise_id;
    match metric {
        MetricLabel::ElbowAngle
        | MetricLabel::ShoulderRotation
        | MetricLabel::TrunkRotation
        | MetricLabel::RepetitionCount => PresentedClaim::Withheld,
    }
}

#[cfg(test)]
mod tests {
    use super::{MetricLabel, PresentedClaim, present_claim};

    #[test]
    fn label_strings_match_the_schema() {
        assert_eq!(MetricLabel::ElbowAngle.as_str(), "elbow_angle");
        assert_eq!(MetricLabel::ShoulderRotation.as_str(), "shoulder_rotation");
        assert_eq!(MetricLabel::TrunkRotation.as_str(), "trunk_rotation");
        assert_eq!(MetricLabel::RepetitionCount.as_str(), "repetition_count");
    }

    #[test]
    fn every_asked_label_is_withheld() {
        let ids = [
            "syn-knee-sit-to-stand",
            "syn-shoulder-band",
            "syn-shoulder-isometric",
            "syn-torso-pelvic-tilt",
            "",
            "syn-knee-sit-to-stand ",
            "other",
        ];
        let labels = [
            MetricLabel::ElbowAngle,
            MetricLabel::ShoulderRotation,
            MetricLabel::TrunkRotation,
            MetricLabel::RepetitionCount,
        ];
        for exercise_id in ids {
            for label in labels {
                let claim = present_claim(exercise_id, label);
                match claim {
                    PresentedClaim::Withheld => {}
                }
                assert_eq!(claim.as_str(), "withheld");
            }
        }
    }
}
