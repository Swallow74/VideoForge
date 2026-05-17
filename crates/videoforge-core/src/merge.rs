use crate::profile::VideoProfile;
use crate::segment::Segment;
use std::collections::HashSet;

pub fn merge_and_group(segments: &[Segment], profile: &VideoProfile) -> Vec<Segment> {
    let mut grouped: Vec<Segment> = Vec::new();
    let mut buffer: Vec<Segment> = Vec::new();

    for seg in segments {
        if is_loop(&seg.text) {
            continue;
        }

        if buffer.is_empty() {
            buffer.push(seg.clone());
            continue;
        }

        let combined = buffer
            .iter()
            .map(|s| s.text.as_str())
            .collect::<Vec<_>>()
            .join(" ")
            + " "
            + &seg.text;
        let duration = seg.end - buffer[0].start;

        if combined.len() > profile.max_chars || duration > profile.max_duration {
            grouped.push(make_entry(&buffer));
            buffer.clear();
            buffer.push(seg.clone());
        } else {
            buffer.push(seg.clone());
        }
    }

    if !buffer.is_empty() {
        grouped.push(make_entry(&buffer));
    }

    grouped
}

fn is_loop(text: &str) -> bool {
    let lower = text.to_lowercase();
    let words: Vec<&str> = lower.split_whitespace().collect();
    if words.len() < 4 {
        return false;
    }

    let unique: HashSet<&&str> = words.iter().collect();
    if unique.len() <= 2 {
        return true;
    }

    if words.len() >= 8 {
        for n in [2, 3, 4] {
            if words.len() < n * 3 {
                continue;
            }
            let chunks: Vec<String> = words
                .chunks(n)
                .map(|chunk| chunk.join(" "))
                .collect();
            if chunks.len() >= 3 {
                let chunk_set: HashSet<&str> = chunks.iter().map(|s| s.as_str()).collect();
                if chunk_set.len() <= 1 {
                    return true;
                }
            }
        }
    }

    false
}

fn make_entry(segs: &[Segment]) -> Segment {
    Segment::new(
        segs[0].start,
        segs[segs.len() - 1].end,
        segs.iter().map(|s| s.text.as_str()).collect::<Vec<_>>().join(" "),
        vec![],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seg(start: f64, end: f64, text: &str) -> Segment {
        Segment::new(start, end, text, vec![])
    }

    #[test]
    fn test_merge_single() {
        let s = vec![seg(0.0, 1.0, "ciao")];
        let r = merge_and_group(&s, &VideoProfile::conversational());
        assert_eq!(r.len(), 1);
    }

    #[test]
    fn test_merge_joins_short() {
        let s = vec![seg(0.0, 1.0, "ciao"), seg(1.0, 2.0, "mondo")];
        let r = merge_and_group(&s, &VideoProfile::conversational());
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].text, "ciao mondo");
    }

    #[test]
    fn test_merge_splits_long() {
        let s: Vec<Segment> = (0..20).map(|i| seg(i as f64, (i + 1) as f64, "parola")).collect();
        let r = merge_and_group(&s, &VideoProfile::conversational());
        assert!(r.len() > 1, "Should split into multiple groups");
        for seg in &r {
            assert!(seg.end - seg.start <= 8.0, "Duration should not exceed max");
        }
    }

    #[test]
    fn test_merge_skips_loop() {
        let s = vec![seg(0.0, 1.0, "ciao ciao ciao ciao")];
        let r = merge_and_group(&s, &VideoProfile::conversational());
        assert!(r.is_empty());
    }

    #[test]
    fn test_merge_duration_respected() {
        let profile = VideoProfile::conversational();
        let s = vec![seg(0.0, 4.0, "Frase"), seg(4.0, 8.5, "lunga")];
        let r = merge_and_group(&s, &profile);
        assert_eq!(r.len(), 2, "Should split when duration exceeds max");
    }

    #[test]
    fn test_merge_profile_aware() {
        let prof_tech = VideoProfile::technical();
        let s = vec![seg(0.0, 1.0, "breve"), seg(1.0, 2.0, "test")];
        let r = merge_and_group(&s, &prof_tech);
        assert_eq!(r.len(), 1);
    }

    #[test]
    fn test_merge_empty() {
        let r = merge_and_group(&[], &VideoProfile::conversational());
        assert!(r.is_empty());
    }
}
