use axum::body::Body;
use axum::http::{Request, StatusCode};
use helpmemove_api::{
    ActorMap, AuthorizeError, PROBE_OPERATION, Scope, app, authorize, synthetic_actor_map,
};
use http_body_util::BodyExt;
use tower::ServiceExt;

const TENANT_A: &str = "11111111-1111-4111-8111-111111111111";
const TENANT_B: &str = "22222222-2222-4222-8222-222222222222";
const SUBJECT_A1: &str = "33333333-3333-4333-8333-333333333333";
const SUBJECT_A2: &str = "44444444-4444-4444-8444-444444444444";
const ACTOR_A1: &str = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ACTOR_A2: &str = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ACTOR_B1: &str = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const ACTOR_REVOKED: &str = "99999999-9999-4999-8999-999999999999";
const OTHER_MARKER: &str = r#"{"synthetic":true,"hidden":"other-row"}"#;

fn sample_map() -> ActorMap {
    let mut map = ActorMap::new();
    map.insert(
        ACTOR_A1,
        Scope::new(TENANT_A, SUBJECT_A1, r#"{"synthetic":true}"#),
    );
    map.insert(ACTOR_A2, Scope::new(TENANT_A, SUBJECT_A2, OTHER_MARKER));
    map
}

#[test]
fn authorize_covers_the_four_probe_outcomes() {
    let served = synthetic_actor_map();
    assert_eq!(
        authorize(
            &served,
            PROBE_OPERATION,
            Some(ACTOR_A1),
            TENANT_A,
            SUBJECT_A1
        ),
        Ok(())
    );
    assert_eq!(
        authorize(
            &served,
            PROBE_OPERATION,
            Some(ACTOR_A1),
            TENANT_A,
            SUBJECT_A2
        ),
        Err(AuthorizeError::NotAllowed)
    );
    assert_eq!(
        authorize(
            &served,
            PROBE_OPERATION,
            Some(ACTOR_REVOKED),
            TENANT_A,
            SUBJECT_A1
        ),
        Err(AuthorizeError::NotAllowed)
    );

    let map = sample_map();
    let missing = authorize(&map, PROBE_OPERATION, None, TENANT_A, SUBJECT_A1);
    assert_eq!(missing, Err(AuthorizeError::NotAllowed));

    let matched = authorize(&map, PROBE_OPERATION, Some(ACTOR_A1), TENANT_A, SUBJECT_A1);
    assert_eq!(matched, Ok(()));

    let forged_tenant = authorize(&map, PROBE_OPERATION, Some(ACTOR_A1), TENANT_B, SUBJECT_A1);
    assert_eq!(forged_tenant, Err(AuthorizeError::NotAllowed));
    let forged_subject = authorize(&map, PROBE_OPERATION, Some(ACTOR_A1), TENANT_A, SUBJECT_A2);
    assert_eq!(forged_subject, Err(AuthorizeError::NotAllowed));

    let revoked = authorize(
        &map,
        PROBE_OPERATION,
        Some(ACTOR_REVOKED),
        TENANT_A,
        SUBJECT_A1,
    );
    assert_eq!(revoked, Err(AuthorizeError::NotAllowed));

    let other = map.get(ACTOR_A2).unwrap();
    for error in [missing, forged_tenant, forged_subject, revoked] {
        let text = error.unwrap_err().to_string();
        assert!(!text.contains(other.marker()));
        assert!(!text.contains("symptom"));
        assert!(!text.contains("email"));
    }
}

#[tokio::test]
async fn health_is_ok_without_a_database() {
    let response = send_app("/health", None).await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_bytes(response).await;
    assert_eq!(body, br#"{"status":"ok"}"#);
}

#[tokio::test]
async fn probe_http_outcomes_hide_the_other_marker() {
    let hidden = synthetic_actor_map()
        .get(ACTOR_A2)
        .unwrap()
        .marker()
        .to_owned();

    let missing = send_app(&probe_uri(TENANT_A, SUBJECT_A1), None).await;
    assert_eq!(missing.status(), StatusCode::UNAUTHORIZED);
    assert!(
        !body_bytes(missing)
            .await
            .windows(hidden.len())
            .any(|w| w == hidden.as_bytes())
    );

    let empty = send_app(&probe_uri(TENANT_A, SUBJECT_A1), Some("")).await;
    assert_eq!(empty.status(), StatusCode::UNAUTHORIZED);

    let matched = send_app(&probe_uri(TENANT_A, SUBJECT_A1), Some(ACTOR_A1)).await;
    assert_eq!(matched.status(), StatusCode::OK);
    let matched_body = body_bytes(matched).await;
    assert_eq!(matched_body, br#"{"allowed":true}"#);
    assert!(!contains_bytes(&matched_body, hidden.as_bytes()));

    let forged = send_app(&probe_uri(TENANT_A, SUBJECT_A2), Some(ACTOR_A1)).await;
    assert_eq!(forged.status(), StatusCode::NOT_FOUND);
    assert!(!contains_bytes(
        &body_bytes(forged).await,
        hidden.as_bytes()
    ));

    let revoked = send_app(&probe_uri(TENANT_A, SUBJECT_A1), Some(ACTOR_REVOKED)).await;
    assert_eq!(revoked.status(), StatusCode::NOT_FOUND);

    let cross_tenant = send_app(&probe_uri(TENANT_A, SUBJECT_A1), Some(ACTOR_B1)).await;
    assert_eq!(cross_tenant.status(), StatusCode::NOT_FOUND);
    assert!(!contains_bytes(
        &body_bytes(cross_tenant).await,
        hidden.as_bytes()
    ));

    let absent_query = send_app("/ownership/probe", Some(ACTOR_A1)).await;
    assert_eq!(absent_query.status(), StatusCode::NOT_FOUND);
}

fn probe_uri(tenant_id: &str, subject_id: &str) -> String {
    format!("/ownership/probe?tenant_id={tenant_id}&subject_id={subject_id}")
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    !needle.is_empty()
        && haystack
            .windows(needle.len())
            .any(|window| window == needle)
}

async fn send_app(uri: &str, token: Option<&str>) -> axum::response::Response {
    let mut builder = Request::builder().uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    app()
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap()
}

async fn body_bytes(response: axum::response::Response) -> Vec<u8> {
    response
        .into_body()
        .collect()
        .await
        .unwrap()
        .to_bytes()
        .to_vec()
}
