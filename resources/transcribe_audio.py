#!/usr/bin/env python3
"""Bridge script: called by VideoForge to transcribe audio.
Supports multiple engines: whisper (default), qwen3-0.6b, qwen3-1.7b.
Outputs JSON to stdout. Model weights auto-download on first use."""

import argparse
import json
import os
import subprocess
import sys
import warnings

warnings.filterwarnings("ignore")
# TQDM non disabilitato: lasciamo che huggingface_hub mostri progresso


def ensure_installed(package: str, import_name: str | None = None):
    """Auto-install a pip package if missing. Returns the module."""
    mod = import_name or package.replace("-", "_")
    try:
        return __import__(mod)
    except ImportError:
        print(f"DOWNLOAD_PROGRESS:0.0|Installazione {package}...", file=sys.stderr)
        sys.stderr.flush()
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", package, "--quiet"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(f"ERROR: Failed to install {package}: {result.stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        print(f"DOWNLOAD_PROGRESS:1.0|{package} installato", file=sys.stderr)
        sys.stderr.flush()
        return __import__(mod)


def model_is_cached(hf_repo: str) -> bool:
    """Check if a HuggingFace model is already cached locally."""
    from huggingface_hub import HfApi, scan_cache_dir
    try:
        cache_info = scan_cache_dir()
        for repo in cache_info.repos:
            if repo.repo_id == hf_repo:
                return True
    except Exception:
        pass
    try:
        api = HfApi()
        files = api.list_repo_files(hf_repo)
        for f in files:
            path = os.path.expanduser(f"~/.cache/huggingface/hub/{hf_repo.replace('/', '--')}/snapshots")
            if os.path.exists(path):
                return True
        return False
    except Exception:
        return False


def model_size_str(model_size: str) -> str:
    _labels = {"0.6B": "0.6B (600M)", "1.7B": "1.7B", "large-v3": "large-v3", "large-v2": "large-v2",
               "medium": "medium", "small": "small", "base": "base", "tiny": "tiny"}
    return _labels.get(model_size, model_size)


def transcribe_whisper(audio_path: str, model: str, language: str | None) -> list[dict]:
    ensure_installed("mlx-whisper", "mlx_whisper")
    import mlx_whisper
    repo = f"mlx-community/whisper-{model}-mlx"
    if not model_is_cached(repo):
        print(f"MODEL_DOWNLOAD:0.0|Download modello {model_size_str(model)}...", file=sys.stderr)
        sys.stderr.flush()
    kwargs: dict = dict(path_or_hf_repo=repo, word_timestamps=True)
    if language:
        kwargs["language"] = language
    result = mlx_whisper.transcribe(audio_path, **kwargs)
    return parse_whisper_segments(result)


def transcribe_qwen3(audio_path: str, model_size: str, language: str | None) -> list[dict]:
    ensure_installed("mlx-qwen3-asr", "mlx_qwen3_asr")
    import mlx_qwen3_asr
    model_id = f"mlx-community/Qwen3-ASR-{model_size}-4bit"
    if not model_is_cached(model_id):
        print(f"MODEL_DOWNLOAD:0.0|Download modello Qwen3-ASR {model_size_str(model_size)}...", file=sys.stderr)
        sys.stderr.flush()
    session = mlx_qwen3_asr.Session(model=model_id)
    kwargs: dict = dict(verbose=False, return_timestamps=True, return_chunks=True)
    if language:
        kwargs["language"] = language
    result = session.transcribe(audio_path, **kwargs)
    return parse_qwen3_segments(result)


def parse_whisper_segments(result) -> list[dict]:
    segments = []
    for idx, seg in enumerate(result.get("segments", [])):
        words = []
        for w in seg.get("words", []):
            words.append({
                "word": w.get("word", "").strip(),
                "start": w.get("start", 0.0),
                "end": w.get("end", 0.0),
            })
        segments.append({
            "id": seg.get("id", idx),
            "start": seg.get("start", 0.0),
            "end": seg.get("end", 0.0),
            "text": seg.get("text", "").strip(),
            "words": words,
        })
    return segments


def parse_qwen3_segments(result) -> list[dict]:
    segments = []
    result_dict = result if isinstance(result, dict) else result.__dict__
    raw_segments = result_dict.get("segments") or result_dict.get("chunks") or []
    for idx, seg in enumerate(raw_segments):
        seg_dict = seg if isinstance(seg, dict) else seg.__dict__
        segments.append({
            "id": seg_dict.get("id", idx),
            "start": seg_dict.get("start", 0.0),
            "end": seg_dict.get("end", 0.0),
            "text": seg_dict.get("text", "").strip(),
            "words": [],
        })
    if not segments:
        text = result_dict.get("text", "")
        if text:
            segments.append({
                "id": 0,
                "start": 0.0,
                "end": 0.0,
                "text": text.strip(),
                "words": [],
            })
    return segments


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_path")
    parser.add_argument("--engine", default="whisper",
                        choices=["whisper", "qwen3-0.6b", "qwen3-1.7b"])
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--language", default=None)
    args = parser.parse_args()

    if args.engine == "whisper":
        segments = transcribe_whisper(args.audio_path, args.model, args.language)
    elif args.engine == "qwen3-0.6b":
        segments = transcribe_qwen3(args.audio_path, "0.6B", args.language)
    elif args.engine == "qwen3-1.7b":
        segments = transcribe_qwen3(args.audio_path, "1.7B", args.language)
    else:
        print(f"ERROR: Unknown engine: {args.engine}", file=sys.stderr)
        sys.exit(1)

    json.dump(segments, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
