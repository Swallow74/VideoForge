use videoforge_core::{BoundaryContext, VideoProfile, normalize, CorrectionCache};

static SYSTEM_PROMPT: &str = "Sei un correttore ortografico automatico per sottotitoli video italiani. \
INPUT: una frase breve, possibilmente con errori di battitura, \
accordo grammaticale o trascrizione automatica. \
OUTPUT: restituisci SOLO la frase corretta, senza spiegazioni, senza virgolette, \
senza prefissi come Correzione:, senza aggiungere frasi nuove, \
senza completare pensieri lasciati volutamente incompleti. \
NON aggiungere parole a meno che non siano strettamente necessarie per la grammatica. \
NON togliere parole. NON cambiare il significato. NON punteggiare alla fine. \
Se la frase è già corretta, restituiscila identica.";

pub struct GrammarService {
    base_url: String,
    api_key: String,
    cache: CorrectionCache,
}

impl GrammarService {
    pub fn new(base_url: &str, api_key: &str) -> Self {
        Self {
            base_url: base_url.trim_end_matches('/').to_string(),
            api_key: if api_key.is_empty() {
                crate::services::env::EnvLoader::load()
                    .get("API_KEY")
                    .cloned()
                    .unwrap_or_default()
            } else {
                api_key.to_string()
            },
            cache: CorrectionCache::new(None),
        }
    }

    pub async fn list_models(&self) -> Vec<String> {
        let url = format!("{}/v1/models", self.base_url);
        let client = reqwest::Client::new();
        let resp = client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .send()
            .await;

        let json: serde_json::Value = match resp {
            Ok(r) => match r.json().await {
                Ok(v) => v,
                Err(_) => return vec![],
            },
            Err(_) => return vec![],
        };

        json["data"]
            .as_array()
            .map(|arr| {
                arr.iter()
                    .filter_map(|m| m["id"].as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
    }

    pub async fn correct_segments(
        &self,
        segments: &[videoforge_core::Segment],
        model: &str,
        profile: &VideoProfile,
    ) -> Vec<videoforge_core::Segment> {
        let mut result = Vec::new();
        let batch_size = 5;

        for chunk in segments.chunks(batch_size) {
            let corrected = self.correct_batch(chunk, model).await;
            result.extend(corrected);
        }

        let ctx = BoundaryContext::default();
        for seg in result.iter_mut() {
            // fix_punct_local su ogni segmento
            let next_text = String::new(); // semplificato, in produzione è più complesso
            let fixed = normalize::fix_punct_local(&seg.text, &next_text, 1.0, profile, Some(&ctx));
            seg.text = fixed;
        }

        result
    }

    async fn correct_batch(&self, segments: &[videoforge_core::Segment], model: &str) -> Vec<videoforge_core::Segment> {
        let mut result = segments.to_vec();

        for i in 0..result.len() {
            let text = result[i].text.clone();
            if !normalize::needs_qwen(&text) {
                result[i].text = normalize::normalize_text(&text);
                continue;
            }

            // Check cache
            if let Some(cached) = self.cache.get(&text) {
                result[i].text = cached;
                continue;
            }

            // Chiamata API
            if let Some(corrected) = self.correct_text(&text, model).await {
                let validated = validate_output(&corrected, &text);
                if !validated.is_empty() {
                    self.cache.set(&text, &validated);
                    result[i].text = validated;
                }
            }
        }

        result
    }

    async fn correct_text(&self, text: &str, model: &str) -> Option<String> {
        let url = format!("{}/v1/chat/completions", self.base_url);
        let client = reqwest::Client::new();

        let body = serde_json::json!({
            "model": model,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": text}
            ],
            "temperature": 0.0,
            "max_tokens": text.len() * 3 + 30,
        });

        let resp = client
            .post(&url)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .ok()?;

        let json: serde_json::Value = resp.json().await.ok()?;
        let content = json["choices"][0]["message"]["content"].as_str()?;
        Some(content.trim().to_string())
    }
}

fn validate_output(output: &str, original: &str) -> String {
    let mut stripped = output.trim().to_string();
    stripped = stripped.trim_matches(|c: char| c == '"' || c == '\'').to_string();

    let words_out = stripped.split_whitespace().count();
    let words_in = original.split_whitespace().count();

    if words_out > words_in * 2 {
        return String::new();
    }

    if stripped.contains('\n') || stripped.contains('→')
        || stripped.contains("Correzione") || stripped.contains("Nota")
        || stripped.contains("**")
    {
        return stripped.lines().next().unwrap_or("").to_string();
    }

    if stripped.contains(':') && stripped.split_whitespace().count() < 6 {
        return stripped.split(':').last().unwrap_or("").trim().to_string();
    }

    stripped
}
