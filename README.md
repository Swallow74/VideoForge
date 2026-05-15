# VideoForge

**The all-in-one video workstation for macOS.**  
Transcribe, clean, resize, subtitle, and publish — 100% offline.

> Trascrizione AI → SRT | Rimozione silenzi | Portrait 9:16 | Musica + Ducking | Overlay PIP | SRT bilingue

---

## Features

| Module | What it does |
|--------|-------------|
| **🎙 AI Transcription** | Whisper large-v3 via MLX (Apple Silicon native). Word-level timestamps |
| **✂️ Silence Removal** | Auto-cut silences with configurable threshold |
| **🔇 Noise Removal** | Background noise filter (anlmdn + highpass) |
| **📱 Portrait Box** | Auto-crop 16:9 → 9:16 for Shorts/Reels |
| **🎵 Music + Ducking** | Background music with sidechain compression |
| **🌐 Dual Subtitles** | Bilingual SRT/VTT (IT + EN, etc.) |
| **🖼️ Overlay (PIP)** | Webcam / screen overlay compositing |
| **📜 Teleprompter** | Scrolling script with speed control |
| **🧹 Smart Punctuation** | Adaptive boundary scoring (no more _HANGING word lists) |
| **⚙️ Any LLM backend** | Works with omlx, Ollama, LM Studio, OpenAI |
| **🗂 Batch Processing** | Queue multiple files with same settings |
| **🔒 100% Offline** | Your footage never leaves your Mac |

## Quick Start

```bash
# 1. Download VideoForge.dmg
# 2. Drag to Applications
# 3. Install dependencies:
bash /Applications/VideoForge.app/Contents/Resources/install.sh

# 4. Launch:
open /Applications/VideoForge.app
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
    ├── ffmpeg (audio extraction)
    ├── Whisper (MLX / Python) → transcription with word timestamps
    ├── Merge (boundary-aware) → smart segment grouping
    ├── LLM (omlx / Ollama) → grammar correction (optional)
    ├── Boundary scoring → auto punctuation
    ├── Post-processing → silence / noise / portrait / music / overlay
    └── SRT / VTT / MP4 → export
```

The core engine (`VideoEditCore`) is pure Swift. Transcription uses `mlx-whisper` via Python bridge with a full MLX Swift model scaffold ready for native inference.

## Requirements

- macOS 15+ (Sequoia)
- Apple Silicon (M1/M2/M3/M4)
- 8 GB RAM recommended
- 4 GB storage for AI models

## Development

```bash
git clone https://github.com/Swallow74/VideoForge.git
cd VideoForge

swift build              # Build
swift test               # 46 tests — all green
swift run VideoForge     # Launch in debug mode
swift build -c release   # Release build → .build/arm64-apple-macosx/release/VideoForge
```

### Project structure

```
VideoForge/
├── Sources/
│   ├── VideoForgeCore/        # Pure Swift logic
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
│   ├── MLXWhisper/           # MLX Whisper scaffold (native)
│   ├── VideoForge/           # macOS app
│   │   ├── App.swift
│   │   ├── ContentView.swift
│   │   ├── PipelineService.swift
│   │   ├── GrammarService.swift
│   │   ├── TranscriptionService.swift
│   │   ├── DependencyService.swift
│   │   ├── SetupView.swift
│   │   ├── TeleprompterService.swift
│   │   └── UI/
│   │       └── TeleprompterView.swift
│   └── py/                   # Python bridge scripts
│       └── transcribe_audio.py
├── Tests/
│   └── VideoForgeCoreTests/  # 46 unit tests
└── Package.swift
```

### Python bridge

Transcription currently uses `mlx-whisper` via Python. The MLX Swift model scaffold is ready and compiles — native inference requires wiring up weight loading from HuggingFace (`mlx-community/whisper-*-mlx`).

## License

Apache 2.0 — see [LICENSE](LICENSE).

---

Built with [MLX Swift](https://github.com/ml-explore/mlx-swift) and [ffmpeg](https://ffmpeg.org/).
