"""Manage shared Godot addons distribution (`gu addons sync`) and starter scaffolding (`gu init`)."""

from __future__ import annotations

import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence

from game_utils_audio.paths import (
    DEFAULT_GODOT_PROJECT_DIR,
    GODOT_ADDONS_DIR,
    GODOT_STARTER_TEMPLATE_DIR,
)

DEFAULT_ADDONS: tuple[str, ...] = ("gu_core", "gu_gameplay")
SKIP_FILENAMES = {".DS_Store"}


@dataclass
class AddonSyncResult:
    target_project: Path
    addons: list[str]
    dry_run: bool
    prune: bool
    copied: list[str] = field(default_factory=list)
    updated: list[str] = field(default_factory=list)
    unchanged: list[str] = field(default_factory=list)
    pruned: list[str] = field(default_factory=list)


@dataclass
class InitProjectResult:
    target_dir: Path
    project_name: str
    dry_run: bool
    created_files: list[str] = field(default_factory=list)
    addon_sync: AddonSyncResult | None = None


def _should_skip_source(path: Path) -> bool:
    if path.name in SKIP_FILENAMES:
        return True
    suffix = path.suffix.lower()
    if suffix == ".uid":
        return True
    # Keep editor metadata local, but ship localization CSV keep-imports with the template.
    if suffix == ".import" and not path.name.lower().endswith(".csv.import"):
        return True
    return False


def sync_addons(
    target_project: Path | None = None,
    *,
    addons_src: Path | None = None,
    addons: Sequence[str] | None = None,
    dry_run: bool = False,
    prune: bool = False,
) -> AddonSyncResult:
    """Copy shared Godot addons from godot/addons/ into <target_project>/addons/."""
    dest_project = (target_project or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    src_root = (addons_src or GODOT_ADDONS_DIR).expanduser().resolve()
    addon_names = list(addons) if addons else list(DEFAULT_ADDONS)

    if not src_root.is_dir():
        raise FileNotFoundError(f"Shared addons directory not found: {src_root}")

    result = AddonSyncResult(
        target_project=dest_project,
        addons=addon_names,
        dry_run=dry_run,
        prune=prune,
    )

    for addon_name in addon_names:
        src_addon = src_root / addon_name
        if not src_addon.is_dir():
            raise FileNotFoundError(f"Unknown addon '{addon_name}' in {src_root}")

        dest_addon = dest_project / "addons" / addon_name
        expected_rel_paths: set[Path] = set()

        for src_file in sorted(src_addon.rglob("*")):
            if not src_file.is_file() or _should_skip_source(src_file):
                continue
            rel = src_file.relative_to(src_addon)
            expected_rel_paths.add(rel)
            dest_file = dest_addon / rel
            rel_label = f"addons/{addon_name}/{rel.as_posix()}"

            if dest_file.exists():
                if dest_file.read_bytes() == src_file.read_bytes():
                    result.unchanged.append(rel_label)
                else:
                    result.updated.append(rel_label)
                    if not dry_run:
                        dest_file.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(src_file, dest_file)
            else:
                result.copied.append(rel_label)
                if not dry_run:
                    dest_file.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src_file, dest_file)

        if prune and dest_addon.is_dir():
            for existing in sorted(dest_addon.rglob("*")):
                if not existing.is_file() or _should_skip_source(existing):
                    continue
                rel = existing.relative_to(dest_addon)
                if rel not in expected_rel_paths:
                    rel_label = f"addons/{addon_name}/{rel.as_posix()}"
                    result.pruned.append(rel_label)
                    if not dry_run:
                        existing.unlink()

    return result


def init_godot_project(
    target_dir: Path,
    *,
    name: str | None = None,
    template_dir: Path | None = None,
    addons_src: Path | None = None,
    addons: Sequence[str] | None = None,
    force: bool = False,
    dry_run: bool = False,
) -> InitProjectResult:
    """Scaffold a new Godot 4.6 project with shared addons and starter UI/test structure."""
    dest_dir = target_dir.expanduser().resolve()
    tpl_root = (template_dir or GODOT_STARTER_TEMPLATE_DIR).expanduser().resolve()
    if not tpl_root.is_dir():
        raise FileNotFoundError(f"Starter template directory not found: {tpl_root}")

    if (dest_dir / "project.godot").exists() and not force:
        raise FileExistsError(
            f"Target already contains project.godot: {dest_dir} (pass --force to overwrite)"
        )

    project_name = (name or dest_dir.name or "New Godot Game").strip()
    result = InitProjectResult(
        target_dir=dest_dir,
        project_name=project_name,
        dry_run=dry_run,
    )

    for src_file in sorted(tpl_root.rglob("*")):
        if not src_file.is_file() or _should_skip_source(src_file):
            continue
        rel = src_file.relative_to(tpl_root)
        if src_file.name == "project.godot.tmpl":
            dest_rel = rel.with_name("project.godot")
            rendered = src_file.read_text(encoding="utf-8").replace("{{PROJECT_NAME}}", project_name)
            result.created_files.append(dest_rel.as_posix())
            if not dry_run:
                out_path = dest_dir / dest_rel
                out_path.parent.mkdir(parents=True, exist_ok=True)
                out_path.write_text(rendered, encoding="utf-8")
        else:
            result.created_files.append(rel.as_posix())
            if not dry_run:
                out_path = dest_dir / rel
                out_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src_file, out_path)

    result.addon_sync = sync_addons(
        target_project=dest_dir,
        addons_src=addons_src,
        addons=addons,
        dry_run=dry_run,
        prune=False,
    )
    return result
