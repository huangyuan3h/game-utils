from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from game_utils_audio import __version__
from game_utils_audio.assets_audit import audit_project_assets, write_credits
from game_utils_audio.bgm import acestep
from game_utils_audio.data_pipeline import (
    build_data_dir,
    extract_tr_keys,
    merge_translation_keys,
    validate_data_dir,
)
from game_utils_audio.godot_project import init_godot_project, sync_addons
from game_utils_audio.launcher import run_home
from game_utils_audio.menu import run_menu
from game_utils_audio.play import launch_test_game
from game_utils_audio.paths import (
    BGM_OUTPUT_DIR,
    DEFAULT_GODOT_AUDIO_DIR,
    DEFAULT_GODOT_PROJECT_DIR,
    REPO_ROOT,
    SFX_OUTPUT_DIR,
    ensure_output_dirs,
)
from game_utils_audio.quality import export_godot_project, run_godot_tests, run_project_check
from game_utils_audio.sfx import builtin, jsfxr, library as sfx_library, rfxgen
from game_utils_audio.sync import sync_audio_assets


def _cmd_doctor(_: argparse.Namespace) -> int:
    ensure_output_dirs()
    info = {
        "version": __version__,
        "sfx": {
            "builtin": True,
            "jsfxr_node": jsfxr.node_available(),
            "jsfxr_ready": jsfxr.is_ready(),
            "rfxgen": rfxgen.is_ready(),
            "rfxgen_path": rfxgen.binary_path(),
        },
        "bgm": acestep.status(),
        "output": {"sfx": str(SFX_OUTPUT_DIR), "bgm": str(BGM_OUTPUT_DIR)},
    }
    print(json.dumps(info, indent=2))
    return 0


def _cmd_sfx_list(_: argparse.Namespace) -> int:
    print("Placeholder synth presets (low priority):")
    for name in builtin.list_presets():
        print(f"  - {name}")
    return 0


def _cmd_sfx_collections(args: argparse.Namespace) -> int:
    sfx_library.print_collections(tag=args.tag)
    return 0


def _cmd_sfx_needs(_: argparse.Namespace) -> int:
    sfx_library.print_needs()
    return 0


def _cmd_sfx_open(args: argparse.Namespace) -> int:
    if args.need:
        sfx_library.open_need(args.need)
    else:
        sfx_library.open_collection(args.collection)
    return 0


def _cmd_sfx_import(args: argparse.Namespace) -> int:
    sfx_library.import_path(Path(args.path), pack_name=args.name)
    return 0


def _cmd_sfx_library(_: argparse.Namespace) -> int:
    sfx_library.print_imported()
    return 0


def _cmd_sfx_setup_jsfxr(_: argparse.Namespace) -> int:
    jsfxr.setup()
    print("jsfxr ready.")
    return 0


def _cmd_sfx_generate(args: argparse.Namespace) -> int:
    ensure_output_dirs()
    out = Path(args.out) if args.out else SFX_OUTPUT_DIR / "placeholder" / f"{args.preset}.wav"
    backend = args.backend

    if backend == "auto":
        if jsfxr.is_ready():
            backend = "jsfxr"
        elif rfxgen.is_ready():
            backend = "rfxgen"
        else:
            backend = "builtin"

    if backend == "builtin":
        path = builtin.generate_file(args.preset, out, seed=args.seed)
    elif backend == "jsfxr":
        path = jsfxr.generate_file(args.preset, out, seed=args.seed)
    elif backend == "rfxgen":
        path = rfxgen.generate_file(args.preset, out, seed=args.seed)
    else:
        raise SystemExit(f"Unknown backend: {backend}")

    print(f"Wrote {path} (backend={backend})")
    print("Note: procedural synth is placeholder-only; prefer `sfx collections`.")
    return 0


def _cmd_bgm_setup(args: argparse.Namespace) -> int:
    acestep.setup(force=args.force)
    return 0


def _cmd_bgm_status(_: argparse.Namespace) -> int:
    print(json.dumps(acestep.status(), indent=2))
    return 0


def _cmd_bgm_ui(_: argparse.Namespace) -> int:
    acestep.start_ui()
    return 0


def _cmd_bgm_api(_: argparse.Namespace) -> int:
    acestep.start_api()
    return 0


def _cmd_bgm_generate(args: argparse.Namespace) -> int:
    ensure_output_dirs()
    out = Path(args.out) if args.out else None
    path = acestep.generate(
        args.prompt,
        out=out,
        base=args.api,
        duration=args.duration,
    )
    print(f"Wrote {path}")
    return 0


def _cmd_home(_: argparse.Namespace) -> int:
    return run_home()


def _cmd_menu(_: argparse.Namespace) -> int:
    return run_menu()


def _cmd_play(args: argparse.Namespace) -> int:
    project = Path(args.project) if args.project else None
    cmd = launch_test_game(
        project,
        godot_bin=args.godot,
        editor=args.editor,
        skip_import=args.skip_import,
        dry_run=args.dry_run,
    )
    if args.dry_run:
        print(" ".join(cmd))
    return 0


def _cmd_sync(args: argparse.Namespace) -> int:
    target = Path(args.target) if args.target else DEFAULT_GODOT_AUDIO_DIR
    res = sync_audio_assets(
        target_dir=target,
        dry_run=args.dry_run,
        force=args.force,
    )
    mode = "DRY-RUN" if res.dry_run else "SYNC"
    print(f"[{mode}] target={res.target_dir}")
    print(
        f"  copied={len(res.copied)} overwritten={len(res.overwritten)} "
        f"skipped={len(res.skipped)} attribution={len(res.attribution_entries)}"
    )
    for rel in res.copied:
        print(f"  + {rel}")
    for rel in res.overwritten:
        print(f"  ~ {rel}")
    for rel in res.skipped:
        print(f"  = {rel} (exists, skipped)")
    return 0


def _cmd_addons_sync(args: argparse.Namespace) -> int:
    target = Path(args.target) if args.target else DEFAULT_GODOT_PROJECT_DIR
    res = sync_addons(
        target_project=target,
        addons=args.addon or None,
        dry_run=args.dry_run,
        prune=args.prune,
    )
    mode = "DRY-RUN" if res.dry_run else "ADDONS-SYNC"
    print(f"[{mode}] target={res.target_project} addons={','.join(res.addons)}")
    print(
        f"  copied={len(res.copied)} updated={len(res.updated)} "
        f"unchanged={len(res.unchanged)} pruned={len(res.pruned)}"
    )
    for rel in res.copied:
        print(f"  + {rel}")
    for rel in res.updated:
        print(f"  ~ {rel}")
    for rel in res.pruned:
        print(f"  - {rel}")
    return 0


def _cmd_init(args: argparse.Namespace) -> int:
    res = init_godot_project(
        Path(args.target),
        name=args.name,
        force=args.force,
        dry_run=args.dry_run,
    )
    mode = "DRY-RUN" if res.dry_run else "INIT"
    addon_files = (
        len(res.addon_sync.copied) + len(res.addon_sync.updated)
        if res.addon_sync is not None
        else 0
    )
    print(f"[{mode}] project='{res.project_name}' dir={res.target_dir}")
    print(f"  template_files={len(res.created_files)} addon_files={addon_files}")
    return 0


def _cmd_assets_audit(args: argparse.Namespace) -> int:
    target = Path(args.target) if args.target else DEFAULT_GODOT_PROJECT_DIR
    res = audit_project_assets(target, write=args.write)
    print(f"[AUDIT] project={res.project_dir}")
    print(
        f"  total={len(res.entries)} audio={res.counts_by_category.get('audio', 0)} "
        f"models={res.counts_by_category.get('model', 0)} textures={res.counts_by_category.get('texture', 0)}"
    )
    print(f"  unknown_licenses={len(res.unknown_licenses)} non_commercial={len(res.non_commercial)}")
    for path in res.unknown_licenses:
        print(f"  ? unknown license: {path}")
    for path in res.non_commercial:
        print(f"  ! non-commercial: {path}")
    if args.write:
        print(f"  wrote {res.attribution_path}")
    if args.strict and not res.ok:
        return 1
    return 0


def _cmd_assets_credits(args: argparse.Namespace) -> int:
    target = Path(args.target) if args.target else DEFAULT_GODOT_PROJECT_DIR
    out = Path(args.out) if args.out else None
    credits_path, res = write_credits(target, out)
    print(f"Wrote {credits_path} ({len(res.entries)} asset(s))")
    return 0


def _cmd_data_validate(args: argparse.Namespace) -> int:
    res = validate_data_dir(Path(args.src))
    print(f"[DATA-VALIDATE] dir={res.src_dir} files={len(res.checked_files)}")
    if not res.ok:
        for err in res.errors:
            print(f"  ERROR: {err}", file=sys.stderr)
        return 1
    print(f"  OK ({len(res.tables)} table(s), {len(res.localization_files)} localization file(s))")
    return 0


def _cmd_data_extract(args: argparse.Namespace) -> int:
    keys, scanned = extract_tr_keys([Path(item) for item in args.scan])
    locales = [part.strip() for part in str(args.locales).split(",") if part.strip()]
    res = merge_translation_keys(Path(args.out), keys, locales=locales)
    res.scanned_files = scanned
    print(
        f"[DATA-EXTRACT] scanned_files={res.scanned_files} found={len(res.found_keys)} "
        f"added={len(res.added_keys)} out={res.csv_path}"
    )
    for key in res.added_keys:
        print(f"  + {key}")
    return 0


def _cmd_data_build(args: argparse.Namespace) -> int:
    res = build_data_dir(Path(args.src), Path(args.out), dry_run=args.dry_run)
    mode = "DRY-RUN" if res.dry_run else "DATA-BUILD"
    print(f"[{mode}] src={res.src_dir} out={res.out_dir} files={len(res.written_files)}")
    for rel in res.written_files:
        print(f"  + {rel}")
    return 0


def _cmd_test(args: argparse.Namespace) -> int:
    target = Path(args.project) if args.project else DEFAULT_GODOT_PROJECT_DIR
    report = run_godot_tests(target, godot_bin=args.godot, skip_godot=args.skip_godot)
    print(f"[TEST] project={report.project_dir}")
    for step in report.steps:
        mark = "PASS" if step.ok else "FAIL"
        print(f"  [{mark}] {step.name}: {step.detail}")
    return 0 if report.ok else 1


def _cmd_check(args: argparse.Namespace) -> int:
    target = Path(args.project) if args.project else DEFAULT_GODOT_PROJECT_DIR
    report = run_project_check(
        target,
        godot_bin=args.godot,
        skip_pytest=args.skip_pytest,
        skip_godot=args.skip_godot,
        frames=args.frames,
    )
    print(f"[CHECK] project={report.project_dir}")
    for step in report.steps:
        mark = "PASS" if step.ok else "FAIL"
        print(f"  [{mark}] {step.name}: {step.detail}")
    return 0 if report.ok else 1


def _repo_path(raw: str | None) -> Path | None:
    """Resolve a CLI path against the repo root, so `start.sh` keeps one working directory."""
    if raw is None:
        return None
    path = Path(raw).expanduser()
    return path if path.is_absolute() else (REPO_ROOT / path)


def _cmd_export(args: argparse.Namespace) -> int:
    target = _repo_path(args.project) if args.project else DEFAULT_GODOT_PROJECT_DIR
    cmd = export_godot_project(
        target,
        preset=args.preset,
        out_path=_repo_path(args.out),
        godot_bin=args.godot,
        debug=args.debug,
        dry_run=args.dry_run,
    )
    mode = "DRY-RUN" if args.dry_run else "EXPORT"
    print(f"[{mode}] {' '.join(cmd)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="game-utils — test game, audio tools, and Godot project commands",
    )
    parser.add_argument("--version", action="version", version=f"gu {__version__}")
    sub = parser.add_subparsers(dest="command", required=False)

    p_play = sub.add_parser("play", help="Launch the Walk Sandbox test game")
    p_play.add_argument("--project", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_play.add_argument("--godot", default=None, help="Path to Godot binary")
    p_play.add_argument("--editor", action="store_true", help="Open the Godot editor instead of running the game")
    p_play.add_argument("--skip-import", action="store_true", help="Skip the headless asset import")
    p_play.add_argument("--dry-run", action="store_true", help="Print the Godot command without launching")
    p_play.set_defaults(func=_cmd_play)

    p_menu = sub.add_parser("menu", help="Interactive audio tools")
    p_menu.set_defaults(func=_cmd_menu)

    p_doctor = sub.add_parser("doctor", help="Check backends and environment")
    p_doctor.set_defaults(func=_cmd_doctor)

    # --- SFX ---
    p_sfx = sub.add_parser("sfx", help="Sound effects (collections first)")
    sfx_sub = p_sfx.add_subparsers(dest="sfx_command", required=True)

    p_sfx_cols = sfx_sub.add_parser("collections", help="List curated realistic SFX sources")
    p_sfx_cols.add_argument("--tag", help="Filter by tag, e.g. nature / footsteps")
    p_sfx_cols.set_defaults(func=_cmd_sfx_collections)

    p_sfx_needs = sfx_sub.add_parser("needs", help="List common SFX needs → suggested sources")
    p_sfx_needs.set_defaults(func=_cmd_sfx_needs)

    p_sfx_open = sfx_sub.add_parser("open", help="Open a collection or need in the browser")
    open_group = p_sfx_open.add_mutually_exclusive_group(required=True)
    open_group.add_argument("--collection", help="Collection id, e.g. sonniss-gdc")
    open_group.add_argument("--need", help="Need id, e.g. footsteps")
    p_sfx_open.set_defaults(func=_cmd_sfx_open)

    p_sfx_import = sfx_sub.add_parser("import", help="Import a downloaded zip/folder into local library")
    p_sfx_import.add_argument("path", help="Path to .zip or directory")
    p_sfx_import.add_argument("--name", help="Pack name inside output/sfx/library/")
    p_sfx_import.set_defaults(func=_cmd_sfx_import)

    p_sfx_lib = sfx_sub.add_parser("library", help="List imported local packs")
    p_sfx_lib.set_defaults(func=_cmd_sfx_library)

    p_sfx_list = sfx_sub.add_parser("list", help="List placeholder synth presets")
    p_sfx_list.set_defaults(func=_cmd_sfx_list)

    p_sfx_setup = sfx_sub.add_parser("setup-jsfxr", help="Install jsfxr via npm (needs Node)")
    p_sfx_setup.set_defaults(func=_cmd_sfx_setup_jsfxr)

    p_sfx_gen = sfx_sub.add_parser("generate", help="Placeholder synth beep (not recommended)")
    p_sfx_gen.add_argument("preset", help="Preset name, e.g. coin, jump, laser")
    p_sfx_gen.add_argument("--out", help="Output WAV path")
    p_sfx_gen.add_argument(
        "--backend",
        choices=["auto", "builtin", "jsfxr", "rfxgen"],
        default="auto",
        help="Backend (default: auto → jsfxr → rfxgen → builtin)",
    )
    p_sfx_gen.add_argument("--seed", type=int, default=None, help="Random seed (builtin)")
    p_sfx_gen.set_defaults(func=_cmd_sfx_generate)

    # --- BGM ---
    p_bgm = sub.add_parser("bgm", help="Background music (ACE-Step 1.5)")
    bgm_sub = p_bgm.add_subparsers(dest="bgm_command", required=True)

    p_bgm_setup = bgm_sub.add_parser("setup", help="Clone ACE-Step and uv sync")
    p_bgm_setup.add_argument("--force", action="store_true", help="Re-clone even if present")
    p_bgm_setup.set_defaults(func=_cmd_bgm_setup)

    p_bgm_status = bgm_sub.add_parser("status", help="Show ACE-Step install / API status")
    p_bgm_status.set_defaults(func=_cmd_bgm_status)

    p_bgm_ui = bgm_sub.add_parser("ui", help="Start ACE-Step Gradio UI (blocking)")
    p_bgm_ui.set_defaults(func=_cmd_bgm_ui)

    p_bgm_api = bgm_sub.add_parser("api", help="Start ACE-Step REST API (blocking)")
    p_bgm_api.set_defaults(func=_cmd_bgm_api)

    p_bgm_gen = bgm_sub.add_parser("generate", help="Generate BGM via running ACE-Step API")
    p_bgm_gen.add_argument("--prompt", required=True, help="Text prompt for music")
    p_bgm_gen.add_argument("--out", help="Output audio path")
    p_bgm_gen.add_argument("--api", default=acestep.DEFAULT_API, help="API base URL")
    p_bgm_gen.add_argument("--duration", type=float, default=None, help="Optional duration seconds")
    p_bgm_gen.set_defaults(func=_cmd_bgm_generate)

    # --- Sync ---
    p_sync = sub.add_parser("sync", help="Sync output/ audio assets to Godot project + ATTRIBUTION.json")
    p_sync.add_argument(
        "--target",
        default=None,
        help=f"Target Godot audio dir (default: {DEFAULT_GODOT_AUDIO_DIR})",
    )
    p_sync.add_argument("--dry-run", action="store_true", help="Preview sync without copying or writing files")
    p_sync.add_argument("--force", action="store_true", help="Overwrite existing destination files")
    p_sync.set_defaults(func=_cmd_sync)

    # --- Addons ---
    p_addons = sub.add_parser("addons", help="Manage shared Godot addons (gu_core, gu_gameplay)")
    addons_sub = p_addons.add_subparsers(dest="addons_command", required=True)

    p_addons_sync = addons_sub.add_parser("sync", help="Sync godot/addons/ into a Godot project")
    p_addons_sync.add_argument(
        "--target",
        default=None,
        help=f"Target Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})",
    )
    p_addons_sync.add_argument("--addon", action="append", help="Specific addon to sync (repeatable)")
    p_addons_sync.add_argument("--dry-run", action="store_true", help="Preview addon changes without writing")
    p_addons_sync.add_argument("--prune", action="store_true", help="Remove stale files inside synced addons")
    p_addons_sync.set_defaults(func=_cmd_addons_sync)

    # --- Init ---
    p_init = sub.add_parser("init", help="Scaffold a new Godot 4.6 game project from shared skeleton")
    p_init.add_argument("target", help="Target directory for the new Godot project")
    p_init.add_argument("--name", default=None, help="Application name in project.godot")
    p_init.add_argument("--force", action="store_true", help="Overwrite existing project.godot/template files")
    p_init.add_argument("--dry-run", action="store_true", help="Preview scaffolded files without writing")
    p_init.set_defaults(func=_cmd_init)

    # --- Assets Audit & Credits ---
    p_assets = sub.add_parser("assets", help="Audit project assets and generate CREDITS.md")
    assets_sub = p_assets.add_subparsers(dest="assets_command", required=True)

    p_assets_audit = assets_sub.add_parser("audit", help="Scan project assets/ for license and commercial status")
    p_assets_audit.add_argument("--target", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_assets_audit.add_argument("--write", action="store_true", help="Write ASSETS_ATTRIBUTION.json")
    p_assets_audit.add_argument("--strict", action="store_true", help="Exit 1 if unknown or non-commercial assets exist")
    p_assets_audit.set_defaults(func=_cmd_assets_audit)

    p_assets_credits = assets_sub.add_parser("credits", help="Generate CREDITS.md from project assets")
    p_assets_credits.add_argument("--target", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_assets_credits.add_argument("--out", default=None, help="Output markdown path (default: <target>/CREDITS.md)")
    p_assets_credits.set_defaults(func=_cmd_assets_credits)

    # --- Data Tables & Localization ---
    p_data = sub.add_parser("data", help="Validate and build CSV/JSON game data tables")
    data_sub = p_data.add_subparsers(dest="data_command", required=True)

    p_data_val = data_sub.add_parser("validate", help="Validate CSV/JSON tables and localization CSVs")
    p_data_val.add_argument("src", help="Source data directory")
    p_data_val.set_defaults(func=_cmd_data_validate)

    p_data_extract = data_sub.add_parser("extract", help="Merge tr() keys into a localization CSV")
    p_data_extract.add_argument("--scan", action="append", required=True, help="File or directory to scan (repeatable)")
    p_data_extract.add_argument("--out", required=True, help="Localization CSV to create or update")
    p_data_extract.add_argument(
        "--locales",
        default="en,zh",
        help="Locale columns used only when --out does not exist yet",
    )
    p_data_extract.set_defaults(func=_cmd_data_extract)

    p_data_build = data_sub.add_parser("build", help="Validate and compile data tables into Godot JSON")
    p_data_build.add_argument("src", help="Source data directory")
    p_data_build.add_argument("--out", required=True, help="Output Godot data directory")
    p_data_build.add_argument("--dry-run", action="store_true", help="Preview output files without writing")
    p_data_build.set_defaults(func=_cmd_data_build)

    # --- Quality Gate & Export ---
    p_test = sub.add_parser("test", help="Run the Godot headless test runner, including the play-flow smoke")
    p_test.add_argument("--project", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_test.add_argument("--godot", default=None, help="Path to Godot binary")
    p_test.add_argument("--skip-godot", action="store_true", help="Skip the Godot process")
    p_test.set_defaults(func=_cmd_test)

    p_check = sub.add_parser("check", help="Run addons parity, pytest, and Godot headless checks")
    p_check.add_argument("--project", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_check.add_argument("--godot", default=None, help="Path to Godot binary")
    p_check.add_argument("--skip-pytest", action="store_true", help="Skip pytest step")
    p_check.add_argument("--skip-godot", action="store_true", help="Skip Godot headless checks")
    p_check.add_argument("--frames", type=int, default=30, help="Frames for smoke run (default: 30)")
    p_check.set_defaults(func=_cmd_check)

    p_export = sub.add_parser("export", help="Headless Godot export using export_presets.cfg")
    p_export.add_argument("--project", default=None, help=f"Godot project dir (default: {DEFAULT_GODOT_PROJECT_DIR})")
    p_export.add_argument("--preset", required=True, help="Export preset name from export_presets.cfg")
    p_export.add_argument("--out", required=True, help="Output artifact path")
    p_export.add_argument("--godot", default=None, help="Path to Godot binary")
    p_export.add_argument("--debug", action="store_true", help="Use --export-debug instead of --export-release")
    p_export.add_argument("--dry-run", action="store_true", help="Validate preset and print command without running")
    p_export.set_defaults(func=_cmd_export)

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args.func = _cmd_home
    try:
        code = args.func(args)
    except Exception as exc:  # noqa: BLE001 - CLI boundary
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    raise SystemExit(code)


if __name__ == "__main__":
    main()
