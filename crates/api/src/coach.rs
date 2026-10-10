//! Local explanation seam. The Ollama key is read from the process
//! environment and is not written to the response or to logs.

use std::time::Duration;

use axum::body::Bytes;
use axum::http::{HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

const LOCAL_SENTENCE: &str = "This note stays on this device.";
const DEFAULT_BASE: &str = "https://ollama.com";
const MODEL: &str = "deepseek-v4.1-flash";
const TIMEOUT: Duration = Duration::from_secs(15);
const REPLY_LIMIT: usize = 500;

const REGION_IDS: &[&str] = &[
    "head_neck",
    "shoulder",
    "arm",
    "torso",
    "pelvis",
    "leg",
    "foot",
];
const FOCUS_IDS: &[&str] = &[
    "strength",
    "mobility",
    "stability",
    "conditioning",
    "control",
];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ExplainRequest {
    selection_kind: SelectionKind,
    selection_id: String,
}

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
enum SelectionKind {
    Region,
    Focus,
}

impl SelectionKind {
    fn token(self) -> &'static str {
        match self {
            Self::Region => "region",
            Self::Focus => "focus",
        }
    }

    fn allows(self, id: &str) -> bool {
        match self {
            Self::Region => REGION_IDS.contains(&id),
            Self::Focus => FOCUS_IDS.contains(&id),
        }
    }
}

#[derive(Serialize)]
struct ChatRequest<'a> {
    model: &'a str,
    messages: [ChatMessage<'a>; 1],
    stream: bool,
}

#[derive(Serialize)]
struct ChatMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Deserialize)]
struct ChatResponse {
    message: ChatResponseMessage,
}

#[derive(Deserialize)]
struct ChatResponseMessage {
    content: String,
}

pub(super) async fn explain(body: Bytes) -> Response {
    let Some((kind, id)) = accepted_selection(&body) else {
        return StatusCode::BAD_REQUEST.into_response();
    };
    match cloud_key() {
        Some(key) => request_explanation(&key, kind, &id).await,
        None => local_sentence(),
    }
}

fn accepted_selection(body: &[u8]) -> Option<(SelectionKind, String)> {
    let request: ExplainRequest = serde_json::from_slice(body).ok()?;
    if !request.selection_kind.allows(&request.selection_id) {
        return None;
    }
    Some((request.selection_kind, request.selection_id))
}

fn cloud_key() -> Option<String> {
    match std::env::var("OLLAMA_CLOUD_API_KEY") {
        Ok(value) if !value.is_empty() => Some(value),
        Ok(_) | Err(_) => None,
    }
}

fn api_base() -> Option<String> {
    match std::env::var("OLLAMA_API_BASE") {
        Ok(value) if !value.is_empty() => Some(value),
        Ok(_) | Err(std::env::VarError::NotPresent) => Some(DEFAULT_BASE.to_owned()),
        Err(std::env::VarError::NotUnicode(_)) => None,
    }
}

fn local_sentence() -> Response {
    plain(LOCAL_SENTENCE)
}

fn plain(body: &str) -> Response {
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/plain; charset=utf-8")],
        body.to_owned(),
    )
        .into_response()
}

fn truncate_scalars(content: &str) -> String {
    content.chars().take(REPLY_LIMIT).collect()
}

fn bearer_header(key: &str) -> Option<HeaderValue> {
    let mut value = HeaderValue::from_str(&format!("Bearer {key}")).ok()?;
    value.set_sensitive(true);
    Some(value)
}

fn ollama_client() -> Option<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .ok()
}

async fn request_explanation(key: &str, kind: SelectionKind, id: &str) -> Response {
    let Some(base) = api_base() else {
        return local_sentence();
    };
    let Some(client) = ollama_client() else {
        return local_sentence();
    };
    let Some(authorization) = bearer_header(key) else {
        return local_sentence();
    };
    let user_message = format!("selection_kind={}\nselection_id={id}", kind.token());
    let payload = ChatRequest {
        model: MODEL,
        messages: [ChatMessage {
            role: "user",
            content: &user_message,
        }],
        stream: false,
    };
    let url = format!("{}/api/chat", base.trim_end_matches('/'));
    let pending = client
        .post(url)
        .header(reqwest::header::AUTHORIZATION, authorization)
        .json(&payload);
    let response = match pending.send().await {
        Ok(response) => response,
        Err(_) => return local_sentence(),
    };
    if response.status().as_u16() != 200 {
        return local_sentence();
    }
    match response.json::<ChatResponse>().await {
        Ok(parsed) => plain(&truncate_scalars(&parsed.message.content)),
        Err(_) => local_sentence(),
    }
}
