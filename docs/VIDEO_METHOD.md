# The Video's Method (Elden Ring-style game with Claude Opus + Godot + Blender)

> ⚠️ **Incomplete:** based on a short summary only. Full transcript analysis is pending, see [`TODO_LOCAL.md`](TODO_LOCAL.md).

Source: *"САМЫЕ МОЩНЫЕ НЕЙРОСЕТИ СОЗДАЮТ ELDEN RING С НУЛЯ | Claude Opus vs GPT Astra в движке Godot"*, НейроЧел+
(https://www.youtube.com/watch?v=oJ5PJcOGuaY). Taken from a summary of the video, not a full transcript.

## The 5 tricks and how we copy them

### 1. MCP: Claude controls Godot and Blender directly (the main trick)
He didn't copy and paste code. Claude was connected through **MCP servers**, so it could run scripts inside the
Blender and Godot editors itself: build scenes, run the game, read errors, fix them.

**For us:**
- **Blender MCP** (e.g. `ahujasid/blender-mcp`): Claude runs Python in Blender. It can make or fix models,
  apply transforms, decimate and export `.glb`.
- **Godot MCP** (e.g. `Coding-Solo/godot-mcp`): Claude can launch the editor and run the project,
  read debug output, and create scenes and nodes.
- Check each repo's README for current install steps and versions before installing.
- ⚠️ **This only works on your PC.** Godot and Blender must run on the same machine as Claude Code.
  The cloud session (where we are now) can't do it, so we set it up as soon as the repo moves to your PC.

### 2. Concept art → Tripo3D → rigged 3D model
AI makes 2D concept art, Tripo3D turns it into a textured 3D model, and Tripo3D also **auto-rigs** it.
No manual modelling or rigging.

**For us:**
1. Claude writes the concept prompt: character, armour, colours, **T-pose or A-pose**, plain background, full body.
2. Generate the image with any image AI you have.
3. Upload it to Tripo3D (image-to-3D). Turn on quad remesh and PBR textures, and choose **low-poly / game-ready**.
4. Auto-rig in Tripo3D. Export `.glb`.
5. If the rig is bad: **strip it and re-rig** (Tripo3D, Mixamo or AccuRIG) rather than patching it.
   Then fix the weights in Blender, which Claude can do through Blender MCP.

### 3. One big structured prompt with permission to use both tools
He gave large prompts that let the AI use **Blender and Godot as needed**. If the level lacked assets,
the AI opened Blender and made new ones on the fly.
→ Our template is in [Master prompt](#master-prompt-template) below.

### 4. Use ready-made animations from the internet
The AI wrote the logic, but also **searched for existing high-quality open-source animations** instead of making everything itself.

**For us (free sources):**
- **Mixamo** (free, needs an Adobe account): idle, run, roll, sword attacks, hit, death
- **Quaternius** animation and model packs (CC0)
- **Kenney** assets (CC0) for props and placeholders
- **Poly Haven** (CC0) for textures, HDRI skies and rocks

Credit and licence of everything we use goes in `docs/CREDITS.md`.

### 5. Control token and API costs
He gave and took away API keys (e.g. OpenRouter keys for image generation) so the AI only spent money when he wanted.

**For us:**
- Keep keys in a local `.env` file that's in `.gitignore` and **never committed**.
- Give an MCP or tool its key only for the task that needs it, then remove it.
- Plan in the cloud on cheap turns. Do heavy agent sessions (MCP loops) only for a defined task.
- Your $250 API credit: use it for the big build sessions, not for chatting.

## The resulting pipeline

```
Claude writes concept prompt → image AI → Tripo3D (model + auto-rig) → Blender via MCP (clean, fix weights, export .glb)
        → Godot via MCP (import, AnimationTree, scripts, test run, read errors, fix) → you play-test
                                ↑ Mixamo / Quaternius / CC0 animations
```

## Souls-like features to build (Elden Ring style)
- Third-person camera plus **lock-on**
- **Stamina** for attack, roll and sprint
- **Dodge roll** with invincibility frames
- Light and heavy attacks, hit-stop, poise and stagger
- Enemies with **telegraphed attacks**, plus a boss with phases
- **Bonfire / grace** checkpoints, with enemies respawning when you rest
- Drop your runes on death and pick them up again
- Dark-fantasy look: volumetric fog, SDFGI/GI, glow, golden-hour sky, ruins (Godot WorldEnvironment)

## Master prompt template

```
You are building a souls-like 3D action game in Godot 4 (GDScript) for the repo in this folder.
You have Godot MCP and Blender MCP tools. You MAY:
- create/edit scenes and scripts, run the project, read the errors and fix them yourself
- open Blender to create or repair assets when existing assets are missing or not good enough,
  then export .glb into assets/models/<category>/
- search for free CC0/open-licence assets and animations (Mixamo, Quaternius, Kenney, Poly Haven)
  and log their licence in docs/CREDITS.md
Read docs/GDD.md and docs/VIDEO_METHOD.md first.
Task for this session: <ONE CLEAR TASK, e.g. "player controller: move, sprint, roll with i-frames, stamina">
Done when: <TEST, e.g. "the player can roll through an enemy attack without taking damage">
Do not touch other systems. Commit when done.
```
One clear task per session. That keeps cost down and results good.
