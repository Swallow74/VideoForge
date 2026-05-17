use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum ProfileName {
    Conversational,
    Lecturing,
    Technical,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct VideoProfile {
    pub name: ProfileName,
    pub boundary_threshold: f32,
    pub max_chars: usize,
    pub max_duration: f64,
    pub weak_conj_boost: f32,
    pub gap_break: f64,
}

impl VideoProfile {
    pub fn conversational() -> Self {
        Self {
            name: ProfileName::Conversational,
            boundary_threshold: 0.55,
            max_chars: 45,
            max_duration: 8.0,
            weak_conj_boost: 1.3,
            gap_break: 0.8,
        }
    }

    pub fn lecturing() -> Self {
        Self {
            name: ProfileName::Lecturing,
            boundary_threshold: 0.70,
            max_chars: 70,
            max_duration: 10.0,
            weak_conj_boost: 0.8,
            gap_break: 1.3,
        }
    }

    pub fn technical() -> Self {
        Self {
            name: ProfileName::Technical,
            boundary_threshold: 0.62,
            max_chars: 55,
            max_duration: 9.0,
            weak_conj_boost: 1.0,
            gap_break: 1.0,
        }
    }

    pub fn named(name: ProfileName) -> Self {
        match name {
            ProfileName::Conversational => Self::conversational(),
            ProfileName::Lecturing => Self::lecturing(),
            ProfileName::Technical => Self::technical(),
        }
    }
}
