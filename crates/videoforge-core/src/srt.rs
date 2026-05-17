use crate::segment::Segment;

pub const MAX_CPS: usize = 15;

pub fn format_timestamp(seconds: f64) -> String {
    let s = seconds.max(0.0);
    let h = (s as i64) / 3600;
    let m = ((s as i64) % 3600) / 60;
    let sec = (s as i64) % 60;
    let ms = ((s - s.floor()) * 1000.0).round() as i64;
    let ms = ms.min(999);
    format!("{h:02}:{m:02}:{sec:02},{ms:03}")
}

pub fn wrap_text(text: &str, max_chars: usize) -> String {
    let words: Vec<&str> = text.split_whitespace().collect();
    let mut lines: Vec<String> = Vec::new();
    let mut current_line = String::new();

    for word in words {
        if current_line.is_empty() {
            current_line = word.to_string();
        } else if current_line.len() + word.len() + 1 <= max_chars {
            current_line.push(' ');
            current_line.push_str(word);
        } else {
            lines.push(current_line);
            current_line = word.to_string();
        }
    }
    if !current_line.is_empty() {
        lines.push(current_line);
    }

    lines.truncate(3);
    lines.join("\n")
}

fn split_by_cps(seg: &Segment) -> Vec<Segment> {
    let dur = seg.end - seg.start;
    let text = &seg.text;

    if dur <= 0.0 || (text.len() as f64 / dur) <= MAX_CPS as f64 {
        return vec![seg.clone()];
    }

    let candidates: Vec<usize> = text
        .char_indices()
        .filter_map(|(i, ch)| if ".!?".contains(ch) { Some(i + 1) } else { None })
        .collect();

    if candidates.is_empty() {
        return vec![seg.clone()];
    }

    let mid = text.len() / 2;
    let split_pos = candidates
        .iter()
        .copied()
        .min_by(|a, b| {
            let da = if *a > mid { *a - mid } else { mid - *a };
            let db = if *b > mid { *b - mid } else { mid - *b };
            da.cmp(&db)
        })
        .unwrap();

    if split_pos < 15 || text.len() - split_pos < 15 {
        return vec![seg.clone()];
    }

    let part_a = text[..split_pos].trim().to_string();
    let part_b = text[split_pos..].trim().to_string();

    if part_a.is_empty() || part_b.is_empty() {
        return vec![seg.clone()];
    }

    let total_len = part_a.len() + part_b.len();
    let ratio_a = if total_len > 0 {
        part_a.len() as f64 / total_len as f64
    } else {
        0.5
    };
    let split_at = seg.start + dur * ratio_a;

    let a_dur = split_at - seg.start;
    let b_dur = seg.end - split_at;

    if a_dur < 1.0 || b_dur < 1.0 {
        return vec![seg.clone()];
    }

    vec![
        Segment::new(seg.start, split_at, &part_a, vec![]),
        Segment::new(split_at, seg.end, &part_b, vec![]),
    ]
}

fn validate_segments(segments: &[Segment]) -> Vec<Segment> {
    let mut validated: Vec<Segment> = Vec::new();
    for seg in segments {
        let mut s = seg.clone();
        if s.end <= s.start {
            s.end = s.start + 0.5;
        }
        if let Some(last) = validated.last() {
            if s.start < last.start {
                s.start = last.end;
            }
            if s.start >= s.end {
                s.start = last.end;
                s.end = s.start + 0.5;
            }
        }
        validated.push(s);
    }
    validated
}

pub fn export_srt(segments: &[Segment], output_path: &str) -> Result<(), String> {
    let validated = validate_segments(segments);

    let mut resynced: Vec<Segment> = Vec::new();
    for seg in &validated {
        resynced.extend(split_by_cps(seg));
    }

    let resynced = validate_segments(&resynced);

    let mut lines: Vec<String> = Vec::new();
    for (i, seg) in resynced.iter().enumerate() {
        let start_ts = format_timestamp(seg.start);
        let end_ts = format_timestamp(seg.end);
        let mut text = seg.text.clone();

        if text.to_lowercase().contains("fino a poco")
            && !text.to_lowercase().contains("tempo fa")
        {
            text = text.replace("fino a poco", "fino a poco tempo fa");
        }

        text = wrap_text(&text, 42);
        lines.push(format!("{}", i + 1));
        lines.push(format!("{start_ts} --> {end_ts}"));
        lines.push(text);
        lines.push(String::new());
    }

    let content = lines.join("\n");
    std::fs::write(output_path, &content).map_err(|e| format!("{e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seg(start: f64, end: f64, text: &str) -> Segment {
        Segment::new(start, end, text, vec![])
    }

    #[test]
    fn test_format_timestamp() {
        assert_eq!(format_timestamp(0.0), "00:00:00,000");
    }

    #[test]
    fn test_format_timestamp_zero() {
        assert_eq!(format_timestamp(3661.0), "01:01:01,000");
    }

    #[test]
    fn test_format_timestamp_no_leading_zeros() {
        assert_eq!(format_timestamp(65.0), "00:01:05,000");
    }

    #[test]
    fn test_wrap_text_short() {
        assert_eq!(wrap_text("Ciao mondo", 42), "Ciao mondo");
    }

    #[test]
    fn test_wrap_text_long() {
        let long = "parola " .repeat(20).trim().to_string();
        let wrapped = wrap_text(&long, 42);
        assert!(wrapped.lines().count() <= 3);
    }

    #[test]
    fn test_split_by_cps_under_limit() {
        let s = seg(0.0, 10.0, "Corto testo");
        let r = split_by_cps(&s);
        assert_eq!(r.len(), 1);
    }

    #[test]
    fn test_split_by_cps_over_limit() {
        let long = "Prima parte della frase che finisce qui. Seconda parte che continua oltre il limite di caratteri al secondo";
        let s = seg(0.0, 5.0, long);
        let r = split_by_cps(&s);
        assert_eq!(r.len(), 2);
        assert_eq!(r[0].start, 0.0);
        assert_eq!(r[1].end, 5.0);
    }

    #[test]
    fn test_split_by_cps_edge_too_small() {
        let s = seg(0.0, 1.0, "a b.");
        let r = split_by_cps(&s);
        assert_eq!(r.len(), 1, "Too small to split");
    }

    #[test]
    fn test_split_by_cps_no_punct() {
        let s = seg(0.0, 0.1, &"parola ".repeat(50).trim().to_string());
        let r = split_by_cps(&s);
        assert_eq!(r.len(), 1, "No puntuation, cannot split");
    }

    #[test]
    fn test_validate_segments() {
        let s = vec![seg(10.0, 5.0, "inverted")];
        let r = validate_segments(&s);
        assert!(r[0].end > r[0].start);
    }

    #[test]
    fn test_export_srt() {
        let s = vec![seg(0.0, 1.0, "Ciao mondo")];
        let path = std::env::temp_dir().join("test_export.srt");
        let path_str = path.to_str().unwrap().to_string();
        assert!(export_srt(&s, &path_str).is_ok());
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("00:00:00,000 --> 00:00:01,000"));
        assert!(content.contains("Ciao mondo"));
        std::fs::remove_file(&path).ok();
    }
}
