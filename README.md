# VideoForge

AI-powered video transcription and processing workstation built with [Tauri 2](https://v2.tauri.app/), React 19, and Rust.

## Features

- **AI Transcription** — Whisper (large-v3/v2, medium, small, base, tiny) or Qwen3-ASR (0.6B/1.7B, 4-bit quantized)
- **Grammar Correction** — LLM-based text refinement with configurable profiles (conversational, lecturing, technical)
- **Subtitle Export** — SRT output with optional bilingual subtitles
- **Audio Processing** — Silence removal, noise reduction, audio cleanup
- **Video Processing** — Portrait 9:16 crop, picture-in-picture overlay, background music with auto-ducking
- **Drag & Drop** — Native file drop support with visual feedback
- **Pipeline Automation** — One-click full pipeline from file to subtitles
- **Real-time Logging** — Live progress and log output in the app UI
- **Stop Processing** — Cancel running operations (transcription, FFmpeg) at any time
- **Multi-engine ASR** — Switch between Whisper and Qwen3-ASR engines with automatic model download

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Desktop Shell | [Tauri 2](https://v2.tauri.app/) (macOS native) |
| Frontend | React 19 + TypeScript + Vite |
| Backend | Rust (Tauri commands, async services, tokio) |
| Core Library | `videoforge-core` (segment model, SRT export, profile detection) |
| ASR Engines | Whisper via [mlx-whisper](https://github.com/ml-explore/mlx-whisper) (Apple Silicon), Qwen3-ASR via [mlx-qwen3-asr](https://github.com/BobDu/MLX-Qwen3-ASR) |
| LLM Grammar | Compatible with OpenAI / vLLM / llama.cpp / Ollama endpoints |

## Prerequisites

- macOS (Apple Silicon recommended for MLX acceleration)
- [Rust](https://rustup.rs/) (edition 2021, MSRV 1.77.2)
- [Node.js](https://nodejs.org/) 18+
- Python 3.10+ (for local ASR transcription — venv auto-setup on first run)
- FFmpeg (auto-downloaded on first run if missing)

## Development

```bash
# Install JS dependencies
npm install

# Run in dev mode (Vite + Tauri)
npm run tauri dev
```

## Build

```bash
# Production build
npm run tauri build
```

Build artifacts are written to `src-tauri/target/release/bundle/`.

## Configuration

API endpoints and keys are persisted locally via `EnvLoader` (`.env` file). Configure these in the app UI:
- **API URL** — LLM endpoint (e.g. `http://127.0.0.1:8000` for vLLM, `http://localhost:11434` for Ollama)
- **API Key** — Optional API key for the LLM endpoint

## ASR Models

| Engine | Models | Size (disk) |
|--------|--------|-------------|
| Whisper | large-v3, large-v2, medium, small, base, tiny | ~0.1–3 GB |
| Qwen3-ASR 0.6B | 4-bit quantized | ~0.6 GB |
| Qwen3-ASR 1.7B | 4-bit quantized | ~1.6 GB |

Models are downloaded from HuggingFace Hub on first use and cached locally.

## Project Structure

```
videoforge/
├── src/                  # React frontend
│   ├── App.tsx           # Main app component
│   ├── App.css           # Styles
│   └── main.tsx          # Entry point
├── src-tauri/            # Rust backend
│   ├── src/
│   │   ├── lib.rs        # Tauri commands & app setup
│   │   ├── main.rs       # Entry point
│   │   └── services/     # Audio, transcription, grammar, pipeline, video
│   └── tauri.conf.json   # Tauri configuration
├── crates/
│   └── videoforge-core/  # Shared Rust library (segments, SRT, profiles)
├── resources/            # Bundled assets
│   └── transcribe_audio.py  # Python transcription bridge (Whisper + Qwen3-ASR)
└── package.json
```

## License

[MIT](LICENSE)
