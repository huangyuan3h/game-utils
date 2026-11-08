# Game Utils — Concept

## Problem

Making games is hard for independent developers — not mainly because of code, but because of **assets**:

- Music and SFX: licensing, quality, style consistency
- 3D models / characters: modeling skill, topology, animation-ready rigs
- Textures, sprites, UI kits: visual coherence across the whole game
- Formats and pipelines: different engines expect different layouts

Searching marketplaces, Discord servers, and free asset packs one by one does not scale. There is no single place that answers: **“I need X for my game — where do I get it, under what license, and how do I use it?”**

## Vision

**game-utils** is a unified entry point for game asset discovery, evaluation, and integration.

It does not try to replace Blender, Unity, or Unreal. It sits **before** and **beside** the creative tools:

```
Need asset → game-utils → shortlist / generate / convert → drop into engine
```

## First vertical: Audio shell

We start with audio because SFX can ship with zero GPU, and open music models are finally usable locally.

| Surface | Backends | Notes |
|---------|----------|-------|
| **SFX** | builtin (Python) → jsfxr (JS) → rFXGen (C) | Instant WAV presets |
| **BGM** | ACE-Step 1.5 (Python / `uv`) | Gradio UI + REST API |

See `docs/research-audio-tools.md` and `docs/audio-shell.md`.

## Goals (v0 thinking)

1. **One door** — Search and browse asset sources from one place (free + paid + generative).
2. **License clarity** — Surface license terms early (commercial use, attribution, redistribution).
3. **Engine-aware** — Prefer outputs that are ready for common engines (Unity, Godot, Unreal) or easy to convert.
4. **Style coherence** — Help keep music, models, and art in a consistent mood / art direction.
5. **Practical over perfect** — Favor “good enough, shippable today” over endless hunting.

## Non-goals (for now)

- Becoming a full game engine
- Hosting a new asset marketplace (may index / link existing ones)
- Replacing professional DCC tools (Blender, Substance, DAW, etc.)

## Design principles

- **Docs first**: Capture decisions here before coding features.
- **Composable**: Small utilities > one monolithic app.
- **Transparent**: Prefer open formats and clear provenance.
- **Indie-friendly**: Optimize for solo / small-team workflows.

## Next steps (open)

- [x] Research open audio tools
- [x] Audio shell: SFX + BGM launchers
- [ ] Install Node for real jsfxr path (optional)
- [ ] Run ACE-Step setup on a machine with GPU
- [ ] Decide primary interface beyond CLI (web later?)

## Notes

This document is a living concept sketch. Update it when the product direction changes.
