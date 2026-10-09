"""Renders a 128x128 transparent icon for every item, tool and resource → assets/icons/<id>.png

    blender --background --python blender/scripts/render_icons.py -- <repo_root> [only=key,wood]

Tools / repair items come from the exported .glb models; resources without a model are built here
with the same helpers and materials as build_assets.py.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import build_assets as A  # noqa: E402

OUT = os.path.join(A.ROOT, "assets", "icons")
os.makedirs(OUT, exist_ok=True)
PROPS = os.path.join(A.ROOT, "assets", "models", "props")

FROM_GLB = {
    "hammer": "hammer.glb", "wrench": "wrench.glb", "nail_gun": "nail_gun.glb", "welder": "welder_torch.glb",
    "wheel": "wheel.glb", "plank": "plank.glb", "rail": "rail.glb", "key": "gate_key.glb",
}


# food and the team-pool bolts (icons only): extra materials on top of build_assets.MATS
A.MATS.update({
    "bread": ("plain", (0.78, 0.52, 0.22), 0.0, 0.85),
    "crumb": ("plain", (0.93, 0.84, 0.62), 0.0, 0.9),
    "lettuce": ("plain", (0.25, 0.6, 0.12), 0.0, 0.7),
    "cheese": ("plain", (0.98, 0.75, 0.15), 0.0, 0.6),
    "tomato": ("plain", (0.8, 0.12, 0.08), 0.0, 0.4),
    "apple_red": ("plain", (0.75, 0.06, 0.05), 0.0, 0.35),
    "leaf": ("plain", (0.2, 0.5, 0.1), 0.0, 0.7),
    "stem": ("plain", (0.3, 0.18, 0.08), 0.0, 0.8),
    "tin": ("iron", (0.62, 0.63, 0.66), 0.95, 0.3),
    "label_red": ("plain", (0.75, 0.2, 0.1), 0.0, 0.6),
    "beans": ("plain", (0.62, 0.25, 0.08), 0.0, 0.45),
    "bowl": ("plain", (0.88, 0.85, 0.78), 0.0, 0.35),
    "soup": ("plain", (0.85, 0.42, 0.1), 0.0, 0.25),
    "mug": ("plain", (0.2, 0.45, 0.7), 0.0, 0.35),
    "coffee": ("plain", (0.18, 0.09, 0.04), 0.0, 0.2),
    "choc": ("plain", (0.3, 0.15, 0.06), 0.0, 0.45),
    "wrapper": ("plain", (0.8, 0.12, 0.2), 0.0, 0.5),
    "foil": ("iron", (0.8, 0.8, 0.82), 1.0, 0.25),
})


def build_food(item):
    parts = []
    if item == "sandwich":
        # a wedge: bread, lettuce, cheese, tomato, bread
        parts += [A.box("bread_lo", (0.7, 0.5, 0.08), (0, 0, 0), "bread", 0.03),
                  A.box("lettuce", (0.74, 0.54, 0.03), (0, 0, 0.055), "lettuce", 0.01),
                  A.box("cheese", (0.66, 0.46, 0.04), (0.02, 0, 0.09), "cheese", 0.005),
                  A.cyl("tom1", 0.12, 0.03, (-0.15, 0.05, 0.12), "tomato", verts=16),
                  A.cyl("tom2", 0.12, 0.03, (0.16, -0.05, 0.12), "tomato", verts=16),
                  A.box("bread_hi", (0.7, 0.5, 0.1), (0, 0, 0.19), "bread", 0.04),
                  A.box("crumb", (0.64, 0.44, 0.02), (0, 0, 0.245), "crumb", 0.005)]
    elif item == "apple":
        parts += [A.sphere("apple", 0.3, (0, 0, 0), "apple_red", scale=(1, 1, 0.9), seg=24),
                  A.cyl("stem", 0.02, 0.16, (0, 0, 0.3), "stem", verts=8),
                  A.sphere("leaf", 0.08, (0.08, 0, 0.32), "leaf", scale=(1.6, 0.6, 0.3), seg=12)]
    elif item == "beans":
        parts += [A.cyl("can", 0.22, 0.5, (0, 0, 0), "tin", verts=28),
                  A.cyl("label", 0.225, 0.3, (0, 0, 0), "label_red", verts=28),
                  A.torus("rim", 0.21, 0.015, (0, 0, 0.25), "tin", axis="Z")]
        for k, (x, y) in enumerate([(-0.07, 0.03), (0.05, -0.05), (0.06, 0.07), (-0.03, -0.09), (0.0, 0.0)]):
            parts.append(A.sphere(f"bean{k}", 0.045, (x, y, 0.27), "beans", scale=(1.3, 0.8, 0.7), seg=10))
    elif item == "soup":
        parts += [A.cyl("bowl", 0.2, 0.3, (0, 0, 0), "bowl", verts=32, radius2=0.38),
                  A.cyl("soup", 0.34, 0.02, (0, 0, 0.155), "soup", verts=32),
                  A.rod("spoon", (0.05, 0.05, 0.1), (0.3, 0.25, 0.45), 0.02, "tin")]
    elif item == "coffee":
        parts += [A.cyl("mug", 0.2, 0.42, (0, 0, 0), "mug", verts=28),
                  A.cyl("coffee", 0.18, 0.02, (0, 0, 0.2), "coffee", verts=28),
                  A.torus("handle", 0.11, 0.035, (0.22, 0, 0.02), "mug", axis="Y")]
    elif item == "chocolate":
        parts += [A.box("bar", (0.7, 0.34, 0.07), (0, 0, 0), "choc", 0.02),
                  A.box("wrap", (0.42, 0.36, 0.09), (0.16, 0, 0), "wrapper", 0.01),
                  A.box("foil", (0.04, 0.36, 0.085), (-0.07, 0, 0), "foil", 0.005)]
        for k in range(2):
            for j in range(2):
                parts.append(A.box(f"sq{k}{j}", (0.1, 0.13, 0.03), (-0.27 + k * 0.12, -0.075 + j * 0.15, 0.045), "choc", 0.01))
    elif item == "bolts":
        for k, (x, y) in enumerate([(-0.15, 0.0), (0.15, 0.05), (0.0, -0.18)]):
            parts.append(A.cyl(f"head{k}", 0.1, 0.06, (x, y, 0.2), "steel", verts=6))
            parts.append(A.cyl(f"shank{k}", 0.04, 0.4, (x, y, 0.0), "steel", verts=12))
            parts.append(A.cyl(f"nut{k}", 0.08, 0.06, (x, y, -0.1), "iron", verts=6))
    return A.join(item, parts) if parts else None


def build_resource(item):
    """Small models for things that only exist as icons / pickups."""
    parts = []
    if item == "coal":
        import random
        random.seed(3)
        for k in range(9):
            parts.append(A.sphere(f"c{k}", random.uniform(0.12, 0.2), (random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25), random.uniform(0.0, 0.2)), "coal", seg=8))
    elif item == "wood":
        for k, (x, z) in enumerate([(-0.15, 0.0), (0.15, 0.0), (0.0, 0.25)]):
            parts.append(A.cyl(f"log{k}", 0.13, 0.9, (x, 0, z), "wood", axis="Y", verts=14))
            parts.append(A.cyl(f"end{k}", 0.12, 0.92, (x, 0, z), "wood_grey", axis="Y", verts=14))
        parts.append(A.torus("rope", 0.3, 0.02, (0, 0, 0.1), "canvas", axis="Y"))
    elif item == "scrap":
        parts += [A.box("plate", (0.5, 0.4, 0.04), (0, 0, 0), "rust", 0.01, rot=(0.2, 0.3, 0)),
                  A.cyl("pipe", 0.06, 0.6, (0.1, 0.05, 0.12), "iron", axis="X", verts=12),
                  A.torus("gear", 0.14, 0.04, (-0.15, 0.1, 0.15), "steel", axis="Y", seg=12)]
    elif item == "gold":
        parts += [A.sphere("nug1", 0.18, (0, 0, 0.1), "brass", scale=(1.3, 1, 0.8), seg=10),
                  A.sphere("nug2", 0.12, (0.2, 0.1, 0.05), "brass", seg=8),
                  A.sphere("nug3", 0.1, (-0.18, 0.12, 0.05), "brass", seg=8)]
    elif item == "nails":
        parts.append(A.box("box", (0.5, 0.35, 0.2), (0, 0, 0), "canvas", 0.01))
        for k in range(6):
            parts.append(A.cyl(f"nail{k}", 0.012, 0.3, (-0.18 + k * 0.07, 0, 0.18), "steel", verts=8, rot=(0.4 - k * 0.15, 0.2, 0)))
    elif item == "medkit":
        parts += [A.box("case", (0.6, 0.25, 0.45), (0, 0, 0), "cream_paint", 0.04),
                  A.box("cross_v", (0.08, 0.27, 0.28), (0, 0, 0), "buffer_red", 0.0),
                  A.box("cross_h", (0.28, 0.27, 0.08), (0, 0, 0), "buffer_red", 0.0),
                  A.box("handle", (0.25, 0.06, 0.06), (0, 0, 0.27), "rubber", 0.01)]
    elif item == "engine_oil":
        parts += [A.cyl("can", 0.2, 0.4, (0, 0, 0), "orange_paint", verts=24),
                  A.rod("spout", (0.0, 0.1, 0.18), (0.0, 0.45, 0.35), 0.025, "brass"),
                  A.torus("handle", 0.12, 0.02, (0, -0.12, 0.25), "iron", axis="X")]
    elif item == "grappler":
        parts.append(A.cyl("shaft", 0.03, 0.4, (0, 0, 0), "iron", verts=10))
        for k in range(3):
            a = k * 2 * math.pi / 3
            parts.append(A.rod(f"claw{k}", (0, 0, 0.15), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.32), 0.022, "iron"))
        parts.append(A.torus("rope", 0.14, 0.03, (0, 0, -0.25), "canvas", axis="Z"))
    elif item == "come_along":
        parts += [A.cyl("drum", 0.08, 0.25, (0, 0, 0), "buffer_red", axis="X", verts=16),
                  A.box("handle", (0.05, 0.06, 0.6), (0, 0.05, 0.3), "buffer_red", 0.01, rot=(0.5, 0, 0)),
                  A.torus("hook1", 0.07, 0.02, (0, -0.35, 0), "buffer_red", axis="X"),
                  A.torus("hook2", 0.07, 0.02, (0, 0.35, 0), "buffer_red", axis="X"),
                  A.rod("chain", (0, -0.3, 0), (0, 0.3, 0), 0.015, "steel")]
    elif item == "panel":
        for k in range(5):
            parts.append(A.box(f"b{k}", (0.15, 0.04, 0.8), (-0.32 + k * 0.16, 0, 0), "van_brown", 0.005))
        parts.append(A.box("strap", (0.85, 0.05, 0.06), (0, 0.02, 0.25), "iron", 0.005))
    elif item in ("sandwich", "apple", "beans", "soup", "coffee", "chocolate", "bolts"):
        return build_food(item)
    elif item == "nail_gun_ammo":
        pass
    return A.join(item, parts) if parts else None


def setup_scene():
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 24
    s.cycles.use_denoising = True
    s.render.film_transparent = True
    s.render.resolution_x = 128
    s.render.resolution_y = 128
    s.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    s.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.82, 0.85, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(35)))
    bpy.context.active_object.data.energy = 3.0


def frame_and_render(objs, path):
    # bounding box of everything → camera at a 3/4 angle that fits it
    pts = [o.matrix_world @ Vector(c) for o in objs if o.type == "MESH" for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (lo + hi) / 2
    size = (hi - lo).length
    bpy.ops.object.camera_add(location=center + Vector((1.0, -1.3, 0.9)).normalized() * size * 1.6)
    cam = bpy.context.active_object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size * 1.05
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("icon", path)


def main():
    items = list(FROM_GLB) + ["coal", "wood", "scrap", "gold", "nails", "medkit", "engine_oil", "grappler", "come_along", "panel",
             "sandwich", "apple", "beans", "soup", "coffee", "chocolate", "bolts"]
    if A.ONLY is not None:
        items = [i for i in items if i in A.ONLY]
    for item in items:
        A.clear_scene()
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete()
        setup_scene()
        if item in FROM_GLB:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS, FROM_GLB[item]))
            objs = [o for o in bpy.data.objects if o not in before]
        else:
            obj = build_resource(item)
            objs = [obj]
        frame_and_render(objs, os.path.join(OUT, f"{item}.png"))


main()
