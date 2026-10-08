"""Builds the Trust Issues crew member: a chunky cartoon railway worker with a rig, swappable face parts and
accessories, and every animation the game plays. No baking: flat colours per material, Godot tints them.

Run headless:
    blender --background --python blender/scripts/build_character.py -- <repo_root> [only=character,arm] [preview=<png>]

Exports to assets/models/character:
    character.glb  Armature (root, hips, spine, chest, neck, head, shoulder/upper_arm/forearm/hand .L/.R,
                   thigh/shin/foot .L/.R) with the skinned meshes:
                     Body                     skin, jacket, trousers, boots, belt, stripe (always shown)
                     Eyes_<round|sleepy|angry|googly|dot>   one shown at a time
                     Mouth_<smile|grin|flat|open|frown|teeth>
                     Acc_<beanie|cap|hardhat|glasses|scarf|backpack|mustache>   (none = all hidden)
                     Hair                     a little tuft, hidden under hats
                   Materials Godot recolours by name: Skin, Outfit, OutfitDark, Pants, Boots, Hat, HatDark, Iris,
                   Pupil, EyeWhite, Mouth, Tongue, Teeth, Hair, Frame, Glass, Stripe, Belt, Lid.
                   Animations (glTF actions, keyframed here): idle, walk, run, jump, fall, crouch, carry_shoulder,
                   carry_front, hold_tool, hammer, wrench, nail_gun, weld, crank, shovel, lever, interact, wave,
                   downed, climb.
    fp_arm.glb     first-person arm: a bare cartoon hand (Skin) with curled fingers and the jacket sleeve (Outfit,
                   OutfitDark cuff). Hand at the origin, forearm along Blender -Y (Godot +Z, towards the camera),
                   same layout as the old props/arm.glb so the viewmodel poses still fit.
Axes: Blender +Y = the character's front (Godot -Z), Z up, the character's right hand is at +X. Feet at Z = 0.
Our own design (chunky rounded shapes, big head, stubby limbs); no third-party assets.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = argv[0] if argv else os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ONLY = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("only=")), None)
PREVIEW = next((a.split("=", 1)[1] for a in argv if a.startswith("preview=")), None)
OUT = os.path.join(ROOT, "assets", "models", "character")
os.makedirs(OUT, exist_ok=True)
FPS = 30

# --- Materials: flat colours (sRGB), soft roughness. Godot replaces them with its toon material by name. ---------
COLORS = {
    "Skin": ((1.0, 0.78, 0.62), 0.7), "Outfit": ((0.86, 0.42, 0.18), 0.85), "OutfitDark": ((0.6, 0.27, 0.1), 0.85),
    "Pants": ((0.24, 0.3, 0.42), 0.85), "Boots": ((0.3, 0.19, 0.12), 0.7), "Belt": ((0.18, 0.12, 0.08), 0.6),
    "Stripe": ((0.98, 0.9, 0.45), 0.5), "Hat": ((0.2, 0.55, 0.6), 0.85), "HatDark": ((0.13, 0.38, 0.42), 0.85),
    "EyeWhite": ((0.98, 0.98, 0.96), 0.3), "Iris": ((0.36, 0.22, 0.12), 0.3), "Pupil": ((0.06, 0.05, 0.05), 0.2),
    "Mouth": ((0.32, 0.08, 0.08), 0.6), "Tongue": ((0.9, 0.4, 0.42), 0.6), "Teeth": ((1.0, 1.0, 0.97), 0.4),
    "Hair": ((0.3, 0.18, 0.1), 0.8), "Frame": ((0.12, 0.1, 0.1), 0.4), "Glass": ((0.75, 0.9, 1.0), 0.1),
    "Lid": ((1.0, 0.78, 0.62), 0.7),
}
_mats = {}


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mat(name):
    if name in _mats:
        return _mats[name]
    col, rough = COLORS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*srgb_to_linear(col), 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if name == "Glass":
        bsdf.inputs["Alpha"].default_value = 0.35
        m.blend_method = "BLEND" if hasattr(m, "blend_method") else m.blend_method
    _mats[name] = m
    return m


# --- Mesh builders (bmesh): every part is a list of (verts, faces) in one object with one material ----------------

def new_obj(name, bm, material, bone=None, weights=None):
    """Object from a bmesh, smooth shaded, one material. `bone` = rigid weight; `weights(co) -> {bone: w}` = custom."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat(material))
    if bone or weights:
        groups = {}
        for v in me.vertices:
            w = {bone: 1.0} if bone else weights(v.co)
            for b, val in w.items():
                if val <= 0.0:
                    continue
                if b not in groups:
                    groups[b] = ob.vertex_groups.new(name=b)
                groups[b].add([v.index], val, "REPLACE")
    return ob


def lathe(profile, seg=24, scale=(1.0, 1.0), center=(0, 0, 0)):
    """Surface of revolution around Z from [(z, r)] (first/last r may be 0 to close the ends)."""
    bm = bmesh.new()
    rings = []
    for z, r in profile:
        if r <= 1e-5:
            rings.append([bm.verts.new((center[0], center[1], center[2] + z))])
            continue
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring.append(bm.verts.new((center[0] + math.cos(a) * r * scale[0], center[1] + math.sin(a) * r * scale[1], center[2] + z)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(seg):
                bm.faces.new((a[0], b[(i + 1) % seg], b[i]))
        elif len(b) == 1:
            for i in range(seg):
                bm.faces.new((a[i], a[(i + 1) % seg], b[0]))
        else:
            for i in range(seg):
                bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def ellipsoid_profile(rz, rings=12, z0=0.0, cut_low=-1.0, cut_high=1.0):
    """(z, r) samples of a unit-radius ellipse with half-height rz, between cut_low..cut_high (in -1..1)."""
    out = []
    lo = math.asin(max(-1.0, cut_low))
    hi = math.asin(min(1.0, cut_high))
    for i in range(rings + 1):
        t = lo + (hi - lo) * i / rings
        out.append((z0 + math.sin(t) * rz, math.cos(t)))
    return out


def ball(center, radii, seg=20, rings=12):
    """Ellipsoid bmesh."""
    prof = [(z, r * radii[0]) for z, r in ellipsoid_profile(radii[2], rings)]
    prof[0] = (prof[0][0], 0.0)
    prof[-1] = (prof[-1][0], 0.0)
    return lathe(prof, seg, (1.0, radii[1] / radii[0]), center)


def capsule(a, b, r1, r2=None, seg=16, cap_rings=5):
    """Tapered capsule from point a to point b (radii r1 at a, r2 at b)."""
    r2 = r1 if r2 is None else r2
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    prof = []
    for i in range(cap_rings + 1):  # bottom cap (at a)
        t = -math.pi / 2 + (math.pi / 2) * i / cap_rings
        prof.append((math.sin(t) * r1, math.cos(t) * r1))
    for i in range(cap_rings + 1):  # top cap (at b)
        t = (math.pi / 2) * i / cap_rings
        prof.append((length + math.sin(t) * r2, math.cos(t) * r2))
    prof[0] = (prof[0][0], 0.0)
    prof[-1] = (prof[-1][0], 0.0)
    bm = lathe(prof, seg)
    rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(a) @ rot, verts=bm.verts)
    return bm


def tube(points, radius, seg=10, caps=True):
    """Round tube through a list of 3D points (radius may be a list), with rounded ends."""
    pts = [Vector(p) for p in points]
    radii = radius if isinstance(radius, (list, tuple)) else [radius] * len(pts)
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        x = d.cross(up).normalized()
        y = x.cross(d).normalized()
        rings.append([bm.verts.new(p + (x * math.cos(2 * math.pi * k / seg) + y * math.sin(2 * math.pi * k / seg)) * radii[i])
                      for k in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    if caps:
        for ring, p, sgn in ((rings[0], pts[0], -1), (rings[-1], pts[-1], 1)):
            d = (pts[1] - pts[0]) if sgn < 0 else (pts[-1] - pts[-2])
            tip = bm.verts.new(p + d.normalized() * sgn * radii[0 if sgn < 0 else -1] * 0.8)
            for k in range(seg):
                bm.faces.new((ring[k], ring[(k + 1) % seg], tip))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def rbox(center, size, bevel=0.03, seg=3):
    """Rounded box."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=bevel, segments=seg, affect="EDGES", profile=0.5)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def merge(*bms):
    out = bmesh.new()
    for bm in bms:
        tmp = bpy.data.meshes.new("tmp")
        bm.to_mesh(tmp)
        out.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        bm.free()
    return out


def xform(bm, loc=(0, 0, 0), rot=(0, 0, 0), origin=(0, 0, 0)):
    m = Matrix.Translation(Vector(loc) + Vector(origin)) @ Euler(rot).to_matrix().to_4x4() @ Matrix.Translation(-Vector(origin))
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
    return bm


# --- Proportions --------------------------------------------------------------------------------------------------
HEAD_C = Vector((0.0, 0.0, 1.44))
HEAD_R = (0.335, 0.31, 0.305)      # x, y (front), z
SHOULDER = (0.27, 0.0, 1.05)
ELBOW = (0.37, 0.01, 0.84)
WRIST = (0.42, 0.04, 0.65)
HAND_END = (0.44, 0.06, 0.55)
HIP = (0.125, 0.0, 0.5)
KNEE = (0.13, 0.02, 0.29)
ANKLE = (0.13, 0.0, 0.1)
TOE = (0.13, 0.17, 0.04)

BONES = [  # name, head, tail, parent
    ("root", (0, 0, 0), (0, 0.25, 0), None),
    ("hips", (0, 0, 0.52), (0, 0, 0.68), "root"),
    ("spine", (0, 0, 0.68), (0, 0, 0.88), "hips"),
    ("chest", (0, 0, 0.88), (0, 0, 1.1), "spine"),
    ("neck", (0, 0, 1.1), (0, 0, 1.2), "chest"),
    ("head", (0, 0, 1.2), (0, 0, 1.7), "neck"),
]
for s, side in ((1, "R"), (-1, "L")):
    m = lambda p: (p[0] * s, p[1], p[2])  # noqa: E731
    BONES += [
        (f"shoulder.{side}", m((0.07, 0, 1.03)), m(SHOULDER), "chest"),
        (f"upper_arm.{side}", m(SHOULDER), m(ELBOW), f"shoulder.{side}"),
        (f"forearm.{side}", m(ELBOW), m(WRIST), f"upper_arm.{side}"),
        (f"hand.{side}", m(WRIST), m(HAND_END), f"forearm.{side}"),
        (f"thigh.{side}", m(HIP), m(KNEE), "hips"),
        (f"shin.{side}", m(KNEE), m(ANKLE), f"thigh.{side}"),
        (f"foot.{side}", m(ANKLE), m(TOE), f"shin.{side}"),
    ]


def head_surface(u, v, off=0.0):
    """Point on the head's front surface at face coords (u = right, v = up from the head centre) + normal offset."""
    a, b, c = HEAD_R
    k = 1.0 - (u / a) ** 2 - (v / c) ** 2
    y = b * math.sqrt(max(k, 0.0))
    p = Vector((u, y, v))
    n = Vector((u / a ** 2, y / b ** 2, v / c ** 2)).normalized()
    return HEAD_C + p + n * off, n


def face_patch(outline, front=0.006, back=-0.02):
    """A thin shape lying on the face: 2D outline [(u, v)] (convex-ish, around its centroid)."""
    bm = bmesh.new()
    cu = sum(p[0] for p in outline) / len(outline)
    cv = sum(p[1] for p in outline) / len(outline)
    fc = bm.verts.new(head_surface(cu, cv, front)[0])
    bc = bm.verts.new(head_surface(cu, cv, back)[0])
    fr = [bm.verts.new(head_surface(u, v, front)[0]) for u, v in outline]
    br = [bm.verts.new(head_surface(u, v, back)[0]) for u, v in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((fc, fr[i], fr[j]))
        bm.faces.new((bc, br[j], br[i]))
        bm.faces.new((fr[i], br[i], br[j], fr[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def face_tube(uvs, radius, off=0.004, seg=8):
    return tube([head_surface(u, v, off)[0] for u, v in uvs], radius, seg)


def ellipse(cu, cv, ru, rv, n=20, a0=0.0, a1=2 * math.pi):
    return [(cu + math.cos(a0 + (a1 - a0) * i / n) * ru, cv + math.sin(a0 + (a1 - a0) * i / n) * rv) for i in range(n)]


def arc(cu, cv, r, a0, a1, n=10, squash=1.0):
    return [(cu + math.cos(a0 + (a1 - a0) * i / n) * r, cv + math.sin(a0 + (a1 - a0) * i / n) * r * squash) for i in range(n + 1)]


def eye_ball(u, v, radii, off):
    """A flattened sphere sitting on the face at (u, v), pushed out along the normal."""
    p, n = head_surface(u, v, off)
    bm = ball((0, 0, 0), radii, 16, 10)
    rot = Vector((0, 1, 0)).rotation_difference(n).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation(p) @ rot, verts=bm.verts)
    return bm


# --- Character -----------------------------------------------------------------------------------------------------

def torso_weights(co):
    z = co.z
    w = {}
    if z < 0.62:
        w = {"hips": 1.0}
    elif z < 0.78:
        t = (z - 0.62) / 0.16
        w = {"hips": 1 - t, "spine": t}
    elif z < 0.95:
        t = (z - 0.78) / 0.17
        w = {"spine": 1 - t, "chest": t}
    else:
        w = {"chest": 1.0}
    return w


def limb_weights(side, a_bone, b_bone, a, b, blend=0.35):
    """Smooth weight from bone a to bone b along the segment a->b (blend = fraction around the joint)."""
    a, b = Vector(a), Vector(b)

    def fn(co):
        t = (co - a).dot(b - a) / (b - a).length_squared
        k = min(max((t - (1 - blend)) / blend, 0.0), 1.0)
        return {a_bone: 1 - k, b_bone: k} if k > 0 else {a_bone: 1.0}
    return fn


def build_body():
    parts = []
    # trousers: hips block and two stubby legs, chunky boots
    pants = lathe([(0.4, 0.0), (0.42, 0.17), (0.48, 0.25), (0.58, 0.27), (0.68, 0.275)], 28)
    parts.append(new_obj("pants_hips", pants, "Pants", weights=torso_weights))
    for s, side in ((1, "R"), (-1, "L")):
        hip, knee, ankle = Vector((HIP[0] * s, HIP[1], HIP[2])), Vector((KNEE[0] * s, KNEE[1], KNEE[2])), Vector((ANKLE[0] * s, ANKLE[1], ANKLE[2]))
        parts.append(new_obj(f"thigh_{side}", capsule(hip + Vector((0, 0, 0.04)), knee, 0.105, 0.095), "Pants", f"thigh.{side}"))
        parts.append(new_obj(f"shin_{side}", capsule(knee, ankle + Vector((0, 0, 0.04)), 0.095, 0.09), "Pants", f"shin.{side}"))
        boot = rbox((ANKLE[0] * s, 0.055, 0.065), (0.2, 0.32, 0.14), 0.06, 3)
        boot = merge(boot, ball((ANKLE[0] * s, 0.0, 0.12), (0.1, 0.11, 0.08), 14, 8))
        parts.append(new_obj(f"boot_{side}", boot, "Boots", f"foot.{side}"))
        parts.append(new_obj(f"sole_{side}", rbox((ANKLE[0] * s, 0.06, 0.016), (0.19, 0.3, 0.035), 0.014, 2), "Belt", f"foot.{side}"))
    # jacket: a big rounded egg, collar, two reflective stripes, belt, pocket
    jacket = lathe([(0.58, 0.0), (0.6, 0.27), (0.68, 0.31), (0.8, 0.315), (0.93, 0.3), (1.02, 0.27), (1.09, 0.21),
                    (1.13, 0.13), (1.15, 0.0)], 32, (1.0, 0.9))
    parts.append(new_obj("jacket", jacket, "Outfit", weights=torso_weights))
    collar = tube([(math.cos(a) * 0.15, math.sin(a) * 0.13, 1.13) for a in [2 * math.pi * i / 24 for i in range(25)]], 0.045, 10, caps=False)
    parts.append(new_obj("collar", collar, "OutfitDark", "chest"))
    for z, r in ((0.74, 0.318), (0.88, 0.31)):
        ring = tube([(math.cos(a) * r, math.sin(a) * r * 0.9, z) for a in [2 * math.pi * i / 40 for i in range(41)]], 0.016, 6, caps=False)
        parts.append(new_obj(f"stripe_{z}", ring, "Stripe", weights=torso_weights))
    belt = tube([(math.cos(a) * 0.3, math.sin(a) * 0.27, 0.61) for a in [2 * math.pi * i / 40 for i in range(41)]], 0.028, 8, caps=False)
    parts.append(new_obj("belt", belt, "Belt", "hips"))
    parts.append(new_obj("buckle", rbox((0, 0.29, 0.61), (0.08, 0.03, 0.06), 0.01, 2), "Stripe", "hips"))
    parts.append(new_obj("pocket", rbox((0.13, 0.255, 0.95), (0.1, 0.03, 0.09), 0.015, 2), "OutfitDark", "chest"))
    parts.append(new_obj("zip", rbox((0.0, 0.282, 0.86), (0.018, 0.02, 0.4), 0.006, 1), "OutfitDark", weights=torso_weights))
    # arms: sleeves (jacket), cuffs, big cartoon hands with a thumb
    for s, side in ((1, "R"), (-1, "L")):
        sh, el, wr, he = (Vector((p[0] * s, p[1], p[2])) for p in (SHOULDER, ELBOW, WRIST, HAND_END))
        parts.append(new_obj(f"shoulder_{side}", ball(sh + Vector((-0.02 * s, 0, 0.0)), (0.105, 0.105, 0.1), 16, 10), "Outfit", f"upper_arm.{side}"))
        parts.append(new_obj(f"upper_{side}", capsule(sh, el, 0.088, 0.08), "Outfit",
                             weights=limb_weights(side, f"upper_arm.{side}", f"forearm.{side}", sh, el, 0.2)))
        parts.append(new_obj(f"fore_{side}", capsule(el, wr - (wr - el).normalized() * 0.03, 0.08, 0.078), "Outfit", f"forearm.{side}"))
        cuff_pts = [wr - (wr - el).normalized() * 0.04, wr - (wr - el).normalized() * 0.01]
        parts.append(new_obj(f"cuff_{side}", capsule(cuff_pts[0], cuff_pts[1], 0.086, 0.086, 16, 3), "OutfitDark", f"forearm.{side}"))
        d = (he - wr).normalized()
        hand = ball(wr + d * 0.075, (0.072, 0.06, 0.085), 16, 10)
        hand = xform(hand, rot=(0, 0, 0))
        thumb = capsule(wr + d * 0.04 + Vector((-0.03 * s, 0.05, 0)), wr + d * 0.07 + Vector((-0.04 * s, 0.085, 0.0)), 0.026, 0.024, 10, 3)
        parts.append(new_obj(f"hand_{side}", merge(hand, thumb), "Skin", f"hand.{side}"))
    # neck and head, nose and ears
    parts.append(new_obj("neck", capsule((0, 0, 1.08), (0, 0, 1.2), 0.09), "Skin", "neck"))
    parts.append(new_obj("head", ball(HEAD_C, HEAD_R, 32, 20), "Skin", "head"))
    nose_p, n = head_surface(0.0, -0.035, 0.0)
    parts.append(new_obj("nose", ball(nose_p + n * 0.01, (0.045, 0.04, 0.038), 14, 8), "Skin", "head"))
    for s in (1, -1):
        ear = ball(HEAD_C + Vector(((HEAD_R[0] - 0.015) * s, -0.01, -0.02)), (0.045, 0.06, 0.075), 12, 8)
        parts.append(new_obj(f"ear_{s}", ear, "Skin", "head"))
    # cheeks: a hint of blush is done in Godot (rim); keep the mesh simple
    return parts


def build_eyes():
    out = {}
    eu, ev = 0.115, 0.055  # eye centre offset on the face

    def round_eye(u, v, r=0.074, iris=0.044, pupil=0.025, look=(0.0, 0.0), lid=False):
        parts = [(eye_ball(u, v, (r, r * 0.45, r * 1.2), -0.012), "EyeWhite")]
        iu, iv = u + look[0], v + look[1]
        parts.append((eye_ball(iu, iv, (iris, iris * 0.35, iris * 1.15), 0.014), "Iris"))
        parts.append((eye_ball(iu, iv, (pupil, pupil * 0.35, pupil * 1.15), 0.02), "Pupil"))
        parts.append((eye_ball(iu + 0.012, iv + 0.02, (0.009, 0.006, 0.009), 0.026), "EyeWhite"))
        return parts

    # round: big friendly eyes
    out["round"] = round_eye(eu, ev) + round_eye(-eu, ev)
    # sleepy: half-closed lids with a lash line
    sleepy = []
    for s in (1, -1):
        sleepy += round_eye(eu * s, ev, look=(0.0, -0.012))
        sleepy.append((eye_ball(eu * s, ev + 0.03, (0.072, 0.04, 0.06), -0.004), "Lid"))
        sleepy.append((face_tube(arc(eu * s, ev + 0.012, 0.062, math.radians(195), math.radians(345), 8, 0.25), 0.007, 0.03), "Pupil"))
    out["sleepy"] = sleepy
    # angry: smaller eyes under heavy slanted brows
    angry = []
    for s in (1, -1):
        angry += round_eye(eu * s, ev - 0.005, r=0.062, iris=0.038, pupil=0.021)
        angry.append((face_tube([(s * (eu + 0.075), ev + 0.1), (s * (eu - 0.005), ev + 0.075), (s * (eu - 0.07), ev + 0.04)], 0.018, 0.012), "Hair"))
    out["angry"] = angry
    # googly: big bulging whites with loose pupils looking different ways
    googly = []
    for s, look in ((1, (0.022, 0.018)), (-1, (0.012, -0.024))):
        u = eu * s * 1.05
        p, n = head_surface(u, ev + 0.01, 0.02)
        googly.append((eye_ball(u, ev + 0.01, (0.078, 0.06, 0.085), 0.0), "EyeWhite"))
        googly.append((eye_ball(u + look[0], ev + 0.01 + look[1], (0.034, 0.02, 0.034), 0.058), "Pupil"))
    out["googly"] = googly
    # dot: tiny shiny bead eyes
    dot = []
    for s in (1, -1):
        dot.append((eye_ball(eu * s * 0.95, ev, (0.03, 0.015, 0.042), 0.0), "Pupil"))
        dot.append((eye_ball(eu * s * 0.95 + 0.008, ev + 0.018, (0.008, 0.005, 0.009), 0.014), "EyeWhite"))
    out["dot"] = dot
    objs = []
    for style, parts in out.items():
        objs.append(join_parts(f"Eyes_{style}", parts, "head"))
    return objs


def build_mouths():
    mv = -0.12  # mouth height on the face
    out = {}
    out["smile"] = [(face_tube(arc(0.0, mv + 0.05, 0.085, math.radians(215), math.radians(325), 12, 0.75), 0.014, 0.006), "Mouth")]
    # grin: a wide open D with a row of teeth
    d = [(0.1 * math.cos(a), mv + 0.015 + 0.075 * math.sin(a)) for a in [math.pi + math.pi * i / 16 for i in range(17)]]
    out["grin"] = [(face_patch(d, 0.004), "Mouth"),
                   (face_patch([(-0.085, mv + 0.015), (0.085, mv + 0.015), (0.075, mv - 0.012), (-0.075, mv - 0.012)], 0.008), "Teeth"),
                   (face_patch(ellipse(0.0, mv - 0.042, 0.04, 0.016, 12), 0.007), "Tongue")]
    out["flat"] = [(face_tube([(-0.055, mv), (0.0, mv - 0.004), (0.055, mv)], 0.013, 0.006), "Mouth")]
    out["open"] = [(face_patch(ellipse(0.0, mv - 0.01, 0.045, 0.055, 20), 0.004), "Mouth"),
                   (face_patch(ellipse(0.0, mv - 0.042, 0.03, 0.017, 12), 0.008), "Tongue")]
    out["frown"] = [(face_tube(arc(0.0, mv - 0.07, 0.075, math.radians(40), math.radians(140), 12, 0.7), 0.014, 0.006), "Mouth")]
    out["teeth"] = [(face_tube(arc(0.0, mv + 0.05, 0.08, math.radians(220), math.radians(320), 12, 0.7), 0.013, 0.006), "Mouth"),
                    (face_patch([(-0.026, mv - 0.003), (-0.002, mv - 0.004), (-0.003, mv - 0.042), (-0.025, mv - 0.04)], 0.007), "Teeth"),
                    (face_patch([(0.002, mv - 0.004), (0.026, mv - 0.003), (0.025, mv - 0.04), (0.003, mv - 0.042)], 0.007), "Teeth")]
    return [join_parts(f"Mouth_{k}", v, "head") for k, v in out.items()]


def build_accessories():
    hc = HEAD_C
    a, b, c = HEAD_R
    objs = []
    # beanie: a knitted dome with a thick rolled rim and a pompom
    dome = lathe([(z * (c + 0.035), r * (a + 0.025)) for z, r in ellipsoid_profile(1.0, 10, 0.0, 0.28, 1.0)][:-1] + [(c + 0.035, 0.0)],
                 28, (1.0, (b + 0.025) / (a + 0.025)), hc)
    rim = tube([(hc.x + math.cos(t) * (a + 0.03), hc.y + math.sin(t) * (b + 0.03), hc.z + 0.085) for t in [2 * math.pi * i / 32 for i in range(33)]],
               0.04, 10, caps=False)
    pom = ball(hc + Vector((0, 0, c + 0.06)), (0.06, 0.06, 0.055), 14, 8)
    objs.append(join_parts("Acc_beanie", [(dome, "Hat"), (rim, "HatDark"), (pom, "HatDark")], "head"))
    # cap: a dome, a long visor, a button
    cdome = lathe([(z * (c + 0.035), r * (a + 0.035)) for z, r in ellipsoid_profile(1.0, 10, 0.0, 0.42, 1.0)][:-1] + [(c + 0.035, 0.0)],
                  28, (1.0, (b + 0.035) / (a + 0.035)), hc)
    visor = ball(hc + Vector((0, b + 0.05, 0.135)), (0.21, 0.16, 0.02), 20, 6)
    visor = xform(visor, rot=(math.radians(10), 0, 0), origin=hc + Vector((0, b - 0.05, 0.135)))
    button = ball(hc + Vector((0, 0, c + 0.035)), (0.03, 0.03, 0.018), 10, 6)
    objs.append(join_parts("Acc_cap", [(cdome, "Hat"), (visor, "HatDark"), (button, "HatDark")], "head"))
    # hard hat: a tall shell, a ridge, a brim all round
    shell = lathe([(z * (c + 0.07), r * (a + 0.035)) for z, r in ellipsoid_profile(1.0, 10, 0.0, 0.22, 1.0)][:-1] + [(c + 0.07, 0.0)],
                  28, (1.0, (b + 0.035) / (a + 0.035)), hc + Vector((0, 0, 0.01)))
    brim = lathe([(0.0, a + 0.02), (0.01, a + 0.09), (0.02, a + 0.1), (0.03, a + 0.09), (0.04, a + 0.03)], 32,
                 (1.0, (b + 0.06) / (a + 0.06)), hc + Vector((0, 0.02, 0.07)))
    ridge = tube([hc + Vector((0, -0.23, 0.2)), hc + Vector((0, -0.1, 0.33)), hc + Vector((0, 0.08, 0.34)), hc + Vector((0, 0.22, 0.23))], 0.03, 10)
    objs.append(join_parts("Acc_hardhat", [(shell, "Hat"), (brim, "Hat"), (ridge, "HatDark")], "head"))
    # glasses: two round rims, a bridge, the arms back to the ears
    gl = []
    for s in (1, -1):
        p, n = head_surface(0.115 * s, 0.055, 0.06)
        ring = tube([p + Vector((math.cos(t) * 0.088, 0, math.sin(t) * 0.082)) for t in [2 * math.pi * i / 24 for i in range(25)]], 0.011, 8, caps=False)
        lens = ball(p + Vector((0, -0.004, 0)), (0.084, 0.006, 0.078), 16, 6)
        gl += [(ring, "Frame"), (lens, "Glass")]
        gl.append((tube([p + Vector((0.088 * s, 0, 0.0)), hc + Vector((0.32 * s, 0.13, 0.05)), hc + Vector((0.34 * s, -0.02, 0.02))], 0.01, 6), "Frame"))
    pl, _ = head_surface(0.027, 0.06, 0.06)
    pr, _ = head_surface(-0.027, 0.06, 0.06)
    gl.append((tube([pl, (pl + pr) / 2 + Vector((0, 0.005, 0.012)), pr], 0.01, 6), "Frame"))
    objs.append(join_parts("Acc_glasses", gl, "head"))
    # scarf: a fat roll round the neck and a tail hanging over the chest
    loop = tube([(math.cos(t) * 0.19, math.sin(t) * 0.17, 1.13 + 0.015 * math.sin(2 * t)) for t in [2 * math.pi * i / 28 for i in range(29)]],
                0.065, 12, caps=False)
    tail = tube([(0.1, 0.17, 1.1), (0.14, 0.27, 0.98), (0.15, 0.3, 0.84)], [0.05, 0.045, 0.04], 10)
    stripe = tube([(0.14, 0.29, 0.92), (0.15, 0.305, 0.9)], 0.047, 10, caps=False)
    objs.append(join_parts("Acc_scarf", [(loop, "Hat"), (tail, "Hat"), (stripe, "HatDark")], "chest"))
    # backpack: a rounded pack on the back, a flap, straps over the shoulders
    pack = rbox((0, -0.37, 0.86), (0.4, 0.2, 0.42), 0.08, 3)
    flap = rbox((0, -0.37, 1.04), (0.38, 0.22, 0.1), 0.04, 2)
    pocket = rbox((0, -0.475, 0.8), (0.26, 0.05, 0.16), 0.03, 2)
    straps = []
    for s in (1, -1):
        straps.append((tube([(0.13 * s, -0.28, 1.04), (0.15 * s, -0.05, 1.15), (0.17 * s, 0.2, 1.03), (0.19 * s, 0.29, 0.86), (0.17 * s, 0.27, 0.7)],
                            0.025, 8), "HatDark"))
    objs.append(join_parts("Acc_backpack", [(pack, "Hat"), (flap, "HatDark"), (pocket, "HatDark")] + straps, "chest"))
    # mustache: two curly bushy halves under the nose
    mu = []
    for s in (1, -1):
        mu.append((face_tube([(0.005 * s, -0.07), (0.05 * s, -0.08), (0.09 * s, -0.07), (0.11 * s, -0.045)], [0.03, 0.032, 0.024, 0.014], 0.012), "Hair"))
    objs.append(join_parts("Acc_mustache", mu, "head"))
    # hair: a little tuft on top (shown when no hat)
    tuft = []
    for k, (u, ang) in enumerate(((-0.06, -0.5), (0.0, 0.0), (0.06, 0.5))):
        base = hc + Vector((u, 0.12, c - 0.02))
        tip = base + Vector((math.sin(ang) * 0.06, 0.08, 0.07))
        tuft.append((tube([base, (base + tip) / 2 + Vector((0, 0, 0.03)), tip], [0.05, 0.035, 0.012], 8), "Hair"))
    tuft.append((ball(hc + Vector((0, 0.03, c - 0.03)), (0.2, 0.18, 0.06), 16, 8), "Hair"))
    objs.append(join_parts("Hair", tuft, "head"))
    return objs


def join_parts(name, parts, bone):
    obs = [new_obj(f"{name}_{i}", bm, material, bone) for i, (bm, material) in enumerate(parts)]
    return join(name, obs)


def join(name, obs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def build_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "Armature"
    arm.data.name = "Armature"
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, head, tail, parent in BONES:
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def skin(arm, obs):
    for ob in obs:
        ob.parent = arm
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = arm


# --- Animation -------------------------------------------------------------------------------------------------------
# A pose: {bone: (rx, ry, rz)} in degrees, about the ARMATURE axes (X = right, Y = front, Z = up) as seen from the
# bone's rest orientation (so "upper_arm.R": (60, 0, 0) swings the right arm forward). "sym" entries are written for
# the right side and mirrored to the left; "loc" moves the hips (metres, armature axes).
#   +X rotation: a hanging limb swings forward; the head / spine bends forward with -X... (see below)
# For spine/neck/head (pointing up), +X tips them backwards (looking up); -X bends forward.
# For the right arm, -Y raises it outwards (sideways); +Z turns it inwards. Left side mirrored automatically.

ALL_BONES = [b[0] for b in BONES]


def _mirror(name):
    return name.replace(".R", ".L") if name.endswith(".R") else name.replace(".L", ".R")


def expand(pose):
    """Pose dict with 'R:' shorthand -> full {bone: (rx, ry, rz)} (both sides when given as 'both:<bone>')."""
    out = {}
    for k, v in pose.items():
        if k == "loc":
            continue
        if k.startswith("both:"):
            n = k[5:]
            out[n + ".R"] = v
            out[n + ".L"] = (v[0], -v[1], -v[2])
        elif k.startswith("L:"):  # given in right-side terms, mirrored onto the left bone
            out[k[2:] + ".L"] = (v[0], -v[1], -v[2])
        elif k.startswith("R:"):
            out[k[2:] + ".R"] = v
        else:
            out[k] = v
    return out


def set_pose(arm, pose):
    p = expand(pose)
    for name in ALL_BONES:
        pb = arm.pose.bones[name]
        rest = pb.bone.matrix_local.to_quaternion()
        rx, ry, rz = p.get(name, (0, 0, 0))
        q = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        pb.location = (0, 0, 0)
    loc = Vector(pose.get("loc", (0, 0, 0)))
    hips = arm.pose.bones["hips"]
    hips.location = hips.bone.matrix_local.to_quaternion().inverted() @ loc


def key_all(arm, frame):
    for name in ALL_BONES:
        pb = arm.pose.bones[name]
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        pb.keyframe_insert("location", frame=frame, group=name)


def make_action(arm, name, keys, cyclic=False):
    """keys: [(time in seconds, pose)]. A cyclic action repeats its first pose at the end."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = act
    for t, pose in keys:
        set_pose(arm, pose)
        key_all(arm, 1 + round(t * FPS))
    # smooth: auto-clamped bezier (default); cyclic: add a cycle modifier hint by matching ends (done by the caller)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 1, act)
    strip.name = name
    arm.animation_data.action = None
    return act


def cycle(keys, length):
    """Appends the first pose at `length` so the loop is seamless."""
    return keys + [(length, keys[0][1])]


# Base stance pieces
ARMS_DOWN = {"both:upper_arm": (0, 0, 0), "both:forearm": (12, 0, 0)}


def walk_keys(length, stride, arm_swing, bounce, lean, knee, run=False):
    keys = []
    for i, phase in enumerate((0.0, 0.25, 0.5, 0.75)):
        s = 1.0 if i in (0, 1) else -1.0  # which leg is forward
        contact = i % 2 == 0
        thigh_f = stride if contact else stride * 0.25
        thigh_b = -stride * 0.8 if contact else -stride * 0.1
        shin_b = knee * (0.4 if contact else 1.4)
        shin_f = knee * (0.15 if contact else 0.4)
        # right leg forward when s > 0
        r_thigh, l_thigh = (thigh_f, thigh_b) if s > 0 else (thigh_b, thigh_f)
        r_shin, l_shin = (-shin_f, -shin_b) if s > 0 else (-shin_b, -shin_f)
        if not contact:
            # passing pose: swing leg lifted
            r_thigh, l_thigh = (stride * 0.35, -stride * 0.1) if s < 0 else (-stride * 0.1, stride * 0.35)
            r_shin, l_shin = (-knee * 1.6, -knee * 0.2) if s < 0 else (-knee * 0.2, -knee * 1.6)
        arm_r = -arm_swing * (1 if r_thigh > l_thigh else -1) if contact else 0.0
        pose = {
            "loc": (0, 0, -bounce if contact else bounce * 0.6),
            "thigh.R": (r_thigh, 0, 0), "thigh.L": (l_thigh, 0, 0),
            "shin.R": (r_shin, 0, 0), "shin.L": (l_shin, 0, 0),
            "foot.R": (-r_thigh * 0.3 - r_shin * 0.5 if contact else 15, 0, 0),
            "foot.L": (-l_thigh * 0.3 - l_shin * 0.5 if contact else 15, 0, 0),
            "R:upper_arm": (arm_r, -8, 0), "L:upper_arm": (-arm_r, -8, 0),
            "R:forearm": (25 if not run else 70, 0, 0), "L:forearm": (25 if not run else 70, 0, 0),
            "spine": (-lean, 0, (6 if run else 4) * s if contact else 0), "chest": (-lean * 0.5, 0, (-8 if run else -5) * s if contact else 0),
            "hips": (0, (4 if run else 3) * s if contact else 0, (-6 if run else -4) * s if contact else 0),
            "head": (lean * 0.8, 0, 0),
        }
        keys.append((length * phase, pose))
    return cycle(keys, length)


def build_actions(arm):
    A = {}
    # --- locomotion ---
    A["idle"] = cycle([
        (0.0, {**ARMS_DOWN, "L:upper_arm": (0, -6, 0), "R:upper_arm": (0, -6, 0), "loc": (0, 0, 0), "chest": (2, 0, 0), "head": (0, 0, 2)}),
        (1.0, {**ARMS_DOWN, "L:upper_arm": (2, -9, 0), "R:upper_arm": (2, -9, 0), "loc": (0, 0, -0.012), "chest": (-1, 0, 0), "head": (3, 0, -2),
               "both:forearm": (16, 0, 0), "spine": (-1, 0, 0)}),
    ], 2.0)
    A["walk"] = walk_keys(0.62, 32, 30, 0.025, 4, 30)
    A["run"] = walk_keys(0.46, 52, 55, 0.05, 12, 45, run=True)
    A["jump"] = [
        (0.0, {"loc": (0, 0, -0.08), "both:thigh": (40, 0, 0), "both:shin": (-60, 0, 0), "both:foot": (20, 0, 0), "spine": (-12, 0, 0),
               "both:upper_arm": (-30, -10, 0), "both:forearm": (20, 0, 0)}),
        (0.12, {"loc": (0, 0, 0.02), "both:thigh": (-5, 0, 0), "both:shin": (-5, 0, 0), "both:foot": (-20, 0, 0), "spine": (5, 0, 0),
                "both:upper_arm": (20, -70, 0), "both:forearm": (30, 0, 0), "head": (8, 0, 0)}),
        (0.35, {"loc": (0, 0, 0.0), "R:thigh": (50, 0, 0), "R:shin": (-80, 0, 0), "L:thigh": (10, 0, 0), "L:shin": (-40, 0, 0),
                "both:upper_arm": (10, -95, 0), "both:forearm": (25, 0, 0), "head": (5, 0, 0)}),
    ]
    A["fall"] = cycle([
        (0.0, {"R:thigh": (30, 0, 0), "R:shin": (-50, 0, 0), "L:thigh": (5, 0, 0), "L:shin": (-25, 0, 0),
               "both:upper_arm": (0, -110, 0), "both:forearm": (20, 0, 10), "head": (-5, 0, 0)}),
        (0.2, {"R:thigh": (20, 0, 0), "R:shin": (-35, 0, 0), "L:thigh": (15, 0, 0), "L:shin": (-45, 0, 0),
               "both:upper_arm": (0, -125, 0), "both:forearm": (30, 0, -10), "head": (-8, 0, 0)}),
    ], 0.4)
    A["crouch"] = cycle([
        (0.0, {"loc": (0, -0.03, -0.2), "both:thigh": (75, -6, 0), "both:shin": (-110, 0, 0), "both:foot": (35, 0, 0), "spine": (-18, 0, 0),
               "chest": (-8, 0, 0), "head": (22, 0, 0), "both:upper_arm": (35, -10, 0), "both:forearm": (40, 0, 0)}),
        (0.8, {"loc": (0, -0.03, -0.21), "both:thigh": (77, -6, 0), "both:shin": (-113, 0, 0), "both:foot": (36, 0, 0), "spine": (-20, 0, 0),
               "chest": (-9, 0, 0), "head": (24, 0, 0), "both:upper_arm": (38, -12, 0), "both:forearm": (44, 0, 0)}),
    ], 1.6)
    # --- upper-body holds (looped, blended over the legs) ---
    A["hold_tool"] = cycle([
        (0.0, {"R:upper_arm": (35, -12, 0), "R:forearm": (55, 0, -10), "R:hand": (-10, 0, 0)}),
        (0.8, {"R:upper_arm": (37, -12, 0), "R:forearm": (58, 0, -10), "R:hand": (-12, 0, 0)}),
    ], 1.6)
    A["carry_shoulder"] = cycle([  # a plank on the right shoulder, the right hand up and forward holding it on
        (0.0, {"R:upper_arm": (70, -18, 0), "R:forearm": (80, 0, 0), "R:hand": (-20, 0, 0), "L:upper_arm": (8, -6, 0), "L:forearm": (20, 0, 0),
               "chest": (0, 0, 5), "head": (0, 0, -8), "spine": (0, 0, 3)}),
        (0.5, {"R:upper_arm": (72, -18, 0), "R:forearm": (82, 0, 0), "R:hand": (-20, 0, 0), "L:upper_arm": (10, -6, 0), "L:forearm": (24, 0, 0),
               "chest": (-1, 0, 5), "head": (0, 0, -8), "spine": (0, 0, 3)}),
    ], 1.0)
    A["carry_front"] = cycle([  # rail / wheel / panel hugged in front, a little lean back
        (0.0, {"both:upper_arm": (40, -6, 18), "both:forearm": (60, 0, 25), "both:hand": (0, 0, 10), "spine": (6, 0, 0), "chest": (4, 0, 0)}),
        (0.5, {"both:upper_arm": (42, -6, 18), "both:forearm": (64, 0, 25), "both:hand": (0, 0, 10), "spine": (7, 0, 0), "chest": (5, 0, 0)}),
    ], 1.0)
    A["weld"] = cycle([  # both hands steady the torch, a slight crouch-lean and a tiny tremble
        (0.0, {"R:upper_arm": (55, -8, 10), "R:forearm": (55, 0, -15), "L:upper_arm": (55, -6, 30), "L:forearm": (70, 0, 40),
               "spine": (-8, 0, 0), "head": (8, 0, 0)}),
        (0.06, {"R:upper_arm": (56, -8, 10), "R:forearm": (54, 0, -15), "L:upper_arm": (55, -6, 30), "L:forearm": (71, 0, 40),
                "spine": (-8, 0, 0), "head": (8, 0, 0)}),
        (0.13, {"R:upper_arm": (55, -9, 11), "R:forearm": (56, 0, -14), "L:upper_arm": (56, -6, 30), "L:forearm": (70, 0, 40),
                "spine": (-8, 0, 0), "head": (8, 0, 0)}),
    ], 0.2)
    # --- one-shot tool actions (upper body) ---
    A["hammer"] = [  # wind up high over the shoulder, a fast overhead strike, recoil
        (0.0, {"R:upper_arm": (35, -12, 0), "R:forearm": (55, 0, -10)}),
        (0.16, {"R:upper_arm": (165, -20, 0), "R:forearm": (70, 0, 0), "R:hand": (-30, 0, 0), "spine": (6, 0, 6), "chest": (8, 0, 10), "head": (-5, 0, 0)}),
        (0.24, {"R:upper_arm": (55, -10, 0), "R:forearm": (10, 0, 0), "R:hand": (25, 0, 0), "spine": (-12, 0, -4), "chest": (-10, 0, -6), "head": (8, 0, 0)}),
        (0.3, {"R:upper_arm": (60, -10, 0), "R:forearm": (15, 0, 0), "R:hand": (20, 0, 0), "spine": (-10, 0, -4), "chest": (-8, 0, -6), "head": (8, 0, 0)}),
        (0.46, {"R:upper_arm": (35, -12, 0), "R:forearm": (55, 0, -10)}),
    ]
    A["wrench"] = [  # reach forward, twist the wrist round twice, pull back
        (0.0, {"R:upper_arm": (35, -12, 0), "R:forearm": (55, 0, -10)}),
        (0.15, {"R:upper_arm": (70, -5, 10), "R:forearm": (20, 0, 0), "R:hand": (0, 0, 0), "L:upper_arm": (60, -5, 25), "L:forearm": (40, 0, 30),
                "spine": (-10, 0, 0)}),
        (0.32, {"R:upper_arm": (70, -5, 10), "R:forearm": (20, -80, 0), "R:hand": (0, -30, 0), "L:upper_arm": (60, -5, 25), "L:forearm": (40, 0, 30),
                "spine": (-10, 0, 4), "chest": (0, 0, 8)}),
        (0.42, {"R:upper_arm": (70, -5, 10), "R:forearm": (20, -5, 0), "R:hand": (0, 0, 0), "L:upper_arm": (60, -5, 25), "L:forearm": (40, 0, 30),
                "spine": (-10, 0, 0)}),
        (0.6, {"R:upper_arm": (35, -12, 0), "R:forearm": (55, 0, -10)}),
    ]
    A["nail_gun"] = [  # sharp recoil kicking the arm up, settle
        (0.0, {"R:upper_arm": (70, -8, 5), "R:forearm": (25, 0, -5), "L:upper_arm": (55, -5, 30), "L:forearm": (55, 0, 35)}),
        (0.04, {"R:upper_arm": (88, -8, 5), "R:forearm": (40, 0, -5), "R:hand": (-25, 0, 0), "L:upper_arm": (62, -5, 30), "L:forearm": (60, 0, 35),
                "chest": (5, 0, 0), "head": (-4, 0, 0)}),
        (0.14, {"R:upper_arm": (68, -8, 5), "R:forearm": (24, 0, -5), "L:upper_arm": (55, -5, 30), "L:forearm": (55, 0, 35), "chest": (-1, 0, 0)}),
        (0.3, {"R:upper_arm": (70, -8, 5), "R:forearm": (25, 0, -5), "L:upper_arm": (55, -5, 30), "L:forearm": (55, 0, 35)}),
    ]
    A["crank"] = [  # come-along: both hands on the long handle, a big pump down and back up
        (0.0, {"both:upper_arm": (60, -5, 20), "both:forearm": (50, 0, 20), "spine": (-5, 0, 0)}),
        (0.2, {"both:upper_arm": (100, -5, 20), "both:forearm": (40, 0, 20), "spine": (4, 0, 0), "head": (-5, 0, 0)}),
        (0.38, {"both:upper_arm": (30, -5, 20), "both:forearm": (30, 0, 20), "spine": (-22, 0, 0), "chest": (-8, 0, 0), "head": (15, 0, 0)}),
        (0.56, {"both:upper_arm": (60, -5, 20), "both:forearm": (50, 0, 20), "spine": (-5, 0, 0)}),
    ]
    A["shovel"] = [  # scoop low on the left, swing up and throw forward-right into the firebox
        (0.0, {"R:upper_arm": (20, -5, 0), "R:forearm": (30, 0, 0), "L:upper_arm": (20, -5, 0), "L:forearm": (30, 0, 0)}),
        (0.3, {"R:upper_arm": (25, -5, 30), "R:forearm": (20, 0, 20), "L:upper_arm": (45, -5, 40), "L:forearm": (15, 0, 10),
               "spine": (-35, 0, 25), "chest": (-15, 0, 15), "head": (30, 0, -10)}),
        (0.55, {"R:upper_arm": (95, -5, 10), "R:forearm": (25, 0, 10), "L:upper_arm": (85, -5, 30), "L:forearm": (30, 0, 20),
                "spine": (0, 0, -15), "chest": (5, 0, -10), "head": (0, 0, 5)}),
        (0.68, {"R:upper_arm": (100, -5, 10), "R:forearm": (15, 0, 10), "L:upper_arm": (90, -5, 30), "L:forearm": (20, 0, 20),
                "spine": (-8, 0, -18), "chest": (-4, 0, -12)}),
        (0.95, {"R:upper_arm": (20, -5, 0), "R:forearm": (30, 0, 0), "L:upper_arm": (20, -5, 0), "L:forearm": (30, 0, 0)}),
    ]
    A["lever"] = [  # grab the lever high, haul it towards you with the body
        (0.0, {"R:upper_arm": (20, -8, 0), "R:forearm": (20, 0, 0)}),
        (0.15, {"R:upper_arm": (100, -8, 10), "R:forearm": (20, 0, 0), "R:hand": (10, 0, 0), "spine": (-8, 0, 0)}),
        (0.4, {"R:upper_arm": (60, -8, 10), "R:forearm": (70, 0, 0), "spine": (10, 0, -6), "chest": (6, 0, -6), "loc": (0, -0.03, -0.02)}),
        (0.6, {"R:upper_arm": (20, -8, 0), "R:forearm": (20, 0, 0)}),
    ]
    A["interact"] = [  # reach out and press / grab
        (0.0, {"R:upper_arm": (20, -8, 0), "R:forearm": (20, 0, 0)}),
        (0.14, {"R:upper_arm": (80, -6, 6), "R:forearm": (5, 0, 0), "R:hand": (-15, 0, 0), "spine": (-8, 0, 0), "head": (6, 0, 0)}),
        (0.26, {"R:upper_arm": (78, -6, 6), "R:forearm": (15, 0, 0), "R:hand": (10, 0, 0), "spine": (-8, 0, 0), "head": (6, 0, 0)}),
        (0.45, {"R:upper_arm": (20, -8, 0), "R:forearm": (20, 0, 0)}),
    ]
    A["wave"] = [  # big friendly wave over the head
        (0.0, {"R:upper_arm": (0, 0, 0), "R:forearm": (12, 0, 0)}),
        (0.2, {"R:upper_arm": (10, -150, 0), "R:forearm": (0, 0, -40), "head": (5, 0, -8), "chest": (0, 0, 5), "L:upper_arm": (0, -10, 0)}),
        (0.4, {"R:upper_arm": (10, -150, 0), "R:forearm": (0, 0, 20), "head": (5, 0, -8), "chest": (0, 0, 5)}),
        (0.6, {"R:upper_arm": (10, -150, 0), "R:forearm": (0, 0, -40), "head": (5, 0, -8), "chest": (0, 0, 5)}),
        (0.8, {"R:upper_arm": (10, -150, 0), "R:forearm": (0, 0, 20), "head": (5, 0, -8), "chest": (0, 0, 5)}),
        (1.0, {"R:upper_arm": (10, -150, 0), "R:forearm": (0, 0, -30), "head": (5, 0, -8), "chest": (0, 0, 5)}),
        (1.25, {"R:upper_arm": (0, 0, 0), "R:forearm": (12, 0, 0)}),
    ]
    # --- full body states ---
    A["downed"] = cycle([  # flat on the back, limbs splayed, a slow woozy breathe
        (0.0, {"root": (90, 0, 0), "loc": (0, 0.28, 0.0), "both:upper_arm": (0, -80, 0), "both:forearm": (0, 0, 30), "both:thigh": (5, -18, 0),
               "both:shin": (-10, 0, 0), "head": (0, 0, 25), "neck": (0, 0, 8)}),
        (1.2, {"root": (90, 0, 0), "loc": (0, 0.28, 0.0), "both:upper_arm": (0, -84, 0), "both:forearm": (0, 0, 35), "both:thigh": (5, -20, 0),
               "both:shin": (-12, 0, 0), "head": (0, 0, 19), "neck": (0, 0, 4), "chest": (3, 0, 0)}),
    ], 2.4)
    A["climb"] = cycle([  # hand over hand up a wall / rope, knees alternating
        (0.0, {"R:upper_arm": (160, -15, 0), "R:forearm": (40, 0, 0), "L:upper_arm": (110, -15, 0), "L:forearm": (80, 0, 0),
               "R:thigh": (20, 0, 0), "R:shin": (-30, 0, 0), "L:thigh": (70, 0, 0), "L:shin": (-90, 0, 0), "head": (15, 0, 0), "spine": (-5, 0, 0)}),
        (0.4, {"R:upper_arm": (110, -15, 0), "R:forearm": (80, 0, 0), "L:upper_arm": (160, -15, 0), "L:forearm": (40, 0, 0),
               "R:thigh": (70, 0, 0), "R:shin": (-90, 0, 0), "L:thigh": (20, 0, 0), "L:shin": (-30, 0, 0), "head": (15, 0, 0), "spine": (-5, 0, 0)}),
    ], 0.8)
    for name, keys in A.items():
        make_action(arm, name, keys)
    return list(A)


# --- Build ------------------------------------------------------------------------------------------------------------

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.armatures, bpy.data.actions):
        for item in list(block):
            block.remove(item)
    _mats.clear()


def build_character():
    clear_scene()
    bpy.context.scene.render.fps = FPS
    body = join("Body", build_body())
    variants = build_eyes() + build_mouths() + build_accessories()
    arm = build_armature()
    skin(arm, [body] + variants)
    names = build_actions(arm)
    set_pose(arm, {})
    path = os.path.join(OUT, "character.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_frame_range=False, export_anim_single_armature=True, export_reset_pose_bones=True,
                              export_def_bones=False, export_skins=True, export_morph=False)
    print("exported", path, "with", len(names), "animations:", ", ".join(names))
    if PREVIEW:
        render_preview(PREVIEW)


def build_fp_arm():
    """First-person arm: bare cartoon hand with curled fingers (Skin) and the jacket sleeve (Outfit + cuff)."""
    clear_scene()
    parts = [new_obj("palm", ball((0, 0.0, 0), (0.058, 0.062, 0.03), 18, 10), "Skin")]
    for k in range(4):
        x = -0.036 + k * 0.024
        ln = 0.045 if k in (1, 2) else 0.038
        pts = [(x, 0.045, 0.0), (x, 0.045 + ln * 0.7, -0.004), (x, 0.05 + ln, -0.026), (x, 0.04 + ln * 0.8, -0.048)]
        parts.append(new_obj(f"finger{k}", tube(pts, 0.0135, 10), "Skin"))
    parts.append(new_obj("thumb", tube([(-0.045, 0.0, -0.005), (-0.07, 0.035, -0.02), (-0.066, 0.065, -0.035)], [0.019, 0.017, 0.015], 10), "Skin"))
    parts.append(new_obj("wrist", capsule((0, -0.02, -0.003), (0, -0.09, -0.008), 0.04, 0.046, 16, 3), "Skin"))
    parts.append(new_obj("cuff", capsule((0, -0.1, -0.012), (0, -0.14, -0.016), 0.066, 0.068, 18, 3), "OutfitDark"))
    parts.append(new_obj("sleeve", capsule((0, -0.13, -0.02), (0, -0.48, -0.04), 0.07, 0.08, 18, 4), "Outfit"))
    parts.append(new_obj("stripe", capsule((0, -0.27, -0.028), (0, -0.3, -0.03), 0.074, 0.075, 18, 2), "Stripe"))
    join("FpArm", parts)
    path = os.path.join(OUT, "fp_arm.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True, export_animations=False)
    print("exported", path)


def render_preview(path):
    """Quick EEVEE turnaround render of the default look (for checking the model without Godot)."""
    scene = bpy.context.scene
    arm = scene.objects["Armature"]
    for tr in arm.animation_data.nla_tracks:
        tr.mute = True
    set_pose(arm, {})
    for name in [o.name for o in scene.objects]:
        o = scene.objects[name]
        if o.type == "MESH" and (o.name.startswith("Acc_") or (o.name.startswith("Eyes_") and o.name != "Eyes_round")
                                 or (o.name.startswith("Mouth_") and o.name != "Mouth_smile")):
            o.hide_render = True
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (1.6, 3.2, 1.4)
    cam.rotation_euler = (math.radians(85), 0, math.radians(153))
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(40), 0, math.radians(30))
    scene.collection.objects.link(sun)
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.device = "CPU"
    world = bpy.data.worlds.new("w")
    world.color = (0.6, 0.6, 0.65)
    scene.world = world
    scene.render.resolution_x = 600
    scene.render.resolution_y = 700
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    if ONLY is None or "character" in ONLY:
        build_character()
    if ONLY is None or "arm" in ONLY:
        build_fp_arm()
    print("done")
