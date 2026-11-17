from __future__ import annotations

from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = SHELL_ROOT.parent
OUTPUT_DIR = REPO_ROOT / "output"
SFX_OUTPUT_DIR = OUTPUT_DIR / "sfx"
SFX_LIBRARY_DIR = SFX_OUTPUT_DIR / "library"
BGM_OUTPUT_DIR = OUTPUT_DIR / "bgm"
DEFAULT_GODOT_AUDIO_DIR = REPO_ROOT / "prototypes" / "walk-sandbox" / "assets" / "audio"
VENDORS_DIR = SHELL_ROOT / "vendors"
ACESTEP_DIR = VENDORS_DIR / "ACE-Step-1.5"
JSFXR_DIR = SHELL_ROOT / "sfx_node"
META_SUFFIX = ".meta.json"


def ensure_output_dirs() -> None:
    SFX_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    BGM_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    VENDORS_DIR.mkdir(parents=True, exist_ok=True)
