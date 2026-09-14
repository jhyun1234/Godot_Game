"""Stage 4 blockout: import v2 GLB, scale to 2.5m, retopo, attach timber as separate objects, save + render.
usage: blender -b --factory-startup -P stage4_build.py -- <in.glb> <out.blend> <render_dir>"""
import bpy, sys, math, os
from mathutils import Vector

glb, out_blend, render_dir = sys.argv[sys.argv.index("--") + 1:][:3]
os.makedirs(render_dir, exist_ok=True)
H = 2.5  # standing height, metres (4m tunnel module reference)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in scene.objects if o.type == "MESH"]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Miner_Body"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# ---- 4-1 scale: feet on z=0, centred, height H
vs = [v.co for v in body.data.vertices]
lo = Vector([min(v[i] for v in vs) for i in range(3)])
hi = Vector([max(v[i] for v in vs) for i in range(3)])
s = H / (hi.z - lo.z)
for v in body.data.vertices:
    v.co = Vector(((v.co.x - (lo.x + hi.x) / 2) * s, (v.co.y - (lo.y + hi.y) / 2) * s, (v.co.z - lo.z) * s))
body.data.update()


def band(zlo, zhi, xmax=None, xmin=None, q=0.06):
    pts = [v.co for v in body.data.vertices if zlo <= v.co.z <= zhi
           and (xmax is None or v.co.x <= xmax) and (xmin is None or v.co.x >= xmin)]
    xs, zs = [p.x for p in pts], [p.z for p in pts]
    ys = sorted(p.y for p in pts)
    k = int(len(ys) * q)  # q-th percentile: ignore the few most protruding verts (ribs, organs)
    return dict(xmin=min(xs), xmax=max(xs), ymin=ys[k], ymax=ys[-1 - k], zc=sum(zs) / len(zs), n=len(pts))


# front of figure faces -Y after glTF import (verified by earlier front render). figure LEFT = +X.
chest = band(0.60 * H, 0.72 * H, xmax=0.35, xmin=-0.35)
arm_L = band(0.55 * H, 0.85 * H, xmin=0.55)        # +X arm (flesh)
shin_R = band(0.15 * H, 0.30 * H, xmax=-0.02)      # -X leg (bone)
back_up = band(0.72 * H, 0.80 * H, xmax=0.35, xmin=-0.35)
hand_x = max(v.co.x for v in body.data.vertices)
print("LANDMARKS chest", chest)
print("LANDMARKS arm_L", arm_L)
print("LANDMARKS shin_R", shin_R, "hand_x", round(hand_x, 3))


# ---- materials (matte, non-reflective)
def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1)
    p.inputs["Roughness"].default_value = 1.0
    return m


M = {k: mat(k, c) for k, c in {
    "살": (0.30, 0.30, 0.30), "뒤틀린_갱목": (0.36, 0.28, 0.19), "녹슨_주철": (0.22, 0.11, 0.07),
    "가죽끈": (0.14, 0.09, 0.07), "낡은_황동": (0.50, 0.40, 0.18), "탁한_석영": (0.75, 0.73, 0.70)}.items()}
body.data.materials.clear()
body.data.materials.append(M["살"])

# ---- 4-2 retopo: keep HI copy for baking, remesh working body
hi_col = bpy.data.collections.new("HI_source")
scene.collection.children.link(hi_col)
hi_obj = body.copy()
hi_obj.data = body.data.copy()
hi_obj.name = "Miner_Body_HI"
hi_col.objects.link(hi_obj)
hi_col.hide_render = True
hi_col.hide_viewport = True
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
body.data.remesh_voxel_size = 0.012  # ~1.2cm: closes the non-watertight source before quadriflow
bpy.ops.object.voxel_remesh()
print("after voxel:", len(body.data.polygons), "faces")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.separate(type="LOOSE")  # drop floating islands left by the voxel pass
bpy.ops.object.mode_set(mode="OBJECT")
parts = [o for o in bpy.context.selected_objects if o.type == "MESH"]
parts.sort(key=lambda o: len(o.data.vertices), reverse=True)
for o in parts[1:]:
    print("removing loose island", o.name, len(o.data.vertices), "verts")
    bpy.data.objects.remove(o, do_unlink=True)
body = parts[0]
body.name = "Miner_Body"
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
# ponytail: quadriflow refuses this mesh in background mode (manifold check fails despite 0 non-manifold edges);
# decimate-collapse is enough for a single hero enemy. Upgrade to a real retopo if skinning artefacts show up.
dec = body.modifiers.new("retopo", "DECIMATE")
dec.ratio = 0.5
bpy.ops.object.modifier_apply(modifier="retopo")
print("after decimate:", len(body.data.vertices), "verts", len(body.data.polygons), "faces")
bpy.ops.object.shade_smooth()
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
bpy.ops.object.mode_set(mode="OBJECT")

# ---- 4-3 timber: separate objects, parented to an empty (later: bones)
rig = bpy.data.objects.new("Timber_Rig", None)
scene.collection.objects.link(rig)


def box(name, dims, loc, rot=(0, 0, 0), m="뒤틀린_갱목", parent=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector(dims)
    o.data.materials.append(M[m])
    if parent:
        o.parent = rig
    return o


def strap(name, loc, rx, ry, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.012, location=loc, rotation=rot,
                                     major_segments=32, minor_segments=8)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector((rx, ry, 1))
    o.data.materials.append(M["가죽끈"])
    o.parent = rig
    sw = o.modifiers.new("hug", "SHRINKWRAP")
    sw.target = body
    sw.wrap_mode = "OUTSIDE_SURFACE"
    sw.offset = 0.008
    return o


def nail(name, base, tilt_x_deg, length=0.14):
    t = math.radians(tilt_x_deg)
    axis = Vector((0, -math.sin(t), math.cos(t)))
    bpy.ops.mesh.primitive_cube_add(size=1, location=Vector(base) + axis * (length / 2), rotation=(t, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector((0.03, 0.03, length))
    o.data.materials.append(M["녹슨_주철"])
    o.parent = rig
    return o


# chest: two planks crossing (X) on the front surface, three straps around torso
cz = 0.66 * H
cy = chest["ymin"] - 0.015
box("Plank_Chest_A", (0.95, 0.03, 0.15), (0, cy, cz), rot=(0, math.radians(38), 0))
box("Plank_Chest_B", (0.95, 0.03, 0.15), (0, cy, cz), rot=(0, math.radians(-38), 0))
for i, z in enumerate((0.58 * H, 0.66 * H, 0.74 * H)):
    b = band(z - 0.02, z + 0.02, xmax=0.35, xmin=-0.35)
    strap(f"Strap_Torso_{i}", (0, (b["ymin"] + b["ymax"]) / 2, z),
          (b["xmax"] - b["xmin"]) / 2 + 0.03, (b["ymax"] - b["ymin"]) / 2 + 0.035)

# left forearm splint (+X, flesh arm): plank on the front of the forearm, two straps around the arm
fx = 0.62 * hand_x
fa = band(arm_L["zc"] - 0.08, arm_L["zc"] + 0.08, xmin=fx - 0.12, xmax=fx + 0.12)
box("Plank_Forearm_L", (0.36, 0.025, 0.06), (fx, fa["ymin"] - 0.012, fa["zc"]))
ar = max((fa["ymax"] - fa["ymin"]) / 2, 0.03) + 0.015
for i, x in enumerate((fx - 0.11, fx + 0.11)):
    strap(f"Strap_Forearm_{i}", (x, (fa["ymin"] + fa["ymax"]) / 2, fa["zc"]), ar, ar, rot=(0, math.radians(90), 0))

# right shin splint (-X, bone leg)
sx = (shin_R["xmin"] + shin_R["xmax"]) / 2
sz = 0.22 * H
box("Plank_Shin_R", (0.07, 0.025, 0.42), (sx, shin_R["ymin"] - 0.012, sz))
lr = max((shin_R["xmax"] - shin_R["xmin"]) / 2, (shin_R["ymax"] - shin_R["ymin"]) / 2) + 0.012
for i, z in enumerate((sz - 0.15, sz + 0.15)):
    strap(f"Strap_Shin_{i}", (sx, (shin_R["ymin"] + shin_R["ymax"]) / 2, z), lr, lr)

# back plank: diagonal up over the RIGHT shoulder (-X); top stays below the head so it never reads as a second head
L = 1.15
ang = math.radians(-35)  # local +Z tilts toward -X: top end lands over the right shoulder
top = Vector((-0.33, 0, 0.90 * H))  # below helmet top (1.0H) but clearly above the shoulder line (0.78H)
axis = Vector((math.sin(ang), 0, math.cos(ang)))
c = top - axis * (L / 2)
box("Plank_Back", (0.15, 0.03, L), (c.x, back_up["ymax"] + 0.018, c.z), rot=(0, ang, 0))

# nails: 5, upper back / shoulders, all leaning backward (+Y) so the silhouette stays a body, not a sea urchin
by = back_up["ymax"]
for i, (x, z) in enumerate(((-0.28, 0.79 * H), (-0.12, 0.81 * H), (0.05, 0.78 * H), (0.20, 0.80 * H), (0.30, 0.76 * H))):
    nail(f"Nail_{i}", (x, by - 0.02, z), tilt_x_deg=-65, length=0.22)

# ---- 4m tunnel gauge (render reference only): 4m tall post + 4m wide floor bar
box("Gauge_4m_post", (0.03, 0.03, 4.0), (-2.3, 0, 2.0), m="탁한_석영", parent=False)
box("Gauge_4m_floor", (4.0, 0.03, 0.03), (0, 0.6, 0.0), m="탁한_석영", parent=False)

bpy.ops.wm.save_as_mainfile(filepath=out_blend)
print("saved", out_blend, "body faces", len(body.data.polygons))

# body only, for Mixamo auto-rig (accepts FBX/OBJ, not GLB). Timber is parented to bones after rigging.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
fbx = os.path.join(os.path.dirname(out_blend), "miner_body_for_mixamo.fbx")
bpy.ops.export_scene.fbx(filepath=fbx, use_selection=True, apply_scale_options="FBX_SCALE_ALL", path_mode="COPY")
print("exported", fbx)

# ---- renders
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = scene.render.resolution_y = 1024
world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 4.6
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
scene.collection.objects.link(sun)
sun.data.energy = 3
center = Vector((0, 0, 2.0))
d = 8
views = (("front", (0, -d, 0), (math.pi / 2, 0, 0)),
         ("back", (0, d, 0), (math.pi / 2, 0, math.pi)),
         ("left", (d, 0, 0), (math.pi / 2, 0, math.pi / 2)),
         ("iso", (-d * .7, -d * .7, 2.5), (math.radians(72), 0, math.radians(-45))))
for name, off, rot in views:
    cam.location = center + Vector(off)
    cam.rotation_euler = rot
    sun.rotation_euler = rot
    scene.render.filepath = os.path.join(render_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", name)
