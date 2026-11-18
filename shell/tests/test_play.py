"""Unit tests for the test-game launcher."""

from __future__ import annotations

from pathlib import Path

import pytest

from game_utils_audio import cli
from game_utils_audio.play import launch_test_game


def test_launch_dry_run_runs_main_scene(tmp_path: Path) -> None:
    project = tmp_path / "game"
    project.mkdir()
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")

    cmd = launch_test_game(
        project,
        godot_bin="/usr/bin/godot",
        dry_run=True,
    )
    assert cmd == ["/usr/bin/godot", "--path", str(project.resolve())]


def test_launch_dry_run_editor_flag(tmp_path: Path) -> None:
    project = tmp_path / "game"
    project.mkdir()
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")

    cmd = launch_test_game(
        project,
        godot_bin="/usr/bin/godot",
        editor=True,
        dry_run=True,
    )
    assert cmd[1:3] == ["--editor", "--path"]


def test_launch_missing_project(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError):
        launch_test_game(tmp_path, godot_bin="/usr/bin/godot", dry_run=True)


def test_launch_missing_godot(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = tmp_path / "game"
    project.mkdir()
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    monkeypatch.delenv("GODOT_BIN", raising=False)
    monkeypatch.setattr("game_utils_audio.play.find_godot_binary", lambda explicit=None: None)

    with pytest.raises(RuntimeError, match="Godot binary not found"):
        launch_test_game(project, dry_run=True)


def test_cli_play_dry_run_exits_zero(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    project = tmp_path / "game"
    project.mkdir()
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")

    with pytest.raises(SystemExit) as exc:
        cli.main(
            [
                "play",
                "--project",
                str(project),
                "--godot",
                "/usr/bin/godot",
                "--dry-run",
                "--skip-import",
            ]
        )
    assert exc.value.code == 0
    captured = capsys.readouterr()
    assert "/usr/bin/godot" in captured.out
    assert "--path" in captured.out
