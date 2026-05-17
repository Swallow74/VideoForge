use crate::profile::VideoProfile;
use crate::segment::Segment;

pub fn detect_profile(segments: &[Segment]) -> VideoProfile {
    if segments.is_empty() {
        return VideoProfile::conversational();
    }

    let sample_size = 30.min(segments.len());
    let sample_texts: Vec<&str> = segments[..sample_size].iter().map(|s| s.text.as_str()).collect();
    let full_sample = sample_texts.join(" ");
    let words: Vec<&str> = full_sample.split_whitespace().collect();

    if words.is_empty() {
        return VideoProfile::conversational();
    }

    let question_count = full_sample.chars().filter(|&c| c == '?').count() as f32;
    let question_ratio = question_count / words.len().max(1) as f32;
    let avg_seg_len = sample_texts.iter().map(|s| s.len()).sum::<usize>() / sample_texts.len().max(1);
    let avg_word_len = words.iter().map(|w| w.len()).sum::<usize>() / words.len().max(1);
    let long_seg_count = sample_texts.iter().filter(|s| s.len() > 60).count();
    let long_seg_ratio = long_seg_count as f32 / sample_texts.len().max(1) as f32;

    if question_ratio > 0.08 {
        VideoProfile::conversational()
    } else if long_seg_ratio > 0.5 && avg_seg_len > 65 {
        VideoProfile::lecturing()
    } else if avg_word_len > 6 {
        VideoProfile::technical()
    } else {
        VideoProfile::conversational()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::profile::ProfileName;

    fn seg(text: &str) -> Segment {
        Segment::new(0.0, 1.0, text, vec![])
    }

    #[test]
    fn test_detect_conversational() {
        let segs: Vec<Segment> = (0..30).map(|_| seg("Ciao come stai? Tutto bene?")).collect();
        let p = detect_profile(&segs);
        assert_eq!(p.name, ProfileName::Conversational);
    }

    #[test]
    fn test_detect_lecturing() {
        let long = "Questa è una frase molto lunga che supera abbondantemente i sessanta caratteri ed è tipica di un discorso strutturato";
        let segs: Vec<Segment> = (0..30).map(|_| seg(long)).collect();
        let p = detect_profile(&segs);
        assert_eq!(p.name, ProfileName::Lecturing);
    }

    #[test]
    fn test_detect_empty() {
        let p = detect_profile(&[]);
        assert_eq!(p.name, ProfileName::Conversational);
    }

    #[test]
    fn test_profile_values() {
        let c = VideoProfile::conversational();
        assert_eq!(c.boundary_threshold, 0.55);
        let l = VideoProfile::lecturing();
        assert_eq!(l.boundary_threshold, 0.70);
        let t = VideoProfile::technical();
        assert_eq!(t.boundary_threshold, 0.62);
        assert_eq!(c.max_chars, 45);
        assert_eq!(l.max_chars, 70);
        assert_eq!(t.max_chars, 55);
    }

    #[test]
    fn test_profile_named() {
        let p = VideoProfile::named(ProfileName::Technical);
        assert_eq!(p.name, ProfileName::Technical);
    }
}
