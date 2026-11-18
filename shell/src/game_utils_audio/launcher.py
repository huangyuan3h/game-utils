"""Top-level interactive entry. The test game is its own item, not an audio tool."""

from __future__ import annotations

from game_utils_audio.menu import run_menu
from game_utils_audio.play import launch_test_game


def run_home() -> int:
    while True:
        print()
        print("=" * 48)
        print("  game-utils")
        print("=" * 48)
        print("  1. Play test game (Walk Sandbox)")
        print("  2. Audio tools")
        print("  0. Exit")
        print("-" * 48)
        print("  Other: ./start.sh check | addons sync | init ...")

        choice = input("Select: ").strip()
        if choice in {"0", "q", "Q", "exit"}:
            print("Bye.")
            return 0
        if choice == "1":
            launch_test_game()
            return 0
        if choice == "2":
            return run_menu()
        print("Invalid choice.")
