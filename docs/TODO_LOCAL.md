# ⚠️ TODO when the repo is on the local PC

Things we couldn't do from the cloud session. Do these **first** once the repo is cloned locally and the weekly limit is back.

## 0. Move to the local PC (start here)
Local folder: `D:\desktop\work\games coding\Trust Issues game\Trust Issues`
```powershell
cd "D:\desktop\work\games coding\Trust Issues game"
git clone -b claude/sharp-clarke-rqh9ii https://github.com/kader7md/study.git "Trust Issues"
cd "Trust Issues"
```
Then open the folder in Godot 4.7.2 and press F5. The tests (as in CLAUDE.md) should print PASSED.

**Reference games (study only, never copy files into this public repo):** RV There Yet (HUD, winch, repair,
map flow), Peak (climbing, stamina, the mountain level), Raft (sea chapter), Among Us (impostor, voting).
Ideas taken from them so far are in `docs/REFERENCE_NOTES.md`; keep the games' own files outside git.

**Next big features not built yet:** meeting-table voting, body carry / goat altar revive, the intro and kidnap,
crafting (spear, blueprints), the Backrooms-style Nest quest map, Chapter 2 (sea / raft), real sound and music, Steam.

## 1. Fully analyse the reference video
- Video: https://www.youtube.com/watch?v=oJ5PJcOGuaY ("САМЫЕ МОЩНЫЕ НЕЙРОСЕТИ СОЗДАЮТ ELDEN RING С НУЛЯ | Claude Opus vs GPT Astra в движке Godot", НейроЧел+)
- **Why it's open:** YouTube blocked the cloud server (robot check), so Claude never saw the transcript.
  `docs/VIDEO_METHOD.md` is based only on a short summary.
- **How:** open the video in your browser, click "…more", then "Show transcript", and paste the full text plus the description to Claude
  (or let Claude read it through the desktop app or Claude in Chrome, which won't be blocked on your own connection).
- **What to pull out:**
  - [ ] The exact prompts he gave Claude Opus (and GPT Astra)
  - [ ] Which MCP servers he used for Godot and Blender, and how he set them up
  - [ ] His step order: what he built first, second and so on
  - [ ] How he made the concept art and his Tripo3D settings (rig, poly count, export format)
  - [ ] Which animation sources he used and how he fit them into Godot
  - [ ] His lighting and post-processing setup for the Elden Ring look
  - [ ] Where Claude beat GPT and where it failed, and the mistakes to avoid
  - [ ] Cost: how many tokens or dollars it took, and how he handled keys (OpenRouter)
- **Then:** update `docs/VIDEO_METHOD.md` with anything we missed and fix the plan if needed.

## 2. Set up MCP (phase 0.5 in WORKFLOW_PLAN.md)
- [ ] Install Godot 4.x, Blender 4.x, Git and Git LFS
- [ ] Enable the Git LFS lines in `.gitattributes`
- [ ] Install and connect Blender MCP and Godot MCP to Claude Code
- [ ] Test: Claude creates a cube in Blender, and Claude runs an empty Godot project

## 3. Things from the polish session that need your PC (see `docs/POLISH_REPORT.md`)
- [x] ~~Back up your saves before you run the tests~~: fixed (T3-02). Test scenes keep their saves and settings in
  `user://test/<TestScene>/` (on Windows `%APPDATA%\Godot\app_userdata\Trust Issues\test\`), never your own files.
- [ ] **Microphone with real hardware:** Settings > Microphone: pick the device, check that the level meter moves, try
  "hear yourself", push-to-talk on (V) and off (noise gate). Then talk to a friend online and check proximity volume.
  The cloud session had no audio device, so voice is only tested in code.
- [ ] **Playtest with friends (M5):** host from the main menu, send the **Same Wi-Fi** code to someone on your network
  and the **Internet** code to someone outside it (forward UDP 24565 on the router, or press "Open the port (UPnP)").
  Play 2, 3 (impostor) and 5 players to station 5. Note lag, desyncs, confusing UI and where people got stuck;
  also try a drop-out and rejoin (same invite code, without closing the game).
- [ ] **Firewall:** the first Host game on Windows shows a firewall prompt; allow private and public networks.
- [ ] **Steam / GodotSteam:** get a Steam App ID (or test with 480 Spacewar), install the GodotSteam GDExtension for
  4.7, fill in `scripts/net/steam_backend.gd` (steps in `docs/NETWORK.md`), then test lobby invites through the Steam
  overlay with a friend. That removes the need for port forwarding.
- [ ] **Look at the game on a real GPU** (Forward+ instead of the cloud's software opengl3): lighting, shadows, FPS at
  1080p / 1440p, and the Graphics settings (window modes, V-Sync, resolution scale).
- [ ] **Export builds** (Windows / Linux templates for 4.7.2) and try them on a friend's PC.

## Open from the character pass
**Flagged: these were not finished or not checked on a real screen in the cloud session.**
- [ ] **Check the animations live on a real GPU, with friends** (`blender/scripts/build_character.py`). The cloud
  machine was overloaded, so the clips were only checked as still frames (`tests/ScreenshotCharacter.tscn`, modes
  model / anims / game). Watch walk / run timing (`CharacterAnimator.WALK_SPEED`, `RUN_SPEED`), the jump / fall
  switch on remote players (worked out from the synced positions), and how the one-shot actions blend over walking.
- [ ] **Tool grips on other players** (`CharacterModel.TOOL_GRIP`): the hammer and wrench look right. The nail gun and
  the welding torch may point the wrong way in the hand: check them, and turn them in `TOOL_GRIP` if needed.
- [ ] **The plank on the shoulder and the rail in the arms** (`CharacterModel.CARRY_POSE` and the
  `carry_shoulder` / `carry_front` clips) were tuned once and not looked at again after the last change.
- [ ] **First-person sleeve:** the new bare hand and sleeve (`fp_arm.glb`) fill a lot of the screen with the wrench.
  Maybe make it thinner or shorter, or move `Viewmodel.RIGHT_REST`.
- [ ] **The mirror image renders a bit dark** in opengl3 (`Mirror`; the glass tint tries to brighten it). Check it
  in Forward+.
- [ ] **New first-person clips** (`Viewmodel.ANIMS`: interact, shovel, lever, wave) were added at the end and never
  seen on screen.
- [ ] Downed pose: the body lies on the ground but was only seen from one angle. Check that it lies on its back.
- [ ] Not done: a look preview in the crew lobby cards (the `look` is already in `Net.players`), and a climbing
  state on the Player (the `climb` clip is in place for the mountain map).

## Open from the HUD/inventory pass
⚠️ Left open when the HUD redesign and the team pool / personal inventory split were committed:
- [ ] **HUD draw cost on a real GPU:** the bars, train status and readout redraw every frame (striped fills are clipped
  with `Geometry2D.intersect_polygons`). Check the FPS; if it costs, redraw only when a value changes (or cache the
  stripes in a texture / a small shader). Headless runs already skip these redraws (`HudStyle.headless`).
- [ ] **Held food has no first-person model:** with food in the hotbar the hands are empty (LMB still eats it). Add small
  food props to the viewmodel / RemoteBody, and an eating animation.
- [ ] **Come-along "reverse" (RMB):** the hints show Pull / Release only; slacking the chain is not built.
- [ ] **Dropping items** out of the personal inventory onto the ground (and giving items to a crewmate) is not built.
- [ ] **Old saves:** a checkpoint from before the split gives its coal / scrap / tools to the host; its scrap is not turned
  into rails. Start a new run if a save feels off.
- [ ] **Playtest the balance** of the split (each player starts with 10 coal, 4 scrap, a sandwich, 2 apples; food every
  ~120 m; health only comes back by eating) with 2-5 players.
- [ ] Re-take the HUD screenshots on a real GPU (`tests/Screenshot.tscn ... hud`: play, shop, pause, inventory,
  low health / frost, come-along hooked and pulling, help).

## Open from the fixes pass
> ⚠️ **Not done in the cloud fixes pass. Pick these up locally.**
- [ ] **T3-03, and T3-05 in the HUD, plus the HUD per-frame allocations:** handed to the HUD redesign (`scripts/ui/hud.gd`).
  The intro banner still overlaps the train card's wheel warning line, and the inventory chip still says "Winch".
- [ ] **Platform flagstones look almost white in Godot** (the bake is fine; Godot's lighting brightens them). Darken
  `flagstone` / `flagstone_dark` / `coping_stone` in `blender/scripts/build_station.py` and re-run `only=platform`.
- [ ] **No screenshots yet of the new build items** (plank sleeper, rail, track spike, fishplate bolt, spare panel) in game:
  run `Screenshot.tscn -- <dir> tools` and `repair`, and check that the spike and bolt sizes look right.
- [ ] Tools and props that use the `paint` material (wrench grip, nail gun, welder machine, come-along, kiosk tins)
  still have the old speckled bake. Re-run `build_assets.py only=props` and `build_station.py only=tools` to give them
  the clean paint. Only the four train models were re-baked.
- [ ] Rejoin tickets live only in memory. A player who closes the game cannot rejoin the running run (by design for now).

## Open from the mountain quest pass
⚠️ The Mountain (quest map, segment 2) is built and tested headless; these are the parts NOT done or NOT verified:
- [ ] **Play it by hand on a real GPU** and tune: stamina numbers (`scripts/quest/climber.gd`: drain 8/s moving,
  climb 2 m/s, so a ~13 m cliff costs ~52 of 100), fall damage (over 7 m), the cold (up to -45 max stamina).
- [ ] **Entering builds the map in 2-4 s** (heightmap + scatter, `MountainMap.build`): a short freeze. Ideas: build
  it on a thread while the banner shows, or pre-build it when the train stops at the gate.
- [ ] **Looks:** the terraces read as rings from far away; more hand-placed Blender cliff faces along the risers, a
  better rock tile texture (`build_mountain.py` `_rock_color`), and vines in the jungle would help.
- [ ] **Climbing animation hook:** `player.is_climbing` / `player.is_hanging` are synced; the character agent's
  third-person climbing animation still has to use them. First-person hands have no climbing pose yet.
- [ ] **HUD:** the stamina bar is a fallback in `scripts/quest/quest_hud.gd`; it calls `HUD.set_stamina(value 0..100,
  visible)` when the new HUD has it (value passed in 0..100, check it matches what the HUD expects).
- [ ] **Overworld quest zone:** the portal uses `Terrain.quest_zone(seg)` when it exists, else stands where the key
  used to lie. Check it once the terrain agent's plateaus are merged.
- [ ] Ideas not built: crank lifts / gondola, a cave route, goats or snow leopards, impostor sabotage on quest maps.

## Open from the world-map pass
⚠️ The big overworld (Landscape / Terrain / WorldFeatures / Atmosphere) works and passes the tests, but these are open:
- [ ] **Frame rate on a real GPU.** Only measured on software rendering in the cloud (0.2 fps, ~510 draw calls,
  ~0.7 M primitives at a ground view: meaningless for a GPU). Check FPS locally (`tests/Screenshot.tscn -- <dir> world ground`
  prints `[fps]`); tune `Terrain.LOD_END`, the `SCATTER` view distances and the tree density if needed.
- [ ] **Build time.** The terrain takes several seconds to build on every start (and five times in TestMenu). Ideas: cache the
  heightmap per seed in `user://`, or compute it on worker threads (`Terrain.THREADS`; GDScript threads were slower in the
  cloud test, re-measure on a desktop CPU).
- [ ] **Hazard feel** (mud, quicksand, ice, thorns, geysers) and the out-of-bounds warning are untested by hand: walk them.
- [ ] **New nature models** (`rock_spire`, `cliff_big`, `cave`, `flowers`, `fern`, `thorn_bush`): check they look right in-game;
  if one is missing, rebuild with `blender --background --python blender/scripts/build_nature.py -- <repo> <names>`.
- [ ] Caves are rock domes on open ground with a trimesh collider: check you can walk in and out.
- [ ] Rope bridges, waterfalls and rockfalls: look at them in-game (no close-up screenshots were taken).
- [ ] Multiplayer: the land is deterministic (checked in TestRoute), but rockfalls and falling trees play per peer (visual
  timing may differ slightly between peers).
