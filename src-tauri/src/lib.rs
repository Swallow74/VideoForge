pub mod services;

use services::audio;
use services::dependency::DependencyService;
use services::env::EnvLoader;
use services::grammar::GrammarService;
use services::pipeline::PipelineService;
use services::transcription;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::{DragDropEvent, Emitter, State, WindowEvent};

// ── App State ──────────────────────────────────────────

struct AppState {
    files: Mutex<Vec<String>>,
    log: Mutex<String>,
}

#[derive(Serialize, Deserialize)]
pub struct TranscriptionResult {
    segments: Vec<videoforge_core::Segment>,
}

// ── Commands ──────────────────────────────────────────

// Fast sync commands (no I/O, no CPU-heavy work)

#[tauri::command]
fn add_file(state: State<AppState>, path: String) {
    let mut files = state.files.lock().unwrap();
    if !files.contains(&path) {
        files.push(path);
    }
}

#[tauri::command]
fn remove_file(state: State<AppState>, index: usize) {
    let mut files = state.files.lock().unwrap();
    if index < files.len() {
        files.remove(index);
    }
}

#[tauri::command]
fn clear_files(state: State<AppState>) {
    state.files.lock().unwrap().clear();
}

#[tauri::command]
fn get_files(state: State<AppState>) -> Vec<String> {
    state.files.lock().unwrap().clone()
}

#[tauri::command]
fn is_audio_file(path: &str) -> bool {
    audio::is_audio_file(path)
}

#[tauri::command]
fn check_venv() -> bool {
    DependencyService::check_venv()
}

#[tauri::command]
fn find_python() -> Result<String, String> {
    Err("Usa setup_venv prima".into())
}

#[tauri::command]
fn load_env() -> std::collections::HashMap<String, String> {
    EnvLoader::load()
}

#[tauri::command]
fn save_env(key: &str, value: &str) -> bool {
    EnvLoader::save(key, value)
}

#[tauri::command]
fn export_srt(segments: Vec<videoforge_core::Segment>, output_path: &str) -> Result<(), String> {
    videoforge_core::srt::export_srt(&segments, output_path)
}

#[tauri::command]
fn detect_profile(segments: Vec<videoforge_core::Segment>) -> String {
    let p = videoforge_core::detect::detect_profile(&segments);
    serde_json::to_string(&p).unwrap_or_default()
}

// Async commands (I/O-bound: subprocess, HTTP)

#[tauri::command]
async fn get_duration(path: String) -> f64 {
    tokio::task::spawn_blocking(move || audio::get_duration(&path))
        .await
        .unwrap_or(0.0)
}

#[tauri::command]
async fn extract_audio(video_path: String) -> Result<String, String> {
    let out = video_path
        .replace(".mp4", "_audio.wav")
        .replace(".mov", "_audio.wav")
        .replace(".mkv", "_audio.wav");
    let out_clone = out.clone();
    tokio::task::spawn_blocking(move || {
        audio::extract_audio(&video_path, &out_clone)?;
        Ok(out)
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

#[tauri::command]
async fn setup_venv() -> Result<(), String> {
    tokio::task::spawn_blocking(DependencyService::setup_venv)
        .await
        .map_err(|e| format!("Task join error: {e}"))?
}

#[tauri::command]
async fn list_models(api_base_url: String, api_key: String) -> Vec<String> {
    let g = GrammarService::new(&api_base_url, &api_key);
    g.list_models().await
}

#[tauri::command]
async fn transcribe(
    audio_path: String,
    engine: String,
    model: String,
    language: Option<String>,
) -> Result<Vec<videoforge_core::Segment>, String> {
    tokio::task::spawn_blocking(move || {
        transcription::transcribe(&audio_path, &engine, &model, language.as_deref())
    })
    .await
    .map_err(|e| format!("Task join error: {e}"))?
}

#[tauri::command]
async fn correct_segments(
    segments: Vec<videoforge_core::Segment>,
    model: String,
    api_base_url: String,
    api_key: String,
    _profile: String,
) -> Vec<videoforge_core::Segment> {
    let g = GrammarService::new(&api_base_url, &api_key);
    g.correct_segments(&segments, &model).await
}

#[tauri::command]
async fn process_pipeline(
    segments: Vec<videoforge_core::Segment>,
    text_model: String,
    api_base_url: String,
    api_key: String,
) -> Vec<videoforge_core::Segment> {
    PipelineService::process(&segments, &text_model, &api_base_url, &api_key).await
}

// ── App Entry ──────────────────────────────────────────

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .manage(AppState {
            files: Mutex::new(Vec::new()),
            log: Mutex::new(String::new()),
        })
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            app.handle().plugin(tauri_plugin_dialog::init())?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::DragDrop(drag) = event {
                match drag {
                    DragDropEvent::Enter { paths, .. } => { window.emit("f-drop-hover", paths.iter().map(|p| p.to_string_lossy().into_owned()).collect::<Vec<_>>()).ok(); }
                    DragDropEvent::Over { .. } => { window.emit("f-drop-hover", Vec::<String>::new()).ok(); }
                    DragDropEvent::Drop { paths, .. } => { window.emit("f-drop", paths.iter().map(|p| p.to_string_lossy().into_owned()).collect::<Vec<_>>()).ok(); }
                    DragDropEvent::Leave => { window.emit("f-drop-leave", ()).ok(); }
                    _ => {}
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            add_file,
            remove_file,
            clear_files,
            get_files,
            is_audio_file,
            get_duration,
            extract_audio,
            check_venv,
            setup_venv,
            find_python,
            load_env,
            save_env,
            list_models,
            transcribe,
            correct_segments,
            process_pipeline,
            export_srt,
            detect_profile,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
