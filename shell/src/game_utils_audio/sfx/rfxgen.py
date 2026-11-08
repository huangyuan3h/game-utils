"""Optional rFXGen backend (C binary on PATH)."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from game_utils_audio.wavutil import write_meta

RFXGEN_PRESETS = {
    "coin": "coin",
    "laser": "laser",
    "explosion": "explosion",
    "powerup": "powerup",
    "hit": "hit",
    "jump": "jump",
    "blip": "blip",
}


def binary_path() -> str | None:
    return shutil.which("rfxgen")


def is_ready() -> bool:
    return binary_path() is not None


def generate_file(preset: str, out: Path, seed: int | None = None) -> Path:
    exe = binary_path()
    if not exe:
        raise RuntimeError(
            "rfxgen not found on PATH. Build/install from https://github.com/raysan5/rfxgen "
            "or download a standalone binary, then retry."
        )

    key = preset.lower().replace("_", "").replace("-", "")
    mapped = RFXGEN_PRESETS.get(key)
    if not mapped:
        raise ValueError(f"Unknown rfxgen preset '{preset}'. Known: {', '.join(sorted(RFXGEN_PRESETS))}")

    out.parent.mkdir(parents=True, exist_ok=True)
    # rFXGen: --generate <preset> --output file.wav
    subprocess.run(
        [exe, "--generate", mapped, "--output", str(out)],
        check=True,
    )
    write_meta(
        out,
        {
            "kind": "sfx",
            "backend": "rfxgen",
            "preset": preset,
            "rfxgen_preset": mapped,
            "seed": seed,
            "upstream": "https://github.com/raysan5/rfxgen",
        },
    )
    return out
