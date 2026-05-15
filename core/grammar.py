import os
import time
from openai import OpenAI
from tqdm import tqdm

from .text_normalize import normalize_text, fix_punct_local, needs_qwen
from .cache import CorrectionCache
from .config import PROFILES

_API_KEY = os.environ.get("OMLX_API_KEY", "pippopippo")
_client = OpenAI(base_url="http://127.0.0.1:8000/v1", api_key=_API_KEY)

_SYS = (
    "Sei un correttore ortografico automatico per sottotitoli video italiani. "
    "INPUT: una frase breve, possibilmente con errori di battitura, "
    "accordo grammaticale o trascrizione automatica. "
    "OUTPUT: restituisci SOLO la frase corretta, senza spiegazioni, senza virgolette, "
    "senza prefissi come Correzione:, senza aggiungere frasi nuove, "
    "senza completare pensieri lasciati volutamente incompleti. "
    "NON aggiungere parole a meno che non siano strettamente necessarie per la grammatica. "
    "NON togliere parole. NON cambiare il significato. NON punteggiare alla fine. "
    "Se la frase è già corretta, restituiscila identica."
)

_cache = CorrectionCache()


def _validate(output: str, original: str) -> str:
    stripped = output.strip().strip('"').strip("'").strip()
    words_out = stripped.split()
    words_in = original.strip().split()
    if len(words_out) > len(words_in) * 2:
        return ""
    if any(c in stripped for c in ["\n", "→", "Correzione", "Nota", "**"]):
        return stripped.split("\n")[0]
    if ":" in stripped and stripped.count(" ") < 6:
        return stripped.split(":")[-1].strip()
    return stripped


def _correct_text(text: str, model: str) -> str:
    if not text.strip():
        return text
    try:
        r = _client.chat.completions.create(
            model=model,
            messages=[{"role": "system", "content": _SYS}, {"role": "user", "content": text}],
            temperature=0.0,
            max_tokens=len(text) * 3 + 30,
        )
        raw = r.choices[0].message.content.strip()
        out = _validate(raw, text)
        return out if out else text
    except Exception:
        return text


def _correct_with_cache(text: str, model: str) -> str:
    return _cache.get_or_correct(text, lambda t: _correct_text(t, model))


def _correct_batch(segments: list[dict], model: str) -> list[dict]:
    to_correct = [s for s in segments if needs_qwen(s["text"])]
    cache_hits = 0

    for seg in to_correct:
        cached = _cache.get(seg["text"])
        if cached is not None:
            seg["text"] = cached
            cache_hits += 1

    to_query = [s for s in to_correct if s["text"] == s.get("_original", s["text"])]

    for seg in to_query:
        corrected = _correct_text(seg["text"], model)
        if corrected:
            _cache.set(seg["text"], corrected)
            seg["text"] = corrected

    return segments


def correct_segments(
    segments: list[dict],
    model: str,
    profile: dict | None = None,
    on_corrected=None,
) -> list[dict]:
    if profile is None:
        profile = PROFILES.get("conversational")

    corrected = []
    batch_size = 5

    if model:
        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            batch = _correct_batch(batch, model)
            corrected.extend(batch)
    else:
        corrected = [dict(s) for s in segments]

    for seg in corrected:
        seg["text"] = normalize_text(seg["text"])

    context: dict = {"prev_gap": 0.0}
    for i, seg in enumerate(corrected):
        next_seg = corrected[i + 1] if i + 1 < len(corrected) else None
        next_text = next_seg["text"] if next_seg else ""
        gap = (next_seg["start"] - seg["end"]) if next_seg else 2.0

        seg["text"] = fix_punct_local(seg["text"], next_text=next_text, gap_sec=gap, profile=profile, context=context)

        if seg["text"] and seg["text"][0].islower():
            seg["text"] = seg["text"][0].upper() + seg["text"][1:]

        context["prev_gap"] = gap

        if on_corrected:
            on_corrected({"start": seg["start"], "end": seg["end"], "text": seg["text"]})

    return corrected
