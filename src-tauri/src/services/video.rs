use std::io::{BufRead, BufReader};
use std::path::Path;
use std::process::{Command, Stdio};

pub type ProgressFn = Box<dyn Fn(f64) + Send + 'static>;

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

fn crop_expr(position: &str) -> &'static str {
    match position {
        "Top" => "crop=ih*9/16:ih:0:0",
        "Bottom" => "crop=ih*9/16:ih:iw-ih*9/16:0",
        _ => "crop=ih*9/16:ih",
    }
}

fn overlay_pos_expr(pos: &str) -> &'static str {
    match pos {
        "Top Left" => "10:10",
        "Top Right" => "main_w-overlay_w-10:10",
        "Bottom Left" => "10:main_h-overlay_h-10",
        _ => "main_w-overlay_w-10:main_h-overlay_h-10",
    }
}

pub fn process_video(
    input_path: &str,
    output_path: &str,
    portrait_crop: bool,
    crop_position: &str,
    blur_bg: bool,
    overlay_path: Option<&str>,
    overlay_position: &str,
    overlay_scale: f64,
    music_path: Option<&str>,
    music_volume: f64,
    music_duck: f64,
    total_duration: f64,
    progress: ProgressFn,
) -> Result<String, String> {
    let ffmpeg = find_in_path("ffmpeg").unwrap_or_else(|| "ffmpeg".to_string());

    let mut inputs = vec![input_path.to_string()];
    let mut filter_chains: Vec<String> = Vec::new();
    let mut has_complex = false;
    let mut has_video_filter = false;
    let mut has_audio_filter = false;

    let mut stage = 0usize;
    let mut video_label: Option<String> = None;
    let mut audio_label: Option<String> = None;

    // Portrait mode
    if portrait_crop {
        has_complex = true;
        has_video_filter = true;
        let vout = format!("v{stage}");
        stage += 1;

        if blur_bg {
            filter_chains.push(format!(
                "[0:v]scale=1080:1920:force_original_aspect_ratio=2,crop=1080:1920,boxblur=20:10[bg]"
            ));
            filter_chains.push(format!(
                "[0:v]{c},scale=1080:1920[fg]",
                c = crop_expr(crop_position)
            ));
            filter_chains.push(format!(
                "[bg][fg]overlay=(main_w-overlay_w)/2:(main_h-overlay_h)/2[{vout}]"
            ));
        } else {
            filter_chains.push(format!(
                "[0:v]{c},scale=1080:1920[{vout}]",
                c = crop_expr(crop_position)
            ));
        }
        video_label = Some(vout);
    }

    // Overlay PIP
    if let Some(pip_path) = overlay_path {
        inputs.push(pip_path.to_string());
        let pip_idx = inputs.len() - 1;
        has_complex = true;
        has_video_filter = true;
        let vout = format!("v{stage}");
        stage += 1;

        let src = video_label.as_deref().unwrap_or("0:v");
        let pos = overlay_pos_expr(overlay_position);
        let scale = overlay_scale;

        filter_chains.push(format!(
            "[{pip_idx}:v]scale=iw*{scale}:ih*{scale}[pip]"
        ));
        filter_chains.push(format!(
            "[{src}][pip]overlay={pos}[{vout}]"
        ));
        video_label = Some(vout);
    }

    // Music + ducking
    if let Some(music_path) = music_path {
        inputs.push(music_path.to_string());
        let music_idx = inputs.len() - 1;
        has_complex = true;
        has_audio_filter = true;
        let aout = format!("a{stage}");

        filter_chains.push(format!(
            "[{music_idx}:a]volume={music_volume}[music]"
        ));
        filter_chains.push(format!(
            "[0:a][music]amix=inputs=2:duration=first:weights=1 {duck}[{aout}]",
            duck = 1.0 - music_duck
        ));
        audio_label = Some(aout);
    }

    let mut args = vec!["-y".to_string(), "-progress".to_string(), "pipe:1".to_string()];
    for inp in &inputs {
        args.push("-i".to_string());
        args.push(inp.clone());
    }

    if has_complex {
        args.push("-filter_complex".to_string());
        args.push(filter_chains.join(";"));

        if has_video_filter {
            args.push("-map".to_string());
            args.push(format!("[{}]", video_label.as_ref().unwrap()));
        } else {
            args.push("-map".to_string());
            args.push("0:v".to_string());
        }

        if has_audio_filter {
            args.push("-map".to_string());
            args.push(format!("[{}]", audio_label.as_ref().unwrap()));
        } else {
            args.push("-map".to_string());
            args.push("0:a".to_string());
        }
    } else {
        args.push("-map".to_string());
        args.push("0:v".to_string());
        args.push("-map".to_string());
        args.push("0:a".to_string());
    }

    if has_video_filter {
        args.push("-c:v".to_string());
        args.push("libx264".to_string());
    } else {
        args.push("-c:v".to_string());
        args.push("copy".to_string());
    }

    args.push("-c:a".to_string());
    args.push("aac".to_string());
    args.push(output_path.to_string());

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
    Ok(output_path.to_string())
}
