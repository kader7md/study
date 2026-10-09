# Asset credits

Everything else in `assets/` is made for this project (Blender scripts in `blender/scripts/`, or built in code).

| Asset | Author | License | Source |
|-------|--------|---------|--------|
| `fonts/kenney_rocket.ttf` (Kenney Rocket, title logo) | Kenney (www.kenney.nl) | CC0 1.0 | https://kenney.nl/assets/kenney-fonts |
| `fonts/Fredoka-Variable.ttf` (Fredoka, in-game HUD font) | The Fredoka Project Authors (Milena Brandão, Hafontia) | SIL Open Font License 1.1 (`fonts/LICENSE_Fredoka_OFL.txt`) | https://fonts.google.com/specimen/Fredoka |

Menu text uses Open Sans SemiBold, the font built into Godot (no file in this repo); the in-game HUD uses Fredoka.
HUD line icons are drawn in code (`scripts/ui/hud/hud_style.gd`); item icons, including the food, are rendered by
`blender/scripts/render_icons.py`.
UI sounds (menu click and hover) are generated in code (`scripts/autoload/settings.gd`).
