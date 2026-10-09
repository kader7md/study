# ⚠️ TODO when the repo is on the local PC

Things we couldn't do from the cloud session. Do these **first** once the repo is cloned locally and the weekly limit is back.

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
- [ ] **Back up your saves before you run the tests.** The tests still write the real `user://checkpoint_solo.json`,
  `checkpoint_host.json` and `settings.cfg` (issue T3-02, a fix is planned). On Windows they are in
  `%APPDATA%\Godot\app_userdata\Trust Issues\`.
- [ ] **Microphone with real hardware:** Settings > Microphone: pick the device, check that the level meter moves, try
  "hear yourself", push-to-talk on (V) and off (noise gate). Then talk to a friend online and check proximity volume.
  The cloud session had no audio device, so voice is only tested in code.
- [ ] **Playtest with friends (M5):** host from the main menu, send the **Same Wi-Fi** code to someone on your network
  and the **Internet** code to someone outside it (forward UDP 24565 on the router, or press "Open the port (UPnP)").
  Play 2, 3 (impostor) and 5 players to station 5. Note lag, desyncs, confusing UI and where people got stuck;
  also try a drop-out and rejoin with the same name.
- [ ] **Firewall:** the first Host game on Windows shows a firewall prompt; allow private and public networks.
- [ ] **Steam / GodotSteam:** get a Steam App ID (or test with 480 Spacewar), install the GodotSteam GDExtension for
  4.7, fill in `scripts/net/steam_backend.gd` (steps in `docs/NETWORK.md`), then test lobby invites through the Steam
  overlay with a friend. That removes the need for port forwarding.
- [ ] **Look at the game on a real GPU** (Forward+ instead of the cloud's software opengl3): lighting, shadows, FPS at
  1080p / 1440p, and the Graphics settings (window modes, V-Sync, resolution scale).
- [ ] **Export builds** (Windows / Linux templates for 4.7.2) and try them on a friend's PC.

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
