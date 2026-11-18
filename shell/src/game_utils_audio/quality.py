"""Unified project quality checks (`gu check`) and headless export (`gu export`)."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from game_utils_audio.godot_project import AddonSyncResult, sync_addons
from game_utils_audio.paths import DEFAULT_GODOT_PROJECT_DIR, SHELL_ROOT

MACOS_GODOT_DEFAULT = Path("/Applications/Godot.app/Contents/MacOS/Godot")


@dataclass
class CheckStep:
    name: str
    ok: bool
    detail: str = ""


@dataclass
class CheckReport:
    project_dir: Path
    steps: list[CheckStep] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(s.ok for s in self.steps)


def find_godot_binary(explicit: str | None = None) -> str | None:
    if explicit:
        return explicit
    env_bin = os.environ.get("GODOT_BIN")
    if env_bin:
        return env_bin
    on_path = shutil.which("godot") or shutil.which("godot4")
    if on_path:
        return on_path
    if MACOS_GODOT_DEFAULT.is_file():
        return str(MACOS_GODOT_DEFAULT)
    return None


def check_addons_parity(
    target_project: Path | None = None,
    *,
    addons_src: Path | None = None,
) -> tuple[bool, AddonSyncResult]:
    res = sync_addons(
        target_project=target_project or DEFAULT_GODOT_PROJECT_DIR,
        addons_src=addons_src,
        dry_run=True,
        prune=True,
    )
    in_sync = not res.copied and not res.updated and not res.pruned
    return in_sync, res


def parse_export_presets(project_dir: Path) -> list[str]:
    cfg = project_dir / "export_presets.cfg"
    if not cfg.is_file():
        return []
    text = cfg.read_text(encoding="utf-8", errors="replace")
    presets: list[str] = []
    for match in re.finditer(r'(?m)^name="([^"]+)"\s*$', text):
        presets.append(match.group(1))
    return presets


def _run_cmd(cmd: list[str], cwd: Path | None = None) -> tuple[int, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stdout


def run_godot_tests(
    project_dir: Path | None = None,
    *,
    godot_bin: str | None = None,
    skip_godot: bool = False,
) -> CheckReport:
    """Headless import plus `tests/test_runner.gd`, including the play-flow smoke."""
    proj = (project_dir or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    report = CheckReport(project_dir=proj)
    if skip_godot:
        report.steps.append(CheckStep("godot-tests", True, "skipped"))
        return report

    godot = find_godot_binary(godot_bin)
    if not godot:
        report.steps.append(CheckStep("godot-binary", False, "Godot binary not found (set --godot or GODOT_BIN)"))
        return report

    imp_code, imp_out = _run_cmd([godot, "--headless", "--path", str(proj), "--import", "--quit-after", "3"])
    report.steps.append(CheckStep("godot-import", imp_code == 0 and "SCRIPT ERROR" not in imp_out, f"exit={imp_code}"))

    test_script = proj / "tests" / "test_runner.gd"
    if not test_script.is_file():
        report.steps.append(CheckStep("godot-tests", False, f"missing {test_script}"))
        return report
    t_code, t_out = _run_cmd([godot, "--headless", "--path", str(proj), "--script", "res://tests/test_runner.gd"])
    summary = next((ln for ln in t_out.splitlines() if "[PASS]" in ln or "[FAIL]" in ln), f"exit={t_code}")
    report.steps.append(CheckStep("godot-tests", t_code == 0 and "[PASS]" in t_out and "SCRIPT ERROR" not in t_out, summary))
    return report


def run_project_check(
    project_dir: Path | None = None,
    *,
    godot_bin: str | None = None,
    skip_pytest: bool = False,
    skip_godot: bool = False,
    frames: int = 30,
) -> CheckReport:
    proj = (project_dir or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    report = CheckReport(project_dir=proj)

    in_sync, sync_res = check_addons_parity(proj)
    if in_sync:
        report.steps.append(CheckStep("addons-parity", True, f"{len(sync_res.unchanged)} files in sync"))
    else:
        drift = len(sync_res.copied) + len(sync_res.updated) + len(sync_res.pruned)
        report.steps.append(CheckStep("addons-parity", False, f"{drift} file(s) out of sync; run `gu addons sync`"))

    if not skip_pytest:
        code, out = _run_cmd([sys.executable, "-m", "pytest"], cwd=SHELL_ROOT)
        last_line = out.strip().splitlines()[-1] if out.strip() else f"exit={code}"
        report.steps.append(CheckStep("pytest", code == 0, last_line))

    if not skip_godot:
        godot = find_godot_binary(godot_bin)
        if not godot:
            report.steps.append(CheckStep("godot-binary", False, "Godot binary not found (set --godot or GODOT_BIN)"))
            return report

        imp_code, imp_out = _run_cmd([godot, "--headless", "--path", str(proj), "--import", "--quit-after", "3"])
        report.steps.append(CheckStep("godot-import", imp_code == 0 and "SCRIPT ERROR" not in imp_out, f"exit={imp_code}"))

        test_script = proj / "tests" / "test_runner.gd"
        if test_script.is_file():
            t_code, t_out = _run_cmd([godot, "--headless", "--path", str(proj), "--script", "res://tests/test_runner.gd"])
            summary = next((ln for ln in t_out.splitlines() if "[PASS]" in ln or "[FAIL]" in ln), f"exit={t_code}")
            report.steps.append(CheckStep("godot-tests", t_code == 0 and "[PASS]" in t_out, summary))

        smoke_code, smoke_out = _run_cmd([godot, "--headless", "--path", str(proj), "--quit-after", str(max(1, frames))])
        smoke_ok = smoke_code == 0 and "SCRIPT ERROR" not in smoke_out
        report.steps.append(CheckStep("godot-smoke", smoke_ok, f"frames={frames} exit={smoke_code}"))

    return report


def export_godot_project(
    project_dir: Path | None,
    *,
    preset: str,
    out_path: Path,
    godot_bin: str | None = None,
    debug: bool = False,
    dry_run: bool = False,
) -> list[str]:
    proj = (project_dir or DEFAULT_GODOT_PROJECT_DIR).expanduser().resolve()
    if not (proj / "project.godot").is_file():
        raise FileNotFoundError(f"Missing project.godot in {proj}")

    presets = parse_export_presets(proj)
    if not presets:
        raise FileNotFoundError(
            f"Missing or empty export_presets.cfg in {proj}. Configure export presets in Godot first."
        )
    if preset not in presets:
        raise KeyError(f"Unknown export preset '{preset}'. Available: {', '.join(presets)}")

    godot = find_godot_binary(godot_bin)
    if not godot:
        if dry_run:
            godot = "godot"
        else:
            raise RuntimeError("Godot binary not found (set --godot or GODOT_BIN)")

    dest = out_path.expanduser().resolve()
    flag = "--export-debug" if debug else "--export-release"
    cmd = [godot, "--headless", "--path", str(proj), flag, preset, str(dest)]

    if not dry_run:
        dest.parent.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(cmd, check=False)
        if proc.returncode != 0:
            raise RuntimeError(f"Godot export failed with exit code {proc.returncode}")

    return cmd
