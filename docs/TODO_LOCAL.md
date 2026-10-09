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
