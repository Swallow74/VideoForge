use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::RwLock;

pub struct CorrectionCache {
    cache_dir: PathBuf,
    mem_cache: RwLock<HashMap<String, String>>,
}

impl CorrectionCache {
    pub fn new(cache_dir: Option<PathBuf>) -> Self {
        let dir = cache_dir.unwrap_or_else(|| {
            let home = dirs::home_dir().unwrap_or_default();
            home.join(".cache/correzioni")
        });
        std::fs::create_dir_all(&dir).ok();
        Self {
            cache_dir: dir,
            mem_cache: RwLock::new(HashMap::new()),
        }
    }

    fn hash(&self, text: &str) -> String {
        let hash = blake3::hash(text.as_bytes());
        hash.to_hex()[..32].to_string()
    }

    pub fn get(&self, text: &str) -> Option<String> {
        if let Some(cached) = self.mem_cache.read().ok()?.get(text).cloned() {
            return Some(cached);
        }
        let h = self.hash(text);
        let path = self.cache_dir.join(format!("{h}.txt"));
        if let Ok(val) = std::fs::read_to_string(&path) {
            let trimmed = val.trim().to_string();
            if let Ok(mut mem) = self.mem_cache.write() {
                mem.insert(text.to_string(), trimmed.clone());
            }
            Some(trimmed)
        } else {
            None
        }
    }

    pub fn set(&self, original: &str, corrected: &str) {
        if original == corrected {
            return;
        }
        if let Ok(mut mem) = self.mem_cache.write() {
            mem.insert(original.to_string(), corrected.to_string());
        }
        let h = self.hash(original);
        let path = self.cache_dir.join(format!("{h}.txt"));
        std::fs::write(&path, corrected.trim()).ok();
    }

    pub fn get_or_correct(&self, text: &str, correct_fn: impl Fn(&str) -> String) -> String {
        if let Some(cached) = self.get(text) {
            return cached;
        }
        let corrected = correct_fn(text);
        self.set(text, &corrected);
        corrected
    }

    pub fn clear(&self) {
        if let Ok(mut mem) = self.mem_cache.write() {
            mem.clear();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_store_and_retrieve() {
        let cache = CorrectionCache::new(None);
        cache.set("hello", "world");
        assert_eq!(cache.get("hello"), Some("world".to_string()));
    }

    #[test]
    fn test_cache_returns_nil_for_missing() {
        let cache = CorrectionCache::new(None);
        assert_eq!(cache.get("missing"), None);
    }

    #[test]
    fn test_cache_skips_identical() {
        let cache = CorrectionCache::new(None);
        cache.set("same", "same");
        assert_eq!(cache.get("same"), None);
    }

    #[test]
    fn test_cache_get_or_correct() {
        let cache = CorrectionCache::new(None);
        let result = cache.get_or_correct("test", |s| s.to_uppercase());
        assert_eq!(result, "TEST");
    }

    #[test]
    fn test_cache_persistence() {
        let dir = std::env::temp_dir().join("test_cache_persist");
        std::fs::create_dir_all(&dir).ok();
        {
            let cache = CorrectionCache::new(Some(dir.clone()));
            cache.set("ciao", "hello");
        }
        let cache2 = CorrectionCache::new(Some(dir.clone()));
        assert_eq!(cache2.get("ciao"), Some("hello".to_string()));
        std::fs::remove_dir_all(&dir).ok();
    }
}
