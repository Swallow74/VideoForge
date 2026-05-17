use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};

fn find_in_path(name: &str) -> Option<String> {
    std::env::var("PATH").ok().and_then(|path| {
        for dir in path.split(':') {
            let candidate = format!("{}/{}", dir, name);
            if Path::new(&candidate).is_file() {
                return Some(candidate);
            }
        }
        None
    })
}

fn is_video(path: &str) -> bool {
    matches!(
        Path::new(path).extension().and_then(|e| e.to_str()),
        Some(ext) if matches!(ext.to_lowercase().as_str(), "mp4" | "mov" | "mkv" | "avi")
    )
}

fn get_duration(path: &str) -> f64 {
    let ffprobe = find_in_path("ffprobe").unwrap_or_else(|| "ffprobe".to_string());
    Command::new(&ffprobe)
        .args(["-v", "quiet", "-print_format", "json", "-show_format", path])
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok())
        .and_then(|v| v["format"]["duration"].as_str()?.parse::<f64>().ok())
        .unwrap_or(0.0)
}

fn detect_silence(path: &str, threshold: f64, min_duration: f64) -> Result<Vec<(f64, f64)>, String> {
    let ffmpeg = find_in_path("ffmpeg").unwrap_or_else(|| "ffmpeg".to_string());

    let output = Command::new(&ffmpeg)
        .args([
            "-i", path,
            "-af", &format!("silencedetect=noise={}dB:d={}", threshold, min_duration),
            "-f", "null", "-",
        ])
        .output()
        .map_err(|e| format!("Errore ffmpeg silencedetect: {e}"))?;

    let stderr = String::from_utf8_lossy(&output.stderr);
    let mut silences: Vec<(f64, f64)> = Vec::new();
    let mut start: Option<f64> = None;

    for line in stderr.lines() {
        let line = line.trim();
        if let Some(val) = line.split("silence_start:").nth(1) {
            if let Ok(t) = val.trim().parse::<f64>() {
                start = Some(t);
            }
        } else if let Some(val) = line.split("silence_end:").nth(1) {
            if let Some(end_str) = val.split('|').next() {
                if let Ok(t) = end_str.trim().parse::<f64>() {
                    if let Some(s) = start {
                        silences.push((s, t));
                        start = None;
                    }
                }
            }
        }
    }

    Ok(silences)
}

const PADDING: f64 = 0.15;

fn non_silent_segments(path: &str, threshold: f64, min_duration: f64) -> Result<Vec<(f64, f64)>, String> {
    let total = get_duration(path);
    if total <= 0.0 {
        return Err("Impossibile ottenere la durata del file".into());
    }

    let silence = detect_silence(path, threshold, min_duration)?;

    if silence.is_empty() {
        return Ok(vec![(0.0, total)]);
    }

    let mut segs: Vec<(f64, f64)> = Vec::new();
    let mut cur = 0.0;

    for (s, e) in &silence {
        let s = *s;
        let e = e.min(total);
        if s > cur + 0.001 {
            segs.push((cur, s));
        }
        cur = e;
    }

    if total > cur + 0.001 {
        segs.push((cur, total));
    }

    for seg in &mut segs {
        seg.0 = (seg.0 - PADDING).max(0.0);
        seg.1 = (seg.1 + PADDING).min(total);
    }

    let mut merged: Vec<(f64, f64)> = Vec::new();
    for seg in segs {
        if let Some(last) = merged.last_mut() {
            if seg.0 - last.1 < 0.3 {
                last.1 = last.1.max(seg.1);
            } else {
                merged.push(seg);
            }
        } else {
            merged.push(seg);
        }
    }

    Ok(merged)
}

pub type ProgressFn = Box<dyn Fn(f64) + Send + 'static>;

pub fn clean_audio(
    input_path: &str,
    output_path: &str,
    remove_silence: bool,
    silence_threshold: f64,
    silence_duration: f64,
    remove_noise: bool,
    noise_strength: f64,
    total_duration: f64,
    progress: &dyn Fn(f64),
) -> Result<String, String> {
    let ffmpeg = find_in_path("ffmpeg").unwrap_or_else(|| "ffmpeg".to_string());
    let input_is_video = is_video(input_path);

    if remove_silence {
        let segs = non_silent_segments(input_path, silence_threshold, silence_duration)?;
        let dur = get_duration(input_path);
        if segs.len() > 1
            || segs.first().map_or(true, |(s, e)| *s > 0.1 || *e < dur - 0.1)
        {
            return build_trim_concat_reencode(
                &ffmpeg, input_path, output_path, &segs,
                input_is_video, remove_noise, noise_strength,
                total_duration, progress,
            );
        }
    }

    if remove_noise {
        progress(0.0);
        let filter_str = format!("afftdn=nr={}", noise_strength);
        let mut args = vec!["-y", "-i", input_path, "-progress", "pipe:1", "-af", &filter_str];
        if input_is_video {
            args.extend_from_slice(&["-c:v", "copy"]);
        }
        args.push(output_path);

        let mut child = Command::new(&ffmpeg)
            .args(&args)
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| format!("Errore ffmpeg: {e}"))?;

        crate::CURRENT_FFMPEG_PID.store(child.id(), std::sync::atomic::Ordering::SeqCst);

        if let Some(stdout) = child.stdout.take() {
            for line in BufReader::new(stdout).lines() {
                if let Ok(line) = line {
                    if line.starts_with("out_time_us=") {
                        if let Ok(us) = line[12..].trim().parse::<f64>() {
                            let pct = (us / 1_000_000.0 / total_duration.max(1.0)).min(1.0);
                            progress(pct);
                        }
                    }
                }
            }
        }

        let status = child.wait().map_err(|e| format!("Errore wait: {e}"))?;
        crate::CURRENT_FFMPEG_PID.store(0, std::sync::atomic::Ordering::SeqCst);
        if !status.success() {
            return Err("Elaborazione interrotta".into());
        }
        progress(1.0);
        return Ok(output_path.to_string());
    }

    Err("Nessuna elaborazione richiesta".into())
}

fn get_video_bitrate(path: &str) -> Option<String> {
    let ffprobe = find_in_path("ffprobe")?;
    Command::new(&ffprobe)
        .args(["-v", "quiet", "-print_format", "json",
               "-select_streams", "v:0",
               "-show_entries", "stream=bit_rate", path])
        .output().ok()
        .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok())
        .and_then(|v| v["streams"][0]["bit_rate"].as_str().map(String::from))
}

/// filter_complex trim+concat with re-encode via Apple Silicon hardware encoder.
/// Keeps original bitrate so quality is preserved.
fn build_trim_concat_reencode(
    ffmpeg: &str,
    input_path: &str,
    output_path: &str,
    segments: &[(f64, f64)],
    input_is_video: bool,
    apply_noise: bool,
    noise_strength: f64,
    total_duration: f64,
    progress: &dyn Fn(f64),
) -> Result<String, String> {
    let n = segments.len();
    let mut filter_parts: Vec<String> = Vec::with_capacity(n * 2 + 1);

    for (i, (start, end)) in segments.iter().enumerate() {
        let dur = end - start;

        if input_is_video {
            filter_parts.push(format!(
                "[0:v]trim=start={start}:duration={dur},setpts=PTS-STARTPTS[v{i}]"
            ));
        }

        let mut af = format!("atrim=start={start}:duration={dur},asetpts=PTS-STARTPTS");
        if apply_noise {
            af.push_str(&format!(",afftdn=nr={noise_strength}"));
        }
        filter_parts.push(format!("[0:a]{af}[a{i}]"));
    }

    if input_is_video {
        let labels: String = (0..n).flat_map(|i| [format!("[v{i}]"), format!("[a{i}]")]).collect();
        filter_parts.push(format!("{labels}concat=n={n}:v=1:a=1[outv][outa]"));
    } else {
        let labels: String = (0..n).map(|i| format!("[a{i}]")).collect();
        filter_parts.push(format!("{labels}concat=n={n}:v=0:a=1[outa]"));
    }

    let filter_str = filter_parts.join(";");
    let mut args = vec![
        "-y".to_string(),
        "-i".to_string(), input_path.to_string(),
        "-progress".to_string(), "pipe:1".to_string(),
        "-filter_complex".to_string(), filter_str,
    ];

    if input_is_video {
        args.extend_from_slice(&[
            "-map".into(), "[outv]".into(),
            "-map".into(), "[outa]".into(),
            "-c:v".into(), "libx264".into(),
            "-preset".into(), "fast".into(),
        ]);
        if let Some(br) = get_video_bitrate(input_path) {
            args.extend_from_slice(&["-b:v".into(), br]);
        } else {
            args.extend_from_slice(&["-crf".into(), "18".into()]);
        }
        args.extend_from_slice(&["-c:a".into(), "aac".into()]);
    } else {
        args.extend_from_slice(&["-map".into(), "[outa]".into()]);
    }
    args.push(output_path.to_string());

    let mut child = Command::new(ffmpeg)
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("Errore ffmpeg: {e}"))?;

    crate::CURRENT_FFMPEG_PID.store(child.id(), std::sync::atomic::Ordering::SeqCst);

    if let Some(stdout) = child.stdout.take() {
        for line in BufReader::new(stdout).lines() {
            if let Ok(line) = line {
                if line.starts_with("out_time_us=") {
                    if let Ok(us) = line[12..].trim().parse::<f64>() {
                        let pct = (us / 1_000_000.0 / total_duration.max(1.0)).min(1.0);
                        progress(pct);
                    }
                }
            }
        }
    }

    let status = child.wait().map_err(|e| format!("Errore wait: {e}"))?;
    crate::CURRENT_FFMPEG_PID.store(0, std::sync::atomic::Ordering::SeqCst);
    if !status.success() {
        return Err("Elaborazione interrotta".into());
    }

    progress(1.0);
    Ok(output_path.to_string())
}


