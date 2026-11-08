# Architecture — Language & Multi-Asset Plan

## Short answer

**Yes: Python is a good shell language for game-utils** — as an **orchestrator**, not as the only implementation language.

| Role | Language | Why |
|------|----------|-----|
| Shell / job runner / CLI | **Python** | Best fit for gen-AI & local ML tooling; ACE-Step already Python; easy subprocess/HTTP adapters |
| Optional web UI (later) | **TypeScript** | Asset browser, preview, queues — UI strength |
| Individual backends | **Native** | Keep jsfxr=JS, rFXGen=C, Blender=Python API, ComfyUI=its own stack |

Do **not** rewrite jsfxr into Python or ACE-Step into Node. The shell **calls** tools; it does not absorb them.

---

## Why Python works for the shell

1. **Upstream gravity** — Music (ACE-Step), image gen (Diffusers / ComfyUI clients), many 3D/pipeline scripts speak Python or HTTP that Python wraps well.
2. **Glue strength** — `subprocess`, files, ZIP packs, metadata JSON, simple REST clients — zero drama.
3. **Indie ops** — `uv` already in the stack; one toolchain for shell + ACE-Step setup.
4. **2D / character roadmaps** — Most open pipelines (SDXL, ControlNet, IP-Adapter, rembg, sprite sheet tools) are Python-adjacent or HTTP-from-Python.

## When Python would be the wrong *center*

- Product becomes a **rich interactive studio in the browser** first → put UX in TypeScript; Python stays a worker/API.
- You need a **single static binary** for non-technical users with no Python → consider Go/Rust *packaging* later; still can embed or call Python workers.
- Team is JS-only and refuses Python → Node orchestrator is possible, but you will fight more ML installs (ACE-Step, ComfyUI).

For this repo’s stated goal (unified asset entry for indie games), **Python orchestrator + TS UI later** is the balanced plan.

---

## Core design: adapters, not a monolith

```
┌─────────────────────────────────────────┐
│  Interfaces (CLI today / Web later)     │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│  Orchestrator (Python)                  │
│  - jobs, presets, output layout         │
│  - license/meta sidecar files           │
│  - backend registry                     │
└─────────────────┬───────────────────────┘
                  │
     ┌────────────┼────────────┬──────────────┐
     ▼            ▼            ▼              ▼
  SFX adapter  BGM adapter  2D adapter   Character…
  builtin/     ACE-Step     Comfy/SD     …adapters
  jsfxr/rfxgen  (HTTP/CLI)  (HTTP/CLI)
```

### Stable contract (language-agnostic)

Every generation job should look roughly like:

```json
{
  "category": "sfx | bgm | background_2d | character | item",
  "backend": "builtin | jsfxr | acestep | comfyui | ...",
  "prompt_or_preset": "...",
  "params": {},
  "seed": 42,
  "out_dir": "output/..."
}
```

Every result writes:

- asset file(s): `.wav` / `.png` / `.webp` / …
- `*.meta.json`: backend, version, prompt, seed, license notes

This contract lets us swap UI (CLI → web) without rewriting backends.

---

## Category roadmap (planning, not commitment)

| Phase | Category | Likely backends | Shell work |
|-------|----------|-----------------|------------|
| **Now** | SFX | builtin, jsfxr, rFXGen | Done (thin adapters) |
| **Now** | BGM | ACE-Step 1.5 | Launch + API client |
| **Next** | 2D background | ComfyUI / Diffusers / external APIs | New adapter + style presets |
| **Next** | Characters / items | Same + rembg / sprite sheet / size packs | Post-process pipeline |
| **Later** | 3D models | Blender headless, Meshy-like OSS, format convert | Separate heavier worker |

Each new category = **one adapter package + docs + presets**, not a new shell language.

---

## Repo shape (target)

```
game-utils/
  docs/                 # concepts, research, architecture
  shell/                # Python orchestrator (gu-audio → later gu / game-utils)
  apps/web/             # optional future TS UI
  adapters/             # optional: split sfx/bgm/2d as packages when large
  output/               # generated assets (gitignored)
  vendors/              # cloned upstream tools (gitignored)
```

Today `shell/` already matches the orchestrator role. Rename CLI from `gu-audio` → `gu` when a second category lands.

---

## Decision record

| Decision | Choice | Revisit when |
|----------|--------|--------------|
| Orchestrator language | **Python 3.11+** | Team cannot run Python, or product is UI-first with no local ML |
| Backend policy | Native runtime + adapter | A backend becomes the product itself |
| UI | CLI first; TS web later | We need browse/preview/queue UX |
| Packaging | `uv` project | We need one-click .app for artists |

---

## Practical guidance

- **Keep** Python for the shell.
- **Invest** in clear adapter interfaces and `meta.json` provenance.
- **Defer** rewriting tools into one language.
- **Add** TypeScript only when building a real asset browser UI.
- **Treat** 2D/character as new adapters sharing the same job/output conventions.

This keeps short-term shipping (audio) aligned with long-term multi-asset growth.
