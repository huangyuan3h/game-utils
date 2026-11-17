"""Unit tests for `gu data validate` and `gu data build`."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from game_utils_audio.data_pipeline import build_data_dir, validate_data_dir


def test_data_validate_and_build_csv_and_localization(tmp_path: Path) -> None:
    src = tmp_path / "data"
    out = tmp_path / "godot_data"
    src.mkdir()

    (src / "items.csv").write_text(
        "id,display_name,max_stack,weight,consumable\n"
        "wood,Wood,50,1.5,false\n"
        "apple,Apple,20,0.2,true\n",
        encoding="utf-8",
    )
    (src / "items.schema.json").write_text(
        json.dumps(
            {
                "required": ["id", "display_name"],
                "types": {
                    "id": "string",
                    "max_stack": "int",
                    "weight": "float",
                    "consumable": "bool",
                },
                "unique": ["id"],
            }
        ),
        encoding="utf-8",
    )

    (src / "ui_i18n.csv").write_text(
        "keys,en,zh\n"
        "BTN_START,Start,开始\n"
        "BTN_QUIT,Quit,退出\n",
        encoding="utf-8",
    )

    val = validate_data_dir(src)
    assert val.ok, val.errors
    assert len(val.tables["items.csv"]) == 2
    assert val.tables["items.csv"][0]["max_stack"] == 50
    assert val.tables["items.csv"][1]["consumable"] is True

    dry = build_data_dir(src, out, dry_run=True)
    assert sorted(dry.written_files) == [
        "i18n_manifest.json",
        "items.json",
        "ui_i18n.csv",
        "ui_i18n.csv.import",
    ]
    assert not out.exists()

    built = build_data_dir(src, out)
    assert sorted(built.written_files) == [
        "i18n_manifest.json",
        "items.json",
        "ui_i18n.csv",
        "ui_i18n.csv.import",
    ]
    built_items = json.loads((out / "items.json").read_text(encoding="utf-8"))
    assert built_items["table"] == "items"
    assert built_items["rows"][0]["weight"] == 1.5
    assert (out / "ui_i18n.csv").is_file()
    assert 'importer="keep"' in (out / "ui_i18n.csv.import").read_text(encoding="utf-8")
    manifest = json.loads((out / "i18n_manifest.json").read_text(encoding="utf-8"))
    assert manifest["version"] == 1
    assert manifest["default_locale"] == "en"
    assert manifest["locales"] == ["en", "zh"]
    assert manifest["files"] == ["ui_i18n.csv"]

    # Build output is a valid data dir: the manifest is not a second table.
    again = validate_data_dir(out)
    assert again.ok, again.errors
    assert again.localization_locales == ["en", "zh"]


def test_data_validate_catches_duplicate_ids_type_errors_and_missing_translations(tmp_path: Path) -> None:
    src = tmp_path / "bad_data"
    src.mkdir()

    (src / "items.csv").write_text(
        "id,max_stack\n"
        "sword,not_an_int\n"
        "sword,1\n",
        encoding="utf-8",
    )
    (src / "items.schema.json").write_text(
        json.dumps({"required": ["id"], "types": {"max_stack": "int"}, "unique": ["id"]}),
        encoding="utf-8",
    )
    (src / "translations.csv").write_text(
        "keys,en,zh\n"
        "HELLO,Hello,\n"
        "HELLO,Hi,你好\n",
        encoding="utf-8",
    )

    val = validate_data_dir(src)
    assert not val.ok
    joined = "\n".join(val.errors)
    assert "duplicate id 'sword'" in joined
    assert "Expected int" in joined
    assert "missing 'zh' translation" in joined
    assert "duplicate translation key 'HELLO'" in joined

    with pytest.raises(ValueError):
        build_data_dir(src, tmp_path / "out")


def test_localization_rejects_mismatched_locale_sets(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "a_i18n.csv").write_text("keys,en,zh\nA,a,啊\n", encoding="utf-8")
    (src / "b_i18n.csv").write_text("keys,en,ja\nB,b,い\n", encoding="utf-8")

    val = validate_data_dir(src)
    assert not val.ok
    assert "locale columns [en, ja] differ from a_i18n.csv [en, zh]" in "\n".join(val.errors)
    with pytest.raises(ValueError):
        build_data_dir(src, tmp_path / "out")


def test_localization_rejects_duplicate_keys_across_files(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "a_i18n.csv").write_text("keys,en\nHELLO,Hi\n", encoding="utf-8")
    (src / "b_i18n.csv").write_text("keys,en\nHELLO,Hello\n", encoding="utf-8")

    val = validate_data_dir(src)
    assert not val.ok
    joined = "\n".join(val.errors)
    assert "duplicate translation key 'HELLO' also defined in a_i18n.csv" in joined


def test_localization_rejects_invalid_and_duplicate_locale_columns(tmp_path: Path) -> None:
    invalid = tmp_path / "invalid"
    invalid.mkdir()
    (invalid / "ui_i18n.csv").write_text("keys,english\nHELLO,Hello\n", encoding="utf-8")
    invalid_val = validate_data_dir(invalid)
    assert not invalid_val.ok
    assert "invalid locale column 'english'" in "\n".join(invalid_val.errors)

    dup = tmp_path / "dup"
    dup.mkdir()
    (dup / "ui_i18n.csv").write_text("keys,zh-CN,zh_CN\nHELLO,你好,你好\n", encoding="utf-8")
    dup_val = validate_data_dir(dup)
    assert not dup_val.ok
    assert "duplicate locale column 'zh_CN'" in "\n".join(dup_val.errors)


def test_localization_manifest_canonicalizes_hyphen_locales(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "ui_i18n.csv").write_text("keys,zh,pt-BR\nHELLO,你好,Ola\n", encoding="utf-8")

    built = build_data_dir(src, tmp_path / "out")
    manifest = json.loads((tmp_path / "out" / "i18n_manifest.json").read_text(encoding="utf-8"))
    assert manifest["locales"] == ["zh", "pt_BR"]
    assert manifest["default_locale"] == "pt_BR"
    assert "ui_i18n.csv" in built.written_files


def test_shipped_localization_samples_match_contract() -> None:
    repo = Path(__file__).resolve().parents[2]
    for rel in ("godot/templates/starter/data", "prototypes/walk-sandbox/data"):
        val = validate_data_dir(repo / rel)
        assert val.ok, val.errors
        assert val.localization_locales == ["en", "zh"]
