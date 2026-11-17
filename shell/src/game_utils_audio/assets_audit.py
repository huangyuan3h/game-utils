"""Project-wide asset provenance audit and CREDITS.md generator."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from game_utils_audio.paths import DEFAULT_GODOT_PROJECT_DIR

CATEGORY_EXTENSIONS: dict[str, set[str]] = {
    "audio": {".wav", ".ogg", ".mp3", ".flac", ".aiff", ".aif"},
    "model": {".glb", ".gltf", ".fbx", ".obj"},
    "texture": {".png", ".jpg", ".jpeg", ".webp", ".svg"},
}
ALL_ASSET_EXTENSIONS = set().union(*CATEGORY_EXTENSIONS.values())
ATTRIBUTION_JSON_NAME = "ASSETS_ATTRIBUTION.json"
CREDITS_MD_NAME = "CREDITS.md"
LICENSE_FILENAMES = (
    "LICENSE",
    "LICENSE.txt",
    "LICENSE.md",
    "README",
    "README.txt",
    "README.md",
)


@dataclass
class AssetAuditResult:
    project_dir: Path
    assets_dir: Path
    entries: list[dict[str, Any]] = field(default_factory=list)
    counts_by_category: dict[str, int] = field(default_factory=dict)
    unknown_licenses: list[str] = field(default_factory=list)
    non_commercial: list[str] = field(default_factory=list)
    attribution_path: Path = field(default_factory=Path)

    @property
    def ok(self) -> bool:
        return not self.unknown_licenses and not self.non_commercial


def _classify_asset(path: Path) -> str | None:
    ext = path.suffix.lower()
    for category, exts in CATEGORY_EXTENSIONS.items():
        if ext in exts:
            return category
    return None


def _read_json_safe(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _detect_license_from_text(text: str) -> tuple[str | None, bool | None]:
    low = text.lower()
    if "cc0" in low or "zero/1.0" in low or "public domain dedication" in low:
        return "CC0", True
    if re.search(r"\bcc[\s_-]?by[\s_-]?nc", low) or "non-commercial" in low or "noncommercial" in low:
        return "CC-BY-NC", False
    if re.search(r"\bcc[\s_-]?by[\s_-]?sa", low):
        return "CC-BY-SA", True
    if re.search(r"\bcc[\s_-]?by\b", low):
        return "CC-BY", True
    if "apache license" in low or "apache-2.0" in low:
        return "Apache-2.0", True
    if "mit license" in low or "permission is hereby granted, free of charge" in low:
        return "MIT", True
    if "placeholder" in low and ("swap later" in low or "prototype" in low):
        return "prototype-placeholder", True
    return None, None


def _find_nearest_license(asset_path: Path, stop_root: Path) -> tuple[str | None, bool | None, str | None]:
    cur = asset_path.parent
    resolved_stop = stop_root.resolve()
    while True:
        for fname in LICENSE_FILENAMES:
            cand = cur / fname
            if cand.is_file():
                text = cand.read_text(encoding="utf-8", errors="replace")
                lic, comm = _detect_license_from_text(text)
                if lic is not None:
                    return lic, comm, cand.relative_to(stop_root.parent).as_posix()
        if cur.resolve() == resolved_stop or cur.parent == cur:
            break
        cur = cur.parent
    return None, None, None


def _find_sidecar_meta(asset_path: Path) -> dict[str, Any]:
    for cand in (Path(str(asset_path) + ".meta.json"), asset_path.with_suffix(".meta.json")):
        meta = _read_json_safe(cand)
        if meta:
            return meta
    return {}


def _find_pack_meta(asset_path: Path, stop_root: Path) -> dict[str, Any]:
    cur = asset_path.parent
    resolved_stop = stop_root.resolve()
    while True:
        meta = _read_json_safe(cur / "pack.meta.json")
        if meta:
            return meta
        if cur.resolve() == resolved_stop or cur.parent == cur:
            break
        cur = cur.parent
    return {}


def _load_existing_audio_attribution(project_dir: Path) -> dict[str, dict[str, Any]]:
    by_rel: dict[str, dict[str, Any]] = {}
    audio_attr = project_dir / "assets" / "audio" / "ATTRIBUTION.json"
    doc = _read_json_safe(audio_attr)
    for item in doc.get("assets", []):
        if isinstance(item, dict) and isinstance(item.get("path"), str):
            by_rel[f"assets/audio/{item['path']}"] = item
    return by_rel


def audit_project_assets(
    project_dir: Path | None = None,
    *,
    write: bool = False,
) -> AssetAuditResult:
    proj = (project_dir or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    assets_dir = proj / "assets"
    attr_path = proj / ATTRIBUTION_JSON_NAME
    result = AssetAuditResult(
        project_dir=proj,
        assets_dir=assets_dir,
        counts_by_category={"audio": 0, "model": 0, "texture": 0},
        attribution_path=attr_path,
    )

    if not assets_dir.is_dir():
        if write:
            attr_path.write_text(json.dumps({"version": 1, "assets": []}, indent=2) + "\n", encoding="utf-8")
        return result

    existing_audio = _load_existing_audio_attribution(proj)

    for file_path in sorted(assets_dir.rglob("*")):
        if not file_path.is_file():
            continue
        if file_path.name == ".DS_Store" or file_path.suffix.lower() == ".import":
            continue
        category = _classify_asset(file_path)
        if category is None:
            continue

        rel_str = file_path.relative_to(proj).as_posix()
        result.counts_by_category[category] = result.counts_by_category.get(category, 0) + 1

        meta = _find_sidecar_meta(file_path)
        pack_meta = _find_pack_meta(file_path, assets_dir)
        audio_item = existing_audio.get(rel_str, {})
        lic_from_txt, comm_from_txt, lic_file_rel = _find_nearest_license(file_path, assets_dir)

        source = (
            meta.get("source")
            or meta.get("upstream")
            or pack_meta.get("source")
            or pack_meta.get("upstream")
            or audio_item.get("source")
            or lic_file_rel
            or "local"
        )
        license_val = (
            meta.get("license")
            or pack_meta.get("license")
            or audio_item.get("license")
            or lic_from_txt
            or "unknown"
        )

        if "commercial" in meta:
            commercial: Any = meta["commercial"]
        elif "commercial" in pack_meta:
            commercial = pack_meta["commercial"]
        elif "commercial" in audio_item:
            commercial = audio_item["commercial"]
        elif comm_from_txt is not None:
            commercial = comm_from_txt
        elif str(license_val) in {"CC0", "MIT", "Apache-2.0", "CC-BY", "CC-BY-SA", "procedural-cc0"}:
            commercial = True
        else:
            commercial = None

        entry = {
            "path": rel_str,
            "category": category,
            "source": str(source),
            "license": str(license_val),
            "commercial": commercial,
        }
        result.entries.append(entry)

        if entry["license"] == "unknown":
            result.unknown_licenses.append(rel_str)
        if entry["commercial"] is False:
            result.non_commercial.append(rel_str)

    if write:
        doc = {
            "version": 1,
            "project": proj.name,
            "counts": result.counts_by_category,
            "assets": result.entries,
        }
        attr_path.write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return result


def render_credits_markdown(result: AssetAuditResult) -> str:
    lines = [
        f"# Credits — {result.project_dir.name}",
        "",
        "Generated by `gu assets credits`.",
        "",
        "## Summary",
        "",
        f"- Total assets: {len(result.entries)}",
        f"- Audio: {result.counts_by_category.get('audio', 0)}",
        f"- Models: {result.counts_by_category.get('model', 0)}",
        f"- Textures/UI: {result.counts_by_category.get('texture', 0)}",
        "",
        "## Assets",
        "",
        "| Path | Category | License | Commercial | Source |",
        "|------|----------|---------|------------|--------|",
    ]
    for e in result.entries:
        comm = "yes" if e["commercial"] is True else ("no" if e["commercial"] is False else "unknown")
        lines.append(
            f"| `{e['path']}` | {e['category']} | {e['license']} | {comm} | {e['source']} |"
        )
    lines.append("")
    return "\n".join(lines)


def write_credits(project_dir: Path | None = None, out_path: Path | None = None) -> tuple[Path, AssetAuditResult]:
    res = audit_project_assets(project_dir, write=False)
    target = (out_path or (res.project_dir / CREDITS_MD_NAME)).expanduser().resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_credits_markdown(res), encoding="utf-8")
    return target, res
