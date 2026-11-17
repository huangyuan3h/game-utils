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
    assert sorted(dry.written_files) == ["items.json", "ui_i18n.csv"]
    assert not out.exists()

    built = build_data_dir(src, out)
    assert sorted(built.written_files) == ["items.json", "ui_i18n.csv"]
    built_items = json.loads((out / "items.json").read_text(encoding="utf-8"))
    assert built_items["table"] == "items"
    assert built_items["rows"][0]["weight"] == 1.5
    assert (out / "ui_i18n.csv").is_file()


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
