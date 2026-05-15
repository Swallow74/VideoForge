import json
import subprocess
from pathlib import Path


def extract_audio(video_path: str, sample_rate: int = 16000) -> str:
    audio_path = video_path.rsplit(".", 1)[0] + "_audio.wav"
    ap = Path(audio_path)
    vp = Path(video_path)
    if ap.exists() and ap.stat().st_mtime >= vp.stat().st_mtime:
        return audio_path
    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", str(sample_rate),
        "-ac", "1",
        audio_path
    ]
    subprocess.run(cmd, check=True, capture_output=True)
    return audio_path


def is_audio_file(path: str) -> bool:
    return Path(path).suffix.lower() in (".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac")


def get_audio_duration(path: str) -> float:
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json",
           "-show_format", path]
    data = json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)
    return float(data["format"]["duration"])
