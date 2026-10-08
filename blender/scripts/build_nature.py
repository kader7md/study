"""Builds the Trust Issues nature models (trees, rocks, cliffs, bushes) in Blender with baked textures → .glb.

Run headless:
    blender --background --python blender/scripts/build_nature.py -- <repo_root>
Each model is ONE mesh object (several materials) so Godot can scatter thousands with MultiMesh.
Origin = ground contact point at the base.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import build_assets as A  # noqa: E402

OUT = os.path.join(A.ROOT, "assets", "models", "nature")
os.makedirs(OUT, exist_ok=True)


def displace(obj, strength, scale, kind="CLOUDS", subdiv=0):
    if subdiv:
        m = obj.modifiers.new("Sub", "SUBSURF")
        m.levels = subdiv
        m.render_levels = subdiv
    tex = bpy.data.textures.new(obj.name + "_tex", kind)
    tex.noise_scale = scale
    if kind == "VORONOI":
        tex.distance_metric = "DISTANCE"
    d = obj.modifiers.new("Disp", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.texture_coords = "OBJECT" if False else "LOCAL"
    # keep displacement modifiers before the bevel / weighted normal ones
    for name in ("Bevel", "WN"):
        if name in obj.modifiers:
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_move_to_index(modifier=name, index=len(obj.modifiers) - 1)
    return obj


def ico(name, radius, loc, material, subdiv=3, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    obj = bpy.context.active_object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return A._finish(obj, name, material, 0.0)


def branch(name, a, b, r0, r1, material):
    o = A.rod(name, a, b, r0, material, 10)
    # taper: scale the top ring by moving to a cone would need bmesh; a cone is simpler
    return o


def cone_between(name, a, b, r0, r1, material, verts=10):
    from mathutils import Vector
    va, vb = Vector(a), Vector(b)
    d = vb - va
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r0, radius2=r1, depth=d.length, location=(va + vb) / 2)
    obj = bpy.context.active_object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return A._finish(obj, name, material, 0.0)


def pine(name, height=11.0, snow=False):
    A.clear_scene()
    random.seed(hash(name) % 1000)
    parts = [cone_between("trunk", (0, 0, -0.3), (0, 0, height * 0.95), 0.32, 0.05, "bark", 12)]
    displace(parts[0], 0.05, 0.15)
    layers = 8
    for i in range(layers):
        t = i / (layers - 1)
        z = height * (0.22 + t * 0.7)
        r = (1.0 - t) * 2.6 + 0.45
        h = 2.4 - t * 1.1
        c = A.cyl(f"layer{i}", r, h, (0, 0, z), "pine_needles", verts=14, radius2=0.12, bevel=0.0)
        c.rotation_euler.z = random.random() * 6.28
        displace(c, 0.35 + (1 - t) * 0.3, 0.6, subdiv=1)
        parts.append(c)
        if snow:
            s = A.cyl(f"snow{i}", r * 0.82, h * 0.35, (0, 0, z + h * 0.32), "snow", verts=14, radius2=0.1, bevel=0.0)
            displace(s, 0.25, 0.5, subdiv=1)
            parts.append(s)
    obj = A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def oak(name):
    A.clear_scene()
    random.seed(11)
    parts = [cone_between("trunk", (0, 0, -0.3), (0, 0, 3.2), 0.55, 0.35, "bark", 14)]
    displace(parts[0], 0.12, 0.3, subdiv=1)
    tips = []
    for i in range(5):
        a = i * 2 * math.pi / 5 + random.random() * 0.4
        tip = (math.cos(a) * 2.4, math.sin(a) * 2.4, 4.8 + random.random() * 1.2)
        parts.append(cone_between(f"limb{i}", (0, 0, 3.0), tip, 0.3, 0.12, "bark", 10))
        tips.append(tip)
    for i, t in enumerate(tips + [(0, 0, 6.2)]):
        for k in range(3):
            c = ico(f"clump{i}{k}", random.uniform(1.4, 2.0), (t[0] + random.uniform(-0.8, 0.8), t[1] + random.uniform(-0.8, 0.8), t[2] + random.uniform(0.2, 1.2)), "oak_leaves", 2)
            displace(c, 0.55, 0.5)
            parts.append(c)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def birch(name):
    A.clear_scene()
    random.seed(12)
    parts = [cone_between("trunk", (0, 0, -0.3), (0.3, 0, 9.0), 0.2, 0.06, "birch_bark", 12)]
    for i in range(6):
        z = 4.0 + i * 0.8
        a = random.random() * 6.28
        parts.append(cone_between(f"b{i}", (0.15, 0, z), (math.cos(a) * 1.4, math.sin(a) * 1.4, z + 1.0), 0.06, 0.02, "birch_bark", 8))
        c = ico(f"leaf{i}", random.uniform(0.9, 1.3), (math.cos(a) * 1.4, math.sin(a) * 1.4, z + 1.3), "birch_leaves", 2, scale=(1, 1, 1.3))
        displace(c, 0.4, 0.45)
        parts.append(c)
    top = ico("leaf_top", 1.3, (0.3, 0, 9.2), "birch_leaves", 2, scale=(1, 1, 1.4))
    displace(top, 0.4, 0.45)
    parts.append(top)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def dead_tree(name):
    A.clear_scene()
    random.seed(13)
    parts = [cone_between("trunk", (0, 0, -0.3), (0.2, 0.1, 5.5), 0.45, 0.12, "bark", 12)]
    displace(parts[0], 0.15, 0.25, subdiv=1)

    def grow(p, d, length, r, depth):
        if depth == 0:
            return
        end = (p[0] + d[0] * length, p[1] + d[1] * length, p[2] + d[2] * length)
        parts.append(cone_between(f"br{len(parts)}", p, end, r, r * 0.55, "bark", 8))
        for k in range(2):
            nd = (d[0] + random.uniform(-0.8, 0.8), d[1] + random.uniform(-0.8, 0.8), d[2] + random.uniform(-0.2, 0.5))
            n = math.sqrt(sum(c * c for c in nd))
            grow(end, tuple(c / n for c in nd), length * 0.65, r * 0.55, depth - 1)
    for i in range(4):
        a = i * 1.57 + random.random()
        grow((0.15, 0.08, 3.5 + i * 0.5), (math.cos(a), math.sin(a), 0.6), 1.8, 0.14, 3)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def boulder(name, size=1.6, seed=1):
    A.clear_scene()
    random.seed(seed)
    r = ico("rock", size, (0, 0, size * 0.45), "rock", 3, scale=(1.2, 1.0, 0.75))
    displace(r, size * 0.35, 0.8, "VORONOI")
    displace(r, size * 0.12, 0.25)
    A.join(name, [r], origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def cliff(name):
    A.clear_scene()
    random.seed(21)
    parts = []
    z = 0.0
    for i in range(6):
        h = random.uniform(1.2, 2.2)
        w = 7.0 - i * 0.6 + random.uniform(-0.5, 0.5)
        b = A.box(f"layer{i}", (w, w * 0.6, h), (random.uniform(-0.4, 0.4), random.uniform(-0.3, 0.3), z + h / 2), "cliff", 0.0)
        displace(b, 0.5, 0.9, "VORONOI", subdiv=2)
        parts.append(b)
        z += h * 0.92
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 2048)


def bush(name):
    A.clear_scene()
    random.seed(31)
    parts = []
    for k in range(5):
        c = ico(f"b{k}", random.uniform(0.5, 0.8), (random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0.3, 0.6)), "bush_leaves", 2)
        displace(c, 0.25, 0.3)
        parts.append(c)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 512)


if __name__ == "__main__":
    pine("pine")
    pine("pine_snow", 10.0, snow=True)
    oak("oak")
    birch("birch")
    dead_tree("dead_tree")
    boulder("boulder", 1.6, 1)
    boulder("rock_small", 0.5, 2)
    cliff("cliff")
    bush("bush")
    print("done")
