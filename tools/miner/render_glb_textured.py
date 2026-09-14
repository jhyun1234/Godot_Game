import bpy, sys, os, math
glb, outdir = sys.argv[sys.argv.index("--") + 1:][:2]
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
objs = [o for o in bpy.data.objects if o.type == "MESH"]
xs = [ (o.matrix_world @ v.co) for o in objs for v in o.data.vertices ]
lo = [min(p[i] for p in xs) for i in range(3)]; hi = [max(p[i] for p in xs) for i in range(3)]
c = [(lo[i] + hi[i]) / 2 for i in range(3)]; size = max(hi[i] - lo[i] for i in range(3))
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.25, 0.25, 1); w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); cam.data.type = "ORTHO"; cam.data.ortho_scale = size * 1.15; scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 4; scene.collection.objects.link(sun)
d = size * 3
views = {"front": ((c[0], c[1] - d, c[2]), (math.pi / 2, 0, 0)), "back": ((c[0], c[1] + d, c[2]), (math.pi / 2, 0, math.pi)),
         "left": ((c[0] + d, c[1], c[2]), (math.pi / 2, 0, math.pi / 2)), "iso": ((c[0] - d * 0.7, c[1] - d * 0.7, c[2] + d * 0.4), (math.radians(65), 0, math.radians(-45)))}
for n, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; sun.rotation_euler = rot
    scene.render.filepath = os.path.join(outdir, n + ".png"); bpy.ops.render.render(write_still=True)
print("RENDERED", outdir, "bbox", [round(hi[i] - lo[i], 3) for i in range(3)], "faces", sum(len(o.data.polygons) for o in objs))
