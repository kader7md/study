# Trust Issues

A co-op train chase (then a sea chase) with a secret impostor. Made with **Godot 4** (GDScript), with assets from **Tripo3D**, cleaned up in **Blender**.

- Game Design Doc: [`docs/GDD.md`](docs/GDD.md)
- Workflow and phases: [`docs/WORKFLOW_PLAN.md`](docs/WORKFLOW_PLAN.md) · the video's method: [`docs/VIDEO_METHOD.md`](docs/VIDEO_METHOD.md)
- Asset image prompts for Higgsfield: [`docs/ASSET_PROMPTS.md`](docs/ASSET_PROMPTS.md)
- ⚠️ **Open TODOs for when the repo moves to your PC: [`docs/TODO_LOCAL.md`](docs/TODO_LOCAL.md)** (full video analysis, MCP setup)

## Current prototype: Chapter 1 train core (grey boxes)

Open the folder in **Godot 4.7** (standard build, 4.7.2), then press **F5** (Run Project).

### Menu, hosting and joining
- The game starts on the **title screen** (`scenes/menu/MainMenu.tscn`): **Host game**, **Join game**, **Settings**, **Quit**.
  Type your name in the card at the bottom right.
- **Host game** opens the lobby (once the multiplayer layer is in; until then it starts a solo run straight away).
  Solo play is hosting with nobody else.
- **Join game** asks for the host's **invite code** (or `IP:port`) and your name.
- **Esc** in game opens the **pause menu**: Resume, Settings, Back to menu, Quit. Solo play pauses; online it keeps running.
- **Settings** (also in the pause menu), saved in `user://settings.cfg`:
  Controls (rebind every key or mouse button, reset to defaults, mouse sensitivity, invert Y) ·
  Graphics (window mode, V-Sync, resolution scale, shadows, anti-aliasing, FOV, max FPS) ·
  Audio (Master, Music, SFX, Voice) · Microphone (input device, live level meter, hear-yourself test, push to talk).
  **F11** toggles fullscreen anywhere.

What's in it:
- **Landscape**: 6 stations 1.5 km apart, through forest hills, a river valley, a mountain pass, a lake and the coast.
  Hills slow the train, and wooden trestle bridges cross the rivers and the lake
- **Detailed models made in Blender** (stylized realism, baked worn textures): steam locomotive with rivets, pistons and
  rods, boxcar, workshop wagon, rusty container, tools (hammer, nail gun, welder, welding machine), trees, rocks, cliffs.
  Furnace + coal, 3-way lever
- **Hands-on track repair**: take planks → place → nail (hammer 3 hits / nail gun) → take rails → place → bolt the fishplates
- **Welder only at stations**: take the torch from the station welder machine (30 m cable). Metal panels are welded there
- **Wheels** fall off in crashes: carry a new one, lift it into place, bolt it with the hammer
- **Breakable train cover**: walls, roofs, doors and boiler plates fly off when damaged. Pick them up (or take a new panel),
  place them, then nail (wood, anywhere) or weld (metal, at a station). Doors open with E; the cab front doors swing
  forward so you can see ahead and walk to the front of the engine
- **Shop** at every station, **checkpoints**, back to the last checkpoint if everyone dies
- **Sabotage**: meteor (aimed), zombies, eagles (steal cargo), freezing wind
- First-person player with cartoony hands, a tool hotbar, and carrying items; can ride the moving train

### Controls
| Key | Action |
|-----|--------|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse · LMB | Look · use tool (hammer hit, nail gun shot, hold to weld) |
| 1-5 (or mouse wheel) | Hammer / wrench / nail gun / welder (only while holding a station torch) / come-along |
| E · Q · G | Use / place carried item · alternative use · put the carried item back |
| Esc | Pause menu (closes the shop or Settings first) |
| V | Push to talk (voice chat, with multiplayer) |
| F1 | Show/hide help |
| F11 | Fullscreen on/off |
| F2 | Debug: play as **impostor** (**Tab** = sabotage menu, then 1–4; meteor: aim + LMB) |
| F3 | Debug: world sabotage on/off |
| F5 / F6 | Last checkpoint / new game |

### Rebuilding the models
```bash
blender --background --python blender/scripts/build_assets.py -- .      # train, tools, repair items
blender --background --python blender/scripts/build_nature.py -- .      # trees, rocks, cliffs, bushes
blender --background --python blender/scripts/render_showcase.py -- . renders   # preview pictures
```

All keys can be changed in Settings > Controls.

### Tests
```bash
godot --headless --path . --import                     # once after pulling (registers classes and imports assets)
godot --headless --path . res://tests/TestTrain.tscn   # automated playthrough of the core loop, exit code 0 = pass
godot --headless --path . res://tests/TestMenu.tscn    # settings save/load/rebind, main menu, pause menu, scene flow
# Screenshots need a display (or xvfb-run); modes: repair, train, menu, hud
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/Screenshot.tscn -- <out_dir> menu
```

### Not built yet (see GDD milestones)
Multiplayer (M1, in progress) · meeting-table voting (M4) · carry system + revive (M5) · intro and kidnap (M6) · crafting (M7) · **locked routes + quest maps (next)** · Chapter 2 sea
