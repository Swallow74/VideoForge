use std::sync::Arc;
use videoforge_core::Segment;
use crate::services::grammar::GrammarService;

pub struct PipelineService;

impl PipelineService {
    pub async fn process(
        segments: &[Segment],
        text_model: &str,
        api_base_url: &str,
        api_key: &str,
        log: Arc<dyn Fn(&str) + Send + Sync>,
    ) -> Vec<Segment> {
        let segments_owned = segments.to_vec();
        let text_model_owned = text_model.to_string();
        let api_base_url_owned = api_base_url.to_string();
        let api_key_owned = api_key.to_string();
        let log2 = log.clone();

        let merged = tokio::task::spawn_blocking(move || {
            let profile = videoforge_core::detect::detect_profile(&segments_owned);
            log2("[merge] Rilevamento profilo completato");
            videoforge_core::merge::merge_and_group(&segments_owned, &profile)
        })
        .await
        .expect("spawn_blocking for detect/merge failed");

        log(&format!("[merge] Da {} a {} segmenti dopo merge", segments.len(), merged.len()));

        if text_model_owned.is_empty() {
            return merged;
        }

        log("[grammar] Correzione grammaticale in corso...");
        let grammar = GrammarService::new(&api_base_url_owned, &api_key_owned);
        let result = grammar.correct_segments(&merged, &text_model_owned, &*log).await;
        log("[grammar] Correzione completata");
        result
    }
}
