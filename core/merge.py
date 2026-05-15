from .config import PROFILES, DEFAULT_PROFILE


def _is_loop(text: str) -> bool:
    words = text.lower().split()
    if len(words) < 4:
        return False
    unique = set(words)
    if len(unique) <= 2:
        return True
    if len(words) >= 8:
        for n in (2, 3, 4):
            if len(words) >= n * 3:
                chunks = [tuple(words[i:i + n]) for i in range(0, len(words), n)]
                if len(chunks) >= 3 and len(set(chunks)) <= 1:
                    return True
    return False


def _make_entry(segs: list[dict]) -> dict:
    return {
        "start": segs[0]["start"],
        "end": segs[-1]["end"],
        "text": " ".join(s["text"] for s in segs),
        "words": [],
    }


def merge_and_group(segments: list[dict], profile: dict | None = None) -> list[dict]:
    if profile is None:
        profile = PROFILES[DEFAULT_PROFILE]

    max_chars = profile.get("max_chars", 60)
    max_duration = profile.get("max_duration", 10.0)

    grouped = []
    buffer: list[dict] = []

    for seg in segments:
        if _is_loop(seg["text"]):
            continue

        if not buffer:
            buffer = [seg]
            continue

        combined = " ".join(s["text"] for s in buffer) + " " + seg["text"]
        duration = seg["end"] - buffer[0]["start"]

        if len(combined) > max_chars or duration > max_duration:
            grouped.append(_make_entry(buffer))
            buffer = [seg]
        else:
            buffer.append(seg)

    if buffer:
        grouped.append(_make_entry(buffer))

    return grouped
