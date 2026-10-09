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
# materials of the overworld scatter models (ground plants, brambles)
A.MATS.update({
    "grass_blade": ("foliage", (0.16, 0.3, 0.07), 0.0, 0.9),
    "fern_leaves": ("foliage", (0.08, 0.22, 0.05), 0.0, 0.85),
    "flower_red": ("plain", (0.7, 0.08, 0.06), 0.0, 0.7),
    "flower_yellow": ("plain", (0.85, 0.65, 0.08), 0.0, 0.7),
    "flower_white": ("plain", (0.85, 0.85, 0.8), 0.0, 0.7),
    "flower_blue": ("plain", (0.25, 0.3, 0.75), 0.0, 0.7),
    "bramble": ("wood", (0.14, 0.07, 0.05), 0.0, 0.9),
    "berry": ("plain", (0.45, 0.02, 0.05), 0.0, 0.4),
})
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
    """Spruce-like pine: tapered bark trunk, whorls of drooping branch clusters getting shorter towards the top."""
    A.clear_scene()
    random.seed(hash(name) % 1000)
    parts = [cone_between("trunk", (0, 0, -0.3), (0, 0, height), 0.3, 0.04, "bark", 12)]
    displace(parts[0], 0.04, 0.12)
    whorls = 11
    for i in range(whorls):
        t = i / (whorls - 1)
        z = height * (0.18 + t * 0.78)
        reach = (1.0 - t) ** 0.9 * 2.8 + 0.35
        count = max(4, int(9 - t * 5))
        for k in range(count):
            a = k * 2 * math.pi / count + random.uniform(-0.25, 0.25) + i * 0.6
            droop = 0.35 + (1.0 - t) * 0.5
            tip = (math.cos(a) * reach, math.sin(a) * reach, z - droop * reach * 0.6)
            # the branch: a flattened cone of needles from the trunk to the tip, slightly upturned at the end
            c = cone_between(f"br{i}_{k}", (0, 0, z + 0.15), tip, 0.55 * (1.0 - t * 0.5), 0.08, "pine_needles", 7)
            c.scale = (1.0, 1.0, 1.0)
            displace(c, 0.18, 0.35, subdiv=1)
            parts.append(c)
            if snow and k % 2 == 0:
                sn = cone_between(f"sn{i}_{k}", (0, 0, z + 0.3), (tip[0] * 0.8, tip[1] * 0.8, tip[2] + 0.25), 0.3, 0.05, "snow", 6)
                displace(sn, 0.1, 0.3)
                parts.append(sn)
    top = A.cyl("top", 0.35, 1.2, (0, 0, height + 0.2), "pine_needles", verts=8, radius2=0.02, bevel=0.0)
    parts.append(top)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def _leafy_tree(name, trunk_h, trunk_r, limbs, spread, leaf_mat, bark_mat, clump=(0.55, 0.9), seed=11):
    """Broadleaf tree: trunk splitting into limbs that fork twice, each twig end carrying a few leaf clumps."""
    A.clear_scene()
    random.seed(seed)
    parts = [cone_between("trunk", (0, 0, -0.3), (0, 0, trunk_h), trunk_r, trunk_r * 0.65, bark_mat, 12)]
    displace(parts[0], trunk_r * 0.2, 0.3, subdiv=1)
    tips = []

    def fork(p, d, length, r, depth):
        end = (p[0] + d[0] * length, p[1] + d[1] * length, p[2] + d[2] * length)
        parts.append(cone_between(f"limb{len(parts)}", p, end, r, r * 0.6, bark_mat, 8))
        if depth == 0:
            tips.append(end)
            return
        for k in range(2):
            nd = (d[0] + random.uniform(-0.7, 0.7), d[1] + random.uniform(-0.7, 0.7), d[2] + random.uniform(0.0, 0.6))
            n = math.sqrt(sum(c * c for c in nd))
            fork(end, tuple(c / n for c in nd), length * 0.7, r * 0.6, depth - 1)
    for i in range(limbs):
        a = i * 2 * math.pi / limbs + random.uniform(-0.3, 0.3)
        d = (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.75)
        n = math.sqrt(sum(c * c for c in d))
        fork((0, 0, trunk_h * random.uniform(0.85, 1.0)), tuple(c / n for c in d), spread, trunk_r * 0.55, 2)
    for i, t in enumerate(tips):
        for k in range(6):
            c = ico(f"leaf{i}_{k}", random.uniform(*clump), (t[0] + random.uniform(-0.7, 0.7), t[1] + random.uniform(-0.7, 0.7), t[2] + random.uniform(-0.3, 0.6)), leaf_mat, 1)
            displace(c, 0.22, 0.25, subdiv=1)
            parts.append(c)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def oak(name):
    _leafy_tree(name, 3.0, 0.5, 6, 2.0, "oak_leaves", "bark", (0.45, 0.75), 11)


def birch(name):
    _leafy_tree(name, 5.5, 0.2, 5, 1.5, "birch_leaves", "birch_bark", (0.3, 0.5), 12)


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


def rock_spire(name):
    """A tall crag (about 18 m): stacked, shrinking, weathered blocks, leaning a little."""
    A.clear_scene()
    random.seed(41)
    parts = []
    z = 0.0
    lean = (random.uniform(-0.25, 0.25), random.uniform(-0.25, 0.25))
    for i in range(7):
        h = random.uniform(2.2, 3.2)
        w = 7.0 - i * 0.75 + random.uniform(-0.4, 0.4)
        b = A.box(f"block{i}", (w, w * random.uniform(0.75, 0.95), h), (lean[0] * i, lean[1] * i, z + h / 2), "cliff", 0.0,
                  rot=(0, 0, random.uniform(0, 1.2)))
        displace(b, 0.7, 1.1, "VORONOI", subdiv=1)
        parts.append(b)
        z += h * 0.9
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def cliff_big(name):
    """A wide cliff face (about 22 x 9 x 16 m) with strata ledges, to dress steep mountainsides."""
    A.clear_scene()
    random.seed(43)
    parts = []
    for col in range(4):
        x = -8.0 + col * 5.4 + random.uniform(-0.6, 0.6)
        z = 0.0
        for i in range(5):
            h = random.uniform(2.4, 3.8)
            w = random.uniform(5.5, 7.0)
            dpt = random.uniform(6.0, 9.0) - i * 0.9
            b = A.box(f"c{col}_{i}", (w, dpt, h), (x, random.uniform(-0.8, 0.8) + i * 0.6, z + h / 2), "cliff", 0.0,
                      rot=(0, 0, random.uniform(-0.15, 0.15)))
            displace(b, 0.8, 1.3, "VORONOI", subdiv=1)
            parts.append(b)
            z += h * 0.93
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def cave(name):
    """A rock cave: a thick, lumpy shell (about 18 m wide, 9 m high) with a wide mouth on the -Y side."""
    import bmesh
    A.clear_scene()
    random.seed(47)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=9.0, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.scale = (1.0, 1.25, 0.85)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    kill = [f for f in bm.faces if f.calc_center_median().z < -0.5 or
            (f.calc_center_median().y < -6.0 and f.calc_center_median().z < 5.8 and abs(f.calc_center_median().x) < 5.5)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bm.to_mesh(obj.data)
    bm.free()
    obj = A._finish(obj, "shell", "cliff", 0.0)
    sol = obj.modifiers.new("Solid", "SOLIDIFY")
    sol.thickness = 2.2
    sol.offset = 1.0
    displace(obj, 1.2, 1.6, "VORONOI")
    # a few fallen blocks around the mouth
    parts = [obj]
    for k in range(4):
        r = ico(f"blk{k}", random.uniform(0.8, 1.5), (random.uniform(-7, 7), random.uniform(-12, -9), 0.3), "rock", 2)
        displace(r, 0.4, 0.6, "VORONOI")
        parts.append(r)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 1024)


def log(name):
    """A fallen trunk (about 5 m) with broken branch stubs."""
    A.clear_scene()
    random.seed(53)
    trunk = cone_between("trunk", (-2.6, 0, 0.36), (2.6, 0, 0.32), 0.38, 0.3, "bark", 14)
    displace(trunk, 0.05, 0.15)
    parts = [trunk]
    for k in range(4):
        x = random.uniform(-2.0, 2.0)
        a = random.uniform(0, math.pi * 2)
        parts.append(cone_between(f"stub{k}", (x, 0, 0.36), (x + random.uniform(-0.3, 0.3), math.cos(a) * 0.9, 0.36 + math.sin(a) * 0.9 + 0.3),
                                  0.09, 0.03, "bark", 6))
    for side in (-1, 1):
        parts.append(A.cyl(f"end{side}", 0.3 if side > 0 else 0.38, 0.04, (2.62 * side, 0, 0.36 if side < 0 else 0.32), "wood", axis="X", verts=14, bevel=0.0))
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 512)


def grass_clump(name):
    """A tuft of 16 bent grass blades (about 0.7 m)."""
    A.clear_scene()
    random.seed(59)
    parts = []
    for k in range(16):
        a = k * 2 * math.pi / 16 + random.uniform(-0.2, 0.2)
        r = random.uniform(0.05, 0.18)
        h = random.uniform(0.45, 0.8)
        lean = random.uniform(0.15, 0.4)
        base = (math.cos(a) * r, math.sin(a) * r, -0.02)
        tip = (math.cos(a) * (r + lean), math.sin(a) * (r + lean), h)
        b = cone_between(f"blade{k}", base, tip, 0.035, 0.002, "grass_blade", 3)
        b.scale = (1.0, 1.0, 1.0)
        parts.append(b)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 256)


def flowers(name):
    """Wild flowers: thin stems with red, yellow, white and blue heads."""
    A.clear_scene()
    random.seed(61)
    parts = []
    colours = ["flower_red", "flower_yellow", "flower_white", "flower_blue"]
    for k in range(9):
        x, y = random.uniform(-0.35, 0.35), random.uniform(-0.35, 0.35)
        h = random.uniform(0.3, 0.55)
        parts.append(cone_between(f"stem{k}", (x, y, -0.02), (x + random.uniform(-0.05, 0.05), y, h), 0.012, 0.008, "grass_blade", 4))
        parts.append(ico(f"head{k}", random.uniform(0.04, 0.07), (x, y, h + 0.02), colours[k % 4], 1, scale=(1, 1, 0.55)))
    for k in range(6):
        a = random.uniform(0, math.pi * 2)
        parts.append(cone_between(f"leaf{k}", (0, 0, 0), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.2), 0.03, 0.004, "grass_blade", 3))
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 256)


def fern(name):
    """A fern: eight arching fronds (about 1 m)."""
    A.clear_scene()
    random.seed(67)
    parts = []
    for k in range(8):
        a = k * 2 * math.pi / 8 + random.uniform(-0.2, 0.2)
        mid = (math.cos(a) * 0.45, math.sin(a) * 0.45, 0.7)
        tip = (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.35)
        f1 = cone_between(f"f{k}a", (0, 0, 0), mid, 0.14, 0.12, "fern_leaves", 4)
        f2 = cone_between(f"f{k}b", mid, tip, 0.12, 0.01, "fern_leaves", 4)
        for f in (f1, f2):
            f.scale = (1.0, 1.0, 1.0)
            displace(f, 0.04, 0.1)
        parts += [f1, f2]
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 512)


def thorn_bush(name):
    """A bramble thicket (about 2.5 m wide): a tangle of thorny dark canes with red berries. It hurts to walk through."""
    A.clear_scene()
    random.seed(71)
    parts = []
    for k in range(22):
        a = random.uniform(0, math.pi * 2)
        p0 = (random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), 0.0)
        p1 = (math.cos(a) * random.uniform(0.6, 1.3), math.sin(a) * random.uniform(0.6, 1.3), random.uniform(0.6, 1.3))
        p2 = (p1[0] * 1.3, p1[1] * 1.3, p1[2] * random.uniform(0.3, 0.8))
        parts.append(cone_between(f"cane{k}a", p0, p1, 0.04, 0.03, "bramble", 5))
        parts.append(cone_between(f"cane{k}b", p1, p2, 0.03, 0.01, "bramble", 5))
        for t in range(3):
            f = random.uniform(0.2, 0.9)
            q = tuple(p0[i] + (p1[i] - p0[i]) * f for i in range(3))
            parts.append(cone_between(f"th{k}_{t}", q, (q[0] + random.uniform(-0.1, 0.1), q[1] + random.uniform(-0.1, 0.1), q[2] + 0.1), 0.012, 0.0, "bramble", 3))
        if k % 3 == 0:
            parts.append(ico(f"berry{k}", 0.05, p2, "berry", 1))
    for k in range(6):
        c = ico(f"leaf{k}", random.uniform(0.35, 0.55), (random.uniform(-0.8, 0.8), random.uniform(-0.8, 0.8), random.uniform(0.4, 0.9)), "bush_leaves", 1)
        displace(c, 0.15, 0.2)
        parts.append(c)
    A.join(name, parts, origin=(0, 0, 0))
    A.bake_and_export(os.path.join(OUT, f"{name}.glb"), 512)


OVERWORLD = {"rock_spire": rock_spire, "cliff_big": cliff_big, "cave": cave, "log": log, "grass_clump": grass_clump,
             "flowers": flowers, "fern": fern, "thorn_bush": thorn_bush}


if __name__ == "__main__" and "--" in sys.argv and len(sys.argv) > sys.argv.index("--") + 2:
    # build only the named models: blender ... -- <repo_root> rock_spire log ...
    for model in sys.argv[sys.argv.index("--") + 2:]:
        OVERWORLD[model](model)
    print("done")
elif __name__ == "__main__":
    for model, fn in OVERWORLD.items():
        fn(model)
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
