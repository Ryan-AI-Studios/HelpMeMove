//! Synthetic sit-to-stand stepper. No camera, clock, or spoken cue.
//! Metric labels are withheld and no degree is returned.

mod policy;
mod step;

pub use policy::{MetricLabel, PresentedClaim, present_claim};
pub use step::{
    CueToken, MovementError, MovementPhase, MovementRule, MovementSample, MovementState,
    step_movement,
};
