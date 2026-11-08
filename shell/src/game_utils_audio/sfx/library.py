"""Local library helpers: open curated sources, import downloaded packs."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any

from game_utils_audio.paths import OUTPUT_DIR, REPO_ROOT, ensure_output_dirs
from game_utils_audio.sfx.catalog import get_collection, list_collections, list_needs
LIBRARY_DIR = OUTPUT_DIR / "sfx" / "library"
INCOMING_DIR = REPO_ROOT / "library" / "sfx" / "incoming"


def ensure_library_dirs() -> None:
    ensure_output_dirs()
    LIBRARY_DIR.mkdir(parents=True, exist_ok=True)
    INCOMING_DIR.mkdir(parents=True, exist_ok=True)


def open_url(url: str) -> None:
    if sys.platform == "darwin":
        subprocess.run(["open", url], check=False)
    elif sys.platform.startswith("linux"):
        opener = shutil.which("xdg-open")
        if opener:
            subprocess.run([opener, url], check=False)
        else:
            print(url)
    else:
        print(url)


def print_collections(tag: str | None = None) -> None:
    items = list_collections(tag)
    if not items:
        print("No collections matched.")
        return
    for c in items:
        print(f"- {c['id']}")
        print(f"  {c['name']}")
        print(f"  license: {c['license']} | commercial: {c['commercial']}")
        print(f"  why: {c['why']}")
        print(f"  url: {c['url']}")
        print()


def print_needs() -> None:
    for need in list_needs():
        print(f"- {need['id']}: {need['title']}")
        print(f"  try: {', '.join(need['suggest'])}")


def open_collection(collection_id: str) -> dict[str, Any]:
    item = get_collection(collection_id)
    print(f"Opening: {item['name']}")
    print(f"License: {item['license']}")
    print(f"Note: {item['why']}")
    open_url(item["url"])
    return item


def open_need(need_id: str) -> None:
    needs = {n["id"]: n for n in list_needs()}
    if need_id not in needs:
        raise KeyError(f"Unknown need '{need_id}'. Try: {', '.join(needs)}")
    need = needs[need_id]
    print(f"Need: {need['title']}")
    print("Suggested collections:")
    for cid in need["suggest"]:
        try:
            c = get_collection(cid)
            print(f"  - {c['id']}: {c['name']} ({c['license']})")
        except KeyError:
            print(f"  - {cid}")
    first = need["suggest"][0]
    print(f"\nOpening first suggestion: {first}")
    open_collection(first)


def _safe_name(name: str) -> str:
    keep = []
    for ch in name.strip().replace(" ", "_"):
        if ch.isalnum() or ch in {"_", "-", "."}:
            keep.append(ch)
    return "".join(keep) or "pack"


def import_path(src: Path, pack_name: str | None = None) -> Path:
    """Copy a folder or unzip a zip into output/sfx/library/<pack>/."""
    ensure_library_dirs()
    src = src.expanduser().resolve()
    if not src.exists():
        raise FileNotFoundError(src)

    name = _safe_name(pack_name or src.stem)
    dest = LIBRARY_DIR / name
    if dest.exists():
        raise FileExistsError(f"Already imported: {dest} (delete it or choose another --name)")

    if src.is_file() and src.suffix.lower() == ".zip":
        dest.mkdir(parents=True)
        with zipfile.ZipFile(src, "r") as zf:
            zf.extractall(dest)
    elif src.is_dir():
        shutil.copytree(src, dest)
    else:
        raise ValueError("Import source must be a directory or .zip")

    meta = {
        "kind": "sfx-library-pack",
        "pack": name,
        "source_path": str(src),
        "note": "Imported local pack. Keep original license files inside the pack.",
    }
    (dest / "pack.meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")

    audio_ext = {".wav", ".mp3", ".ogg", ".flac", ".aiff", ".aif"}
    count = sum(1 for p in dest.rglob("*") if p.suffix.lower() in audio_ext)
    print(f"Imported → {dest}")
    print(f"Audio files found: {count}")
    print("Tip: keep LICENSE / readme from the original pack inside this folder.")
    return dest


def list_imported() -> list[Path]:
    ensure_library_dirs()
    return sorted([p for p in LIBRARY_DIR.iterdir() if p.is_dir()])


def print_imported() -> None:
    packs = list_imported()
    if not packs:
        print(f"No local packs yet. Download a collection, then:")
        print(f"  gu-audio sfx import ~/Downloads/some-pack.zip")
        print(f"Or drop files into: {INCOMING_DIR}")
        return
    for p in packs:
        audio_ext = {".wav", ".mp3", ".ogg", ".flac"}
        n = sum(1 for f in p.rglob("*") if f.suffix.lower() in audio_ext)
        print(f"- {p.name} ({n} audio files) → {p}")
