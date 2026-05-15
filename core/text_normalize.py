import re


def normalize_text(text: str) -> str:
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return text
    text = text[0].upper() + text[1:]
    text = re.sub(r"\s+([.,!?;:])", r"\1", text)
    text = re.sub(r"([.!?])([A-Za-z])", r"\1 \2", text)
    return text


def fix_punct_local(
    text: str,
    next_text: str = "",
    gap_sec: float = 1.0,
    profile: dict | None = None,
    context: dict | None = None,
) -> str:
    from .boundary_score import should_break
    from .config import PROFILES

    if profile is None:
        profile = PROFILES["conversational"]

    text = text.strip()
    if not text:
        return text

    brk = should_break(text, 0.0, next_text, gap_sec, profile, context) if next_text else True

    if text[0].islower():
        text = text[0].upper() + text[1:]

    if brk:
        if text[-1] not in ".!?":
            text += "."
    else:
        if text and text[-1] in ".!?" and len(text.split()) > 1:
            pass
        elif text and text[-1] in ".!?" and len(text.split()) <= 1:
            text = text.rstrip(".!?").strip()

    return text


def needs_qwen(text: str) -> bool:
    if len(text) < 30:
        return False
    if any(c in text for c in "[]()"):
        return True
    if text.count("  ") > 2:
        return True
    if re.search(r"[a-z][A-Z]", text):
        return True
    words = text.split()
    if len(words) >= 3 and len(set(w.lower() for w in words)) <= 2:
        return False
    return False
