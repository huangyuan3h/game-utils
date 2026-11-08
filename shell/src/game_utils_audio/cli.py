from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from game_utils_audio import __version__
from game_utils_audio.bgm import acestep
from game_utils_audio.menu import run_menu
from game_utils_audio.paths import BGM_OUTPUT_DIR, SFX_OUTPUT_DIR, ensure_output_dirs
from game_utils_audio.sfx import builtin, jsfxr, library as sfx_library, rfxgen


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


def _cmd_menu(_: argparse.Namespace) -> int:
    return run_menu()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gu-audio",
        description="game-utils audio shell — realistic SFX collections + BGM (ACE-Step)",
    )
    parser.add_argument("--version", action="version", version=f"gu-audio {__version__}")
    sub = parser.add_subparsers(dest="command", required=False)

    p_menu = sub.add_parser("menu", help="Interactive launcher (default)")
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

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "command", None):
        args.func = _cmd_menu
    try:
        code = args.func(args)
    except Exception as exc:  # noqa: BLE001 - CLI boundary
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    raise SystemExit(code)


if __name__ == "__main__":
    main()
