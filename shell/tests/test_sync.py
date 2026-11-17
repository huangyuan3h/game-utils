"""Unit tests for gu sync and ATTRIBUTION.json generation."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from game_utils_audio import cli
from game_utils_audio.sync import ATTRIBUTION_FILENAME, sync_audio_assets
from game_utils_audio.wavutil import write_meta, write_wav_mono_s16


@pytest.fixture()
def audio_workspace(tmp_path: Path) -> dict[str, Path]:
    sfx_dir = tmp_path / "output" / "sfx"
    lib_dir = sfx_dir / "library"
    bgm_dir = tmp_path / "output" / "bgm"
    target_dir = tmp_path / "godot" / "assets" / "audio"

    # 1) Generated SFX + .meta.json
    coin_wav = sfx_dir / "placeholder" / "coin.wav"
    write_wav_mono_s16(coin_wav, [0.0, 0.25, -0.25, 0.0])
    write_meta(
        coin_wav,
        {
            "kind": "sfx",
            "backend": "builtin",
            "preset": "coin",
            "license_note": "Generated procedurally by game-utils builtin synth.",
        },
    )

    # 2) Imported SFX pack + pack.meta.json
    pack_dir = lib_dir / "kenney_footsteps"
    pack_dir.mkdir(parents=True, exist_ok=True)
    step_wav = pack_dir / "grass_01.wav"
    write_wav_mono_s16(step_wav, [0.0, 0.1, -0.1, 0.0])
    (pack_dir / "pack.meta.json").write_text(
        json.dumps(
            {
                "kind": "sfx-library-pack",
                "pack": "kenney_footsteps",
                "collection": "kenney-rpg",
                "source_path": "/downloads/kenney.zip",
                "license": "CC0",
                "commercial": True,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    # 3) BGM + .meta.json
    bgm_wav = bgm_dir / "meadow_theme.wav"
    write_wav_mono_s16(bgm_wav, [0.0, 0.05, -0.05, 0.0])
    write_meta(
        bgm_wav,
        {
            "kind": "bgm",
            "backend": "acestep-1.5",
            "prompt": "calm meadow acoustic loop",
            "upstream": "https://github.com/ACE-Step/ACE-Step-1.5.git",
            "license": "Apache-2.0",
            "commercial": True,
        },
    )

    return {
        "sfx_dir": sfx_dir,
        "lib_dir": lib_dir,
        "bgm_dir": bgm_dir,
        "target_dir": target_dir,
    }


def test_sync_copies_all_buckets_and_generates_attribution(audio_workspace: dict[str, Path]) -> None:
    res = sync_audio_assets(
        target_dir=audio_workspace["target_dir"],
        sfx_dir=audio_workspace["sfx_dir"],
        bgm_dir=audio_workspace["bgm_dir"],
        library_dir=audio_workspace["lib_dir"],
    )

    target = audio_workspace["target_dir"]
    assert sorted(res.copied) == [
        "bgm/meadow_theme.wav",
        "sfx/library/kenney_footsteps/grass_01.wav",
        "sfx/placeholder/coin.wav",
    ]
    assert res.overwritten == []
    assert res.skipped == []

    for rel in res.copied:
        assert (target / rel).is_file()

    # Meta files are aggregated rather than copied verbatim into audio folders
    assert not (target / "sfx/placeholder/coin.wav.meta.json").exists()
    assert not (target / "sfx/library/kenney_footsteps/pack.meta.json").exists()

    attr_file = target / ATTRIBUTION_FILENAME
    assert attr_file.is_file()
    doc = json.loads(attr_file.read_text(encoding="utf-8"))
    by_path = {item["path"]: item for item in doc["assets"]}

    assert by_path["sfx/placeholder/coin.wav"]["source"] == "builtin"
    assert by_path["sfx/placeholder/coin.wav"]["commercial"] is True
    assert "builtin synth" in by_path["sfx/placeholder/coin.wav"]["license"]

    assert by_path["sfx/library/kenney_footsteps/grass_01.wav"]["license"] == "CC0"
    assert by_path["sfx/library/kenney_footsteps/grass_01.wav"]["commercial"] is True
    assert by_path["sfx/library/kenney_footsteps/grass_01.wav"]["pack"] == "kenney_footsteps"

    assert by_path["bgm/meadow_theme.wav"]["kind"] == "bgm"
    assert by_path["bgm/meadow_theme.wav"]["license"] == "Apache-2.0"
    assert by_path["bgm/meadow_theme.wav"]["commercial"] is True


def test_sync_conflict_skips_by_default_and_overwrites_with_force(audio_workspace: dict[str, Path]) -> None:
    target = audio_workspace["target_dir"]
    existing = target / "sfx" / "placeholder" / "coin.wav"
    existing.parent.mkdir(parents=True, exist_ok=True)
    existing.write_bytes(b"KEEP_ME")

    res_skip = sync_audio_assets(
        target_dir=target,
        sfx_dir=audio_workspace["sfx_dir"],
        bgm_dir=audio_workspace["bgm_dir"],
        library_dir=audio_workspace["lib_dir"],
        force=False,
    )
    assert "sfx/placeholder/coin.wav" in res_skip.skipped
    assert existing.read_bytes() == b"KEEP_ME"

    res_force = sync_audio_assets(
        target_dir=target,
        sfx_dir=audio_workspace["sfx_dir"],
        bgm_dir=audio_workspace["bgm_dir"],
        library_dir=audio_workspace["lib_dir"],
        force=True,
    )
    assert "sfx/placeholder/coin.wav" in res_force.overwritten
    assert existing.read_bytes() != b"KEEP_ME"


def test_sync_dry_run_makes_no_filesystem_changes(audio_workspace: dict[str, Path]) -> None:
    target = audio_workspace["target_dir"]
    res = sync_audio_assets(
        target_dir=target,
        sfx_dir=audio_workspace["sfx_dir"],
        bgm_dir=audio_workspace["bgm_dir"],
        library_dir=audio_workspace["lib_dir"],
        dry_run=True,
    )

    assert len(res.copied) == 3
    assert len(res.attribution_entries) == 3
    assert not target.exists()


def test_cli_sync_dry_run_exits_zero(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    target = tmp_path / "empty_target"
    with pytest.raises(SystemExit) as exc_info:
        cli.main(["sync", "--target", str(target), "--dry-run"])
    assert exc_info.value.code == 0
    captured = capsys.readouterr()
    assert "[DRY-RUN]" in captured.out
    assert not target.exists()
