"""Interactive launcher — realistic SFX collections first, BGM second."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from game_utils_audio.bgm import acestep
from game_utils_audio.paths import OUTPUT_DIR, ensure_output_dirs
from game_utils_audio.sfx import builtin
from game_utils_audio.sfx.catalog import list_collections, list_needs
from game_utils_audio.sfx import library as sfx_library


def _pause() -> None:
    input("\nPress Enter to continue...")


def _play(path: Path) -> None:
    player = shutil.which("afplay") or shutil.which("ffplay") or shutil.which("aplay")
    if not player:
        print(f"(No audio player found; open the file manually: {path})")
        return
    print(f"Playing {path.name} ...")
    cmd = [player, str(path)]
    if player.endswith("ffplay"):
        cmd = [player, "-nodisp", "-autoexit", str(path)]
    subprocess.run(cmd, check=False)


def _open_output() -> None:
    ensure_output_dirs()
    sfx_library.ensure_library_dirs()
    if sys.platform == "darwin":
        subprocess.run(["open", str(OUTPUT_DIR)], check=False)
    elif sys.platform.startswith("linux"):
        opener = shutil.which("xdg-open")
        if opener:
            subprocess.run([opener, str(OUTPUT_DIR)], check=False)
    else:
        print(f"Output folder: {OUTPUT_DIR}")


def _bgm_status() -> None:
    st = acestep.status()
    print("BGM / ACE-Step status:")
    print(f"  installed : {st['installed']}")
    print(f"  path      : {st['path']}")
    print(f"  uv / git  : {st['uv']} / {st['git']}")
    print(f"  API up    : {st['api_up']} ({st['api_url']})")
    print(f"  UI URL    : {st['ui_url']}")
    if not st["installed"]:
        print("\nTip: choose “Setup ACE-Step” first (large download, GPU recommended).")


def _pick_from_list(title: str, labels: list[str]) -> int | None:
    print(title)
    for i, label in enumerate(labels, start=1):
        print(f"  {i}. {label}")
    print("  0. Back")
    raw = input("Select: ").strip()
    if raw in {"0", ""}:
        return None
    try:
        n = int(raw)
    except ValueError:
        print("Invalid choice.")
        return None
    if not 1 <= n <= len(labels):
        print("Invalid choice.")
        return None
    return n - 1


def _menu_by_need() -> None:
    needs = list_needs()
    idx = _pick_from_list(
        "What kind of sound do you need?",
        [f"{n['id']} — {n['title']}" for n in needs],
    )
    if idx is None:
        return
    sfx_library.open_need(needs[idx]["id"])


def _menu_collections() -> None:
    cols = list_collections()
    idx = _pick_from_list(
        "Collections (opens download / browse page):",
        [f"{c['id']} — {c['name']} [{c['license']}]" for c in cols],
    )
    if idx is None:
        return
    sfx_library.open_collection(cols[idx]["id"])


def _menu_import() -> None:
    sfx_library.ensure_library_dirs()
    print("Import a downloaded pack into the local library.")
    print(f"Default drop folder: {sfx_library.INCOMING_DIR}")
    path = input("Path to .zip or folder (Enter = list incoming): ").strip()
    if not path:
        incoming = sorted(sfx_library.INCOMING_DIR.iterdir()) if sfx_library.INCOMING_DIR.exists() else []
        if not incoming:
            print("Incoming folder is empty. Download a pack, put the zip there, then import.")
            return
        idx = _pick_from_list("Incoming files:", [p.name for p in incoming])
        if idx is None:
            return
        src = incoming[idx]
    else:
        src = Path(path)
    name = input("Pack name (Enter = auto): ").strip() or None
    sfx_library.import_path(src, pack_name=name)


def _menu_placeholder_synth() -> None:
    presets = builtin.list_presets()
    idx = _pick_from_list(
        "Placeholder synth (8-bit beeps — low priority / prototype only):",
        presets,
    )
    if idx is None:
        return
    ensure_output_dirs()
    preset = presets[idx]
    out = OUTPUT_DIR / "sfx" / "placeholder" / f"{preset}.wav"
    path = builtin.generate_file(preset, out)
    print(f"Wrote {path}")
    _play(path)


def run_menu() -> int:
    ensure_output_dirs()
    sfx_library.ensure_library_dirs()

    while True:
        print()
        print("=" * 48)
        print("  game-utils · Audio Launcher")
        print("=" * 48)
        print("  Realistic SFX (recommended)")
        print("    1. Browse by need (footsteps / nature / doors…)")
        print("    2. Browse curated collections")
        print("    3. Import downloaded pack → local library")
        print("    4. List local library")
        print("    5. Open output / library folder")
        print()
        print("  BGM")
        print("    6. ACE-Step status")
        print("    7. Setup ACE-Step")
        print("    8. Start ACE-Step UI")
        print()
        print("  Other")
        print("    9. Placeholder synth beeps (not recommended)")
        print("    0. Exit")
        print("-" * 48)

        choice = input("Select: ").strip()
        if choice in {"0", "q", "Q", "exit"}:
            print("Bye.")
            return 0

        try:
            if choice == "1":
                _menu_by_need()
            elif choice == "2":
                _menu_collections()
            elif choice == "3":
                _menu_import()
            elif choice == "4":
                sfx_library.print_imported()
            elif choice == "5":
                _open_output()
            elif choice == "6":
                _bgm_status()
            elif choice == "7":
                confirm = input("Large download. Continue? [y/N] ").strip().lower()
                if confirm == "y":
                    acestep.setup()
                else:
                    print("Cancelled.")
            elif choice == "8":
                if not acestep.is_installed():
                    print("ACE-Step not installed yet. Run setup first.")
                else:
                    print("Starting UI (Ctrl+C to stop)...")
                    acestep.start_ui()
            elif choice == "9":
                _menu_placeholder_synth()
            else:
                print("Invalid choice.")
        except KeyboardInterrupt:
            print("\nInterrupted.")
        except Exception as exc:  # noqa: BLE001
            print(f"error: {exc}")

        _pause()
