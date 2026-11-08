"""Curated realistic SFX collection catalog (not procedural beeps)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from game_utils_audio.paths import SHELL_ROOT

CATALOG_PATH = SHELL_ROOT / "data" / "sfx_collections.json"


def load_catalog() -> dict[str, Any]:
    if not CATALOG_PATH.exists():
        raise FileNotFoundError(f"Missing catalog: {CATALOG_PATH}")
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def list_collections(tag: str | None = None) -> list[dict[str, Any]]:
    items = load_catalog()["collections"]
    if tag:
        t = tag.lower()
        items = [c for c in items if t in [x.lower() for x in c.get("tags", [])]]
    return items


def get_collection(collection_id: str) -> dict[str, Any]:
    for item in list_collections():
        if item["id"] == collection_id:
            return item
    raise KeyError(f"Unknown collection id: {collection_id}")


def list_needs() -> list[dict[str, Any]]:
    return load_catalog().get("needs", [])
