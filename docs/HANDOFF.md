# Handoff: cloud session → local PC

Read this first in a new Claude Code session on the local PC.
Local folder: `D:\desktop\work\games coding\Trust Issues game\Trust Issues`
Branch: `claude/sharp-clarke-rqh9ii` on https://github.com/kader7md/study (public repo).

## State at handoff
- **Game:** Trust Issues, co-op train chase for 1–5 players, with a secret impostor at 3–5. Built in Godot 4.7.2 with
  GDScript; models come from Blender 4.5 scripts. The design source of truth is `docs/GDD.md`.
- **Built and tested:**
  - Main menu, settings (key rebinding, graphics, audio, mic), pause menu.
  - ENet host/join with invite codes, a lobby, rejoin tickets, and proximity voice.
  - Six stations and five locked gates with keys, and the Chapter 1 ending.
  - The train: distance-based movement, two-bar damage (body, plus wheels/engine/chassis), and a breakable cover.
  - Hands-on repair: planks, nails, rails, bolts, the station welder, and the come-along winch to tip the train back.
  - **Cartoon crew character:** rigged, 20 animations, and a mirror in the utility wagon with a look editor.
  - **HUD:** train bars top centre, team supplies, health/warmth, hotbar 1–5, and a Tab 5×5 personal inventory with food.
  - **World:** a big heightmap overworld with weather per biome, hazards, caves, rope bridges, and a flat quest site per gate.
  - **The Mountain (gate 2):** a Peak-style climbing quest map with stamina and campfires; the summit key opens the gate.
- **Tests (all PASSED at handoff):** TestTrain, TestRoute, TestMenu, TestCharacter, TestQuest, `tests/run_net_test.sh`.

## Open work (flagged)
- Everything that needs a real PC, plus per-pass leftovers: `docs/TODO_LOCAL.md`.
  Section 0 is the move itself; then the sections "Open from the … pass".
- **Most urgent:** check the frame rate on a real GPU. The big world was only measured on software rendering.
  Then watch the animations live, and play the mountain to tune climbing.
- **Not built yet:** meeting-table voting, body carry and goat-altar revive, the intro and kidnap, crafting
  (spear, blueprints), the Nest quest map, Chapter 2 at sea, sound and music, Steam (GodotSteam).
- Polish history and reports: `docs/POLISH_PLAN.md`, `docs/POLISH_REPORT.md`.
- Reference-game ideas (RV There Yet, Peak): `docs/REFERENCE_NOTES.md`.
- Reference video analysis still open: `docs/TODO_LOCAL.md` §1 and `docs/VIDEO_METHOD.md`.

## Rules the owner set
- Don't use Higgsfield tools.
- Only CC0 or self-made assets. Never copy files from RV There Yet, Peak or other games into this public repo.
  Study installed copies locally instead.
- No AI model names in the repo. Commits end with the Co-Authored-By / Claude-Session lines used in the git log.
- Don't create a PR unless asked.
- Before pushing, run the tests listed in `CLAUDE.md`.
