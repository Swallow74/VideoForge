use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WordTimestamp {
    pub word: String,
    pub start: f64,
    pub end: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub id: u64,
    pub start: f64,
    pub end: f64,
    pub text: String,
    pub words: Vec<WordTimestamp>,
}

impl Segment {
    pub fn new(start: f64, end: f64, text: impl Into<String>, words: Vec<WordTimestamp>) -> Self {
        Self {
            id: 0,
            start,
            end,
            text: text.into(),
            words,
        }
    }
}

impl WordTimestamp {
    pub fn new(word: impl Into<String>, start: f64, end: f64) -> Self {
        Self { word: word.into(), start, end }
    }
}
