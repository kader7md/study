"""Builds the Trust Issues train, repair items and tools in Blender, bakes worn PBR-style textures, exports .glb.

Run headless:
    blender --background --python blender/scripts/build_assets.py -- <repo_root> [only=train,props,gate,items,pickups]
    (items = the build items: plank, rail, track spike, fishplate bolt, spare panel; or one by one with
    only=plank / rail / fasteners / panel)
Or open Blender → Scripting tab → open this file → Run Script.

Style: stylized realism (Sea of Thieves / Valheim direction): real proportions, rivets, bolts, iron straps,
worn paint with chipped edges, dirt in the corners, rust, wood grain. The wear is made with shader nodes and then
BAKED into one texture per model (Cycles), so it also shows up in Godot.

Axes: Blender +Y = front of the train (becomes -Z in Godot), Z up. Rail top is Z = 0.
Train deck (walkable floor) top is Z = 1.35 = Train.FLOOR_HEIGHT in train.gd.
Names the game relies on: Wheel_0..5 (locomotive), Panel_<wood|metal>_<n> and Door_<wood|metal>_<n> (breakable cover).
"""
import math
import os
import random
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = argv[0] if argv else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ONLY = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("only=")), None)
OUT_TRAIN = os.path.join(ROOT, "assets", "models", "train")
OUT_PROPS = os.path.join(ROOT, "assets", "models", "props")
os.makedirs(OUT_TRAIN, exist_ok=True)
os.makedirs(OUT_PROPS, exist_ok=True)

FLOOR = 1.35
random.seed(7)

# --- Materials (procedural wear → baked) ---------------------------------------------
# kind: paint (chipped edges), enamel (clean signal paint), iron (rust), brass (tarnish), wood (grain), plain, canvas, glass, lamp, rubber
MATS = {
    "red_paint": ("paint", (0.42, 0.07, 0.05), 0.35, 0.45),
    "green_paint": ("paint", (0.12, 0.27, 0.18), 0.3, 0.5),
    "black_paint": ("paint", (0.035, 0.035, 0.04), 0.5, 0.55),
    "cream_paint": ("paint", (0.72, 0.66, 0.52), 0.2, 0.6),
    "orange_paint": ("paint", (0.75, 0.3, 0.05), 0.3, 0.5),
    "iron": ("iron", (0.13, 0.13, 0.14), 0.85, 0.6),
    "steel": ("iron", (0.45, 0.46, 0.48), 0.95, 0.35),
    "rust": ("iron", (0.32, 0.13, 0.06), 0.4, 0.85),
    "brass": ("brass", (0.78, 0.55, 0.2), 1.0, 0.3),
    "wood": ("wood", (0.36, 0.21, 0.11), 0.0, 0.8),
    "wood_dark": ("wood", (0.2, 0.12, 0.06), 0.0, 0.85),
    "wood_grey": ("wood", (0.33, 0.29, 0.24), 0.0, 0.9),
    "canvas": ("canvas", (0.62, 0.55, 0.4), 0.0, 0.95),
    "glass": ("plain", (0.25, 0.35, 0.38), 0.0, 0.08),
    "lamp": ("lamp", (1.0, 0.85, 0.5), 0.0, 0.2),
    "rubber": ("plain", (0.04, 0.04, 0.045), 0.0, 0.8),
    "leather": ("canvas", (0.23, 0.12, 0.06), 0.0, 0.7),
    "coal": ("plain", (0.03, 0.03, 0.035), 0.0, 0.4),
    "blue_paint": ("paint", (0.08, 0.18, 0.35), 0.3, 0.5),
    "dial": ("plain", (0.85, 0.82, 0.72), 0.0, 0.4),
    # GWR-style locomotive livery (reference: 7822 "Foxcote Manor" photos)
    "loco_green": ("paint", (0.035, 0.13, 0.06), 0.3, 0.35),
    "lining": ("paint", (0.75, 0.38, 0.06), 0.2, 0.4),
    "copper": ("brass", (0.62, 0.27, 0.13), 1.0, 0.3),
    "buffer_red": ("paint", (0.5, 0.04, 0.03), 0.3, 0.45),
    "van_brown": ("paint", (0.25, 0.09, 0.05), 0.4, 0.6),
    "roof_grey": ("paint", (0.42, 0.42, 0.4), 0.3, 0.7),
    # nature
    "bark": ("wood", (0.17, 0.11, 0.07), 0.0, 0.95),
    "birch_bark": ("bark_birch", (0.82, 0.8, 0.74), 0.0, 0.8),
    "pine_needles": ("foliage", (0.05, 0.15, 0.07), 0.0, 0.85),
    "oak_leaves": ("foliage", (0.13, 0.25, 0.06), 0.0, 0.85),
    "birch_leaves": ("foliage", (0.3, 0.42, 0.1), 0.0, 0.85),
    "bush_leaves": ("foliage", (0.09, 0.21, 0.06), 0.0, 0.85),
    "rock": ("rock", (0.12, 0.115, 0.105), 0.0, 0.9),
    "cliff": ("rock", (0.16, 0.13, 0.1), 0.0, 0.9),
    "snow": ("plain", (0.88, 0.9, 0.94), 0.0, 0.6),
    # locked track gate (boom barrier), its signal post and the key
    "white_paint": ("enamel", (0.8, 0.78, 0.72), 0.1, 0.5),
    "signal_red": ("enamel", (0.5, 0.035, 0.025), 0.1, 0.45),
    "lamp_red": ("lamp", (1.0, 0.1, 0.04), 0.0, 0.2),
    "concrete": ("rock", (0.36, 0.35, 0.33), 0.0, 0.9),
    "paper": ("canvas", (0.8, 0.72, 0.52), 0.0, 0.9),
    # pickups
    "gold_ore": ("brass", (1.0, 0.72, 0.16), 1.0, 0.28),
    "ore_rock": ("rock", (0.13, 0.115, 0.1), 0.0, 0.9),
    "coal_lump": ("rock", (0.045, 0.043, 0.045), 0.1, 0.45),
    "rope": ("canvas", (0.55, 0.43, 0.25), 0.0, 0.95),
    "rail_steel": ("iron", (0.3, 0.28, 0.26), 0.75, 0.45),
    # build items: creosoted sleeper timber (the same brown as the intact track's sleepers), cast plates, spikes
    "sleeper_wood": ("wood", (0.4, 0.25, 0.13), 0.0, 0.85),
    "wood_end": ("plain", (0.12, 0.075, 0.04), 0.0, 0.9),
    "tie_plate": ("iron", (0.2, 0.19, 0.18), 0.8, 0.6),
    "spike_steel": ("iron", (0.24, 0.23, 0.22), 0.85, 0.5),
}
_mats = {}


def _n(nt, kind, loc=(0, 0)):
    node = nt.nodes.new(kind)
    node.location = loc
    return node


def _mix(nt, a, b, fac):
    m = _n(nt, "ShaderNodeMix")
    m.data_type = "RGBA"
    nt.links.new(fac, m.inputs[0])
    if isinstance(a, tuple):
        m.inputs[6].default_value = (*a, 1.0)
    else:
        nt.links.new(a, m.inputs[6])
    if isinstance(b, tuple):
        m.inputs[7].default_value = (*b, 1.0)
    else:
        nt.links.new(b, m.inputs[7])
    return m.outputs[2]


def _ramp(nt, src, lo, hi):
    r = _n(nt, "ShaderNodeValToRGB")
    r.color_ramp.elements[0].position = lo
    r.color_ramp.elements[1].position = hi
    nt.links.new(src, r.inputs[0])
    return r.outputs[0]


def _noise(nt, coord, scale, detail=6.0):
    t = _n(nt, "ShaderNodeTexNoise")
    t.inputs["Scale"].default_value = scale
    t.inputs["Detail"].default_value = detail
    nt.links.new(coord, t.inputs["Vector"])
    return t.outputs["Fac"]


def mat(name):
    if name in _mats:
        return _mats[name]
    kind, base, metal, rough = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = _n(nt, "ShaderNodeOutputMaterial", (900, 0))
    bsdf = _n(nt, "ShaderNodeBsdfPrincipled", (600, 0))
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    coord = _n(nt, "ShaderNodeTexCoord").outputs["Object"]
    ao = _n(nt, "ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = 0.25
    ao.samples = 32                    # smooth corner dirt (fewer rays bake as salt-and-pepper speckles)
    geo = _n(nt, "ShaderNodeNewGeometry")
    dirt = _ramp(nt, ao.outputs["AO"], 0.2, 0.9)           # 0 in corners, 1 in the open
    grime = _ramp(nt, _noise(nt, coord, 3.0, 3.0), 0.5, 0.8)

    color = base
    if kind == "wood":
        wave = _n(nt, "ShaderNodeTexWave")
        wave.bands_direction = "X"
        wave.inputs["Scale"].default_value = 2.5
        wave.inputs["Distortion"].default_value = 8.0
        wave.inputs["Detail"].default_value = 4.0
        nt.links.new(coord, wave.inputs["Vector"])
        dark = tuple(c * 0.55 for c in base)
        light = tuple(min(c * 1.35, 1.0) for c in base)
        color = _mix(nt, dark, light, _ramp(nt, wave.outputs["Fac"], 0.2, 0.8))
        color = _mix(nt, color, (0.12, 0.1, 0.08), _ramp(nt, _noise(nt, coord, 25.0), 0.6, 0.8))
    elif kind == "iron":
        rust = _ramp(nt, _noise(nt, coord, 4.0, 10.0), 0.55, 0.72)
        color = _mix(nt, base, (0.3, 0.12, 0.04), rust)
    elif kind == "brass":
        color = _mix(nt, base, (0.2, 0.15, 0.06), _ramp(nt, _noise(nt, coord, 12.0), 0.55, 0.8))
    elif kind == "canvas":
        color = _mix(nt, base, tuple(c * 0.6 for c in base), _ramp(nt, _noise(nt, coord, 3.0, 4.0), 0.4, 0.75))
    elif kind == "foliage":
        color = _mix(nt, tuple(c * 0.6 for c in base), tuple(min(c * 1.5, 1.0) for c in base), _ramp(nt, _noise(nt, coord, 1.5, 4.0), 0.3, 0.7))
        color = _mix(nt, color, (0.25, 0.22, 0.06), _ramp(nt, _noise(nt, coord, 7.0), 0.65, 0.8))
    elif kind == "bark_birch":
        stripes = _ramp(nt, _noise(nt, coord, 9.0, 3.0), 0.62, 0.66)
        color = _mix(nt, base, (0.06, 0.05, 0.05), stripes)
    elif kind == "rock":
        color = _mix(nt, tuple(c * 0.7 for c in base), tuple(min(c * 1.25, 1.0) for c in base), _ramp(nt, _noise(nt, coord, 1.2, 8.0), 0.3, 0.7))
        sep = _n(nt, "ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Normal"], sep.inputs[0])
        moss = _ramp(nt, sep.outputs["Z"], 0.45, 0.75)
        mul = _n(nt, "ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(moss, mul.inputs[0])
        nt.links.new(_ramp(nt, _noise(nt, coord, 3.0), 0.35, 0.6), mul.inputs[1])
        color = _mix(nt, color, (0.06, 0.13, 0.03), mul.outputs[0])
    elif kind == "stone":
        # dressed stone / flagstones: soft mottling and a fine grit, no moss (it is walked on)
        color = _mix(nt, tuple(c * 0.86 for c in base), tuple(min(c * 1.1, 1.0) for c in base), _ramp(nt, _noise(nt, coord, 2.5, 4.0), 0.3, 0.7))
        color = _mix(nt, color, tuple(c * 0.8 for c in base), _ramp(nt, _noise(nt, coord, 40.0, 1.0), 0.62, 0.75))
    elif kind == "brick":
        # brick courses on a wall facing X (the platform's track side): the brick pattern runs along Y and Z
        sep = _n(nt, "ShaderNodeSeparateXYZ")
        nt.links.new(coord, sep.inputs[0])
        comb = _n(nt, "ShaderNodeCombineXYZ")
        nt.links.new(sep.outputs["Y"], comb.inputs["X"])
        nt.links.new(sep.outputs["Z"], comb.inputs["Y"])
        nt.links.new(sep.outputs["X"], comb.inputs["Z"])
        tb = _n(nt, "ShaderNodeTexBrick")
        tb.offset = 0.5
        tb.inputs["Color1"].default_value = (*base, 1.0)
        tb.inputs["Color2"].default_value = (*(c * 0.72 for c in base), 1.0)
        tb.inputs["Mortar"].default_value = (0.42, 0.4, 0.36, 1.0)
        tb.inputs["Scale"].default_value = 1.0
        tb.inputs["Mortar Size"].default_value = 0.012
        tb.inputs["Brick Width"].default_value = 0.23
        tb.inputs["Row Height"].default_value = 0.077
        nt.links.new(comb.outputs[0], tb.inputs["Vector"])
        color = _mix(nt, tb.outputs["Color"], tuple(c * 0.8 for c in base), _ramp(nt, _noise(nt, coord, 3.0, 4.0), 0.45, 0.8))
    elif kind == "enamel":
        # signal enamel: glossy, only a faint colour variation (no chipping, so stripes read cleanly from afar)
        color = _mix(nt, tuple(c * 0.9 for c in base), base, _ramp(nt, _noise(nt, coord, 0.8, 2.0), 0.35, 0.65))
    elif kind == "paint":
        # Clean painted metal: a very soft, large-scale tone variation and only a few worn patches on the sharpest
        # edges, in a darker, duller shade of the paint (no fine noise: small chips bake as speckles that shimmer
        # in game). Corner dirt and grime are toned down below.
        color = _mix(nt, tuple(c * 0.96 for c in base), base, _ramp(nt, _noise(nt, coord, 0.5, 1.0), 0.35, 0.65))
        edge = _ramp(nt, geo.outputs["Pointiness"], 0.56, 0.64)
        chip = _ramp(nt, _noise(nt, coord, 4.0, 1.0), 0.6, 0.7)
        mul = _n(nt, "ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(edge, mul.inputs[0])
        nt.links.new(chip, mul.inputs[1])
        worn = tuple(c * 0.6 + 0.04 for c in base)
        color = _mix(nt, color, worn, mul.outputs[0])
        bsdf.inputs["Metallic"].default_value = 0.15
    if kind not in ("lamp", "glass"):
        # dirt and soot collect in corners, streaks of grime everywhere
        inv = _n(nt, "ShaderNodeInvert")
        nt.links.new(dirt, inv.inputs["Color"])
        dirty = tuple(c * 0.3 for c in base) if kind != "brass" else (0.12, 0.08, 0.03)
        if kind == "paint":
            dirty = tuple(c * 0.7 for c in base)  # paint: a light shadow of dirt in the corners only
        color = _mix(nt, color, dirty, inv.outputs[0])
        streak = tuple(c * (0.9 if kind == "paint" else 0.7) for c in base) if kind != "brass" else (0.3, 0.22, 0.08)
        color = _mix(nt, color, streak, _ramp(nt, grime, 0.75, 1.0))
    if isinstance(color, tuple):
        rgb = _n(nt, "ShaderNodeRGB")
        rgb.outputs[0].default_value = (*color, 1.0)
        color = rgb.outputs[0]
    # a reroute marks the final colour so the bake step can find it
    reroute = _n(nt, "NodeReroute")
    reroute.name = "COLOR_OUT"
    nt.links.new(color, reroute.inputs[0])
    nt.links.new(reroute.outputs[0], bsdf.inputs["Base Color"])
    if kind == "lamp":
        bsdf.inputs["Emission Color"].default_value = (*base, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 6.0
    m["kind"] = kind
    _mats[name] = m
    return m


# --- Geometry helpers --------------------------------------------------------------------

def _finish(obj, name, material, bevel, segments=2):
    obj.name = name
    obj.data.materials.append(mat(material))
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    for poly in obj.data.polygons:
        poly.use_smooth = True
    obj.modifiers.new("WN", "WEIGHTED_NORMAL").keep_sharp = True
    return obj


def box(name, size, loc, material, bevel=0.015, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, bevel)


def cyl(name, radius, depth, loc, material, axis="Z", verts=32, bevel=0.01, radius2=None, rot=None):
    r = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis] if rot is None else rot
    if radius2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=r)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius, radius2=radius2, depth=depth, location=loc, rotation=r)
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, name, material, bevel)


def sphere(name, radius, loc, material, scale=(1, 1, 1), seg=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(obj, name, material, 0.0)


def torus(name, major, minor, loc, material, axis="X", seg=32):
    r = {"X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0), "Z": (0, 0, 0)}[axis]
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=seg, minor_segments=8,
                                     location=loc, rotation=r)
    obj = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, name, material, 0.0)


def rod(name, a, b, radius, material, verts=12):
    """Cylinder from point a to point b (pipes, handrails, rods)."""
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=length,
                                        location=((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2))
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    from mathutils import Vector
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector((dx, dy, dz)).normalized())
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return _finish(obj, name, material, 0.0)


def rivets_line(name, a, b, count, material="iron", radius=0.022):
    out = []
    for i in range(count):
        t = i / max(count - 1, 1)
        p = tuple(a[k] + (b[k] - a[k]) * t for k in range(3))
        out.append(sphere(f"{name}{i}", radius, p, material, scale=(1, 1, 0.7), seg=8))
    return out


def rivets_ring(name, center, radius, count, axis="Y", material="iron", r=0.022):
    out = []
    cx, cy, cz = center
    for i in range(count):
        a = i * 2 * math.pi / count
        if axis == "Y":
            p = (cx + math.cos(a) * radius, cy, cz + math.sin(a) * radius)
        else:
            p = (cx, cy + math.cos(a) * radius, cz + math.sin(a) * radius)
        out.append(sphere(f"{name}{i}", r, p, material, seg=8))
    return out


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def join(name, objects, origin=None, bounds_origin=False):
    for o in objects:
        apply_all(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    if origin is not None:
        bpy.context.scene.cursor.location = origin
        bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
        bpy.context.scene.cursor.location = (0, 0, 0)
    elif bounds_origin:
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    return obj


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)
    _mats.clear()


# --- Bake: procedural wear → one texture per model ---------------------------------

def bake_and_export(path, size=2048, repack=False):
    """`repack`: pack the UV islands again with rotation, so long thin parts (planks, rails) fill the whole texture
    instead of a strip of it (more texels on the model, sharper grain)."""
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        apply_all(o)
    # one shared UV atlas for all objects of this model
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.003)
    if repack:
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
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
    scene.cycles.samples = 96          # enough samples so the corner dirt (AO) bakes smooth, not speckled
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


# --- Train parts ------------------------------------------------------------------------

def loco_wheel(name, loc, radius=0.45, paint="loco_green"):
    """Cast spoked driving wheel with a steel tyre, counterweight and crank pin. Origin at the centre."""
    x, y, z = loc
    s = 1 if x >= 0 else -1
    parts = [
        torus(name + "_tyre", radius - 0.03, 0.045, loc, "steel", axis="X", seg=40),
        cyl(name + "_rim", radius - 0.05, 0.1, loc, paint, axis="X", verts=40),
        cyl(name + "_hubdisc", 0.13, 0.16, loc, paint, axis="X"),
        cyl(name + "_hub", 0.07, 0.2, (x + 0.03 * s, y, z), "steel", axis="X", verts=16),
        cyl(name + "_crank", 0.04, 0.12, (x + 0.08 * s, y + 0.2, z), "steel", axis="X", verts=12),
    ]
    # counterweight crescent
    parts.append(box(name + "_cw", (0.09, 0.32, 0.12), (x + 0.01 * s, y - 0.17, z - 0.17), paint, 0.03,
                     rot=(math.radians(-45), 0, 0)))
    for i in range(12):
        a = i * math.pi / 6
        parts.append(rod(name + f"_spoke{i}", (x, y + math.cos(a) * 0.12, z + math.sin(a) * 0.12),
                         (x, y + math.cos(a) * (radius - 0.07), z + math.sin(a) * (radius - 0.07)), 0.022, paint, 8))
    # the disc behind the spokes is hollow in reality; a thin dark backing keeps it readable from afar
    parts.append(cyl(name + "_back", radius - 0.06, 0.02, (x - 0.03 * s, y, z), "iron", axis="X", verts=40))
    return join(name, parts, origin=loc)


def wagon_wheel(name, loc):
    x, y, z = loc
    return join(name, [torus(name + "_t", 0.33, 0.04, loc, "steel", axis="X"),
                       cyl(name + "_d", 0.33, 0.08, loc, "iron", axis="X"),
                       cyl(name + "_h", 0.08, 0.18, loc, "steel", axis="X", verts=12)], origin=loc)


def bogie(name, y, parts):
    for s in (-1, 1):
        parts.append(box(f"{name}side{s}", (0.1, 1.8, 0.25), (1.0 * s, y, 0.45), "iron", 0.02))
        parts.append(cyl(f"{name}spring{s}", 0.07, 0.18, (1.0 * s, y, 0.68), "steel", verts=10))
    parts.append(box(f"{name}bolster", (2.1, 0.3, 0.15), (0, y, 0.72), "iron", 0.02))


def underframe(length, parts, buffer_beam="red_paint"):
    for s in (-1, 1):
        parts.append(box(f"sill{s}", (0.18, length, 0.32), (1.05 * s, 0, 0.92), "iron", 0.02))
        parts += rivets_line(f"sillriv{s}", (1.15 * s, -length / 2 + 0.2, 1.02), (1.15 * s, length / 2 - 0.2, 1.02), int(length * 3))
    parts.append(box("frame_mid", (1.6, length - 0.4, 0.15), (0, 0, 0.85), "iron", 0.02))
    for e in (-1, 1):
        parts.append(box(f"beam{e}", (2.7, 0.2, 0.36), (0, e * length / 2, 0.95), buffer_beam, 0.02))
        for s in (-1, 1):
            parts.append(cyl(f"buf{e}{s}", 0.06, 0.3, (0.75 * s, e * (length / 2 + 0.15), 0.95), "steel", axis="Y", verts=12))
            parts.append(cyl(f"bufhead{e}{s}", 0.15, 0.04, (0.75 * s, e * (length / 2 + 0.3), 0.95), "steel", axis="Y", verts=20))
        parts.append(box(f"hook{e}", (0.08, 0.3, 0.08), (0, e * (length / 2 + 0.15), 0.9), "iron", 0.01))


def plank_floor(length, parts, width=2.8, material="wood"):
    n = int(length / 0.25)
    for i in range(n):
        y = -length / 2 + 0.125 + i * 0.25
        parts.append(box(f"fplank{i}", (width, 0.24, 0.08), (0, y, FLOOR - 0.04), material if i % 3 else "wood_dark", 0.008))
    parts.append(box("deck_base", (width - 0.05, length, 0.2), (0, 0, FLOOR - 0.18), "iron", 0.01))


def panel(kind, mat_kind, n, parts, origin=None):
    """Joins parts into one breakable cover piece: Panel_<wood|metal>_<n> or Door_<wood|metal>_<n>."""
    return join(f"{kind}_{mat_kind}_{n}", parts, origin=origin, bounds_origin=origin is None)


def plank_wall(name, s, y, length, height=2.25, z0=FLOOR, x=1.42):
    """Wooden wall panel: vertical boards with two iron straps and bolts."""
    parts = []
    boards = int(length / 0.2)
    for k in range(boards):
        by = y - length / 2 + 0.1 + k * 0.2
        parts.append(box(f"{name}b{k}", (0.06, 0.19, height), (x * s, by, z0 + height / 2), "van_brown", 0.006))
    for h in (0.35, height - 0.35):
        parts.append(box(f"{name}strap{h}", (0.025, length - 0.05, 0.08), ((x + 0.04) * s, y, z0 + h), "iron", 0.005))
        parts += rivets_line(f"{name}bolt{h}", ((x + 0.06) * s, y - length / 2 + 0.1, z0 + h), ((x + 0.06) * s, y + length / 2 - 0.1, z0 + h), boards // 2, "iron", 0.018)
    return parts


# --- Train cars ----------------------------------------------------------------------------

def build_locomotive():
    """GWR-style 4-6-0 tank-engine look (reference photos of 7822): black smokebox, green boiler and cab with orange
    lining, brass safety-valve bonnet, copper-capped chimney, red riveted buffer beam with big buffers.
    The cab front has two doors (one each side of the boiler) that open FORWARD: you see where you're going and can
    walk out along the running boards to the front."""
    clear_scene()
    L = 10.0
    body = []
    underframe(L, body, buffer_beam="buffer_red")
    # wider cab floor than the wagons (3.2 m) so there is room beside the boiler
    body.append(box("cab_floor_wide", (3.2, 4.8, 0.08), (0, -2.6, FLOOR - 0.04), "wood_dark", 0.008))
    bogie("bogie_front", 4.3, body)
    plank_floor(4.8, body, material="wood_dark")
    for o in body[-21:]:
        o.location.y -= 2.6
    # red buffer beam with a rivet grid, big buffers, vacuum hose, coupling, lamp irons
    body.append(box("bufferbeam", (2.8, 0.18, 0.55), (0, 5.05, 0.95), "buffer_red", 0.015))
    for row in (0.75, 1.15):
        body += rivets_line(f"bbriv{row}", (-1.3, 5.15, row), (1.3, 5.15, row), 16)
    for s in (-1, 1):
        body.append(cyl(f"buf_body{s}", 0.11, 0.35, (0.85 * s, 5.3, 0.95), "black_paint", axis="Y", verts=20))
        body.append(sphere(f"buf_head{s}", 0.2, (0.85 * s, 5.5, 0.95), "black_paint", scale=(1.0, 0.35, 0.85)))
        body.append(box(f"lampiron{s}", (0.06, 0.05, 0.16), (0.6 * s, 5.16, 1.32), "iron", 0.005))
    body.append(rod("vac_hose", (0.35, 5.15, 1.05), (0.25, 5.5, 0.55), 0.04, "rubber"))
    body.append(box("coupling", (0.1, 0.35, 0.08), (0, 5.3, 0.88), "iron", 0.01))
    body.append(box("guard_iron", (2.0, 0.06, 0.25), (0, 5.12, 0.35), "black_paint", 0.01))
    # boiler core (visible when the jacket plates are knocked off) + black smokebox
    body.append(cyl("boiler_core", 0.92, 4.6, (0, 2.0, FLOOR + 1.0), "iron", axis="Y", verts=48))
    body.append(cyl("smokebox", 1.02, 1.0, (0, 4.5, FLOOR + 1.0), "black_paint", axis="Y", verts=48, bevel=0.03))
    body.append(box("smokebox_saddle", (1.4, 0.9, 0.6), (0, 4.5, FLOOR + 0.2), "black_paint", 0.02))
    body.append(cyl("smokedoor", 0.84, 0.1, (0, 5.02, FLOOR + 1.0), "black_paint", axis="Y", verts=48, bevel=0.03))
    body.append(torus("smokedoor_ring", 0.86, 0.03, (0, 5.0, FLOOR + 1.0), "black_paint", axis="Y", seg=48))
    body += rivets_ring("doorriv", (0, 5.08, FLOOR + 1.0), 0.8, 24)
    for i, zz in enumerate((0.42, -0.42)):
        body.append(box(f"hinge{i}", (1.0, 0.05, 0.07), (-0.35, 5.08, FLOOR + 1.0 + zz), "black_paint", 0.01))
    body.append(cyl("dart", 0.03, 0.2, (0, 5.15, FLOOR + 1.0), "steel", axis="Y", verts=10))
    for a in (0.6, 2.2):
        body.append(box(f"dart_handle{a}", (0.32, 0.03, 0.035), (0, 5.24, FLOOR + 1.0), "steel", 0.004, rot=(0, a, 0)))
    body.append(box("numberplate", (0.6, 0.03, 0.18), (0, 5.08, FLOOR + 1.55), "black_paint", 0.005))
    body.append(box("numberplate_rim", (0.64, 0.025, 0.22), (0, 5.07, FLOOR + 1.55), "brass", 0.005))
    body.append(cyl("shedplate", 0.08, 0.02, (0, 5.09, FLOOR + 0.55), "dial", axis="Y", verts=16))
    # copper-capped chimney, brass safety-valve bonnet, top feed, whistles, lamp on top of the smokebox
    body.append(cyl("chimney_base", 0.42, 0.18, (0, 4.4, FLOOR + 1.92), "black_paint", verts=32, bevel=0.03))
    body.append(cyl("chimney", 0.24, 0.85, (0, 4.4, FLOOR + 2.4), "black_paint", verts=32))
    body.append(cyl("chimney_cap", 0.3, 0.25, (0, 4.4, FLOOR + 2.9), "copper", verts=32, radius2=0.33, bevel=0.02))
    body.append(cyl("chimney_rim", 0.34, 0.06, (0, 4.4, FLOOR + 3.05), "black_paint", verts=32))
    body.append(cyl("bonnet", 0.32, 0.55, (0, 1.6, FLOOR + 2.15), "brass", verts=32, radius2=0.22, bevel=0.02))
    body.append(cyl("bonnet_top", 0.22, 0.06, (0, 1.6, FLOOR + 2.45), "brass", verts=32))
    body.append(box("topfeed", (0.5, 0.35, 0.25), (0, 3.0, FLOOR + 1.98), "loco_green", 0.03))
    for k, x in enumerate((-0.25, 0.25)):
        body.append(rod(f"feedpipe{k}", (x, 3.0, FLOOR + 1.95), (x * 3.4, 3.0, FLOOR + 1.6), 0.025, "copper"))
        body.append(cyl(f"whistle{k}", 0.04, 0.3, (x, -0.12, FLOOR + 2.65), "brass", verts=12))
    body.append(box("lamp_body", (0.32, 0.28, 0.38), (0, 5.0, FLOOR + 2.05), "black_paint", 0.03))
    body.append(cyl("lamp_glass", 0.11, 0.03, (0, 5.15, FLOOR + 2.05), "lamp", axis="Y", verts=20))
    body.append(rod("lamp_handle", (-0.1, 5.0, FLOOR + 2.27), (0.1, 5.0, FLOOR + 2.27), 0.012, "iron", 6))
    # running gear: cylinders, slide bars, crossheads, rods, valve gear
    for s in (-1, 1):
        body.append(cyl(f"cylinder{s}", 0.32, 1.1, (1.05 * s, 4.0, 0.7), "loco_green", axis="Y", verts=32, bevel=0.02))
        body.append(cyl(f"cyl_cap{s}", 0.34, 0.06, (1.05 * s, 4.56, 0.7), "steel", axis="Y", verts=32))
        body += rivets_ring(f"capriv{s}", (1.05 * s, 4.6, 0.7), 0.28, 10)
        body.append(rod(f"piston{s}", (1.05 * s, 3.45, 0.7), (1.05 * s, 2.85, 0.7), 0.04, "steel"))
        body.append(box(f"crosshead{s}", (0.1, 0.25, 0.18), (1.05 * s, 2.8, 0.7), "steel", 0.01))
        for zz in (0.62, 0.78):
            body.append(box(f"slidebar{s}{zz}", (0.05, 1.2, 0.04), (1.05 * s, 2.9, zz), "steel", 0.005))
        body.append(rod(f"mainrod{s}", (1.12 * s, 2.8, 0.7), (1.12 * s, 0.2, 0.5), 0.045, "steel"))
        body.append(box(f"siderod{s}", (0.06, 7.4, 0.1), (1.18 * s, 0.0, 0.5), "steel", 0.01))
        body.append(rod(f"reach{s}", (1.15 * s, 0.4, 1.1), (1.15 * s, 2.6, 0.95), 0.025, "steel"))
        # running board along the boiler (walkable from the cab front doors), splashers over the wheels
        body.append(box(f"runboard{s}", (0.75, 5.1, 0.05), (1.2 * s, 2.35, FLOOR - 0.02), "black_paint", 0.008))
        body.append(box(f"valance{s}", (0.04, 5.1, 0.25), (1.57 * s, 2.35, FLOOR - 0.15), "loco_green", 0.006))
        body.append(box(f"valance_line{s}", (0.045, 5.1, 0.03), (1.57 * s, 2.35, FLOOR - 0.08), "lining", 0.003))
        for yy in (0.0, 3.5):
            body.append(cyl(f"splasher{s}{yy}", 0.5, 0.12, (1.2 * s, yy, FLOOR - 0.05), "loco_green", axis="X", verts=32))
        body.append(rod(f"handrail{s}", (0.98 * s, -0.1, FLOOR + 1.5), (0.98 * s, 4.3, FLOOR + 1.5), 0.018, "steel"))
        for yy in (0.4, 1.7, 3.0, 4.1):
            body.append(rod(f"stanchion{s}{yy}", (0.9 * s, yy, FLOOR + 1.45), (0.98 * s, yy, FLOOR + 1.5), 0.014, "steel", 8))
        body.append(rod(f"smokebox_rail{s}", (0.98 * s, 4.3, FLOOR + 1.5), (0.6 * s, 5.05, FLOOR + 1.8), 0.018, "steel"))
        body.append(rod(f"steampipe{s}", (0.6 * s, 4.05, FLOOR + 1.2), (1.0 * s, 4.0, 1.0), 0.07, "black_paint", 16))
    # cab: fixed backhead plate behind the boiler with spectacle windows, corner posts, roof beams, steps
    body.append(box("cab_front_mid", (1.66, 0.1, 2.55), (0, -0.25, FLOOR + 1.28), "loco_green", 0.02))
    for s in (-1, 1):
        body.append(cyl(f"spectacle{s}", 0.22, 0.12, (0.6 * s, -0.25, FLOOR + 2.15), "glass", axis="Y", verts=32))
        body.append(torus(f"spectacle_ring{s}", 0.23, 0.03, (0.6 * s, -0.31, FLOOR + 2.15), "brass", axis="Y"))
        body.append(box(f"cab_front_top{s}", (0.66, 0.1, 0.55), (1.17 * s, -0.25, FLOOR + 2.27), "loco_green", 0.01))
        for py in (-0.25, -3.9, -4.95):
            body.append(box(f"cab_post{s}{py}", (0.1, 0.1, 2.6), (1.48 * s, py, FLOOR + 1.3), "loco_green", 0.01))
        body.append(box(f"roof_beam{s}", (0.1, 4.7, 0.1), (1.48 * s, -2.6, FLOOR + 2.55), "loco_green", 0.01))
        body.append(box(f"cab_step{s}", (0.45, 0.6, 0.05), (1.55 * s, -4.45, 0.78), "black_paint", 0.01))
        body.append(box(f"cab_step2{s}", (0.45, 0.6, 0.05), (1.55 * s, -4.45, 0.35), "black_paint", 0.01))
        body.append(rod(f"cab_grab{s}", (1.6 * s, -3.95, FLOOR + 0.2), (1.6 * s, -3.95, FLOOR + 1.6), 0.018, "brass", 8))
    body += rivets_line("cabfront_riv", (-0.85, -0.31, FLOOR + 2.5), (0.85, -0.31, FLOOR + 2.5), 12)
    for k, x in enumerate((-0.35, 0.35)):
        body.append(cyl(f"gauge{k}", 0.11, 0.06, (x, -0.33, FLOOR + 1.55), "brass", axis="Y", verts=24))
        body.append(cyl(f"gaugeface{k}", 0.09, 0.02, (x, -0.37, FLOOR + 1.55), "dial", axis="Y", verts=24))
    body.append(rod("backhead_pipe", (-0.8, -0.34, FLOOR + 1.3), (0.8, -0.34, FLOOR + 1.3), 0.025, "copper"))
    # coal bunker at the back of the cab (it's a tank engine: no tender)
    body.append(box("bunker", (2.2, 0.6, 1.1), (0, -4.65, FLOOR + 0.55), "loco_green", 0.02))
    body.append(sphere("bunker_coal", 0.7, (0, -4.6, FLOOR + 1.05), "coal", scale=(1.7, 0.45, 0.35)))
    join("Locomotive", body, origin=(0, 0, 0))

    # --- breakable cover ---
    n = 0
    for i, (y0, y1) in enumerate(((-0.25, 1.3), (1.3, 2.75), (2.75, 4.0))):
        yc = (y0 + y1) / 2
        parts = [cyl(f"jacket{i}", 1.0, y1 - y0 - 0.03, (0, yc, FLOOR + 1.0), "loco_green", axis="Y", verts=48, bevel=0.01),
                 cyl(f"band{i}", 1.02, 0.08, (0, y0 + 0.06, FLOOR + 1.0), "black_paint", axis="Y", verts=48),
                 cyl(f"line_a{i}", 1.022, 0.015, (0, y0 + 0.015, FLOOR + 1.0), "lining", axis="Y", verts=48),
                 cyl(f"line_b{i}", 1.022, 0.015, (0, y0 + 0.105, FLOOR + 1.0), "lining", axis="Y", verts=48)]
        panel("Panel", "metal", n, parts)
        n += 1
    for s in (-1, 1):
        x = 1.5 * s
        parts = [box(f"cab_low{s}", (0.07, 3.45, 0.95), (x, -2.12, FLOOR + 0.48), "loco_green", 0.01),
                 box(f"cab_top{s}", (0.07, 3.45, 0.4), (x, -2.12, FLOOR + 2.3), "loco_green", 0.01),
                 box(f"cab_mid_a{s}", (0.07, 0.6, 0.9), (x, -0.7, FLOOR + 1.4), "loco_green", 0.01),
                 box(f"cab_mid_b{s}", (0.07, 0.6, 0.9), (x, -3.55, FLOOR + 1.4), "loco_green", 0.01)]
        # orange-black-orange lining panel on the cab side
        for (zc, h) in ((FLOOR + 0.48, 0.7),):
            for k, (inset, mtl) in enumerate(((0.0, "lining"), (0.03, "black_paint"), (0.06, "lining"))):
                w = 3.1 - inset * 2
                hh = h - inset * 2
                for (dz, dy, sz) in ((hh / 2, 0, (0.08, w, 0.015)), (-hh / 2, 0, (0.08, w, 0.015)),
                                     (0, w / 2, (0.08, 0.015, hh)), (0, -w / 2, (0.08, 0.015, hh))):
                    parts.append(box(f"cabline{s}{k}{dz}{dy}", sz, (x * 1.005, -2.12 + dy, zc + dz), mtl, 0.0))
        parts += rivets_line(f"cabriv{s}", (x * 1.03, -3.8, FLOOR + 2.45), (x * 1.03, -0.45, FLOOR + 2.45), 14)
        panel("Panel", "metal", n, parts)
        n += 1
    parts = [box("roof", (3.25, 4.7, 0.1), (0, -2.6, FLOOR + 2.67), "black_paint", 0.03),
             box("roof_lip", (3.35, 4.8, 0.04), (0, -2.6, FLOOR + 2.6), "loco_green", 0.01),
             box("roof_vent", (0.6, 0.8, 0.15), (0, -2.4, FLOOR + 2.78), "black_paint", 0.02)]
    for k in range(5):
        parts.append(box(f"roof_rib{k}", (3.25, 0.05, 0.03), (0, -4.6 + k * 1.0, FLOOR + 2.73), "iron", 0.005))
    panel("Panel", "metal", n, parts)
    # rear side doors (hinge at the front edge)
    for k, s in enumerate((-1, 1)):
        x = 1.5 * s
        panel("Door", "metal", k, [box(f"cab_door{s}", (0.06, 0.95, 1.9), (x, -4.43, FLOOR + 0.95), "loco_green", 0.01),
                                   box(f"door_win{s}", (0.08, 0.5, 0.45), (x, -4.43, FLOOR + 1.45), "glass", 0.005),
                                   box(f"door_winframe{s}", (0.07, 0.6, 0.55), (x * 0.999, -4.43, FLOOR + 1.45), "brass", 0.005),
                                   sphere(f"door_knob{s}", 0.045, (x + 0.05 * s, -4.78, FLOOR + 0.95), "brass")],
              origin=(x, -3.95, FLOOR + 0.95))
    # cab FRONT doors, one each side of the boiler, hinged at the outer edge, opening forward
    for k, s in enumerate((-1, 1)):
        x0, x1 = 0.84 * s, 1.46 * s
        xc = (x0 + x1) / 2
        w = abs(x1 - x0)
        panel("Door", "metal", 2 + k, [
            box(f"front_door{s}", (w, 0.05, 1.95), (xc, -0.25, FLOOR + 0.98), "loco_green", 0.01),
            box(f"front_door_win{s}", (w - 0.12, 0.06, 0.55), (xc, -0.25, FLOOR + 1.5), "glass", 0.005),
            box(f"front_door_frame{s}", (w - 0.06, 0.055, 0.62), (xc, -0.249, FLOOR + 1.5), "brass", 0.005),
            box(f"front_door_line{s}", (w - 0.1, 0.06, 0.015), (xc, -0.25, FLOOR + 0.5), "lining", 0.0),
            sphere(f"front_door_knob{s}", 0.04, (x0 + 0.06 * s, -0.19, FLOOR + 1.0), "brass")],
            origin=(x1, -0.25, FLOOR + 0.98))
    idx = 0
    for y in (3.5, 0.0, -3.5):
        for s in (-1, 1):
            loco_wheel(f"Wheel_{idx}", (0.85 * s, y, 0.5))
            idx += 1
    bake_and_export(os.path.join(OUT_TRAIN, "locomotive.glb"), 2048)


def build_wagon(kind):
    clear_scene()
    L = 8.0
    body = []
    underframe(L, body, buffer_beam="iron")
    bogie("b1", 2.8, body)
    bogie("b2", -2.8, body)
    plank_floor(L, body)
    later = []
    if kind == "cargo":
        for s in (-1, 1):
            for py in (-3.0, -1.0, 1.0, 3.0):
                body.append(box(f"post{s}{py}", (0.12, 0.12, 2.4), (1.44 * s, py, FLOOR + 1.2), "iron", 0.01))
                body += rivets_line(f"postriv{s}{py}", (1.51 * s, py, FLOOR + 0.2), (1.51 * s, py, FLOOR + 2.2), 6)
            body.append(box(f"top_beam{s}", (0.12, 6.2, 0.12), (1.44 * s, 0, FLOOR + 2.37), "iron", 0.01))
            for e in (-1, 1):
                body.append(box(f"step{s}{e}", (0.45, 0.6, 0.05), (1.45 * s, e * 3.5, 0.78), "iron", 0.01))
        for i in range(4):
            body.append(box(f"rib{i}", (2.95, 0.1, 0.1), (0, -3.0 + i * 2.0, FLOOR + 2.45), "iron", 0.01))
        for e in (-1, 1):
            for x in (-1.2, -0.4, 0.4, 1.2):
                body.append(box(f"endpost{e}{x}", (0.1, 0.1, 2.35), (x, e * 3.95, FLOOR + 1.17), "iron", 0.01))
            body.append(box(f"endplank{e}", (2.6, 0.05, 2.2), (0, e * 3.98, FLOOR + 1.12), "van_brown", 0.005))
        for s in (-1, 1):
            body.append(box(f"door_runner_top{s}", (0.06, 3.2, 0.06), (1.5 * s, 0.6, FLOOR + 2.28), "iron", 0.005))
            body.append(box(f"door_runner_bot{s}", (0.06, 3.2, 0.06), (1.5 * s, 0.6, FLOOR + 0.05), "iron", 0.005))
        for k in range(6):
            body.append(box(f"ladder_rung{k}", (0.4, 0.03, 0.03), (-0.9, -4.08, 0.9 + k * 0.35), "iron", 0.003))
        for x in (-1.1, -0.7):
            body.append(box(f"ladder_rail{x}", (0.03, 0.03, 2.1), (x, -4.08, 1.75), "iron", 0.003))
        # brake wheel on one end
        body.append(rod("brake_shaft", (1.1, -4.05, 0.9), (1.1, -4.05, FLOOR + 1.6), 0.03, "iron"))
        body.append(torus("brake_wheel", 0.22, 0.025, (1.1, -4.05, FLOOR + 1.6), "iron", axis="Z"))
        for i, (x, y) in enumerate([(-0.6, -2.0), (0.6, -1.0), (-0.5, 1.2), (0.55, 2.2)]):
            body.append(box(f"crate{i}", (0.9, 0.9, 0.8), (x, y, FLOOR + 0.4), "wood", 0.02))
            for zz in (0.12, 0.68):
                body.append(box(f"crate_band{i}{zz}", (0.93, 0.93, 0.06), (x, y, FLOOR + zz), "iron", 0.005))
        body.append(sphere("coal_pile", 0.7, (0.4, -0.2, FLOOR + 0.1), "coal", scale=(1.2, 1.4, 0.55)))
        for s in (-1, 1):
            for y in (-2.0, 2.0):
                later.append(("Panel", "wood", plank_wall(f"w{s}{y}", s, y, 1.9), None))
            door = plank_wall(f"d{s}", s, 0.0, 1.9)
            door.append(rod(f"door_x{s}", (1.49 * s, -0.85, FLOOR + 0.3), (1.49 * s, 0.85, FLOOR + 2.0), 0.03, "wood_dark", 6))
            door.append(box(f"door_handle{s}", (0.05, 0.05, 0.3), (1.52 * s, 0.8, FLOOR + 1.1), "iron", 0.005))
            later.append(("Door", "wood", door, (1.42 * s, -0.95, FLOOR + 1.15)))
        for y in (-1.6, 1.6):
            roof = [box(f"roof{y}", (3.1, 3.2, 0.06), (0, y, FLOOR + 2.55), "roof_grey", 0.02)]
            for k in range(6):
                roof.append(box(f"roofseam{y}{k}", (3.1, 0.04, 0.03), (0, y - 1.5 + k * 0.6, FLOOR + 2.6), "iron", 0.005))
            later.append(("Panel", "metal", roof, None))
    elif kind == "utility":
        for s in (-1, 1):
            for py in (-3.0, 0.0, 3.0):
                body.append(box(f"post{s}{py}", (0.1, 0.1, 2.6), (1.38 * s, py, FLOOR + 1.3), "iron", 0.01))
            body.append(box(f"top_beam{s}", (0.1, 6.1, 0.1), (1.38 * s, 0, FLOOR + 2.55), "iron", 0.01))
            for e in (-1, 1):
                body.append(box(f"step{s}{e}", (0.45, 0.6, 0.05), (1.45 * s, e * 3.5, 0.78), "iron", 0.01))
            for y in (-1.5, 1.5):
                boards = []
                for k in range(3):
                    boards.append(box(f"board{s}{y}{k}", (0.06, 2.9, 0.22), (1.4 * s, y, FLOOR + 0.13 + k * 0.25), "wood" if k % 2 else "wood_grey", 0.006))
                boards += rivets_line(f"boardriv{s}{y}", (1.44 * s, y - 1.35, FLOOR + 0.4), (1.44 * s, y + 1.35, FLOOR + 0.4), 8)
                later.append(("Panel", "wood", boards, None))
        # tool rack and hanging tools
        body.append(box("rack", (0.08, 1.6, 0.9), (1.25, -1.6, FLOOR + 1.5), "wood_dark", 0.01))
        for k in range(4):
            body.append(rod(f"tool{k}", (1.2, -2.2 + k * 0.4, FLOOR + 1.9), (1.2, -2.2 + k * 0.4, FLOOR + 1.2), 0.02, "wood", 8))
        body.append(box("toolbox", (0.6, 0.35, 0.3), (-0.9, 3.4, FLOOR + 0.15), "red_paint", 0.02))
        body.append(box("bench_top", (0.7, 1.6, 0.08), (-1.0, 1.0, FLOOR + 0.85), "wood_dark", 0.01))
        for y in (0.3, 1.7):
            body.append(box(f"bench_leg{y}", (0.6, 0.08, 0.85), (-1.0, y, FLOOR + 0.42), "iron", 0.01))
        body.append(box("vice", (0.15, 0.2, 0.15), (-0.75, 1.6, FLOOR + 0.97), "blue_paint", 0.01))
        for k, y in enumerate((-3.3, -2.8)):
            body.append(cyl(f"barrel{k}", 0.28, 0.75, (0.9, y, FLOOR + 0.38), "wood", verts=20))
            for zz in (0.15, 0.6):
                body.append(torus(f"barrelband{k}{zz}", 0.285, 0.015, (0.9, y, FLOOR + zz), "iron", axis="Z", seg=20))
        for y in (-1.6, 1.6):
            canvas = [box(f"canopy{y}", (3.0, 3.2, 0.05), (0, y, FLOOR + 2.65), "canvas", 0.02)]
            for k in range(4):
                canvas.append(rod(f"canopy_bow{y}{k}", (-1.45, y - 1.2 + k * 0.8, FLOOR + 2.62), (1.45, y - 1.2 + k * 0.8, FLOOR + 2.62), 0.02, "wood_dark", 6))
            later.append(("Panel", "metal", canvas, None))
    elif kind == "container":
        body.append(box("inner", (2.3, 6.2, 2.15), (0, 0, FLOOR + 1.1), "wood_dark", 0.01))
        for s in (-1, 1):
            for py in (-3.2, -1.07, 1.07, 3.2):
                body.append(box(f"cpost{s}{py}", (0.12, 0.12, 2.35), (1.28 * s, py, FLOOR + 1.17), "rust", 0.01))
        for e in (-3.25, 3.25):
            for zz in (FLOOR + 0.05, FLOOR + 2.3):
                body.append(box(f"crail{e}{zz}", (2.6, 0.12, 0.12), (0, e, zz), "rust", 0.01))
        for s in (-1, 1):
            for j, yc in enumerate((-2.13, 0.0, 2.13)):
                parts = [box(f"cpan{s}{j}", (0.04, 2.0, 2.1), (1.27 * s, yc, FLOOR + 1.12), "rust", 0.005)]
                for r in range(10):
                    parts.append(box(f"crib{s}{j}{r}", (0.05, 0.08, 2.05), (1.3 * s, yc - 0.9 + r * 0.2, FLOOR + 1.12), "rust", 0.004))
                later.append(("Panel", "metal", parts, None))
        later.append(("Panel", "metal", [box("croof", (2.6, 6.5, 0.06), (0, 0, FLOOR + 2.33), "rust", 0.01)], None))
        doors = [box("doors", (2.3, 0.05, 2.1), (0, -3.25, FLOOR + 1.12), "rust", 0.005),
                 box("door_split", (0.03, 0.06, 2.1), (0, -3.28, FLOOR + 1.12), "iron", 0.003),
                 box("padlock", (0.2, 0.1, 0.25), (0.15, -3.36, FLOOR + 1.1), "brass", 0.02),
                 torus("shackle", 0.07, 0.02, (0.15, -3.36, FLOOR + 1.27), "steel", axis="Y")]
        for sx in (-0.6, -0.2, 0.2, 0.6):
            doors.append(rod(f"lockbar{sx}", (sx, -3.32, FLOOR + 0.1), (sx, -3.32, FLOOR + 2.15), 0.025, "steel", 8))
        for k in range(5):
            doors.append(torus(f"chain{k}", 0.06, 0.015, (-1.0 + k * 0.12, -3.36, FLOOR + 1.3 - abs(k - 2) * 0.05), "steel", axis="Z" if k % 2 else "Y", seg=12))
        later.append(("Panel", "metal", doors, None))
    join(kind.capitalize(), body, origin=(0, 0, 0))
    counters = {}
    for kind_name, mat_kind, parts, origin in later:
        counters[kind_name] = counters.get(kind_name, 0)
        panel(kind_name, mat_kind, counters[kind_name], parts, origin)
        counters[kind_name] += 1
    m = 0
    for y in (2.8, -2.8):
        for yy in (y - 0.6, y + 0.6):
            for s in (-1, 1):
                wagon_wheel(f"WagonWheel_{m}", (0.85 * s, yy, 0.38))
                m += 1
    bake_and_export(os.path.join(OUT_TRAIN, f"{kind}_wagon.glb"), 2048)


# --- Props and tools ----------------------------------------------------------------------

def build_props():
    clear_scene()
    loco_wheel("Wheel", (0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "wheel.glb"), 1024)

    build_items()

    clear_scene()
    # forged claw hammer: hickory handle with leather grip, steel head with curved claw
    parts = [cyl("handle", 0.022, 0.5, (0, 0, 0.02), "wood", verts=16, radius2=0.018),
             cyl("grip", 0.027, 0.18, (0, 0, -0.16), "leather", verts=16),
             box("head", (0.14, 0.045, 0.05), (0.03, 0, 0.29), "steel", 0.008),
             cyl("face", 0.03, 0.04, (0.12, 0, 0.29), "steel", axis="X", verts=16),
             box("wedge", (0.02, 0.046, 0.02), (0.0, 0, 0.32), "wood_dark", 0.002)]
    for k in range(4):
        a = math.radians(-10 - k * 14)
        parts.append(box(f"claw{k}", (0.04, 0.04, 0.025), (-0.06 - k * 0.03, 0, 0.3 - k * k * 0.006), "steel", 0.004, rot=(0, a, 0)))
    for k in range(5):
        parts.append(torus(f"wrap{k}", 0.028, 0.004, (0, 0, -0.24 + k * 0.035), "leather", axis="Z", seg=16))
    join("Hammer", parts, origin=(0, 0, -0.2))
    bake_and_export(os.path.join(OUT_PROPS, "hammer.glb"), 512)

    clear_scene()
    # welding torch (stinger): insulated grip, clamp jaws, cable stub; nozzle points forward (+Y)
    parts = [cyl("grip", 0.035, 0.2, (0, -0.06, 0), "rubber", axis="Y", verts=16),
             cyl("guard", 0.05, 0.02, (0, 0.05, 0), "blue_paint", axis="Y", verts=16),
             cyl("neck", 0.018, 0.2, (0, 0.15, 0.02), "brass", axis="Y", verts=12),
             box("jaw_top", (0.03, 0.07, 0.015), (0, 0.27, 0.035), "brass", 0.003),
             box("jaw_bot", (0.03, 0.07, 0.015), (0, 0.27, 0.005), "brass", 0.003),
             rod("electrode", (0, 0.28, 0.02), (0, 0.42, 0.02), 0.004, "steel", 6),
             cyl("cable_stub", 0.02, 0.1, (0, -0.2, 0), "rubber", axis="Y", verts=12)]
    for k in range(4):
        parts.append(torus(f"ridge{k}", 0.035, 0.004, (0, -0.13 + k * 0.04, 0), "rubber", axis="Y", seg=16))
    join("WelderTorch", parts, origin=(0, -0.1, 0))
    bake_and_export(os.path.join(OUT_PROPS, "welder_torch.glb"), 512)

    clear_scene()
    # diesel welding generator on a tubular frame with gauges, exhaust and cable reel
    parts = [box("case", (0.9, 0.55, 0.55), (0, 0, 0.42), "orange_paint", 0.02),
             box("panel", (0.6, 0.03, 0.32), (0, -0.29, 0.45), "black_paint", 0.005),
             cyl("exhaust", 0.03, 0.25, (0.32, 0.12, 0.8), "iron", verts=10),
             box("vents", (0.4, 0.02, 0.15), (-0.15, 0.285, 0.45), "black_paint", 0.003)]
    for k, x in enumerate((-0.18, 0.05)):
        parts.append(cyl(f"gauge{k}", 0.06, 0.03, (x, -0.31, 0.5), "brass", axis="Y", verts=20))
        parts.append(cyl(f"gface{k}", 0.05, 0.01, (x, -0.33, 0.5), "dial", axis="Y", verts=20))
    parts.append(cyl("knob", 0.035, 0.04, (0.22, -0.32, 0.42), "black_paint", axis="Y", verts=12))
    for s in (-1, 1):
        parts.append(rod(f"frame_a{s}", (0.5 * s, -0.33, 0.1), (0.5 * s, -0.33, 0.78), 0.02, "iron"))
        parts.append(rod(f"frame_b{s}", (0.5 * s, 0.33, 0.1), (0.5 * s, 0.33, 0.78), 0.02, "iron"))
        parts.append(rod(f"frame_c{s}", (0.5 * s, -0.33, 0.78), (0.5 * s, 0.33, 0.78), 0.02, "iron"))
        parts.append(rod(f"skid{s}", (0.5 * s, -0.33, 0.1), (0.5 * s, 0.33, 0.1), 0.025, "iron"))
    parts.append(rod("handle", (-0.5, 0, 0.78), (0.5, 0, 0.78), 0.02, "iron"))
    parts.append(cyl("reel", 0.24, 0.2, (0, 0.5, 0.42), "iron", axis="X", verts=24))
    parts.append(torus("cable_coil", 0.19, 0.045, (0, 0.5, 0.42), "rubber", axis="X"))
    parts.append(torus("cable_coil2", 0.14, 0.04, (0, 0.5, 0.42), "rubber", axis="X"))
    join("WelderMachine", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "welder_machine.glb"), 1024)

    clear_scene()
    # pneumatic nail gun: body, handle, magazine, nose, hose fitting
    parts = [box("body", (0.07, 0.3, 0.12), (0, 0.0, 0.06), "orange_paint", 0.02),
             cyl("cap", 0.065, 0.06, (0, -0.1, 0.11), "black_paint", verts=20),
             box("handle", (0.05, 0.08, 0.16), (0, -0.08, -0.06), "rubber", 0.015),
             box("trigger", (0.015, 0.03, 0.04), (0, -0.02, -0.02), "black_paint", 0.003),
             box("nose", (0.04, 0.06, 0.12), (0, 0.16, 0.0), "steel", 0.005),
             box("magazine", (0.035, 0.28, 0.04), (0, 0.04, -0.07), "black_paint", 0.005),
             cyl("fitting", 0.012, 0.05, (0, -0.1, -0.16), "brass", verts=10)]
    join("NailGun", parts, origin=(0, -0.08, -0.06))
    bake_and_export(os.path.join(OUT_PROPS, "nail_gun.glb"), 512)

    clear_scene()
    # heavy adjustable wrench: long handle along Z, open jaw at the top
    parts = [box("handle", (0.035, 0.018, 0.34), (0, 0, 0.0), "steel", 0.006),
             box("grip", (0.042, 0.024, 0.16), (0, 0, -0.11), "red_paint", 0.008),
             box("head", (0.09, 0.03, 0.07), (0.01, 0, 0.2), "steel", 0.008),
             box("jaw_fixed", (0.025, 0.03, 0.07), (-0.035, 0, 0.26), "steel", 0.006),
             box("jaw_move", (0.025, 0.03, 0.06), (0.045, 0, 0.255), "steel", 0.006),
             cyl("worm", 0.012, 0.05, (0.0, 0, 0.215), "brass", axis="X", verts=10)]
    join("Wrench", parts, origin=(0, 0, -0.12))
    bake_and_export(os.path.join(OUT_PROPS, "wrench.glb"), 512)


def build_items():
    """The build items a player carries and places on a broken piece of track."""
    build_plank()
    build_rail()
    build_fasteners()
    build_panel()


def build_plank():
    """plank.glb: a creosoted timber sleeper, 2.4 x 0.3 x 0.12 m (the same size as the intact track's sleepers): chamfered
    edges, darker end grain, a few seasoning cracks along the top, and two cast tie plates where the rails sit
    (x = +-0.95, under the rails at +-0.85; the game drives a nail into each plate). Origin at the centre."""
    clear_scene()
    parts = [box("sleeper", (2.4, 0.3, 0.12), (0, 0, 0), "sleeper_wood", 0.022)]
    for sx in (-1, 1):
        parts.append(box(f"endgrain{sx}", (0.012, 0.27, 0.1), (sx * 1.198, 0, 0), "wood_end", 0.004))
    rng = random.Random(7)
    for k in range(5):
        x = rng.uniform(-1.05, 1.05)
        if abs(abs(x) - 0.95) < 0.2:
            x += 0.3 * (1 if x >= 0 else -1)
        parts.append(box(f"crack{k}", (rng.uniform(0.25, 0.6), 0.008, 0.01), (x, rng.uniform(-0.09, 0.09), 0.057),
                         "wood_end", 0.0, rot=(0, 0, math.radians(rng.uniform(-3, 3)))))
    for sx in (-1, 1):
        x = sx * 0.95
        parts.append(box(f"plate{sx}", (0.26, 0.32, 0.018), (x, 0, 0.069), "tie_plate", 0.005))
        for dx in (-0.075, 0.075):  # shoulders either side of the rail seat (rail at +-0.85)
            parts.append(box(f"shoulder{sx}{dx}", (0.018, 0.3, 0.02), (sx * 0.85 + dx * 1.13, 0, 0.086), "tie_plate", 0.004))
        for dy in (-0.11, 0.11):
            parts.append(cyl(f"hole{sx}{dy}", 0.014, 0.004, (x + sx * 0.08, dy, 0.079), "coal", verts=10, bevel=0.0))
    join("Plank", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "plank.glb"), 1024, repack=True)


def build_rail():
    """A 4 m length of flat-bottom rail: a rounded, worn steel head, a rusty web and foot, bolt holes and fishplates
    at both ends (where the game bolts it), so a placed rail reads as a real rail instead of a bar. Each fishplate
    carries its outer bolt; the inner bolt (y = +-1.71) is the one the player drives in (track_bolt.glb, NailSpot)."""
    clear_scene()
    parts = [box("rail_head", (0.075, 4.0, 0.045), (0, 0, 0.052), "rail_steel", 0.016),
             box("rail_head_top", (0.06, 3.99, 0.012), (0, 0, 0.076), "steel", 0.005),
             box("rail_web", (0.026, 4.0, 0.075), (0, 0, 0.0), "rust", 0.006),
             box("rail_neck", (0.045, 4.0, 0.02), (0, 0, 0.03), "rust", 0.006),
             box("rail_foot", (0.15, 4.0, 0.018), (0, 0, -0.048), "rust", 0.006),
             box("rail_foot_slope", (0.07, 4.0, 0.016), (0, 0, -0.034), "rust", 0.006)]
    for end in (-1, 1):
        y = end * 1.82
        for sx in (-1, 1):
            parts.append(box(f"fish{end}{sx}", (0.012, 0.42, 0.055), (sx * 0.022, y, 0.0), "iron", 0.004))
        # outer bolt with its nuts; an empty hole for the inner one
        yo = y + end * 0.11
        parts.append(cyl(f"bolt{end}", 0.012, 0.08, (0, yo, 0.0), "steel", axis="X", verts=8))
        for sx in (-1, 1):
            parts.append(cyl(f"nut{end}{sx}", 0.018, 0.012, (sx * 0.034, yo, 0.0), "iron", axis="X", verts=6))
            parts.append(cyl(f"hole{end}{sx}", 0.011, 0.003, (sx * 0.0285, y - end * 0.11, 0.0), "coal", axis="X", verts=10, bevel=0.0))
    join("Rail", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "rail.glb"), 1024, repack=True)


def build_fasteners():
    """track_spike.glb: a cut track spike (square shank with a chisel tip and an offset head), tip at the origin,
    head up (+Z, Godot +Y), 0.25 m long. track_bolt.glb: a fishplate bolt with a square head and a washer, the shank
    along -X (Godot -X) from the washer face at the origin, so it is driven in by moving it along -X."""
    clear_scene()
    parts = [box("shank", (0.018, 0.018, 0.21), (0, 0, 0.125), "spike_steel", 0.002),
             box("tip", (0.018, 0.01, 0.03), (0, 0, 0.012), "spike_steel", 0.002, rot=(math.radians(10), 0, 0)),
             box("head", (0.05, 0.03, 0.02), (0.012, 0, 0.24), "spike_steel", 0.005),
             box("head_lip", (0.02, 0.03, 0.014), (0.032, 0, 0.226), "spike_steel", 0.004)]
    join("TrackSpike", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "track_spike.glb"), 256)

    clear_scene()
    parts = [cyl("shank", 0.012, 0.15, (-0.075, 0, 0), "steel", axis="X", verts=12),
             box("head", (0.022, 0.04, 0.04), (0.016, 0, 0), "spike_steel", 0.004),
             cyl("washer", 0.024, 0.005, (0.0025, 0, 0), "iron", axis="X", verts=16)]
    for k in range(6):  # thread rings near the end
        parts.append(torus(f"thread{k}", 0.012, 0.0018, (-0.12 - k * 0.006, 0, 0), "steel", axis="X", seg=12))
    join("TrackBolt", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "track_bolt.glb"), 256)


def build_panel():
    """panel.glb: the spare cover panel from the cargo car (fits any missing wall piece): 1.6 x 1.0 m of tongue-and-
    groove boards on two battens, with iron corner straps and carriage bolts. Upright, facing -Y (Godot +Z)."""
    clear_scene()
    parts = []
    for k in range(6):
        z = -0.5 + 0.0835 + k * 0.1667
        parts.append(box(f"board{k}", (1.6, 0.06, 0.16), (0, 0, z), "wood" if k % 2 else "wood_dark", 0.012))
    for x in (-0.55, 0.55):
        parts.append(box(f"batten{x}", (0.12, 0.04, 0.96), (x, 0.045, 0), "wood_dark", 0.01))
    for z in (-0.3, 0.3):
        parts.append(box(f"strap{z}", (1.64, 0.012, 0.09), (0, -0.036, z), "iron", 0.004))
        for x in (-0.7, -0.25, 0.25, 0.7):
            parts.append(cyl(f"bolt{z}{x}", 0.018, 0.012, (x, -0.044, z), "steel", axis="Y", verts=10))
    join("Panel", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "panel.glb"), 1024, repack=True)


# --- Trackside pickups: gold ore, coal, scrap, planks, nails, supply crate ----------------------

def lump(name, radius, loc, material, scale=(1, 1, 1), jitter=0.22, subdiv=2, seed=0):
    """Irregular rock / ore lump: an icosphere with its vertices pushed in and out (flat shaded, chunky)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    rng = random.Random(seed)
    for v in obj.data.vertices:
        k = 1.0 + rng.uniform(-jitter, jitter)
        v.co = v.co * k
    obj.name = name
    obj.data.materials.append(mat(material))
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def build_gold_ore():
    """gold_ore.glb: a dark boulder crusted all over its upper half with gold nuggets of many sizes, plus a few loose
    crumbs at its foot, so it reads as gold from every side (no evenly spaced round "eyes")."""
    clear_scene()
    parts = [lump("boulder", 0.8, (0, 0, 0.62), "ore_rock", (1.15, 0.95, 0.85), 0.14, 3, 11),
             lump("boulder2", 0.5, (0.62, 0.38, 0.33), "ore_rock", (1.0, 0.9, 0.75), 0.2, 2, 12),
             lump("boulder3", 0.38, (-0.72, -0.34, 0.25), "ore_rock", (1.1, 0.9, 0.7), 0.22, 2, 13)]
    rng = random.Random(5)
    golden = 2.39996  # golden-angle spiral: even but irregular-looking cover
    for k in range(34):
        t = (k + 0.5) / 34.0
        zc = 0.15 + 0.85 * t          # 0.15..1 of the way up the boulder
        ring = math.sqrt(max(1.0 - zc * zc, 0.0))
        a = k * golden + rng.uniform(-0.3, 0.3)
        nx, ny, nz = math.cos(a) * ring, math.sin(a) * ring, zc
        sx, sy, sz = 0.8 * 1.15, 0.8 * 0.95, 0.8 * 0.85
        p = (nx * sx * 0.97, ny * sy * 0.97, 0.62 + nz * sz * 0.97)
        r = rng.uniform(0.06, 0.1) if k % 4 else rng.uniform(0.12, 0.17)
        parts.append(lump(f"nugget{k}", r, p, "gold_ore", (1.25, 1.0, 0.65), 0.35, 1, 100 + k))
    for k in range(6):
        a = rng.uniform(0, math.tau)
        parts.append(lump(f"crumb{k}", rng.uniform(0.06, 0.1), (math.cos(a) * 1.05, math.sin(a) * 0.95, 0.05), "gold_ore", (1, 1, 0.6), 0.3, 1, 300 + k))
    join("GoldOre", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "gold_ore.glb"), 1024)


def build_pickups():
    build_gold_ore()

    # coal: a heap of glossy black lumps on a few sacking scraps
    clear_scene()
    parts = [box("sack", (0.8, 0.7, 0.02), (0, 0, 0.01), "canvas", 0.01, rot=(0, 0, math.radians(12)))]
    rng = random.Random(9)
    for k in range(22):
        ring = 0 if k < 5 else (1 if k < 13 else 2)
        a = rng.uniform(0, math.tau)
        d = (0.05, 0.2, 0.32)[ring]
        z = (0.24, 0.14, 0.07)[ring] + rng.uniform(-0.03, 0.03)
        parts.append(lump(f"coal{k}", rng.uniform(0.07, 0.12), (math.cos(a) * d, math.sin(a) * d, z), "coal_lump", (1.2, 1.0, 0.8), 0.3, 1, 400 + k))
    join("CoalPile", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "coal_pile.glb"), 512)

    # scrap: a bent plate, a rail offcut, a cog, a pipe and loose bolts
    clear_scene()
    parts = [box("plate", (0.5, 0.36, 0.02), (0.02, 0.02, 0.05), "rust", 0.006, rot=(math.radians(8), math.radians(-6), math.radians(20))),
             box("plate_bend", (0.18, 0.36, 0.02), (0.3, 0.1, 0.12), "rust", 0.006, rot=(math.radians(8), math.radians(-40), math.radians(20))),
             box("offcut_head", (0.06, 0.6, 0.04), (-0.18, -0.05, 0.12), "rail_steel", 0.01, rot=(0, 0, math.radians(-35))),
             box("offcut_web", (0.022, 0.6, 0.06), (-0.18, -0.05, 0.08), "rust", 0.004, rot=(0, 0, math.radians(-35))),
             box("offcut_foot", (0.12, 0.6, 0.016), (-0.18, -0.05, 0.045), "rust", 0.004, rot=(0, 0, math.radians(-35))),
             cyl("cog", 0.13, 0.04, (0.12, -0.2, 0.2), "iron", verts=24, rot=(math.radians(70), 0, math.radians(15))),
             cyl("cog_hub", 0.04, 0.07, (0.12, -0.2, 0.2), "steel", verts=12, rot=(math.radians(70), 0, math.radians(15))),
             rod("pipe", (-0.3, 0.25, 0.05), (0.15, 0.32, 0.18), 0.04, "black_paint", 14)]
    for k in range(10):
        a = math.tau * k / 10
        parts.append(box(f"tooth{k}", (0.05, 0.04, 0.04), (0.12 + math.cos(a) * 0.15, -0.2 + math.sin(a) * 0.05, 0.2 + math.sin(a) * 0.14), "iron", 0.004,
                         rot=(math.radians(70), 0, math.radians(15))))
    for k, (x, y) in enumerate(((0.3, -0.3), (-0.35, -0.25), (0.05, 0.38), (-0.05, -0.35))):
        parts.append(cyl(f"bolt{k}", 0.014, 0.1, (x, y, 0.02), "steel", axis="X", verts=8, rot=(0, math.radians(90), k * 0.9)))
        parts.append(cyl(f"nut{k}", 0.024, 0.02, (x + 0.04, y, 0.02), "iron", verts=6, rot=(0, math.radians(90), k * 0.9)))
    join("ScrapPile", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "scrap_pile.glb"), 512)

    # planks: a bundle of five boards tied with two rope bands
    clear_scene()
    parts = []
    for k, (y, z) in enumerate(((-0.1, 0.04), (0.0, 0.04), (0.1, 0.04), (-0.05, 0.11), (0.05, 0.11))):
        parts.append(box(f"board{k}", (1.2 + 0.04 * (k % 2), 0.095, 0.06), (0.02 * (k - 2), y, z), "wood_grey" if k % 2 else "wood", 0.006))
    for x in (-0.38, 0.38):
        parts.append(box(f"band{x}", (0.04, 0.3, 0.02), (x, 0, 0.15), "rope", 0.006))
        for sy in (-1, 1):
            parts.append(box(f"band_side{x}{sy}", (0.04, 0.02, 0.15), (x, sy * 0.15, 0.08), "rope", 0.006))
        parts.append(box(f"band_knot{x}", (0.06, 0.05, 0.035), (x, 0.0, 0.165), "rope", 0.012))
    join("WoodBundle", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "wood_bundle.glb"), 512)

    # nails: a small open slatted crate with a heap of nail heads and a paper label
    clear_scene()
    parts = [box("bottom", (0.6, 0.45, 0.03), (0, 0, 0.015), "wood_dark", 0.005)]
    for sy in (-1, 1):
        for k in range(2):
            parts.append(box(f"side{sy}{k}", (0.6, 0.025, 0.14), (0, sy * 0.212, 0.09 + k * 0.16), "wood", 0.006))
    for sx in (-1, 1):
        for k in range(2):
            parts.append(box(f"end{sx}{k}", (0.025, 0.45, 0.14), (sx * 0.29, 0, 0.09 + k * 0.16), "wood", 0.006))
        parts.append(box(f"handle{sx}", (0.03, 0.18, 0.04), (sx * 0.31, 0, 0.3), "wood_dark", 0.008))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"corner{sx}{sy}", (0.035, 0.035, 0.34), (sx * 0.285, sy * 0.208, 0.17), "iron", 0.004))
    parts.append(box("heap", (0.52, 0.38, 0.04), (0, 0, 0.27), "steel", 0.02))
    rng = random.Random(3)
    for k in range(26):
        x, y = rng.uniform(-0.23, 0.23), rng.uniform(-0.16, 0.16)
        parts.append(cyl(f"head{k}", 0.018, 0.008, (x, y, 0.295 + rng.uniform(0, 0.02)), "steel", verts=8, rot=(rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0)))
    parts.append(box("label", (0.3, 0.004, 0.09), (0, -0.226, 0.17), "paper", 0.002))
    parts.append(box("label_band", (0.3, 0.006, 0.02), (0, -0.227, 0.2), "signal_red", 0.002))
    join("NailsBox", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "nails_box.glb"), 512)

    # supply crate: a sturdy plank crate with iron corners, a stencil band and a canvas tarp roped on top
    clear_scene()
    w, d, h = 1.0, 0.8, 0.62
    parts = [box("core", (w - 0.04, d - 0.04, h - 0.04), (0, 0, h / 2), "wood_dark", 0.01)]
    for k in range(3):
        z = 0.1 + k * 0.21
        for sy in (-1, 1):
            parts.append(box(f"slat_y{sy}{k}", (w, 0.03, 0.19), (0, sy * d / 2, z), "wood", 0.008))
        for sx in (-1, 1):
            parts.append(box(f"slat_x{sx}{k}", (0.03, d, 0.19), (sx * w / 2, 0, z), "wood", 0.008))
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"post{sx}{sy}", (0.07, 0.07, h + 0.02), (sx * (w / 2 - 0.01), sy * (d / 2 - 0.01), h / 2), "wood_dark", 0.01))
            parts.append(box(f"cap{sx}{sy}", (0.09, 0.09, 0.08), (sx * (w / 2 - 0.01), sy * (d / 2 - 0.01), h - 0.02), "iron", 0.008))
            parts.append(box(f"foot{sx}{sy}", (0.09, 0.09, 0.08), (sx * (w / 2 - 0.01), sy * (d / 2 - 0.01), 0.04), "iron", 0.008))
    parts.append(box("band", (w + 0.02, d + 0.02, 0.05), (0, 0, h * 0.55), "signal_red", 0.004))
    parts.append(box("tarp", (w - 0.06, d - 0.04, 0.1), (0, 0, h + 0.04), "canvas", 0.04))
    parts.append(box("tarp_hang", (w - 0.2, 0.03, 0.16), (0, -d / 2 - 0.01, h - 0.04), "canvas", 0.01))
    for x in (-0.25, 0.25):
        parts.append(box(f"rope{x}", (0.03, d + 0.06, 0.03), (x, 0, h + 0.1), "rope", 0.008))
    join("SupplyCrate", parts, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "supply_crate.glb"), 1024)


# --- Locked track gate, its signal post and the key ------------------------------------------

def build_gate_props():
    """track_gate.glb: a heavy striped timber boom across the rails, hinged on a timber post (with a lantern and a
    counterweight) and padlocked into a steel cradle on the far post. Separate nodes for the game to animate:
    GateFrame (static), Boom (origin = hinge pin, swings up about the track axis), Padlock (origin = shackle top),
    Lamp (the lantern lens, recoloured red / green in Godot).
    gate_signal.glb: the warning signal post 120 m before the gate (Lens = recoloured in Godot).
    gate_key.glb: the big iron key with a brass bow and a paper tag (upright, origin in the middle)."""
    clear_scene()
    hx, rx, pz = -2.35, 2.35, 1.05      # hinge post x, rest post x, boom pivot height
    ground = -0.38
    frame = []
    for x, h in ((hx, 2.05), (rx, 1.12)):
        frame.append(box(f"footing{x}", (0.7, 0.7, 0.35), (x, 0, ground - 0.05), "concrete", 0.04))
        frame.append(box(f"post{x}", (0.34, 0.34, h), (x, 0, ground + 0.12 + h / 2), "wood_dark", 0.02))
        for k, zz in enumerate((ground + 0.4, ground + 0.12 + h - 0.25)):
            frame.append(box(f"band{x}{k}", (0.37, 0.37, 0.07), (x, 0, zz), "iron", 0.006))
            frame += rivets_line(f"bandriv{x}{k}", (x - 0.12, -0.19, zz), (x + 0.12, -0.19, zz), 3, "iron", 0.02)
        # raking strut so the post looks like it can take a hit
        frame.append(rod(f"strut{x}", (x, -0.75, ground + 0.05), (x, -0.12, ground + 0.95), 0.055, "wood", 8))
        frame.append(box(f"strut_shoe{x}", (0.2, 0.25, 0.08), (x, -0.78, ground + 0.06), "iron", 0.01))
    # hinge: two steel cheek plates with an axle pin along the track
    for sy in (-0.21, 0.21):
        frame.append(box(f"cheek{sy}", (0.42, 0.04, 0.42), (hx, sy, pz), "steel", 0.01))
        frame += rivets_line(f"cheekriv{sy}", (hx - 0.13, sy * 1.12, pz - 0.13), (hx + 0.13, sy * 1.12, pz - 0.13), 2, "iron", 0.02)
    frame.append(cyl("pin", 0.045, 0.56, (hx, 0, pz), "steel", axis="Y", verts=16))
    for sy in (-0.29, 0.29):
        frame.append(cyl(f"pin_nut{sy}", 0.07, 0.04, (hx, sy, pz), "iron", axis="Y", verts=6))
    # lantern on top of the hinge post
    top = ground + 0.12 + 2.05
    frame.append(box("lantern_base", (0.3, 0.3, 0.05), (hx, 0, top + 0.03), "black_paint", 0.01))
    frame.append(box("lantern_body", (0.24, 0.24, 0.3), (hx, 0, top + 0.2), "black_paint", 0.015))
    frame.append(cyl("lantern_roof", 0.2, 0.14, (hx, 0, top + 0.42), "black_paint", verts=4, radius2=0.04, rot=(0, 0, math.pi / 4)))
    frame.append(torus("lantern_handle", 0.07, 0.012, (hx, 0, top + 0.53), "iron", axis="Y", seg=16))
    frame.append(cyl("lantern_hood", 0.1, 0.08, (hx, -0.16, top + 0.24), "black_paint", axis="Y", verts=20))
    # rest post: steel fork cradle the boom drops into, with the hasp staple for the padlock
    rz = ground + 0.12 + 1.12
    frame.append(box("cradle_base", (0.36, 0.36, 0.06), (rx, 0, rz + 0.02), "steel", 0.01))
    for sy in (-0.15, 0.15):
        frame.append(box(f"fork{sy}", (0.3, 0.05, 0.26), (rx, sy, rz + 0.17), "steel", 0.008))
    frame.append(box("hasp_plate", (0.16, 0.03, 0.3), (rx, -0.2, rz - 0.1), "iron", 0.006))
    frame.append(torus("staple", 0.045, 0.014, (rx, -0.235, rz - 0.16), "steel", axis="X", seg=16))
    # warning plate on the hinge post
    frame.append(box("plate_back", (0.42, 0.02, 0.42), (hx, -0.18, ground + 1.55), "white_paint", 0.006, rot=(0, math.radians(45), 0)))
    frame.append(box("plate_rim", (0.3, 0.025, 0.3), (hx, -0.185, ground + 1.55), "signal_red", 0.004, rot=(0, math.radians(45), 0)))
    frame.append(box("plate_core", (0.2, 0.03, 0.2), (hx, -0.19, ground + 1.55), "white_paint", 0.004, rot=(0, math.radians(45), 0)))
    join("GateFrame", frame, origin=(0, 0, 0))

    join("Lamp", [cyl("lens", 0.075, 0.05, (hx, -0.13, top + 0.2), "lamp_red", axis="Y", verts=20),
                  cyl("lens_back", 0.075, 0.05, (hx, 0.13, top + 0.2), "lamp_red", axis="Y", verts=20)],
         origin=(hx, 0, top + 0.2))

    # the boom: a heavy timber beam painted in red / white stripes, steel bands at the joints, counterweight
    boom = []
    x0, x1 = hx + 0.25, rx + 0.12
    n = int(round((x1 - x0) / 0.5))
    seg = (x1 - x0) / n
    for k in range(n):
        boom.append(box(f"stripe{k}", (seg + 0.002, 0.24, 0.24), (x0 + seg * (k + 0.5), 0, pz),
                        "signal_red" if k % 2 == 0 else "white_paint", 0.012))
    for k in range(0, n + 1, 2):
        boom.append(box(f"sband{k}", (0.05, 0.26, 0.26), (x0 + seg * k, 0, pz), "iron", 0.006))
    boom.append(box("underchannel", (x1 - x0, 0.12, 0.05), ((x0 + x1) / 2, 0, pz - 0.14), "steel", 0.006))
    boom.append(box("hub", (0.42, 0.34, 0.3), (hx, 0, pz), "iron", 0.02))
    boom.append(box("tail", (0.7, 0.2, 0.2), (hx - 0.45, 0, pz), "wood_dark", 0.015))
    boom.append(box("counterweight", (0.38, 0.36, 0.46), (hx - 0.82, 0, pz - 0.05), "iron", 0.03))
    boom += rivets_line("cwriv", (hx - 0.95, -0.19, pz + 0.1), (hx - 0.69, -0.19, pz + 0.1), 3, "iron", 0.025)
    boom.append(box("hasp_strap", (0.08, 0.03, 0.36), (rx, -0.15, pz - 0.08), "iron", 0.006))
    boom.append(box("tip_cap", (0.05, 0.27, 0.27), (x1 + 0.01, 0, pz), "steel", 0.008))
    # diamond STOP plate hanging in the middle of the boom
    boom.append(box("stop_plate", (0.55, 0.03, 0.55), (0, -0.13, pz - 0.05), "signal_red", 0.01, rot=(0, math.radians(45), 0)))
    boom.append(box("stop_core", (0.36, 0.035, 0.36), (0, -0.14, pz - 0.05), "white_paint", 0.006, rot=(0, math.radians(45), 0)))
    boom.append(box("stop_bar", (0.26, 0.04, 0.07), (0, -0.15, pz - 0.05), "signal_red", 0.004))
    join("Boom", boom, origin=(hx, 0, pz))

    # a big brass padlock hanging from the staple, facing the train (-Y = towards the approaching train)
    lz = rz - 0.16
    lock = [box("lock_body", (0.24, 0.1, 0.22), (rx, -0.29, lz - 0.2), "brass", 0.03),
            box("lock_face", (0.2, 0.02, 0.18), (rx, -0.345, lz - 0.2), "brass", 0.01),
            box("keyhole", (0.025, 0.02, 0.06), (rx, -0.355, lz - 0.22), "black_paint", 0.003),
            cyl("keyhole_top", 0.022, 0.02, (rx, -0.355, lz - 0.18), "black_paint", axis="Y", verts=12)]
    for sx in (-0.07, 0.07):
        lock.append(rod(f"shackle_leg{sx}", (rx + sx, -0.27, lz - 0.1), (rx + sx, -0.27, lz + 0.02), 0.022, "steel", 10))
    lock.append(torus("shackle_top", 0.07, 0.022, (rx, -0.27, lz + 0.02), "steel", axis="Y", seg=20))
    lock += rivets_line("lockriv", (rx - 0.09, -0.35, lz - 0.28), (rx + 0.09, -0.35, lz - 0.28), 3, "brass", 0.012)
    join("Padlock", lock, origin=(rx, -0.27, lz + 0.08))
    bake_and_export(os.path.join(OUT_PROPS, "track_gate.glb"), 1024)

    clear_scene()
    # warning signal post: iron mast with a ladder, lamp case with a hood, red / white diamond board
    sig = [box("sig_footing", (0.5, 0.5, 0.3), (0, 0, -0.3), "concrete", 0.03),
           cyl("mast", 0.07, 3.4, (0, 0, 1.55), "black_paint", verts=12),
           box("sig_case", (0.36, 0.26, 0.6), (0, 0, 3.2), "black_paint", 0.03),
           cyl("sig_hood", 0.15, 0.16, (0, -0.2, 3.32), "black_paint", axis="Y", verts=20),
           box("backboard", (0.56, 0.03, 0.8), (0, 0.12, 3.2), "black_paint", 0.02),
           box("board", (0.6, 0.03, 0.6), (0, -0.08, 2.35), "white_paint", 0.01, rot=(0, math.radians(45), 0)),
           box("board_rim", (0.44, 0.035, 0.44), (0, -0.085, 2.35), "signal_red", 0.006, rot=(0, math.radians(45), 0)),
           box("board_core", (0.3, 0.04, 0.3), (0, -0.09, 2.35), "white_paint", 0.004, rot=(0, math.radians(45), 0)),
           box("board_bar", (0.06, 0.045, 0.24), (0, -0.095, 2.38), "black_paint", 0.004),
           box("board_dot", (0.06, 0.045, 0.06), (0, -0.095, 2.2), "black_paint", 0.004)]
    for k in range(7):
        sig.append(box(f"rung{k}", (0.3, 0.03, 0.03), (0, 0.1, 0.4 + k * 0.38), "iron", 0.004))
    for sx in (-0.15, 0.15):
        sig.append(box(f"rung_rail{sx}", (0.03, 0.03, 2.6), (sx, 0.1, 1.55), "iron", 0.004))
    join("SignalPost", sig, origin=(0, 0, 0))
    join("Lens", [cyl("sig_lens", 0.11, 0.04, (0, -0.14, 3.32), "lamp_red", axis="Y", verts=24)], origin=(0, -0.14, 3.32))
    bake_and_export(os.path.join(OUT_PROPS, "gate_signal.glb"), 512)

    clear_scene()
    # the key: big old iron key, brass trefoil bow, collar rings, toothed bit, and a paper tag on a string.
    # Upright (bow at the top), about 0.55 m tall so it reads from the cab.
    key = [torus("bow", 0.075, 0.022, (0, 0, 0.17), "brass", axis="Y", seg=28)]
    for k, (bx, bz) in enumerate(((0.075, 0.2), (-0.075, 0.2), (0, 0.26))):
        key.append(torus(f"lobe{k}", 0.035, 0.016, (bx, 0, bz), "brass", axis="Y", seg=18))
    key.append(cyl("collar1", 0.03, 0.03, (0, 0, 0.085), "brass", verts=16))
    key.append(cyl("collar2", 0.026, 0.02, (0, 0, 0.055), "iron", verts=16))
    key.append(cyl("shank", 0.017, 0.33, (0, 0, -0.1), "iron", verts=14))
    key.append(sphere("tip", 0.022, (0, 0, -0.265), "iron", seg=12))
    key.append(box("bit", (0.1, 0.022, 0.08), (0.055, 0, -0.22), "iron", 0.006))
    for k, (tx, tz) in enumerate(((0.09, -0.27), (0.11, -0.2), (0.09, -0.18))):
        key.append(box(f"tooth{k}", (0.025, 0.024, 0.03), (tx, 0, tz), "iron", 0.004))
    key.append(rod("string", (-0.07, 0, 0.2), (-0.16, 0.0, 0.08), 0.006, "canvas", 6))
    key.append(box("tag", (0.1, 0.012, 0.15), (-0.19, 0, 0.0), "paper", 0.01, rot=(0, math.radians(-14), 0)))
    key.append(box("tag_stripe", (0.1, 0.016, 0.025), (-0.188, 0, 0.045), "signal_red", 0.002, rot=(0, math.radians(-14), 0)))
    key.append(torus("tag_eye", 0.012, 0.004, (-0.172, 0, 0.068), "brass", axis="Y", seg=12))
    join("GateKey", key, origin=(0, 0, 0))
    bake_and_export(os.path.join(OUT_PROPS, "gate_key.glb"), 512)


if __name__ == "__main__":
    if ONLY is None or "train" in ONLY:
        build_locomotive()
        for k in ("cargo", "utility", "container"):
            build_wagon(k)
    if ONLY is None or "props" in ONLY:
        build_props()
    if ONLY is None or "gate" in ONLY:
        build_gate_props()
    if ONLY is not None and "items" in ONLY:
        build_items()
    elif ONLY is not None:  # single build items: only=plank,rail,fasteners,panel
        for key, fn in (("plank", build_plank), ("rail", build_rail), ("fasteners", build_fasteners), ("panel", build_panel)):
            if key in ONLY:
                fn()
    if ONLY is None or "pickups" in ONLY:
        build_pickups()
    elif "gold" in ONLY:
        build_gold_ore()
    print("done")
