"""Sync generated and imported audio assets into a Godot project with ATTRIBUTION.json."""

from __future__ import annotations

import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from game_utils_audio.paths import (
    BGM_OUTPUT_DIR,
    DEFAULT_GODOT_AUDIO_DIR,
    SFX_LIBRARY_DIR,
    SFX_OUTPUT_DIR,
)
from game_utils_audio.sfx.catalog import load_catalog

AUDIO_EXTENSIONS = {".wav", ".ogg", ".mp3", ".flac", ".aiff", ".aif"}
ATTRIBUTION_FILENAME = "ATTRIBUTION.json"


@dataclass
class SyncResult:
    target_dir: Path
    dry_run: bool
    force: bool
    copied: list[str] = field(default_factory=list)
    overwritten: list[str] = field(default_factory=list)
    skipped: list[str] = field(default_factory=list)
    attribution_path: Path = field(default_factory=Path)
    attribution_entries: list[dict[str, Any]] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "target_dir": str(self.target_dir),
            "dry_run": self.dry_run,
            "force": self.force,
            "copied": self.copied,
            "overwritten": self.overwritten,
            "skipped": self.skipped,
            "attribution_path": str(self.attribution_path),
            "attribution_count": len(self.attribution_entries),
            "attribution_entries": self.attribution_entries,
        }


def _read_json_safe(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _find_file_meta(audio_path: Path) -> dict[str, Any]:
    candidates = [
        Path(str(audio_path) + ".meta.json"),
        audio_path.with_suffix(".meta.json"),
    ]
    for cand in candidates:
        meta = _read_json_safe(cand)
        if meta:
            return meta
    return {}


def _find_pack_meta(audio_path: Path, stop_root: Path) -> dict[str, Any]:
    cur = audio_path.parent
    resolved_stop = stop_root.resolve()
    while True:
        pack_meta = _read_json_safe(cur / "pack.meta.json")
        if pack_meta:
            return pack_meta
        if cur.resolve() == resolved_stop or cur.parent == cur:
            break
        cur = cur.parent
    return {}


def _catalog_by_id() -> dict[str, dict[str, Any]]:
    try:
        catalog = load_catalog()
    except FileNotFoundError:
        return {}
    return {
        str(item["id"]): item
        for item in catalog.get("collections", [])
        if isinstance(item, dict) and "id" in item
    }


def _build_attribution_entry(
    rel_target_path: str,
    kind: str,
    src_file: Path,
    bucket_root: Path,
    catalog_map: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    file_meta = _find_file_meta(src_file)
    pack_meta = _find_pack_meta(src_file, bucket_root)

    collection_id = str(file_meta.get("collection") or pack_meta.get("collection") or "")
    cat_item = catalog_map.get(collection_id, {})

    backend = file_meta.get("backend")
    source = (
        file_meta.get("source")
        or file_meta.get("upstream")
        or pack_meta.get("source")
        or pack_meta.get("upstream")
        or pack_meta.get("source_path")
        or cat_item.get("url")
        or backend
        or "local"
    )

    license_val = (
        file_meta.get("license")
        or file_meta.get("license_note")
        or pack_meta.get("license")
        or pack_meta.get("license_note")
        or cat_item.get("license")
    )
    if not license_val:
        if backend == "builtin":
            license_val = "procedural-cc0"
        else:
            license_val = "unknown"

    if "commercial" in file_meta:
        commercial: Any = file_meta["commercial"]
    elif "commercial" in pack_meta:
        commercial = pack_meta["commercial"]
    elif "commercial" in cat_item:
        commercial = cat_item["commercial"]
    elif backend in {"builtin", "jsfxr", "rfxgen"}:
        commercial = True
    else:
        commercial = None

    entry: dict[str, Any] = {
        "path": rel_target_path,
        "kind": kind,
        "source": str(source),
        "license": str(license_val),
        "commercial": commercial,
    }

    if pack_meta.get("pack"):
        entry["pack"] = str(pack_meta["pack"])
    if backend:
        entry["backend"] = str(backend)
    if file_meta.get("preset"):
        entry["preset"] = str(file_meta["preset"])
    if file_meta.get("prompt"):
        entry["prompt"] = str(file_meta["prompt"])
    return entry


def _is_under(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def sync_audio_assets(
    *,
    target_dir: Path | None = None,
    sfx_dir: Path | None = None,
    bgm_dir: Path | None = None,
    library_dir: Path | None = None,
    dry_run: bool = False,
    force: bool = False,
) -> SyncResult:
    """Sync audio files from output/sfx, output/sfx/library, and output/bgm into target_dir."""
    dest_root = (target_dir or DEFAULT_GODOT_AUDIO_DIR).expanduser().resolve()
    src_sfx = (sfx_dir or SFX_OUTPUT_DIR).expanduser().resolve()
    src_bgm = (bgm_dir or BGM_OUTPUT_DIR).expanduser().resolve()
    src_lib = (library_dir or SFX_LIBRARY_DIR).expanduser().resolve()

    attr_path = dest_root / ATTRIBUTION_FILENAME
    result = SyncResult(
        target_dir=dest_root,
        dry_run=dry_run,
        force=force,
        attribution_path=attr_path,
    )

    catalog_map = _catalog_by_id()

    existing_attr = _read_json_safe(attr_path)
    merged_by_path: dict[str, dict[str, Any]] = {}
    for item in existing_attr.get("assets", []):
        if isinstance(item, dict) and isinstance(item.get("path"), str):
            merged_by_path[item["path"]] = item

    buckets: list[tuple[str, Path, Path, Path | None]] = [
        ("sfx", src_sfx, dest_root / "sfx", src_lib),
        ("sfx-library", src_lib, dest_root / "sfx" / "library", None),
        ("bgm", src_bgm, dest_root / "bgm", None),
    ]

    for kind, bucket_src, bucket_dest, exclude_dir in buckets:
        if not bucket_src.is_dir():
            continue
        for src_file in sorted(bucket_src.rglob("*")):
            if not src_file.is_file():
                continue
            if exclude_dir is not None and _is_under(src_file, exclude_dir):
                continue
            if src_file.suffix.lower() not in AUDIO_EXTENSIONS:
                continue

            rel_in_bucket = src_file.relative_to(bucket_src)
            dest_file = bucket_dest / rel_in_bucket
            rel_target_str = dest_file.relative_to(dest_root).as_posix()

            entry = _build_attribution_entry(
                rel_target_str,
                kind,
                src_file,
                bucket_src,
                catalog_map,
            )

            if dest_file.exists():
                if force:
                    result.overwritten.append(rel_target_str)
                    merged_by_path[rel_target_str] = entry
                    if not dry_run:
                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(src_file, dest_file)
                else:
                    result.skipped.append(rel_target_str)
                    if rel_target_str not in merged_by_path:
                        merged_by_path[rel_target_str] = entry
            else:
                result.copied.append(rel_target_str)
                merged_by_path[rel_target_str] = entry
                if not dry_run:
                    dest_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src_file, dest_file)

    entries = [merged_by_path[k] for k in sorted(merged_by_path)]
    result.attribution_entries = entries

    if not dry_run:
        dest_root.mkdir(parents=True, exist_ok=True)
        doc = {
            "version": 1,
            "assets": entries,
        }
        attr_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return result
