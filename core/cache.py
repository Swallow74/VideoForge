import hashlib
from pathlib import Path


class CorrectionCache:
    def __init__(self, cache_dir: str = ".cache/correzioni"):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._mem_cache: dict[str, str] = {}

    def _hash(self, text: str) -> str:
        return hashlib.md5(text.encode("utf-8")).hexdigest()

    def get(self, text: str) -> str | None:
        if text in self._mem_cache:
            return self._mem_cache[text]
        h = self._hash(text)
        p = self.cache_dir / f"{h}.txt"
        if p.exists():
            val = p.read_text("utf-8").strip()
            self._mem_cache[text] = val
            return val
        return None

    def set(self, original: str, corrected: str):
        if original == corrected:
            return
        h = self._hash(original)
        p = self.cache_dir / f"{h}.txt"
        p.write_text(corrected.strip(), "utf-8")
        self._mem_cache[original] = corrected.strip()

    def get_or_correct(self, text: str, correct_fn) -> str:
        cached = self.get(text)
        if cached is not None:
            return cached
        corrected = correct_fn(text)
        self.set(text, corrected)
        return corrected
