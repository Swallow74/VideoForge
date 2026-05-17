# VideoForge

AI-powered video transcription and processing workstation built with [Tauri 2](https://v2.tauri.app/), React 19, and Rust.

## Features

- **AI Transcription** — Whisper (large-v3/v2, medium, small, base, tiny) or Qwen3-ASR
- **Grammar Correction** — LLM-based text refinement with configurable profiles (conversational, lecturing, technical)
- **Subtitle Export** — SRT output with optional bilingual subtitles
- **Audio Processing** — Silence removal, noise reduction
- **Video Processing** — Portrait 9:16 crop, picture-in-picture overlay, background music with auto-ducking
- **Drag & Drop** — Native file drop support with visual feedback
- **Pipeline Automation** — One-click full pipeline from file to subtitles

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Desktop Shell | [Tauri 2](https://v2.tauri.app/) |
| Frontend | React 19 + TypeScript + Vite |
| Backend | Rust (Tauri commands, async services) |
| Core Library | `videoforge-core` (segment model, SRT export, profile detection) |
| ASR Engines | Whisper (local Python), Qwen3-ASR |
| LLM Grammar | Compatible with OpenAI / vLLM / llama.cpp endpoints |

## Prerequisites

- [Rust](https://rustup.rs/) (edition 2021, MSRV 1.77.2)
- [Node.js](https://nodejs.org/) 18+
- Python 3.10+ (for local Whisper transcription)
- FFmpeg (for audio extraction and video processing)

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

Build artifacts are written to `src-tauri/target/release/`.

## Configuration

API endpoints and keys are persisted locally via `EnvLoader`. Configure these in the app UI:
- **API URL** — LLM endpoint (e.g. `http://127.0.0.1:8000` for vLLM)
- **API Key** — Optional API key for the LLM endpoint

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
│   │   └── services/     # Audio, transcription, grammar, pipeline
│   └── tauri.conf.json   # Tauri configuration
├── crates/
│   └── videoforge-core/  # Shared Rust library (segments, SRT, profiles)
├── resources/            # Bundled assets
│   └── transcribe_audio.py  # Python transcription script
└── package.json
```

## License

[MIT](LICENSE)
