//! One exercise, one side, and no degree in the returned sample.

use helpmemove_domain::{Confidence, PoseFrame, PosePoint};

const EXERCISE_ID: &str = "syn-knee-sit-to-stand";
const HIP: usize = 23;
const KNEE: usize = 25;
const ANKLE: usize = 27;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MovementPhase {
    Waiting,
    Positioning,
    Ready,
    Eccentric,
    Bottom,
    Concentric,
    Top,
    RepComplete,
}

impl MovementPhase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Waiting => "waiting",
            Self::Positioning => "positioning",
            Self::Ready => "ready",
            Self::Eccentric => "eccentric",
            Self::Bottom => "bottom",
            Self::Concentric => "concentric",
            Self::Top => "top",
            Self::RepComplete => "rep-complete",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CueToken {
    RangeShort,
    TempoFast,
}

impl CueToken {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::RangeShort => "range-short",
            Self::TempoFast => "tempo-fast",
        }
    }

    fn rank(self) -> u8 {
        match self {
            Self::RangeShort => 3,
            Self::TempoFast => 4,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MovementSample {
    pub phase: MovementPhase,
    pub rep_count: u32,
    pub tempo_ms: Option<u64>,
    pub cue: Option<CueToken>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MovementRule {
    pub exercise_id: String,
    pub min_confidence: f64,
    pub alpha: f64,
    pub bottom_enter_cosine: f64,
    pub bottom_exit_cosine: f64,
    pub max_gap_ms: u64,
    pub min_rep_ms: u64,
    pub cue_cooldown_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MovementError {
    InvalidMovementRule,
    InvalidMovementFrame,
    InvalidConfidence,
}

impl MovementError {
    pub fn code(self) -> &'static str {
        match self {
            Self::InvalidMovementRule => "invalid-movement-rule",
            Self::InvalidMovementFrame => "invalid-movement-frame",
            Self::InvalidConfidence => "invalid-confidence",
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct Joint {
    x: f64,
    y: f64,
}

#[derive(Debug, Clone, Copy)]
struct Smoother {
    hip: Joint,
    knee: Joint,
    ankle: Joint,
}

#[derive(Debug, Clone)]
pub struct MovementState {
    phase: MovementPhase,
    rep_count: u32,
    tempo_ms: Option<u64>,
    last_sample: Option<MovementSample>,
    last_timestamp: Option<i64>,
    drop_count: u32,
    held_count: u32,
    smoother: Option<Smoother>,
    previous_cosine: Option<f64>,
    rep_started_ms: Option<i64>,
    cooldown_until_ms: i64,
}

impl MovementState {
    pub fn new() -> Self {
        Self {
            phase: MovementPhase::Waiting,
            rep_count: 0,
            tempo_ms: None,
            last_sample: None,
            last_timestamp: None,
            drop_count: 0,
            held_count: 0,
            smoother: None,
            previous_cosine: None,
            rep_started_ms: None,
            cooldown_until_ms: i64::MIN,
        }
    }

    pub fn drop_count(&self) -> u32 {
        self.drop_count
    }

    pub fn held_count(&self) -> u32 {
        self.held_count
    }

    fn reset_attempt(&mut self) {
        self.phase = MovementPhase::Waiting;
        self.smoother = None;
        self.previous_cosine = None;
        self.rep_started_ms = None;
    }
}

impl Default for MovementState {
    fn default() -> Self {
        Self::new()
    }
}

struct PhaseStep {
    phase: MovementPhase,
    cue: Option<CueToken>,
    start_rep: bool,
    finish_rep: bool,
    clear_rep: bool,
}

pub fn step_movement(
    state: &mut MovementState,
    frame: &PoseFrame,
    rule: &MovementRule,
) -> Result<MovementSample, MovementError> {
    let min_confidence = checked_rule(rule)?;
    if frame.points.len() != 33 {
        return Err(MovementError::InvalidMovementFrame);
    }
    if let Some(last) = state.last_timestamp
        && frame.timestamp_unix_ms <= last
    {
        state.drop_count = state.drop_count.saturating_add(1);
        return Ok(match state.last_sample {
            Some(sample) => sample,
            None => resting(MovementPhase::Waiting, 0, None),
        });
    }

    let mut next = state.clone();
    if let Some(last) = state.last_timestamp {
        let gap = i128::from(frame.timestamp_unix_ms) - i128::from(last);
        let max_gap = i128::from(rule.max_gap_ms);
        if gap > max_gap {
            next.reset_attempt();
        }
    }

    let hip = point_at(frame, HIP)?;
    let knee = point_at(frame, KNEE)?;
    let ankle = point_at(frame, ANKLE)?;
    let seen = [
        hip.visibility,
        hip.presence,
        knee.visibility,
        knee.presence,
        ankle.visibility,
        ankle.presence,
    ];
    let mut below_cutoff = false;
    for value in seen {
        let parsed = match Confidence::parse(value) {
            Ok(confidence) => confidence.value(),
            Err(_) => return Err(MovementError::InvalidMovementFrame),
        };
        if parsed < min_confidence {
            below_cutoff = true;
        }
    }
    if below_cutoff {
        next.held_count = next.held_count.saturating_add(1);
        next.last_timestamp = Some(frame.timestamp_unix_ms);
        let sample = resting(next.phase, next.rep_count, next.tempo_ms);
        next.last_sample = Some(sample);
        *state = next;
        return Ok(sample);
    }

    let raw = Smoother {
        hip: Joint { x: hip.x, y: hip.y },
        knee: Joint {
            x: knee.x,
            y: knee.y,
        },
        ankle: Joint {
            x: ankle.x,
            y: ankle.y,
        },
    };
    let smoothed = smooth(next.smoother, raw, rule.alpha)?;
    let cosine = joint_cosine(smoothed)?;
    let effect = match next.phase {
        MovementPhase::Waiting => PhaseStep {
            phase: MovementPhase::Positioning,
            cue: None,
            start_rep: false,
            finish_rep: false,
            clear_rep: false,
        },
        phase => {
            let previous = match next.previous_cosine {
                Some(value) => value,
                None => return Err(MovementError::InvalidMovementFrame),
            };
            advance(
                phase,
                cosine,
                previous,
                rule.bottom_enter_cosine,
                rule.bottom_exit_cosine,
            )
        }
    };

    let mut tempo_ms = next.tempo_ms;
    let mut rep_count = next.rep_count;
    if effect.finish_rep {
        let started = match next.rep_started_ms {
            Some(value) => value,
            None => return Err(MovementError::InvalidMovementFrame),
        };
        let elapsed = i128::from(frame.timestamp_unix_ms) - i128::from(started);
        tempo_ms = Some(match u64::try_from(elapsed) {
            Ok(value) => value,
            Err(_) => return Err(MovementError::InvalidMovementFrame),
        });
        rep_count = rep_count.saturating_add(1);
    }

    let mut candidates = Vec::new();
    if effect.cue.is_some() {
        // The abort path is the only phase cue.
        candidates.push(CueToken::RangeShort);
    }
    if effect.finish_rep
        && let Some(tempo) = tempo_ms
        && tempo < rule.min_rep_ms
    {
        candidates.push(CueToken::TempoFast);
    }
    let cue = select_cue(&candidates, frame.timestamp_unix_ms, next.cooldown_until_ms);
    if cue.is_some() {
        let cooldown = match i64::try_from(rule.cue_cooldown_ms) {
            Ok(value) => value,
            Err(_) => return Err(MovementError::InvalidMovementRule),
        };
        next.cooldown_until_ms = frame.timestamp_unix_ms.saturating_add(cooldown);
    }

    next.phase = effect.phase;
    next.rep_count = rep_count;
    next.tempo_ms = tempo_ms;
    next.smoother = Some(smoothed);
    next.previous_cosine = Some(cosine);
    next.last_timestamp = Some(frame.timestamp_unix_ms);
    if effect.clear_rep {
        next.rep_started_ms = None;
    }
    if effect.start_rep {
        next.rep_started_ms = Some(frame.timestamp_unix_ms);
    }
    if effect.finish_rep {
        next.rep_started_ms = None;
    }
    let sample = MovementSample {
        phase: next.phase,
        rep_count: next.rep_count,
        tempo_ms: next.tempo_ms,
        cue,
    };
    next.last_sample = Some(sample);
    *state = next;
    Ok(sample)
}

pub(crate) fn select_cue(
    candidates: &[CueToken],
    now_ms: i64,
    cooldown_until_ms: i64,
) -> Option<CueToken> {
    if now_ms < cooldown_until_ms {
        return None;
    }
    let mut chosen: Option<CueToken> = None;
    for candidate in candidates {
        match chosen {
            None => chosen = Some(*candidate),
            Some(current) if candidate.rank() < current.rank() => chosen = Some(*candidate),
            Some(_) => {}
        }
    }
    chosen
}

fn checked_rule(rule: &MovementRule) -> Result<f64, MovementError> {
    if rule.exercise_id != EXERCISE_ID {
        return Err(MovementError::InvalidMovementRule);
    }
    let min_confidence = match Confidence::parse(rule.min_confidence) {
        Ok(confidence) => confidence.value(),
        Err(_) => return Err(MovementError::InvalidConfidence),
    };
    if !rule.alpha.is_finite() || rule.alpha <= 0.0 || rule.alpha > 1.0 {
        return Err(MovementError::InvalidMovementRule);
    }
    if !cosine_bound(rule.bottom_enter_cosine) || !cosine_bound(rule.bottom_exit_cosine) {
        return Err(MovementError::InvalidMovementRule);
    }
    if rule.bottom_exit_cosine >= rule.bottom_enter_cosine {
        return Err(MovementError::InvalidMovementRule);
    }
    if rule.max_gap_ms < 1 || rule.min_rep_ms < 1 || rule.cue_cooldown_ms < 1 {
        return Err(MovementError::InvalidMovementRule);
    }
    if i64::try_from(rule.max_gap_ms).is_err()
        || i64::try_from(rule.min_rep_ms).is_err()
        || i64::try_from(rule.cue_cooldown_ms).is_err()
    {
        return Err(MovementError::InvalidMovementRule);
    }
    Ok(min_confidence)
}

fn cosine_bound(value: f64) -> bool {
    value.is_finite() && (-1.0..=1.0).contains(&value)
}

fn point_at(frame: &PoseFrame, index: usize) -> Result<&PosePoint, MovementError> {
    match frame.points.get(index) {
        Some(point) => Ok(point),
        None => Err(MovementError::InvalidMovementFrame),
    }
}

fn smooth(
    previous: Option<Smoother>,
    raw: Smoother,
    alpha: f64,
) -> Result<Smoother, MovementError> {
    let smoothed = match previous {
        None => raw,
        Some(prior) => Smoother {
            hip: mix(prior.hip, raw.hip, alpha)?,
            knee: mix(prior.knee, raw.knee, alpha)?,
            ankle: mix(prior.ankle, raw.ankle, alpha)?,
        },
    };
    if !finite_joint(smoothed.hip) || !finite_joint(smoothed.knee) || !finite_joint(smoothed.ankle)
    {
        return Err(MovementError::InvalidMovementFrame);
    }
    Ok(smoothed)
}

fn mix(previous: Joint, raw: Joint, alpha: f64) -> Result<Joint, MovementError> {
    let joint = Joint {
        x: alpha * raw.x + (1.0 - alpha) * previous.x,
        y: alpha * raw.y + (1.0 - alpha) * previous.y,
    };
    if finite_joint(joint) {
        Ok(joint)
    } else {
        Err(MovementError::InvalidMovementFrame)
    }
}

fn finite_joint(joint: Joint) -> bool {
    joint.x.is_finite() && joint.y.is_finite()
}

fn joint_cosine(joints: Smoother) -> Result<f64, MovementError> {
    let hip_dx = joints.hip.x - joints.knee.x;
    let hip_dy = joints.hip.y - joints.knee.y;
    let ankle_dx = joints.ankle.x - joints.knee.x;
    let ankle_dy = joints.ankle.y - joints.knee.y;
    let hip_len = (hip_dx * hip_dx + hip_dy * hip_dy).sqrt();
    let ankle_len = (ankle_dx * ankle_dx + ankle_dy * ankle_dy).sqrt();
    if !hip_len.is_finite() || !ankle_len.is_finite() || hip_len == 0.0 || ankle_len == 0.0 {
        return Err(MovementError::InvalidMovementFrame);
    }
    let dot = hip_dx * ankle_dx + hip_dy * ankle_dy;
    let ratio = dot / (hip_len * ankle_len);
    if !ratio.is_finite() {
        return Err(MovementError::InvalidMovementFrame);
    }
    Ok(ratio.clamp(-1.0, 1.0))
}

fn advance(
    phase: MovementPhase,
    cosine: f64,
    previous: f64,
    enter: f64,
    exit_cosine: f64,
) -> PhaseStep {
    match phase {
        MovementPhase::Waiting => PhaseStep {
            phase: MovementPhase::Positioning,
            cue: None,
            start_rep: false,
            finish_rep: false,
            clear_rep: false,
        },
        MovementPhase::Positioning | MovementPhase::RepComplete => {
            let next = if cosine <= exit_cosine {
                MovementPhase::Ready
            } else {
                MovementPhase::Positioning
            };
            PhaseStep {
                phase: next,
                cue: None,
                start_rep: false,
                finish_rep: false,
                clear_rep: false,
            }
        }
        MovementPhase::Ready => {
            if cosine > previous {
                PhaseStep {
                    phase: MovementPhase::Eccentric,
                    cue: None,
                    start_rep: true,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else {
                PhaseStep {
                    phase: MovementPhase::Ready,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            }
        }
        MovementPhase::Eccentric => {
            if cosine >= enter {
                PhaseStep {
                    phase: MovementPhase::Bottom,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else if cosine < previous {
                PhaseStep {
                    phase: MovementPhase::Ready,
                    cue: Some(CueToken::RangeShort),
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: true,
                }
            } else {
                PhaseStep {
                    phase: MovementPhase::Eccentric,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            }
        }
        MovementPhase::Bottom => {
            if cosine <= exit_cosine {
                PhaseStep {
                    phase: MovementPhase::Top,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else if cosine < previous {
                PhaseStep {
                    phase: MovementPhase::Concentric,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else {
                PhaseStep {
                    phase: MovementPhase::Bottom,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            }
        }
        MovementPhase::Concentric => {
            if cosine <= exit_cosine {
                PhaseStep {
                    phase: MovementPhase::Top,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else if cosine >= enter {
                PhaseStep {
                    phase: MovementPhase::Bottom,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else {
                PhaseStep {
                    phase: MovementPhase::Concentric,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: false,
                }
            }
        }
        MovementPhase::Top => {
            if cosine <= exit_cosine {
                PhaseStep {
                    phase: MovementPhase::RepComplete,
                    cue: None,
                    start_rep: false,
                    finish_rep: true,
                    clear_rep: false,
                }
            } else if cosine > previous {
                PhaseStep {
                    phase: MovementPhase::Eccentric,
                    cue: None,
                    start_rep: true,
                    finish_rep: false,
                    clear_rep: false,
                }
            } else {
                PhaseStep {
                    phase: MovementPhase::Ready,
                    cue: None,
                    start_rep: false,
                    finish_rep: false,
                    clear_rep: true,
                }
            }
        }
    }
}

fn resting(phase: MovementPhase, rep_count: u32, tempo_ms: Option<u64>) -> MovementSample {
    MovementSample {
        phase,
        rep_count,
        tempo_ms,
        cue: None,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CueToken, MovementError, MovementPhase, MovementRule, MovementSample, MovementState,
        select_cue, step_movement,
    };
    use helpmemove_domain::{PoseFrame, PosePoint, normalize_pose_frame};

    type Shape = ((f64, f64), (f64, f64), (f64, f64));
    type TimedShape = (i64, Shape);

    fn rule_with(min_rep_ms: u64, alpha: f64) -> MovementRule {
        MovementRule {
            exercise_id: "syn-knee-sit-to-stand".to_owned(),
            min_confidence: 0.2,
            alpha,
            bottom_enter_cosine: 0.0,
            bottom_exit_cosine: -0.5,
            max_gap_ms: 1000,
            min_rep_ms,
            cue_cooldown_ms: 1,
        }
    }

    fn rule() -> MovementRule {
        rule_with(1, 1.0)
    }

    fn pose(
        timestamp_unix_ms: i64,
        hip: (f64, f64),
        knee: (f64, f64),
        ankle: (f64, f64),
        knee_visibility: f64,
    ) -> PoseFrame {
        let mut points = Vec::new();
        for index in 0..33 {
            let (x, y, visibility) = if index == 23 {
                (hip.0, hip.1, 1.0)
            } else if index == 25 {
                (knee.0, knee.1, knee_visibility)
            } else if index == 27 {
                (ankle.0, ankle.1, 1.0)
            } else {
                (0.5, 0.5, 1.0)
            };
            points.push(PosePoint {
                x,
                y,
                z: 0.0,
                visibility,
                presence: 1.0,
            });
        }
        PoseFrame {
            timestamp_unix_ms,
            points,
        }
    }

    fn standing() -> Shape {
        ((0.5, 0.2), (0.5, 0.5), (0.5, 0.8))
    }

    fn orthogonal() -> Shape {
        ((0.5, 0.2), (0.5, 0.5), (0.8, 0.5))
    }

    fn folded() -> Shape {
        ((0.5, 0.2), (0.5, 0.5), (0.5, 0.2))
    }

    fn shape(timestamp_unix_ms: i64, points: Shape) -> PoseFrame {
        pose(timestamp_unix_ms, points.0, points.1, points.2, 1.0)
    }

    fn must(result: Result<MovementSample, MovementError>) -> MovementSample {
        match result {
            Ok(sample) => sample,
            Err(error) => panic!("{}", error.code()),
        }
    }

    fn code(result: Result<MovementSample, MovementError>) -> &'static str {
        match result {
            Ok(_) => panic!("accepted a frame"),
            Err(error) => error.code(),
        }
    }

    fn play(
        state: &mut MovementState,
        rule: &MovementRule,
        frames: &[TimedShape],
    ) -> Vec<MovementSample> {
        let mut samples = Vec::new();
        for (timestamp, points) in frames {
            samples.push(must(step_movement(
                state,
                &shape(*timestamp, *points),
                rule,
            )));
        }
        samples
    }

    fn clean_frames() -> [TimedShape; 7] {
        [
            (0, standing()),
            (100, standing()),
            (200, orthogonal()),
            (300, folded()),
            (400, orthogonal()),
            (500, standing()),
            (600, standing()),
        ]
    }

    #[test]
    fn clean_rep_matches_the_worked_table() {
        let mut state = MovementState::new();
        let samples = play(&mut state, &rule(), &clean_frames());
        let phases = [
            MovementPhase::Positioning,
            MovementPhase::Ready,
            MovementPhase::Eccentric,
            MovementPhase::Bottom,
            MovementPhase::Concentric,
            MovementPhase::Top,
            MovementPhase::RepComplete,
        ];
        for (sample, phase) in samples.iter().zip(phases) {
            assert_eq!(sample.phase, phase);
            assert_eq!(sample.cue, None);
        }
        assert_eq!(samples[6].rep_count, 1);
        assert_eq!(samples[6].tempo_ms, Some(400));
        assert_eq!(samples[5].rep_count, 0);
        assert_eq!(samples[6].phase.as_str(), "rep-complete");
    }

    #[test]
    fn abort_before_bottom_emits_range_short() {
        let mut state = MovementState::new();
        let frames = [
            (0, standing()),
            (100, standing()),
            (200, orthogonal()),
            (300, standing()),
        ];
        let samples = play(&mut state, &rule(), &frames);
        let last = samples[3];
        assert_eq!(last.phase, MovementPhase::Ready);
        assert_eq!(last.rep_count, 0);
        assert_eq!(last.cue, Some(CueToken::RangeShort));
        assert_eq!(last.cue.map(CueToken::as_str), Some("range-short"));
    }

    #[test]
    fn fast_rep_emits_tempo_fast() {
        let mut state = MovementState::new();
        let samples = play(&mut state, &rule_with(1000, 1.0), &clean_frames());
        let last = samples[6];
        assert_eq!(last.phase, MovementPhase::RepComplete);
        assert_eq!(last.rep_count, 1);
        assert_eq!(last.tempo_ms, Some(400));
        assert_eq!(last.cue, Some(CueToken::TempoFast));
    }

    #[test]
    fn low_confidence_holds_bottom() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let held = must(step_movement(
            &mut state,
            &pose(350, (0.5, 0.2), (0.5, 0.5), (0.5, 0.2), 0.0),
            &rule(),
        ));
        assert_eq!(held.phase, MovementPhase::Bottom);
        assert_eq!(held.rep_count, 0);
        assert_eq!(held.cue, None);
        assert_eq!(state.held_count(), 1);
        let next = must(step_movement(
            &mut state,
            &shape(400, orthogonal()),
            &rule(),
        ));
        assert_eq!(next.phase, MovementPhase::Concentric);
    }

    #[test]
    fn low_confidence_does_not_consume_the_top_edge() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..6]);
        let held = must(step_movement(
            &mut state,
            &pose(550, (0.5, 0.2), (0.5, 0.5), (0.5, 0.8), 0.0),
            &rule(),
        ));
        assert_eq!(held.phase, MovementPhase::Top);
        assert_eq!(held.rep_count, 0);
        assert_eq!(state.held_count(), 1);
        let finished = must(step_movement(&mut state, &shape(600, standing()), &rule()));
        assert_eq!(finished.phase, MovementPhase::RepComplete);
        assert_eq!(finished.rep_count, 1);
        assert_eq!(finished.tempo_ms, Some(400));
    }

    #[test]
    fn gap_resets_the_open_attempt_and_keeps_the_count() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let reset = must(step_movement(&mut state, &shape(1401, standing()), &rule()));
        assert_eq!(reset.phase, MovementPhase::Positioning);
        assert_eq!(reset.rep_count, 0);

        let mut completed = MovementState::new();
        let _ = play(&mut completed, &rule(), &clean_frames());
        let again = must(step_movement(
            &mut completed,
            &shape(1601, standing()),
            &rule(),
        ));
        assert_eq!(again.phase, MovementPhase::Positioning);
        assert_eq!(again.rep_count, 1);
        assert_eq!(again.tempo_ms, Some(400));
    }

    #[test]
    fn older_timestamp_drops_without_moving_the_phase() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let dropped = must(step_movement(&mut state, &shape(250, standing()), &rule()));
        assert_eq!(dropped.phase, MovementPhase::Bottom);
        assert_eq!(state.drop_count(), 1);
        assert_eq!(state.held_count(), 0);
        let next = must(step_movement(
            &mut state,
            &shape(400, orthogonal()),
            &rule(),
        ));
        assert_eq!(next.phase, MovementPhase::Concentric);
        assert_eq!(state.drop_count(), 1);
    }

    #[test]
    fn smoothing_rescues_a_zero_raw_vector() {
        let mut state = MovementState::new();
        let first = must(step_movement(
            &mut state,
            &shape(0, standing()),
            &rule_with(1, 0.5),
        ));
        assert_eq!(first.phase, MovementPhase::Positioning);
        let second = must(step_movement(
            &mut state,
            &pose(100, (0.5, 0.5), (0.5, 0.5), (0.5, 0.8), 1.0),
            &rule_with(1, 0.5),
        ));
        assert_eq!(second.phase, MovementPhase::Ready);
    }

    #[test]
    fn mirrored_normalization_still_counts_the_subject_left_rep() {
        let mut state = MovementState::new();
        let frames = clean_frames();
        let mut phases = Vec::new();
        for (timestamp, points) in frames {
            let frame = mirrored_frame(timestamp, points);
            phases.push(must(step_movement(&mut state, &frame, &rule())).phase);
        }
        assert_eq!(
            phases,
            vec![
                MovementPhase::Positioning,
                MovementPhase::Ready,
                MovementPhase::Eccentric,
                MovementPhase::Bottom,
                MovementPhase::Concentric,
                MovementPhase::Top,
                MovementPhase::RepComplete,
            ]
        );
        assert_eq!(state.rep_count, 1);
    }

    fn mirrored_frame(timestamp_unix_ms: i64, motion: Shape) -> PoseFrame {
        let mut x = [0.5_f64; 33];
        let mut y = [0.5_f64; 33];
        let z = [0.0_f64; 33];
        let visibility = [1.0_f64; 33];
        let presence = [1.0_f64; 33];
        let still = standing();
        x[23] = still.0.0;
        y[23] = still.0.1;
        x[25] = still.1.0;
        y[25] = still.1.1;
        x[27] = still.2.0;
        y[27] = still.2.1;
        x[24] = motion.0.0;
        y[24] = motion.0.1;
        x[26] = motion.1.0;
        y[26] = motion.1.1;
        x[28] = motion.2.0;
        y[28] = motion.2.1;
        match normalize_pose_frame(
            &x,
            &y,
            &z,
            &visibility,
            &presence,
            timestamp_unix_ms,
            0,
            true,
        ) {
            Ok(frame) => frame,
            Err(error) => panic!("{}", error.code()),
        }
    }

    #[test]
    fn select_cue_prefers_range_and_honors_cooldown() {
        let both = [CueToken::TempoFast, CueToken::RangeShort];
        assert_eq!(select_cue(&both, 10, 10), Some(CueToken::RangeShort));
        assert_eq!(select_cue(&both, 9, 10), None);
        assert_eq!(select_cue(&[], 10, 0), None);
    }

    #[test]
    fn rejected_frames_leave_the_bottom_in_place() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let drop = state.drop_count();
        let held = state.held_count();

        let mut wrong_id = rule();
        wrong_id.exercise_id = "syn-shoulder-band".to_owned();
        assert_eq!(
            code(step_movement(
                &mut state,
                &shape(350, standing()),
                &wrong_id
            )),
            "invalid-movement-rule"
        );

        let mut short = shape(360, standing());
        short.points.pop();
        assert_eq!(short.points.len(), 32);
        assert_eq!(
            code(step_movement(&mut state, &short, &rule())),
            "invalid-movement-frame"
        );

        assert_eq!(
            code(step_movement(
                &mut state,
                &pose(370, (0.5, 0.5), (0.5, 0.5), (0.5, 0.8), 1.0),
                &rule(),
            )),
            "invalid-movement-frame"
        );

        let mut high = rule();
        high.min_confidence = 1.1;
        assert_eq!(
            code(step_movement(&mut state, &shape(380, standing()), &high)),
            "invalid-confidence"
        );

        assert_eq!(state.drop_count(), drop);
        assert_eq!(state.held_count(), held);
        let next = must(step_movement(
            &mut state,
            &shape(400, orthogonal()),
            &rule(),
        ));
        assert_eq!(next.phase, MovementPhase::Concentric);
        assert_eq!(next.rep_count, 0);
    }

    fn widest_gap() -> u64 {
        match u64::try_from(i64::MAX) {
            Ok(value) => value,
            Err(_) => panic!("gap limit"),
        }
    }

    #[test]
    fn low_confidence_does_not_hide_a_later_invalid_value() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let drop = state.drop_count();
        let held = state.held_count();
        let mut frame = shape(350, folded());
        frame.points[23].visibility = 0.0;
        frame.points[23].presence = 1.1;
        assert_eq!(
            code(step_movement(&mut state, &frame, &rule())),
            "invalid-movement-frame"
        );
        assert_eq!(state.drop_count(), drop);
        assert_eq!(state.held_count(), held);
        let next = must(step_movement(
            &mut state,
            &shape(400, orthogonal()),
            &rule(),
        ));
        assert_eq!(next.phase, MovementPhase::Concentric);
        assert_eq!(next.rep_count, 0);
    }

    #[test]
    fn gap_equal_to_the_limit_stays_on_the_attempt() {
        let mut state = MovementState::new();
        let _ = play(&mut state, &rule(), &clean_frames()[..4]);
        let same = must(step_movement(&mut state, &shape(1300, standing()), &rule()));
        assert_eq!(same.phase, MovementPhase::Top);
        assert_eq!(same.rep_count, 0);
    }

    #[test]
    fn gap_wider_than_i64_resets_the_attempt() {
        let mut wide = rule();
        wide.max_gap_ms = widest_gap();
        let mut state = MovementState::new();
        let _ = must(step_movement(
            &mut state,
            &shape(i64::MIN, standing()),
            &wide,
        ));
        let _ = must(step_movement(
            &mut state,
            &shape(i64::MIN + 1, standing()),
            &wide,
        ));
        let reset = must(step_movement(&mut state, &shape(1, orthogonal()), &wide));
        assert_eq!(reset.phase, MovementPhase::Positioning);
        assert_eq!(reset.rep_count, 0);
        assert_eq!(state.drop_count(), 0);
        assert_eq!(state.held_count(), 0);
    }

    #[test]
    fn tempo_above_i64_max_still_completes() {
        let mut wide = rule();
        wide.max_gap_ms = widest_gap();
        let frames = [
            (i64::MIN, standing()),
            (i64::MIN + 1, standing()),
            (i64::MIN + 2, orthogonal()),
            (-2, folded()),
            (-1, orthogonal()),
            (0, standing()),
            (3, standing()),
        ];
        let mut state = MovementState::new();
        let samples = play(&mut state, &wide, &frames);
        let last = samples[6];
        assert_eq!(last.phase, MovementPhase::RepComplete);
        assert_eq!(last.rep_count, 1);
        assert_eq!(last.tempo_ms, Some(9_223_372_036_854_775_809));
        assert_eq!(last.cue, None);
    }
}
