from __future__ import annotations

import json
import wave
from pathlib import Path
from typing import Any


def write_wav_mono_s16(path: Path, samples: list[float] | list[int], sample_rate: int = 44100) -> None:
    """Write mono 16-bit PCM WAV from float samples in [-1, 1] or int16 values."""
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = bytearray()
    for s in samples:
        if isinstance(s, float):
            v = max(-1.0, min(1.0, s))
            i = int(v * 32767.0)
        else:
            i = max(-32768, min(32767, int(s)))
        frames += int(i).to_bytes(2, byteorder="little", signed=True)

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(frames)


def write_meta(path: Path, meta: dict[str, Any]) -> Path:
    meta_path = path.with_suffix(path.suffix + ".meta.json")
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return meta_path
