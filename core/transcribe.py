import os
import time
import warnings
from functools import partial

warnings.filterwarnings("ignore", message=".*unauthenticated requests.*")

_OMLX_KEY = os.environ.get("OMLX_API_KEY", "pippopippo")
_OMLX_URL = os.environ.get("OMLX_API_URL", "http://127.0.0.1:8000/v1")

_mlx_whisper = None
_vad_model = None


def _get_mlx():
    global _mlx_whisper
    if _mlx_whisper is None:
        import mlx_whisper
        _mlx_whisper = mlx_whisper
    return _mlx_whisper


def _omlx_client(base_url=None):
    from openai import OpenAI
    url = base_url or _OMLX_URL
    return OpenAI(base_url=url, api_key=_OMLX_KEY)


def list_models(base_url=None) -> list[str]:
    try:
        models = _omlx_client(base_url).models.list()
        return [m.id for m in models]
    except Exception:
        return []


def _is_speech(seg_start: float, seg_end: float, speech_segments: list[tuple[float, float]]) -> bool:
    if not speech_segments:
        return True
    overlap_threshold = 1.0
    for sp_start, sp_end in speech_segments:
        overlap = min(seg_end, sp_end) - max(seg_start, sp_start)
        if overlap >= overlap_threshold:
            return True
    return False


def _filter_hallucinations(segments: list[dict], speech_segments: list[tuple[float, float]]) -> list[dict]:
    if not speech_segments:
        return segments
    return [s for s in segments if _is_speech(s["start"], s["end"], speech_segments)]


def _fmt(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    if h:
        return f"{h}:{m:02d}:{s:02d}"
    return f"{m}:{s:02d}"


def transcribe_file(
    audio_path: str,
    language: str | None = None,
    model_size: str = "large-v3",
    on_raw_segment=None,
    on_progress=None,
) -> list[dict]:
    mlx = _get_mlx()
    model_path = f"mlx-community/whisper-{model_size}-mlx"

    kwargs = dict(
        path_or_hf_repo=model_path,
        word_timestamps=True,
    )
    if language:
        kwargs["language"] = language

    from core.audio import get_audio_duration

    try:
        total_duration = get_audio_duration(audio_path)
    except Exception:
        total_duration = 0

    t0 = time.time()
    if on_progress and total_duration:
        on_progress(0, 0, total_duration)

    result = mlx.transcribe(audio_path, **kwargs)

    speech_segments = _get_speech_segments(audio_path)

    all_segments = []
    for seg in result.get("segments", []):
        words = []
        for w in seg.get("words", []):
            words.append({
                "word": w.get("word", "").strip(),
                "start": w.get("start", 0.0),
                "end": w.get("end", 0.0),
            })
        entry = {
            "start": seg.get("start", 0.0),
            "end": seg.get("end", 0.0),
            "text": seg.get("text", "").strip(),
            "words": words,
        }
        all_segments.append(entry)

    before_filter = len(all_segments)
    all_segments = _filter_hallucinations(all_segments, speech_segments)
    after_filter = len(all_segments)

    for entry in all_segments:
        if on_raw_segment:
            on_raw_segment(entry)
        if on_progress and total_duration:
            pct = min(entry["end"] / total_duration * 100, 99.9)
            elapsed = time.time() - t0
            on_progress(pct, entry["end"], total_duration, elapsed=elapsed)

    filtered_count = before_filter - after_filter
    if on_progress and total_duration:
        on_progress(100, total_duration, total_duration,
                    elapsed=0, filtered=filtered_count)

    return all_segments


ASR_MODELS = ["large-v3", "large-v2", "medium", "small", "base", "tiny"]
