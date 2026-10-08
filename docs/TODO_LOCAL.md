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
