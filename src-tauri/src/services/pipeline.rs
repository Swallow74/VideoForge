use videoforge_core::Segment;
use crate::services::grammar::GrammarService;

pub struct PipelineService;

impl PipelineService {
    pub async fn process(
        segments: &[Segment],
        text_model: &str,
        api_base_url: &str,
        api_key: &str,
    ) -> Vec<Segment> {
        let segments_owned = segments.to_vec();
        let text_model_owned = text_model.to_string();
        let api_base_url_owned = api_base_url.to_string();
        let api_key_owned = api_key.to_string();

        let (profile, merged) = tokio::task::spawn_blocking(move || {
            let profile = videoforge_core::detect::detect_profile(&segments_owned);
            let merged = videoforge_core::merge::merge_and_group(&segments_owned, &profile);
            (profile, merged)
        })
        .await
        .expect("spawn_blocking for detect/merge failed");

        if text_model_owned.is_empty() {
            return merged;
        }

        let grammar = GrammarService::new(&api_base_url_owned, &api_key_owned);
        grammar.correct_segments(&merged, &text_model_owned, &profile).await
    }
}
