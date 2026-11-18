"""Unit tests for `gu check`, `gu export`, and CLI subcommands."""

from __future__ import annotations

from pathlib import Path

import pytest

from game_utils_audio import cli
from game_utils_audio.quality import (
    check_addons_parity,
    export_godot_project,
    parse_export_presets,
    run_project_check,
)


def test_addons_parity_matches_walk_sandbox() -> None:
    in_sync, res = check_addons_parity()
    assert in_sync, f"Out of sync: copied={res.copied} updated={res.updated} pruned={res.pruned}"


def test_parse_export_presets_and_export_dry_run(tmp_path: Path) -> None:
    proj = tmp_path / "game"
    proj.mkdir()
    (proj / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    (proj / "export_presets.cfg").write_text(
        '[preset.0]\nname="macOS"\nplatform="macOS"\n\n[preset.1]\nname="Web"\nplatform="Web"\n',
        encoding="utf-8",
    )

    assert parse_export_presets(proj) == ["macOS", "Web"]

    cmd = export_godot_project(
        proj,
        preset="macOS",
        out_path=tmp_path / "dist" / "game.dmg",
        godot_bin="/usr/bin/godot",
        dry_run=True,
    )
    assert "--export-release" in cmd
    assert "macOS" in cmd

    with pytest.raises(KeyError):
        export_godot_project(
            proj,
            preset="Linux",
            out_path=tmp_path / "dist" / "game.x86_64",
            dry_run=True,
        )


def test_run_project_check_skip_subprocesses() -> None:
    report = run_project_check(skip_pytest=True, skip_godot=True)
    assert report.ok
    assert report.steps[0].name == "addons-parity"


def test_cli_test_skip_godot_exits_zero() -> None:
    with pytest.raises(SystemExit) as exc:
        cli.main(["test", "--skip-godot"])
    assert exc.value.code == 0


def test_cli_check_skip_flags_exits_zero() -> None:
    with pytest.raises(SystemExit) as exc:
        cli.main(["check", "--skip-pytest", "--skip-godot"])
    assert exc.value.code == 0
