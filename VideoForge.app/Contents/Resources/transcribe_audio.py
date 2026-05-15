#!/usr/bin/env python3
"""Bridge script: called by the Swift app to transcribe audio via mlx-whisper.
Outputs JSON to stdout. Accepts --model and --language."""

import argparse
import json
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("audio_path")
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--language", default=None)
    args = parser.parse_args()

    try:
        import mlx_whisper
    except ImportError:
        print("ERROR: mlx-whisper not installed. Run: pip install mlx-whisper", file=sys.stderr)
        sys.exit(1)

    kwargs = dict(path_or_hf_repo=f"mlx-community/whisper-{args.model}-mlx",
                  word_timestamps=True)
    if args.language:
        kwargs["language"] = args.language

    result = mlx_whisper.transcribe(args.audio_path, **kwargs)

    segments = []
    for seg in result.get("segments", []):
        words = []
        for w in seg.get("words", []):
            words.append({
                "word": w.get("word", "").strip(),
                "start": w.get("start", 0.0),
                "end": w.get("end", 0.0),
            })
        segments.append({
            "start": seg.get("start", 0.0),
            "end": seg.get("end", 0.0),
            "text": seg.get("text", "").strip(),
            "words": words,
        })

    json.dump(segments, sys.stdout, ensure_ascii=False)

if __name__ == "__main__":
    main()
