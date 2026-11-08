# Audio Shell — Architecture

## Tool tech stacks

| Tool | Language | How we drive it | Ease |
|------|----------|-----------------|------|
| **jsfxr** | JavaScript (npm) | Node script / `npm i jsfxr` | Easy if Node exists; preset → WAV |
| **rFXGen** | C (raylib) | Prebuilt binary or compile; CLI `--generate coin` | Easy once binary is on PATH |
| **ACE-Step 1.5** | Python (`uv`) | Clone repo → `uv run acestep` / `acestep-api` | Medium: GPU + first model download |

## Shell layout

```
shell/
  README.md
  pyproject.toml
  src/game_utils_audio/     # Python CLI entry: `gu-audio` / `python -m game_utils_audio`
    cli.py                  # two sections: sfx | bgm
    sfx/                    # sound effects
    bgm/                    # background music (ACE-Step)
  vendors/                  # cloned tools (gitignored), e.g. ACE-Step-1.5
  output/                   # generated wav/mp3
```

## Two product surfaces

1. **SFX** — fast, no GPU  
   - Default backend: built-in procedural synth (sfxr-style presets)  
   - Optional: `jsfxr` (Node), `rfxgen` (binary)

2. **BGM** — ACE-Step 1.5  
   - `setup` → clone + `uv sync`  
   - `ui` / `api` → start Gradio or REST server  
   - `generate` → call local API when server is up

## Design rules

- Shell owns UX; vendors stay upstream clones when possible.
- Prefer offline / local generation for indie workflows.
- Always write license + backend + prompt/seed metadata next to outputs.
