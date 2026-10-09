//! Synthetic manual session. Not a clinician-approved workout.

use serde_json::{Map, Number, Value};

use super::ContentError;
use super::model::{Exercise, Tempo};

const RULE_ID: &str = "syn-program-core";
const PROGRAM_KEYS: [&str; 7] = [
    "exercises",
    "record_version",
    "rule_id",
    "rule_version",
    "safety_rule_id",
    "safety_rule_version",
    "session_minutes",
];
const SESSION_KEYS: [&str; 11] = [
    "elapsed_ms",
    "exercises",
    "monotonic_ms",
    "outcome",
    "record_version",
    "reported_pain",
    "rest_until_ms",
    "rule_id",
    "session_id",
    "state",
    "symptom",
];
const EXERCISE_KEYS: [&str; 7] = [
    "exercise_id",
    "reps",
    "reps_done",
    "set_index",
    "sets",
    "skipped",
    "tempo",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionState {
    Preparing,
    Demonstrating,
    Positioning,
    Ready,
    Active,
    Correcting,
    Resting,
    Paused,
    PainCheck,
    Substituting,
    Completed,
    Abandoned,
    SafetyStopped,
}

impl SessionState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Demonstrating => "demonstrating",
            Self::Positioning => "positioning",
            Self::Ready => "ready",
            Self::Active => "active",
            Self::Correcting => "correcting",
            Self::Resting => "resting",
            Self::Paused => "paused",
            Self::PainCheck => "pain_check",
            Self::Substituting => "substituting",
            Self::Completed => "completed",
            Self::Abandoned => "abandoned",
            Self::SafetyStopped => "safety_stopped",
        }
    }

    fn parse(token: &str) -> Option<Self> {
        Some(match token {
            "preparing" => Self::Preparing,
            "demonstrating" => Self::Demonstrating,
            "positioning" => Self::Positioning,
            "ready" => Self::Ready,
            "active" => Self::Active,
            "correcting" => Self::Correcting,
            "resting" => Self::Resting,
            "paused" => Self::Paused,
            "pain_check" => Self::PainCheck,
            "substituting" => Self::Substituting,
            "completed" => Self::Completed,
            "abandoned" => Self::Abandoned,
            "safety_stopped" => Self::SafetyStopped,
            _ => return None,
        })
    }

    fn counts_elapsed(self) -> bool {
        !matches!(
            self,
            Self::Paused
                | Self::PainCheck
                | Self::Substituting
                | Self::Completed
                | Self::Abandoned
                | Self::SafetyStopped
        )
    }

    fn terminal(self) -> Option<&'static str> {
        match self {
            Self::Completed => Some("completed"),
            Self::Abandoned => Some("abandoned"),
            Self::SafetyStopped => Some("safety_stopped"),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Symptom {
    MildDiscomfort,
    SharpPain,
    Increased,
    NumbnessTingling,
    Weakness,
}

impl Symptom {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::MildDiscomfort => "mild_discomfort",
            Self::SharpPain => "sharp_pain",
            Self::Increased => "increased",
            Self::NumbnessTingling => "numbness_tingling",
            Self::Weakness => "weakness",
        }
    }

    fn parse(token: &str) -> Option<Self> {
        Some(match token {
            "mild_discomfort" => Self::MildDiscomfort,
            "sharp_pain" => Self::SharpPain,
            "increased" => Self::Increased,
            "numbness_tingling" => Self::NumbnessTingling,
            "weakness" => Self::Weakness,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionExercise {
    pub exercise_id: String,
    pub reps_done: u32,
    pub set_index: u32,
    pub sets: u32,
    pub reps: u32,
    pub skipped: bool,
    pub tempo: Tempo,
    /// Fixture `substitutions` only. Not rendered. Regressions are never copied.
    pub substitutions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Session {
    pub elapsed_ms: u64,
    pub exercises: Vec<SessionExercise>,
    pub monotonic_ms: u64,
    pub outcome: Option<String>,
    pub reported_pain: Option<u8>,
    pub rest_until_ms: Option<u64>,
    pub session_id: String,
    pub state: SessionState,
    pub symptom: Option<Symptom>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEvent {
    Ready,
    CompleteRep,
    Tick,
    Pause,
    Resume,
    ReportPain { symptom: Symptom, reported_pain: u8 },
    ContinueAfterPain,
    SelectSubstitute { exercise_id: String },
    Skip,
    Shorten,
    EndSession,
}

/// Open a session from a stored program. Counts come from `library`, not the document.
pub fn open_session(
    program_json: &str,
    library: &[Exercise],
    monotonic_ms: u64,
    session_id: &str,
) -> Result<Session, ContentError> {
    if session_id.is_empty() || library.is_empty() {
        return Err(ContentError::InvalidSession);
    }
    let value: Value =
        serde_json::from_str(program_json).map_err(|_| ContentError::InvalidSession)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidSession);
    };
    if object.len() != PROGRAM_KEYS.len()
        || PROGRAM_KEYS.iter().any(|key| !object.contains_key(*key))
    {
        return Err(ContentError::InvalidSession);
    }
    if object.get("rule_id").and_then(Value::as_str) != Some(RULE_ID)
        || !exact(object.get("record_version"), 1)
        || !exact(object.get("rule_version"), 1)
        || object.get("safety_rule_id").and_then(Value::as_str) != Some("syn-safety-core")
        || !exact(object.get("safety_rule_version"), 1)
        || !exact(object.get("session_minutes"), 15)
    {
        return Err(ContentError::InvalidSession);
    }
    let Some(rows) = object.get("exercises").and_then(Value::as_array) else {
        return Err(ContentError::InvalidSession);
    };
    if rows.is_empty() {
        return Err(ContentError::InvalidSession);
    }
    let mut exercises = Vec::with_capacity(rows.len());
    for row in rows {
        exercises.push(copy_exercise(row, library)?);
    }
    Ok(Session {
        elapsed_ms: 0,
        exercises,
        monotonic_ms,
        outcome: None,
        reported_pain: None,
        rest_until_ms: None,
        session_id: session_id.to_owned(),
        state: SessionState::Preparing,
        symptom: None,
    })
}

pub fn apply_session_event(
    session: &Session,
    event: &SessionEvent,
    monotonic_ms: u64,
    eligible: &[String],
    library: &[Exercise],
) -> Result<Session, ContentError> {
    if session.outcome.is_some() || session.state.terminal().is_some() {
        return Err(ContentError::SessionClosed);
    }
    if monotonic_ms < session.monotonic_ms {
        return Err(ContentError::ClockWentBackwards);
    }
    let mut next = session.clone();
    let frozen_ms = monotonic_ms - next.monotonic_ms;
    if next.state.counts_elapsed() {
        next.elapsed_ms = add_signed_clock(next.elapsed_ms, frozen_ms)?;
    } else if let Some(until) = next.rest_until_ms {
        // Rest is a monotonic deadline. Time outside `resting` must not consume it.
        next.rest_until_ms = Some(add_signed_clock(until, frozen_ms)?);
    }
    next.monotonic_ms = monotonic_ms;
    dispatch(&mut next, event, monotonic_ms, eligible, library)?;
    Ok(next)
}

pub fn render_session(session: &Session) -> Result<String, ContentError> {
    let mut root = Map::new();
    root.insert("elapsed_ms".to_owned(), number(session.elapsed_ms)?);
    let mut rows = Vec::with_capacity(session.exercises.len());
    for exercise in &session.exercises {
        let mut row = Map::new();
        row.insert(
            "exercise_id".to_owned(),
            Value::String(exercise.exercise_id.clone()),
        );
        row.insert("reps".to_owned(), number(u64::from(exercise.reps))?);
        row.insert(
            "reps_done".to_owned(),
            number(u64::from(exercise.reps_done))?,
        );
        row.insert(
            "set_index".to_owned(),
            number(u64::from(exercise.set_index))?,
        );
        row.insert("sets".to_owned(), number(u64::from(exercise.sets))?);
        row.insert("skipped".to_owned(), Value::Bool(exercise.skipped));
        let mut tempo = Map::new();
        tempo.insert(
            "concentric".to_owned(),
            number(u64::from(exercise.tempo.concentric))?,
        );
        tempo.insert(
            "eccentric".to_owned(),
            number(u64::from(exercise.tempo.eccentric))?,
        );
        tempo.insert("pause".to_owned(), number(u64::from(exercise.tempo.pause))?);
        row.insert("tempo".to_owned(), Value::Object(tempo));
        rows.push(Value::Object(row));
    }
    root.insert("exercises".to_owned(), Value::Array(rows));
    root.insert("monotonic_ms".to_owned(), number(session.monotonic_ms)?);
    root.insert(
        "outcome".to_owned(),
        match &session.outcome {
            Some(token) => Value::String(token.clone()),
            None => Value::Null,
        },
    );
    root.insert("record_version".to_owned(), number(1)?);
    root.insert(
        "reported_pain".to_owned(),
        match session.reported_pain {
            Some(value) => number(u64::from(value))?,
            None => Value::Null,
        },
    );
    root.insert(
        "rest_until_ms".to_owned(),
        match session.rest_until_ms {
            Some(value) => number(value)?,
            None => Value::Null,
        },
    );
    root.insert("rule_id".to_owned(), Value::String(RULE_ID.to_owned()));
    root.insert(
        "session_id".to_owned(),
        Value::String(session.session_id.clone()),
    );
    root.insert(
        "state".to_owned(),
        Value::String(session.state.as_str().to_owned()),
    );
    root.insert(
        "symptom".to_owned(),
        match session.symptom {
            Some(symptom) => Value::String(symptom.as_str().to_owned()),
            None => Value::Null,
        },
    );
    Ok(Value::Object(root).to_string())
}

pub fn parse_session(text: &str, library: &[Exercise]) -> Result<Session, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidSession)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidSession);
    };
    if object.len() != SESSION_KEYS.len()
        || SESSION_KEYS.iter().any(|key| !object.contains_key(*key))
    {
        return Err(ContentError::InvalidSession);
    }
    if !exact(object.get("record_version"), 1)
        || object.get("rule_id").and_then(Value::as_str) != Some(RULE_ID)
    {
        return Err(ContentError::InvalidSession);
    }
    let Some(session_id) = object.get("session_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidSession);
    };
    if session_id.is_empty() {
        return Err(ContentError::InvalidSession);
    }
    let Some(state) = object
        .get("state")
        .and_then(Value::as_str)
        .and_then(SessionState::parse)
    else {
        return Err(ContentError::InvalidSession);
    };
    let outcome = match object.get("outcome") {
        Some(Value::Null) => None,
        Some(Value::String(token)) => Some(token.clone()),
        _ => return Err(ContentError::InvalidSession),
    };
    match (state.terminal(), outcome.as_deref()) {
        (None, None)
        | (Some("completed"), Some("completed"))
        | (Some("abandoned"), Some("abandoned"))
        | (Some("safety_stopped"), Some("safety_stopped")) => {}
        _ => return Err(ContentError::InvalidSession),
    }
    if matches!(
        state,
        SessionState::Positioning
            | SessionState::Ready
            | SessionState::Correcting
            | SessionState::Substituting
    ) {
        return Err(ContentError::InvalidSession);
    }
    let symptom = match object.get("symptom") {
        Some(Value::Null) => None,
        Some(Value::String(token)) => {
            Some(Symptom::parse(token).ok_or(ContentError::InvalidSession)?)
        }
        _ => return Err(ContentError::InvalidSession),
    };
    let reported_pain = optional_u8(object.get("reported_pain"))?;
    if reported_pain.is_some_and(|value| value > 10) {
        return Err(ContentError::InvalidSession);
    }
    let Some(rows) = object.get("exercises").and_then(Value::as_array) else {
        return Err(ContentError::InvalidSession);
    };
    if rows.is_empty() {
        return Err(ContentError::InvalidSession);
    }
    let mut exercises = Vec::with_capacity(rows.len());
    for row in rows {
        exercises.push(parse_exercise_row(row, library)?);
    }
    Ok(Session {
        elapsed_ms: required_u64(object.get("elapsed_ms"))?,
        exercises,
        monotonic_ms: required_u64(object.get("monotonic_ms"))?,
        outcome,
        reported_pain,
        rest_until_ms: optional_u64(object.get("rest_until_ms"))?,
        session_id: session_id.to_owned(),
        state,
        symptom,
    })
}

pub fn read_session_event(text: &str) -> Result<SessionEvent, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidSession)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidSession);
    };
    let Some(name) = object.get("name").and_then(Value::as_str) else {
        return Err(ContentError::InvalidSession);
    };
    let event = match name {
        "ready" => SessionEvent::Ready,
        "complete_rep" => SessionEvent::CompleteRep,
        "tick" => SessionEvent::Tick,
        "pause" => SessionEvent::Pause,
        "resume" => SessionEvent::Resume,
        "continue_after_pain" => SessionEvent::ContinueAfterPain,
        "skip" => SessionEvent::Skip,
        "shorten" => SessionEvent::Shorten,
        "end_session" => SessionEvent::EndSession,
        "report_pain" => {
            let Some(token) = object.get("symptom").and_then(Value::as_str) else {
                return Err(ContentError::InvalidSession);
            };
            let Some(symptom) = Symptom::parse(token) else {
                return Err(ContentError::InvalidSession);
            };
            let Some(reported_pain) = object.get("reported_pain").and_then(Value::as_u64) else {
                return Err(ContentError::InvalidSession);
            };
            if reported_pain > 10 {
                return Err(ContentError::InvalidSession);
            }
            SessionEvent::ReportPain {
                symptom,
                reported_pain: u8::try_from(reported_pain)
                    .map_err(|_| ContentError::InvalidSession)?,
            }
        }
        "select_substitute" => {
            let Some(exercise_id) = object.get("exercise_id").and_then(Value::as_str) else {
                return Err(ContentError::InvalidSession);
            };
            if exercise_id.is_empty() {
                return Err(ContentError::InvalidSession);
            }
            SessionEvent::SelectSubstitute {
                exercise_id: exercise_id.to_owned(),
            }
        }
        _ => return Err(ContentError::InvalidSession),
    };
    let allowed: &[&str] = match name {
        "report_pain" => &["name", "reported_pain", "symptom"],
        "select_substitute" => &["exercise_id", "name"],
        _ => &["name"],
    };
    if object.len() != allowed.len() || allowed.iter().any(|key| !object.contains_key(*key)) {
        return Err(ContentError::InvalidSession);
    }
    Ok(event)
}

fn dispatch(
    session: &mut Session,
    event: &SessionEvent,
    now: u64,
    eligible: &[String],
    library: &[Exercise],
) -> Result<(), ContentError> {
    match event {
        SessionEvent::Ready => on_ready(session),
        SessionEvent::CompleteRep => on_complete_rep(session, now),
        SessionEvent::Tick => on_tick(session, now),
        SessionEvent::Pause => on_pause(session),
        SessionEvent::Resume => on_resume(session),
        SessionEvent::ReportPain {
            symptom,
            reported_pain,
        } => on_pain(session, *symptom, *reported_pain),
        SessionEvent::ContinueAfterPain => on_continue(session),
        SessionEvent::SelectSubstitute { exercise_id } => {
            on_substitute(session, exercise_id, eligible, library)
        }
        SessionEvent::Skip => on_skip(session),
        SessionEvent::Shorten => on_shorten(session),
        SessionEvent::EndSession => on_end(session),
    }
}

fn on_ready(session: &mut Session) -> Result<(), ContentError> {
    session.state = match session.state {
        SessionState::Preparing => SessionState::Demonstrating,
        SessionState::Demonstrating => SessionState::Active,
        _ => return Err(ContentError::InvalidSession),
    };
    Ok(())
}

fn on_complete_rep(session: &mut Session, now: u64) -> Result<(), ContentError> {
    if session.state != SessionState::Active {
        return Err(ContentError::InvalidSession);
    }
    let index = current_index(session).ok_or(ContentError::InvalidSession)?;
    let exercise = &mut session.exercises[index];
    if exercise.reps_done >= exercise.reps {
        return Err(ContentError::InvalidSession);
    }
    exercise.reps_done += 1;
    if exercise.reps_done < exercise.reps {
        return Ok(());
    }
    if has_another_set(exercise) {
        let pause_ms = u64::from(exercise.tempo.pause).saturating_mul(1000);
        session.rest_until_ms = Some(add_signed_clock(now, pause_ms)?);
        session.state = SessionState::Resting;
        return Ok(());
    }
    advance(session);
    Ok(())
}

fn on_tick(session: &mut Session, now: u64) -> Result<(), ContentError> {
    if session.state != SessionState::Resting {
        return Err(ContentError::InvalidSession);
    }
    let Some(until) = session.rest_until_ms else {
        return Err(ContentError::InvalidSession);
    };
    if now < until {
        return Err(ContentError::InvalidSession);
    }
    let index = current_index(session).ok_or(ContentError::InvalidSession)?;
    let exercise = &mut session.exercises[index];
    let Some(next_index) = exercise.set_index.checked_add(1) else {
        return Err(ContentError::InvalidSession);
    };
    if next_index >= exercise.sets {
        return Err(ContentError::InvalidSession);
    }
    exercise.set_index = next_index;
    exercise.reps_done = 0;
    session.rest_until_ms = None;
    session.state = SessionState::Active;
    Ok(())
}

fn on_pause(session: &mut Session) -> Result<(), ContentError> {
    if !matches!(session.state, SessionState::Active | SessionState::Resting) {
        return Err(ContentError::InvalidSession);
    }
    session.state = SessionState::Paused;
    Ok(())
}

fn on_resume(session: &mut Session) -> Result<(), ContentError> {
    if session.state != SessionState::Paused {
        return Err(ContentError::InvalidSession);
    }
    session.state = if session.rest_until_ms.is_some() {
        SessionState::Resting
    } else {
        SessionState::Active
    };
    Ok(())
}

fn on_pain(session: &mut Session, symptom: Symptom, reported_pain: u8) -> Result<(), ContentError> {
    if !matches!(session.state, SessionState::Active | SessionState::Resting) || reported_pain > 10
    {
        return Err(ContentError::InvalidSession);
    }
    session.symptom = Some(symptom);
    session.reported_pain = Some(reported_pain);
    session.state = SessionState::PainCheck;
    Ok(())
}

fn on_continue(session: &mut Session) -> Result<(), ContentError> {
    if session.state != SessionState::PainCheck {
        return Err(ContentError::InvalidSession);
    }
    session.state = SessionState::Paused;
    Ok(())
}

fn on_substitute(
    session: &mut Session,
    exercise_id: &str,
    eligible: &[String],
    library: &[Exercise],
) -> Result<(), ContentError> {
    if session.state != SessionState::PainCheck {
        return Err(ContentError::InvalidSession);
    }
    let index = current_index(session).ok_or(ContentError::InvalidSession)?;
    if !session.exercises[index]
        .substitutions
        .iter()
        .any(|id| id == exercise_id)
        || !eligible.iter().any(|id| id == exercise_id)
    {
        return Err(ContentError::InvalidSession);
    }
    let Some(replacement) = library
        .iter()
        .find(|exercise| exercise.id.as_str() == exercise_id)
    else {
        return Err(ContentError::InvalidSession);
    };
    if replacement.default_sets == 0 || replacement.default_reps == 0 {
        return Err(ContentError::InvalidSession);
    }
    session.exercises[index] = SessionExercise {
        exercise_id: exercise_id.to_owned(),
        reps_done: 0,
        set_index: 0,
        sets: u32::from(replacement.default_sets),
        reps: u32::from(replacement.default_reps),
        skipped: false,
        tempo: replacement.tempo,
        substitutions: substitution_ids(replacement),
    };
    session.rest_until_ms = None;
    session.state = SessionState::Demonstrating;
    Ok(())
}

fn on_skip(session: &mut Session) -> Result<(), ContentError> {
    if !matches!(
        session.state,
        SessionState::Demonstrating | SessionState::Active | SessionState::Paused
    ) {
        return Err(ContentError::InvalidSession);
    }
    let index = current_index(session).ok_or(ContentError::InvalidSession)?;
    session.exercises[index].skipped = true;
    session.rest_until_ms = None;
    advance(session);
    Ok(())
}

fn on_shorten(session: &mut Session) -> Result<(), ContentError> {
    if session.state != SessionState::Paused {
        return Err(ContentError::InvalidSession);
    }
    let index = current_index(session).ok_or(ContentError::InvalidSession)?;
    session.exercises.truncate(index + 1);
    Ok(())
}

fn on_end(session: &mut Session) -> Result<(), ContentError> {
    let outcome = match session.state {
        SessionState::Paused => "abandoned",
        SessionState::PainCheck => "safety_stopped",
        _ => return Err(ContentError::InvalidSession),
    };
    close(session, outcome);
    Ok(())
}

fn advance(session: &mut Session) {
    if let Some(index) = session
        .exercises
        .iter()
        .position(|exercise| !finished_row(exercise))
    {
        let _ = index;
        session.state = SessionState::Demonstrating;
        session.rest_until_ms = None;
        return;
    }
    let outcome = if session
        .exercises
        .iter()
        .any(|exercise| exercise.reps_done > 0)
    {
        "completed"
    } else {
        "abandoned"
    };
    close(session, outcome);
}

fn close(session: &mut Session, outcome: &str) {
    session.outcome = Some(outcome.to_owned());
    session.rest_until_ms = None;
    session.state = match outcome {
        "completed" => SessionState::Completed,
        "safety_stopped" => SessionState::SafetyStopped,
        _ => SessionState::Abandoned,
    };
}

fn current_index(session: &Session) -> Option<usize> {
    session
        .exercises
        .iter()
        .position(|exercise| !finished_row(exercise))
}

fn finished_row(exercise: &SessionExercise) -> bool {
    exercise.skipped || (exercise.reps_done >= exercise.reps && !has_another_set(exercise))
}

fn has_another_set(exercise: &SessionExercise) -> bool {
    match exercise.set_index.checked_add(1) {
        Some(next) => next < exercise.sets,
        None => false,
    }
}

fn add_signed_clock(left: u64, right: u64) -> Result<u64, ContentError> {
    let sum = left
        .checked_add(right)
        .ok_or(ContentError::InvalidSession)?;
    if sum > i64::MAX as u64 {
        return Err(ContentError::InvalidSession);
    }
    Ok(sum)
}

fn copy_exercise(row: &Value, library: &[Exercise]) -> Result<SessionExercise, ContentError> {
    let Some(object) = row.as_object() else {
        return Err(ContentError::InvalidSession);
    };
    let Some(exercise_id) = object.get("exercise_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidSession);
    };
    if !exact(object.get("exercise_version"), 1) {
        return Err(ContentError::InvalidSession);
    }
    let Some(fixture) = library
        .iter()
        .find(|exercise| exercise.id.as_str() == exercise_id)
    else {
        return Err(ContentError::InvalidSession);
    };
    let sets = required_u64(object.get("sets"))?;
    let reps = required_u64(object.get("reps"))?;
    if sets != u64::from(fixture.default_sets)
        || reps != u64::from(fixture.default_reps)
        || sets == 0
        || reps == 0
    {
        return Err(ContentError::InvalidSession);
    }
    let tempo = tempo_from(object.get("tempo"))?;
    if tempo != fixture.tempo {
        return Err(ContentError::InvalidSession);
    }
    Ok(SessionExercise {
        exercise_id: exercise_id.to_owned(),
        reps_done: 0,
        set_index: 0,
        sets: u32::try_from(sets).map_err(|_| ContentError::InvalidSession)?,
        reps: u32::try_from(reps).map_err(|_| ContentError::InvalidSession)?,
        skipped: false,
        tempo,
        substitutions: substitution_ids(fixture),
    })
}

fn parse_exercise_row(row: &Value, library: &[Exercise]) -> Result<SessionExercise, ContentError> {
    let Some(object) = row.as_object() else {
        return Err(ContentError::InvalidSession);
    };
    if object.len() != EXERCISE_KEYS.len()
        || EXERCISE_KEYS.iter().any(|key| !object.contains_key(*key))
    {
        return Err(ContentError::InvalidSession);
    }
    let Some(exercise_id) = object.get("exercise_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidSession);
    };
    let Some(skipped) = object.get("skipped").and_then(Value::as_bool) else {
        return Err(ContentError::InvalidSession);
    };
    let sets = required_u32(object.get("sets"))?;
    let reps = required_u32(object.get("reps"))?;
    if sets == 0 || reps == 0 {
        return Err(ContentError::InvalidSession);
    }
    let Some(fixture) = library
        .iter()
        .find(|exercise| exercise.id.as_str() == exercise_id)
    else {
        return Err(ContentError::InvalidSession);
    };
    let tempo = tempo_from(object.get("tempo"))?;
    if sets != u32::from(fixture.default_sets)
        || reps != u32::from(fixture.default_reps)
        || tempo != fixture.tempo
    {
        return Err(ContentError::InvalidSession);
    }
    Ok(SessionExercise {
        exercise_id: exercise_id.to_owned(),
        reps_done: required_u32(object.get("reps_done"))?,
        set_index: required_u32(object.get("set_index"))?,
        sets,
        reps,
        skipped,
        tempo,
        substitutions: substitution_ids(fixture),
    })
}

fn substitution_ids(exercise: &Exercise) -> Vec<String> {
    exercise
        .substitutions
        .iter()
        .map(|id| id.as_str().to_owned())
        .collect()
}

fn tempo_from(value: Option<&Value>) -> Result<Tempo, ContentError> {
    let Some(object) = value.and_then(Value::as_object) else {
        return Err(ContentError::InvalidSession);
    };
    if object.len() != 3
        || !object.contains_key("concentric")
        || !object.contains_key("eccentric")
        || !object.contains_key("pause")
    {
        return Err(ContentError::InvalidSession);
    }
    Ok(Tempo {
        concentric: required_u8(object.get("concentric"))?,
        eccentric: required_u8(object.get("eccentric"))?,
        pause: required_u8(object.get("pause"))?,
    })
}

fn exact(value: Option<&Value>, expected: i64) -> bool {
    value.and_then(Value::as_i64) == Some(expected)
}

fn number(value: u64) -> Result<Value, ContentError> {
    Number::from_u128(u128::from(value))
        .map(Value::Number)
        .ok_or(ContentError::InvalidSession)
}

fn required_u64(value: Option<&Value>) -> Result<u64, ContentError> {
    value
        .and_then(Value::as_u64)
        .ok_or(ContentError::InvalidSession)
}

fn optional_u64(value: Option<&Value>) -> Result<Option<u64>, ContentError> {
    match value {
        Some(Value::Null) => Ok(None),
        Some(other) => other.as_u64().map(Some).ok_or(ContentError::InvalidSession),
        None => Err(ContentError::InvalidSession),
    }
}

fn required_u32(value: Option<&Value>) -> Result<u32, ContentError> {
    let number = required_u64(value)?;
    u32::try_from(number).map_err(|_| ContentError::InvalidSession)
}

fn required_u8(value: Option<&Value>) -> Result<u8, ContentError> {
    let number = required_u64(value)?;
    u8::try_from(number).map_err(|_| ContentError::InvalidSession)
}

fn optional_u8(value: Option<&Value>) -> Result<Option<u8>, ContentError> {
    match optional_u64(value)? {
        None => Ok(None),
        Some(number) => u8::try_from(number)
            .map(Some)
            .map_err(|_| ContentError::InvalidSession),
    }
}
