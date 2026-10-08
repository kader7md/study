# Trust Issues

A co-op train chase (then a sea chase) with a secret impostor. Made with **Godot 4** (GDScript), with assets from **Tripo3D**, cleaned up in **Blender**.

- Game Design Doc: [`docs/GDD.md`](docs/GDD.md)
- Workflow and phases: [`docs/WORKFLOW_PLAN.md`](docs/WORKFLOW_PLAN.md) · the video's method: [`docs/VIDEO_METHOD.md`](docs/VIDEO_METHOD.md)
- ⚠️ **Open TODOs for when the repo moves to your PC: [`docs/TODO_LOCAL.md`](docs/TODO_LOCAL.md)** (full video analysis, MCP setup)

## Current prototype: Chapter 1 train core (grey boxes)

Open the folder in **Godot 4.7** (standard build, 4.7.2), then press **F5** (Run Project).

What's in it:
- **Track** with 6 stations: departure + 5 checkpoints (420 m apart for now; the real game will be longer)
- **Train**: locomotive, cargo, utility car, locked container. Furnace + coal, a 3-way lever (forward / stop / reverse)
- **Track damage**: pre-placed broken rails and meteor craters. The train stops at a gap and **crashes** if it hits one fast
- **Repairs**: rails (2 wood + 2 nails, hold E); train body patch up to 60 % (2 scrap)
- **Station-only repairs**: arc welding to 100 %, fitting new wheels
- **Shop** at every station (nails, wheel, engine oil, hammer, nail gun, medkit, grappler, coal)
- **Checkpoints**: stopping in the next station saves. If all players die, you go back to the last checkpoint
- **Sabotage** with cooldowns: ☄ meteor (aimed, falls for 3 s so it can miss), 🧟 zombies, 🦅 eagles (steal cargo), 🌬 freezing wind (slower train, more coal used, frost unless near the furnace)
- **Resources** along the track: coal, wood, scrap, gold rocks (mine with E)
- First-person player who can **ride the moving train**, a shovel attack, and frost

### Controls
| Key | Action |
|-----|--------|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse · LMB | Look · shovel attack |
| E / hold E · Q | Use / repair · alternative use (e.g. pull the lever back) |
| F1 | Show/hide help |
| F2 | Debug: play as **impostor** (keys **1–4** = sabotage, meteor: aim + LMB) |
| F3 | Debug: world sabotage on/off (random sabotage when there's no impostor) |
| F5 / F6 | Last checkpoint / new game |

### Tests
```bash
godot --headless --path . res://tests/TestTrain.tscn   # automated playthrough of the core loop, exit code 0 = pass
```

### Not built yet (see GDD milestones)
Multiplayer (M1) · meeting-table voting (M4) · carry system + revive (M5) · intro and kidnap (M6) · crafting (M7) · **locked routes + quest maps (next)** · Chapter 2 sea
