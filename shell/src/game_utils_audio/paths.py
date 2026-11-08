from __future__ import annotations

from pathlib import Path

SHELL_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = SHELL_ROOT.parent
OUTPUT_DIR = REPO_ROOT / "output"
SFX_OUTPUT_DIR = OUTPUT_DIR / "sfx"
BGM_OUTPUT_DIR = OUTPUT_DIR / "bgm"
VENDORS_DIR = SHELL_ROOT / "vendors"
ACESTEP_DIR = VENDORS_DIR / "ACE-Step-1.5"
JSFXR_DIR = SHELL_ROOT / "sfx_node"
META_SUFFIX = ".meta.json"


def ensure_output_dirs() -> None:
    SFX_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    BGM_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    VENDORS_DIR.mkdir(parents=True, exist_ok=True)
