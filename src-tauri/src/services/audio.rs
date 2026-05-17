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

pub fn is_audio_file(path: &str) -> bool {
    let ext = match Path::new(path).extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return false,
    };
    matches!(ext.as_str(), "mp3" | "wav" | "m4a" | "aac" | "ogg" | "flac")
}

pub fn extract_audio(video_path: &str, output_path: &str) -> Result<String, String> {
    let ffmpeg = find_in_path("ffmpeg").unwrap_or_else(|| "ffmpeg".to_string());

    let mut child = Command::new(&ffmpeg)
        .args([
            "-y", "-i", video_path,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            output_path,
        ])
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|e| format!("Errore ffmpeg: {e}"))?;

    crate::CURRENT_FFMPEG_PID.store(child.id(), std::sync::atomic::Ordering::SeqCst);

    let status = child.wait().map_err(|e| format!("Errore wait: {e}"))?;
    crate::CURRENT_FFMPEG_PID.store(0, std::sync::atomic::Ordering::SeqCst);

    if !status.success() {
        return Err("Elaborazione interrotta".into());
    }
    Ok(output_path.to_string())
}

pub fn get_duration(path: &str) -> f64 {
    let ffprobe = find_in_path("ffprobe").unwrap_or_else(|| "ffprobe".to_string());

    let out = match Command::new(&ffprobe)
        .args(["-v", "quiet", "-print_format", "json", "-show_format", path])
        .output()
    {
        Ok(o) => o,
        Err(_) => return 0.0,
    };

    let json: serde_json::Value = match serde_json::from_slice(&out.stdout) {
        Ok(v) => v,
        Err(_) => return 0.0,
    };
    match json["format"]["duration"].as_str() {
        Some(dur) => dur.parse::<f64>().unwrap_or(0.0),
        None => 0.0,
    }
}
