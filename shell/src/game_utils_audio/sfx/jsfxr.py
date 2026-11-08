"""Optional jsfxr backend (Node.js)."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

from game_utils_audio.paths import JSFXR_DIR
from game_utils_audio.wavutil import write_meta

# jsfxr preset names
JSFXR_PRESETS = {
    "coin": "pickupCoin",
    "pickupcoin": "pickupCoin",
    "laser": "laserShoot",
    "lasershoot": "laserShoot",
    "explosion": "explosion",
    "powerup": "powerUp",
    "hit": "hitHurt",
    "hithurt": "hitHurt",
    "jump": "jump",
    "blip": "blipSelect",
    "blipselect": "blipSelect",
    "click": "click",
    "synth": "synth",
    "tone": "tone",
    "random": "random",
}

GENERATE_SCRIPT = """\
const fs = require("fs");
const path = require("path");
const { sfxr } = require("jsfxr");

const preset = process.argv[2];
const out = process.argv[3];
const sound = sfxr.generate(preset);
const wave = sfxr.toWave(sound);
const m = wave.dataURI.match(/^data:.+;base64,(.*)$/);
if (!m) {
  console.error("Failed to encode WAV");
  process.exit(1);
}
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, Buffer.from(m[1], "base64"));
console.log(out);
"""


def node_available() -> bool:
    return shutil.which("node") is not None and shutil.which("npm") is not None


def is_ready() -> bool:
    return node_available() and (JSFXR_DIR / "node_modules" / "jsfxr").exists()


def setup() -> None:
    if not node_available():
        raise RuntimeError(
            "Node.js / npm not found. Install Node 18+ (e.g. `brew install node`), then re-run setup."
        )
    JSFXR_DIR.mkdir(parents=True, exist_ok=True)
    pkg = JSFXR_DIR / "package.json"
    if not pkg.exists():
        pkg.write_text(
            json.dumps(
                {
                    "name": "game-utils-jsfxr",
                    "private": True,
                    "dependencies": {"jsfxr": "^1.4.0"},
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    (JSFXR_DIR / "generate.js").write_text(GENERATE_SCRIPT, encoding="utf-8")
    subprocess.run(["npm", "install"], cwd=JSFXR_DIR, check=True)


def generate_file(preset: str, out: Path, seed: int | None = None) -> Path:
    if not is_ready():
        raise RuntimeError("jsfxr backend not ready. Run: gu-audio sfx setup-jsfxr")

    key = preset.lower().replace("_", "").replace("-", "")
    js_preset = JSFXR_PRESETS.get(key)
    if not js_preset:
        raise ValueError(f"Unknown jsfxr preset '{preset}'. Known: {', '.join(sorted(set(JSFXR_PRESETS)))}")

    # jsfxr presets are random each call; seed is recorded for our meta only
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["node", str(JSFXR_DIR / "generate.js"), js_preset, str(out)],
        cwd=JSFXR_DIR,
        check=True,
    )
    write_meta(
        out,
        {
            "kind": "sfx",
            "backend": "jsfxr",
            "preset": preset,
            "jsfxr_preset": js_preset,
            "seed": seed,
            "upstream": "https://github.com/chr15m/jsfxr",
        },
    )
    return out
