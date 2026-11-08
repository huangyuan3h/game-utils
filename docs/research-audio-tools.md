# Research: Open-Source Audio & Music Tools

Date: 2026-11-08  
Scope: Free / open-source GitHub tools for **game music (BGM)** and **sound effects (SFX)** that we could integrate into game-utils.

## Summary

Two workable stacks stand out:

| Need | Best first pick | Why |
|------|-----------------|-----|
| Retro / placeholder SFX | [chr15m/jsfxr](https://github.com/chr15m/jsfxr) or [raysan5/rfxgen](https://github.com/raysan5/rfxgen) | Zero GPU, tiny, commercial-friendly, CLI/web ready |
| Realistic SFX / ambience | [Stable Audio Open](https://huggingface.co/stabilityai/stable-audio-open-1.0) via [stable-audio-tools](https://github.com/Stability-AI/stable-audio-tools) | Text → short audio; indie commercial OK under Community License (&lt;$1M revenue) |
| Full BGM / songs | [ACE-Step-1.5](https://github.com/ACE-Step/ACE-Step-1.5) | MIT, local, fast, consumer GPU, strong community |

**Caution:** Meta MusicGen / AudioCraft weights are **CC-BY-NC** — code is open, but commercial use of the weights is restricted. Prefer ACE-Step / YuE / HeartMuLa / DiffRhythm for commercial-leaning indie work.

---

## 1. AI music generation (BGM / songs)

### Tier A — practical for indie + clearer OSS licenses

| Project | Stars (approx.) | License | What it does | Fit for games |
|---------|-----------------|---------|--------------|---------------|
| [ACE-Step/ACE-Step-1.5](https://github.com/ACE-Step/ACE-Step-1.5) | ~14k+ | **MIT** | Local text-to-music; fast; &lt;4GB VRAM claimed; Mac/AMD/Intel/CUDA; LoRA personalization | **Top candidate** for BGM pipeline |
| [ace-step/ACE-Step](https://github.com/ace-step/ACE-Step) | ~5k | Apache-2.0 | Earlier ACE-Step foundation model | Prefer 1.5 unless you need v1 APIs |
| [HeartMuLa/heartlib](https://github.com/HeartMuLa/heartlib) | ~3.8k | Apache-2.0 | Lyrics + tags → songs; multilingual; codec + CLAP family | Good when you need vocals + lyric control |
| [multimodal-art-projection/YuE](https://github.com/multimodal-art-projection/YuE) | ~13k | Apache-2.0 | Full songs, covers, symbolic planning (YuE2) | Strong quality; heavier setup |
| [xiaomi-research/diffrhythm2](https://github.com/xiaomi-research/diffrhythm2) | smaller | Apache-2.0 | Full-length songs, lyric alignment | Research-grade; watch maturity |
| [FunAudioLLM/InspireMusic](https://github.com/FunAudioLLM/InspireMusic) | smaller | Apache-2.0 | Text-to-music / long-form instrumental | Better for loops / ambience BGM |

### Tier B — famous but license traps

| Project | License note | Verdict |
|---------|--------------|---------|
| [facebookresearch/audiocraft](https://github.com/facebookresearch/audiocraft) (MusicGen / AudioGen) | Code MIT; **weights CC-BY-NC 4.0** | Great demos; **avoid as default commercial path** |
| [Stability-AI/stable-audio-tools](https://github.com/Stability-AI/stable-audio-tools) + Stable Audio Open | Code MIT; weights **Stability Community License** | Commercial OK if org revenue &lt; ~$1M/year; good for SFX more than long music |

### UI / wrappers worth knowing

- [fspecii/ace-step-ui](https://github.com/fspecii/ace-step-ui) — Gradio/UI front-end for ACE-Step
- [timoncool/YuE2-Studio](https://github.com/timoncool/YuE2-Studio) — local studio UI for YuE2
- [leemysw/yovoice](https://github.com/leemysw/yovoice) — desktop AI audio/music studio (broader than games)

---

## 2. Sound effects (SFX)

### Classic procedural (easiest to integrate)

These need **no GPU**, produce tiny WAV files, and match jam / indie / retro games perfectly.

| Project | License | Integration style | Notes |
|---------|---------|-------------------|-------|
| [chr15m/jsfxr](https://github.com/chr15m/jsfxr) | permissive (sfxr port) | `npm i jsfxr` or browser; also online [sfxr.me](https://sfxr.me) | Presets: coin, laser, explosion, jump… serialize JSON → replay |
| [raysan5/rfxgen](https://github.com/raysan5/rfxgen) | zlib | Standalone + **CLI** batch `.rfx` → `.wav` | Raylib family; presets; great for offline asset baking |
| [loov/jsfx](https://github.com/loov/jsfx) | MIT | JS library / live AudioContext | Parameter recipes as JSON; good for web games |
| [increpare/bfxr](https://github.com/increpare/bfxr) | Apache-2.0 | Editor + string params | Richer than sfxr; Flash heritage but still useful |
| ChipTone (SFBGames) | outputs **CC0** | HTML5 / desktop tool | Not always the best “API to wrap”, but excellent human workflow |

### AI text-to-SFX / ambience

| Project | Strength | Caveat |
|---------|----------|--------|
| Stable Audio Open (1.0 / Small) | Text → realistic SFX, Foley, ambience (seconds–tens of seconds) | Community License revenue threshold; needs GPU |
| AudioGen (AudioCraft) | Dedicated text-to-sound | **NC weights** |

### Experimental / niche

- [marmikshah/tono](https://github.com/marmikshah/tono) — Rust deterministic SFX/music from JSON recipes; CLI + WASM; early but game-oriented
- [poormikey80-create/sfx-kitchen](https://github.com/poormikey80-create/sfx-kitchen) — tiny Python procedural SFX CLI; MIT

---

## 3. Comparison axes (what matters for game-utils)

| Criterion | Procedural SFX (jsfxr / rfxgen) | Stable Audio Open | ACE-Step 1.5 |
|-----------|----------------------------------|-------------------|--------------|
| Hardware | CPU only | Consumer GPU | Consumer GPU (&lt;4GB claimed) |
| Latency | Instant | Seconds | Seconds–tens of seconds |
| Style | Chiptune / arcade | Realistic / cinematic | Full music tracks |
| License clarity for shipping | High | Medium (Community License) | High (MIT) |
| Wrap as CLI / API | Easy | Medium | Medium |
| Style control | Parameters / presets | Text prompt | Text / tags / LoRA |

---

## 4. Recommended integration path for this repo

Phased approach — start light, add AI later:

1. **Phase 0 — SFX baker (no AI)**  
   Wrap `jsfxr` and/or `rfxgen` CLI:  
   `game-utils sfx generate --preset coin --out coin.wav`  
   Fast win, zero infra, clear licenses.

2. **Phase 1 — BGM via ACE-Step**  
   Optional local/remote worker: prompt → WAV/MP3 loop candidate.  
   Document seed, prompt, model version for reproducibility.

3. **Phase 2 — Realistic SFX**  
   Optional Stable Audio Open path for footsteps, doors, ambience — with license gate in docs/UI.

4. **Phase 3 — Vocals / full songs** (only if needed)  
   HeartMuLa / YuE as secondary backends; heavier deps.

---

## 5. Open questions

- [ ] Do we prioritize **CLI-first** (asset baking) or **web UI** (browse + preview)?
- [ ] Target engines: Unity / Godot / web — affects export formats (wav/ogg vs runtime synth)
- [ ] Will generated BGM need **loop-friendly** post-processing (fade, beat-align)?
- [ ] GPU availability for contributors (local vs hosted inference)

## 6. Sources

- GitHub repository search (music-generation, sfx tools)
- Project READMEs / licenses as of research date
- Stability AI Community License FAQ
- AudioCraft LICENSE_weights (CC-BY-NC)

---

*Living research note. Re-check stars, licenses, and VRAM claims before committing to a backend.*
