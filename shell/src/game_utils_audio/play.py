"""Launch the Walk Sandbox Godot project for manual testing."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

from game_utils_audio.paths import DEFAULT_GODOT_PROJECT_DIR
from game_utils_audio.quality import find_godot_binary


def launch_test_game(
    project_dir: Path | None = None,
    *,
    godot_bin: str | None = None,
    editor: bool = False,
    skip_import: bool = False,
    dry_run: bool = False,
) -> list[str]:
    """Import assets, then replace this process with Godot.

    Default mode runs the project's main scene. ``editor=True`` opens the
    Godot editor instead. ``dry_run`` returns the launch command and does
    not start Godot.
    """
    project = (project_dir or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    if not (project / "project.godot").is_file():
        raise FileNotFoundError(f"Missing project.godot in {project}")

    godot = find_godot_binary(godot_bin)
    if not godot:
        raise RuntimeError(
            "Godot binary not found. Install Godot 4.6+ or set GODOT_BIN / pass --godot."
        )

    if not skip_import and not dry_run:
        print(f"Importing {project.name} ...")
        imported = subprocess.run(
            [godot, "--headless", "--path", str(project), "--import", "--quit-after", "3"],
            check=False,
        )
        if imported.returncode != 0:
            print(f"warning: asset import exited {imported.returncode}; launching anyway")

    cmd = [godot, "--path", str(project)]
    if editor:
        cmd = [godot, "--editor", "--path", str(project)]

    if dry_run:
        return cmd

    mode = "editor" if editor else "game"
    print(f"Starting {project.name} ({mode}) ...")
    os.execv(cmd[0], cmd)
    return cmd
