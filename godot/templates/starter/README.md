# Game Starter

A playable Godot 4.6 project scaffolded by `game-utils`.

## Controls

- **WASD / Arrows**: move relative to the camera
- **Shift**: toggle run
- **Space**: strike
- **E**: interact (talk to the guide)
- **Scroll / `+` `-`**: camera zoom
- **`I`**: inventory
- **ESC**: pause menu / save slots / settings

## What is wired

- `gu_core` autoloads: settings, input contexts, audio buses, save slots, UI router, game flow, clock, events, pools, dev console.
- `GuPlayer` and `CameraRig` from `gu_gameplay`.
- A guide NPC (`DialogueInteractable`), a `DialogueBox`, an interaction prompt, and a quest HUD.
- A sample quest (`meet_guide`) and guide dialogue loaded from `data/content/`.

## Add content

Edit the JSON tables under `data/content/`:

| File | Rows |
|------|------|
| `quests.json` | `id`, `title`, `description`, `objectives`, `rewards`, `auto_start` |
| `dialogue.json` | `id`, `start`, `nodes` with text, choices, conditions, and effects |
| `items.json` | `id`, `display_name`, `max_stack`, `tags` |

Text is authored in English and translated through `data/ui_i18n.csv` (`keys,en,zh`).
`tr()` resolves it at render time, so missing translations fall back to English.

Validate and run the quality gate from the game-utils repository:

```bash
# from the game-utils repository
./start.sh data validate path/to/this/project/data
./start.sh check --project path/to/this/project
```
