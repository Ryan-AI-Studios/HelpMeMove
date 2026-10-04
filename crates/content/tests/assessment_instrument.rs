use helpmemove_content::{
    AssessmentInstrument, ContentError, MovementRating, parse_assessment_instrument,
};

const COMMITTED: &str = include_str!("../../../content/assessments/syn-assessment-core.json");

#[test]
fn ratings_round_trip_and_unknown_tokens_are_none() {
    let cases = [
        ("normal", MovementRating::Normal, "Normal"),
        ("limited", MovementRating::Limited, "Limited"),
        ("painful", MovementRating::Painful, "Painful"),
        ("very_painful", MovementRating::VeryPainful, "Very painful"),
        ("unable", MovementRating::Unable, "Unable"),
    ];
    for (token, rating, label) in cases {
        assert_eq!(MovementRating::parse(token), Some(rating));
        assert_eq!(rating.as_str(), token);
        assert_eq!(rating.label(), label);
    }
    assert_eq!(MovementRating::parse("difficult"), None);
    assert_eq!(MovementRating::parse("Normal"), None);
    assert_eq!(MovementRating::parse("very painful"), None);
    assert_eq!(MovementRating::parse(""), None);
}

#[test]
fn committed_instrument_parses() {
    let instrument = parse_assessment_instrument(COMMITTED).expect("committed instrument");
    assert_eq!(
        instrument,
        AssessmentInstrument {
            instrument_id: "syn-assessment-core",
            instrument_version: 1,
            ratings: [
                MovementRating::Normal,
                MovementRating::Limited,
                MovementRating::Painful,
                MovementRating::VeryPainful,
                MovementRating::Unable,
            ],
        }
    );
}

#[test]
fn extra_key_is_invalid_document_without_the_key() {
    let text = r#"{"instrument_id":"syn-assessment-core","instrument_version":1,"ratings":["normal","limited","painful","very_painful","unable"],"not_in_the_error":true}"#;
    let error = parse_assessment_instrument(text).expect_err("extra key");
    assert_eq!(error, ContentError::InvalidDocument);
    assert_eq!(error.code(), "invalid-document");
    assert!(!error.to_string().contains("not_in_the_error"));
    assert!(!error.code().contains("not_in_the_error"));
}

#[test]
fn malformed_and_reordered_documents_stay_invalid_document() {
    let malformed = parse_assessment_instrument("{").expect_err("brace");
    assert_eq!(malformed, ContentError::InvalidDocument);
    assert!(!malformed.to_string().contains('{'));

    let swapped = r#"{"instrument_id":"syn-assessment-core","instrument_version":1,"ratings":["limited","normal","painful","very_painful","unable"]}"#;
    assert_eq!(
        parse_assessment_instrument(swapped).expect_err("order"),
        ContentError::InvalidDocument
    );
}

#[test]
fn wrong_id_and_version_stay_invalid_document() {
    let wrong_id = r#"{"instrument_id":"clinical-shoulder","instrument_version":1,"ratings":["normal","limited","painful","very_painful","unable"]}"#;
    let id_error = parse_assessment_instrument(wrong_id).expect_err("id");
    assert_eq!(id_error, ContentError::InvalidDocument);
    assert!(!id_error.to_string().contains("clinical-shoulder"));

    let wrong_version = r#"{"instrument_id":"syn-assessment-core","instrument_version":2,"ratings":["normal","limited","painful","very_painful","unable"]}"#;
    let version_error = parse_assessment_instrument(wrong_version).expect_err("version");
    assert_eq!(version_error, ContentError::InvalidDocument);
    assert_eq!(version_error.code(), "invalid-document");
}
