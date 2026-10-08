# Trust Issues

A co-op train chase (then a sea chase) with a secret impostor. Made with **Godot 4** (GDScript), with assets from **Tripo3D**, cleaned up in **Blender**.

- Game Design Doc: [`docs/GDD.md`](docs/GDD.md)
- Workflow and phases: [`docs/WORKFLOW_PLAN.md`](docs/WORKFLOW_PLAN.md) · the video's method: [`docs/VIDEO_METHOD.md`](docs/VIDEO_METHOD.md)
- Asset image prompts for Higgsfield: [`docs/ASSET_PROMPTS.md`](docs/ASSET_PROMPTS.md)
- ⚠️ **Open TODOs for when the repo moves to your PC: [`docs/TODO_LOCAL.md`](docs/TODO_LOCAL.md)** (full video analysis, MCP setup)

## Current prototype: Chapter 1 train core (grey boxes)

Open the folder in **Godot 4.7** (standard build, 4.7.2), then press **F5** (Run Project).

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
- First-person player with cartoony hands, a tool hotbar, and carrying items; can ride the moving train.
  Every tool has its own first-person animation (hammer overhead swing with a camera kick, wrench twist with a ratchet
  tick, nail gun recoil and puff, welder steady hand with sparks, two-handed come-along pump) and every carried item
  its own pose (plank on the shoulder, rail low with a strained bob, wheel in front, panel flat at chest height)
- **A full run, station 0 to station 5**: each segment has pre-placed gaps (2 in the first, then 3) and one **locked gate**
  across the rails (striped boom, padlock, red lamp, a red signal post 120 m before it). Its **glowing key lies right
  beside the track**: pick it up [E], use it on the padlock [E], the boom swings up (placeholder until the quest maps).
  An objective line on the HUD says what to do next ("Gate locked: find the key", "Rebuild the broken track ahead"...)
- **Chapter 1 complete** screen at the port with the run stats (time, distance, track rebuilt, panels, wheels lost,
  gates, gold), then *Back to main menu* (`Game.return_to_menu()`, reloads Main while there is no menu scene) or *Keep exploring*
- **Balance**: supplies beside every gap and gate, softlock guards (supply crate, coal crate, emergency wheel, a limping
  train can always reach a station). See the balance table in the GDD

### Controls
| Key | Action |
|-----|--------|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse · LMB | Look · use tool (hammer hit, nail gun shot, hold to weld) |
| 1–5 (or mouse wheel) | Hammer / wrench / nail gun (once bought) / welder (only while holding a station torch) / come-along |
| E · Q · G | Use / place carried item · alternative use · put the carried item back |
| F1 | Show/hide help |
| F2 | Debug: play as **impostor** (**Tab** = sabotage menu, then 1–4; meteor: aim + LMB) |
| F3 | Debug: world sabotage on/off |
| F5 / F6 | Last checkpoint / new game |

### Rebuilding the models
```bash
blender --background --python blender/scripts/build_assets.py -- .      # train, tools, repair items, gate, key
blender --background --python blender/scripts/build_assets.py -- . only=gate   # just the locked gate, signal post, key
blender --background --python blender/scripts/build_nature.py -- .      # trees, rocks, cliffs, bushes
blender --background --python blender/scripts/render_icons.py -- . [only=key]   # item icons (assets/icons)
blender --background --python blender/scripts/render_showcase.py -- . renders [shots=gate]   # preview pictures
```

### Tests
```bash
godot --headless --path . --import                     # once, after pulling new assets
godot --headless --path . res://tests/TestTrain.tscn   # automated playthrough of the core loop, exit code 0 = pass
godot --headless --path . res://tests/TestRoute.tscn   # the whole Chapter 1 route: gaps, 5 gates and keys, every
                                                       # checkpoint, the end screen and a station 3 restart (~1-2 min)
# screenshots (needs a display or xvfb): modes repair, train, gate, end, tools
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/Screenshot.tscn -- shots gate
```

### Not built yet (see GDD milestones)
Multiplayer (M1) · meeting-table voting (M4) · carry system + revive (M5) · intro and kidnap (M6) · crafting (M7) · **quest maps (next; the keys lie beside the gates until then)** · Chapter 2 sea
