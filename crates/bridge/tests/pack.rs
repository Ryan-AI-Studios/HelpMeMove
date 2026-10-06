use helpmemove_bridge::api::bridge::{
    SafetyAnswer, classify_committed_rule, committed_disable_list, committed_disable_list_sig,
    evaluate_content_pack, recalled_sessions, verify_disable_list,
};

#[test]
fn first_launch_classifies_without_pack_bytes() {
    let unmatched = classify_committed_rule(
        vec![SafetyAnswer {
            token: "schema_ack".to_owned(),
            value: "yes".to_owned(),
        }],
        1_767_225_600_000,
        Vec::new(),
        String::new(),
    );
    assert_eq!(unmatched.code, "unmatched");
    assert!(!unmatched.permits_ordinary_generation);
}

#[test]
fn committed_disable_list_verifies_and_recalls_nothing() {
    let json = committed_disable_list();
    let sig = committed_disable_list_sig();
    assert_eq!(verify_disable_list(json.clone(), sig.clone()), "accept");
    assert!(
        recalled_sessions(
            vec![
                r#"{"rule_id":"syn-program-core","record_version":1,"session_id":"session-one"}"#
                    .to_owned()
            ],
            json,
        )
        .is_empty()
    );
    assert_eq!(
        verify_disable_list(committed_disable_list(), "aa".repeat(64)),
        "invalid-signature"
    );
}

#[test]
fn evaluate_content_pack_rejects_path_length_mismatch() {
    let code = evaluate_content_pack(
        "{}".to_owned(),
        "aa".repeat(64),
        vec!["a".to_owned()],
        Vec::new(),
        1,
        committed_disable_list(),
        committed_disable_list_sig(),
        0,
        0,
        None,
    );
    assert_eq!(code, "invalid-manifest");
}

#[test]
fn recalled_sessions_returns_rule_match() {
    let list =
        r#"{"schema_version":1,"entries":[{"kind":"rule","id":"syn-program-core","version":1}]}"#;
    let ids = recalled_sessions(
        vec![
            r#"{"rule_id":"syn-program-core","record_version":1,"session_id":"session-one"}"#
                .to_owned(),
        ],
        list.to_owned(),
    );
    assert_eq!(ids, vec!["session-one".to_owned()]);
    assert!(recalled_sessions(vec!["not-json".to_owned()], "bad".to_owned()).is_empty());
}
