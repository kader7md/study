# Trust Issues: notes for Claude

- Godot 4.7.2, GDScript, typed. Models come from Blender 4.5 scripts: `blender/scripts/build_assets.py` (train, tools,
  repair items) and `build_nature.py` (trees, rocks, cliffs). Procedural wear is baked into one texture per model; `.glb`
  goes to `assets/models/`, loaded via `Props` / `Terrain.nature_mesh`. `render_showcase.py` renders preview pictures. Other grey-box geometry is built in code (`scripts/util/build.gd`).
- `Game` autoload (`scripts/autoload/game.gd`) holds shared state: inventory, checkpoints, signals, debug role, run
  `stats` (`add_stat`), `objective` (+ `objective_changed`), `run_finished`, `return_to_menu()`, balance (`SHOP`, `START_INVENTORY`).
  Keep state changes host-side so multiplayer (M1) can sync them later.
- Main pieces: `Track` (rail pieces, gaps, stations, landscape themes, bridges), `Terrain` (ribbon mesh along the track),
  `Train` (distance-based movement), `RailRepair`/`PlaceSlot`/`NailSpot`/`WeldSeam`/`WelderSource` (hands-on repair), `Station`,
  `SabotageManager` (+ `Meteor`, `Zombie`, `Eagle`), `Player` (+ `Viewmodel`: hands, tool animations, carry poses), `HUD`.
  `ActionSpot` = interactable from callables. Locked gates: `TrackGate` (`Gate_<seg>`, Track gate API) + `GateKey`
  (`Key_<seg>`). `RunDirector` (objective, softlock guards, ending) shows the `EndScreen`. Node names are deterministic
  (`Repair_<piece>`, `Pickup_<n>`, `Station<i>`) because every peer builds the world from `Main.SEED`.
- The design source of truth is `docs/GDD.md`. Open TODOs for local work: `docs/TODO_LOCAL.md`.
- Before pushing: `godot --headless --path . --import` then `godot --headless --path . res://tests/TestTrain.tscn` and
  `res://tests/TestRoute.tscn` (both must print PASSED).
