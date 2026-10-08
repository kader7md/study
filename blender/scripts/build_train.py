"""Builds the Trust Issues train and repair-item models in Blender and exports them as .glb.

Run headless:
    blender --background --python blender/scripts/build_train.py -- <repo_root>
Or open Blender → Scripting tab → open this file → Run Script (exports next to the repo).

Style: chunky, rounded, bright cartoon (RV There Yet look). Every part has a bevel.
Axes: Blender +Y = front of the train (becomes -Z in Godot), Z up. The rail top is at Z = 0.
Train deck (walkable floor) top is at Z = 1.35, matching Train.FLOOR_HEIGHT in train.gd.
"""
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = argv[0] if argv else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_TRAIN = os.path.join(ROOT, "assets", "models", "train")
OUT_PROPS = os.path.join(ROOT, "assets", "models", "props")
os.makedirs(OUT_TRAIN, exist_ok=True)
os.makedirs(OUT_PROPS, exist_ok=True)

FLOOR = 1.35

# --- Palette -------------------------------------------------------------------
PALETTE = {
    "red": (0.62, 0.11, 0.08), "dark_red": (0.35, 0.06, 0.05), "black": (0.05, 0.05, 0.06),
    "iron": (0.22, 0.23, 0.25), "gold": (0.95, 0.68, 0.18), "cream": (0.93, 0.86, 0.68),
    "wood": (0.55, 0.33, 0.16), "wood_dark": (0.36, 0.2, 0.1), "green": (0.18, 0.42, 0.27),
    "rust": (0.6, 0.27, 0.14), "steel": (0.62, 0.64, 0.68), "glass": (0.6, 0.85, 0.95),
    "lamp": (1.0, 0.9, 0.5), "orange": (0.95, 0.45, 0.08), "blue": (0.15, 0.35, 0.65),
}
_mats = {}


def mat(name, rough=0.7, metal=0.0, emit=0.0):
    key = (name, rough, metal, emit)
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new(f"{name}")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    color = PALETTE[name]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    _mats[key] = m
    return m


# --- Primitive helpers ---------------------------------------------------------

def _finish(obj, name, material, bevel):
    obj.name = name
    obj.data.materials.append(material)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.modifiers.new("Smooth", "WEIGHTED_NORMAL").keep_sharp = True
    return obj


def box(name, size, loc, material, bevel=0.04, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, bevel)


def cyl(name, radius, depth, loc, material, axis="Z", verts=32, bevel=0.02, radius2=None):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=rot)
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, name, material, bevel)


def sphere(name, radius, loc, material, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, 0.0)


def torus(name, major, minor, loc, material, axis="X"):
    rot = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=32, minor_segments=8,
                                     location=loc, rotation=rot)
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, name, material, 0.0)


def join(name, objects, origin=None):
    """Joins objects into one mesh. origin: world point to put the object origin at."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    if origin is not None:
        bpy.context.scene.cursor.location = origin
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.context.scene.cursor.location = (0, 0, 0)
    return obj


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    _mats.clear()


def export(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("exported", path)


# --- Shared parts ----------------------------------------------------------------

def loco_wheel(name, loc):
    """Big red spoked steam wheel with a white rim, origin at the wheel centre (so it can be lifted and fitted)."""
    x, y, z = loc
    parts = [
        cyl(name + "_disc", 0.45, 0.14, loc, mat("red"), axis="X", bevel=0.03),
        torus(name + "_rim", 0.43, 0.045, loc, mat("cream", 0.5), axis="X"),
        cyl(name + "_hub", 0.13, 0.24, loc, mat("gold", 0.35, 0.6), axis="X"),
    ]
    for i in range(6):
        a = i * math.pi / 3
        parts.append(box(name + f"_spoke{i}", (0.16, 0.06, 0.7), (x + 0.0, y, z), mat("dark_red"), 0.01,
                         rot=(a, 0, 0)))
    return join(name, parts, origin=loc)


def wagon_wheel(name, loc):
    x, y, z = loc
    parts = [
        cyl(name + "_disc", 0.36, 0.14, loc, mat("black"), axis="X", bevel=0.03),
        cyl(name + "_hub", 0.1, 0.2, loc, mat("red"), axis="X"),
    ]
    return join(name, parts, origin=loc)


def underframe(length, parts):
    parts.append(box("frame", (2.3, length, 0.4), (0, 0, 0.85), mat("black"), 0.05))
    for s in (-1, 1):
        parts.append(cyl(f"buffer{s}", 0.13, 0.35, (0.7 * s, length / 2 + 0.12, 0.95), mat("iron", 0.4, 0.7), axis="Y"))
        parts.append(cyl(f"bufferr{s}", 0.13, 0.35, (0.7 * s, -length / 2 - 0.12, 0.95), mat("iron", 0.4, 0.7), axis="Y"))


def plank_deck(length, parts, color="wood"):
    n = int(length / 0.5)
    for i in range(n):
        y = -length / 2 + 0.25 + i * 0.5
        shade = color if i % 2 == 0 else "wood_dark"
        parts.append(box(f"plank{i}", (2.8, 0.48, 0.3), (0, y, FLOOR - 0.15), mat(shade), 0.03))


def side_boards(length, parts, height=0.7, door=1.0, color="wood"):
    """Low side walls with a gap of `door` metres at each end for climbing aboard."""
    inner = length - 2 * door
    for s in (-1, 1):
        for k in range(3):
            parts.append(box(f"board{s}{k}", (0.12, inner, 0.2), (1.4 * s, 0, FLOOR + 0.12 + k * 0.24), mat(color), 0.03))
        for py in (-inner / 2, 0, inner / 2):
            parts.append(box(f"post{s}{py}", (0.16, 0.16, height + 0.1), (1.42 * s, py, FLOOR + height / 2), mat("iron", 0.5, 0.5), 0.03))
        # step under each door
        for e in (-1, 1):
            parts.append(box(f"step{s}{e}", (0.5, 0.7, 0.08), (1.45 * s, e * (length / 2 - door / 2), 0.75), mat("iron", 0.5, 0.5), 0.02))


# --- Train cars -------------------------------------------------------------------

def build_locomotive():
    clear_scene()
    L = 10.0
    body = []
    underframe(L, body)
    # cab deck (rear half)
    body.append(box("cab_deck", (2.8, 4.8, 0.3), (0, -2.6, FLOOR - 0.15), mat("wood_dark"), 0.03))
    # boiler (front half), smokebox, bands
    body.append(cyl("boiler", 1.0, 4.6, (0, 2.0, FLOOR + 1.0), mat("red", 0.45), axis="Y", verts=48, bevel=0.06))
    body.append(cyl("smokebox", 1.04, 0.8, (0, 4.45, FLOOR + 1.0), mat("black", 0.6), axis="Y", verts=48, bevel=0.08))
    body.append(cyl("smokedoor", 0.8, 0.12, (0, 4.9, FLOOR + 1.0), mat("iron", 0.4, 0.6), axis="Y", verts=48, bevel=0.04))
    body.append(sphere("doorknob", 0.1, (0, 4.98, FLOOR + 1.0), mat("gold", 0.3, 0.8)))
    for i, y in enumerate((0.3, 1.6, 2.9)):
        body.append(cyl(f"band{i}", 1.03, 0.12, (0, y, FLOOR + 1.0), mat("gold", 0.35, 0.7), axis="Y", verts=48))
    # chimney (flared), domes, whistle, headlight
    body.append(cyl("chimney", 0.28, 1.0, (0, 4.0, FLOOR + 2.4), mat("black"), bevel=0.03))
    body.append(cyl("chimney_top", 0.3, 0.45, (0, 4.0, FLOOR + 3.05), mat("black"), radius2=0.5, bevel=0.03))
    body.append(sphere("steam_dome", 0.42, (0, 2.3, FLOOR + 1.95), mat("gold", 0.3, 0.8), scale=(1, 1, 0.9)))
    body.append(sphere("sand_dome", 0.34, (0, 0.9, FLOOR + 1.9), mat("red", 0.45), scale=(1, 1, 0.85)))
    body.append(cyl("whistle", 0.07, 0.4, (0.3, 0.2, FLOOR + 2.2), mat("gold", 0.3, 0.8)))
    body.append(cyl("lamp_body", 0.26, 0.4, (0, 4.7, FLOOR + 2.15), mat("black"), axis="Y"))
    body.append(cyl("lamp_glass", 0.2, 0.06, (0, 4.92, FLOOR + 2.15), mat("lamp", 0.2, 0.0, 4.0), axis="Y"))
    # cowcatcher
    for i in range(5):
        x = -0.8 + i * 0.4
        body.append(box(f"cowbar{i}", (0.1, 0.9, 0.08), (x, 5.35, 0.55), mat("red"), 0.02, rot=(math.radians(35), 0, 0)))
    body.append(box("cow_top", (2.0, 0.15, 0.12), (0, 5.05, 0.85), mat("red"), 0.03))
    # running boards along the boiler
    for s in (-1, 1):
        body.append(box(f"runboard{s}", (0.35, 4.6, 0.08), (1.22 * s, 2.2, FLOOR - 0.05), mat("black"), 0.02))
    # cab: front wall with round windows, low side walls with doors, posts, roof
    body.append(box("cab_front", (2.8, 0.15, 2.5), (0, -0.25, FLOOR + 1.25), mat("green", 0.6), 0.04))
    for s in (-1, 1):
        body.append(cyl(f"porthole{s}", 0.25, 0.18, (0.75 * s, -0.25, FLOOR + 1.85), mat("glass", 0.1), axis="Y"))
        body.append(torus(f"portring{s}", 0.26, 0.04, (0.75 * s, -0.33, FLOOR + 1.85), mat("gold", 0.3, 0.8), axis="Y"))
        body.append(box(f"cab_side{s}", (0.12, 3.6, 0.9), (1.4 * s, -2.1, FLOOR + 0.45), mat("green", 0.6), 0.03))
        body.append(box(f"cab_trim{s}", (0.16, 3.6, 0.1), (1.42 * s, -2.1, FLOOR + 0.92), mat("gold", 0.35, 0.7), 0.02))
        for py in (-0.35, -4.7):
            body.append(box(f"cab_post{s}{py}", (0.14, 0.14, 2.6), (1.36 * s, py, FLOOR + 1.3), mat("green", 0.6), 0.03))
        body.append(box(f"cab_step{s}", (0.5, 0.7, 0.08), (1.45 * s, -4.5, 0.75), mat("iron", 0.5, 0.5), 0.02))
    body.append(box("roof", (3.1, 4.6, 0.16), (0, -2.55, FLOOR + 2.65), mat("dark_red", 0.6), 0.06))
    body.append(box("roof_lip", (3.2, 4.7, 0.06), (0, -2.55, FLOOR + 2.55), mat("black"), 0.02))
    # connecting rods
    for s in (-1, 1):
        body.append(box(f"rod{s}", (0.06, 7.4, 0.12), (1.0 * s, 0.0, 0.5), mat("steel", 0.3, 0.9), 0.02))
    join("Locomotive", body, origin=(0, 0, 0))
    # tracked wheels: Wheel_0..5, same order as train.gd (front pair first, left then right)
    idx = 0
    for y in (3.5, 0.0, -3.5):
        for s in (-1, 1):
            loco_wheel(f"Wheel_{idx}", (0.85 * s, y, 0.5))
            idx += 1
    export(os.path.join(OUT_TRAIN, "locomotive.glb"))


def build_wagon(kind):
    clear_scene()
    L = 8.0
    body = []
    underframe(L, body)
    plank_deck(L, body)
    if kind in ("cargo", "utility"):
        side_boards(L, body, color="wood" if kind == "cargo" else "green")
    if kind == "cargo":
        for i, (x, y) in enumerate([(-0.6, -2.0), (0.6, -1.0), (-0.5, 1.2), (0.55, 2.2)]):
            body.append(box(f"crate{i}", (0.9, 0.9, 0.8), (x, y, FLOOR + 0.4), mat("wood"), 0.05))
            body.append(box(f"crate_band{i}", (0.94, 0.94, 0.12), (x, y, FLOOR + 0.4), mat("wood_dark"), 0.02))
        body.append(sphere("coal_pile", 0.7, (0.4, -0.2, FLOOR + 0.1), mat("black", 0.9), scale=(1.2, 1.4, 0.6)))
    elif kind == "utility":
        body.append(box("canopy", (3.0, 3.4, 0.12), (0, 1.8, FLOOR + 2.6), mat("cream", 0.7), 0.05))
        for s in (-1, 1):
            for py in (0.2, 3.4):
                body.append(box(f"canopy_post{s}{py}", (0.1, 0.1, 2.6), (1.35 * s, py, FLOOR + 1.3), mat("iron", 0.5, 0.5), 0.02))
    elif kind == "container":
        body.append(box("container", (2.5, 6.4, 2.3), (0, 0, FLOOR + 1.15), mat("rust", 0.75), 0.06))
        for i in range(13):
            y = -3.0 + i * 0.5
            for s in (-1, 1):
                body.append(box(f"rib{i}{s}", (0.06, 0.18, 2.1), (1.26 * s, y, FLOOR + 1.15), mat("rust", 0.75), 0.01))
        body.append(box("doors", (2.3, 0.08, 2.1), (0, -3.23, FLOOR + 1.15), mat("dark_red", 0.7), 0.02))
        for s in (-0.3, 0.3):
            body.append(cyl(f"lockbar{s}", 0.04, 2.0, (s, -3.3, FLOOR + 1.15), mat("steel", 0.3, 0.9)))
        body.append(box("padlock", (0.25, 0.12, 0.3), (0, -3.36, FLOOR + 1.1), mat("gold", 0.3, 0.8), 0.03))
        body.append(torus("shackle", 0.09, 0.025, (0, -3.36, FLOOR + 1.3), mat("steel", 0.3, 0.9), axis="Y"))
    join(kind.capitalize(), body, origin=(0, 0, 0))
    n = 0
    for y in (2.8, -2.8):
        for s in (-1, 1):
            wagon_wheel(f"WagonWheel_{n}", (0.85 * s, y, 0.4))
            n += 1
    export(os.path.join(OUT_TRAIN, f"{kind}_wagon.glb"))


# --- Props: repair items and tools -------------------------------------------------

def build_props():
    clear_scene()
    loco_wheel("Wheel", (0, 0, 0))
    export(os.path.join(OUT_PROPS, "wheel.glb"))

    clear_scene()
    # sleeper plank: 2.4 x 0.12 x 0.3 m (same as the track sleepers)
    join("Plank", [box("plank", (2.4, 0.3, 0.12), (0, 0, 0), mat("wood"), 0.02),
                   box("grain", (2.3, 0.02, 0.122), (0, 0.06, 0), mat("wood_dark"), 0.005)], origin=(0, 0, 0))
    export(os.path.join(OUT_PROPS, "plank.glb"))

    clear_scene()
    # rail: 4 m long I-beam, runs along Y (becomes Godot -Z)
    join("Rail", [box("rail_head", (0.12, 4.0, 0.05), (0, 0, 0.05), mat("steel", 0.3, 0.9), 0.01),
                  box("rail_web", (0.04, 4.0, 0.08), (0, 0, 0.0), mat("iron", 0.4, 0.8), 0.005),
                  box("rail_foot", (0.16, 4.0, 0.03), (0, 0, -0.055), mat("iron", 0.4, 0.8), 0.005)], origin=(0, 0, 0))
    export(os.path.join(OUT_PROPS, "rail.glb"))

    clear_scene()
    # hammer: handle along Z (held upright), head on top
    join("Hammer", [cyl("handle", 0.035, 0.55, (0, 0, 0.0), mat("wood"), bevel=0.01),
                    cyl("grip", 0.042, 0.18, (0, 0, -0.2), mat("red", 0.8), bevel=0.01),
                    box("head", (0.26, 0.08, 0.09), (0.02, 0, 0.3), mat("iron", 0.35, 0.8), 0.02),
                    box("claw", (0.1, 0.06, 0.05), (-0.13, 0, 0.32), mat("iron", 0.35, 0.8), 0.015, rot=(0, math.radians(-25), 0))],
         origin=(0, 0, -0.2))
    export(os.path.join(OUT_PROPS, "hammer.glb"))

    clear_scene()
    # welding torch: grip + neck + nozzle pointing forward (+Y)
    join("WelderTorch", [cyl("grip", 0.045, 0.22, (0, -0.05, 0), mat("blue", 0.6), axis="Y", bevel=0.01),
                         cyl("trigger", 0.02, 0.06, (0, 0.0, -0.06), mat("black")),
                         cyl("neck", 0.022, 0.25, (0, 0.17, 0.04), mat("steel", 0.3, 0.9), axis="Y"),
                         cyl("nozzle", 0.035, 0.08, (0, 0.32, 0.05), mat("gold", 0.3, 0.8), axis="Y", radius2=0.02)],
         origin=(0, -0.1, 0))
    export(os.path.join(OUT_PROPS, "welder_torch.glb"))

    clear_scene()
    # welder machine with a cable reel
    join("WelderMachine", [box("case", (0.9, 0.6, 0.7), (0, 0, 0.35), mat("orange", 0.55), 0.05),
                           box("panel", (0.6, 0.04, 0.35), (0, -0.31, 0.45), mat("black", 0.4), 0.01),
                           cyl("dial1", 0.06, 0.04, (-0.15, -0.34, 0.5), mat("cream", 0.4), axis="Y"),
                           cyl("dial2", 0.06, 0.04, (0.15, -0.34, 0.5), mat("cream", 0.4), axis="Y"),
                           cyl("reel", 0.28, 0.22, (0, 0.42, 0.45), mat("iron", 0.5, 0.6), axis="X"),
                           torus("cable_coil", 0.22, 0.05, (0, 0.42, 0.45), mat("black", 0.8), axis="X"),
                           box("handle", (0.7, 0.06, 0.06), (0, 0, 0.75), mat("black"), 0.02)], origin=(0, 0, 0))
    export(os.path.join(OUT_PROPS, "welder_machine.glb"))


if __name__ == "__main__":
    build_locomotive()
    for k in ("cargo", "utility", "container"):
        build_wagon(k)
    build_props()
    print("done")
