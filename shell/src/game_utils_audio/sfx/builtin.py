"""Lightweight sfxr-style procedural SFX (Python, no GPU / Node)."""

from __future__ import annotations

import math
import random
from dataclasses import dataclass
from pathlib import Path

from game_utils_audio.wavutil import write_meta, write_wav_mono_s16

# Friendly names → internal recipe ids (aligned with jsfxr / rFXGen naming)
PRESETS = {
    "coin": "coin",
    "pickupcoin": "coin",
    "laser": "laser",
    "lasershoot": "laser",
    "explosion": "explosion",
    "powerup": "powerup",
    "hit": "hit",
    "hithurt": "hit",
    "jump": "jump",
    "blip": "blip",
    "blipselect": "blip",
    "click": "click",
}


@dataclass
class Recipe:
    wave: str  # square | saw | sine | noise
    base_freq: float
    freq_slide: float
    length: float
    attack: float
    sustain: float
    decay: float
    punch: float
    duty: float = 0.5
    vibrato_speed: float = 0.0
    vibrato_depth: float = 0.0
    noise_amount: float = 0.0


def _recipe(name: str, seed: int | None) -> Recipe:
    rng = random.Random(seed)
    j = lambda a, b: a + (b - a) * rng.random()  # noqa: E731

    table = {
        "coin": Recipe("square", j(900, 1400), -j(200, 600), 0.35, 0.0, 0.08, 0.25, 0.4, 0.5),
        "laser": Recipe("saw", j(600, 1200), -j(800, 1600), 0.28, 0.0, 0.05, 0.2, 0.2, 0.3),
        "explosion": Recipe("noise", j(80, 180), -j(40, 120), 0.7, 0.0, 0.15, 0.55, 0.6, noise_amount=1.0),
        "powerup": Recipe("square", j(200, 350), j(400, 900), 0.55, 0.02, 0.2, 0.3, 0.35, 0.5, 8.0, 0.05),
        "hit": Recipe("noise", j(200, 500), -j(300, 700), 0.22, 0.0, 0.04, 0.18, 0.5, noise_amount=0.8),
        "jump": Recipe("square", j(220, 320), j(250, 450), 0.3, 0.0, 0.08, 0.2, 0.25, 0.45),
        "blip": Recipe("square", j(600, 900), 0.0, 0.12, 0.0, 0.04, 0.08, 0.15, 0.5),
        "click": Recipe("square", j(1000, 1800), -j(200, 500), 0.06, 0.0, 0.01, 0.05, 0.1, 0.5),
    }
    if name not in table:
        raise ValueError(f"Unknown preset: {name}. Choose from: {', '.join(sorted(PRESETS))}")
    return table[name]


def _osc(wave: str, phase: float, duty: float, rng: random.Random) -> float:
    if wave == "sine":
        return math.sin(phase * 2 * math.pi)
    if wave == "saw":
        return 2.0 * phase - 1.0
    if wave == "noise":
        return rng.uniform(-1.0, 1.0)
    # square
    return 1.0 if phase < duty else -1.0


def synthesize(preset: str, seed: int | None = None, sample_rate: int = 44100) -> list[float]:
    key = PRESETS.get(preset.lower().replace("_", "").replace("-", ""), preset.lower())
    recipe = _recipe(key, seed)
    rng = random.Random(seed if seed is not None else 0)

    n = max(1, int(recipe.length * sample_rate))
    samples: list[float] = []
    phase = 0.0
    freq = recipe.base_freq

    attack_n = int(recipe.attack * sample_rate)
    sustain_n = int(recipe.sustain * sample_rate)
    decay_n = max(1, n - attack_n - sustain_n)

    for i in range(n):
        t = i / sample_rate
        if i < attack_n and attack_n > 0:
            env = i / attack_n
        elif i < attack_n + sustain_n:
            env = 1.0 + recipe.punch * (1.0 - (i - attack_n) / max(1, sustain_n))
        else:
            d = i - attack_n - sustain_n
            env = max(0.0, 1.0 - d / decay_n)

        vib = 1.0 + recipe.vibrato_depth * math.sin(2 * math.pi * recipe.vibrato_speed * t)
        freq = max(20.0, freq + recipe.freq_slide / sample_rate)
        phase = (phase + (freq * vib) / sample_rate) % 1.0

        sig = _osc(recipe.wave, phase, recipe.duty, rng)
        if recipe.noise_amount and recipe.wave != "noise":
            sig = sig * (1.0 - recipe.noise_amount) + rng.uniform(-1.0, 1.0) * recipe.noise_amount

        samples.append(max(-1.0, min(1.0, sig * env * 0.45)))

    return samples


def generate_file(preset: str, out: Path, seed: int | None = None) -> Path:
    samples = synthesize(preset, seed=seed)
    write_wav_mono_s16(out, samples)
    write_meta(
        out,
        {
            "kind": "sfx",
            "backend": "builtin",
            "preset": preset,
            "seed": seed,
            "inspired_by": "sfxr / jsfxr / rFXGen presets",
            "license_note": "Generated procedurally by game-utils builtin synth; no third-party samples.",
        },
    )
    return out


def list_presets() -> list[str]:
    return sorted({v for v in PRESETS.values()})
