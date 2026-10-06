use helpmemove_bridge::api::bridge::{BridgeError, accept_pose_frame};

fn row(value: f64) -> Vec<f64> {
    vec![value; 33]
}

#[test]
fn accept_pose_frame_mirrors_the_shoulder_pair() {
    let mut x = row(0.5);
    let mut y = row(0.5);
    x[11] = 0.2;
    y[11] = 0.1;
    x[12] = 0.5;
    y[12] = 0.5;
    let frame = match accept_pose_frame(x, y, row(0.0), row(1.0), row(1.0), 20, 0, true) {
        Ok(frame) => frame,
        Err(error) => panic!("{}", error.code()),
    };
    assert_eq!(frame.timestamp_unix_ms, 20);
    assert_eq!(frame.points.len(), 33);
    assert_eq!(frame.points[11].x, 0.5);
    assert_eq!(frame.points[11].y, 0.5);
    assert_eq!(frame.points[12].x, 0.8);
    assert_eq!(frame.points[12].y, 0.1);
}

#[test]
fn accept_pose_frame_rejects_a_short_slice_and_a_bad_visibility() {
    let mut short = row(0.5);
    short.pop();
    match accept_pose_frame(short, row(0.5), row(0.0), row(1.0), row(1.0), 1, 0, false) {
        Err(error) => {
            assert_eq!(error, BridgeError::InvalidPoseFrame);
            assert_eq!(error.code(), "invalid-pose-frame");
        }
        Ok(_) => panic!("accepted a short slice"),
    }
    match accept_pose_frame(
        row(0.5),
        row(0.5),
        row(0.0),
        row(1.1),
        row(1.0),
        1,
        0,
        false,
    ) {
        Err(error) => assert_eq!(error, BridgeError::InvalidConfidence),
        Ok(_) => panic!("accepted visibility 1.1"),
    }
}
