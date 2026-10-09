"""Builds the models and tiling ground textures of the quest map "The Mountain" (GDD 7) with baked textures.

Run headless:
    blender --background --python blender/scripts/build_mountain.py -- <repo_root> [only=rocks,camp,plants,items,tex]
Models go to assets/models/quest/<name>.glb (one mesh, procedural wear baked into one texture, like build_assets.py),
tiling ground textures to assets/textures/quest/<name>.png (4D noise on a torus, so they repeat without seams).
Origin = ground contact point at the base unless noted. Blender -Y (front) becomes Godot +Z.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import build_assets as A  # noqa: E402
import build_nature as N  # noqa: E402

OUT = os.path.join(A.ROOT, "assets", "models", "quest")
OUT_TEX = os.path.join(A.ROOT, "assets", "textures", "quest")
os.makedirs(OUT, exist_ok=True)
os.makedirs(OUT_TEX, exist_ok=True)

# extra materials for the mountain (same kinds as build_assets.MATS)
A.MATS.update({
    "granite": ("rock", (0.27, 0.25, 0.23), 0.0, 0.9),
    "dark_rock": ("rock", (0.15, 0.14, 0.13), 0.0, 0.9),
    "jungle_rock": ("rock", (0.2, 0.19, 0.15), 0.0, 0.9),
    "palm_bark": ("wood", (0.33, 0.25, 0.16), 0.0, 0.95),
    "palm_leaf": ("foliage", (0.12, 0.3, 0.07), 0.0, 0.8),
    "jungle_leaf": ("foliage", (0.06, 0.24, 0.06), 0.0, 0.8),
    "fern_leaf": ("foliage", (0.1, 0.3, 0.08), 0.0, 0.8),
    "vine": ("foliage", (0.08, 0.2, 0.05), 0.0, 0.85),
    "ash": ("plain", (0.12, 0.11, 0.1), 0.0, 0.95),
    "ember": ("lamp", (1.0, 0.35, 0.05), 0.0, 0.4),
    "tent_orange": ("canvas", (0.75, 0.3, 0.08), 0.0, 0.85),
    "tent_teal": ("canvas", (0.12, 0.4, 0.4), 0.0, 0.85),
    "wrapper": ("enamel", (0.85, 0.55, 0.08), 0.1, 0.4),
    "wrapper_red": ("enamel", (0.6, 0.08, 0.05), 0.1, 0.4),
    "flag_red": ("canvas", (0.65, 0.07, 0.05), 0.0, 0.85),
    "flag_yellow": ("canvas", (0.85, 0.65, 0.1), 0.0, 0.85),
    "flag_blue": ("canvas", (0.1, 0.25, 0.6), 0.0, 0.85),
})


SAMPLES = int(next((x.split("=", 1)[1] for x in sys.argv if x.startswith("samples=")), "32"))
FORCE = "force" in sys.argv


def bake_and_export(path, size=2048):
    """build_assets.bake_and_export with SAMPLES bake samples (these models are big and seen from afar), skipping
    models that already exist unless "force" is given."""
    if os.path.exists(path) and not FORCE:
        print("exists, skipped:", path)
        return
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        A.apply_all(o)
    # one shared UV atlas for all objects of this model
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")

    img = bpy.data.images.new(os.path.splitext(os.path.basename(path))[0] + "_albedo", size, size)
    used = {s.material for o in objs for s in o.material_slots if s.material}
    for m in used:
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        tex.name = "BAKE_TARGET"
        nt.nodes.active = tex
        emit = nt.nodes.new("ShaderNodeEmission")
        emit.name = "BAKE_EMIT"
        nt.links.new(nt.nodes["COLOR_OUT"].outputs[0] if "COLOR_OUT" in nt.nodes else nt.nodes["Principled BSDF"].inputs[0], emit.inputs[0])
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(emit.outputs[0], out.inputs["Surface"])

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 6
    bpy.ops.object.bake(type="EMIT")
    img.pack()

    # rebuild simple game materials: baked colour + the original metal / roughness
    for m in used:
        nt = m.node_tree
        kind = m.get("kind", "plain")
        bsdf_old = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        metal = bsdf_old.inputs["Metallic"].default_value
        rough = bsdf_old.inputs["Roughness"].default_value
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = img
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if kind == "lamp":
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 4.0
        nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    print("exported", path)


def rock_blob(name, size, loc, material, scale=(1, 1, 1), seed=1, detail=0.3):
    random.seed(seed)
    r = N.ico(name, size, loc, material, 3, scale=scale)
    N.displace(r, size * detail, 0.8, "VORONOI")
    N.displace(r, size * detail * 0.35, 0.25)
    return r


# --- Rocks with collision in the game (hand-placed on the routes) -----------------------------

def cliff_wall():
    """A rough strata rock face 12 m wide, 14 m tall, 4 m deep; the climbing face looks to -Y (Godot +Z)."""
    A.clear_scene()
    random.seed(41)
    parts = []
    z = 0.0
    while z < 14.0:
        h = random.uniform(1.4, 2.6)
        w = 12.0 + random.uniform(-0.8, 0.8)
        d = 4.0 + random.uniform(-0.3, 0.5)
        b = A.box(f"layer{len(parts)}", (w, d, h), (random.uniform(-0.3, 0.3), random.uniform(-0.25, 0.25), z + h / 2), "granite", 0.0)
        N.displace(b, 0.45, 0.9, "VORONOI", subdiv=3)
        parts.append(b)
        z += h * 0.95
    A.join("CliffWall", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "cliff_wall.glb"), 2048)


def rock_pillar():
    """A free-standing stone column (6 m across, 28 m tall, flat-ish top) for the rope bridges over the gorge."""
    A.clear_scene()
    random.seed(42)
    parts = []
    z = 0.0
    while z < 28.0:
        h = random.uniform(2.0, 3.4)
        r = 3.0 + random.uniform(-0.3, 0.4) - z * 0.012
        c = A.cyl(f"drum{len(parts)}", r, h, (random.uniform(-0.2, 0.2), random.uniform(-0.2, 0.2), z + h / 2), "jungle_rock", verts=10, bevel=0.0)
        N.displace(c, 0.35, 0.8, "VORONOI", subdiv=2)
        parts.append(c)
        z += h * 0.96
    top = A.cyl("cap", 3.1, 0.6, (0, 0, 28.0), "jungle_rock", verts=12, bevel=0.0)
    N.displace(top, 0.12, 0.6, subdiv=1)
    parts.append(top)
    A.join("RockPillar", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "rock_pillar.glb"), 2048)


def overhang():
    """A rock roof: 10 m wide, sticking out 4 m to -Y, 2.4 m thick. Origin at the back top edge (where it meets the wall)."""
    A.clear_scene()
    random.seed(43)
    parts = []
    for k in range(3):
        w = 10.0 - k * 1.5
        b = A.box(f"slab{k}", (w, 5.0 - k * 0.6, 1.0), (random.uniform(-0.3, 0.3), -2.0 + k * 0.4, -0.5 - k * 0.75), "dark_rock", 0.0)
        N.displace(b, 0.35, 0.7, "VORONOI", subdiv=3)
        parts.append(b)
    A.join("Overhang", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "overhang.glb"), 1024)


def chimney_wall():
    """One side of a chimney: a thin rock fin 1.2 m thick, 5 m deep (along Y), 15 m tall."""
    A.clear_scene()
    random.seed(44)
    parts = []
    z = 0.0
    while z < 15.0:
        h = random.uniform(1.6, 2.6)
        b = A.box(f"fin{len(parts)}", (1.2 + random.uniform(-0.1, 0.2), 5.0 + random.uniform(-0.3, 0.3), h), (0, random.uniform(-0.2, 0.2), z + h / 2), "granite", 0.0)
        N.displace(b, 0.18, 0.7, "VORONOI", subdiv=3)
        parts.append(b)
        z += h * 0.95
    A.join("ChimneyWall", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "chimney_wall.glb"), 1024)


def scree_rocks():
    """Decoration (no collision): a cluster of granite rocks, and the same with a snow cap."""
    for name, snow in (("rock_cluster", False), ("rock_snow", True)):
        A.clear_scene()
        parts = [rock_blob("r0", 1.4, (0, 0, 0.6), "granite", (1.3, 1.0, 0.8), 3),
                 rock_blob("r1", 0.8, (1.5, 0.6, 0.35), "granite", (1.1, 1.0, 0.8), 4),
                 rock_blob("r2", 0.6, (-1.3, -0.5, 0.25), "granite", (1.0, 1.2, 0.7), 5)]
        if snow:
            for k, (x, y, z, s) in enumerate(((0, 0, 1.45, 1.25), (1.5, 0.6, 0.9, 0.65), (-1.3, -0.5, 0.65, 0.45))):
                cap = N.ico(f"snow{k}", s, (x, y, z), "snow", 3, scale=(1.2, 1.1, 0.35))
                N.displace(cap, 0.08, 0.3)
                parts.append(cap)
        A.join(name, parts, origin=(0, 0, 0))
        bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


# --- Plants ------------------------------------------------------------------------------

def palm():
    A.clear_scene()
    random.seed(51)
    parts = []
    prev = (0, 0, -0.3)
    segs = 9
    for i in range(segs):
        t = (i + 1) / segs
        p = (math.sin(t * 1.4) * 1.6, 0.0, t * 9.0)
        c = N.cone_between(f"seg{i}", prev, p, 0.28 - t * 0.08, 0.24 - t * 0.08, "palm_bark", 10)
        parts.append(c)
        prev = p
    for k in range(8):
        a = k * math.tau / 8 + random.uniform(-0.2, 0.2)
        tip = (prev[0] + math.cos(a) * 3.6, prev[1] + math.sin(a) * 3.6, prev[2] - 1.4)
        mid = (prev[0] + math.cos(a) * 1.8, prev[1] + math.sin(a) * 1.8, prev[2] + 0.5)
        for a0, b0, w in ((prev, mid, 0.55), (mid, tip, 0.45)):
            leaf = N.cone_between(f"leaf{k}{w}", a0, b0, w, 0.05, "palm_leaf", 4)
            leaf.scale = (1.0, 1.0, 1.0)
            parts.append(leaf)
    for k in range(3):
        parts.append(N.ico(f"nut{k}", 0.2, (prev[0] + math.cos(k * 2.1) * 0.3, math.sin(k * 2.1) * 0.3, prev[2] - 0.3), "wood_dark", 2))
    A.join("Palm", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "palm.glb"), 1024)


def jungle_tree():
    """A tall rainforest tree: buttress roots, a straight trunk, an umbrella crown and hanging vines."""
    A.clear_scene()
    random.seed(52)
    parts = [N.cone_between("trunk", (0, 0, -0.3), (0, 0, 13.0), 0.6, 0.35, "bark", 12)]
    N.displace(parts[0], 0.08, 0.3)
    for k in range(5):
        a = k * math.tau / 5 + 0.3
        root = A.box(f"buttress{k}", (2.0, 0.18, 2.2), (math.cos(a) * 0.9, math.sin(a) * 0.9, 0.7), "bark", 0.0, rot=(0, 0, a))
        parts.append(root)
    for k in range(7):
        a = k * math.tau / 7 + random.uniform(-0.2, 0.2)
        d = random.uniform(1.6, 3.2)
        c = N.ico(f"crown{k}", random.uniform(1.6, 2.4), (math.cos(a) * d, math.sin(a) * d, 13.0 + random.uniform(-0.4, 0.8)), "jungle_leaf", 2, scale=(1.3, 1.3, 0.55))
        N.displace(c, 0.35, 0.4, subdiv=1)
        parts.append(c)
        if k % 2 == 0:
            vx, vy = math.cos(a) * d * 1.2, math.sin(a) * d * 1.2
            parts.append(A.rod(f"vine{k}", (vx, vy, 12.6), (vx * 1.05, vy * 1.05, 6.0 + random.uniform(-1, 1)), 0.05, "vine", 6))
    A.join("JungleTree", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "jungle_tree.glb"), 1024)


def fern():
    A.clear_scene()
    random.seed(53)
    parts = []
    for k in range(9):
        a = k * math.tau / 9 + random.uniform(-0.2, 0.2)
        tip = (math.cos(a) * 1.3, math.sin(a) * 1.3, 0.45)
        mid = (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.75)
        parts.append(N.cone_between(f"f{k}a", (0, 0, 0.05), mid, 0.22, 0.18, "fern_leaf", 4))
        parts.append(N.cone_between(f"f{k}b", mid, tip, 0.18, 0.02, "fern_leaf", 4))
    A.join("Fern", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "fern.glb"), 512)


# --- Camp, items, portal --------------------------------------------------------------------

def campfire():
    """A ring of stones around crossed logs and glowing embers (the flames are added in Godot)."""
    A.clear_scene()
    parts = []
    for k in range(10):
        a = k * math.tau / 10
        parts.append(A.lump(f"stone{k}", 0.2, (math.cos(a) * 0.75, math.sin(a) * 0.75, 0.12), "granite", (1.3, 1.0, 0.8), 0.25, 1, 60 + k))
    parts.append(A.cyl("ash", 0.62, 0.04, (0, 0, 0.02), "ash", verts=20, bevel=0.0))
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        parts.append(A.rod(f"log{k}", (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.06), (math.cos(a) * 0.05, math.sin(a) * 0.05, 0.45), 0.07, "bark", 8))
    for k in range(7):
        a = k * 2.4
        parts.append(A.lump(f"ember{k}", 0.07, (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.06), "ember", (1.2, 1.0, 0.6), 0.3, 1, 80 + k))
    # a log bench beside the fire
    parts.append(A.cyl("bench", 0.2, 1.8, (0, 1.7, 0.2), "bark", axis="X", verts=12, bevel=0.0))
    A.join("Campfire", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "campfire.glb"), 1024)


def tent():
    """An A-frame canvas tent with a ridge pole and guy lines (base camp)."""
    A.clear_scene()
    parts = []
    for sx in (-1, 1):
        parts.append(A.box(f"side{sx}", (0.04, 2.6, 1.75), (sx * 0.62, 0, 0.72), "tent_orange", 0.01, rot=(0, sx * math.radians(-35), 0)))
    parts.append(A.box("floor", (2.1, 2.7, 0.03), (0, 0, 0.015), "canvas", 0.0))
    parts.append(A.cyl("ridge", 0.03, 2.8, (0, 0, 1.43), "wood_dark", axis="Y", verts=8))
    for sy in (-1.3, 1.3):
        parts.append(A.cyl(f"pole{sy}", 0.03, 1.45, (0, sy, 0.72), "wood_dark", verts=8))
        for sx in (-1, 1):
            parts.append(A.rod(f"guy{sy}{sx}", (0, sy, 1.43), (sx * 1.4, sy * 1.5, 0.0), 0.008, "rope", 4))
    parts.append(A.box("door", (1.0, 0.03, 1.2), (0, -1.31, 0.5), "tent_teal", 0.0))
    A.join("Tent", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "tent.glb"), 1024)


def items():
    # rope coil (pickup: a rope for the rope ladders)
    A.clear_scene()
    parts = []
    for k in range(5):
        parts.append(A.torus(f"loop{k}", 0.28 - k * 0.012, 0.035, (0, 0, 0.04 + k * 0.06), "rope", axis="Z", seg=28))
    parts.append(A.box("tie", (0.08, 0.6, 0.06), (0, 0, 0.18), "rope", 0.02))
    A.join("RopeCoil", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "rope_coil.glb"), 512)

    # energy snack: two wrapped bars and a small cloth pouch
    A.clear_scene()
    parts = [A.box("bar1", (0.32, 0.1, 0.04), (0, 0, 0.02), "wrapper", 0.01),
             A.box("bar1_band", (0.08, 0.104, 0.044), (0.06, 0, 0.02), "wrapper_red", 0.004),
             A.box("bar2", (0.32, 0.1, 0.04), (0.02, 0.05, 0.06), "wrapper", 0.01, rot=(0, 0, 0.5)),
             A.box("bar2_band", (0.08, 0.104, 0.044), (0.06, 0.07, 0.06), "wrapper_red", 0.004, rot=(0, 0, 0.5)),
             N.ico("pouch", 0.12, (-0.18, -0.08, 0.1), "canvas", 2, scale=(1.0, 1.0, 1.1)),
             A.cyl("pouch_tie", 0.05, 0.03, (-0.18, -0.08, 0.22), "rope", verts=10)]
    A.join("Snack", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "snack.glb"), 512)

    # piton anchor: an iron plate bolted into the rock with a big ring (the rope ladder hangs from it)
    A.clear_scene()
    parts = [A.box("plate", (0.5, 0.5, 0.06), (0, 0, 0.03), "iron", 0.01)]
    for x in (-0.18, 0.18):
        for y in (-0.18, 0.18):
            parts.append(A.cyl(f"bolt{x}{y}", 0.035, 0.05, (x, y, 0.08), "steel", verts=6))
    parts.append(A.cyl("eye", 0.06, 0.18, (0, 0, 0.12), "iron", verts=10))
    parts.append(A.torus("ring", 0.16, 0.03, (0, 0, 0.36), "steel", axis="X", seg=20))
    A.join("Anchor", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "anchor.glb"), 512)

    # bridge plank: one weathered board of a rope bridge (instanced in Godot)
    A.clear_scene()
    parts = [A.box("board", (2.0, 0.34, 0.07), (0, 0, 0), "wood_grey", 0.01)]
    for x in (-0.85, 0.85):
        parts.append(A.box(f"lash{x}", (0.06, 0.36, 0.09), (x, 0, 0), "rope", 0.01))
    A.join("BridgePlank", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "bridge_plank.glb"), 512)

    # summit cairn with a flag pole and three faded pennants
    A.clear_scene()
    parts = []
    z = 0.0
    for k in range(6):
        s = 0.9 - k * 0.12
        parts.append(A.lump(f"stone{k}", s * 0.6, (random.uniform(-0.1, 0.1), random.uniform(-0.1, 0.1), z + s * 0.3), "granite", (1.3, 1.1, 0.6), 0.2, 1, 90 + k))
        z += s * 0.5
    parts.append(A.cyl("pole", 0.05, 4.2, (0, 0, z + 2.0), "wood_dark", verts=8))
    for k, m in enumerate(("flag_red", "flag_yellow", "flag_blue")):
        parts.append(A.box(f"flag{k}", (0.9, 0.02, 0.45), (0.47, 0, z + 3.8 - k * 0.55), m, 0.0, rot=(0, math.radians(4 * k), 0)))
    A.join("Cairn", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "cairn.glb"), 1024)


def portal():
    """The trailhead gate of a quest map: two log posts, a carved crossbeam with a sign board, hanging lanterns,
    a string of pennants, and a stone step. 4.4 m wide, 4.6 m tall; you walk through it along Y."""
    A.clear_scene()
    parts = []
    for sx in (-1, 1):
        parts.append(A.cyl(f"post{sx}", 0.22, 4.4, (sx * 2.0, 0, 2.2), "bark", verts=12, bevel=0.0))
        parts.append(A.lump(f"foot{sx}", 0.5, (sx * 2.0, 0, 0.15), "granite", (1.2, 1.2, 0.6), 0.2, 1, 70 + sx))
        parts.append(A.rod(f"brace{sx}", (sx * 2.0, 0, 3.4), (sx * 1.3, 0, 4.1), 0.09, "bark", 8))
        parts.append(A.box(f"lantern{sx}", (0.22, 0.22, 0.3), (sx * 1.55, -0.3, 3.4), "lamp", 0.02))
        parts.append(A.box(f"lantern_cap{sx}", (0.28, 0.28, 0.06), (sx * 1.55, -0.3, 3.58), "iron", 0.01))
        parts.append(A.rod(f"lantern_hook{sx}", (sx * 1.55, -0.3, 3.6), (sx * 1.55, 0, 4.05), 0.015, "iron", 6))
    parts.append(A.cyl("beam", 0.24, 5.0, (0, 0, 4.25), "bark", axis="X", verts=12, bevel=0.0))
    parts.append(A.box("sign", (2.6, 0.12, 0.7), (0, -0.25, 3.6), "wood", 0.02))
    for sx in (-1, 1):
        parts.append(A.rod(f"sign_rope{sx}", (sx * 1.1, -0.25, 3.95), (sx * 1.1, -0.1, 4.2), 0.02, "rope", 6))
    for k in range(9):
        t = k / 8.0
        x = -2.0 + 4.0 * t
        z = 4.0 - math.sin(t * math.pi) * 0.5
        m = ("flag_red", "flag_yellow", "flag_blue")[k % 3]
        parts.append(A.box(f"pennant{k}", (0.32, 0.02, 0.3), (x, 0.2, z - 0.18), m, 0.0, rot=(0, math.radians(8), 0)))
    parts.append(A.box("step", (3.6, 1.6, 0.18), (0, 0, 0.09), "granite", 0.03))
    A.join("Portal", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT, "portal.glb"), 1024)


# --- Tiling ground textures --------------------------------------------------------------------

def _torus_coords(nt, scale):
    """UV (0..1) -> a 4D point on a torus, so any 4D noise tiles seamlessly. Returns (vector xyz, w) sockets."""
    tc = A._n(nt, "ShaderNodeTexCoord").outputs["UV"]
    sep = A._n(nt, "ShaderNodeSeparateXYZ")
    nt.links.new(tc, sep.inputs[0])

    def m(op, a, b=None):
        n = A._n(nt, "ShaderNodeMath")
        n.operation = op
        if isinstance(a, (int, float)):
            n.inputs[0].default_value = a
        else:
            nt.links.new(a, n.inputs[0])
        if b is not None:
            if isinstance(b, (int, float)):
                n.inputs[1].default_value = b
            else:
                nt.links.new(b, n.inputs[1])
        return n.outputs[0]
    r = scale / math.tau
    au = m("MULTIPLY", sep.outputs["X"], math.tau)
    av = m("MULTIPLY", sep.outputs["Y"], math.tau)
    comb = A._n(nt, "ShaderNodeCombineXYZ")
    nt.links.new(m("MULTIPLY", m("COSINE", au), r), comb.inputs[0])
    nt.links.new(m("MULTIPLY", m("SINE", au), r), comb.inputs[1])
    nt.links.new(m("MULTIPLY", m("COSINE", av), r), comb.inputs[2])
    return comb.outputs[0], m("MULTIPLY", m("SINE", av), r)


def _noise4(nt, vec, w, scale, detail, kind="ShaderNodeTexNoise"):
    t = A._n(nt, kind)
    if kind == "ShaderNodeTexVoronoi":
        t.voronoi_dimensions = "4D"
    else:
        t.noise_dimensions = "4D"
    nt.links.new(vec, t.inputs["Vector"])
    nt.links.new(w, t.inputs["W"])
    t.inputs["Scale"].default_value = scale
    if "Detail" in t.inputs and kind != "ShaderNodeTexVoronoi":
        t.inputs["Detail"].default_value = detail
    return t


def bake_tile(name, build_color, size=1024):
    A.clear_scene()
    bpy.ops.mesh.primitive_plane_add(size=2.0)
    plane = bpy.context.active_object
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = A._n(nt, "ShaderNodeOutputMaterial")
    emit = A._n(nt, "ShaderNodeEmission")
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    vec, w = _torus_coords(nt, 1.0)
    nt.links.new(build_color(nt, vec, w), emit.inputs[0])
    plane.data.materials.append(m)
    img = bpy.data.images.new(name, size, size)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.nodes.active = tex
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 4
    scene.render.bake.margin = 0
    bpy.ops.object.bake(type="EMIT")
    img.filepath_raw = os.path.join(OUT_TEX, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    print("saved", img.filepath_raw)


def _rock_color(nt, vec, w):
    base = _noise4(nt, vec, w, 2.5, 10.0)
    base.inputs["Roughness"].default_value = 0.65
    col = A._mix(nt, (0.06, 0.055, 0.05), (0.32, 0.29, 0.26), A._ramp(nt, base.outputs["Fac"], 0.25, 0.75))
    mid = _noise4(nt, vec, w, 9.0, 8.0)
    col = A._mix(nt, col, (0.42, 0.38, 0.33), A._ramp(nt, mid.outputs["Fac"], 0.55, 0.8))
    vor = _noise4(nt, vec, w, 4.0, 0.0, "ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Randomness"].default_value = 1.0
    cracks = A._ramp(nt, vor.outputs["Distance"], 0.0, 0.025)
    col = A._mix(nt, (0.03, 0.028, 0.025), col, cracks)
    lichen = _noise4(nt, vec, w, 6.0, 6.0)
    col = A._mix(nt, col, (0.3, 0.32, 0.18), A._ramp(nt, lichen.outputs["Fac"], 0.68, 0.78))
    return col


def _ground_color(nt, vec, w):
    """Neutral, light earth-and-pebbles grain (the game tints it per biome with vertex colours)."""
    base = _noise4(nt, vec, w, 6.0, 6.0)
    col = A._mix(nt, (0.45, 0.43, 0.4), (0.85, 0.83, 0.79), A._ramp(nt, base.outputs["Fac"], 0.3, 0.7))
    vor = _noise4(nt, vec, w, 18.0, 0.0, "ShaderNodeTexVoronoi")
    pebbles = A._ramp(nt, vor.outputs["Distance"], 0.05, 0.25)
    col = A._mix(nt, (1.0, 0.98, 0.95), col, pebbles)
    fine = _noise4(nt, vec, w, 40.0, 3.0)
    return A._mix(nt, col, (0.55, 0.53, 0.5), A._ramp(nt, fine.outputs["Fac"], 0.6, 0.8))


def _snow_color(nt, vec, w):
    base = _noise4(nt, vec, w, 4.0, 5.0)
    col = A._mix(nt, (0.78, 0.82, 0.9), (0.97, 0.98, 1.0), A._ramp(nt, base.outputs["Fac"], 0.35, 0.65))
    sparkle = _noise4(nt, vec, w, 60.0, 1.0)
    return A._mix(nt, col, (1.0, 1.0, 1.0), A._ramp(nt, sparkle.outputs["Fac"], 0.7, 0.75))


if __name__ == "__main__":
    ONLY = A.ONLY
    if ONLY is None or "tex" in ONLY:
        bake_tile("rock_tile", _rock_color)
        bake_tile("ground_tile", _ground_color)
        bake_tile("snow_tile", _snow_color)
    if ONLY is None or "rocks" in ONLY:
        cliff_wall()
        rock_pillar()
        overhang()
        chimney_wall()
        scree_rocks()
    if ONLY is None or "plants" in ONLY:
        palm()
        jungle_tree()
        fern()
    if ONLY is None or "camp" in ONLY:
        campfire()
        tent()
        portal()
    if ONLY is None or "items" in ONLY:
        items()
    print("done")
