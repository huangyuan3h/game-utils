"""Unit tests for `gu addons sync` and `gu init` starter scaffolding."""

from __future__ import annotations

from pathlib import Path

import pytest

from game_utils_audio import cli
from game_utils_audio.godot_project import init_godot_project, sync_addons


@pytest.fixture()
def mock_godot_repo(tmp_path: Path) -> dict[str, Path]:
    addons_src = tmp_path / "godot" / "addons"
    core_dir = addons_src / "gu_core"
    gameplay_dir = addons_src / "gu_gameplay"
    core_dir.mkdir(parents=True)
    gameplay_dir.mkdir(parents=True)

    (core_dir / "plugin.cfg").write_text('[plugin]\nname="gu_core"\n', encoding="utf-8")
    (core_dir / "core.gd").write_text("extends Node\n", encoding="utf-8")
    (gameplay_dir / "plugin.cfg").write_text('[plugin]\nname="gu_gameplay"\n', encoding="utf-8")
    (gameplay_dir / "actor.gd").write_text("extends Node3D\n", encoding="utf-8")

    tpl_dir = tmp_path / "godot" / "templates" / "starter"
    (tpl_dir / "scenes").mkdir(parents=True)
    (tpl_dir / "scripts").mkdir(parents=True)
    (tpl_dir / "project.godot.tmpl").write_text(
        '[application]\nconfig/name="{{PROJECT_NAME}}"\n',
        encoding="utf-8",
    )
    (tpl_dir / "export_presets.cfg.tmpl").write_text(
        '[preset.0]\nname="macOS"\n\n[preset.0.options]\n'
        'application/bundle_identifier="{{BUNDLE_ID}}"\n',
        encoding="utf-8",
    )
    (tpl_dir / "scenes" / "main.tscn").write_text("[gd_scene format=3]\n", encoding="utf-8")
    (tpl_dir / "scripts" / "main.gd").write_text("extends Node3D\n", encoding="utf-8")

    return {
        "addons_src": addons_src,
        "tpl_dir": tpl_dir,
        "target_project": tmp_path / "game_alpha",
    }


def test_sync_addons_copies_updates_and_prunes_while_preserving_imports(mock_godot_repo: dict[str, Path]) -> None:
    target = mock_godot_repo["target_project"]
    addons_src = mock_godot_repo["addons_src"]

    # Dry-run writes nothing
    dry = sync_addons(target, addons_src=addons_src, dry_run=True)
    assert len(dry.copied) == 4
    assert not target.exists()

    # Real sync copies all files
    res1 = sync_addons(target, addons_src=addons_src)
    assert len(res1.copied) == 4
    assert (target / "addons" / "gu_core" / "core.gd").is_file()

    # Re-sync reports unchanged
    res2 = sync_addons(target, addons_src=addons_src)
    assert len(res2.unchanged) == 4
    assert res2.copied == []
    assert res2.updated == []

    # Modify source + add stale file + keep a .import file in target
    (addons_src / "gu_core" / "core.gd").write_text("extends Node\n# v2\n", encoding="utf-8")
    stale = target / "addons" / "gu_core" / "obsolete.gd"
    stale.write_text("# stale\n", encoding="utf-8")
    imp = target / "addons" / "gu_core" / "icon.svg.import"
    imp.write_text("[remap]\n", encoding="utf-8")

    res3 = sync_addons(target, addons_src=addons_src, prune=True)
    assert "addons/gu_core/core.gd" in res3.updated
    assert "addons/gu_core/obsolete.gd" in res3.pruned
    assert not stale.exists()
    assert imp.is_file()


def test_init_godot_project_scaffolds_starter_and_protects_existing(mock_godot_repo: dict[str, Path]) -> None:
    target = mock_godot_repo["target_project"]
    res = init_godot_project(
        target,
        name="Star Odyssey",
        template_dir=mock_godot_repo["tpl_dir"],
        addons_src=mock_godot_repo["addons_src"],
    )

    assert res.project_name == "Star Odyssey"
    assert (target / "project.godot").is_file()
    assert 'config/name="Star Odyssey"' in (target / "project.godot").read_text(encoding="utf-8")
    assert (target / "export_presets.cfg").is_file()
    presets_text = (target / "export_presets.cfg").read_text(encoding="utf-8")
    assert 'application/bundle_identifier="com.example.star_odyssey"' in presets_text
    assert "{{BUNDLE_ID}}" not in presets_text
    assert (target / "scenes" / "main.tscn").is_file()
    assert (target / "addons" / "gu_core" / "core.gd").is_file()
    assert (target / "addons" / "gu_gameplay" / "actor.gd").is_file()

    # Refuses overwrite without force
    with pytest.raises(FileExistsError):
        init_godot_project(
            target,
            name="Other",
            template_dir=mock_godot_repo["tpl_dir"],
            addons_src=mock_godot_repo["addons_src"],
            force=False,
        )

    # Overwrites cleanly with force=True
    init_godot_project(
        target,
        name="Other",
        template_dir=mock_godot_repo["tpl_dir"],
        addons_src=mock_godot_repo["addons_src"],
        force=True,
    )
    assert 'config/name="Other"' in (target / "project.godot").read_text(encoding="utf-8")


def test_cli_addons_sync_dry_run_exits_zero(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc:
        cli.main(["addons", "sync", "--dry-run"])
    assert exc.value.code == 0
    out = capsys.readouterr().out
    assert "[DRY-RUN]" in out
    assert "gu_core,gu_gameplay" in out
