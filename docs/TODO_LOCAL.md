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
