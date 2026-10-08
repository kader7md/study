# Trust Issues

A co-op train chase (then a sea chase) with a secret impostor. Made with **Godot 4** (GDScript), with assets from **Tripo3D**, cleaned up in **Blender**.

- Game Design Doc: [`docs/GDD.md`](docs/GDD.md)
- Workflow and phases: [`docs/WORKFLOW_PLAN.md`](docs/WORKFLOW_PLAN.md) · the video's method: [`docs/VIDEO_METHOD.md`](docs/VIDEO_METHOD.md)
- Asset image prompts for Higgsfield: [`docs/ASSET_PROMPTS.md`](docs/ASSET_PROMPTS.md)
- Polish session report (what works, known issues, next steps): [`docs/POLISH_REPORT.md`](docs/POLISH_REPORT.md)
- ⚠️ **Open TODOs for when the repo moves to your PC: [`docs/TODO_LOCAL.md`](docs/TODO_LOCAL.md)** (full video analysis, MCP setup, Steam/GodotSteam, mic test, playtest with friends)

## Current prototype: Chapter 1, menu to the last station

Open the folder in **Godot 4.7** (standard build, 4.7.2), then press **F5** (Run Project).

### Menu, hosting and joining
- The game starts on the **title screen** (`scenes/menu/MainMenu.tscn`): **Continue** (only when there is a save),
  **Play solo**, **Host game**, **Join game**, **Settings**, **Quit**. Type your name in the card at the bottom right.
- **Play solo** starts an offline run (no network port, no firewall prompt). With a solo save on disk it asks first.
- **Continue (station N)** carries on from the last station you reached: every station saves the run to
  `user://checkpoint_solo.json` (inventory, train, run stats, opened gates). A finished run is not offered.
  Online runs save on the host in `user://checkpoint_host.json`, so they never overwrite the solo run.
- **Host game** opens the crew lobby. If port 24565 is busy it uses the next free one (the invite code carries it).
  With a save on disk the host can also press **Continue from station N** in the lobby (everyone starts there).
- **Join game** asks for the host's **invite code** (or `IP:port`); you join with the name in the name card. The dialog stays open while
  connecting and shows why a join failed; once the host lets you in, the lobby opens.
- **Esc** in game opens the **pause menu**: Resume, Restart from the last station (solo, or the host for everyone),
  Settings, Back to menu, Quit. Solo play pauses; online it keeps running. The host's Back to menu / Quit asks first
  (it ends the run for the whole crew).
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
- First-person player with cartoony hands, a tool hotbar, and carrying items; can ride the moving train.
  Every tool has its own first-person animation (hammer overhead swing with a camera kick, wrench twist with a ratchet
  tick, nail gun recoil and puff, welder steady hand with sparks, two-handed come-along pump) and every carried item
  its own pose (plank on the shoulder, rail low with a strained bob, wheel in front, panel flat at chest height)
- **A full run, station 0 to station 5**: each segment has pre-placed gaps (2 in the first, then 3) and one **locked gate**
  across the rails (striped boom, padlock, red lamp, a red signal post 120 m before it). Its **glowing key lies right
  beside the track**: pick it up [E], use it on the padlock [E], the boom swings up (placeholder until the quest maps).
  An objective line on the HUD says what to do next ("Gate locked: find the key", "Rebuild the broken track ahead"...)
- **Chapter 1 complete** screen at the port with the run stats (time, distance, track rebuilt, panels, wheels lost,
  gates, gold), then *Back to main menu* or *Keep exploring*
- **Balance**: supplies beside every gap and gate, softlock guards (supply crate, coal crate, emergency wheel, a limping
  train can always reach a station). See the balance table in the GDD
- **Online co-op for 1 to 5 players** (host-authoritative, ENet): crew lobby with invite codes, ready and kick, other
  players drawn as chunky workers with name tags, a secret impostor with 3+ players, push-to-talk proximity voice

### Controls
| Key | Action |
|-----|--------|
| WASD / Shift / Space | Move / sprint / jump |
| Mouse · LMB | Look · use tool (hammer hit, nail gun shot, hold to weld) |
| 1–5 (or mouse wheel) | Hammer / wrench / nail gun (once bought) / welder (only while holding a station torch) / come-along |
| E · Q · G | Use / place carried item · alternative use · put the carried item back |
| Esc | Pause menu (closes the shop or Settings first) |
| V | Push to talk (voice chat, with multiplayer) |
| F1 | Show/hide help |
| F11 | Fullscreen on/off |
| F2 | Debug: play as **impostor** (**Tab** = sabotage menu, then 1–4; meteor: aim + LMB) |
| F3 | Debug: world sabotage on/off |
| F5 / F6 | Debug: last checkpoint / new game (offline or host only) |

The F2/F3/F5/F6 debug keys only work in debug builds (the editor, or `developer/debug_keys=true` in
`user://settings.cfg`), only during a run, and they only show in the F1 help then. Every key hint on screen follows
your own bindings from Settings > Controls.

Going down: a player whose health reaches 0 is **down**. A **medkit** (station shop) saves you once when you would go
down, or a crewmate aims at you and presses **E** with a medkit to revive you. Everyone who is down gets back up when the
train reaches the next station. If the whole crew is down, the run goes back to the last checkpoint. Health comes back
slowly over time, and quickly near the warm furnace or in a station.

### Rebuilding the models
```bash
blender --background --python blender/scripts/build_assets.py -- .      # train, tools, repair items, gate, key
blender --background --python blender/scripts/build_assets.py -- . only=gate   # just the locked gate, signal post, key
blender --background --python blender/scripts/build_nature.py -- .      # trees, rocks, cliffs, bushes
blender --background --python blender/scripts/build_station.py -- .     # station canopy, shop kiosk, name board,
                                                                         # come-along, first-person glove and sleeve
blender --background --python blender/scripts/render_icons.py -- . [only=key]   # item icons (assets/icons)
blender --background --python blender/scripts/render_showcase.py -- . renders [shots=gate]   # preview pictures
```

All keys can be changed in Settings > Controls.

### Playing together (1 to 5 players)
- **Host:** *Host game* in the main menu opens the **crew lobby** (run `res://scenes/net/Lobby.tscn` on its own and it
  offers solo / host / join too). It shows two **invite codes** (each with Copy code), e.g. `60N00-H8QZN` (an IP and
  port): **Same Wi-Fi** for friends on your network, and **Internet** (your public address, found automatically or
  typed in the Public IP field) for friends elsewhere: that one works once **UDP port 24565** is forwarded to your PC,
  by hand on the router or with **Open the port (UPnP)**. With no network the lobby says so and offers no code. Press **Start the run** when everyone is ready (alone it says *Start solo*: plain offline play).
- **Join:** *Join game*, paste the code (or type `192.168.1.20` / `192.168.1.20:24565`), then **I'm ready**.
- The host's PC runs the game; everyone sees the same train, track, repairs and inventory. With 3 to 5 players one of
  you is secretly the **impostor** (a private banner tells only them). If the host leaves, everyone goes back to the menu
  ("The host ended the run" when the host chose Back to menu). A player who drops out can rejoin the running run:
  join again with the same code from the same game window (the host gave it a private rejoin ticket), and you appear on the train.
- Details, the Steam plug-in steps and the invite-code format: [`docs/NETWORK.md`](docs/NETWORK.md).

### Tests
```bash
godot --headless --path . --import                     # once after pulling (registers classes and imports assets)
godot --headless --path . res://tests/TestTrain.tscn   # automated playthrough of the core loop, exit code 0 = pass
godot --headless --path . res://tests/TestMenu.tscn    # settings save/load/rebind, main menu, pause menu, scene flow
godot --headless --path . res://tests/TestRoute.tscn   # the whole Chapter 1 route: gaps, 5 gates and keys, every
                                                       # checkpoint, the end screen and a station 3 restart (~1-2 min)
# Screenshots need a display (or xvfb-run); modes: repair, train, menu, hud, gate, end, tools, station.
# Run them one after another (several minutes each on software rendering; parallel runs starve each other).
# Each run deletes its own old PNGs first and prints "DONE n shots" at the end.
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/Screenshot.tscn -- <out_dir> menu
xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 res://tests/ScreenshotLobby.tscn -- <out_dir>   # lobby cards
tests/run_net_test.sh                                   # multiplayer: headless host + client (+ latecomer, + 3 players with a rejoin); GODOT=/path/to/godot
```

The tests never touch your own saves: every scene started from `res://tests/` keeps its checkpoints and settings in
`user://test/<TestScene>/` (`Game.save_dir`, see `Game.use_save_dir()`).

### Known issues (see `docs/POLISH_REPORT.md`)
- With a solo save present, the main menu's Quit button can run off the bottom of a 16:9 window (T3-01).
- The host's *Back to main menu* on the Chapter 1 card ends the run for clients with no confirmation (T3-07).
- Stations 1 to 5 still look grey-box.

### Not built yet (see GDD milestones)
Steam lobbies (the backend is stubbed, ENet works) · joining mid-run as a new player (rejoining works) · meeting-table voting (M4) · carry system + revive (M5) · intro and kidnap (M6) · crafting (M7) · **quest maps (next; the keys lie beside the gates until then)** · Chapter 2 sea
