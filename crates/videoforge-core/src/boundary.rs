use crate::profile::VideoProfile;
use std::collections::HashSet;

static WEAK_CONNECTIVES: &[&str] = &[
    "e", "ma", "o", "oppure", "che", "perché", "perche", "quindi",
    "allora", "mentre", "invece", "comunque", "però", "pero",
    "dunque", "infatti", "cioè", "cioe", "inoltre",
    "anche", "poi", "tuttavia", "anzi",
];

static STRONG_STARTS: &[&str] = &[
    "no", "sì", "si", "ah", "oh", "beh", "ecco", "ok", "okay",
    "bene", "giusto", "certo",
];

static PAUSE_WORDS: &[&str] = &[
    "diciamo", "praticamente", "fondamentalmente", "sostanzialmente",
];

lazy_static::lazy_static! {
    static ref WEAK_SET: HashSet<&'static str> = WEAK_CONNECTIVES.iter().copied().collect();
    static ref STRONG_SET: HashSet<&'static str> = STRONG_STARTS.iter().copied().collect();
    static ref PAUSE_SET: HashSet<&'static str> = PAUSE_WORDS.iter().copied().collect();
}

#[derive(Debug, Clone, Default)]
pub struct BoundaryContext {
    pub prev_gap: f64,
    pub silence_after: f64,
}

pub fn evaluate_boundary(
    curr_text: &str,
    curr_end: f64,
    next_text: &str,
    next_start: f64,
    profile: &VideoProfile,
    context: Option<&BoundaryContext>,
) -> f32 {
    let curr = curr_text.trim();
    let nxt = next_text.trim();

    if curr.is_empty() || nxt.is_empty() {
        return 1.0;
    }

    let gap_sec = next_start - curr_end;
    let mut score: f32 = 0.0;

    let gap = f32::min((gap_sec / profile.gap_break) as f32, 1.5);
    score += gap * 0.25;

    if curr.len() > profile.max_chars {
        score += 0.4;
    }

    let ends_strong = curr.chars().last().map_or(false, |c| ".!?…".contains(c));
    let ends_comma = curr.chars().last().map_or(false, |c| ",;:".contains(c));

    if ends_strong {
        score += 0.7;
    } else if ends_comma {
        score -= 0.4;
    }

    if let Some(first_char) = nxt.chars().next() {
        if first_char.is_uppercase() {
            score += 0.3;
        } else {
            score -= 0.3;
        }
    }

    let first_word = nxt
        .split_whitespace()
        .next()
        .map(|w| w.trim_matches(|c: char| "«»\"'".contains(c)).to_lowercase())
        .unwrap_or_default();

    if WEAK_SET.contains(first_word.as_str()) {
        if !ends_strong {
            score -= 0.5 * profile.weak_conj_boost;
        }
    }
    if STRONG_SET.contains(first_word.as_str()) {
        score += 0.3;
    }
    if PAUSE_SET.contains(first_word.as_str()) {
        score -= 0.3;
    }

    let curr_words = curr.split_whitespace().count();
    let len_penalty = if curr_words <= 2 {
        0.5
    } else if curr_words <= 4 {
        0.2
    } else {
        0.0
    };

    if !ends_strong {
        score -= len_penalty;
    }

    if let Some(ctx) = context {
        if ctx.prev_gap > 0.0 && gap_sec < ctx.prev_gap * 0.3 {
            score -= 0.2;
        }
        if ctx.silence_after > 2.0 {
            score += 0.3;
        }
    }

    score
}

pub fn should_break(
    curr_text: &str,
    curr_end: f64,
    next_text: &str,
    next_start: f64,
    profile: &VideoProfile,
    context: Option<&BoundaryContext>,
) -> bool {
    evaluate_boundary(curr_text, curr_end, next_text, next_start, profile, context)
        >= profile.boundary_threshold
}
