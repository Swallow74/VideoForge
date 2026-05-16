# VideoForge

**The all-in-one AI video workstation for macOS.**  
Transcribe, clean, resize, subtitle, and publish — 100% offline.

> Trascrizione AI → SRT | Rimozione silenzi | Portrait 9:16 | Musica + Ducking | Overlay PIP | SRT bilingue | Teleprompter

---

## Features

| Module | What it does |
|--------|-------------|
| **🎙 AI Transcription** | Whisper large-v3 via `mlx-whisper` (Apple Silicon native). Word-level timestamps |
| **✂️ Silence Removal** | Auto-cut silences with configurable threshold |
| **🔇 Noise Removal** | Background noise filter (anlmdn + highpass) |
| **📱 Portrait Box** | Auto-crop 16:9 → 9:16 for Shorts/Reels |
| **🎵 Music + Ducking** | Background music with sidechain compression |
| **🌐 Dual Subtitles** | Bilingual SRT/VTT (IT + EN, etc.) |
| **🖼️ Overlay (PIP)** | Webcam / screen overlay compositing |
| **📜 Teleprompter** | Scrolling script with speed control, font/color/opacity customization |
| **🧹 Smart Punctuation** | Adaptive boundary scoring (no more hanging word lists) |
| **⚙️ Any LLM backend** | Grammar correction via omlx, Ollama, LM Studio, or OpenAI |
| **🗂 Batch Processing** | Queue multiple files with same settings |
| **🔒 100% Offline** | Your footage never leaves your Mac |

## Quick Start

**Prerequisites:** Python 3.12+ (install via [python.org](https://python.org) or `brew install python@3.12`)

```bash
# 1. Download VideoForge.dmg or clone the repo
# 2. Open VideoForge.app (right-click > Open on first launch)
# 3. The app auto-installs mlx-whisper + ffmpeg on first transcription
# 4. Done.
```

Or just open the app — the built-in setup wizard walks you through everything.

### Unblock uncertified app

```bash
xattr -dr com.apple.quarantine /Applications/VideoForge.app
```

## Architecture

```
Input Video
    │
    ├── ffmpeg (audio extraction — system or auto-downloaded static binary)
    ├── mlx-whisper (Python bridge) → transcription with word timestamps
    ├── Merge (boundary-aware) → smart segment grouping
    ├── LLM (omlx / Ollama) → grammar correction (optional)
    ├── Boundary scoring → auto punctuation
    ├── Post-processing → silence / noise / portrait / music / overlay
    └── SRT / VTT / MP4 → export
```

## Requirements

- macOS 15+ (Sequoia)
- Apple Silicon (M1/M2/M3/M4)
- 8 GB RAM recommended
- 4 GB storage for AI models
- Python 3.12+ (auto-detected from Homebrew, pyenv, conda, or system)

## Automatic dependency management

The app creates a self-contained Python environment in `~/.videoforge/venv/`:

| Dependency | Install method |
|---|---|
| **mlx-whisper** | `pip install` into venv (automatic) |
| **ffmpeg** | Uses system installation or downloads static binary to `~/.videoforge/bin/ffmpeg` |
| **Python 3** | Must be pre-installed — the app detects it at known paths |

## Development

```bash
git clone https://github.com/Swallow74/VideoForge.git
cd VideoForge

swift build              # Build
swift test               # 47 unit tests — all green
swift run VideoForge     # Launch in debug mode
swift build -c release   # Release build → .build/arm64-apple-macosx/release/VideoForge
```

### Integration tests

```bash
bash /tmp/vf-test-framework/test_all.sh
```

Tests: Python discovery, venv creation, mlx-whisper install, ffmpeg extraction, transcription (tiny + large-v3), grammar correction API.

### Project structure

```
VideoForge/
├── Sources/
│   ├── VideoEditCore/           # Pure Swift logic (47 unit tests)
│   │   ├── BoundaryScore.swift
│   │   ├── MergeService.swift
│   │   ├── TextNormalizer.swift
│   │   ├── CorrectionCache.swift
│   │   ├── ProfileDetector.swift
│   │   ├── SRTExporter.swift
│   │   ├── SilenceRemovalService.swift
│   │   ├── NoiseRemovalService.swift
│   │   ├── PortraitBoxService.swift
│   │   ├── MusicDuckingService.swift
│   │   ├── DualLanguageService.swift
│   │   └── OverlayService.swift
│   ├── MLXWhisper/              # MLX Whisper model scaffold
│   ├── VideoForge/              # macOS app
│   │   ├── App.swift
│   │   ├── ContentView.swift    # Modern macOS UI with native toolbar
│   │   ├── PipelineService.swift  # Orchestrator with weighted progress
│   │   ├── TranscriptionService.swift  # Python bridge via Process
│   │   ├── GrammarService.swift  # OpenAI-compatible LLM client
│   │   ├── DependencyService.swift  # Auto-setup: venv + ffmpeg
│   │   ├── AudioService.swift
│   │   ├── EnvLoader.swift       # ~/.videoforge/.env reader
│   │   ├── SettingsView.swift    # Preferences (Cmd+,)
│   │   ├── SetupView.swift       # First-launch wizard
│   │   ├── TeleprompterService.swift
│   │   └── UI/
│   │       └── TeleprompterView.swift
│   └── Resources/
│       └── transcribe_audio.py  # Python bridge script
├── Tests/
│   └── VideoEditCoreTests/      # 47 unit tests
└── Package.swift
```

### Python bridge

Transcription uses `mlx-whisper` via a Python subprocess bridge (`transcribe_audio.py`). The app auto-creates a venv at `~/.videoforge/venv/` with all dependencies on first use. The MLX Swift model scaffold (`MLXWhisper/`) compiles and is ready for native inference once weight loading from HuggingFace is wired up.

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | Open Teleprompter |
| `Cmd+R` | Start processing |
| `Cmd+.` | Stop processing |
| `Cmd+,` | Open Settings |

## Settings (Cmd+,)

Two tabs:
- **General** — default Whisper model, language, profile, grammar model
- **API** — API URL, API key (saved to `~/.videoforge/.env`, never committed)

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

Built with [MLX Swift](https://github.com/ml-explore/mlx-swift), [mlx-whisper](https://github.com/ml-explore/mlx-whisper), and [ffmpeg](https://ffmpeg.org/).
