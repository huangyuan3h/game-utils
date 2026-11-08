# SFX Direction Pivot

Date: 2026-11-08

## Feedback

Procedural sfxr-style generation feels low value: random, hard to control, and “beepy”. We want **natural / realistic sound collections** instead.

## New default

| Priority | Approach | Role |
|----------|----------|------|
| **1** | Curated realistic libraries (Kenney CC0, Mixkit, Sonniss GDC, Freesound) | Main SFX path |
| **2** | Local import + organize under `output/sfx/library/` | Make packs usable in-engine |
| **3** | Later: Freesound API search / Stable Audio Open | Find or synthesize specific Foley |
| **low** | Procedural synth (builtin / jsfxr / rFXGen) | Placeholder only |

## Recommended sources

1. **Sonniss GDC bundles** — best free pro Foley for games (large download)
2. **Mixkit** — quick realistic clips, no signup
3. **Kenney audio packs** — CC0, consistent, good for UI / light game cues
4. **Freesound** — specific field recordings; always filter license (prefer CC0 / CC BY)

## Workflow

```
need (footsteps) → open suggested collection → download zip
  → gu-audio sfx import ~/Downloads/pack.zip
  → files in output/sfx/library/<pack>/
```

## Non-goal

Do not invest more UX into random beep generators unless someone explicitly needs jam placeholders.
