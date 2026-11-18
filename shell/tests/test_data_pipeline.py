"""Unit tests for `gu data validate` and `gu data build`."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from game_utils_audio.data_pipeline import (
    build_data_dir,
    extract_tr_keys,
    merge_translation_keys,
    validate_data_dir,
)


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


def test_refs_and_placeholders_reject_orphans(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "items.csv").write_text("id,name_key\nwood,ITEM_WOOD\n", encoding="utf-8")
    (src / "items.schema.json").write_text(
        json.dumps({"unique": ["id"], "i18n": ["name_key"]}),
        encoding="utf-8",
    )
    (src / "quests.csv").write_text(
        "id,reward_item,reward_pool\n"
        "q1,missing_item,wood|ore\n",
        encoding="utf-8",
    )
    (src / "quests.schema.json").write_text(
        json.dumps(
            {
                "refs": {
                    "reward_item": "items.csv#id",
                    "reward_pool": {"table": "items.csv", "column": "id", "list": True},
                }
            }
        ),
        encoding="utf-8",
    )
    (src / "ui_i18n.csv").write_text(
        "keys,en,zh\n"
        "GREET,Hello {name},你好\n",
        encoding="utf-8",
    )

    val = validate_data_dir(src)
    assert not val.ok
    joined = "\n".join(val.errors)
    assert "references missing items.csv#id 'missing_item'" in joined
    assert "references missing items.csv#id 'ore'" in joined
    assert "references missing items.csv#id 'wood'" not in joined
    assert "translation key 'ITEM_WOOD' is not defined" in joined
    assert "placeholder mismatch for 'GREET'" in joined

    with pytest.raises(ValueError):
        build_data_dir(src, tmp_path / "out")


def test_refs_and_placeholders_accept_a_consistent_set(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "items.csv").write_text("id,name_key\nwood,ITEM_WOOD\nore,ITEM_ORE\n", encoding="utf-8")
    (src / "items.schema.json").write_text(
        json.dumps({"unique": ["id"], "i18n": ["name_key"]}),
        encoding="utf-8",
    )
    (src / "drops.json").write_text(
        json.dumps([{"id": "tree", "item_id": "wood"}, {"id": "vein", "item_id": ["ore", "wood"]}]),
        encoding="utf-8",
    )
    (src / "drops.schema.json").write_text(
        json.dumps({"refs": {"item_id": {"table": "items.csv", "column": "id", "list": True}}}),
        encoding="utf-8",
    )
    (src / "ui_i18n.csv").write_text(
        "keys,en,zh\n"
        "ITEM_WOOD,Wood,木材\n"
        "ITEM_ORE,Ore {0},矿石 {0}\n",
        encoding="utf-8",
    )

    val = validate_data_dir(src)
    assert val.ok, val.errors
    built = build_data_dir(src, tmp_path / "out")
    assert "drops.json" in built.written_files


def test_refs_report_a_missing_target_table(tmp_path: Path) -> None:
    src = tmp_path / "data"
    src.mkdir()
    (src / "quests.csv").write_text("id,reward_item\nq1,wood\n", encoding="utf-8")
    (src / "quests.schema.json").write_text(
        json.dumps({"refs": {"reward_item": "nope.csv#id", "bad": "items.csv"}}),
        encoding="utf-8",
    )

    val = validate_data_dir(src)
    joined = "\n".join(val.errors)
    assert "targets missing table 'nope.csv'" in joined
    assert "invalid ref for 'bad'" in joined


def test_extract_merges_tr_keys_without_dropping_translations(tmp_path: Path) -> None:
    scan = tmp_path / "scripts"
    scan.mkdir()
    (scan / "menu.gd").write_text('func _ready() -> void:\n\tlabel.text = tr("HELLO")\n\tother.text = tr("NEW_KEY")\n', encoding="utf-8")
    (scan / "skip.txt").write_text('tr("NOT_A_SCRIPT")\n', encoding="utf-8")
    csv_path = tmp_path / "ui_i18n.csv"
    csv_path.write_text("keys,en,zh\nHELLO,Hello,你好\n", encoding="utf-8")

    keys, scanned = extract_tr_keys([scan])
    assert keys == {"HELLO", "NEW_KEY"}
    assert scanned == 1

    merged = merge_translation_keys(csv_path, keys)
    assert merged.added_keys == ["NEW_KEY"]
    text = csv_path.read_text(encoding="utf-8")
    assert "HELLO,Hello,你好" in text
    assert "NEW_KEY,," in text

    again = merge_translation_keys(csv_path, keys)
    assert again.added_keys == []
    assert csv_path.read_text(encoding="utf-8").count("NEW_KEY") == 1

    val = validate_data_dir(tmp_path)
    assert not val.ok
    assert "missing 'en' translation for key 'NEW_KEY'" in "\n".join(val.errors)


def test_shipped_localization_samples_match_contract() -> None:
    repo = Path(__file__).resolve().parents[2]
    for rel in ("godot/templates/starter/data", "prototypes/walk-sandbox/data"):
        val = validate_data_dir(repo / rel)
        assert val.ok, val.errors
        assert val.localization_locales == ["en", "zh"]
