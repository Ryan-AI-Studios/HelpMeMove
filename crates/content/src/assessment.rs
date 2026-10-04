//! Synthetic movement-check fixture. Not a clinician-approved instrument.

use serde_json::Value;

use super::ContentError;

const INSTRUMENT_ID: &str = "syn-assessment-core";

const RATING_ORDER: [MovementRating; 5] = [
    MovementRating::Normal,
    MovementRating::Limited,
    MovementRating::Painful,
    MovementRating::VeryPainful,
    MovementRating::Unable,
];

/// Self-report word. These are not green, yellow, orange, or red.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MovementRating {
    Normal,
    Limited,
    Painful,
    VeryPainful,
    Unable,
}

impl MovementRating {
    /// Closed token. Unknown strings return `None`.
    pub fn parse(raw: &str) -> Option<Self> {
        Some(match raw {
            "normal" => Self::Normal,
            "limited" => Self::Limited,
            "painful" => Self::Painful,
            "very_painful" => Self::VeryPainful,
            "unable" => Self::Unable,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Limited => "limited",
            Self::Painful => "painful",
            Self::VeryPainful => "very_painful",
            Self::Unable => "unable",
        }
    }

    /// Display word. Not a safety level.
    pub fn label(self) -> &'static str {
        match self {
            Self::Normal => "Normal",
            Self::Limited => "Limited",
            Self::Painful => "Painful",
            Self::VeryPainful => "Very painful",
            Self::Unable => "Unable",
        }
    }
}

/// Parsed `syn-assessment-core` fixture.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AssessmentInstrument {
    pub instrument_id: &'static str,
    pub instrument_version: u32,
    pub ratings: [MovementRating; 5],
}

/// Accept only the committed id, integer version 1, and the five ratings in order.
///
/// Any other shape is [`ContentError::InvalidDocument`]. The error does not include the document.
pub fn parse_assessment_instrument(text: &str) -> Result<AssessmentInstrument, ContentError> {
    let value: Value = serde_json::from_str(text).map_err(|_| ContentError::InvalidDocument)?;
    let Some(object) = value.as_object() else {
        return Err(ContentError::InvalidDocument);
    };
    if object.len() != 3
        || !object.contains_key("instrument_id")
        || !object.contains_key("instrument_version")
        || !object.contains_key("ratings")
    {
        return Err(ContentError::InvalidDocument);
    }
    let Some(id) = object.get("instrument_id").and_then(Value::as_str) else {
        return Err(ContentError::InvalidDocument);
    };
    if id != INSTRUMENT_ID {
        return Err(ContentError::InvalidDocument);
    }
    let Some(version) = object.get("instrument_version").and_then(Value::as_i64) else {
        return Err(ContentError::InvalidDocument);
    };
    if version != 1 {
        return Err(ContentError::InvalidDocument);
    }
    let Some(items) = object.get("ratings").and_then(Value::as_array) else {
        return Err(ContentError::InvalidDocument);
    };
    if items.len() != RATING_ORDER.len() {
        return Err(ContentError::InvalidDocument);
    }
    let mut ratings = RATING_ORDER;
    for (index, item) in items.iter().enumerate() {
        let Some(token) = item.as_str() else {
            return Err(ContentError::InvalidDocument);
        };
        let Some(rating) = MovementRating::parse(token) else {
            return Err(ContentError::InvalidDocument);
        };
        if rating != RATING_ORDER[index] {
            return Err(ContentError::InvalidDocument);
        }
        ratings[index] = rating;
    }
    Ok(AssessmentInstrument {
        instrument_id: INSTRUMENT_ID,
        instrument_version: 1,
        ratings,
    })
}
