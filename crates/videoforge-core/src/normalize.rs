use crate::boundary::{should_break, BoundaryContext};
use crate::profile::VideoProfile;
use regex::Regex;

pub fn normalize_text(text: &str) -> String {
    let re_spaces = Regex::new(r"\s+").unwrap();
    let re_punct = Regex::new(r"\s+([.,!?;:])").unwrap();
    let re_sent = Regex::new(r"([.!?])([A-Za-z])").unwrap();

    let mut t = re_spaces.replace_all(text, " ").to_string();
    t = t.trim().to_string();
    if t.is_empty() {
        return t;
    }
    // Capitalize first letter
    if let Some(first) = t.chars().next() {
        if first.is_lowercase() {
            let mut c = t.chars();
            let first = c.next().unwrap();
            t = first.to_uppercase().to_string() + c.as_str();
        }
    }
    t = re_punct.replace_all(&t, "$1").to_string();
    t = re_sent.replace_all(&t, "$1 $2").to_string();
    t
}

pub fn fix_punct_local(
    text: &str,
    next_text: &str,
    gap_sec: f64,
    profile: &VideoProfile,
    context: Option<&BoundaryContext>,
) -> String {
    let mut t = text.trim().to_string();
    if t.is_empty() {
        return t;
    }

    let brk = if next_text.is_empty() {
        true
    } else {
        should_break(&t, 0.0, next_text, gap_sec, profile, context)
    };

    // Capitalize first letter if lowercase
    if let Some(first) = t.chars().next() {
        if first.is_lowercase() {
            let mut c = t.chars();
            let first = c.next().unwrap();
            t = first.to_uppercase().to_string() + c.as_str();
        }
    }

    if brk {
        if let Some(last) = t.chars().last() {
            if !".!?".contains(last) {
                t.push('.');
            }
        }
    } else {
        if let Some(last) = t.chars().last() {
            if ".!?".contains(last) {
                let word_count = t.split_whitespace().count();
                if word_count <= 1 {
                    t = t.trim_end_matches(|c: char| ".!?".contains(c))
                        .trim()
                        .to_string();
                }
            }
        }
    }

    t
}

pub fn needs_qwen(text: &str) -> bool {
    if text.len() < 30 {
        return false;
    }
    if text.contains('[') || text.contains(']') || text.contains('(') || text.contains(')') {
        return true;
    }
    let double_spaces = text.split("  ").count();
    if double_spaces > 2 {
        return true;
    }
    let re_adjacent = Regex::new(r"[a-z][A-Z]").unwrap();
    if re_adjacent.is_match(text) {
        return true;
    }
    // Need correction if doesn't end with sentence-ending punctuation
    // (indicates mid-sentence truncation)
    let trimmed = text.trim();
    if let Some(last) = trimmed.chars().last() {
        if !".!?".contains(last) {
            return true;
        }
    }
    let words: Vec<&str> = text.split_whitespace().collect();
    if words.len() >= 3 {
        let unique: std::collections::HashSet<String> =
            words.iter().map(|w| w.to_lowercase()).collect();
        if unique.len() <= 2 {
            return false;
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_whitespace() {
        assert_eq!(normalize_text("  ciao    mondo  "), "Ciao mondo");
    }

    #[test]
    fn test_normalize_capitalize() {
        assert_eq!(normalize_text("ciao"), "Ciao");
    }

    #[test]
    fn test_normalize_non_ascii_first_char() {
        assert_eq!(normalize_text("è giusto"), "È giusto");
        assert_eq!(normalize_text("ñandu"), "Ñandu");
        assert_eq!(normalize_text("你好世界"), "你好世界");
    }

    #[test]
    fn test_normalize_punct_spacing() {
        assert_eq!(normalize_text("Ciao , mondo"), "Ciao, mondo");
    }

    #[test]
    fn test_normalize_sentence_break() {
        assert_eq!(normalize_text("Fine.Inizia"), "Fine. Inizia");
    }

    #[test]
    fn test_fix_punct_break() {
        let profile = VideoProfile::conversational();
        let r = fix_punct_local("ciao mondo", "", 2.0, &profile, None);
        assert!(r.ends_with('.'), "expected ending with '.', got: {r}");
    }

    #[test]
    fn test_fix_punct_no_break() {
        let profile = VideoProfile::conversational();
        let r = fix_punct_local("ciao", "mondo", 0.1, &profile, None);
        assert!(!r.ends_with('.'), "expected no trailing dot, got: {r}");
    }

    #[test]
    fn test_fix_punct_single_word() {
        let profile = VideoProfile::conversational();
        let r = fix_punct_local("Ciao.", "mondo", 0.1, &profile, None);
        assert_eq!(r, "Ciao", "expected single word without dot");
    }

    #[test]
    fn test_needs_qwen_short() {
        assert!(!needs_qwen("Corto"));
    }

    #[test]
    fn test_needs_qwen_false_for_normal() {
        assert!(!needs_qwen("Questa è una frase normale di esempio"));
    }

    #[test]
    fn test_needs_qwen_with_brackets() {
        assert!(needs_qwen("Questa è una frase [con] brackets abbastanza lunga"));
    }

    #[test]
    fn test_needs_qwen_loop() {
        assert!(!needs_qwen("la la la"));
    }

    #[test]
    fn test_fino_a_poco_fix() {
        let profile = VideoProfile::conversational();
        let r = fix_punct_local("fino a poco", "", 2.0, &profile, None);
        assert_eq!(r.chars().next().unwrap(), 'F');
        assert!(r.ends_with('.'));
    }
}
