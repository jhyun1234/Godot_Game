"""Stage 7 (pipeline 4-4, proposal #40): texture generated ON the mesh + real surface detail.
Two modes:
  blender -b --factory-startup -P blender/stage7_bake.py -- export
      stage-4 low body (Miner_Body, 33k faces, no timber) -> mesh/miner_body_low.glb   (input for gen_paint.py)
  blender -b --factory-startup -P blender/stage7_bake.py -- bake
      stage-6 .blend (rig + textured timber) + mesh/miner_painted.glb (Hunyuan3D-2.0 paint output, new UVs)
      + stage-4 Miner_Body_HI (201k faces):
      bake painted colour -> rigged body UV (selected-to-active, same surface)  = stage7_tex/miner_skin_albedo.jpg
      bake HI geometry    -> tangent normal map                                  = stage7_tex/miner_skin_normal.png
      -> darken, matte, renders, blender/miner_v2_stage7.blend, mesh/miner_rigged.glb"""
import bpy, os, sys, math
import numpy as np
from mathutils import Vector

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE4 = os.path.join(ROOT, "blender", os.environ.get("HI_BLEND", "miner_v2_stage10.blend"))   # #41/#42/#43: HI copy with the separate head + hands + torso relief
STAGE6 = os.path.join(ROOT, "blender", "miner_v2_stage6.blend")
LOW_GLB = os.path.join(ROOT, "mesh", "miner_body_low.glb")
PAINTED = os.path.join(ROOT, "mesh", "miner_painted.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage7.blend")
OUT_GLB = os.path.join(ROOT, "mesh", "miner_rigged.glb")
TEX = os.path.join(ROOT, "blender", "stage7_tex")
RENDER = os.path.join(ROOT, "blender", "stage7_render")

BAKE_PX = 2048
SKIN_DARKEN = float(os.environ.get("SKIN_DARKEN", "1.0"))   # paint output is already dark (bake luma 0.09 vs projected 0.19 in #39)
ROUGHNESS = float(os.environ.get("ROUGHNESS", "1.0"))
NORMAL_STRENGTH = 1.0
CAGE_M = 0.02            # selected-to-active: how far outside the low body the rays start
RAY_M = 0.06             # max ray distance (HI/painted surfaces sit within mm of the low body)

mode = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "bake"

# ---------------------------------------------------------------- export
if mode == "export":
    bpy.ops.wm.open_mainfile(filepath=STAGE4)
    body = bpy.data.objects["Miner_Body"]
    bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=LOW_GLB, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_animations=False, export_skins=False, export_materials="NONE")
    print("exported", LOW_GLB, "faces", len(body.data.polygons), round(os.path.getsize(LOW_GLB) / 1e6, 2), "MB")
    raise SystemExit

# ---------------------------------------------------------------- bake
os.makedirs(TEX, exist_ok=True); os.makedirs(RENDER, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=STAGE6)
scene = bpy.context.scene
arm = bpy.data.objects["Miner_Rig"]; body = bpy.data.objects["Miner_Body"]
arm.data.pose_position = "REST"                       # T-pose = stage-4 coordinates (stage-5 log: offset 0)
bpy.context.view_layer.update()


def world_bbox(o):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    pts = [ev.matrix_world @ v.co for v in ev.data.vertices]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


def align_to_body(o, label):
    """uniform-scale + translate o so its world bbox matches the rest-pose body (guards against unit/centre drift)"""
    blo, bhi = world_bbox(body); olo, ohi = world_bbox(o)
    s = (bhi.z - blo.z) / max(ohi.z - olo.z, 1e-6)
    o.scale *= s
    bpy.context.view_layer.update()
    olo, ohi = world_bbox(o)
    o.location += (blo + bhi) * 0.5 - (olo + ohi) * 0.5
    bpy.context.view_layer.update()
    olo, ohi = world_bbox(o)
    err = max((olo - blo).length, (ohi - bhi).length)
    print("%s aligned: scale %.4f  bbox err %.4f m" % (label, s, err))
    assert err < 0.03, "%s does not overlay the body (bbox err %.3f)" % (label, err)


def px_array(img):
    w, h = img.size
    return np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)


def save_image(name, arr, fmt="PNG", colorspace="sRGB"):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.colorspace_settings.name = colorspace
    a = np.ones((h, w, 4), dtype=np.float32); a[:, :, :3] = np.clip(arr[:, :, :3], 0, 1)
    img.pixels.foreach_set(a.ravel())
    img.filepath_raw = os.path.join(TEX, name + (".jpg" if fmt == "JPEG" else ".png"))
    img.file_format = fmt
    img.save()
    return img


def bake_to_body(kind, target_img, colorspace):
    """selected (source objects) -> active (body) bake into target_img on the body's UV"""
    skin = bpy.data.materials["살"]
    nt = skin.node_tree
    tnode = nt.nodes.new("ShaderNodeTexImage"); tnode.image = target_img; nt.nodes.active = tnode
    target_img.colorspace_settings.name = colorspace
    scene.render.engine = "CYCLES"; scene.cycles.samples = 4; scene.cycles.device = "CPU"
    b = scene.render.bake
    b.use_selected_to_active = True; b.use_cage = False; b.cage_extrusion = CAGE_M; b.max_ray_distance = RAY_M
    b.margin = 24; b.use_clear = True
    b.use_pass_direct = False; b.use_pass_indirect = False; b.use_pass_color = True
    bpy.context.view_layer.objects.active = body
    body.data.uv_layers.active = body.data.uv_layers[0]
    bpy.ops.object.bake(type=kind)
    nt.nodes.remove(tnode)


# ---- 1. painted mesh (new UVs, same surface) -> colour on the rigged body's UV
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=PAINTED)
painted = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
assert len(painted) == 1, painted
painted = painted[0]; painted.name = "Painted"
for o in [o for o in bpy.data.objects if o not in before and o.type != "MESH"]:
    bpy.data.objects.remove(o, do_unlink=True)
if painted.parent:
    m = painted.matrix_world.copy(); painted.parent = None; painted.matrix_world = m
align_to_body(painted, "painted")
pm = painted.active_material
assert pm is not None and any(n.type == "TEX_IMAGE" and n.image for n in pm.node_tree.nodes), "painted mesh has no texture"
paint_img = [n.image for n in pm.node_tree.nodes if n.type == "TEX_IMAGE" and n.image][0]
print("painted faces", len(painted.data.polygons), "texture", paint_img.size[:])
# the glTF-imported material yields nothing in a selected-to-active bake (Blender 5.2: 0 hits, cause not chased) — a plain
# Principled(image) on the same mesh bakes fine, so swap it in
simple = bpy.data.materials.new("painted_simple"); simple.use_nodes = True
sp = simple.node_tree.nodes["Principled BSDF"]; st = simple.node_tree.nodes.new("ShaderNodeTexImage"); st.image = paint_img
simple.node_tree.links.new(st.outputs["Color"], sp.inputs["Base Color"])
painted.data.materials.clear(); painted.data.materials.append(simple)
alb_target = bpy.data.images.new("bake_albedo", BAKE_PX, BAKE_PX, alpha=False)
bpy.ops.object.select_all(action="DESELECT"); painted.select_set(True); body.select_set(True)
bake_to_body("DIFFUSE", alb_target, "sRGB")
col = px_array(alb_target)[:, :, :3]
lum = col[:, :, 0] * 0.2126 + col[:, :, 1] * 0.7152 + col[:, :, 2] * 0.0722
print("albedo bake luma mean %.3f  p10 %.3f  p90 %.3f" % (lum.mean(), np.percentile(lum, 10), np.percentile(lum, 90)))
albedo = save_image("miner_skin_albedo", col * SKIN_DARKEN, "JPEG")
bpy.data.images.remove(alb_target)
bpy.data.objects.remove(painted, do_unlink=True)

# ---- 2. HI source (201k faces, stage 4) -> tangent normal map on the low body
with bpy.data.libraries.load(STAGE4, link=False) as (src, dst):
    dst.objects = ["Miner_Body_HI"]
hi = dst.objects[0]; scene.collection.objects.link(hi); hi.parent = None
hi.hide_render = False; hi.hide_viewport = False
align_to_body(hi, "HI")
nrm_target = bpy.data.images.new("bake_normal", BAKE_PX, BAKE_PX, alpha=False)
bpy.ops.object.select_all(action="DESELECT"); hi.select_set(True); body.select_set(True)
scene.render.bake.normal_space = "TANGENT"
bake_to_body("NORMAL", nrm_target, "Non-Color")
nrm = px_array(nrm_target)[:, :, :3]
flat = np.abs(nrm - np.array([0.5, 0.5, 1.0])).max(2)
print("normal bake: mean |dev| %.4f  px with dev > 0.05: %.1f%%" % (flat.mean(), (flat > 0.05).mean() * 100))
normal = save_image("miner_skin_normal", nrm, "PNG", "Non-Color")
bpy.data.images.remove(nrm_target)
bpy.data.objects.remove(hi, do_unlink=True)

# ---- 3. skin material: painted albedo + HI normal, matte
skin = bpy.data.materials["살"]
nt = skin.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
N = nt.nodes; L = nt.links
p = N.new("ShaderNodeBsdfPrincipled"); o = N.new("ShaderNodeOutputMaterial"); L.new(p.outputs[0], o.inputs["Surface"])
p.inputs["Roughness"].default_value = ROUGHNESS; p.inputs["Metallic"].default_value = 0.0
p.inputs["Specular IOR Level"].default_value = 0.2
t = N.new("ShaderNodeTexImage"); t.image = albedo; L.new(t.outputs["Color"], p.inputs["Base Color"])
t2 = N.new("ShaderNodeTexImage"); t2.image = normal; nm = N.new("ShaderNodeNormalMap")
nm.inputs["Strength"].default_value = NORMAL_STRENGTH
L.new(t2.outputs["Color"], nm.inputs["Color"]); L.new(nm.outputs[0], p.inputs["Normal"])
for m in bpy.data.materials:                       # #39 timber/iron/strap materials stay; make sure roughness knob applies to all
    if m.use_nodes and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Roughness"].default_value = ROUGHNESS
                n.inputs["Metallic"].default_value = 0.0

# ---- 4. renders: walk_crouch f16 front/left/iso + face 1.6 m, one spot from the camera (headlamp)
arm.data.pose_position = "POSE"
actions = {a.name: a for a in bpy.data.actions}
for tr in arm.animation_data.nla_tracks:
    tr.mute = True
ad = arm.animation_data; ad.action = actions["walk_crouch"]
if hasattr(ad, "action_slot") and actions["walk_crouch"].slots:
    ad.action_slot = actions["walk_crouch"].slots[0]
scene.frame_set(16)
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.02, 0.02, 0.02, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 35
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
lamp = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "SPOT")); scene.collection.objects.link(lamp)
lamp.data.energy = 400; lamp.data.spot_size = math.radians(60); lamp.data.shadow_soft_size = 0.1
views = {"front": ((0, -4.5, 1.2), (math.radians(88), 0, 0)), "left": ((4.5, 0, 1.2), (math.radians(88), 0, math.radians(90))),
         "iso": ((-3.2, -3.2, 1.6), (math.radians(80), 0, math.radians(-45))), "face": ((0.3, -1.6, 1.5), (math.radians(90), 0, math.radians(10)))}
for vname, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; lamp.location = loc; lamp.rotation_euler = rot
    lamp.data.energy = 120 if vname == "face" else 400
    scene.render.filepath = os.path.join(RENDER, f"walk_crouch_f16_{vname}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", list(views))
for ob in (cam, lamp):
    bpy.data.objects.remove(ob, do_unlink=True)
for tr in arm.animation_data.nla_tracks:
    tr.mute = False
ad.action = None

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_apply=True, export_yup=True, export_skins=True, export_image_format="AUTO")
print("exported", OUT_GLB, round(os.path.getsize(OUT_GLB) / 1e6, 2), "MB")
