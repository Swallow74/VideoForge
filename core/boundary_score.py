import re

_WEAK_CONNECTIVES = {
    "e", "ma", "o", "oppure", "che", "perché", "perche", "quindi",
    "allora", "mentre", "invece", "comunque", "però", "pero",
    "dunque", "quindi", "infatti", "cioè", "cioe", "inoltre",
    "anche", "poi", "tuttavia", "anzi",
}

_STRONG_STARTS = {
    "no", "sì", "si", "ah", "oh", "beh", "ecco", "ok", "okay",
    "allora", "dunque", "bene", "giusto", "certo",
}

_PAUSE_WORDS = {
    "diciamo", "praticamente", "fondamentalmente", "sostanzialmente",
}


def boundary_score(
    curr_text: str,
    curr_end: float,
    next_text: str,
    next_start: float,
    profile: dict,
    context: dict | None = None,
) -> float:
    curr = curr_text.strip()
    nxt = next_text.strip()
    if not curr or not nxt:
        return 1.0

    gap_sec = next_start - curr_end
    score = 0.0

    gap = min(gap_sec / profile.get("gap_break", 1.0), 1.5)
    score += gap * 0.25

    if len(curr) > profile["max_chars"]:
        score += 0.4

    if curr and curr[-1] in ".!?…":
        score += 0.7
    elif curr and curr[-1] in ",;:":
        score -= 0.4

    if nxt:
        if nxt[0].isupper():
            score += 0.3
        else:
            score -= 0.3

    first_word = nxt.split()[0].lower().strip("«»\"'") if nxt.split() else ""
    ends_strong = curr and curr[-1] in ".!?…"
    if first_word in _WEAK_CONNECTIVES:
        if not ends_strong:
            score -= 0.5 * profile.get("weak_conj_boost", 1.0)
    if first_word in _STRONG_STARTS:
        score += 0.3
    if first_word in _PAUSE_WORDS:
        score -= 0.3

    curr_words = curr.split()
    len_penalty = 0.0
    if len(curr_words) <= 2:
        len_penalty = 0.5
    elif len(curr_words) <= 4:
        len_penalty = 0.2

    if curr and curr[-1] not in ".!?…":
        score -= len_penalty

    if context:
        prev_gap = context.get("prev_gap", 0)
        if prev_gap > 0 and gap_sec < prev_gap * 0.3:
            score -= 0.2

        silence_after = context.get("silence_after", 0)
        if silence_after > 2.0:
            score += 0.3

    return score


def should_break(
    curr_text: str,
    curr_end: float,
    next_text: str,
    next_start: float,
    profile: dict,
    context: dict | None = None,
) -> bool:
    return boundary_score(curr_text, curr_end, next_text, next_start, profile, context) >= profile["boundary_threshold"]
