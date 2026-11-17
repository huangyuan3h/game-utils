"""Unit tests for `gu assets audit` and `gu assets credits`."""

from __future__ import annotations

import json
from pathlib import Path

from game_utils_audio.assets_audit import audit_project_assets, write_credits


def test_audit_detects_cc0_license_and_sidecar_meta(tmp_path: Path) -> None:
    proj = tmp_path / "demo_game"
    model_dir = proj / "assets" / "models" / "quaternius"
    model_dir.mkdir(parents=True)
    (model_dir / "Hero.glb").write_bytes(b"glb")
    (model_dir / "LICENSE.txt").write_text("License:\nCC0 1.0 Universal\n", encoding="utf-8")

    tex_dir = proj / "assets" / "textures"
    tex_dir.mkdir(parents=True)
    (tex_dir / "grass.png").write_bytes(b"png")
    (tex_dir / "grass.png.meta.json").write_text(
        json.dumps({"source": "kenney", "license": "CC0", "commercial": True}),
        encoding="utf-8",
    )

    res = audit_project_assets(proj, write=True)
    assert res.counts_by_category["model"] == 1
    assert res.counts_by_category["texture"] == 1
    assert res.unknown_licenses == []
    assert res.non_commercial == []
    assert res.ok
    assert res.attribution_path.is_file()

    credits_path, _ = write_credits(proj)
    md = credits_path.read_text(encoding="utf-8")
    assert "Hero.glb" in md
    assert "CC0" in md


def test_audit_flags_unknown_and_non_commercial_assets(tmp_path: Path) -> None:
    proj = tmp_path / "strict_game"
    sfx_dir = proj / "assets" / "sfx"
    sfx_dir.mkdir(parents=True)
    (sfx_dir / "mystery.wav").write_bytes(b"wav")
    (sfx_dir / "fan_track.ogg").write_bytes(b"ogg")
    (sfx_dir / "fan_track.ogg.meta.json").write_text(
        json.dumps({"source": "freesound", "license": "CC-BY-NC", "commercial": False}),
        encoding="utf-8",
    )

    res = audit_project_assets(proj)
    assert "assets/sfx/mystery.wav" in res.unknown_licenses
    assert "assets/sfx/fan_track.ogg" in res.non_commercial
    assert not res.ok
