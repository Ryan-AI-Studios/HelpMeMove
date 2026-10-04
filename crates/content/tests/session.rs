//! Synthetic manual session. Counts come from the fixtures. This is not a clinical workout.

use helpmemove_content::{
    ContentError, Exercise, Session, SessionState, apply_session_event, open_session,
    parse_exercise, parse_session, read_session_event, render_session,
};

const GOLDEN_PROGRAM: &str =
    include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const GOLDEN_SESSION: &str =
    include_str!("../../../apps/mobile/test/workout/opened_shoulder_session.json");
const SESSION_ID: &str = "11111111-1111-4111-8111-111111111111";

const EVENTS: [&str; 11] = [
    r#"{"name":"ready"}"#,
    r#"{"name":"complete_rep"}"#,
    r#"{"name":"tick"}"#,
    r#"{"name":"pause"}"#,
    r#"{"name":"resume"}"#,
    r#"{"name":"report_pain","reported_pain":4,"symptom":"mild_discomfort"}"#,
    r#"{"name":"continue_after_pain"}"#,
    r#"{"name":"select_substitute","exercise_id":"syn-shoulder-band"}"#,
    r#"{"name":"skip"}"#,
    r#"{"name":"shorten"}"#,
    r#"{"name":"end_session"}"#,
];

fn fixtures() -> Vec<Exercise> {
    [
        include_str!("../../../content/exercises/syn-knee-sit-to-stand.json"),
        include_str!("../../../content/exercises/syn-shoulder-band.json"),
        include_str!("../../../content/exercises/syn-shoulder-isometric.json"),
        include_str!("../../../content/exercises/syn-torso-pelvic-tilt.json"),
    ]
    .into_iter()
    .map(|text| parse_exercise(text.as_bytes()).expect("fixture"))
    .collect()
}

fn open_golden() -> Session {
    open_session(GOLDEN_PROGRAM, &fixtures(), 1000, SESSION_ID).expect("open")
}

fn event(text: &str) -> helpmemove_content::SessionEvent {
    read_session_event(text).expect("event")
}

fn apply(session: &Session, text: &str, now: u64) -> Result<Session, ContentError> {
    apply_session_event(session, &event(text), now, &[], &fixtures())
}

fn assert_unchanged(session: &Session, rendered: &str) {
    assert_eq!(render_session(session).expect("render"), rendered);
}

fn assert_reachable(session: &Session) {
    assert!(!matches!(
        session.state,
        SessionState::Positioning
            | SessionState::Ready
            | SessionState::Correcting
            | SessionState::Substituting
    ));
}

fn program_for(exercise_id: &str, sets: u8, reps: u8) -> String {
    format!(
        r#"{{"exercises":[{{"exercise_id":"{exercise_id}","exercise_version":1,"reps":{reps},"sets":{sets},"tempo":{{"concentric":2,"eccentric":2,"pause":1}}}}],"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15}}"#
    )
}

#[test]
fn opened_shoulder_session_matches_the_golden_document() {
    let session = open_golden();
    let rendered = render_session(&session).expect("render");
    assert_eq!(rendered, GOLDEN_SESSION);
    let parsed = parse_session(&rendered, &fixtures()).expect("parse");
    assert_eq!(parsed, session);
    assert_eq!(parsed.state, SessionState::Preparing);
    assert_eq!(parsed.exercises[0].sets, 1);
    assert_eq!(parsed.exercises[0].reps, 1);
    assert!(parsed.exercises[0].substitutions.is_empty());
}

#[test]
fn one_rep_completes_and_skip_abandons_the_only_exercise() {
    let session = open_golden();
    let demonstrating = apply(&session, r#"{"name":"ready"}"#, 1000).expect("ready");
    assert_eq!(demonstrating.state, SessionState::Demonstrating);
    let active = apply(&demonstrating, r#"{"name":"ready"}"#, 1100).expect("start");
    assert_eq!(active.state, SessionState::Active);
    assert_eq!(active.elapsed_ms, 100);
    let done = apply(&active, r#"{"name":"complete_rep"}"#, 1100).expect("rep");
    assert_eq!(done.state, SessionState::Completed);
    assert_eq!(done.outcome.as_deref(), Some("completed"));
    assert_eq!(done.exercises[0].reps_done, 1);
    assert!(done.rest_until_ms.is_none());

    let skipped = apply(&demonstrating, r#"{"name":"skip"}"#, 1000).expect("skip");
    assert_eq!(skipped.state, SessionState::Abandoned);
    assert_eq!(skipped.outcome.as_deref(), Some("abandoned"));
    assert!(skipped.exercises[0].skipped);
    assert_eq!(skipped.exercises[0].reps_done, 0);
}

#[test]
fn every_event_on_a_new_session_stays_out_of_unreachable_states() {
    let session = open_golden();
    for text in EVENTS {
        let rendered = render_session(&session).expect("render");
        match apply(&session, text, 1000) {
            Ok(next) => assert_reachable(&next),
            Err(error) => {
                assert_eq!(error, ContentError::InvalidSession);
                assert_unchanged(&session, &rendered);
            }
        }
    }
}

#[test]
fn two_set_rest_waits_for_the_pause_and_an_early_tick_adds_no_rep() {
    let mut library = fixtures();
    let exercise = library
        .iter_mut()
        .find(|item| item.id.as_str() == "syn-shoulder-isometric")
        .expect("fixture");
    exercise.default_sets = 2;
    let program = program_for("syn-shoulder-isometric", 2, 1);
    let opened = open_session(&program, &library, 5_000, SESSION_ID).expect("open");
    let active = apply_session_event(
        &apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 5_000, &[], &library)
            .expect("demo"),
        &event(r#"{"name":"ready"}"#),
        5_000,
        &[],
        &library,
    )
    .expect("active");
    let resting = apply_session_event(
        &active,
        &event(r#"{"name":"complete_rep"}"#),
        5_000,
        &[],
        &library,
    )
    .expect("rest");
    assert_eq!(resting.state, SessionState::Resting);
    assert_eq!(resting.rest_until_ms, Some(6_000));
    assert_eq!(resting.exercises[0].reps_done, 1);
    assert_eq!(resting.exercises[0].set_index, 0);
    let before = render_session(&resting).expect("render");
    let early = apply_session_event(&resting, &event(r#"{"name":"tick"}"#), 5_999, &[], &library);
    assert_eq!(early.unwrap_err(), ContentError::InvalidSession);
    assert_unchanged(&resting, &before);
    let next = apply_session_event(&resting, &event(r#"{"name":"tick"}"#), 6_000, &[], &library)
        .expect("tick");
    assert_eq!(next.state, SessionState::Active);
    assert_eq!(next.exercises[0].set_index, 1);
    assert_eq!(next.exercises[0].reps_done, 0);
    assert!(next.rest_until_ms.is_none());
    let finished = apply_session_event(
        &next,
        &event(r#"{"name":"complete_rep"}"#),
        6_000,
        &[],
        &library,
    )
    .expect("finish");
    assert_eq!(finished.outcome.as_deref(), Some("completed"));
}

#[test]
fn clock_and_closed_sessions_leave_the_document_unchanged() {
    let session = open_golden();
    let before = render_session(&session).expect("render");
    let backwards = apply(&session, r#"{"name":"ready"}"#, 999);
    assert_eq!(backwards.unwrap_err(), ContentError::ClockWentBackwards);
    assert_unchanged(&session, &before);
    let same = apply(&session, r#"{"name":"ready"}"#, 1000).expect("equal");
    assert_eq!(same.elapsed_ms, 0);

    let done = apply(
        &apply(&same, r#"{"name":"ready"}"#, 1000).expect("active"),
        r#"{"name":"complete_rep"}"#,
        1000,
    )
    .expect("done");
    let closed = render_session(&done).expect("render");
    for text in EVENTS {
        let result = apply(&done, text, 1000);
        assert_eq!(result.unwrap_err(), ContentError::SessionClosed);
        assert_unchanged(&done, &closed);
    }
}

#[test]
fn pain_is_stored_and_does_not_choose_a_stop() {
    let session = open_golden();
    let active = apply(
        &apply(&session, r#"{"name":"ready"}"#, 1000).expect("demo"),
        r#"{"name":"ready"}"#,
        1000,
    )
    .expect("active");
    let pain = apply(
        &active,
        r#"{"name":"report_pain","reported_pain":10,"symptom":"numbness_tingling"}"#,
        1300,
    )
    .expect("pain");
    assert_eq!(pain.state, SessionState::PainCheck);
    assert_eq!(pain.reported_pain, Some(10));
    assert_eq!(
        pain.symptom.map(helpmemove_content::Symptom::as_str),
        Some("numbness_tingling")
    );
    assert_eq!(pain.exercises[0].reps_done, 0);
    assert_eq!(pain.elapsed_ms, 300);
    let paused = apply(&pain, r#"{"name":"continue_after_pain"}"#, 1800).expect("continue");
    assert_eq!(paused.state, SessionState::Paused);
    assert_eq!(paused.elapsed_ms, 300);
    assert_eq!(paused.exercises[0].reps_done, 0);
    let stopped = apply(&pain, r#"{"name":"end_session"}"#, 1800).expect("end");
    assert_eq!(stopped.state, SessionState::SafetyStopped);
    assert_eq!(stopped.outcome.as_deref(), Some("safety_stopped"));
}

#[test]
fn pause_from_rest_keeps_the_remaining_rest() {
    let mut library = fixtures();
    library
        .iter_mut()
        .find(|item| item.id.as_str() == "syn-shoulder-isometric")
        .expect("fixture")
        .default_sets = 2;
    let opened = open_session(
        &program_for("syn-shoulder-isometric", 2, 1),
        &library,
        1_000,
        SESSION_ID,
    )
    .expect("open");
    let active = apply_session_event(
        &apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 1_000, &[], &library)
            .expect("demo"),
        &event(r#"{"name":"ready"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("active");
    let resting = apply_session_event(
        &active,
        &event(r#"{"name":"complete_rep"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("rest");
    let paused = apply_session_event(
        &resting,
        &event(r#"{"name":"pause"}"#),
        1_200,
        &[],
        &library,
    )
    .expect("pause");
    assert_eq!(paused.state, SessionState::Paused);
    assert_eq!(paused.rest_until_ms, Some(2_000));
    assert_eq!(paused.elapsed_ms, 200);
    let resumed = apply_session_event(
        &paused,
        &event(r#"{"name":"resume"}"#),
        4_000,
        &[],
        &library,
    )
    .expect("resume");
    assert_eq!(resumed.state, SessionState::Resting);
    assert_eq!(resumed.elapsed_ms, 200);
    assert_eq!(resumed.rest_until_ms, Some(4_800));
    assert!(
        apply_session_event(&resumed, &event(r#"{"name":"tick"}"#), 4_799, &[], &library,).is_err()
    );
    let advanced =
        apply_session_event(&resumed, &event(r#"{"name":"tick"}"#), 4_800, &[], &library)
            .expect("tick");
    assert_eq!(advanced.state, SessionState::Active);
    assert_eq!(advanced.rest_until_ms, None);
    assert_eq!(advanced.exercises[0].set_index, 1);
    assert_eq!(advanced.exercises[0].reps_done, 0);
}

#[test]
fn pain_check_does_not_consume_remaining_rest() {
    let mut library = fixtures();
    library
        .iter_mut()
        .find(|item| item.id.as_str() == "syn-shoulder-isometric")
        .expect("fixture")
        .default_sets = 2;
    let opened = open_session(
        &program_for("syn-shoulder-isometric", 2, 1),
        &library,
        1_000,
        SESSION_ID,
    )
    .expect("open");
    let active = apply_session_event(
        &apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 1_000, &[], &library)
            .expect("demo"),
        &event(r#"{"name":"ready"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("active");
    let resting = apply_session_event(
        &active,
        &event(r#"{"name":"complete_rep"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("rest");
    let pain = apply_session_event(
        &resting,
        &event(r#"{"name":"report_pain","reported_pain":0,"symptom":"mild_discomfort"}"#),
        1_200,
        &[],
        &library,
    )
    .expect("pain");
    assert_eq!(pain.rest_until_ms, Some(2_000));
    let paused = apply_session_event(
        &pain,
        &event(r#"{"name":"continue_after_pain"}"#),
        1_500,
        &[],
        &library,
    )
    .expect("continue");
    assert_eq!(paused.state, SessionState::Paused);
    assert_eq!(paused.rest_until_ms, Some(2_300));
    let resumed = apply_session_event(
        &paused,
        &event(r#"{"name":"resume"}"#),
        4_000,
        &[],
        &library,
    )
    .expect("resume");
    assert_eq!(resumed.state, SessionState::Resting);
    assert_eq!(resumed.rest_until_ms, Some(4_800));
    assert!(
        apply_session_event(&resumed, &event(r#"{"name":"tick"}"#), 4_799, &[], &library,).is_err()
    );
}

#[test]
fn substitute_accepts_only_an_eligible_substitution_id() {
    let mut library = fixtures();
    let knee = library
        .iter()
        .find(|item| item.id.as_str() == "syn-knee-sit-to-stand")
        .expect("knee")
        .id
        .clone();
    let band = library
        .iter_mut()
        .find(|item| item.id.as_str() == "syn-shoulder-band")
        .expect("band");
    band.substitutions.push(knee);
    let opened = open_session(
        &program_for("syn-shoulder-band", 1, 1),
        &library,
        1_000,
        SESSION_ID,
    )
    .expect("open");
    let pain = apply_session_event(
        &apply_session_event(
            &apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 1_000, &[], &library)
                .expect("demo"),
            &event(r#"{"name":"ready"}"#),
            1_000,
            &[],
            &library,
        )
        .expect("active"),
        &event(r#"{"name":"report_pain","reported_pain":2,"symptom":"sharp_pain"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("pain");
    let before = render_session(&pain).expect("render");
    let regression = apply_session_event(
        &pain,
        &event(r#"{"name":"select_substitute","exercise_id":"syn-shoulder-isometric"}"#),
        1_000,
        &["syn-shoulder-isometric".to_owned()],
        &library,
    );
    assert_eq!(regression.unwrap_err(), ContentError::InvalidSession);
    assert_unchanged(&pain, &before);
    let ineligible = apply_session_event(
        &pain,
        &event(r#"{"name":"select_substitute","exercise_id":"syn-knee-sit-to-stand"}"#),
        1_000,
        &[],
        &library,
    );
    assert_eq!(ineligible.unwrap_err(), ContentError::InvalidSession);
    let replaced = apply_session_event(
        &pain,
        &event(r#"{"name":"select_substitute","exercise_id":"syn-knee-sit-to-stand"}"#),
        1_000,
        &["syn-knee-sit-to-stand".to_owned()],
        &library,
    )
    .expect("substitute");
    assert_eq!(replaced.state, SessionState::Demonstrating);
    assert_eq!(replaced.exercises[0].exercise_id, "syn-knee-sit-to-stand");
    assert_eq!(replaced.exercises[0].reps_done, 0);
    assert_eq!(replaced.exercises[0].set_index, 0);
    assert!(replaced.exercises[0].substitutions.is_empty());
}

#[test]
fn committed_fixtures_reject_substitute_even_when_eligible() {
    let session = open_golden();
    let pain = apply(
        &apply(
            &apply(&session, r#"{"name":"ready"}"#, 1000).expect("demo"),
            r#"{"name":"ready"}"#,
            1000,
        )
        .expect("active"),
        r#"{"name":"report_pain","reported_pain":1,"symptom":"weakness"}"#,
        1000,
    )
    .expect("pain");
    let before = render_session(&pain).expect("render");
    let result = apply_session_event(
        &pain,
        &event(r#"{"name":"select_substitute","exercise_id":"syn-shoulder-band"}"#),
        1000,
        &["syn-shoulder-band".to_owned()],
        &fixtures(),
    );
    assert_eq!(result.unwrap_err(), ContentError::InvalidSession);
    assert_unchanged(&pain, &before);
}

#[test]
fn shorten_and_end_from_pause_drop_the_tail_and_abandon() {
    let library = fixtures();
    let program = r#"{"exercises":[{"exercise_id":"syn-shoulder-isometric","exercise_version":1,"reps":1,"sets":1,"tempo":{"concentric":2,"eccentric":2,"pause":1}},{"exercise_id":"syn-knee-sit-to-stand","exercise_version":1,"reps":1,"sets":1,"tempo":{"concentric":2,"eccentric":2,"pause":1}}],"record_version":1,"rule_id":"syn-program-core","rule_version":1,"safety_rule_id":"syn-safety-core","safety_rule_version":1,"session_minutes":15}"#;
    let opened = open_session(program, &library, 1_000, SESSION_ID).expect("open");
    assert_eq!(opened.exercises.len(), 2);
    let paused = apply_session_event(
        &apply_session_event(
            &apply_session_event(&opened, &event(r#"{"name":"ready"}"#), 1_000, &[], &library)
                .expect("demo"),
            &event(r#"{"name":"ready"}"#),
            1_000,
            &[],
            &library,
        )
        .expect("active"),
        &event(r#"{"name":"pause"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("pause");
    let shorter = apply_session_event(
        &paused,
        &event(r#"{"name":"shorten"}"#),
        1_000,
        &[],
        &library,
    )
    .expect("shorten");
    assert_eq!(shorter.state, SessionState::Paused);
    assert_eq!(shorter.exercises.len(), 1);
    assert!(shorter.outcome.is_none());
    let ended = apply_session_event(
        &shorter,
        &event(r#"{"name":"end_session"}"#),
        1_500,
        &[],
        &library,
    )
    .expect("end");
    assert_eq!(ended.state, SessionState::Abandoned);
    assert_eq!(ended.outcome.as_deref(), Some("abandoned"));
    assert_eq!(ended.elapsed_ms, 0);
}

#[test]
fn shorten_on_the_only_exercise_stays_paused() {
    let paused = apply(
        &apply(
            &apply(&open_golden(), r#"{"name":"ready"}"#, 1_000).expect("demo"),
            r#"{"name":"ready"}"#,
            1_000,
        )
        .expect("active"),
        r#"{"name":"pause"}"#,
        1_000,
    )
    .expect("pause");
    let shorter = apply(&paused, r#"{"name":"shorten"}"#, 1_000).expect("shorten");
    assert_eq!(shorter.state, SessionState::Paused);
    assert!(shorter.outcome.is_none());
    assert_eq!(shorter.exercises.len(), 1);
    assert_eq!(
        shorter.exercises[0].exercise_id,
        paused.exercises[0].exercise_id
    );
}

#[test]
fn shorten_with_no_unfinished_exercise_is_invalid() {
    let library = fixtures();
    let mut paused = apply(
        &apply(
            &apply(&open_golden(), r#"{"name":"ready"}"#, 1_000).expect("demo"),
            r#"{"name":"ready"}"#,
            1_000,
        )
        .expect("active"),
        r#"{"name":"pause"}"#,
        1_000,
    )
    .expect("pause");
    paused.exercises[0].skipped = true;
    let document = render_session(&paused).expect("render");
    let parsed = parse_session(&document, &library).expect("parse");
    let result = apply_session_event(
        &parsed,
        &event(r#"{"name":"shorten"}"#),
        parsed.monotonic_ms,
        &[],
        &library,
    );
    assert_eq!(result.unwrap_err(), ContentError::InvalidSession);
}

#[test]
fn parse_rejects_a_clock_above_u64() {
    let library = fixtures();
    let rendered = render_session(&open_golden()).expect("render");
    let too_big = rendered.replace("\"elapsed_ms\":0", "\"elapsed_ms\":18446744073709551616");
    assert_eq!(
        parse_session(&too_big, &library).unwrap_err(),
        ContentError::InvalidSession
    );
    let maxed = rendered.replace("\"elapsed_ms\":0", "\"elapsed_ms\":18446744073709551615");
    let parsed = parse_session(&maxed, &library).expect("max");
    assert_eq!(parsed.elapsed_ms, u64::MAX);
}

#[test]
fn unknown_and_mismatched_programs_do_not_open() {
    let library = fixtures();
    let unknown = program_for("syn-not-a-fixture", 1, 1);
    assert_eq!(
        open_session(&unknown, &library, 1_000, SESSION_ID).unwrap_err(),
        ContentError::InvalidSession
    );
    let mismatched = program_for("syn-shoulder-isometric", 3, 1);
    assert_eq!(
        open_session(&mismatched, &library, 1_000, SESSION_ID).unwrap_err(),
        ContentError::InvalidSession
    );
    assert_eq!(
        open_session(GOLDEN_PROGRAM, &library, 1_000, "").unwrap_err(),
        ContentError::InvalidSession
    );
}
