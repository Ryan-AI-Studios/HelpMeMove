//! Synthetic sit-to-stand stepper. No camera, clock, or spoken cue.

mod step;

pub use step::{
    CueToken, MovementError, MovementPhase, MovementRule, MovementSample, MovementState,
    step_movement,
};
