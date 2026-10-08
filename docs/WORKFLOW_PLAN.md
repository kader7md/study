# How We Build the Game: Workflow Plan

Based on the reference video (Godot + Blender + Tripo3D pipeline).
**The video's exact method (MCP, concept→Tripo3D, master prompt, animations, cost control): [`VIDEO_METHOD.md`](VIDEO_METHOD.md)**

## 1. The tools

| Tool | What it does for us | Who uses it |
|------|---------------------|-------------|
| **Godot 4.x** (free) | The game engine: scenes, physics, UI, building the game | Claude writes the GDScript and scene files, you run and test in the editor |
| **GDScript** | Godot's scripting language (similar to Python) | Claude writes it, you review and play-test |
| **Tripo3D** (tripo3d.ai) | AI text/image → 3D model for **characters** and **enemies** | You generate the models, Claude writes the prompts |
| **Blender** (free) | Clean up models, rig them, animate, export `.glb` | You do the hands-on work, Claude gives step-by-step guides and Python scripts |
| **Mixamo** (free, optional) | Auto-rigging plus ready-made animations (walk, run, attack) | You |
| **GitHub** | Holds all code and assets, history of every change | Both of us |

## 2. The asset pipeline (character / enemy)

```
Idea → Concept image → Tripo3D (3D model) → Blender (clean-up, rig, animate) → .glb export → Godot (import, scripts)
```

1. **Concept**: Claude writes a detailed prompt (style, pose = T-pose, armour, colours).
   Generate a concept image if you want (Tripo3D accepts an image or text).
2. **Tripo3D**: generate the model in a **T-pose** (like the samurai and knight in the video).
   Download as `.glb` or `.fbx`.
3. **Blender**:
   - Fix scale (1 unit = 1 metre), apply transforms, set the origin at the feet.
   - Lower the poly count if needed (Decimate modifier).
   - Rig it (Tripo3D auto-rig, or Mixamo, or Rigify).
   - Add animations: `idle`, `walk`, `run`, `attack`, `hit`, `death`.
   - Export **glTF 2.0 (.glb)** with animations.
4. **Godot**: drop the `.glb` into `assets/models/...`. Godot imports it automatically.
   Claude writes the controller and AI scripts and the `AnimationTree` setup.

Keep characters and enemies in separate folders (as the video does):
`assets/models/characters/`, `assets/models/enemies/`.

## 3. How you and Claude split the work

**Claude (in the repo):**
- Game design doc, task breakdown, milestones
- All GDScript: player controller, camera, combat, enemy AI, UI, save system
- `.tscn` scene files and `project.godot` settings
- Tripo3D prompts, Blender step-by-step guides, Blender Python scripts for repeat jobs
- Reviewing bugs from your error messages and screenshots

**You (on your PC):**
- Run Godot, play-test, send back errors and screenshots
- Generate models in Tripo3D, do the Blender work
- Judge the art direction and how the game *feels*

Claude can't open the Godot editor or Blender from the cloud. **On your PC, with MCP connected, Claude can run both itself** (like in the video). You still judge how it looks and feels.

## 4. Repo layout

```
project.godot          ← created in Milestone 0
docs/                  ← plans, game design doc, asset prompts
scenes/                ← .tscn files (levels, player, enemies, UI)
scripts/               ← .gd files
assets/
  models/characters/   ← player, NPCs (.glb)
  models/enemies/      ← enemies (.glb)
  models/props/        ← weapons, items
  models/environment/  ← ruins, rocks, trees
  textures/  audio/music/  audio/sfx/
blender/               ← source .blend files
```

## 5. Phases

| Phase | Goal | Done when |
|-------|------|-----------|
| **0. Plan** (now) | Workflow (this file) + the **game idea** from you → Game Design Doc | GDD approved |
| **0.5 PC + MCP setup** | Move repo to PC, install Godot/Blender, connect **Godot MCP + Blender MCP** to Claude Code | Claude can run the game and Blender by itself |
| **1. Skeleton** | `project.godot`, player capsule moves, camera follows, test level from boxes | You can walk around in Godot |
| **2. Core loop** | The main mechanic (combat, exploring, …) with placeholder shapes | It's fun with grey boxes |
| **3. First real assets** | 1 hero + 1 enemy through the Tripo3D → Blender → Godot pipeline | Animated hero fights an animated enemy |
| **4. Content** | Levels, more enemies, items, UI, sound | A playable vertical slice |
| **5. Polish & export** | Menus, settings, bug fixes, export to Windows | A `.exe` your friends can play |

Rule: **gameplay first with grey boxes, art after.** It saves you from making art for features that get cut.

## 6. Cloud now, PC later

1. **Now (cloud, GitHub repo):** planning docs, GDD, all scripts and scenes, asset prompts. Claude pushes to branch `claude/sharp-clarke-rqh9ii`.
2. **When you move to your PC:**
   ```bash
   git clone https://github.com/kader7md/study.git
   cd study
   git checkout claude/sharp-clarke-rqh9ii   # or merge it into main first
   git lfs install                           # then un-comment the LFS lines in .gitattributes
   ```
   Open the folder in Godot 4 (Import → choose `project.godot`), then keep working with Claude Code locally.
3. Install on your PC: **Godot 4.x (standard build, not .NET)**, **Blender 4.x**, **Git + Git LFS**, a Tripo3D account.

## 7. Next step: send the game idea

To write the Game Design Doc, I need:
1. **Genre and camera**: e.g. third-person souls-like (the video's dark-fantasy look), top-down, first-person…
2. **Setting and mood**: the dark-fantasy ruins in the video, or something else?
3. **Core mechanic**: what does the player do most of the time?
4. **Scope**: small jam game (1–2 weeks) or a bigger project?
5. **Platform**: PC only? Mobile?
6. **Reference games** you like.
