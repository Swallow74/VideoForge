import numpy as np

from .config import PROFILES, DEFAULT_PROFILE


def detect_profile(segments: list[dict]) -> dict:
    if not segments:
        return PROFILES[DEFAULT_PROFILE]

    sample_size = min(30, len(segments))
    sample_texts = [s["text"] for s in segments[:sample_size]]
    full_sample = " ".join(sample_texts)
    words = full_sample.split()

    if not words:
        return PROFILES[DEFAULT_PROFILE]

    stats = {
        "question_ratio": full_sample.count("?") / max(len(words), 1),
        "exclaim_ratio": full_sample.count("!") / max(len(words), 1),
        "avg_seg_len": np.mean([len(t) for t in sample_texts]),
        "avg_word_len": np.mean([len(w) for w in words]),
        "long_seg_ratio": sum(1 for t in sample_texts if len(t) > 60) / max(len(sample_texts), 1),
    }

    question_score = stats["question_ratio"]
    long_seg_score = stats["long_seg_ratio"]
    avg_len = stats["avg_seg_len"]

    name = DEFAULT_PROFILE
    if question_score > 0.08:
        name = "conversational"
    elif long_seg_score > 0.5 and avg_len > 65:
        name = "lecturing"
    elif stats["avg_word_len"] > 6.5:
        name = "technical"

    return PROFILES[name]
