"""Validate and build game data tables (CSV/JSON) and localization CSVs for Godot."""

from __future__ import annotations

import csv
import json
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass
class DataValidationResult:
    src_dir: Path
    checked_files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    tables: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    localization_files: list[Path] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


@dataclass
class DataBuildResult:
    src_dir: Path
    out_dir: Path
    dry_run: bool
    written_files: list[str] = field(default_factory=list)
    validation: DataValidationResult | None = None


def _is_localization_csv(path: Path, fieldnames: Sequence[str] | None = None) -> bool:
    stem = path.stem.lower()
    if stem.endswith("_i18n") or stem.startswith("translations"):
        return True
    if fieldnames and fieldnames[0].strip().lower() == "keys":
        return True
    return False


from typing import Sequence  # noqa: E402


def _coerce_value(raw: Any, expected_type: str) -> Any:
    t = expected_type.lower()
    if t == "int":
        if isinstance(raw, bool):
            raise ValueError(f"Expected int, got bool {raw!r}")
        try:
            return int(raw)
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Expected int, got {raw!r}") from exc
    if t == "float":
        if isinstance(raw, bool):
            raise ValueError(f"Expected float, got bool {raw!r}")
        try:
            return float(raw)
        except (TypeError, ValueError) as exc:
            raise ValueError(f"Expected float, got {raw!r}") from exc
    if t == "bool":
        if isinstance(raw, bool):
            return raw
        s = str(raw).strip().lower()
        if s in {"true", "1", "yes"}:
            return True
        if s in {"false", "0", "no"}:
            return False
        raise ValueError(f"Expected bool, got {raw!r}")
    if t == "string":
        return str(raw)
    raise ValueError(f"Unsupported schema type: {expected_type}")


def _load_schema(table_path: Path) -> dict[str, Any]:
    schema_path = table_path.with_suffix(".schema.json")
    if not schema_path.is_file():
        return {}
    data = json.loads(schema_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Schema must be a JSON object: {schema_path}")
    return data


def _validate_localization_csv(path: Path, rel: str, errors: list[str]) -> None:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or reader.fieldnames[0].strip() != "keys":
            errors.append(f"{rel}: localization CSV first column must be 'keys'")
            return
        locales = [col for col in reader.fieldnames[1:] if col and col.strip()]
        if not locales:
            errors.append(f"{rel}: localization CSV must define at least one locale column")
            return
        seen_keys: set[str] = set()
        for row_idx, row in enumerate(reader, start=2):
            key = str(row.get("keys") or "").strip()
            if not key:
                errors.append(f"{rel}:{row_idx}: empty translation key")
                continue
            if key in seen_keys:
                errors.append(f"{rel}:{row_idx}: duplicate translation key '{key}'")
            seen_keys.add(key)
            for loc in locales:
                val = row.get(loc)
                if val is None or str(val).strip() == "":
                    errors.append(f"{rel}:{row_idx}: missing '{loc}' translation for key '{key}'")


def _validate_rows(
    rows: list[dict[str, Any]],
    schema: dict[str, Any],
    rel: str,
    errors: list[str],
) -> list[dict[str, Any]]:
    required = [str(c) for c in schema.get("required", [])]
    types: dict[str, str] = {str(k): str(v) for k, v in schema.get("types", {}).items()}
    unique_cols = [str(c) for c in schema.get("unique", ["id"])]

    seen_unique: dict[str, set[str]] = {col: set() for col in unique_cols}
    typed_rows: list[dict[str, Any]] = []

    for idx, raw_row in enumerate(rows, start=1):
        if not isinstance(raw_row, dict):
            errors.append(f"{rel}: row {idx} must be an object")
            continue
        row = dict(raw_row)
        for req in required:
            if req not in row or row[req] is None or str(row[req]).strip() == "":
                errors.append(f"{rel}: row {idx} missing required field '{req}'")
        for col, tname in types.items():
            if col in row and row[col] is not None and str(row[col]).strip() != "":
                try:
                    row[col] = _coerce_value(row[col], tname)
                except ValueError as exc:
                    errors.append(f"{rel}: row {idx} field '{col}': {exc}")
        for ucol in unique_cols:
            if ucol in row and row[ucol] is not None and str(row[ucol]).strip() != "":
                key = str(row[ucol])
                if key in seen_unique[ucol]:
                    errors.append(f"{rel}: row {idx} duplicate {ucol} '{key}'")
                seen_unique[ucol].add(key)
        typed_rows.append(row)

    return typed_rows


def validate_data_dir(src_dir: Path) -> DataValidationResult:
    root = src_dir.expanduser().resolve()
    result = DataValidationResult(src_dir=root)
    if not root.is_dir():
        result.errors.append(f"Data directory not found: {root}")
        return result

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name.endswith(".schema.json"):
            continue
        rel = path.relative_to(root).as_posix()
        ext = path.suffix.lower()
        if ext not in {".csv", ".json"}:
            continue

        result.checked_files.append(rel)

        try:
            schema = _load_schema(path)
        except Exception as exc:
            result.errors.append(f"{rel}: invalid schema: {exc}")
            continue

        if ext == ".csv":
            with path.open("r", encoding="utf-8-sig", newline="") as f:
                reader = csv.DictReader(f)
                fieldnames = list(reader.fieldnames or [])
                if _is_localization_csv(path, fieldnames):
                    result.localization_files.append(path)
                    _validate_localization_csv(path, rel, result.errors)
                    continue
                raw_rows = [dict(r) for r in reader]
            result.tables[rel] = _validate_rows(raw_rows, schema, rel, result.errors)
        else:
            try:
                parsed = json.loads(path.read_text(encoding="utf-8"))
            except Exception as exc:
                result.errors.append(f"{rel}: invalid JSON: {exc}")
                continue
            if isinstance(parsed, list):
                raw_rows = parsed
            elif isinstance(parsed, dict) and isinstance(parsed.get("rows"), list):
                raw_rows = parsed["rows"]
            else:
                result.errors.append(f"{rel}: JSON table must be a list or {{'rows': [...]}}")
                continue
            result.tables[rel] = _validate_rows(raw_rows, schema, rel, result.errors)

    return result


def build_data_dir(
    src_dir: Path,
    out_dir: Path,
    *,
    dry_run: bool = False,
) -> DataBuildResult:
    val = validate_data_dir(src_dir)
    if not val.ok:
        raise ValueError("Data validation failed:\n  " + "\n  ".join(val.errors))

    dest_root = out_dir.expanduser().resolve()
    res = DataBuildResult(
        src_dir=val.src_dir,
        out_dir=dest_root,
        dry_run=dry_run,
        validation=val,
    )

    for rel, rows in sorted(val.tables.items()):
        out_rel = Path(rel).with_suffix(".json")
        out_path = dest_root / out_rel
        res.written_files.append(out_rel.as_posix())
        if not dry_run:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "version": 1,
                "table": Path(rel).stem,
                "rows": rows,
            }
            out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for loc_path in val.localization_files:
        rel_path = loc_path.relative_to(val.src_dir)
        out_path = dest_root / rel_path
        res.written_files.append(rel_path.as_posix())
        if not dry_run:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(loc_path, out_path)

    return res
