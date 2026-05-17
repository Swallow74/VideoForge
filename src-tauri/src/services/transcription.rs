use std::process::Command;
use crate::services::dependency::DependencyService;

pub fn transcribe(
    audio_path: &str,
    engine: &str,
    model: &str,
    language: Option<&str>,
) -> Result<Vec<videoforge_core::Segment>, String> {
    let script = find_script()?;
    let python = find_python()?;

    let mut cmd = Command::new(&python);
    cmd.args([&script, audio_path, "--engine", engine, "--model", model]);
    if let Some(lang) = language {
        cmd.args(["--language", lang]);
    }

    // macOS Finder PATH minimale — aggiungiamo i path noti
    let path = std::env::var("PATH").unwrap_or_default();
    let home = dirs::home_dir().unwrap_or_default();
    let bin = home.join(".videoforge/bin");
    let extended = format!("{}:{}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", path, bin.display());
    cmd.env("PATH", &extended);
    cmd.env("TQDM_DISABLE", "1");

    let out = cmd.output().map_err(|e| format!("Errore esecuzione Python: {e}"))?;

    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        let trimmed = stderr.trim();
        if trimmed.contains("No module named 'mlx_whisper'") {
            return Err("mlx-whisper non installato. Avvia il setup dall'app".into());
        }
        return Err(trimmed.to_string());
    }

    // Parsing JSON — salta le righe di progresso tqdm
    let stdout = String::from_utf8_lossy(&out.stdout);
    let json_line = stdout.lines().find(|l| l.starts_with('[') || l.starts_with('{'))
        .ok_or("Nessun output JSON valido")?;

    serde_json::from_str::<Vec<videoforge_core::Segment>>(json_line)
        .map_err(|e| format!("Errore parsing JSON: {e}"))
}

fn find_script() -> Result<String, String> {
    let exe_resource = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .map(|p| p.join("../Resources/transcribe_audio.py"));

    let cwd = std::env::current_dir().unwrap_or_default();

    let candidates: [Option<std::path::PathBuf>; 3] = [
        // Runtime: bundle resources dir (macOS .app/Contents/Resources/)
        exe_resource.clone(),
        // Development: resources/ accanto a src-tauri/
        Some(cwd.join("resources/transcribe_audio.py")),
        // Fallback: parent/cwd
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
    // Cerca python3 nel PATH
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
