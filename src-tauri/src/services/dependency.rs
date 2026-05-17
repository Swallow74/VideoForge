use std::path::PathBuf;
use std::process::Command;

pub struct DependencyService;

impl DependencyService {
    pub fn venv_path() -> PathBuf {
        let home = dirs::home_dir().unwrap_or_default();
        home.join(".videoforge/venv")
    }

    pub fn venv_python() -> PathBuf {
        Self::venv_path().join("bin/python3")
    }

    pub fn bin_path() -> PathBuf {
        let home = dirs::home_dir().unwrap_or_default();
        home.join(".videoforge/bin")
    }

    pub fn local_ffmpeg() -> PathBuf {
        Self::bin_path().join("ffmpeg")
    }

    fn find_in_path(name: &str) -> Option<String> {
        std::env::var("PATH").ok().and_then(|path| {
            for dir in path.split(':') {
                let candidate = format!("{}/{}", dir, name);
                if std::path::Path::new(&candidate).is_file() {
                    return Some(candidate);
                }
            }
            None
        })
    }

    fn system_python() -> Option<String> {
        Self::find_in_path("python3")
    }

    pub fn find_ffmpeg() -> Option<String> {
        let local = Self::local_ffmpeg();
        if local.is_file() {
            return Some(local.to_str().unwrap().to_string());
        }
        Self::find_in_path("ffmpeg")
    }

    /// Verifica che il venv esista e mlx-whisper sia installato.
    pub fn check_venv() -> bool {
        let py = Self::venv_python();
        if !py.is_file() {
            return false;
        }
        let out = Command::new(&py)
            .args(["-c", "import mlx_whisper"])
            .output();
        matches!(out, Ok(o) if o.status.success())
    }

    pub fn setup_venv() -> Result<(), String> {
        let venv = Self::venv_path();
        let base = venv.parent().unwrap();
        std::fs::create_dir_all(base).map_err(|e| format!("{e}"))?;

        // Trova Python
        let python = Self::system_python().ok_or("Python 3 non trovato. Installa con: brew install python@3.12")?;

        // Assicura ffmpeg
        Self::ensure_ffmpeg()?;

        // Crea venv
        let status = Command::new(&python)
            .args(["-m", "venv", Self::venv_path().to_str().unwrap()])
            .status()
            .map_err(|e| format!("{e}"))?;
        if !status.success() {
            return Err("Creazione venv fallita".into());
        }

        let pip = Self::venv_python();

        // Upgrade pip
        Command::new(&pip).args(["-m", "pip", "install", "--upgrade", "pip"]).status().ok();

        // Installa mlx-whisper
        let status = Command::new(&pip)
            .args(["-m", "pip", "install", "mlx-whisper"])
            .status()
            .map_err(|e| format!("{e}"))?;

        if !status.success() {
            return Err("Installazione mlx-whisper fallita".into());
        }

        // Installa mlx-qwen3-asr (opzionale per i modelli Qwen3)
        Command::new(&pip).args(["-m", "pip", "install", "mlx-qwen3-asr"]).status().ok();

        Ok(())
    }

    fn ensure_ffmpeg() -> Result<(), String> {
        if Self::find_ffmpeg().is_some() {
            return Ok(());
        }

        let bin = Self::bin_path();
        std::fs::create_dir_all(&bin).map_err(|e| format!("{e}"))?;

        // Download ffmpeg statico
        let url = "https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip";
        let zip_path = bin.join("ffmpeg.zip");

        let resp = reqwest::blocking::get(url).map_err(|e| format!("Download ffmpeg fallito: {e}"))?;
        let bytes = resp.bytes().map_err(|e| format!("{e}"))?;
        std::fs::write(&zip_path, &bytes).map_err(|e| format!("{e}"))?;

        // Decompatta
        let status = Command::new("unzip")
            .args(["-o", zip_path.to_str().unwrap(), "-d", bin.to_str().unwrap()])
            .status()
            .map_err(|e| format!("{e}"))?;
        if !status.success() {
            return Err("Decompressione ffmpeg fallita".into());
        }
        std::fs::remove_file(&zip_path).ok();

        let ffmpeg = Self::local_ffmpeg();
        if !ffmpeg.is_file() {
            return Err("Download ffmpeg fallito".into());
        }
        Ok(())
    }
}
