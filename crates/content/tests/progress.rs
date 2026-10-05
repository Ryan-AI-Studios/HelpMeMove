//! Synthetic stored-session counts. Doses stay on the fixture. This is not a milestone.

use serde_json::{Value, json};

use helpmemove_content::{
    Exercise, ProgressError, Session, apply_session_event, open_session, parse_exercise,
    read_session_event, render_session, summarize_progress,
};

const PROGRAM: &str = include_str!("../../../apps/mobile/test/program/green_shoulder_program.json");
const EMPTY: &str = r#"{"abandoned_count":0,"completed_count":0,"copied_pain":null,"record_version":1,"rule_id":"syn-progress-core","rule_version":1,"safety_stopped_count":0}"#;
const KEYS: [&str; 7] = [
    "abandoned_count",
    "completed_count",
    "copied_pain",
    "record_version",
    "rule_id",
    "rule_version",
    "safety_stopped_count",
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

fn apply(session: &Session, text: &str, library: &[Exercise]) -> Session {
    let event = read_session_event(text).expect("event");
    apply_session_event(session, &event, 1200, &[], library).expect("apply")
}

fn opened(session_id: &str, library: &[Exercise]) -> Session {
    open_session(PROGRAM, library, 1000, session_id).expect("open")
}

fn active(session_id: &str, library: &[Exercise]) -> Session {
    let preparing = opened(session_id, library);
    let demonstrating = apply(&preparing, r#"{"name":"ready"}"#, library);
    apply(&demonstrating, r#"{"name":"ready"}"#, library)
}

fn with_pain(session: &Session, pain: u8, library: &[Exercise]) -> Session {
    let event =
        format!(r#"{{"name":"report_pain","reported_pain":{pain},"symptom":"mild_discomfort"}}"#);
    apply(session, &event, library)
}

fn document(session: &Session) -> String {
    render_session(session).expect("render")
}

fn completed(session_id: &str, pain: Option<u8>, library: &[Exercise]) -> String {
    let mut session = active(session_id, library);
    if let Some(value) = pain {
        session = with_pain(&session, value, library);
        session = apply(&session, r#"{"name":"continue_after_pain"}"#, library);
        session = apply(&session, r#"{"name":"resume"}"#, library);
    }
    session = apply(&session, r#"{"name":"complete_rep"}"#, library);
    assert_eq!(session.outcome.as_deref(), Some("completed"));
    document(&session)
}

fn abandoned(session_id: &str, pain: Option<u8>, library: &[Exercise]) -> String {
    let mut session = active(session_id, library);
    if let Some(value) = pain {
        session = with_pain(&session, value, library);
        session = apply(&session, r#"{"name":"continue_after_pain"}"#, library);
    } else {
        session = apply(&session, r#"{"name":"pause"}"#, library);
    }
    session = apply(&session, r#"{"name":"end_session"}"#, library);
    assert_eq!(session.outcome.as_deref(), Some("abandoned"));
    document(&session)
}

fn safety_stopped(session_id: &str, pain: u8, library: &[Exercise]) -> String {
    let session = active(session_id, library);
    let checking = with_pain(&session, pain, library);
    let stopped = apply(&checking, r#"{"name":"end_session"}"#, library);
    assert_eq!(stopped.outcome.as_deref(), Some("safety_stopped"));
    document(&stopped)
}

fn entry(session_id: &str, document_json: &str, updated_at_ms: i64) -> Value {
    json!({
        "document_json": document_json,
        "session_id": session_id,
        "updated_at_ms": updated_at_ms,
    })
}

fn pack(rows: Vec<Value>) -> String {
    serde_json::to_string(&Value::Array(rows)).expect("entries")
}

fn ready(entries: &str) -> Value {
    let text = summarize_progress(entries, &fixtures()).expect("summary");
    serde_json::from_str(&text).expect("json")
}

fn assert_keys(document: &Value) {
    let object = document.as_object().expect("object");
    let keys: Vec<&str> = object.keys().map(String::as_str).collect();
    assert_eq!(keys, KEYS);
}

fn assert_absent(text: &str) {
    for token in [
        "syn-shoulder",
        "syn-knee",
        "syn-torso",
        "sets",
        "reps",
        "tempo",
        "degree",
        "level",
        "trend",
        "Improving",
        "date",
    ] {
        assert!(!text.contains(token), "{token} leaked into {text}");
    }
}

#[test]
fn empty_array_is_a_zero_summary() {
    let text = summarize_progress("[]", &fixtures()).expect("summary");
    assert_eq!(text, EMPTY);
    assert_keys(&serde_json::from_str::<Value>(&text).expect("json"));
    assert_absent(&text);
}

#[test]
fn empty_library_rejects_before_the_entries() {
    let error = summarize_progress("[]", &[]).expect_err("library");
    assert_eq!(error, ProgressError::LibraryRejected);
    let error = summarize_progress("not-json", &[]).expect_err("library first");
    assert_eq!(error, ProgressError::LibraryRejected);
}

#[test]
fn completed_abandoned_and_safety_stopped_are_counted() {
    let library = fixtures();
    let entries = pack(vec![
        entry(
            "completed-1",
            &completed("completed-1", Some(3), &library),
            10,
        ),
        entry("abandoned-1", &abandoned("abandoned-1", None, &library), 20),
        entry("stopped-1", &safety_stopped("stopped-1", 4, &library), 30),
    ]);
    let document = ready(&entries);
    assert_keys(&document);
    assert_eq!(document["completed_count"], 1);
    assert_eq!(document["abandoned_count"], 1);
    assert_eq!(document["safety_stopped_count"], 1);
    assert_eq!(document["copied_pain"], 4);
    assert_eq!(document["rule_id"], "syn-progress-core");
    assert_absent(&document.to_string());
}

#[test]
fn a_non_terminal_session_is_ignored() {
    let library = fixtures();
    let preparing = document(&opened("open-1", &library));
    let checking = document(&with_pain(&active("pain-1", &library), 10, &library));
    let entries = pack(vec![
        entry("open-1", &preparing, 9_000),
        entry("pain-1", &checking, 9_001),
        entry("completed-1", &completed("completed-1", None, &library), 1),
    ]);
    let document = ready(&entries);
    assert_eq!(document["completed_count"], 1);
    assert_eq!(document["abandoned_count"], 0);
    assert_eq!(document["safety_stopped_count"], 0);
    assert_eq!(document["copied_pain"], Value::Null);
}

#[test]
fn pain_ten_is_copied_and_still_counts() {
    let library = fixtures();
    let entries = pack(vec![entry(
        "completed-10",
        &completed("completed-10", Some(10), &library),
        50,
    )]);
    let document = ready(&entries);
    assert_eq!(document["completed_count"], 1);
    assert_eq!(document["copied_pain"], 10);
}

#[test]
fn the_newest_counted_session_supplies_pain() {
    let library = fixtures();
    let entries = pack(vec![
        entry("older", &completed("older", Some(1), &library), 10),
        entry(
            "newer-small-id",
            &completed("newer-small-id", Some(2), &library),
            40,
        ),
        entry("zzz", &abandoned("zzz", Some(9), &library), 20),
    ]);
    let document = ready(&entries);
    assert_eq!(document["copied_pain"], 2);
    assert_eq!(document["completed_count"], 2);
    assert_eq!(document["abandoned_count"], 1);
}

#[test]
fn an_equal_clock_uses_the_greater_session_id() {
    let library = fixtures();
    let entries = pack(vec![
        entry("a-session", &completed("a-session", Some(1), &library), 80),
        entry("b-session", &completed("b-session", Some(6), &library), 80),
    ]);
    let document = ready(&entries);
    assert_eq!(document["copied_pain"], 6);
    assert_eq!(document["completed_count"], 2);
}

#[test]
fn the_maximum_clock_is_accepted() {
    let library = fixtures();
    let entries = pack(vec![entry(
        "max-clock",
        &completed("max-clock", Some(0), &library),
        9_223_372_036_854_775_807,
    )]);
    let document = ready(&entries);
    assert_eq!(document["copied_pain"], 0);
}

#[test]
fn a_duplicate_session_id_is_invalid() {
    let library = fixtures();
    let body = completed("same-id", None, &library);
    let entries = pack(vec![entry("same-id", &body, 1), entry("same-id", &body, 2)]);
    let error = summarize_progress(&entries, &library).expect_err("duplicate");
    assert_eq!(error, ProgressError::Invalid);
}

#[test]
fn a_session_id_mismatch_is_invalid() {
    let library = fixtures();
    let entries = pack(vec![entry(
        "other-id",
        &completed("real-id", None, &library),
        1,
    )]);
    let error = summarize_progress(&entries, &library).expect_err("mismatch");
    assert_eq!(error, ProgressError::Invalid);
}

#[test]
fn a_document_that_fails_to_parse_rejects_the_summary() {
    let entries = pack(vec![entry("broken", "{}", 1)]);
    let error = summarize_progress(&entries, &fixtures()).expect_err("parse");
    assert_eq!(error, ProgressError::Invalid);
}

#[test]
fn extra_or_missing_keys_and_a_bad_clock_are_invalid() {
    let library = fixtures();
    let body = completed("clock-id", None, &library);
    let extra = pack(vec![json!({
        "document_json": body,
        "session_id": "clock-id",
        "updated_at_ms": 1,
        "note": "no",
    })]);
    assert_eq!(
        summarize_progress(&extra, &library).expect_err("extra"),
        ProgressError::Invalid
    );
    let missing = pack(vec![json!({
        "document_json": body,
        "session_id": "clock-id",
    })]);
    assert_eq!(
        summarize_progress(&missing, &library).expect_err("missing"),
        ProgressError::Invalid
    );
    let overflow = format!(
        r#"[{{"document_json":{body_json},"session_id":"clock-id","updated_at_ms":9223372036854775808}}]"#,
        body_json = serde_json::to_string(&body).expect("string"),
    );
    assert_eq!(
        summarize_progress(&overflow, &library).expect_err("overflow"),
        ProgressError::Invalid
    );
    let negative = pack(vec![entry("clock-id", &body, -1)]);
    assert_eq!(
        summarize_progress(&negative, &library).expect_err("negative"),
        ProgressError::Invalid
    );
    let empty_id = pack(vec![entry("", &body, 1)]);
    assert_eq!(
        summarize_progress(&empty_id, &library).expect_err("empty id"),
        ProgressError::Invalid
    );
    assert_eq!(
        summarize_progress("{}", &library).expect_err("object"),
        ProgressError::Invalid
    );
}
