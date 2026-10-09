"""Builds the station props and the first-person arm in Blender (same helpers, wear and bake as build_assets.py).

Run headless:
    blender --background --python blender/scripts/build_station.py -- <repo_root> [only=station,kiosk,sign,platform,tools,arm]

Exports to assets/models/props:
    station_shelter.glb  platform canopy: cast-iron columns with brackets, a pitched roof sloping to the track with a
                         fretted wooden valance, a timber back wall with notice boards, benches, lamp posts.
                         Origin = platform top, middle of the platform; the track side is -X (Godot -X too).
    shop_kiosk.glb       wooden shop kiosk: serving window with a counter, striped awning, crates and a barrel.
                         The window faces the track (-X). The sign board above it is blank (Godot puts the text on it).
    station_sign.glb     name board on two iron posts, blank (Godot puts the station name on it). Faces -X.
    platform_section.glb 6 m of platform (Station tiles it along the 60 m platform): a brick face on the track side
                         and at the back, a rounded stone coping with a painted yellow safety line, and flagstones.
                         Origin = platform top at the track-side edge (Godot x = Station.EDGE_X), middle of the
                         section; the platform runs 4 m away from the track (+X).
    station_bench.glb    slatted wooden bench on cast-iron ends, facing the track (-X). Origin on the floor.
    station_lamp.glb     cast-iron platform lamp post with a glazed lantern. Origin at its foot.
    gravestone.glb       weathered headstone on a plinth with a carved cross and a wreath, facing -X.
    come_along.glb       hand winch (ratchet puller): red body, long pump handle, chain and two hooks.
    arm.glb              first-person arm: work glove (palm, curled fingers, thumb, cuff) and the jacket sleeve.
                         Hand at the origin, the forearm runs along Blender -Y (= Godot +Z, towards the camera).
Axes: Blender +Y = Godot -Z, Z up.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_assets as B  # noqa: E402  (helpers, materials, bake)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("only=")), None)
OUT = B.OUT_PROPS

B.MATS.update({
    "column_green": ("paint", (0.06, 0.16, 0.1), 0.4, 0.5),
    "valance_cream": ("paint", (0.78, 0.7, 0.52), 0.1, 0.6),
    "awning_red": ("canvas", (0.55, 0.08, 0.06), 0.0, 0.9),
    "awning_cream": ("canvas", (0.82, 0.76, 0.6), 0.0, 0.9),
    "board_cream": ("enamel", (0.8, 0.74, 0.58), 0.05, 0.6),
    "slate": ("rock", (0.16, 0.17, 0.19), 0.0, 0.7),
    "glove": ("canvas", (0.36, 0.22, 0.1), 0.0, 0.75),
    "jacket": ("canvas", (0.62, 0.36, 0.16), 0.0, 0.9),
    "winch_red": ("paint", (0.55, 0.06, 0.04), 0.4, 0.45),
    "platform_brick": ("brick", (0.36, 0.14, 0.08), 0.0, 0.9),
    "flagstone": ("stone", (0.42, 0.4, 0.36), 0.0, 0.92),
    "flagstone_dark": ("stone", (0.34, 0.33, 0.3), 0.0, 0.92),
    "coping_stone": ("stone", (0.55, 0.53, 0.48), 0.0, 0.85),
    "line_yellow": ("enamel", (0.85, 0.62, 0.08), 0.0, 0.6),
    "headstone": ("stone", (0.45, 0.45, 0.43), 0.0, 0.9),
    "moss": ("foliage", (0.12, 0.2, 0.06), 0.0, 0.95),
})

box, cyl, rod, sphere, torus, join = B.box, B.cyl, B.rod, B.sphere, B.torus, B.join


def build_shelter():
    B.clear_scene()
    half = 14.0           # canopy length 28 m (the platform is 60 m)
    parts = []
    # cast-iron columns at the back with curly brackets under the roof
    for k, y in enumerate((-12.0, -6.0, 0.0, 6.0, 12.0)):
        x = 1.9
        parts.append(cyl(f"col{k}", 0.09, 3.1, (x, y, 1.55), "column_green", verts=16))
        parts.append(cyl(f"colbase{k}", 0.16, 0.25, (x, y, 0.12), "column_green", verts=16, radius2=0.11))
        parts.append(cyl(f"colcap{k}", 0.1, 0.18, (x, y, 3.12), "column_green", verts=16, radius2=0.16))
        for s in (-1, 1):
            parts.append(rod(f"brk{k}{s}", (x, y, 2.55), (x - 0.9, y + 0.0, 3.05), 0.035, "column_green", 8))
            parts.append(rod(f"brkb{k}{s}", (x, y, 2.55), (x, y + 0.7 * s, 3.08), 0.03, "column_green", 8))
        parts.append(torus(f"scroll{k}", 0.18, 0.025, (x - 0.35, y, 2.75), "column_green", axis="Y", seg=20))
    # beams along the platform carry the roof
    parts.append(box("beam_back", (0.18, half * 2, 0.22), (1.9, 0, 3.2), "column_green", 0.01))
    parts.append(box("beam_front", (0.14, half * 2, 0.18), (-0.6, 0, 3.32), "column_green", 0.01))
    # pitched roof, sloping down towards the track, with corrugated ribs
    tilt = math.radians(7)
    parts.append(box("roof", (4.9, half * 2 + 0.6, 0.08), (0.9, 0, 3.45), "roof_grey", 0.01, rot=(0, -tilt, 0)))
    for k in range(int(half * 2 / 0.5) + 1):
        y = -half + k * 0.5
        parts.append(box(f"rib{k}", (4.9, 0.05, 0.05), (0.9, y, 3.51), "roof_grey", 0.004, rot=(0, -tilt, 0)))
    parts.append(box("ridge", (0.25, half * 2 + 0.6, 0.12), (3.3, 0, 3.78), "iron", 0.01))
    # fretted wooden valance hanging from the track-side edge
    edge_x, edge_z = -1.5, 3.12
    parts.append(box("valance_rail", (0.08, half * 2 + 0.6, 0.12), (edge_x, 0, edge_z + 0.12), "valance_cream", 0.005))
    n = int((half * 2 + 0.4) / 0.24)
    for k in range(n):
        y = -half - 0.2 + k * 0.24 + 0.12
        parts.append(box(f"fret{k}", (0.04, 0.17, 0.42), (edge_x, y, edge_z - 0.12), "valance_cream", 0.004))
        parts.append(box(f"fretpt{k}", (0.04, 0.12, 0.12), (edge_x, y, edge_z - 0.36), "valance_cream", 0.004,
                         rot=(math.radians(45), 0, 0)))
    # timber back wall with a cream dado, a notice board and a timetable
    parts.append(box("wall", (0.14, half * 2, 2.9), (2.25, 0, 1.45), "wood_dark", 0.01))
    for k in range(int(half * 2 / 0.3)):
        y = -half + 0.15 + k * 0.3
        parts.append(box(f"board{k}", (0.03, 0.26, 2.9), (2.17, y, 1.45), "wood", 0.006))
    parts.append(box("dado", (0.06, half * 2, 0.16), (2.13, 0, 0.95), "valance_cream", 0.005))
    for k, y in enumerate((-8.5, 3.5)):
        parts.append(box(f"notice_frame{k}", (0.05, 1.5, 1.0), (2.1, y, 1.8), "column_green", 0.01))
        parts.append(box(f"notice{k}", (0.03, 1.32, 0.82), (2.07, y, 1.8), "paper", 0.004))
        for j in range(4):
            parts.append(box(f"line{k}{j}", (0.02, 1.0, 0.04), (2.055, y, 2.05 - j * 0.16), "black_paint", 0.002))
    # benches
    for k, y in enumerate((-3.0, 9.0)):
        for j in range(3):
            parts.append(box(f"seat{k}{j}", (0.14, 1.8, 0.05), (1.55 + j * 0.16, y, 0.48), "wood", 0.006))
        for j in range(2):
            parts.append(box(f"back{k}{j}", (0.05, 1.8, 0.14), (1.98, y, 0.7 + j * 0.2), "wood", 0.006,
                             rot=(0, math.radians(-12), 0)))
        for s in (-0.75, 0.75):
            parts.append(box(f"leg{k}{s}", (0.5, 0.06, 0.06), (1.7, y + s, 0.25), "iron", 0.006, rot=(0, math.radians(30), 0)))
            parts.append(box(f"legb{k}{s}", (0.06, 0.06, 0.95), (1.98, y + s, 0.5), "iron", 0.006))
    # two lamp posts near the platform edge
    for k, y in enumerate((-10.0, 10.0)):
        parts.append(cyl(f"lpost{k}", 0.06, 3.0, (-1.0, y, 1.5), "column_green", verts=12))
        parts.append(cyl(f"lbase{k}", 0.13, 0.3, (-1.0, y, 0.15), "column_green", verts=12, radius2=0.08))
        parts.append(box(f"lcase{k}", (0.26, 0.26, 0.34), (-1.0, y, 3.15), "black_paint", 0.02))
        parts.append(box(f"lglass{k}", (0.2, 0.27, 0.24), (-1.0, y, 3.15), "lamp", 0.01))
        parts.append(cyl(f"lroof{k}", 0.22, 0.14, (-1.0, y, 3.4), "black_paint", verts=4, radius2=0.03,
                         rot=(0, 0, math.pi / 4)))
    # a clock hanging under the middle of the roof
    parts.append(rod("clock_rod", (0.2, 0.0, 3.2), (0.2, 0.0, 2.85), 0.02, "iron", 6))
    parts.append(cyl("clock_case", 0.3, 0.14, (0.2, 0.0, 2.55), "column_green", axis="X", verts=28))
    for s in (-1, 1):
        parts.append(cyl(f"clock_face{s}", 0.25, 0.02, (0.2 + 0.075 * s, 0.0, 2.55), "dial", axis="X", verts=28))
        parts.append(box(f"clock_h{s}", (0.01, 0.025, 0.16), (0.2 + 0.088 * s, 0.0, 2.6), "black_paint", 0.002))
        parts.append(box(f"clock_m{s}", (0.01, 0.16, 0.02), (0.2 + 0.088 * s, 0.06, 2.55), "black_paint", 0.002))
    join("StationShelter", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "station_shelter.glb"), 2048)


def build_kiosk():
    B.clear_scene()
    w, d, h = 2.6, 2.0, 2.5      # along the track (Y), depth (X), wall height
    parts = []
    parts.append(box("floor", (d + 0.2, w + 0.2, 0.12), (0, 0, 0.06), "wood_dark", 0.01))
    # plank walls: back, two sides and the front below / above the window
    for k in range(int(w / 0.2)):
        y = -w / 2 + 0.1 + k * 0.2
        parts.append(box(f"back{k}", (0.07, 0.19, h), (d / 2, y, h / 2 + 0.1), "wood", 0.006))
        parts.append(box(f"front_lo{k}", (0.07, 0.19, 0.95), (-d / 2, y, 0.58), "wood", 0.006))
        parts.append(box(f"front_hi{k}", (0.07, 0.19, 0.42), (-d / 2, y, h - 0.1), "wood", 0.006))
    for s in (-1, 1):
        for k in range(int(d / 0.2)):
            x = -d / 2 + 0.1 + k * 0.2
            parts.append(box(f"side{s}{k}", (0.19, 0.07, h), (x, s * w / 2, h / 2 + 0.1), "wood", 0.006))
        for x in (-d / 2, d / 2):
            parts.append(box(f"corner{s}{x}", (0.14, 0.14, h + 0.1), (x, s * w / 2, h / 2 + 0.12), "wood_dark", 0.01))
    # counter in the window, with a cash box and goods
    parts.append(box("counter", (0.6, w - 0.1, 0.07), (-d / 2 - 0.15, 0, 1.08), "wood_dark", 0.01))
    for s in (-0.8, 0.8):
        parts.append(box(f"bracket{s}", (0.4, 0.05, 0.05), (-d / 2 - 0.15, s, 0.95), "iron", 0.004, rot=(0, math.radians(35), 0)))
    parts.append(box("cashbox", (0.3, 0.4, 0.18), (-d / 2 - 0.05, 0.75, 1.21), "green_paint", 0.01))
    parts.append(box("cashlid", (0.31, 0.41, 0.03), (-d / 2 - 0.05, 0.75, 1.31), "brass", 0.004))
    for k in range(3):
        parts.append(box(f"nailbox{k}", (0.22, 0.2, 0.14), (-d / 2 - 0.1, -0.85 + k * 0.26, 1.18), "cream_paint", 0.008))
    # shelves inside, with tins and coal sacks
    for z in (1.3, 1.8):
        parts.append(box(f"shelf{z}", (0.35, w - 0.3, 0.04), (d / 2 - 0.25, 0, z), "wood_grey", 0.004))
        for k in range(5):
            parts.append(cyl(f"tin{z}{k}", 0.07, 0.18, (d / 2 - 0.25, -0.9 + k * 0.45, z + 0.11), "red_paint" if k % 2 else "blue_paint", verts=12))
    # roof sloping back, and a striped awning over the window
    parts.append(box("roof", (d + 0.7, w + 0.5, 0.1), (0.05, 0, h + 0.28), "roof_grey", 0.01, rot=(0, math.radians(-8), 0)))
    stripes = 9
    for k in range(stripes):
        y = -w / 2 - 0.1 + (w + 0.2) * (k + 0.5) / stripes
        parts.append(box(f"awn{k}", (1.0, (w + 0.2) / stripes + 0.005, 0.03), (-d / 2 - 0.45, y, h - 0.05),
                         "awning_red" if k % 2 == 0 else "awning_cream", 0.004, rot=(0, math.radians(22), 0)))
        parts.append(box(f"awnflap{k}", (0.03, (w + 0.2) / stripes + 0.005, 0.2), (-d / 2 - 0.92, y, h - 0.32),
                         "awning_red" if k % 2 == 0 else "awning_cream", 0.004))
    for s in (-1, 1):
        parts.append(rod(f"awnrod{s}", (-d / 2, s * (w / 2 + 0.05), h + 0.1), (-d / 2 - 0.9, s * (w / 2 + 0.05), h - 0.2), 0.02, "iron", 8))
    # blank sign board on the roof (Godot writes SHOP on it)
    parts.append(box("sign", (0.08, 2.2, 0.6), (-d / 2 + 0.2, 0, h + 0.75), "board_cream", 0.01))
    parts.append(box("sign_frame", (0.06, 2.34, 0.74), (-d / 2 + 0.24, 0, h + 0.75), "column_green", 0.01))
    for s in (-0.8, 0.8):
        parts.append(box(f"sign_leg{s}", (0.06, 0.06, 0.5), (-d / 2 + 0.25, s, h + 0.4), "iron", 0.004))
    # crates and a barrel beside the kiosk
    for k, (x, y, z, sz) in enumerate(((-0.6, w / 2 + 0.55, 0.3, 0.6), (-0.5, w / 2 + 0.6, 0.85, 0.5), (0.2, w / 2 + 0.5, 0.3, 0.6))):
        parts.append(box(f"crate{k}", (sz, sz, sz), (x, y, z), "wood", 0.015))
        for e in (-1, 1):
            parts.append(box(f"crateband{k}{e}", (sz + 0.02, 0.05, sz + 0.02), (x, y + e * (sz / 2 - 0.08), z), "wood_dark", 0.004))
    parts.append(cyl("barrel", 0.3, 0.8, (-0.6, -w / 2 - 0.5, 0.4), "wood", verts=20))
    for z in (0.15, 0.65):
        parts.append(torus(f"hoop{z}", 0.305, 0.02, (-0.6, -w / 2 - 0.5, z), "iron", axis="Z", seg=24))
    parts.append(cyl("barrel_coal", 0.27, 0.06, (-0.6, -w / 2 - 0.5, 0.78), "coal", verts=20))
    join("ShopKiosk", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "shop_kiosk.glb"), 1024)


def build_sign():
    B.clear_scene()
    parts = []
    for s in (-1.7, 1.7):
        parts.append(cyl(f"post{s}", 0.07, 3.2, (0, s, 1.6), "column_green", verts=12))
        parts.append(sphere(f"finial{s}", 0.1, (0, s, 3.25), "column_green", seg=12))
        parts.append(cyl(f"foot{s}", 0.14, 0.2, (0, s, 0.1), "column_green", verts=12, radius2=0.09))
    parts.append(box("frame", (0.08, 3.5, 0.95), (0, 0, 2.55), "column_green", 0.015))
    parts.append(box("board", (0.06, 3.3, 0.78), (-0.03, 0, 2.55), "board_cream", 0.01))
    join("StationSign", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "station_sign.glb"), 512)


def build_platform():
    """One 6 m platform section, a bench, a lamp post and the gravestone (see the module docstring)."""
    B.clear_scene()
    half = 3.0
    parts = [box("body", (4.0, half * 2, 1.55), (2.0, 0, -0.875), "platform_brick", 0.0)]
    # rounded stone coping along the edge, overhanging the brick face, in 1 m blocks
    for k in range(6):
        y = -half + 0.5 + k * 1.0
        parts.append(box(f"coping{k}", (0.7, 0.988, 0.14), (0.25, y, -0.04), "coping_stone", 0.03))
    parts.append(box("safety_line", (0.1, half * 2, 0.006), (0.5, 0, 0.031), "line_yellow", 0.0))
    # flagstones, 4 across and 8 along, two shades, set a hair apart
    rng = B.random.Random(11)
    w, l = (4.0 - 0.6) / 4, half * 2 / 8
    for i in range(4):
        for j in range(8):
            x = 0.6 + w * (i + 0.5)
            y = -half + l * (j + 0.5)
            m = "flagstone_dark" if rng.random() < 0.3 else "flagstone"
            parts.append(box(f"flag{i}_{j}", (w - 0.014, l - 0.014, 0.1), (x, y, -0.05 + rng.uniform(-0.004, 0.003)), m, 0.008))
    join("PlatformSection", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "platform_section.glb"), 2048, repack=True)

    B.clear_scene()
    parts = []
    for j in range(3):
        parts.append(box(f"seat{j}", (0.14, 1.8, 0.05), (-0.16 + j * 0.16, 0, 0.48), "wood", 0.006))
    for j in range(2):
        parts.append(box(f"back{j}", (0.05, 1.8, 0.14), (0.27, 0, 0.7 + j * 0.2), "wood", 0.006, rot=(0, math.radians(-12), 0)))
    for s in (-0.75, 0.75):
        parts.append(box(f"leg{s}", (0.5, 0.06, 0.06), (0.0, s, 0.25), "iron", 0.006, rot=(0, math.radians(30), 0)))
        parts.append(box(f"legb{s}", (0.06, 0.06, 0.95), (0.27, s, 0.5), "iron", 0.006))
        parts.append(box(f"arm{s}", (0.42, 0.05, 0.04), (0.05, s, 0.68), "iron", 0.006))
        parts.append(sphere(f"knob{s}", 0.035, (-0.16, s, 0.69), "iron", seg=10))
    join("StationBench", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "station_bench.glb"), 512)

    B.clear_scene()
    parts = [cyl("lpost", 0.06, 3.0, (0, 0, 1.5), "column_green", verts=12),
             cyl("lbase", 0.14, 0.32, (0, 0, 0.16), "column_green", verts=12, radius2=0.08),
             torus("lring", 0.075, 0.018, (0, 0, 2.2), "column_green", axis="Z", seg=16),
             rod("ladder_bar", (0, -0.25, 2.75), (0, 0.25, 2.75), 0.015, "column_green", 8),
             box("lcase", (0.28, 0.28, 0.36), (0, 0, 3.17), "black_paint", 0.02),
             box("lglass", (0.22, 0.29, 0.26), (0, 0, 3.17), "lamp", 0.01),
             cyl("lroof", 0.24, 0.16, (0, 0, 3.43), "black_paint", verts=4, radius2=0.03, rot=(0, 0, math.pi / 4)),
             sphere("lfinial", 0.04, (0, 0, 3.53), "black_paint", seg=10)]
    join("StationLamp", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "station_lamp.glb"), 512)

    B.clear_scene()
    parts = [box("plinth", (0.5, 0.95, 0.14), (0, 0, 0.07), "headstone", 0.02),
             box("stone", (0.16, 0.7, 0.8), (0, 0, 0.54), "headstone", 0.025),
             cyl("stone_top", 0.35, 0.16, (0, 0, 0.94), "headstone", axis="X", verts=28),
             box("cross_v", (0.02, 0.07, 0.36), (-0.081, 0, 0.66), "flagstone_dark", 0.004),
             box("cross_h", (0.02, 0.24, 0.07), (-0.081, 0, 0.74), "flagstone_dark", 0.004),
             torus("wreath", 0.13, 0.035, (-0.2, 0.12, 0.16), "moss", axis="Z", seg=18)]
    for k in range(3):  # moss in the plinth corners
        parts.append(sphere(f"moss{k}", 0.06, (-0.2 + k * 0.2, -0.42, 0.13), "moss", scale=(1.4, 1, 0.5), seg=10))
    join("Gravestone", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "gravestone.glb"), 512)


def build_come_along():
    B.clear_scene()
    # ratchet puller held in the right hand: body along Y, the pump handle reaches forward (+Y = Godot -Z) and up
    parts = [box("body", (0.07, 0.2, 0.09), (0, 0, 0), "winch_red", 0.012),
             cyl("drum", 0.055, 0.1, (0, -0.02, 0), "steel", axis="X", verts=20),
             cyl("ratchet", 0.065, 0.02, (0.06, -0.02, 0), "iron", axis="X", verts=16),
             box("pawl", (0.02, 0.06, 0.02), (0.06, -0.08, 0.05), "steel", 0.003),
             rod("handle", (0, 0.0, 0.03), (0, 0.36, 0.2), 0.014, "winch_red", 10),
             cyl("grip", 0.022, 0.12, (0, 0.33, 0.18), "rubber", axis="Y", verts=12, rot=(math.radians(-62), 0, 0))]
    for s in (-1, 1):
        parts.append(box(f"plate{s}", (0.012, 0.22, 0.11), (s * 0.04, 0, 0), "steel", 0.003))
    # chain links back to a hook, and a hook at the front
    for k in range(4):
        parts.append(torus(f"link{k}", 0.018, 0.005, (0, -0.13 - k * 0.03, -0.02), "steel", axis="X" if k % 2 else "Y", seg=12))
    for y, name in ((-0.27, "hook_b"), (0.12, "hook_f")):
        parts.append(torus(name, 0.035, 0.009, (0, y, -0.06), "iron", axis="X", seg=16))
        parts.append(box(name + "_latch", (0.006, 0.05, 0.006), (0, y, -0.03), "steel", 0.001))
    join("ComeAlong", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "come_along.glb"), 512)


def build_arm():
    B.clear_scene()
    # chunky leather work glove: palm block, four curled fingers, thumb, a cuff; then the jacket sleeve.
    # Hand at the origin (palm facing down, fingers curl forward along +Y), forearm along -Y.
    parts = [box("palm", (0.1, 0.11, 0.05), (0, 0.0, 0), "glove", 0.02)]
    for k in range(4):
        x = -0.036 + k * 0.024
        length = 0.05 if k in (1, 2) else 0.044
        parts.append(box(f"f1_{k}", (0.022, length, 0.024), (x, 0.055 + length / 2, 0.0), "glove", 0.009))
        parts.append(box(f"f2_{k}", (0.021, 0.04, 0.022), (x, 0.06 + length, -0.022), "glove", 0.009,
                         rot=(math.radians(-70), 0, 0)))
    parts.append(box("thumb1", (0.026, 0.05, 0.026), (-0.06, 0.02, -0.01), "glove", 0.01, rot=(0, 0, math.radians(35))))
    parts.append(box("thumb2", (0.024, 0.04, 0.024), (-0.072, 0.055, -0.02), "glove", 0.01, rot=(math.radians(-30), 0, math.radians(20))))
    parts.append(box("seam", (0.09, 0.006, 0.052), (0, 0.035, 0), "leather", 0.002))
    parts.append(cyl("cuff", 0.058, 0.08, (0, -0.07, -0.005), "glove", axis="Y", verts=20, radius2=0.064))
    parts.append(torus("cuff_rim", 0.062, 0.008, (0, -0.11, -0.005), "leather", axis="Y", seg=20))
    # forearm in the jacket sleeve, and a rolled-up turn-back at the wrist
    parts.append(cyl("sleeve", 0.066, 0.36, (0, -0.3, -0.03), "jacket", axis="Y", verts=20, radius2=0.075))
    parts.append(torus("turnback", 0.07, 0.018, (0, -0.14, -0.02), "jacket", axis="Y", seg=20))
    parts.append(box("patch", (0.05, 0.12, 0.02), (0, -0.33, 0.045), "leather", 0.006))
    join("Arm", parts, origin=(0, 0, 0))
    B.bake_and_export(os.path.join(OUT, "arm.glb"), 512)


if __name__ == "__main__":
    if ONLY is None or "station" in ONLY:
        build_shelter()
    if ONLY is None or "kiosk" in ONLY:
        build_kiosk()
    if ONLY is None or "sign" in ONLY:
        build_sign()
    if ONLY is None or "platform" in ONLY:
        build_platform()
    if ONLY is None or "tools" in ONLY:
        build_come_along()
    if ONLY is None or "arm" in ONLY:
        build_arm()
    print("done")
