"""Headless Blender: import a GLB and render front/back/left/top views for shape inspection.
usage: blender -b -P turnaround.py -- <in.glb> <out_dir>"""
import bpy, sys, math, os
from mathutils import Vector

glb, out = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

# bounds in world space
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
center, size = (lo + hi) / 2, hi - lo
print("BBOX size xyz:", tuple(round(v, 3) for v in size), "verts:", sum(len(o.data.vertices) for o in meshes))

# grey matte material so form reads without textures
mat = bpy.data.materials.new("grey"); mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.6, 0.6, 1)
for o in meshes:
    o.data.materials.clear(); o.data.materials.append(mat)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = scene.render.resolution_y = 1024
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = max(size) * 1.15
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun)
sun.data.energy = 3.0

d = max(size) * 3
views = {  # name: (camera offset, rotation euler)
    "front": (Vector((0, -d, 0)), (math.pi / 2, 0, 0)),
    "back":  (Vector((0, d, 0)),  (math.pi / 2, 0, math.pi)),
    "left":  (Vector((-d, 0, 0)), (math.pi / 2, 0, -math.pi / 2)),
    "top":   (Vector((0, 0, d)),  (0, 0, 0)),
}
for name, (off, rot) in views.items():
    cam.location = center + off; cam.rotation_euler = rot
    sun.location = cam.location; sun.rotation_euler = rot
    scene.render.filepath = os.path.join(out, f"{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)
