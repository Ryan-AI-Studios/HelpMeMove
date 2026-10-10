use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, Once};
use std::time::{Duration, Instant};

use axum::Router;
use axum::body::Body;
use axum::extract::State;
use axum::http::{HeaderMap, Request, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::post;
use helpmemove_api::{AuthorizeError, app, authorize, synthetic_actor_map};
use http_body_util::BodyExt;
use serde::Deserialize;
use serde_json::Value;
use tower::ServiceExt;

static ENV_GATE: AtomicBool = AtomicBool::new(false);
static LOG_LINES: Mutex<Vec<String>> = Mutex::new(Vec::new());
static LOGGER: TestLogger = TestLogger;

struct TestLogger;

impl log::Log for TestLogger {
    fn enabled(&self, _metadata: &log::Metadata<'_>) -> bool {
        true
    }

    fn log(&self, record: &log::Record<'_>) {
        if let Ok(mut lines) = LOG_LINES.lock() {
            lines.push(record.args().to_string());
        }
    }

    fn flush(&self) {}
}

fn install_test_logger() {
    static ONCE: Once = Once::new();
    ONCE.call_once(|| {
        log::set_logger(&LOGGER).expect("install the test logger");
        log::set_max_level(log::LevelFilter::Trace);
    });
}

fn clear_logs() {
    LOG_LINES.lock().expect("log buffer").clear();
}

fn logs_text() -> String {
    LOG_LINES.lock().expect("log buffer").join("\n")
}

struct EnvGuard {
    key: Option<String>,
    base: Option<String>,
}

impl EnvGuard {
    fn replace(key: Option<&str>, base: Option<&str>) -> Self {
        while ENV_GATE
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            std::thread::sleep(Duration::from_millis(5));
        }
        let guard = Self {
            key: std::env::var("OLLAMA_CLOUD_API_KEY").ok(),
            base: std::env::var("OLLAMA_API_BASE").ok(),
        };
        set_env("OLLAMA_CLOUD_API_KEY", key);
        set_env("OLLAMA_API_BASE", base);
        guard
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        set_env("OLLAMA_CLOUD_API_KEY", self.key.as_deref());
        set_env("OLLAMA_API_BASE", self.base.as_deref());
        ENV_GATE.store(false, Ordering::Release);
    }
}

fn set_env(name: &str, value: Option<&str>) {
    // SAFETY: `ENV_GATE` is held, and every test that reads or writes
    // `OLLAMA_CLOUD_API_KEY` or `OLLAMA_API_BASE` takes that gate first.
    // The previous values are restored before the gate is released.
    unsafe {
        match value {
            Some(value) => std::env::set_var(name, value),
            None => std::env::remove_var(name),
        }
    }
}

fn runtime_sentinel() -> String {
    [
        'u', 'n', 'i', 't', '-', 't', 'e', 's', 't', '-', 'o', 'l', 'l', 'a', 'm', 'a', '-', 'k',
        'e', 'y', '-', 's', 'e', 'n', 't', 'i', 'n', 'e', 'l',
    ]
    .into_iter()
    .collect()
}

fn assert_exe_lacks_sentinel(sentinel: &str) {
    let path = std::env::current_exe().expect("current test executable");
    assert_bytes_lack_sentinel(&path, sentinel);
    let api_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/debug");
    for name in ["helpmemove_api.exe", "helpmemove_api"] {
        let binary = api_dir.join(name);
        if binary.is_file() {
            assert_bytes_lack_sentinel(&binary, sentinel);
        }
    }
}

fn assert_flutter_assets_lack_sentinel(sentinel: &str) {
    let mobile = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../apps/mobile");
    let mut saw_pubspec = false;
    walk_flutter(&mobile, sentinel.as_bytes(), &mut saw_pubspec);
    assert!(saw_pubspec, "flutter pubspec was not read");
}

fn walk_flutter(dir: &std::path::Path, needle: &[u8], saw_pubspec: &mut bool) {
    let entries = std::fs::read_dir(dir).expect("flutter directory");
    for entry in entries {
        let entry = entry.expect("flutter entry");
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if matches!(
            name.as_ref(),
            "build" | ".dart_tool" | ".gradle" | "ephemeral" | "Pods" | ".symlinks"
        ) {
            continue;
        }
        let path = entry.path();
        let kind = entry.file_type().expect("flutter file type");
        if kind.is_dir() {
            walk_flutter(&path, needle, saw_pubspec);
            continue;
        }
        if name == "pubspec.yaml" {
            *saw_pubspec = true;
        }
        assert_bytes_lack_sentinel(&path, std::str::from_utf8(needle).expect("sentinel utf8"));
    }
}

fn assert_bytes_lack_sentinel(path: &std::path::Path, sentinel: &str) {
    let bytes = std::fs::read(path).expect("read bytes");
    let needle = sentinel.as_bytes();
    if needle.is_empty() {
        return;
    }
    assert!(
        !bytes.windows(needle.len()).any(|window| window == needle),
        "file contains the ollama key sentinel: {}",
        path.display()
    );
}

#[derive(Clone)]
struct MockState {
    hits: Arc<AtomicUsize>,
    captured: Arc<Mutex<Option<Captured>>>,
    mode: MockMode,
}

#[derive(Clone)]
enum MockMode {
    Reply(String),
    Failure { status: u16, body: String },
    Hang { body: String },
}

struct Captured {
    authorization: Option<String>,
    header_names: Vec<String>,
    body: Value,
}

struct Mock {
    base: String,
    hits: Arc<AtomicUsize>,
    captured: Arc<Mutex<Option<Captured>>>,
    server: tokio::task::JoinHandle<()>,
}

impl Drop for Mock {
    fn drop(&mut self) {
        self.server.abort();
    }
}

impl Mock {
    async fn spawn(mode: MockMode) -> Self {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind the mock");
        let addr = listener.local_addr().expect("mock address");
        let hits = Arc::new(AtomicUsize::new(0));
        let captured = Arc::new(Mutex::new(None));
        let state = MockState {
            hits: Arc::clone(&hits),
            captured: Arc::clone(&captured),
            mode,
        };
        let app = Router::new()
            .route("/api/chat", post(mock_chat))
            .with_state(state);
        let server = tokio::spawn(async move {
            axum::serve(listener, app).await.expect("serve the mock");
        });
        Self {
            base: format!("http://{addr}"),
            hits,
            captured,
            server,
        }
    }

    fn hits(&self) -> usize {
        self.hits.load(Ordering::SeqCst)
    }
}

async fn mock_chat(
    State(state): State<MockState>,
    headers: HeaderMap,
    body: axum::body::Bytes,
) -> Response {
    state.hits.fetch_add(1, Ordering::SeqCst);
    let authorization = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .map(ToOwned::to_owned);
    let header_names = headers
        .keys()
        .map(|name| name.as_str().to_owned())
        .collect();
    let parsed = serde_json::from_slice(&body).unwrap_or(Value::Null);
    if let Ok(mut slot) = state.captured.lock() {
        *slot = Some(Captured {
            authorization,
            header_names,
            body: parsed,
        });
    }
    match state.mode {
        MockMode::Reply(content) => reply_json(&content).into_response(),
        MockMode::Failure { status, body } => {
            let code = StatusCode::from_u16(status).expect("mock status");
            (code, body).into_response()
        }
        MockMode::Hang { body } => {
            tokio::time::sleep(Duration::from_secs(20)).await;
            (StatusCode::OK, body).into_response()
        }
    }
}

fn reply_json(content: &str) -> impl IntoResponse {
    axum::Json(serde_json::json!({
        "model": "deepseek-v4.1-flash",
        "message": { "role": "assistant", "content": content },
        "done": true
    }))
}

fn long_reply() -> String {
    let mut text = "a".repeat(499);
    text.push('é');
    text.push_str("ZZZZ");
    text
}

fn expected_truncation() -> String {
    let mut text = "a".repeat(499);
    text.push('é');
    text
}

#[test]
fn authorize_still_allows_only_probe() {
    let map = synthetic_actor_map();
    let result = authorize(
        &map,
        "explain",
        Some("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        "11111111-1111-4111-8111-111111111111",
        "33333333-3333-4333-8333-333333333333",
    );
    assert_eq!(result, Err(AuthorizeError::NotAllowed));
}

#[tokio::test]
async fn explain_rejects_extra_json_key_with_empty_400() {
    let mock = Mock::spawn(MockMode::Reply("should-not-be-requested".to_owned())).await;
    let _env = EnvGuard::replace(Some("rejection-check-not-a-key"), Some(&mock.base));
    let response =
        post_explain(r#"{"selection_kind":"region","selection_id":"leg","extra":true}"#).await;
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    assert!(body_bytes(response).await.is_empty());
    assert_eq!(mock.hits(), 0);
}

#[tokio::test]
async fn explain_rejects_id_outside_the_lists_with_empty_400() {
    let mock = Mock::spawn(MockMode::Reply("should-not-be-requested".to_owned())).await;
    let _env = EnvGuard::replace(Some("rejection-check-not-a-key"), Some(&mock.base));
    for json in [
        r#"{"selection_kind":"region","selection_id":"hand"}"#,
        r#"{"selection_kind":"focus","selection_id":"head_neck"}"#,
        r#"{"selection_kind":"area","selection_id":"leg"}"#,
    ] {
        let response = post_explain(json).await;
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);
        assert!(body_bytes(response).await.is_empty());
    }
    assert_eq!(mock.hits(), 0);
}

#[tokio::test]
async fn explain_returns_truncated_plain_text_from_local_mock() {
    let sentinel = runtime_sentinel();
    assert_exe_lacks_sentinel(&sentinel);
    assert_flutter_assets_lack_sentinel(&sentinel);

    install_test_logger();
    let mock = Mock::spawn(MockMode::Reply(long_reply())).await;
    let _env = EnvGuard::replace(Some(&sentinel), Some(&mock.base));
    clear_logs();

    let response = post_explain(r#"{"selection_kind":"region","selection_id":"head_neck"}"#).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok()),
        Some("text/plain; charset=utf-8")
    );
    let body = String::from_utf8(body_bytes(response).await).expect("utf-8 reply");
    let expected = expected_truncation();
    assert_eq!(expected.chars().count(), 500);
    assert_eq!(body, expected);
    assert!(!body.contains('Z'));

    let captured = mock
        .captured
        .lock()
        .expect("capture")
        .take()
        .expect("the mock was called");
    assert_eq!(mock.hits(), 1);
    let expected_authorization = format!("Bearer {sentinel}");
    assert_eq!(
        captured.authorization.as_deref(),
        Some(expected_authorization.as_str())
    );
    for name in ["x-api-key", "api-key", "x-ollama-api-key", "ollama-api-key"] {
        assert!(
            !captured.header_names.iter().any(|header| header == name),
            "unexpected credential header {name}"
        );
    }
    assert_outbound_chat(&captured.body, "region", "head_neck");
    let logs = logs_text();
    assert!(!logs.contains(&sentinel));
    assert!(!logs.contains("ZZZZ"));
}

#[tokio::test]
async fn explain_missing_key_returns_local_sentence() {
    install_test_logger();
    let body_sentinel = "missing-key-body-not-for-logs";
    let mock = Mock::spawn(MockMode::Reply(body_sentinel.to_owned())).await;
    let _env = EnvGuard::replace(None, Some(&mock.base));
    clear_logs();

    let response = post_explain(r#"{"selection_kind":"focus","selection_id":"strength"}"#).await;
    assert_local_sentence(response).await;
    assert_eq!(mock.hits(), 0);
    assert!(!logs_text().contains(body_sentinel));
}

#[tokio::test]
async fn explain_non_200_returns_local_sentence_without_logging_body() {
    install_test_logger();
    let body_sentinel = "provider-status-body-not-for-logs";
    let key = "status-path-not-a-key";
    let mock = Mock::spawn(MockMode::Failure {
        status: 502,
        body: body_sentinel.to_owned(),
    })
    .await;
    let _env = EnvGuard::replace(Some(key), Some(&mock.base));
    clear_logs();

    let response = post_explain(r#"{"selection_kind":"focus","selection_id":"mobility"}"#).await;
    assert_local_sentence(response).await;
    assert_eq!(mock.hits(), 1);
    let logs = logs_text();
    assert!(!logs.contains(body_sentinel));
    assert!(!logs.contains(key));
}

#[tokio::test]
async fn explain_timeout_returns_local_sentence_without_logging_body() {
    install_test_logger();
    let body_sentinel = "provider-timeout-body-not-for-logs";
    let key = "timeout-path-not-a-key";
    let mock = Mock::spawn(MockMode::Hang {
        body: body_sentinel.to_owned(),
    })
    .await;
    let _env = EnvGuard::replace(Some(key), Some(&mock.base));
    clear_logs();

    let started = Instant::now();
    let response = post_explain(r#"{"selection_kind":"region","selection_id":"foot"}"#).await;
    assert!(started.elapsed() < Duration::from_secs(19));
    assert_local_sentence(response).await;
    assert_eq!(mock.hits(), 1);
    let logs = logs_text();
    assert!(!logs.contains(body_sentinel));
    assert!(!logs.contains(key));
}

#[derive(Deserialize)]
struct OutboundChat {
    model: String,
    messages: Vec<OutboundMessage>,
    stream: bool,
}

#[derive(Deserialize)]
struct OutboundMessage {
    role: String,
    content: String,
}

fn assert_outbound_chat(body: &Value, kind: &str, id: &str) {
    let object = body.as_object().expect("chat object");
    let mut keys: Vec<_> = object.keys().map(String::as_str).collect::<Vec<_>>();
    keys.sort_unstable();
    assert_eq!(keys, ["messages", "model", "stream"]);
    let chat: OutboundChat = serde_json::from_value(body.clone()).expect("chat shape");
    assert_eq!(chat.model, "deepseek-v4.1-flash");
    assert!(!chat.model.contains(":cloud"));
    assert!(!chat.stream);
    assert_eq!(chat.messages.len(), 1);
    assert_eq!(chat.messages[0].role, "user");
    assert_eq!(
        chat.messages[0].content,
        format!("selection_kind={kind}\nselection_id={id}")
    );
    let raw = serde_json::to_string(body).expect("reserialize");
    assert!(!raw.contains(":cloud"));
}

async fn assert_local_sentence(response: Response) {
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok()),
        Some("text/plain; charset=utf-8")
    );
    let body = body_bytes(response).await;
    assert_eq!(body, b"This note stays on this device.");
}

async fn post_explain(json: &str) -> Response {
    app()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/coach/explain")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(json.to_owned()))
                .expect("request"),
        )
        .await
        .expect("response")
}

async fn body_bytes(response: Response) -> Vec<u8> {
    response
        .into_body()
        .collect()
        .await
        .expect("body")
        .to_bytes()
        .to_vec()
}
