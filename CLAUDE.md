# Trust Issues: notes for Claude

- Godot 4.7 (tested on 4.7.2; 4.4+ works), GDScript, typed. Grey-box geometry is built in code (`scripts/util/build.gd`) until real `.glb` assets exist.
- `Game` autoload (`scripts/autoload/game.gd`) holds shared state: inventory, checkpoints, signals, debug role.
  Keep state changes host-side so multiplayer (M1) can sync them later.
- Main pieces: `Track` (rail pieces, gaps, stations), `Train` (distance-based movement on the track), `Station`,
  `SabotageManager` (+ `Meteor`, `Zombie`, `Eagle`), `Player`, `HUD`. `ActionSpot` = interactable from callables.
- The design source of truth is `docs/GDD.md`. Open TODOs for local work: `docs/TODO_LOCAL.md`.
- Before pushing: `godot --headless --path . --import` then `godot --headless --path . res://tests/TestTrain.tscn` (must print PASSED).
