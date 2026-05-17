use std::io::BufRead;
use std::process::{Command, Stdio};
use std::sync::Arc;
use crate::services::dependency::DependencyService;

pub fn transcribe(
    audio_path: &str,
    engine: &str,
    model: &str,
    language: Option<&str>,
    log: Arc<dyn Fn(&str) + Send + Sync>,
) -> Result<Vec<videoforge_core::Segment>, String> {
    let script = find_script()?;
    let python = find_python()?;

    let mut cmd = Command::new(&python);
    cmd.args([&script, audio_path, "--engine", engine, "--model", model]);
    if let Some(lang) = language {
        cmd.args(["--language", lang]);
    }

    let path = std::env::var("PATH").unwrap_or_default();
    let home = dirs::home_dir().unwrap_or_default();
    let bin = home.join(".videoforge/bin");
    let extended = format!("{}:{}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", path, bin.display());
    cmd.env("PATH", &extended);

    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = cmd.spawn().map_err(|e| format!("Errore esecuzione Python: {e}"))?;

    let stderr_handle = {
        let stderr = child.stderr.take().unwrap();
        let log = log.clone();
        std::thread::spawn(move || {
            let reader = std::io::BufReader::new(stderr);
            for line in reader.lines() {
                let line = match line {
                    Ok(l) => l,
                    Err(_) => break,
                };
                if line.is_empty() {
                    continue;
                }
                if line.starts_with("MODEL_DOWNLOAD:") {
                    if let Some(msg_start) = line.find('|') {
                        log(&format!("📥 {}", &line[msg_start+1..]));
                    }
                } else if line.starts_with("DOWNLOAD_PROGRESS:") {
                    if let Some(msg_start) = line.find('|') {
                        log(&format!("📦 {}", &line[msg_start+1..]));
                    }
                } else if line.starts_with("ERROR:") {
                    log(&format!("❌ {}", line));
                } else if !line.starts_with("[林聲]") {
                    log(&format!("  {}", line));
                }
            }
        })
    };

    let output = child.wait_with_output().map_err(|e| format!("Errore attesa Python: {e}"))?;
    stderr_handle.join().ok();

    if !output.status.success() {
        return Err("Trascrizione fallita".into());
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let json_line = stdout.lines().find(|l| l.starts_with('[') || l.starts_with('{'))
        .ok_or("Nessun output JSON valido")?;

    let segments: Vec<videoforge_core::Segment> = serde_json::from_str(json_line)
        .map_err(|e| format!("Errore parsing JSON: {e}"))?;

    log(&format!("✓ Trascrizione completata: {} segmenti", segments.len()));

    Ok(segments)
}

fn find_script() -> Result<String, String> {
    let exe_resource = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .map(|p| p.join("../Resources/transcribe_audio.py"));

    let cwd = std::env::current_dir().unwrap_or_default();

    let candidates: [Option<std::path::PathBuf>; 3] = [
        exe_resource.clone(),
        Some(cwd.join("resources/transcribe_audio.py")),
        Some(cwd.join("../resources/transcribe_audio.py")),
    ];

    for path in candidates.iter().flatten() {
        if path.is_file() {
            return Ok(path.to_string_lossy().into_owned());
        }
    }
    Err(format!("Script non trovato. CWD={}", cwd.display()))
}

fn find_python() -> Result<String, String> {
    let venv = DependencyService::venv_python();
    if venv.is_file() {
        return Ok(venv.to_str().unwrap().to_string());
    }
    if let Some(p) = std::env::var("PATH").ok().and_then(|path| {
        for dir in path.split(':') {
            let candidate = format!("{}/python3", dir);
            if std::path::Path::new(&candidate).is_file() {
                return Some(candidate);
            }
        }
        None
    }) {
        return Ok(p);
    }
    Err("Python 3 non trovato nel PATH".into())
}
