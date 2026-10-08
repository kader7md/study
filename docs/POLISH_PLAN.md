# Polish plan: menu to last station (v1)

The goal is a polished run that goes from the **main menu** to **station 5**: host or join, a lobby, a full Chapter 1
journey with locked rail sections, and an ending screen that returns to the menu. Settings and the UI theme are part of it.
Design source of truth: `docs/GDD.md`. Base commit `821dd25`, branch `claude/sharp-clarke-rqh9ii`.

Team: 3 coders (one per workstream), a **tester** (runs every check below and posts screenshots), and a **critic**
(reviews each merge against the GDD, the user's wishes and the rules).

## Rules (all workstreams)
- Do not copy anything from *RV There Yet*: no files, code, UI art, names or layouts. We want the same *spirit*
  (cosy, chunky, readable) in **our own** design: warm cream and wood panels, rust and teal accents, big rounded corners.
- No Higgsfield tools. If you download assets, use only CC0 ones (Kenney, Quaternius, Poly Haven), and add each one to
  `assets/CREDITS.md`. Otherwise build models with Blender scripts.
- Typed GDScript, Godot 4.7.2. Remember the gotchas: `:=` cannot infer from a Variant (dictionary values, untyped
  arrays), so write the type out; never call `get_meta(key, null)`, use `has_meta()` first.
- **Host-authoritative.** Only the host (or offline play) changes game state. New gameplay code changes state through
  methods that the net layer can call for a client request (see the contracts below).
- Commit locally only (**never push**). Keep commits small and messages clear. They must end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0186uvpAMshtx2JbbQiPNCUD
  ```
- Before every commit: `godot --headless --path . --import`, then `godot --headless --path . res://tests/TestTrain.tscn`.
  It must print `PASSED: 0 failure(s)`. Once they exist, `TestRoute` and `tests/run_net_test.sh` must pass too.

## Scene flow
```
MainMenu (res://scenes/menu/MainMenu.tscn, new run/main_scene)
 ├─ Host game ──> Net.host_game(port) ──> Lobby (res://scenes/net/Lobby.tscn) ── host presses Start ──┐
 ├─ Join game ──> code / IP dialog ──> Net.join_game(text) ──> Lobby ───────────────────────────────┤
 ├─ Settings ───> SettingsMenu (overlay, same scene as in the pause menu)                             │
 └─ Quit                                                                                              v
                                            Main (res://scenes/main/Main.tscn, unchanged path) <──────┘
                                              Esc ─> PauseMenu (Resume / Settings / Back to menu / Quit)
                                              Station 5 ─> EndScreen "Chapter 1 complete" + stats ─> Game.return_to_menu()
```
Solo play means hosting with no clients. **Solo** is a button inside the Lobby ("Start" works with 1 player), so
offline play behaves exactly as it does now.

## Interface contracts (agree on these on day 1, before parallel work)

| Contract | Owner | Shape |
|----------|-------|-------|
| Scene paths | each owner | `res://scenes/menu/MainMenu.tscn` (menus), `res://scenes/net/Lobby.tscn` (multiplayer), `res://scenes/main/Main.tscn` (stays) |
| `Settings` autoload | menus | `scripts/autoload/settings.gd`. Props: `player_name`, `mouse_sensitivity` (default 0.0025), `invert_y`, `fov` (80), `mic_device`. `get_value(section, key, default)`, `set_value(section, key, value)`, `save()`, `reset_controls()`, `signal changed(section: String, key: String)`. Registers the `push_to_talk` action (default V) and `pause` (Esc) |
| `UiTheme` | menus | `scripts/ui/menu/ui_theme.gd`, `class_name UiTheme`: `static func build() -> Theme`, palette consts (`CREAM`, `WOOD`, `INK`, `RUST`, `TEAL`, `BODY_GREEN`, `WHEEL_YELLOW`, `ENGINE_RED`, `CHASSIS_BLUE`, `JOURNEY`), `static func panel(color, radius) -> StyleBoxFlat`, `static func title_label(text, size) -> Label`. Settings sets `get_tree().root.theme = UiTheme.build()` at startup so every Control (HUD, shop, end screen) gets it |
| `Net` autoload | multiplayer | `scripts/net/net.gd`. `host_game(port := DEFAULT_PORT) -> Error`, `join_game(code_or_ip: String) -> Error`, `leave()`, `start_run()`, `is_online() -> bool`, `is_host() -> bool` (true offline), `local_id() -> int`, `players: Dictionary` (peer id -> {name, ready, color}), `invite_code() -> String`, `static encode_invite(ip, port)` / `decode_invite(code)`, `request(target: Node, method: StringName, args := [])`. Signals `players_changed`, `connection_failed(reason)`, `run_started`, `disconnected(reason)`. Offline by default, so `TestTrain` works without it |
| Game additions (gameplay) | gameplay_flow | In `game.gd`: `var stats: Dictionary` (`time`, `distance`, `repairs`, `wheels_lost`, `gates`, `gold_found`), `add_stat(key, amount)`, `var objective: String` + `signal objective_changed(text)`, `signal run_finished(stats)`, `const MENU_SCENE := "res://scenes/menu/MainMenu.tscn"`, `func return_to_menu()` (calls `Net.leave()` if the Net autoload exists, then changes to MENU_SCENE if it exists, else reloads Main). Stats are saved in the checkpoint |
| Game additions (net) | multiplayer | In `game.gd`, marked `# NET:`: `func is_host() -> bool` (true offline). Debug keys F2/F3/F5/F6 work offline or on the host only. `role` is set per peer by Net |
| Deterministic node names | gameplay_flow (world), multiplayer (players) | `RailRepair` = `Repair_<piece>`, gate = `Gate_<segment>`, key = `Key_<segment>`, pickups `Pickup_<n>` (spawn order), stations `Station<i>` (already), players `Players/Player_<peer id>`. The world is built from `Main.SEED`, so every peer builds the same track, gaps, gates and pickups |
| Track gate API | gameplay_flow | `Track.gate_distance(seg)`, `is_gate_locked(seg)`, `open_gate(seg)` (host), `signal gate_opened(seg)`. `blocking_distance()` treats a locked gate as a block |
| Interaction entry points | multiplayer reads, gameplay keeps stable | `Interactable.interact(player)`, `interact_alt(player)`, `on_tool_hit(tool, player)`, `on_weld(delta, player, source)`. A client sends them with `Net.request(...)`, and the host runs them with that peer's `Player` |

### Shared files: who edits what
| File | menus_settings | multiplayer | gameplay_flow |
|------|----------------|-------------|---------------|
| `project.godot` | main_scene, `Settings` autoload (after Game), `audio/driver/enable_input=true`, bus layout, `pause` input | `Net` autoload (after Settings) | none |
| `scripts/autoload/game.gd` | none (reads `INPUTS` as the rebind defaults) | `is_host()`, debug-key gating, per-peer role, all marked `# NET:` | stats, objective, key/gate state, `return_to_menu()`, run_finished, balance constants (SHOP, START_INVENTORY) |
| `scripts/player/player.gd` | `MOUSE_SENS` becomes `Settings.mouse_sensitivity`, invert Y, `camera.fov`, the old Esc mouse release is replaced by the pause menu | authority checks, request routing for interact/tool/weld/carry, remote body vs first-person arms, `# NET:` markers | hands, tools and carry poses move into a new `scripts/player/viewmodel.gd` (`Viewmodel`). player.gd keeps thin calls (`_vm.play("hammer")`, `_vm.carry(item)`) |
| `scripts/ui/hud.gd` | owns it: theme, bars, layout, objective note, shop restyle | adds a player list / speaking icon only through `HUD.add_corner_widget(node)` (an API from menus) | none (shows the objective through `Game.objective_changed`) |
| `scripts/world/main.gd` | none | player spawning hook (`Net.spawn_players(self, spawn_xform)`, keeps `main.player` = local player), `WorldSync` node | gates/keys, pickup balance, end-screen hookup, named pickups |
| `scripts/train/train.gd`, `scripts/track/track.gd` | none | minimal `# NET:` hooks (client skips simulation in `_physics_process`, applies snapshots) | owns everything else |
| `tests/screenshot.gd` | adds `menu` and `hud` modes | none | adds `gate` and `end` modes |

**Merge order.** (1) Day-1 contract stubs: Settings + UiTheme + MainMenu shell, the offline `Net` autoload, the Game
stats/objective/`return_to_menu`. (2) Parallel work. (3) Gameplay lands the track/train API changes **before**
multiplayer adds its hooks to those files. (4) Integration: menu buttons to Net, the end screen to `return_to_menu`,
the HUD objective. Rebase often. The critic reviews each merge.

---

## Workstream menus_settings: Main menu, pause menu, settings, UI polish

**Goal.** Starting the game shows a cosy, chunky title screen over a slowly moving camera at the departure station.
Every menu, HUD bar and panel shares one warm theme. All settings (controls, graphics, audio, microphone) are saved and
applied at startup.

**Files owned:** `scripts/autoload/settings.gd`; `scripts/ui/menu/*` (`ui_theme.gd`, `main_menu.gd`, `menu_background.gd`,
`settings_menu.gd`, `pause_menu.gd`, `key_rebind_button.gd`, `mic_meter.gd`); `scenes/menu/*` (`MainMenu.tscn`,
`SettingsMenu.tscn`, `PauseMenu.tscn`); `default_bus_layout.tres`; `assets/fonts/*` (CC0 Kenney fonts if downloaded,
otherwise `SystemFont`); `scripts/ui/hud.gd`. Shared edits: `project.godot`, `scripts/player/player.gd` (only the
parts listed in the table), `tests/screenshot.gd` (`menu`/`hud` modes).

**Tasks**
1. **Settings autoload** (`Settings`, registered after `Game`): load `user://settings.cfg` (ConfigFile) with sections
   `[controls] [graphics] [audio] [mic] [profile]`, apply it in `_ready`, save when anything changes. Any missing or
   corrupt file falls back to the defaults. Guard all `DisplayServer` and window calls when headless.
2. **UiTheme** built in code: cream and wood panels with a dark ink outline, 14 to 18 px rounded corners, a chunky
   drop shadow, large bold font (28 for buttons, 64 to 96 for titles) with an outline, warm hover and pressed states,
   and styled ProgressBar, HSlider, CheckBox, OptionButton, TabContainer, LineEdit and ScrollBar. Applied to the root
   viewport.
3. **MainMenu.tscn** as `run/main_scene`. The big "TRUST ISSUES" title (with a tagline), then Host game, Join game,
   Settings and Quit. The Join dialog has an invite-code or IP:port field and a player-name field. The background
   (`menu_background.gd`) builds `Track` + `Terrain` + `Station 0` + `Train` from `Main.SEED` **without** setting
   `Game.track` or `Game.train`. A slow dolly or orbit camera runs over the train with chimney smoke and a sunny sky.
   No Player, HUD or sabotage. Buttons fade or slide in. If the `Net` autoload is missing, Host loads Main directly
   (solo).
4. **PauseMenu** (CanvasLayer, `process_mode = ALWAYS`) on the `pause` action (Esc): Resume, Settings, Back to menu
   (`Game.return_to_menu()`), Quit. It sets `Game.ui_open` (which frees the mouse). Offline it pauses the tree; online
   it does **not** pause and shows "Game keeps running". Esc closes an open shop or Settings first.
5. **Settings menu** (TabContainer, reused by both menus):
   - *Controls:* one row per InputMap action except Godot's `ui_*` (friendly names, grouped Movement / Tools /
     Interaction / Impostor / Debug). Click to rebind (keyboard key or mouse button). Esc cancels. Conflicts show in
     a warning colour. "Reset to defaults" restores `Game.INPUTS` plus attack/cancel. Mouse sensitivity, invert Y.
   - *Graphics:* window mode (windowed, borderless, fullscreen), V-Sync, resolution scale (50 to 100 % via
     `Viewport.scaling_3d_scale`), shadow quality (off, low, medium, high: sun shadow on/off, atlas size, soft-shadow
     filter quality), FOV (60 to 110), max FPS (30, 60, 120, 144, unlimited), plus anti-aliasing (off, FXAA, MSAA 2x/4x).
   - *Audio:* sliders for the Master, Music, SFX and Voice buses (in dB, with mute at 0).
   - *Microphone:* input device list (`AudioServer.get_input_device_list()`), push-to-talk on/off plus a rebind button,
     a live level meter from a muted `Mic` bus with `AudioEffectCapture` (an `AudioStreamMicrophone` player that only
     plays while the tab is open), and a "Test: hear yourself" toggle. Enable `audio/driver/enable_input=true`.
6. **Player hooks:** use `Settings.mouse_sensitivity`, `invert_y` and `fov` live (connect `Settings.changed`). Remove
   the old Esc mouse release (the pause menu owns Esc).
7. **HUD polish** to the theme. The top centre becomes a chunky rounded panel with a green **body** bar, six yellow
   **wheel** squares (with an icon; a lost wheel shows as an empty slot with an X), a red **engine** bar and a blue
   **chassis** bar, each with a small icon and a value. The journey bar below it has station pips 0 to 5, a train
   marker, the next station's name and the distance in metres, plus locked-gate markers (from the gameplay API when
   present). Inventory becomes icon chips (top left). A paper-note **objective** card shows `Game.objective`. The
   tool hotbar gets the theme. Bottom left gets health and frost with icons. Messages become toasts that slide in and
   fade. The banner gets a backing plate. The shop gets the theme with icons and prices. Add
   `HUD.add_corner_widget(node)` for multiplayer. Keep every HUD element readable at 1280x720 and at 1920x1080.
8. **Menu sounds (small):** a click and hover sound made in code (`AudioStreamWAV`) on the SFX bus, so the SFX slider
   is audible.
9. Screenshot modes `menu` and `hud` in `tests/screenshot.gd`.

**Acceptance (tester)**
- [ ] F5 in the editor (and the plain `godot --path .`) opens MainMenu: title, 4 buttons, a moving train-station background, no errors in the log.
- [ ] Headless import plus TestTrain still pass (`PASSED: 0 failure(s)`). Loading MainMenu headless for 120 frames gives no errors.
- [ ] Esc in game opens the pause menu. Resume brings back mouse capture. Back to menu reaches MainMenu. Quit exits. Solo play pauses (the train does not move while paused).
- [ ] Rebinding `jump` to J works at once, survives a restart (`user://settings.cfg` holds it), and "Reset to defaults" restores Space.
- [ ] Changing fullscreen, V-Sync, resolution scale, shadows, FOV and max FPS has a visible effect and persists after a restart.
- [ ] The Audio sliders change `AudioServer` bus volumes, and the values persist.
- [ ] The Microphone tab lists devices, and the meter moves when you speak (on a machine with a mic). With no mic it shows "No input device" and does not crash.
- [ ] Screenshots `menu` and `hud` (xvfb, opengl3): one cohesive theme, no overlapping text, bars use green, yellow, red, blue and the journey colour.
- [ ] Critic: the look is our own (no RV There Yet assets or layout copies) and readable from 2 m away.

---

## Workstream multiplayer: Host, join, invite, lobby and network sync

**Goal.** 1 to 5 players play one run together over ENet. The host simulates everything. Clients send requests and
see the same world. Solo play is the same code path with no clients and behaves exactly as now. The network backend
is behind an interface so Steam can be added later.

**Files owned:** `scripts/net/*` (`net.gd` autoload, `net_backend.gd`, `enet_backend.gd`, `steam_backend.gd` stub,
`invite_code.gd`, `world_sync.gd`, `player_sync.gd`, `lobby.gd`, `voice.gd`), `scenes/net/*` (`Lobby.tscn`),
`tests/net_test.gd`, `tests/NetTest.tscn`, `tests/run_net_test.sh`, `docs/NETWORK.md`. Shared edits, minimal and
marked `# NET:`: `project.godot` (autoload), `game.gd`, `main.gd`, `player.gd`, `train.gd`, `track.gd`, and
`sabotage_manager.gd` (spawning only, coordinated with gameplay_flow).

**Tasks (P0 first)**
1. **P0. NetBackend layer:** `NetBackend` (RefCounted) with `host(port, max_players) -> Error`, `join(address, port)`,
   `close()`, `get_peer() -> MultiplayerPeer`, `describe_invite()`. `EnetBackend` implements it. `SteamBackend` is a
   documented stub (lobby, invite and P2P mapped to GodotSteam's `SteamMultiplayerPeer`). `docs/NETWORK.md` explains
   how to plug it in. Offline play uses `OfflineMultiplayerPeer` (peer id 1, `is_server()` true).
2. **P0. Invite code:** IPv4 plus port packed into 6 bytes, then Crockford base32 to a code like `7K2QF-9XM4A`.
   `decode_invite` accepts a code, `ip`, or `ip:port`. The host shows its LAN IPs, the code, and a "Copy code" button.
   Optional UPnP port mapping (Godot `UPNP`) with a clear status line. Default port 24565.
3. **P0. Lobby.tscn** (uses `UiTheme`): player cards with name, colour, a ready tick and a host crown. A Ready toggle
   for clients. The host's Start is enabled when all clients are ready (or when solo). Kick button for the host. A
   chat line is optional. Shows the invite code. Leave goes back to MainMenu. Handles errors (connection failed, lobby
   full at 5, the run already started).
4. **P0. Start run:** the host calls `start_run()`, which is an RPC to all peers to change the scene to Main with the
   same seed. Clients wait for "world ready" before any sync is applied.
5. **P0. Player spawning:** `Main/Players` with a MultiplayerSpawner (custom spawn function, `Player_<id>`) and a
   MultiplayerSynchronizer per player (position, rotation y, camera pitch, `carried_item`, `current_tool`, downed,
   welding). The local player owns its transform (client authority for movement only). Remote players show a
   **third-person body** (a capsule body with a head, hands, a name tag and the held tool or carried item) and hide
   their first-person arms and camera. `main.player` is still the local player.
6. **P0. World sync (`world_sync.gd`, host to clients):** train snapshot at 15 to 20 Hz (distance, speed, lever,
   fuel, body/engine/chassis, wheel wear and state, tipped and tip angle, current_station), interpolated on clients;
   `Train._physics_process` skips simulation on clients (`# NET:`). Reliable events: track `piece_broken` and
   `piece_repaired` (index, cratered, roll), gate opened, pickup collected (by name), inventory changes (a full
   dictionary on change), banner and message, station reached, chapter complete, body-part detach and refit.
7. **P1. Client requests:** in `player.gd`, the calls to `focused.interact`, `interact_alt`, `on_tool_hit`,
   `weld_tick` and `put_back` go through `Net.request(target, method, args)` when not host. The host checks range and
   runs the call with that peer's Player. RailRepair sub-state (planks, rails, bolts) is sent as one state dict per
   repair after each change, so clients see the build progress.
8. **P1. Late join and reconnect:** the run cannot be joined after it starts (lobby only) in v1. A client that
   disconnects mid-run goes back to the menu with a reason. If the host leaves, all clients go back to the menu with
   "Host left the game".
9. **P1. Impostor:** at start with 3 to 5 players, the host picks one random impostor and RPCs the role **only to that
   peer**, which sees a private banner. Everyone else gets "crew". The impostor's sabotage input becomes a request to
   the host, which runs `SabotageManager.use()`. World sabotage runs only with 1 or 2 players (GDD 2). Meteor,
   zombie and eagle spawns are replicated (spawn RPC plus transform sync for zombies and eagles).
10. **P2. Voice chat** (if time allows): the `Mic` bus capture becomes 16 kHz mono frames sent by unreliable RPC on
   push-to-talk, played on an `AudioStreamGenerator` (3D, Voice bus) at the speaker's body, with a speaking icon via
   `HUD.add_corner_widget`.
11. **P0. Automated 2-process test:** `tests/NetTest.tscn` + `net_test.gd` (args `-- host` / `-- client`), and
   `tests/run_net_test.sh` starts a headless host and client on 127.0.0.1 with a timeout. The host waits for the
   client, starts the run, pushes the lever, and (with debug helpers) repairs the first gap and runs into the next
   section. The client asserts it joined, saw the Main scene, has 2 players with `Player_1` remote, saw
   `train.distance` grow by more than 20 m, and saw the repaired piece become unbroken and the inventory change. Each
   process prints `PASSED`/`FAILED` and the script exits non-zero on failure.

**Acceptance (tester)**
- [ ] `tests/run_net_test.sh` prints PASSED for host and client and exits 0 within 3 minutes.
- [ ] TestTrain still passes unchanged (offline equals host with no clients). Solo from the Lobby plays exactly like before.
- [ ] Two windowed instances on one PC: host, join by invite code, both appear in the lobby with names, ready works, host starts, both spawn at the departure station, see each other's body (no floating arms), and the train moves for both.
- [ ] A client can collect a pickup, place a plank, nail it and bolt a rail, and the host sees it (and the other way round). A repaired gap lets the train pass on both.
- [ ] With 3 test instances (or the debug override `Net.debug_force_impostor`), exactly one peer gets the impostor banner. The others never learn who it is (check the logs).
- [ ] Closing the host sends clients back to the menu with a message. There are no script errors on disconnect.
- [ ] `docs/NETWORK.md` explains the backends, the ports, the invite code format and the Steam plug-in steps.

---

## Workstream gameplay_flow: Full journey to the last station, locked rails, balance

**Goal.** One complete run, from leaving the departure station to the Chapter 1 ending at station 5, is possible,
fair and fun. Each segment has a locked gate with its key right beside it, the tools feel distinct in the hand, and
an automated test drives the whole route.

**Files owned:** `scripts/track/*`, `scripts/station/*`, `scripts/train/*`, `scripts/sabotage/*`, `scripts/repair/*`,
`scripts/world/*` (including new `track_gate.gd`, `gate_key.gd`), `scripts/interact/*`, `scripts/player/viewmodel.gd`
(new), `scripts/ui/end_screen.gd` + `scenes/ui/EndScreen.tscn` (styled with `UiTheme`), `scripts/util/props.gd`,
`blender/scripts/build_assets.py`, `blender/scripts/render_icons.py`, the new models and icons, `tests/test_route.gd`,
`tests/TestRoute.tscn`. Shared edits: `game.gd` (see the table), `player.gd` (calls into Viewmodel only),
`tests/test_train.gd` (only where balance changes break expectations), `tests/screenshot.gd` (`gate`/`end`).

**Tasks**
1. **Locked gates and keys (one per segment, 5 in total)**
   - Blender (`build_assets.py`): `track_gate.glb` (a heavy timber and steel barrier across the rails, red and white
     striped boom, a big padlock with a hasp, a lamp, worn paint; the boom pivots open) and `gate_key.glb` (a large old
     iron key with a brass bow and a tag). Add icons `key.png` in `render_icons.py`. Register both in `Props`.
   - `TrackGate` (`Gate_<seg>`): placed by `Track` at a deterministic spot in the second half of each segment, on
     solid ground (not a bridge, not water, not within 30 m of a gap or station). A warning signal post with a red
     lamp stands 120 m before it. While locked, `blocking_distance()` stops the train in front of it: under
     `CRASH_SPEED` it brakes softly, above it, it takes half of normal gap damage with a "Hit the locked gate!" message.
   - `GateKey` (`Key_<seg>`): a glowing pickup (emission, a soft OmniLight, a slow bob and spin, a `KEY` Label3D) **4
     to 10 m beside the track within ±8 m of the gate**, on the ground and reachable. [E] adds `key` to the inventory.
     [E] on the gate with a key consumes it and plays the opening animation (padlock drops, boom swings up, a creak
     sound if available). The gate then stops blocking and `Game.add_stat("gates", 1)` runs. The prompt without a key
     reads "Locked: find the key nearby".
   - Checkpoint: gates and keys of the segments behind the start station load as opened. The state is saved in the
     checkpoint.
   - Objective text (`Game.objective`): "Reach station N", then "Gate locked: find the key" once the train is within
     150 m of a locked gate, then "Open the gate", and the gap and wheel objectives when relevant.
2. **Ending.** On station 5 (`Game.chapter_completed`), stop sabotage, wait about 2 s, then show the
   **EndScreen**: "CHAPTER 1 COMPLETE", a short story line (the trail leads to the port; Chapter 2: the sea), and stats
   (run time mm:ss, distance km, track pieces rebuilt, panels refitted, wheels lost, gates opened, gold found). The
   buttons are "Back to main menu" (`Game.return_to_menu()`) and "Keep exploring" (closes it). Count stats in
   train, track, repair and Game. Time runs from leaving station 0 and pauses while the game is paused. In multiplayer
   the host sends it (multiplayer hooks the signal); the screen only reads `Game.stats`.
3. **Balance pass** (constants in one place, documented in a table in the GDD):
   - Gaps: segment 1 has 2 gaps and later segments 3, with 1 to 2 pieces each. No gap within 60 m before a gate.
   - Pickups: every pre-placed gap gets 2 or 3 wood pickups plus 1 scrap within 25 m, on solid ground. Coal along the
     route covers about 1.5 times the coal needed for a segment at cruise speed (including the mountain climb in
     segment 3). Nails: start with 30 and add a nail crate pickup (5 nails) near every other gap. Gold covers at
     least one wheel plus oil per segment.
   - Prices: review `SHOP` (for example nails x10 = 4, wheel = 8, oil = 6, coal x5 = 2). Every station shop also sells
     planks (wood x5) and scrap x5 as a softlock fallback.
   - Damage: tune crash damage, wheel wear per bump, and the world sabotage interval (segment 1 calmer, rising per
     segment, never within 20 s of a station stop). A meteor never breaks the piece the train stands on.
   - Softlock guards: if the crew has too little wood or nails for a gap ahead and there is no gold, a "supply crate"
     with 6 wood and 10 nails spawns near the gap with a message. The train can always reverse to the last station.
     Fewer than 3 wheels and no gold means the shop gives one emergency wheel per station.
4. **Tool animations and carry poses** in `Viewmodel` (`scripts/player/viewmodel.gd`; player.gd calls it). Hammer: a
   wind-up overhead swing and a downward strike with a small camera kick on impact. Wrench: a fit-on, a 90° wrist twist
   with a ratchet tick, then return. Nail gun: a sharp recoil with the muzzle rising and settling, plus a small flash
   or puff. Welder: a steady hold with micro-shake, sparks and a blue-white light flicker while welding. Come-along:
   a two-handed pump on the ratchet handle (both arms). Idle: gentle breathing sway, walk bob (scaled by speed), and a
   tool raise and lower when switching. Carry poses: a plank on the shoulder (both hands, off-centre), a rail held low
   with both hands and a strained bob, a wheel held in front with both hands and slight wobble, a panel held flat in
   front at chest height. Lowering when placing.
5. **TestRoute** (`tests/TestRoute.tscn`, `tests/test_route.gd`): a new game with world sabotage off, then for each
   segment: fill fuel, push the lever, and on a gap stop use the debug helper `RailRepair.finish_instantly()` (counting
   it as a repair). At the gate, teleport the player to `Key_<seg>`, interact, teleport to the gate, interact, then
   assert it is unlocked. Wait for `station_reached(N)` and assert the checkpoint was saved with
   `station == N`. After station 5, assert `chapter_completed` fired, the EndScreen is visible, and `stats.distance > 7000`,
   `stats.gates == 5`, `stats.time > 0`. A balance check per segment asserts that resources within 15 m of the track
   plus the starting inventory cover the planks, rails and nails the pre-placed gaps need. It runs headless with a
   high `Engine.time_scale` in under 5 minutes and prints `PASSED: 0 failure(s)`.

**Acceptance (tester)**
- [ ] `godot --headless --path . res://tests/TestRoute.tscn` prints `PASSED: 0 failure(s)` (under 5 min). TestTrain still passes.
- [ ] Screenshot `gate`: the gate model with a padlock across the rails, and the glowing key clearly visible beside it from the cab.
- [ ] Manual solo run: the train stops in front of each gate, the key is easy to find (under 30 s), the gate opens with an animation, and the train continues.
- [ ] Reaching station 5 shows the Chapter 1 complete screen with real stats. "Back to main menu" reaches MainMenu (or reloads Main if the menu is missing).
- [ ] Each of the 5 tools has a visibly different first-person animation, and the 4 carry poses differ (screenshots or a short capture).
- [ ] Balance: a manual run with no shop visits except wheels and oil does not run out of wood, nails or coal. Average time per segment is about 6 to 10 minutes for one player.
- [ ] Restart from a checkpoint at station 3: gates 1 to 3 are open, the stats carry over, and there are no orphan keys.
- [ ] Critic: the gate and key models fit the stylized-realism look of the train. The tool motions read clearly.

---

## Known gaps (after review round 1)
- Rejoining a run in progress after a dropped connection is not possible yet (the host has to start a new session).
- Steam backend (invites through Steam) is a stub; ENet with invite codes and UPnP is what ships.
- Reviving by carrying a body to the station grave is M5; until then: a medkit, or reaching the next station.
- The quest mini-game maps that will guard each locked gate come later; the key lies beside each gate for now.

## Tester and critic checklist per merge
1. `--import`, then TestTrain, then TestRoute, then `tests/run_net_test.sh` (when each exists).
2. Screenshots: `menu`, `hud`, `repair`, `train`, `gate`, `end` (xvfb + opengl3). Post them in the review.
3. The critic checks the GDD, the user's wishes (menu to last station, cosy chunky UI, host and invite, settings
   for keys, graphics, audio and mic, a key beside each locked rail), the rules, host-authoritative state, `# NET:`
   markers, and no new warnings in the log.
4. Update `README.md` (controls, menu, how to host and join, tests) and the GDD (locked gates with the key beside them
   as the placeholder until quest maps, the balance table) at the end.
