use videoforge_core::CorrectionCache;

static SYSTEM_PROMPT: &str = "Sei un correttore ortografico e di punteggiatura per sottotitoli video italiani.

Regole:
- Correggi errori di battitura, ortografia e accordo grammaticale.
- Aggiungi la punteggiatura mancante (punti, virgole, punti interrogativi).
- Se la frase termina, metti un punto. Se è una domanda, metti il punto interrogativo.
- Capitalizza la prima lettera della frase.
- Non spezzare le parole. Non dividere frasi. Non togliere pezzi di frase.
- Non parafrasare e non cambiare lo stile o il registro originale.
- Se la frase è già corretta e ben punteggiata, restituiscila identica.
- Restituisci SOLO il testo corretto, senza prefissi, spiegazioni o virgolette.";

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
    ) -> Vec<videoforge_core::Segment> {
        self.correct_batch(segments, model).await
    }

    async fn correct_batch(&self, segments: &[videoforge_core::Segment], model: &str) -> Vec<videoforge_core::Segment> {
        let mut result = segments.to_vec();

        for i in 0..result.len() {
            let text = result[i].text.clone();

            if let Some(cached) = self.cache.get(&text) {
                result[i].text = cached;
                continue;
            }

            let prev = if i > 0 { &result[i - 1].text } else { "" };
            let next = result.get(i + 1).map(|s| s.text.as_str()).unwrap_or("");

            if let Some(corrected) = self.correct_text_with_context(&text, prev, next, model).await {
                let validated = validate_output(&corrected, &text);
                if !validated.is_empty() {
                    self.cache.set(&text, &validated);
                    result[i].text = validated;
                }
            }
        }

        result
    }

    async fn correct_text_with_context(&self, text: &str, prev: &str, next: &str, model: &str) -> Option<String> {
        let url = format!("{}/v1/chat/completions", self.base_url);
        let client = reqwest::Client::new();

        let mut messages = vec![
            serde_json::json!({"role": "system", "content": SYSTEM_PROMPT}),
        ];

        if !prev.is_empty() {
            messages.push(serde_json::json!({"role": "user", "content": format!("FRASE PRECEDENTE: {}", prev)}));
            messages.push(serde_json::json!({"role": "assistant", "content": "OK."}));
        }

        messages.push(serde_json::json!({"role": "user", "content": format!("CORREGGI: {}", text)}));

        if !next.is_empty() {
            messages.push(serde_json::json!({"role": "user", "content": format!("(dopo continua con: {})", next)}));
        }

        let body = serde_json::json!({
            "model": model,
            "messages": messages,
            "temperature": 0.0,
            "max_tokens": text.len() * 3 + 50,
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
    let stripped = output.trim()
        .trim_matches(|c: char| c == '"' || c == '\'')
        .to_string();

    let words_out = stripped.split_whitespace().count();
    let words_in = original.split_whitespace().count();

    if words_out < words_in / 3 || words_out > words_in * 2 {
        return original.to_string();
    }

    if stripped.contains('\n') || stripped.contains("Correzione") || stripped.contains("Nota") || stripped.contains("**") {
        return original.to_string();
    }

    stripped
}
