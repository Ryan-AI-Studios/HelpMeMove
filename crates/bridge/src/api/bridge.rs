use helpmemove_content::{
    AdaptationDecision, AdaptationError, AssessedArea, ContentError, Equipment, Exercise,
    FIXTURE_PACK_VERIFYING_KEY, FlareDecision, FlareError, Goal, MovementRating, ProgramRule,
    ProgressError, Region, Session, SessionEvent, StartingExercise, apply_session_event,
    decide_adaptation, decide_flare, evaluate_pack, flare_followup_envelope, open_session,
    parse_adaptation_rule, parse_assessment_instrument, parse_disable_list, parse_exercise,
    parse_flare_rule, parse_followup, parse_program_rule, parse_readiness, parse_session,
    parse_signature_hex, read_intake_safety_answers, read_program_assessment, read_program_intake,
    read_session_event, recalled_sessions as list_recalled_sessions, render_session,
    render_starting_program, summarize_progress, verify_disable_list as verify_disable_list_bytes,
};
use helpmemove_domain::{
    BRIDGE_VERSION, Confidence, DomainError, DomainInstant, Laterality,
    PoseFrame as DomainPoseFrame, SubjectId, elapsed_millis as domain_elapsed_millis,
    length_mm_to_inch_thousandths, normalize_pose_frame, observe_cancel as domain_observe_cancel,
    require_version as domain_require_version,
};
use helpmemove_safety::{
    ActiveIssue, Classification, DeniedReason, Eligibility, Escalation, SafetyError,
    ScreenDecision, TriageLevel, classify, emergency_display as safety_emergency_display,
    parse_rule_set, screen_exercise,
};

const COMMITTED_RULE: &str = include_str!("../../../../content/rules/syn-safety-core.json");
const COMMITTED_INSTRUMENT: &str =
    include_str!("../../../../content/assessments/syn-assessment-core.json");
const COMMITTED_PROGRAM: &str = include_str!("../../../../content/programs/syn-program-core.json");
const COMMITTED_ADAPTATION: &str =
    include_str!("../../../../content/adaptations/syn-adaptation-core.json");
const COMMITTED_FLARE: &str = include_str!("../../../../content/flares/syn-flare-core.json");
const EXERCISE_KNEE: &str =
    include_str!("../../../../content/exercises/syn-knee-sit-to-stand.json");
const EXERCISE_BAND: &str = include_str!("../../../../content/exercises/syn-shoulder-band.json");
const EXERCISE_ISOMETRIC: &str =
    include_str!("../../../../content/exercises/syn-shoulder-isometric.json");
const EXERCISE_TORSO: &str =
    include_str!("../../../../content/exercises/syn-torso-pelvic-tilt.json");
const COMMITTED_DISABLE_LIST: &str =
    include_str!("../../../../content/packs/syn-disable-list.json");
const COMMITTED_DISABLE_LIST_SIG: &str =
    include_str!("../../../../content/packs/syn-disable-list.sig");

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
    InvalidRating,
    InvalidInstrument,
    InvalidProgram,
    InvalidPoseFrame,
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
            Self::InvalidRating => "invalid-rating",
            Self::InvalidInstrument => "invalid-instrument",
            Self::InvalidProgram => "invalid-program",
            Self::InvalidPoseFrame => "invalid-pose-frame",
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
            DomainError::InvalidPoseFrame => Self::InvalidPoseFrame,
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssessmentVocabulary {
    pub ratings: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AssessmentInstrumentView {
    pub instrument_id: String,
    pub instrument_version: i64,
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

/// One landmark. `z` has no angle meaning.
#[derive(Debug, Clone, PartialEq)]
pub struct PosePoint {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub visibility: f64,
    pub presence: f64,
}

/// Thirty-three landmarks and the caller timestamp. No image bytes.
#[derive(Debug, Clone, PartialEq)]
pub struct PoseFrame {
    pub timestamp_unix_ms: i64,
    pub points: Vec<PosePoint>,
}

#[flutter_rust_bridge::frb(sync)]
#[allow(clippy::too_many_arguments)]
pub fn accept_pose_frame(
    x: Vec<f64>,
    y: Vec<f64>,
    z: Vec<f64>,
    visibility: Vec<f64>,
    presence: Vec<f64>,
    timestamp_unix_ms: i64,
    rotation_degrees: i32,
    mirrored: bool,
) -> Result<PoseFrame, BridgeError> {
    let frame: DomainPoseFrame = normalize_pose_frame(
        &x,
        &y,
        &z,
        &visibility,
        &presence,
        timestamp_unix_ms,
        rotation_degrees,
        mirrored,
    )?;
    Ok(PoseFrame {
        timestamp_unix_ms: frame.timestamp_unix_ms,
        points: frame
            .points
            .into_iter()
            .map(|point| PosePoint {
                x: point.x,
                y: point.y,
                z: point.z,
                visibility: point.visibility,
                presence: point.presence,
            })
            .collect(),
    })
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

/// Ratings in fixture order. This list is not sorted.
#[flutter_rust_bridge::frb(sync)]
pub fn assessment_vocabulary() -> AssessmentVocabulary {
    AssessmentVocabulary {
        ratings: [
            MovementRating::Normal,
            MovementRating::Limited,
            MovementRating::Painful,
            MovementRating::VeryPainful,
            MovementRating::Unable,
        ]
        .into_iter()
        .map(|rating| rating.as_str().to_owned())
        .collect(),
    }
}

/// Accept a movement-rating token. Invalid input does not echo the raw value.
#[flutter_rust_bridge::frb(sync)]
pub fn accept_rating(raw: String) -> Result<String, BridgeError> {
    match MovementRating::parse(&raw) {
        Some(rating) => Ok(rating.as_str().to_owned()),
        None => Err(BridgeError::InvalidRating),
    }
}

/// Load the committed fixture id and version. A parse failure is `InvalidInstrument`.
#[flutter_rust_bridge::frb(sync)]
pub fn load_committed_instrument() -> Result<AssessmentInstrumentView, BridgeError> {
    instrument_view(COMMITTED_INSTRUMENT)
}

fn instrument_view(text: &str) -> Result<AssessmentInstrumentView, BridgeError> {
    match parse_assessment_instrument(text) {
        Ok(instrument) => Ok(AssessmentInstrumentView {
            instrument_id: instrument.instrument_id.to_owned(),
            instrument_version: i64::from(instrument.instrument_version),
        }),
        Err(_) => Err(BridgeError::InvalidInstrument),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgramRuleView {
    pub rule_id: String,
    pub rule_version: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExerciseDisplay {
    pub name: String,
    pub written_instructions: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StartingPlan {
    pub outcome: String,
    pub withhold_code: String,
    pub document_json: String,
}

/// Selector result. Dart cannot construct the classification that produced it.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgramSelection {
    pub code: &'static str,
    pub document_json: String,
}

/// Load the committed program fixture id and version. A parse failure is `InvalidProgram`.
#[flutter_rust_bridge::frb(sync)]
pub fn load_committed_program_rule() -> Result<ProgramRuleView, BridgeError> {
    program_rule_view(COMMITTED_PROGRAM)
}

/// Name and written instructions for one embedded fixture. Unknown ids stay out of the error.
#[flutter_rust_bridge::frb(sync)]
pub fn exercise_display(exercise_id: String) -> Result<ExerciseDisplay, BridgeError> {
    let exercises = embedded_exercises()?;
    for exercise in exercises {
        if exercise.id.as_str() == exercise_id {
            return Ok(ExerciseDisplay {
                name: exercise.name,
                written_instructions: exercise.written_instructions,
            });
        }
    }
    Err(BridgeError::InvalidProgram)
}

/// Classify the committed rule with `schema_ack=yes` only, then select.
///
/// The production answer does not permit ordinary generation.
#[flutter_rust_bridge::frb(sync)]
pub fn compose_starting_plan(
    intake_document: String,
    assessment_document: String,
    now_unix_millis: i64,
) -> StartingPlan {
    let Ok(intake) = read_program_intake(&intake_document) else {
        return withheld_plan("intake_unusable");
    };
    let Ok(areas) = read_program_assessment(&assessment_document) else {
        return withheld_plan("assessment_incomplete");
    };
    let Ok(rule) = parse_rule_set(COMMITTED_RULE.as_bytes()) else {
        return withheld_plan("generation_denied");
    };
    let now = DomainInstant::from_unix_millis(now_unix_millis);
    let Ok(classification) = classify(&rule, &[("schema_ack", "yes")], now, &[]) else {
        return withheld_plan("generation_denied");
    };
    let Ok(program_rule) = parse_program_rule(COMMITTED_PROGRAM) else {
        return withheld_plan("generation_denied");
    };
    let Ok(exercises) = embedded_exercises() else {
        return withheld_plan("generation_denied");
    };
    let selection = select_program(
        &classification,
        &intake.goals,
        &intake.equipment,
        &areas,
        &exercises,
        &program_rule,
    );
    if selection.code == "ready" {
        StartingPlan {
            outcome: "ready".to_owned(),
            withhold_code: String::new(),
            document_json: selection.document_json,
        }
    } else {
        withheld_plan(selection.code)
    }
}

/// Copy fixture counts for exercises `screen_exercise` accepts. No clock and no dose.
#[flutter_rust_bridge::frb(ignore)]
pub fn select_program(
    classification: &Classification,
    goals: &[Goal],
    equipment: &[Equipment],
    areas: &[AssessedArea],
    exercises: &[Exercise],
    rule: &ProgramRule,
) -> ProgramSelection {
    let issues = active_issues_for_areas(areas);
    let mut assessed = Vec::new();
    for area in areas {
        if assessed.contains(&area.region) {
            continue;
        }
        assessed.push(area.region);
    }
    let mut ordered: Vec<&Exercise> = exercises.iter().collect();
    ordered.sort_by(|left, right| left.id.cmp(&right.id));
    // Generation is a property of the classification. One probe fails closed.
    let Some(probe) = ordered.first() else {
        return ProgramSelection::withheld("generation_denied");
    };
    match screen_exercise(classification, &issues, *probe) {
        Ok(ScreenDecision::Denied(DeniedReason::GenerationDenied)) | Err(_) => {
            return ProgramSelection::withheld("generation_denied");
        }
        Ok(ScreenDecision::Eligible | ScreenDecision::Denied(DeniedReason::Contraindicated)) => {}
    }
    let Ok(cap) = usize::try_from(rule.max_exercises) else {
        return ProgramSelection::withheld("generation_denied");
    };
    let mut included = Vec::new();
    for exercise in ordered {
        if included.len() >= cap {
            break;
        }
        if !exercise
            .regions
            .iter()
            .any(|region| assessed.contains(region))
        {
            continue;
        }
        if exercise.equipment.is_empty()
            || exercise
                .equipment
                .iter()
                .any(|item| !equipment.contains(item))
        {
            continue;
        }
        let Some(goal) = exercise.goals.iter().find(|goal| goals.contains(goal)) else {
            continue;
        };
        let Some(region) = exercise
            .regions
            .iter()
            .find(|region| assessed.contains(region))
        else {
            continue;
        };
        let Some(item) = exercise.equipment.first() else {
            continue;
        };
        match screen_exercise(classification, &issues, exercise) {
            Ok(ScreenDecision::Eligible) => included.push(StartingExercise {
                exercise_id: exercise.id.as_str().to_owned(),
                regions: exercise.regions.clone(),
                sets: exercise.default_sets,
                reps: exercise.default_reps,
                tempo: exercise.tempo,
                region: *region,
                equipment: *item,
                goal: *goal,
            }),
            Ok(ScreenDecision::Denied(DeniedReason::Contraindicated)) => {}
            Ok(ScreenDecision::Denied(DeniedReason::GenerationDenied)) | Err(_) => {
                return ProgramSelection::withheld("generation_denied");
            }
        }
    }
    if included.is_empty() {
        return ProgramSelection::withheld("no_candidate");
    }
    match render_starting_program(rule, &included) {
        Ok(document) => ProgramSelection::ready(document),
        Err(_) => ProgramSelection::withheld("generation_denied"),
    }
}

impl ProgramSelection {
    fn ready(document_json: String) -> Self {
        Self {
            code: "ready",
            document_json,
        }
    }

    fn withheld(code: &'static str) -> Self {
        Self {
            code,
            document_json: String::new(),
        }
    }
}

fn program_rule_view(text: &str) -> Result<ProgramRuleView, BridgeError> {
    match parse_program_rule(text) {
        Ok(rule) => Ok(ProgramRuleView {
            rule_id: rule.rule_id.to_owned(),
            rule_version: i64::from(rule.rule_version),
        }),
        Err(_) => Err(BridgeError::InvalidProgram),
    }
}

fn embedded_exercises() -> Result<Vec<Exercise>, BridgeError> {
    let mut exercises = Vec::with_capacity(4);
    for text in [
        EXERCISE_KNEE,
        EXERCISE_BAND,
        EXERCISE_ISOMETRIC,
        EXERCISE_TORSO,
    ] {
        let exercise = parse_exercise(text.as_bytes()).map_err(|_| BridgeError::InvalidProgram)?;
        exercises.push(exercise);
    }
    Ok(exercises)
}

fn withheld_plan(code: &str) -> StartingPlan {
    StartingPlan {
        outcome: "withheld".to_owned(),
        withhold_code: code.to_owned(),
        document_json: String::new(),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkoutView {
    pub outcome: String,
    pub error_code: String,
    pub document_json: String,
}

/// Open a synthetic session from a stored program row.
///
/// Counts come from the embedded fixtures. This does not classify or screen.
#[flutter_rust_bridge::frb(sync)]
pub fn open_workout(
    program_json: String,
    monotonic_millis: i64,
    session_id: String,
) -> WorkoutView {
    let Ok(now) = u64::try_from(monotonic_millis) else {
        return workout_unavailable("invalid-session");
    };
    let Ok(exercises) = embedded_exercises() else {
        return workout_unavailable("invalid-session");
    };
    match open_session(&program_json, &exercises, now, &session_id) {
        Ok(session) => match render_session(&session) {
            Ok(document) => workout_ready(document),
            Err(error) => workout_from_content(error),
        },
        Err(error) => workout_from_content(error),
    }
}

/// Apply one manual event. A substitute is screened here; content does not call safety.
///
/// The production classification is `schema_ack=yes` only, so the eligible list is empty.
#[flutter_rust_bridge::frb(sync)]
pub fn apply_workout_event(
    document_json: String,
    event_json: String,
    monotonic_millis: i64,
) -> WorkoutView {
    let Ok(now) = u64::try_from(monotonic_millis) else {
        return workout_unavailable("invalid-session");
    };
    let Ok(exercises) = embedded_exercises() else {
        return workout_unavailable("invalid-session");
    };
    let Ok(session) = parse_session(&document_json, &exercises) else {
        return workout_unavailable("invalid-session");
    };
    let Ok(event) = read_session_event(&event_json) else {
        return workout_unavailable("invalid-session");
    };
    let eligible = match &event {
        SessionEvent::SelectSubstitute { .. } => eligible_substitutions(&session, &exercises),
        _ => Vec::new(),
    };
    match apply_session_event(&session, &event, now, &eligible, &exercises) {
        Ok(next) => match render_session(&next) {
            Ok(document) => workout_ready(document),
            Err(error) => workout_from_content(error),
        },
        Err(error) => workout_from_content(error),
    }
}

fn eligible_substitutions(session: &Session, exercises: &[Exercise]) -> Vec<String> {
    let Some(current) = session.exercises.iter().find(|row| {
        !row.skipped && (row.reps_done < row.reps || row.set_index.saturating_add(1) < row.sets)
    }) else {
        return Vec::new();
    };
    if current.substitutions.is_empty() {
        return Vec::new();
    }
    let Ok(rule) = parse_rule_set(COMMITTED_RULE.as_bytes()) else {
        return Vec::new();
    };
    let Ok(classification) = classify(
        &rule,
        &[("schema_ack", "yes")],
        DomainInstant::from_unix_millis(0),
        &[],
    ) else {
        return Vec::new();
    };
    let mut eligible = Vec::new();
    for id in &current.substitutions {
        let Some(exercise) = exercises.iter().find(|item| item.id.as_str() == id) else {
            continue;
        };
        if matches!(
            screen_exercise(&classification, &[], exercise),
            Ok(ScreenDecision::Eligible)
        ) {
            eligible.push(id.clone());
        }
    }
    eligible
}

fn workout_ready(document_json: String) -> WorkoutView {
    WorkoutView {
        outcome: "ready".to_owned(),
        error_code: String::new(),
        document_json,
    }
}

fn workout_unavailable(code: &str) -> WorkoutView {
    WorkoutView {
        outcome: "unavailable".to_owned(),
        error_code: code.to_owned(),
        document_json: String::new(),
    }
}

fn workout_from_content(error: ContentError) -> WorkoutView {
    let code = match error {
        ContentError::SessionClosed => "session-closed",
        ContentError::ClockWentBackwards => "clock-went-backwards",
        _ => "invalid-session",
    };
    workout_unavailable(code)
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

/// One issue per distinct assessed region, in first-seen order.
#[flutter_rust_bridge::frb(ignore)]
pub fn active_issues_for_areas(areas: &[AssessedArea]) -> Vec<ActiveIssue> {
    let mut issues = Vec::new();
    let mut assessed = Vec::new();
    for area in areas {
        if assessed.contains(&area.region) {
            continue;
        }
        assessed.push(area.region);
        let mut id = String::from("area-");
        id.push_str(area.region.as_str());
        issues.push(ActiveIssue {
            id,
            restrictions: Vec::new(),
        });
    }
    issues
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdaptationView {
    pub outcome: String,
    pub withhold_code: String,
    pub document_json: String,
}

/// Decide the next session from stored documents. Flutter passes no eligible list.
#[flutter_rust_bridge::frb(sync)]
pub fn prepare_adaptation(
    intake_json: String,
    assessment_json: String,
    program_json: String,
    workout_json: String,
    readiness_json: String,
) -> AdaptationView {
    if intake_json.is_empty() {
        return adaptation_withheld("intake_unusable");
    }
    if assessment_json.is_empty() {
        return adaptation_withheld("assessment_incomplete");
    }
    if program_json.is_empty() {
        return adaptation_withheld("no_program");
    }
    if workout_json.is_empty() {
        return adaptation_withheld("no_terminal_workout");
    }
    if readiness_json.is_empty() {
        return adaptation_withheld("readiness_unusable");
    }
    let Ok(readiness) = parse_readiness(&readiness_json) else {
        return adaptation_withheld("readiness_unusable");
    };
    let Ok(answers) = read_intake_safety_answers(&intake_json) else {
        return adaptation_withheld("intake_unusable");
    };
    let Ok(rule) = parse_rule_set(COMMITTED_RULE.as_bytes()) else {
        return adaptation_withheld("progression_denied");
    };
    let Ok(millis) = i64::try_from(readiness.recorded_at_ms) else {
        return adaptation_withheld("readiness_unusable");
    };
    let pairs: Vec<(&str, &str)> = answers
        .iter()
        .map(|(token, value)| (token.as_str(), value.as_str()))
        .collect();
    let Ok(classification) = classify(&rule, &pairs, DomainInstant::from_unix_millis(millis), &[])
    else {
        return adaptation_withheld("progression_denied");
    };
    if !classification.permits_progression || classification.screening_required {
        return adaptation_withheld("progression_denied");
    }
    let Ok(areas) = read_program_assessment(&assessment_json) else {
        return adaptation_withheld("assessment_incomplete");
    };
    let issues = active_issues_for_areas(&areas);
    let Ok(library) = embedded_exercises() else {
        return adaptation_withheld("program_unusable");
    };
    if library.is_empty() {
        return adaptation_withheld("program_unusable");
    }
    let Ok(program) = open_session(&program_json, &library, 0, "adaptation-probe") else {
        return adaptation_withheld("program_unusable");
    };
    let mut eligible = Vec::with_capacity(program.exercises.len());
    for exercise in &program.exercises {
        let Some(fixture) = library
            .iter()
            .find(|item| item.id.as_str() == exercise.exercise_id)
        else {
            return adaptation_withheld("program_unusable");
        };
        match screen_exercise(&classification, &issues, fixture) {
            Ok(ScreenDecision::Eligible) => eligible.push(exercise.exercise_id.clone()),
            _ => return adaptation_withheld("exercise_denied"),
        }
    }
    let eligible_ids: Vec<&str> = eligible.iter().map(String::as_str).collect();
    if parse_adaptation_rule(COMMITTED_ADAPTATION).is_err() {
        return adaptation_withheld("program_unusable");
    }
    match decide_adaptation(
        &workout_json,
        &program_json,
        &readiness_json,
        COMMITTED_ADAPTATION,
        &library,
        &eligible_ids,
        classification.permits_progression,
    ) {
        Ok(AdaptationDecision::Ready(document)) => AdaptationView {
            outcome: "ready".to_owned(),
            withhold_code: String::new(),
            document_json: document,
        },
        Ok(AdaptationDecision::Withheld(code)) => adaptation_withheld(code),
        Err(AdaptationError::ProgramRejected) => adaptation_withheld("program_unusable"),
        Err(AdaptationError::WorkoutRejected) => adaptation_withheld("no_terminal_workout"),
        Err(AdaptationError::Invalid) => adaptation_withheld("readiness_unusable"),
    }
}

fn adaptation_withheld(code: &str) -> AdaptationView {
    AdaptationView {
        outcome: "withheld".to_owned(),
        withhold_code: code.to_owned(),
        document_json: String::new(),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FlareView {
    pub outcome: String,
    pub withhold_code: String,
    pub document_json: String,
}

/// Decide the follow-up from stored documents. Flutter passes no eligible list.
#[flutter_rust_bridge::frb(sync)]
pub fn prepare_flare_followup(
    intake_json: String,
    assessment_json: String,
    program_json: String,
    workout_json: String,
    followup_json: String,
) -> FlareView {
    if intake_json.is_empty() {
        return flare_withheld("intake_unusable");
    }
    if assessment_json.is_empty() {
        return flare_withheld("assessment_incomplete");
    }
    if program_json.is_empty() {
        return flare_withheld("no_program");
    }
    if workout_json.is_empty() {
        return flare_withheld("no_terminal_workout");
    }
    if followup_json.is_empty() {
        return flare_withheld("followup_unusable");
    }
    let Ok(followup) = parse_followup(&followup_json) else {
        return flare_withheld("followup_unusable");
    };
    let Ok(answers) = read_intake_safety_answers(&intake_json) else {
        return flare_withheld("intake_unusable");
    };
    let Ok(rule) = parse_rule_set(COMMITTED_RULE.as_bytes()) else {
        return flare_withheld("progression_denied");
    };
    let Ok(millis) = i64::try_from(followup.recorded_at_ms) else {
        return flare_withheld("followup_unusable");
    };
    let pairs: Vec<(&str, &str)> = answers
        .iter()
        .map(|(token, value)| (token.as_str(), value.as_str()))
        .collect();
    let Ok(classification) = classify(&rule, &pairs, DomainInstant::from_unix_millis(millis), &[])
    else {
        return flare_withheld("progression_denied");
    };
    if !classification.permits_progression || classification.screening_required {
        return flare_withheld("progression_denied");
    }
    let Ok(areas) = read_program_assessment(&assessment_json) else {
        return flare_withheld("assessment_incomplete");
    };
    let issues = active_issues_for_areas(&areas);
    let Ok(library) = embedded_exercises() else {
        return flare_withheld("program_unusable");
    };
    if library.is_empty() {
        return flare_withheld("program_unusable");
    }
    let Ok(program) = open_session(&program_json, &library, 0, "flare-probe") else {
        return flare_withheld("program_unusable");
    };
    let mut eligible = Vec::with_capacity(program.exercises.len());
    for exercise in &program.exercises {
        let Some(fixture) = library
            .iter()
            .find(|item| item.id.as_str() == exercise.exercise_id)
        else {
            return flare_withheld("program_unusable");
        };
        match screen_exercise(&classification, &issues, fixture) {
            Ok(ScreenDecision::Eligible) => eligible.push(exercise.exercise_id.clone()),
            _ => return flare_withheld("exercise_denied"),
        }
    }
    let eligible_ids: Vec<&str> = eligible.iter().map(String::as_str).collect();
    if parse_flare_rule(COMMITTED_FLARE).is_err() {
        return flare_withheld("program_unusable");
    }
    match decide_flare(
        &workout_json,
        &program_json,
        &followup_json,
        COMMITTED_FLARE,
        &library,
        &eligible_ids,
        classification.permits_progression,
    ) {
        Ok(FlareDecision::Ready(document)) => {
            let Ok(envelope) = flare_followup_envelope(&followup_json, &document) else {
                return flare_withheld("followup_unusable");
            };
            FlareView {
                outcome: "ready".to_owned(),
                withhold_code: String::new(),
                document_json: envelope,
            }
        }
        Ok(FlareDecision::Withheld(code)) => flare_withheld(code),
        Err(FlareError::ProgramRejected) => flare_withheld("program_unusable"),
        Err(FlareError::WorkoutRejected) => flare_withheld("no_terminal_workout"),
        Err(FlareError::Invalid) => flare_withheld("followup_unusable"),
    }
}

fn flare_withheld(code: &str) -> FlareView {
    FlareView {
        outcome: "withheld".to_owned(),
        withhold_code: code.to_owned(),
        document_json: String::new(),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProgressView {
    pub outcome: String,
    pub withhold_code: String,
    pub document_json: String,
}

/// Count stored session rows. Flutter passes the entry list and no library.
#[flutter_rust_bridge::frb(sync)]
pub fn prepare_progress_summary(entries_json: String) -> ProgressView {
    if entries_json.is_empty() {
        return progress_withheld("workout_unusable");
    }
    let Ok(library) = embedded_exercises() else {
        return progress_withheld("library_unusable");
    };
    if library.is_empty() {
        return progress_withheld("library_unusable");
    }
    match summarize_progress(&entries_json, &library) {
        Ok(document) => ProgressView {
            outcome: "ready".to_owned(),
            withhold_code: String::new(),
            document_json: document,
        },
        Err(ProgressError::LibraryRejected) => progress_withheld("library_unusable"),
        Err(ProgressError::Invalid) => progress_withheld("workout_unusable"),
    }
}

fn progress_withheld(code: &str) -> ProgressView {
    ProgressView {
        outcome: "withheld".to_owned(),
        withhold_code: code.to_owned(),
        document_json: String::new(),
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

#[flutter_rust_bridge::frb(sync)]
pub fn committed_disable_list() -> String {
    COMMITTED_DISABLE_LIST.to_owned()
}

#[flutter_rust_bridge::frb(sync)]
pub fn committed_disable_list_sig() -> String {
    COMMITTED_DISABLE_LIST_SIG.trim().to_owned()
}

#[flutter_rust_bridge::frb(sync)]
pub fn verify_disable_list(json: String, signature_hex: String) -> String {
    let Ok(signature) = parse_signature_hex(signature_hex.trim()) else {
        return "invalid-signature".to_owned();
    };
    match verify_disable_list_bytes(json.as_bytes(), &signature, &FIXTURE_PACK_VERIFYING_KEY) {
        Ok(_) => "accept".to_owned(),
        Err(error) => error.code(),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn recalled_sessions(documents: Vec<String>, disable_list_json: String) -> Vec<String> {
    let Ok(list) = parse_disable_list(disable_list_json.as_bytes()) else {
        return Vec::new();
    };
    list_recalled_sessions(&documents, &list)
}

#[allow(clippy::too_many_arguments)]
#[flutter_rust_bridge::frb(sync)]
pub fn evaluate_content_pack(
    manifest_json: String,
    signature_hex: String,
    file_paths: Vec<String>,
    file_contents: Vec<Vec<u8>>,
    floor_version: u32,
    disable_list_json: String,
    disable_list_sig_hex: String,
    now_ms: i64,
    last_verified_at_ms: i64,
    max_offline_age_ms: Option<i64>,
) -> String {
    if file_paths.len() != file_contents.len() {
        return "invalid-manifest".to_owned();
    }
    let Ok(signature) = parse_signature_hex(signature_hex.trim()) else {
        return "invalid-signature".to_owned();
    };
    let Ok(list_sig) = parse_signature_hex(disable_list_sig_hex.trim()) else {
        return "invalid-signature".to_owned();
    };
    let list = match verify_disable_list_bytes(
        disable_list_json.as_bytes(),
        &list_sig,
        &FIXTURE_PACK_VERIFYING_KEY,
    ) {
        Ok(list) => list,
        Err(error) => return error.code(),
    };
    let files: Vec<(String, Vec<u8>)> = file_paths.into_iter().zip(file_contents).collect();
    evaluate_pack(
        manifest_json.as_bytes(),
        &signature,
        &files,
        &FIXTURE_PACK_VERIFYING_KEY,
        floor_version,
        &list,
        now_ms,
        last_verified_at_ms,
        max_offline_age_ms,
    )
    .code()
    .to_owned()
}

#[cfg(test)]
mod tests {
    use super::{BridgeError, instrument_view, probe_contained_panic, program_rule_view};

    #[test]
    fn a_bad_instrument_document_is_invalid_instrument() {
        let text =
            r#"{"instrument_id":"clinical-shoulder","instrument_version":1,"ratings":["normal"]}"#;
        let error = instrument_view(text).expect_err("bad instrument");
        assert_eq!(error, BridgeError::InvalidInstrument);
        assert_eq!(error.code(), "invalid-instrument");
        assert!(!error.to_string().contains("clinical-shoulder"));
    }

    #[test]
    fn a_bad_program_rule_is_invalid_program() {
        let text = r#"{"rule_id":"clinical-dose","rule_version":1,"session_minutes":15,"max_exercises":4}"#;
        let error = program_rule_view(text).expect_err("bad rule");
        assert_eq!(error, BridgeError::InvalidProgram);
        assert_eq!(error.code(), "invalid-program");
        assert_eq!(error.to_string(), "invalid-program");
        assert!(!error.to_string().contains("clinical-dose"));
        assert!(!error.to_string().contains(text));
    }

    #[test]
    fn probe_panic_is_caught() {
        let caught = std::panic::catch_unwind(|| {
            let _unused = probe_contained_panic();
        });
        assert!(caught.is_err());
    }
}
