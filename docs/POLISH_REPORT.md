# Polish report: menu to last station (session v1)

Branch `claude/sharp-clarke-rqh9ii`, base `821dd25`, reviewed at `743ce70` (18 commits, 174 files, about 15k lines).
Plan: [`POLISH_PLAN.md`](POLISH_PLAN.md). Design source of truth: [`GDD.md`](GDD.md).
Team: 3 coders (menus/settings, multiplayer, gameplay flow), a tester and a critic, with 3 review rounds.

**Result:** a full run now works from the **main menu** to the **Chapter 1 complete** card at station 5 and back to the
menu, solo or online with 1 to 5 players. All tests pass. The last review rounds found **no blockers**. Two **major**
issues (menu layout with a save present, and tests overwriting real saves) and a list of minor polish items are still open (see 4).

## 1. What was built, per workstream

### Menus, settings and UI theme (`scripts/ui/menu/`, `scripts/autoload/settings.gd`)
- `UiTheme`: one theme built in code for every Control in the game. It uses cream paper and varnished wood panels,
  ink outlines, big rounded corners, soft shadows, rust and teal accents and honey hover states. The design is our own,
  in the cosy, chunky spirit the owner asked for. Nothing was copied from RV There Yet.
- **Main menu** (`MainMenu.tscn`): the TRUST ISSUES title over a slow camera at the real departure station, with
  chimney smoke and a generated music-box loop. Buttons: Continue (station N), Play solo, Host game, Join game, Settings,
  Quit. A name card sits at the bottom right. Play solo over a save asks first. F11 toggles fullscreen anywhere.
- **Settings** (`user://settings.cfg`, applied at startup):
  - **Controls:** rebind every action (keys or mouse) with conflict warnings, reset to defaults, sensitivity, invert Y.
  - **Graphics:** window mode, V-Sync, resolution scale, shadows, AA, FOV, max FPS.
  - **Audio:** Master, Music, SFX and Voice buses.
  - **Microphone:** input device, live level meter, a "hear yourself" test, push-to-talk on/off and its key, and a noise gate when push-to-talk is off.
- **Pause menu** (Esc): Resume, Restart from the last station, Settings, Back to menu, Quit. Solo pauses the game;
  online the game keeps running. The host must confirm before ending the run for everyone (`ConfirmCard`).
- **Themed HUD:**
  - train card with body, wheel, engine and chassis bars;
  - journey strip with station pips and padlocks on locked sections;
  - inventory chips, objective note, toasts, wood-plate banners and a prompt pill;
  - it scales with the window height and is readable at 720p and 1080p.
- All on-screen key hints follow the player's own bindings.

### Multiplayer: host, invite and lobby (`scripts/net/`, [`NETWORK.md`](NETWORK.md))
- `Net` autoload behind a backend layer: **ENet works**, and `steam_backend.gd` is a stub that GodotSteam plugs into.
- **Hosting** on UDP 24565. If that port is busy, it falls back to the next free one.
- **Invite codes:** 10 characters that carry the IP and port. There are two codes, **Same Wi-Fi** (LAN) and **Internet**
  (public IP found through UPnP or an HTTPS lookup, or typed by hand), plus an "Open the port (UPnP)" button.
- **Lobby:** names and colours, ready ticks, kick, a host crown, Start solo or Start the run, and Continue from a host save.
- **Host-authoritative world sync:**
  - every peer builds the world from `Main.SEED`;
  - clients ask through `Net.request`, which checks an allowed-method list, a reach limit and clamped values;
  - the host streams the train 20 times a second, plus repairs, pickups, crates, inventory, sabotage, the objective and station events.
- Riders stay on the moving train: each player's position is sent relative to the car they stand on.
- Other players appear as chunky workers with name tags. With 3 to 5 players, one is a secret impostor (told only to them).
- Proximity voice chat, with push-to-talk or an open mic.
- **Rejoin:** a player who drops out can rejoin the running run with the same code and name.
- Solo play uses the offline peer and opens no socket, so there is no firewall prompt.

### Gameplay flow: locked gates, ending and balance (`Track`, `TrackGate`, `GateKey`, `RunDirector`, `EndScreen`, `Viewmodel`)
- **One locked gate per segment.** It is a striped timber boom with a padlock and a red lamp, always on solid ground, with a red signal post 120 m before it.
- **The key lies right beside each gate**, as the owner asked. It sits 4.5 to 8.5 m from the track and 1 to 7 m from
  the gate (checked by TestRoute). The key glows, bobs and spins, and has a light, a light beam and a KEY label.
  A "LOCKED / key nearby" sign stands at the gate. To open it, pick up the key [E] and use it on the padlock [E]. The padlock drops, the boom swings up and the lamps turn green.
  This is a placeholder until the quest maps (GDD 7).
- **Objective line**, driven by `RunDirector`: "Gate locked: find the key", "Rebuild the broken track ahead", and so on.
- **Run stats:** time, distance, track rebuilt, panels, wheels lost, gates and gold. They are saved in the checkpoint.
- **Chapter 1 complete** card at station 5, with the stats, *Back to main menu* and *Keep exploring*.
- **Station stops:** stations are detected on the host. Overshooting a platform is handled, and a buffer stop after the last platform means the final stop always counts.
- **Saves:** separate solo and host saves (`checkpoint_solo.json`, `checkpoint_host.json`). A finished run is not offered as Continue.
- **Softlock guards:** a supply crate and a coal crate, an emergency wheel, a limping train that can always reach a
  station, and a crew-wipe check that sends the crew back to the last checkpoint.
- **Down and revive:** medkit self-save and revive by a crewmate, and everyone gets back up at the next station.
- **Viewmodel:** each tool has its own animation (hammer swing with a camera kick, wrench ratchet, nail-gun recoil, steady welder with sparks, come-along pump), and each carried item has its own pose.
- **New Blender models** (scripts, baked wear): gate, signal post, key, station canopy, shop kiosk, name board, come-along, glove and sleeve. Item icons come from `render_icons.py`.
- Balance table v1 in the GDD (constants in `game.gd`, `track.gd`, `main.gd`, `train.gd`, `sabotage_manager.gd`).

## 2. Test results (final round, HEAD `743ce70`, Godot 4.7.2 headless)
| Check | Result |
|-------|--------|
| `--import` | clean, exit 0 |
| `res://tests/TestTrain.tscn` (core loop) | `PASSED: 0 failure(s)` |
| `res://tests/TestRoute.tscn` (whole route to station 5, 5 gates and keys, every checkpoint, end screen, station 3 restart) | `PASSED: 0 failure(s)` |
| `res://tests/TestMenu.tscn` (settings save/load/rebind, menu, pause menu, scene flow) | `PASSED: 0 failure(s)` |
| `tests/run_net_test.sh` (host + client + latecomer, 3-player impostor run, crate sync, rejoin) | `NET TEST PASSED` |

The tester and the critic each ran these on their own copy and found no `SCRIPT ERROR`, `ERROR` or `WARNING` lines. The supervisor ran TestTrain, TestRoute and TestMenu once more before committing.
The only messages in the render logs are the expected ALSA "no audio device" lines.

A code read of a full run found no crash and no softlock. It followed menu → solo/host/join → lobby → Main → stations 1 to 5 → RunDirector ending → EndScreen → menu.

## 3. Screenshots (xvfb, opengl3/llvmpipe, 1600x900)
They are in the session scratchpad, `/tmp/claude-0/-home-user-study/d3bc778e-bde3-5530-a80e-ca91fd5d6521/scratchpad/shots/`.
They are not committed, so regenerate them with `tests/Screenshot.tscn -- <dir> <mode>` and `tests/ScreenshotLobby.tscn`.
| Mode | Files |
|------|-------|
| menu | `menu/menu_1_title.png`, `menu_2_title_later.png`, `menu_3_settings_0_controls.png`, `_1_graphics`, `_2_audio`, `_3_microphone`, `menu_4_join.png` |
| hud | `hud/hud_1_play.png`, `hud_2_banner.png`, `hud_3_shop.png`, `hud_4_pause.png`, `hud_5_play_1280x720.png` |
| end | `end/end_1_complete.png` |
| gate | `gate/gate_1_cab.png`, `gate_2_side.png` (key beside the gate), `gate_3_padlock.png`, `gate_4_signal.png`, `gate_5_open.png` (top-level folder) |
| station | `station/station_1_track.png`, `station_2_kiosk.png`, `station_3_sign.png` |
| repair / train | `repair/6_repair.png`, `7_carry_rail.png`, `8_train_covered.png`, `9_train_damaged.png`; top level `1_station.png` to `5_train_side.png` |
| lobby | `lobby/lobby_1_host_alone.png`, `lobby_2_host_crew.png`, `lobby_3_offline_play.png`, `lobby_4_connecting.png`, `lobby_5_join_failed.png` |
| tools | `tools/tool_1_hammer_windup.png` to `tool_6_welder.png`, `carry_panel/plank/rail/wheel.png` |

In the last round, `tools` saved only 3 of its 10 shots and `lobby_5` did not finish. Another render was using the CPU at the same time, so the runs hit their timeouts; the game did not hang.
The full sets above come from an earlier run.

## 4. What is still missing or weak

> **Update (fix round 3):** T3-01, T3-02, T3-04 to T3-09, rejoin hardening (per-session rejoin ticket) and the dead-code
> clean-ups are fixed. T3-03, T3-05 in the HUD and the HUD per-frame allocations move to the HUD redesign. The train
> paint was re-baked as clean painted metal, and the build items (plank, rail, track spike, fishplate bolt, spare panel)
> are textured Blender models now.

### Major (fix next)
- **T3-01 Main menu overflows with a save.** The button column is centred with no bottom limit. When Continue is shown, Quit runs off a 16:9 screen and covers the footer.
  Returning players see this every time (`main_menu.gd _build_ui`).
- **T3-02 Tests overwrite real saves.** TestTrain, TestRoute and NetTest write `user://checkpoint_solo.json`, `checkpoint_host.json` and `settings.cfg` (`seen_help`).
  Each pre-push test run therefore wipes the developer's own save. Only TestMenu backs up and restores.

### Minor
- T3-03: the intro banner (offset 200) covers the last line of the train card when its warning line shows.
- T3-04: the join dialog's dim layer covers the name card that the dialog itself points to.
- T3-05: the inventory says "Winch"; the shop, help and objectives say "Come-along".
- T3-06: the lobby's bottom bar touches the screen edge at 1600x900, while the crew panel has about 180 px of empty space.
- T3-07: the host's *Back to main menu* on the end screen ends the run for clients who chose *Keep exploring*, with no confirmation.
- T3-08: "Your name" sits under the Microphone / Voice chat header and uses a literal max length of 20 instead of `Net.NAME_MAX`.
- T3-09: intermediate stations 1 to 5 still look grey-box (bare concrete platform, kiosk and board) next to the textured train and the departure canopy.
- Critic round 3 (all minor):
  - name-based rejoin can be claimed by anyone who types the same name (small security hole);
  - the HUD allocates objects every frame;
  - a few docs and dead-code clean-ups;
  - test loose ends.

### Not built yet (by design, later milestones)
- **Steam backend:** GodotSteam lobbies and friend invites with no port forwarding. Only the stub exists.
- New players cannot join mid-run; only rejoining works.
- Meeting-table voting (M4).
- Body carry (M5).
- Intro and kidnap (M6).
- Crafting (M7).
- Quest maps that give the keys (M8).
- Chapter 2 (M9).
- Real sound effects and music beyond the generated loop.
- Voice has never been tested with a real microphone, and no human playtest has been done with friends yet.

## 5. Next steps (in order)
1. Fix **T3-01**: make the menu column fit the screen. Add a TestMenu check that the last button ends at least 50 px above the bottom of the viewport.
2. Fix **T3-02**: add a save-path override (`Game.save_dir` / `Settings` path) and point every test scene at `user://test/`.
3. Do the quick minor fixes: T3-03 (banner below the card), T3-05 (one name, "Come-along"), T3-06 (lobby bottom margin),
   T3-07 (confirm on the end screen), T3-04 and T3-08 (a name field in the join dialog; move "Your name" to a Profile section).
4. Harden rejoin: bind it to a per-session token the host gives out, instead of the name alone.
5. Dress stations 1 to 5: canopy or shelter, benches, a lamp, and a baked stone or plank platform texture (T3-09).
6. **On the owner's PC** (see [`TODO_LOCAL.md`](TODO_LOCAL.md)):
   - a mic test with real hardware;
   - a 2 to 5 player playtest over LAN and the internet (M5 vertical slice);
   - then the GodotSteam backend and a Steam App ID.
7. Sound pass: train, tools, UI clicks and ambience (CC0 or generated).
8. Quest maps (M8): replace the beside-the-gate keys with the first quest map (The Nest or The Mountain).
