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
- **Train made in Blender** (`blender/scripts/build_train.py` → `assets/models/`): steam locomotive, cargo wagon,
  utility wagon (welder machine), locked container. Furnace + coal, 3-way lever
- **Hands-on track repair**: take planks → place → nail (hammer 3 hits / nail gun) → take rails → place → weld both ends
- **Welder** with a **cable** to a welder machine (train: 35 m, rails + body up to 60 %; station: body up to 100 %)
- **Wheels** fall off in crashes: carry a new one, lift it into place, bolt it with the hammer
- **Breakable train cover**: walls, roofs, doors and boiler plates fly off when damaged. Pick them up (or take a new panel),
  place them, then nail (wood) or weld (metal). Doors open with E
- **Shop** at every station, **checkpoints**, back to the last checkpoint if everyone dies
- **Sabotage**: meteor (aimed), zombies, eagles (steal cargo), freezing wind
- First-person player with cartoony hands, a tool hotbar, and carrying items; can ride the moving train

### Controls
| Key | Action |
|-----|--------|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse · LMB | Look · use tool (hammer hit, nail gun shot, hold to weld) |
| 1 / 2 / 3 (or mouse wheel) | Hammer / welder / nail gun |
| E · Q · G | Use / place carried item · alternative use · put the carried item back |
| F1 | Show/hide help |
| F2 | Debug: play as **impostor** (**Tab** = sabotage menu, then 1–4; meteor: aim + LMB) |
| F3 | Debug: world sabotage on/off |
| F5 / F6 | Last checkpoint / new game |

### Rebuilding the train models
```bash
blender --background --python blender/scripts/build_train.py -- .
```

### Tests
```bash
godot --headless --path . res://tests/TestTrain.tscn   # automated playthrough of the core loop, exit code 0 = pass
```

### Not built yet (see GDD milestones)
Multiplayer (M1) · meeting-table voting (M4) · carry system + revive (M5) · intro and kidnap (M6) · crafting (M7) · **locked routes + quest maps (next)** · Chapter 2 sea
