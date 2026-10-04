use helpmemove_bridge::api::bridge::{
    BridgeError, accept_rating, assessment_vocabulary, load_committed_instrument,
};

#[test]
fn accept_rating_accepts_normal_and_hides_unknown_tokens() {
    assert_eq!(accept_rating("normal".to_owned()).as_deref(), Ok("normal"));
    let raw = "not-a-rating";
    match accept_rating(raw.to_owned()) {
        Err(error) => {
            assert_eq!(error, BridgeError::InvalidRating);
            assert_eq!(error.code(), "invalid-rating");
            assert!(!error.to_string().contains(raw));
        }
        Ok(value) => panic!("accepted rating {value}"),
    }
}

#[test]
fn load_committed_instrument_returns_id_and_version() {
    let view = load_committed_instrument().expect("instrument");
    assert_eq!(view.instrument_id, "syn-assessment-core");
    assert_eq!(view.instrument_version, 1);

    let error = BridgeError::InvalidInstrument;
    assert_eq!(error.code(), "invalid-instrument");
    assert!(!error.to_string().contains("syn-assessment-core"));
}

#[test]
fn vocabulary_keeps_fixture_order() {
    assert_eq!(
        assessment_vocabulary().ratings,
        ["normal", "limited", "painful", "very_painful", "unable",]
    );
}
