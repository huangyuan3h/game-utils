# Godot UI vs HTML/CSS

## The gap you felt

HTML + CSS is built for **layout, typography, and polish**.  
Godot `Control` nodes are built for **game HUDs** bound to the scene tree — default look is plain until you theme them.

| Surface | Better tool |
|---------|-------------|
| In-world character, map, camera | Godot (this walk sandbox) |
| Fancy menus / store / settings pages | HTML/CSS (WebView / export web) **or** heavily themed Godot UI |
| Mixed | Godot game + HTML overlay for menus only |

## Strategy for this repo

1. **First prove gameplay** — move a real character on a map (walk-sandbox).
2. **Then decide UI shell** — native Godot theme vs embedded web UI.
3. Do not block movement prototypes on “editor looks ugly”.

Finding the gap by building is the right call.
