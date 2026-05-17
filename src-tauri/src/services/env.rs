use std::collections::HashMap;
use std::path::PathBuf;

pub struct EnvLoader;

impl EnvLoader {
    fn env_path() -> PathBuf {
        let home = dirs::home_dir().unwrap_or_default();
        home.join(".videoforge/.env")
    }

    pub fn load() -> HashMap<String, String> {
        let path = Self::env_path();
        let content = match std::fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => return HashMap::new(),
        };

        let mut map = HashMap::new();
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if let Some((key, value)) = trimmed.split_once('=') {
                map.insert(key.trim().to_string(), value.trim().to_string());
            }
        }
        map
    }

    pub fn save(key: &str, value: &str) -> bool {
        let path = Self::env_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).ok();
        }

        let mut current = Self::load();
        current.insert(key.to_string(), value.to_string());

        let mut lines: Vec<String> = current
            .into_iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect();
        lines.sort();

        std::fs::write(&path, lines.join("\n")).is_ok()
    }
}
