//! One normalized pose frame. No image, clock, or device.

use crate::{Confidence, DomainError};

pub const POSE_LANDMARK_COUNT: usize = 33;

/// One landmark in image coordinates. `z` has no angle meaning.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PosePoint {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub visibility: f64,
    pub presence: f64,
}

/// Thirty-three landmarks from the subject's perspective.
#[derive(Debug, Clone, PartialEq)]
pub struct PoseFrame {
    pub timestamp_unix_ms: i64,
    pub points: Vec<PosePoint>,
}

/// Subject-left index, then the subject-right index it swaps with.
const MIRROR_PAIRS: [(usize, usize); 16] = [
    (1, 4),
    (2, 5),
    (3, 6),
    (7, 8),
    (9, 10),
    (11, 12),
    (13, 14),
    (15, 16),
    (17, 18),
    (19, 20),
    (21, 22),
    (23, 24),
    (25, 26),
    (27, 28),
    (29, 30),
    (31, 32),
];

/// Rotate, then optionally mirror, five length-33 slices into one frame.
#[allow(clippy::too_many_arguments)]
pub fn normalize_pose_frame(
    x: &[f64],
    y: &[f64],
    z: &[f64],
    visibility: &[f64],
    presence: &[f64],
    timestamp_unix_ms: i64,
    rotation_degrees: i32,
    mirrored: bool,
) -> Result<PoseFrame, DomainError> {
    require_length(x)?;
    require_length(y)?;
    require_length(z)?;
    require_length(visibility)?;
    require_length(presence)?;
    if !rotation_is_quadrant(rotation_degrees) {
        return Err(DomainError::InvalidPoseFrame);
    }

    let mut points = Vec::with_capacity(POSE_LANDMARK_COUNT);
    for index in 0..POSE_LANDMARK_COUNT {
        let raw_x = value_at(x, index)?;
        let raw_y = value_at(y, index)?;
        let raw_z = value_at(z, index)?;
        let (mut mapped_x, mapped_y) = rotate(raw_x, raw_y, rotation_degrees)?;
        if mirrored {
            mapped_x = 1.0 - mapped_x;
        }
        if !unit_coordinate(mapped_x) || !unit_coordinate(mapped_y) || !raw_z.is_finite() {
            return Err(DomainError::InvalidPoseFrame);
        }
        let seen = Confidence::parse(value_at(visibility, index)?)?;
        let present = Confidence::parse(value_at(presence, index)?)?;
        points.push(PosePoint {
            x: mapped_x,
            y: mapped_y,
            z: raw_z,
            visibility: seen.value(),
            presence: present.value(),
        });
    }

    if mirrored {
        for (left, right) in MIRROR_PAIRS {
            points.swap(left, right);
        }
    }

    Ok(PoseFrame {
        timestamp_unix_ms,
        points,
    })
}

fn require_length(values: &[f64]) -> Result<(), DomainError> {
    if values.len() == POSE_LANDMARK_COUNT {
        Ok(())
    } else {
        Err(DomainError::InvalidPoseFrame)
    }
}

fn value_at(values: &[f64], index: usize) -> Result<f64, DomainError> {
    match values.get(index) {
        Some(value) => Ok(*value),
        None => Err(DomainError::InvalidPoseFrame),
    }
}

fn rotation_is_quadrant(degrees: i32) -> bool {
    matches!(degrees, 0 | 90 | 180 | 270 | -90)
}

fn rotate(x: f64, y: f64, degrees: i32) -> Result<(f64, f64), DomainError> {
    match degrees {
        0 => Ok((x, y)),
        90 => Ok((1.0 - y, x)),
        180 => Ok((1.0 - x, 1.0 - y)),
        270 | -90 => Ok((y, 1.0 - x)),
        _ => Err(DomainError::InvalidPoseFrame),
    }
}

fn unit_coordinate(value: f64) -> bool {
    value.is_finite() && (0.0..=1.0).contains(&value)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(value: f64) -> Vec<f64> {
        vec![value; POSE_LANDMARK_COUNT]
    }

    fn must(result: Result<PoseFrame, DomainError>) -> PoseFrame {
        match result {
            Ok(frame) => frame,
            Err(error) => panic!("{}", error.code()),
        }
    }

    fn code(result: Result<PoseFrame, DomainError>) -> &'static str {
        match result {
            Ok(_) => panic!("accepted a frame"),
            Err(error) => error.code(),
        }
    }

    fn frame(
        x: &[f64],
        y: &[f64],
        z: &[f64],
        visibility: &[f64],
        presence: &[f64],
        rotation_degrees: i32,
        mirrored: bool,
    ) -> Result<PoseFrame, DomainError> {
        normalize_pose_frame(
            x,
            y,
            z,
            visibility,
            presence,
            10,
            rotation_degrees,
            mirrored,
        )
    }

    #[test]
    fn quarter_turn_keeps_the_same_index() {
        let stored = must(frame(
            &row(0.2),
            &row(0.1),
            &row(0.0),
            &row(1.0),
            &row(1.0),
            90,
            false,
        ));
        let point = stored.points[0];
        assert_eq!(point.x, 0.9);
        assert_eq!(point.y, 0.2);
        assert_eq!(stored.points.len(), POSE_LANDMARK_COUNT);
    }

    #[test]
    fn half_and_three_quarter_turns_use_the_named_maps() {
        let half = must(frame(
            &row(0.2),
            &row(0.1),
            &row(0.0),
            &row(1.0),
            &row(1.0),
            180,
            false,
        ));
        assert_eq!(half.points[0].x, 0.8);
        assert_eq!(half.points[0].y, 0.9);

        let three = must(frame(
            &row(0.2),
            &row(0.1),
            &row(0.0),
            &row(1.0),
            &row(1.0),
            270,
            false,
        ));
        assert_eq!(three.points[0].x, 0.1);
        assert_eq!(three.points[0].y, 0.8);

        let negative = must(frame(
            &row(0.2),
            &row(0.1),
            &row(0.0),
            &row(1.0),
            &row(1.0),
            -90,
            false,
        ));
        assert_eq!(negative.points[0].x, 0.1);
        assert_eq!(negative.points[0].y, 0.8);
    }

    #[test]
    fn mirror_flips_then_swaps_shoulders() {
        let mut x = row(0.5);
        let mut y = row(0.5);
        let mut z = row(0.0);
        x[11] = 0.2;
        y[11] = 0.1;
        z[11] = 0.3;
        x[12] = 0.5;
        y[12] = 0.5;
        z[12] = 0.7;
        let stored = must(frame(&x, &y, &z, &row(0.25), &row(0.0), 0, true));
        assert_eq!(stored.points[11].x, 0.5);
        assert_eq!(stored.points[11].y, 0.5);
        assert_eq!(stored.points[11].z, 0.7);
        assert_eq!(stored.points[12].x, 0.8);
        assert_eq!(stored.points[12].y, 0.1);
        assert_eq!(stored.points[12].z, 0.3);
        assert_eq!(stored.points[0].x, 0.5);
        assert_eq!(stored.points[0].visibility, 0.25);
        assert_eq!(stored.points[0].presence, 0.0);
    }

    #[test]
    fn bad_length_degree_coordinate_and_depth_are_rejected() {
        let short = row(0.5);
        let mut short_x = short.clone();
        short_x.pop();
        assert_eq!(
            code(frame(
                &short_x,
                &row(0.5),
                &row(0.0),
                &row(1.0),
                &row(1.0),
                0,
                false
            )),
            "invalid-pose-frame"
        );
        assert_eq!(
            code(frame(
                &row(0.5),
                &row(0.5),
                &row(0.0),
                &row(1.0),
                &row(1.0),
                45,
                false
            )),
            "invalid-pose-frame"
        );
        assert_eq!(
            code(frame(
                &row(0.5),
                &row(0.5),
                &row(0.0),
                &row(1.0),
                &row(1.0),
                360,
                false
            )),
            "invalid-pose-frame"
        );
        assert_eq!(
            code(frame(
                &row(1.1),
                &row(0.5),
                &row(0.0),
                &row(1.0),
                &row(1.0),
                0,
                false
            )),
            "invalid-pose-frame"
        );
        assert_eq!(
            code(frame(
                &row(0.5),
                &row(0.5),
                &row(f64::NAN),
                &row(1.0),
                &row(1.0),
                0,
                false
            )),
            "invalid-pose-frame"
        );
    }

    #[test]
    fn visibility_outside_the_unit_interval_keeps_the_confidence_code() {
        assert_eq!(
            code(frame(
                &row(0.5),
                &row(0.5),
                &row(0.0),
                &row(1.1),
                &row(1.0),
                0,
                false
            )),
            "invalid-confidence"
        );
    }
}
