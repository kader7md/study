"""Renders showcase pictures of the exported .glb models (train, damaged train, tools, nature).

    blender --background --python blender/scripts/render_showcase.py -- <repo_root> <out_dir> [shots=train,damaged,tools,nature]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
ROOT, OUT = argv[0], argv[1]
SHOTS = next((a.split("=", 1)[1].split(",") for a in argv if a.startswith("shots=")), ["train", "damaged", "tools", "nature"])
M = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 48
    s.cycles.use_denoising = True
    s.render.resolution_x = 1600
    s.render.resolution_y = 900
    s.view_settings.view_transform = "AgX"
    s.view_settings.look = "AgX - Medium High Contrast"
    world = bpy.data.worlds.new("sky")
    s.world = world
    world.use_nodes = True
    nt = world.node_tree
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(28)
    sky.sun_rotation = math.radians(140)
    nt.links.new(sky.outputs[0], nt.nodes["Background"].inputs[0])
    nt.nodes["Background"].inputs[1].default_value = 0.35
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(55), 0, math.radians(140)))
    sun = bpy.context.active_object
    sun.data.energy = 3.5
    sun.data.angle = math.radians(2)


def ground(color=(0.18, 0.22, 0.12), size=200):
    bpy.ops.mesh.primitive_plane_add(size=size)
    g = bpy.context.active_object
    m = bpy.data.materials.new("ground")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    noise = m.node_tree.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.6
    ramp = m.node_tree.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*[c * 0.7 for c in color], 1)
    ramp.color_ramp.elements[1].color = (*[min(c * 1.5, 1) for c in color], 1)
    m.node_tree.links.new(noise.outputs["Fac"], ramp.inputs[0])
    m.node_tree.links.new(ramp.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    g.data.materials.append(m)
    return g


def track(length=60):
    m = bpy.data.materials.new("sleeper")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.12, 0.08, 0.05, 1)
    r = bpy.data.materials.new("railm")
    r.use_nodes = True
    r.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.33, 0.32, 1)
    r.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.9
    b = bpy.data.materials.new("ballast")
    b.use_nodes = True
    b.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.22, 0.2, 0.18, 1)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.1))
    o = bpy.context.active_object
    o.scale = (3.4, length, 0.25)
    o.data.materials.append(b)
    y = -length / 2
    while y < length / 2:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, y, 0.06))
        o = bpy.context.active_object
        o.scale = (2.4, 0.25, 0.12)
        o.data.materials.append(m)
        y += 0.65
    for x in (-0.75, 0.75):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(x, 0, 0.2))
        o = bpy.context.active_object
        o.scale = (0.08, length, 0.15)
        o.data.materials.append(r)


def load(path, offset=(0, 0, 0), rot_z=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location = Vector(o.location) + Vector(offset)
            o.rotation_euler.z += rot_z
    return new


def camera(loc, target, lens=35):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.active_object
    cam.data.lens = lens
    t = bpy.data.objects.new("target", None)
    bpy.context.collection.objects.link(t)
    t.location = target
    c = cam.constraints.new("TRACK_TO")
    c.target = t
    bpy.context.scene.camera = cam


def render(name):
    bpy.context.scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)


def train_scene(damaged=False):
    reset()
    ground()
    track(80)
    # glTF import converts Godot/glTF -Z forward back to Blender +Y forward
    y = 0.0
    names = ["locomotive", "cargo_wagon", "utility_wagon", "container_wagon"]
    lengths = [10.0, 8.0, 8.0, 8.0]
    for n, l in zip(names, lengths):
        objs = load(os.path.join(M, "train", n + ".glb"), (0, y - l / 2, 0))
        if damaged:
            for i, o in enumerate(o for o in objs if o.name.startswith(("Panel", "Door"))):
                if i % 2 == 0:
                    o.hide_render = True
        y -= l + 1.0
    if damaged:
        camera((-9.5, 8.5, 4.0), (0, -4, 1.8), 30)
    else:
        camera((10.5, 9.5, 4.2), (0, -6, 1.6), 28)
    render("train_damaged" if damaged else "train")


def tools_scene():
    reset()
    g = ground((0.25, 0.2, 0.15), 20)
    items = [("props/hammer.glb", (-0.9, 0, 0.3), 0), ("props/nail_gun.glb", (-0.35, 0, 0.25), 0),
             ("props/welder_torch.glb", (0.15, 0, 0.2), 0), ("props/welder_machine.glb", (1.1, 0.2, 0), 0.4),
             ("props/wheel.glb", (-1.9, 0.4, 0.45), 0.3), ("props/plank.glb", (0.0, 1.0, 0.06), 0.0),
             ("props/rail.glb", (0.0, 1.6, 0.08), 1.57)]
    for path, off, rz in items:
        load(os.path.join(M, path), off, rz)
    camera((0.2, -3.6, 1.9), (-0.1, 0.3, 0.3), 40)
    render("tools")


def nature_scene():
    reset()
    ground((0.16, 0.24, 0.09), 120)
    items = [("pine", (-12, 6, 0)), ("pine_snow", (-6, 9, 0)), ("oak", (0, 8, 0)), ("birch", (6, 7, 0)),
             ("dead_tree", (11, 6, 0)), ("boulder", (-4, 0, 0)), ("rock_small", (-1.5, -1, 0)),
             ("cliff", (16, 14, 0)), ("bush", (3, -0.5, 0)), ("bush", (8, 0.5, 0))]
    for n, off in items:
        load(os.path.join(M, "nature", n + ".glb"), off)
    camera((0, -22, 6.5), (1, 6, 4), 30)
    render("nature")


if "train" in SHOTS:
    train_scene(False)
if "damaged" in SHOTS:
    train_scene(True)
if "tools" in SHOTS:
    tools_scene()
if "nature" in SHOTS:
    nature_scene()
print("done")
