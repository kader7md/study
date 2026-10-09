# Trust Issues: notes for Claude

- Godot 4.7.2, GDScript, typed. Models come from Blender 4.5 scripts: `blender/scripts/build_assets.py` (train, tools,
  repair items) and `build_nature.py` (trees, rocks, cliffs), `build_station.py` (station canopy, platform sections, bench, lamp, gravestone, shop kiosk, name board, come-along, arm). Procedural wear is baked into one texture per model; `.glb`
  goes to `assets/models/`, loaded via `Props` / `Terrain.nature_mesh`. `render_showcase.py` renders preview pictures. Other grey-box geometry is built in code (`scripts/util/build.gd`).
- `Game` autoload (`scripts/autoload/game.gd`) holds shared state: the team pool (`inventory`, TEAM_ITEMS) and personal
  inventories (`personal`, hotbar + grid, `count/add/take` route by item and acting peer), checkpoints, signals, debug role, run
  `stats` (`add_stat`), `objective` (+ `objective_changed`), `run_finished`, `return_to_menu()`, balance (`SHOP`, `START_INVENTORY`).
  Keep state changes host-side so multiplayer (M1) can sync them later.
- Main pieces: `Track` (rail pieces, gaps, stations, landscape themes, bridges), `Terrain` (ribbon mesh along the track),
  `Train` (distance-based movement), `RailRepair`/`PlaceSlot`/`NailSpot`/`WeldSeam`/`WelderSource` (hands-on repair), `Station`,
  `SabotageManager` (+ `Meteor`, `Zombie`, `Eagle`), `Player` (+ `Viewmodel`: hands, tool animations, carry poses), `HUD`
  (`scripts/ui/hud/`: `HudStyle` look + line icons, `TrainStatus`, `HudBar`, `ItemSlot`, `KeyText`, `InventoryWindow`).
  `ActionSpot` = interactable from callables. Locked gates: `TrackGate` (`Gate_<seg>`, Track gate API) + `GateKey`
  (`Key_<seg>`). `RunDirector` (objective, softlock guards, ending) shows the `EndScreen`. Node names are deterministic
  (`Repair_<piece>`, `Pickup_<n>`, `Station<i>`) because every peer builds the world from `Main.SEED`.
- Quest maps (`scripts/quest/`): `QuestManager` (Main/Quest: portals, enter/leave, campfire checkpoints, host state +
  RPCs), `QuestPortal`, `Climber` (player climbing + stamina, `player.is_climbing` / `is_hanging`), `MountainMap` +
  `MountainLayout` (The Mountain, segment 2). Test: `res://tests/TestQuest.tscn` (must print PASSED too).
- The design source of truth is `docs/GDD.md`. Open TODOs for local work: `docs/TODO_LOCAL.md`.
- Before pushing: `godot --headless --path . --import` then `godot --headless --path . res://tests/TestTrain.tscn`,
  `res://tests/TestRoute.tscn` and `res://tests/TestMenu.tscn` (all must print PASSED, with no ERROR lines), and `GODOT=<godot> tests/run_net_test.sh` (prints NET TEST PASSED; picks a random free port).
  Test scenes never touch real saves: anything started from `res://tests/` uses `user://test/<TestScene>/`
  (`Game.save_dir`, `Game.use_save_dir()`); new test scenes should call `Game.use_save_dir(Game.test_save_dir())`.
- Screenshot runs (`tests/Screenshot.tscn` under xvfb with opengl3) are slow on software rendering: allow up to
  20 minutes per mode (`timeout 1200`) and run the modes one after another. Each run clears its own old PNGs and
  prints `DONE n shots`.
- Modal windows use `Game.open_ui(id)` / `Game.close_ui(id)` (not `Game.ui_open = true/false`). Confirm dialogs:
  `ConfirmCard.ask(...)`. Saves: `Game.save_slot` ("solo" / "host").
