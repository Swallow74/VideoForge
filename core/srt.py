import re

MAX_CPS = 15


def format_timestamp(seconds: float) -> str:
    seconds = max(seconds, 0)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    ms = min(ms, 999)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def wrap_text(text: str, max_chars: int = 42) -> str:
    words = text.split()
    lines = []
    current_line = ""
    for word in words:
        if len(current_line) + len(word) + 1 <= max_chars:
            current_line = current_line + " " + word if current_line else word
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
    if current_line:
        lines.append(current_line)
    return "\n".join(lines[:3])


def _split_by_cps(seg: dict) -> list[dict]:
    dur = seg["end"] - seg["start"]
    text = seg["text"]
    if dur <= 0 or len(text) / dur <= MAX_CPS:
        return [seg]

    candidates = [i + 1 for i, ch in enumerate(text) if ch in ".!?"]
    if not candidates:
        return [seg]

    mid = len(text) // 2
    split_pos = min(candidates, key=lambda p: abs(p - mid))

    if split_pos < 15 or len(text) - split_pos < 15:
        return [seg]

    part_a = text[:split_pos].strip()
    part_b = text[split_pos:].strip()
    if not part_a or not part_b:
        return [seg]

    total_len = len(part_a) + len(part_b)
    ratio_a = len(part_a) / total_len if total_len else 0.5
    split_at = seg["start"] + dur * ratio_a

    a_dur = split_at - seg["start"]
    b_dur = seg["end"] - split_at
    if a_dur < 1.0 or b_dur < 1.0:
        return [seg]

    return [
        {"start": seg["start"], "end": split_at, "text": part_a, "words": []},
        {"start": split_at, "end": seg["end"], "text": part_b, "words": []},
    ]


def _validate_segments(segments: list[dict]) -> list[dict]:
    validated = []
    for i, seg in enumerate(segments):
        s = dict(seg)
        if s["end"] <= s["start"]:
            s["end"] = s["start"] + 0.5
        if i > 0:
            if s["start"] < validated[-1]["start"]:
                s["start"] = validated[-1]["end"]
            if s["start"] >= s["end"]:
                s["start"] = validated[-1]["end"]
                s["end"] = s["start"] + 0.5
        validated.append(s)
    return validated


def export_srt(segments: list[dict], output_path: str):
    segments = _validate_segments(segments)

    resynced = []
    for seg in segments:
        resynced.extend(_split_by_cps(seg))

    resynced = _validate_segments(resynced)

    with open(output_path, "w", encoding="utf-8") as f:
        for i, seg in enumerate(resynced, 1):
            start_ts = format_timestamp(seg["start"])
            end_ts = format_timestamp(seg["end"])
            text = seg["text"]
            if "fino a poco" in text.lower() and "tempo fa" not in text.lower():
                text = text.replace("fino a poco", "fino a poco tempo fa")
            text = wrap_text(text, max_chars=42)
            f.write(f"{i}\n{start_ts} --> {end_ts}\n{text}\n\n")
