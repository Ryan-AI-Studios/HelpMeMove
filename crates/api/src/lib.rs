#![deny(clippy::unwrap_used, clippy::expect_used)]

//! In-memory ownership probe. This crate does not open Postgres and does not
//! read `identity_map`. The database proof is the pgTAP file.

use std::collections::HashMap;

use axum::Json;
use axum::Router;
use axum::extract::{Query, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde::{Deserialize, Serialize};

pub const PROBE_OPERATION: &str = "probe";

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Scope {
    tenant_id: String,
    subject_id: String,
    marker: String,
}

impl Scope {
    pub fn new(
        tenant_id: impl Into<String>,
        subject_id: impl Into<String>,
        marker: impl Into<String>,
    ) -> Self {
        Self {
            tenant_id: tenant_id.into(),
            subject_id: subject_id.into(),
            marker: marker.into(),
        }
    }

    pub fn marker(&self) -> &str {
        &self.marker
    }
}

#[derive(Clone, Debug, Default)]
pub struct ActorMap {
    entries: HashMap<String, Scope>,
}

impl ActorMap {
    pub fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    pub fn insert(&mut self, actor_id: impl Into<String>, scope: Scope) {
        self.entries.insert(actor_id.into(), scope);
    }

    pub fn get(&self, actor_id: &str) -> Option<&Scope> {
        self.entries.get(actor_id)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
pub enum AuthorizeError {
    #[error("not allowed")]
    NotAllowed,
}

pub fn authorize(
    map: &ActorMap,
    operation: &str,
    token: Option<&str>,
    tenant_id: &str,
    subject_id: &str,
) -> Result<(), AuthorizeError> {
    if operation != PROBE_OPERATION {
        return Err(AuthorizeError::NotAllowed);
    }
    let Some(token) = token.map(str::trim).filter(|value| !value.is_empty()) else {
        return Err(AuthorizeError::NotAllowed);
    };
    let Some(scope) = map.get(token) else {
        return Err(AuthorizeError::NotAllowed);
    };
    if scope.tenant_id != tenant_id || scope.subject_id != subject_id {
        return Err(deny_without_marker(scope));
    }
    Ok(())
}

fn deny_without_marker(scope: &Scope) -> AuthorizeError {
    let error = AuthorizeError::NotAllowed;
    debug_assert!(
        !error.to_string().contains(scope.marker()),
        "denial must not include the stored marker"
    );
    error
}

#[derive(Serialize)]
struct HealthBody {
    status: &'static str,
}

#[derive(Serialize)]
struct AllowedBody {
    allowed: bool,
}

#[derive(Debug, Deserialize)]
struct ProbeQuery {
    tenant_id: Option<String>,
    subject_id: Option<String>,
}

/// Synthetic local actors. The bearer value is the actor id.
/// Track 0019 owns real token verification. This map is not read from Postgres.
pub fn synthetic_actor_map() -> ActorMap {
    let mut map = ActorMap::new();
    map.insert(
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        Scope::new(
            "11111111-1111-4111-8111-111111111111",
            "33333333-3333-4333-8333-333333333333",
            r#"{"synthetic":true}"#,
        ),
    );
    map.insert(
        "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        Scope::new(
            "11111111-1111-4111-8111-111111111111",
            "44444444-4444-4444-8444-444444444444",
            r#"{"synthetic":true}"#,
        ),
    );
    map.insert(
        "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        Scope::new(
            "22222222-2222-4222-8222-222222222222",
            "55555555-5555-4555-8555-555555555555",
            r#"{"synthetic":true}"#,
        ),
    );
    map
}

pub fn app() -> Router {
    router(synthetic_actor_map())
}

pub fn router(map: ActorMap) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/ownership/probe", get(probe))
        .with_state(map)
}

async fn health() -> Json<HealthBody> {
    Json(HealthBody { status: "ok" })
}

async fn probe(
    State(map): State<ActorMap>,
    headers: HeaderMap,
    Query(query): Query<ProbeQuery>,
) -> Response {
    let Some(token) = bearer_token(&headers) else {
        return StatusCode::UNAUTHORIZED.into_response();
    };
    let Some(tenant_id) = nonempty(query.tenant_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let Some(subject_id) = nonempty(query.subject_id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    match authorize(&map, PROBE_OPERATION, Some(token), &tenant_id, &subject_id) {
        Ok(()) => Json(AllowedBody { allowed: true }).into_response(),
        Err(AuthorizeError::NotAllowed) => StatusCode::NOT_FOUND.into_response(),
    }
}

fn bearer_token(headers: &HeaderMap) -> Option<&str> {
    let raw = headers.get(header::AUTHORIZATION)?;
    let value = raw.to_str().ok()?;
    let token = value.strip_prefix("Bearer ")?.trim();
    if token.is_empty() { None } else { Some(token) }
}

fn nonempty(value: Option<String>) -> Option<String> {
    let trimmed = value?.trim().to_owned();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}
