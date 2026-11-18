"""Validate and build game data tables (CSV/JSON) and localization CSVs for Godot."""

from __future__ import annotations

import csv
import json
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence


@dataclass
class DataValidationResult:
    src_dir: Path
    checked_files: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    tables: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    localization_files: list[Path] = field(default_factory=list)
    # Canonical locale columns shared by every localization CSV (hyphens become underscores).
    localization_locales: list[str] = field(default_factory=list)

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


# Godot locale codes: en, zh, zh_CN, pt-BR. Hyphens are canonicalized to underscores.
_LOCALE_RE = re.compile(r"^[A-Za-z]{2,3}([_-][A-Za-z0-9]+)*$")
# Format tokens such as {0} and {player}. Locales of one key must carry the same set.
_PLACEHOLDER_RE = re.compile(r"\{[^{}]+\}")
I18N_MANIFEST_NAME = "i18n_manifest.json"
_KEEP_IMPORT = '[remap]\n\nimporter="keep"\n'


def _canonical_locale(raw: str) -> str:
    return raw.strip().replace("-", "_")


def _choose_default_locale(locales: Sequence[str]) -> str:
    if "en" in locales:
        return "en"
    if not locales:
        return "en"
    return sorted(locales)[0]


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


def _validate_localization_csv(path: Path, rel: str, errors: list[str]) -> tuple[list[str], set[str]]:
    """Return canonical locale columns and translation keys for cross-file checks."""
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames or reader.fieldnames[0].strip() != "keys":
            errors.append(f"{rel}: localization CSV first column must be 'keys'")
            return [], set()
        raw_locales = [col for col in reader.fieldnames[1:] if col and col.strip()]
        if not raw_locales:
            errors.append(f"{rel}: localization CSV must define at least one locale column")
            return [], set()

        locales: list[str] = []
        seen_locales: set[str] = set()
        for col in raw_locales:
            raw = col.strip()
            if _LOCALE_RE.fullmatch(raw) is None:
                errors.append(f"{rel}: invalid locale column '{raw}'")
                continue
            canon = _canonical_locale(raw)
            if canon in seen_locales:
                errors.append(f"{rel}: duplicate locale column '{raw}'")
                continue
            seen_locales.add(canon)
            locales.append(canon)

        seen_keys: set[str] = set()
        for row_idx, row in enumerate(reader, start=2):
            key = str(row.get("keys") or "").strip()
            if not key:
                errors.append(f"{rel}:{row_idx}: empty translation key")
                continue
            if key in seen_keys:
                errors.append(f"{rel}:{row_idx}: duplicate translation key '{key}'")
            seen_keys.add(key)
            token_sets: list[tuple[str, set[str]]] = []
            for loc in raw_locales:
                val = row.get(loc)
                if val is None or str(val).strip() == "":
                    errors.append(f"{rel}:{row_idx}: missing '{loc}' translation for key '{key}'")
                    continue
                token_sets.append((loc, set(_PLACEHOLDER_RE.findall(str(val)))))
            _check_placeholder_parity(rel, row_idx, key, token_sets, errors)
        return locales, seen_keys


def _check_placeholder_parity(
    rel: str,
    row_idx: int,
    key: str,
    token_sets: Sequence[tuple[str, set[str]]],
    errors: list[str],
) -> None:
    """Require every translated locale of one key to use the same {token} set."""
    if len(token_sets) < 2:
        return
    base_loc, base_tokens = token_sets[0]
    for loc, tokens in token_sets[1:]:
        if tokens != base_tokens:
            errors.append(
                f"{rel}:{row_idx}: placeholder mismatch for '{key}': "
                f"{loc} has {sorted(tokens)} but {base_loc} has {sorted(base_tokens)}"
            )


def _cross_check_localization(
    entries: Sequence[tuple[str, list[str], set[str]]],
    errors: list[str],
) -> list[str]:
    """Require one locale set and unique keys across every localization CSV.

    Locale order in the returned list follows the first file. ``default_locale``
    is chosen separately (``en`` when present, otherwise the sorted first code).
    """
    if not entries:
        return []
    reference_rel, reference_locales, _reference_keys = entries[0]
    ref_set = set(reference_locales)
    owner: dict[str, str] = {}
    for rel, locales, keys in entries:
        if set(locales) != ref_set:
            errors.append(
                f"{rel}: locale columns [{', '.join(locales)}] differ from "
                f"{reference_rel} [{', '.join(reference_locales)}]"
            )
        for key in sorted(keys):
            previous = owner.get(key)
            if previous is not None and previous != rel:
                errors.append(
                    f"{rel}: duplicate translation key '{key}' also defined in {previous}"
                )
            else:
                owner[key] = rel
    return list(reference_locales)


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

    localization_entries: list[tuple[str, list[str], set[str]]] = []
    schemas: dict[str, dict[str, Any]] = {}

    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        if path.name.endswith(".schema.json") or path.name == I18N_MANIFEST_NAME:
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
                    locales, keys = _validate_localization_csv(path, rel, result.errors)
                    localization_entries.append((rel, locales, keys))
                    continue
                raw_rows = [dict(r) for r in reader]
            schemas[rel] = schema
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
            schemas[rel] = schema
            result.tables[rel] = _validate_rows(raw_rows, schema, rel, result.errors)

    result.localization_locales = _cross_check_localization(localization_entries, result.errors)
    translation_keys: set[str] = set()
    for _rel, _locales, keys in localization_entries:
        translation_keys.update(keys)
    _check_references(result.tables, schemas, result.errors)
    _check_i18n_keys(result.tables, schemas, translation_keys, result.errors)
    return result


def _parse_ref_spec(spec: Any) -> tuple[str, str, bool]:
    """Return ``(table, column, is_list)`` for a schema ``refs`` entry.

    A string ``"items.csv#id"`` is a single id. An object may set ``list`` so
    a cell can hold ``wood|ore`` or a JSON array of ids.
    """
    if isinstance(spec, str):
        table, sep, column = spec.partition("#")
        if not sep or not table.strip() or not column.strip():
            raise ValueError(f"expected 'table#column', got {spec!r}")
        return table.strip(), column.strip(), False
    if isinstance(spec, dict):
        table = str(spec.get("table", "")).strip()
        column = str(spec.get("column", "id")).strip() or "id"
        if not table:
            raise ValueError(f"ref object needs 'table': {spec!r}")
        return table, column, bool(spec.get("list", False))
    raise ValueError(f"expected string or object, got {spec!r}")


def _ref_values(value: Any, as_list: bool) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    text = str(value).strip()
    if text == "":
        return []
    if text.startswith("["):
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            parsed = None
        if isinstance(parsed, list):
            return [str(item).strip() for item in parsed if str(item).strip()]
    if as_list:
        return [part.strip() for part in text.split("|") if part.strip()]
    return [text]


def _column_index(tables: dict[str, list[dict[str, Any]]]) -> dict[tuple[str, str], set[str]]:
    index: dict[tuple[str, str], set[str]] = {}
    for rel, rows in tables.items():
        for row in rows:
            for column, value in row.items():
                if value is None or str(value).strip() == "":
                    continue
                index.setdefault((rel, str(column)), set()).add(str(value))
    return index


def _check_references(
    tables: dict[str, list[dict[str, Any]]],
    schemas: dict[str, dict[str, Any]],
    errors: list[str],
) -> None:
    """Reject ids that point at a missing row in another table."""
    index = _column_index(tables)
    reported_targets: set[tuple[str, str, str]] = set()
    for rel, rows in tables.items():
        raw_refs = schemas.get(rel, {}).get("refs", {})
        if not raw_refs:
            continue
        if not isinstance(raw_refs, dict):
            errors.append(f"{rel}: schema 'refs' must be an object")
            continue
        parsed: dict[str, tuple[str, str, bool]] = {}
        for column, spec in raw_refs.items():
            try:
                parsed[str(column)] = _parse_ref_spec(spec)
            except ValueError as exc:
                errors.append(f"{rel}: invalid ref for '{column}': {exc}")
        for column, (target, target_column, as_list) in parsed.items():
            target_key = (rel, column, target)
            if target not in tables:
                if target_key not in reported_targets:
                    errors.append(f"{rel}: ref field '{column}' targets missing table '{target}'")
                    reported_targets.add(target_key)
                continue
            if (target, target_column) not in index:
                if target_key not in reported_targets:
                    errors.append(
                        f"{rel}: ref field '{column}' targets missing column '{target}#{target_column}'"
                    )
                    reported_targets.add(target_key)
                continue
            known = index[(target, target_column)]
            for idx, row in enumerate(rows, start=1):
                if column not in row:
                    continue
                for ref_id in _ref_values(row.get(column), as_list):
                    if ref_id not in known:
                        errors.append(
                            f"{rel}: row {idx} field '{column}' references missing "
                            f"{target}#{target_column} '{ref_id}'"
                        )


def _check_i18n_keys(
    tables: dict[str, list[dict[str, Any]]],
    schemas: dict[str, dict[str, Any]],
    translation_keys: set[str],
    errors: list[str],
) -> None:
    """Reject translation keys named by a table but absent from every i18n CSV."""
    for rel, rows in tables.items():
        columns = schemas.get(rel, {}).get("i18n", [])
        if not columns:
            continue
        if not isinstance(columns, list):
            errors.append(f"{rel}: schema 'i18n' must be a list of column names")
            continue
        for idx, row in enumerate(rows, start=1):
            for column in columns:
                value = row.get(str(column))
                if value is None or str(value).strip() == "":
                    continue
                key = str(value).strip()
                if key not in translation_keys:
                    errors.append(
                        f"{rel}: row {idx} field '{column}' translation key '{key}' is not defined"
                    )


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
        import_rel = f"{rel_path.as_posix()}.import"
        res.written_files.append(rel_path.as_posix())
        res.written_files.append(import_rel)
        if not dry_run:
            out_path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(loc_path, out_path)
            out_path.with_name(out_path.name + ".import").write_text(_KEEP_IMPORT, encoding="utf-8")

    if val.localization_files:
        manifest_rel = I18N_MANIFEST_NAME
        res.written_files.append(manifest_rel)
        if not dry_run:
            dest_root.mkdir(parents=True, exist_ok=True)
            manifest = {
                "version": 1,
                "default_locale": _choose_default_locale(val.localization_locales),
                "locales": list(val.localization_locales),
                "files": [path.relative_to(val.src_dir).as_posix() for path in val.localization_files],
            }
            (dest_root / manifest_rel).write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

    return res


_TR_KEY_RE = re.compile(r"""\btr\(\s*(["'])([^"']+)\1""")


@dataclass
class ExtractResult:
    csv_path: Path
    scanned_files: int
    found_keys: list[str] = field(default_factory=list)
    added_keys: list[str] = field(default_factory=list)


def extract_tr_keys(scan_roots: Sequence[Path]) -> tuple[set[str], int]:
    """Collect string literals passed to ``tr()`` in ``.gd`` and ``.tscn`` files."""
    keys: set[str] = set()
    scanned = 0
    for root in scan_roots:
        path = root.expanduser().resolve()
        if path.is_file():
            candidates = [path]
        elif path.is_dir():
            candidates = [item for item in path.rglob("*") if item.suffix.lower() in {".gd", ".tscn"}]
        else:
            raise FileNotFoundError(f"Scan path not found: {path}")
        for item in candidates:
            if item.suffix.lower() not in {".gd", ".tscn"}:
                continue
            scanned += 1
            text = item.read_text(encoding="utf-8", errors="replace")
            for match in _TR_KEY_RE.finditer(text):
                key = match.group(2).strip()
                if key:
                    keys.add(key)
    return keys, scanned


def merge_translation_keys(
    csv_path: Path,
    keys: set[str],
    *,
    locales: Sequence[str] = ("en", "zh"),
) -> ExtractResult:
    """Append missing keys to a localization CSV. Existing translations stay put.

    New cells are left blank so ``gu data validate`` still reports them as untranslated.
    """
    dest = csv_path.expanduser().resolve()
    result = ExtractResult(csv_path=dest, scanned_files=0, found_keys=sorted(keys))
    existing_rows: list[dict[str, str]] = []
    header: list[str]
    if dest.is_file():
        with dest.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            if not reader.fieldnames or reader.fieldnames[0].strip() != "keys":
                raise ValueError(f"{dest}: localization CSV first column must be 'keys'")
            header = [col.strip() for col in reader.fieldnames]
            for row in reader:
                existing_rows.append({col: (row.get(col) or "") for col in header})
    else:
        locale_list = [loc.strip() for loc in locales if loc.strip()]
        if not locale_list:
            raise ValueError("At least one locale is required to create a localization CSV")
        header = ["keys", *locale_list]

    known = {str(row.get("keys", "")).strip() for row in existing_rows}
    for key in sorted(keys):
        if key in known:
            continue
        blank = {col: "" for col in header}
        blank["keys"] = key
        existing_rows.append(blank)
        result.added_keys.append(key)

    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        writer.writerows(existing_rows)
    return result
