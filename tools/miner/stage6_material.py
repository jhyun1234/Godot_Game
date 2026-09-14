"""Stage 6 (pipeline 4-4): materials. Project the Gemini front/back T-pose concept images onto the body
(bake to the smart-UV), derive a tangent normal map from the baked luminance, darken for "lamp off = gone",
put Poly Haven wood/rust on the timber, re-export the GLB. Rig and clips are untouched (loaded from stage 5).
usage: blender -b --factory-startup -P blender/stage6_material.py
Inputs:  blender/miner_v2_stage5.blend, miner_front_Tpose_clean.png, miner_back_Tpose_clean.png, textures/{rough_wood,rusty_metal_02}
Outputs: blender/stage6_tex/*.png|jpg, blender/miner_v2_stage6.blend, mesh/miner_rigged.glb, blender/stage6_render/*.png"""
import bpy, os, sys, math
import numpy as np
from mathutils import Vector

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE5 = os.path.join(ROOT, "blender", "miner_v2_stage5.blend")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage6.blend")
OUT_GLB = os.path.join(ROOT, "mesh", "miner_rigged.glb")
TEX = os.path.join(ROOT, "blender", "stage6_tex")
RENDER = os.path.join(ROOT, "blender", "stage6_render")
PH = os.path.join(ROOT, "textures")
FRONT_IMG = os.path.join(ROOT, "miner_front_Tpose_clean.png")
BACK_IMG = os.path.join(ROOT, "miner_back_Tpose_clean.png")
os.makedirs(TEX, exist_ok=True); os.makedirs(RENDER, exist_ok=True)

# ---- knobs (proposal #39)
BAKE_PX = 2048          # body colour + normal
SKIN_DARKEN = float(os.environ.get("SKIN_DARKEN", "0.5"))   # multiply on the projected colour. 1.0 = concept as drawn (sabotage)
NORMAL_STRENGTH = 1.0
HEIGHT_BLUR_PX = 4      # luminance -> height: box blur radius before the gradient
BLEND_NY = 0.25         # |normal.y| below this: front and back images are mixed (sides)
TIMBER_PX = 1024
WOOD_SCALE, RUST_SCALE = 2.0, 3.0
WOOD_DARKEN, RUST_DARKEN, STRAP_RGB = 0.6, 0.6, (0.05, 0.035, 0.03)
ROUGHNESS = float(os.environ.get("ROUGHNESS", "1.0"))
SKIN_KEEP = os.environ.get("SKIN_KEEP", "1") == "1"   # #45: the body carries its own generated textures (TRELLIS.2) — skip the concept-projection bake

bpy.ops.wm.open_mainfile(filepath=STAGE5)
scene = bpy.context.scene
arm = bpy.data.objects["Miner_Rig"]; body = bpy.data.objects["Miner_Body"]
timber = [o for o in bpy.data.objects if o.type == "MESH" and o is not body]
print("loaded", STAGE5, "timber", len(timber), "actions", len(bpy.data.actions), "nla", len(arm.animation_data.nla_tracks))


# ---- helpers
def figure_bbox(path):
    """pixel bbox (x0, x1, y0_top, y1_top, w, h) of the figure against the flat grey background"""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[:, :, :3]
    bg = px[h - 6, 5]                       # Blender rows start at the bottom: top-left corner is the last row
    mask = np.abs(px - bg).sum(2) > 30 / 255
    ys, xs = np.where(mask)
    y0b, y1b = ys.min(), ys.max()           # bottom-origin rows
    return img, (xs.min() / w, (xs.max() + 1) / w, y0b / h, (y1b + 1) / h)


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


def blur(a, r):
    if r <= 0:
        return a
    k = 2 * r + 1
    p = np.pad(a, r, mode="edge")
    c = np.cumsum(np.cumsum(p, 0), 1)
    c = np.pad(c, ((1, 0), (1, 0)))
    h, w = a.shape
    return (c[k:k + h, k:k + w] - c[:h, k:k + w] - c[k:k + h, :w] + c[:h, :w]) / (k * k)


def normal_from_height(hgt, strength):
    """tangent-space normal (OpenGL +Y up) from a height field, rows bottom-up like Blender pixels"""
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * 0.5
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * 0.5
    n = np.dstack((-dx * strength, -dy * strength, np.ones_like(hgt)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


if not SKIN_KEEP:
    # ---- 1. body in rest pose (T-pose = the concept images) + world bbox
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    pts = [ev.matrix_world @ v.co for v in ev.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
    print("REST world bbox", tuple(round(v, 3) for v in lo), tuple(round(v, 3) for v in hi))
    front_img, fb = figure_bbox(FRONT_IMG)
    back_img, bb = figure_bbox(BACK_IMG)
    print("front bbox(u0,u1,v0,v1)", [round(v, 4) for v in fb], "aspect", round((fb[1] - fb[0]) * front_img.size[0] / ((fb[3] - fb[2]) * front_img.size[1]), 3))
    print("back  bbox(u0,u1,v0,v1)", [round(v, 4) for v in bb], "aspect", round((bb[1] - bb[0]) * back_img.size[0] / ((bb[3] - bb[2]) * back_img.size[1]), 3))
    print("mesh aspect", round((hi.x - lo.x) / (hi.z - lo.z), 3))
    assert body.data.uv_layers, "body has no UV (stage 4 smart_project)"
    uv_name = body.data.uv_layers[0].name

    # ---- 2. bake material: world position -> image uv, front/back by world normal.y (front = -Y)
    skin = bpy.data.materials["살"]
    nt = skin.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N = nt.nodes; L = nt.links
    geo = N.new("ShaderNodeNewGeometry")
    sep_p = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Position"], sep_p.inputs[0])
    sep_n = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Normal"], sep_n.inputs[0])


    def map_range(src, a, b, c, d):
        m = N.new("ShaderNodeMapRange"); m.clamp = True
        m.inputs["From Min"].default_value = a; m.inputs["From Max"].default_value = b
        m.inputs["To Min"].default_value = c; m.inputs["To Max"].default_value = d
        L.new(src, m.inputs["Value"]); return m.outputs["Result"]


    def projected(img, box, mirror):
        u0, u1, v0, v1 = box
        u = map_range(sep_p.outputs["X"], lo.x, hi.x, u1 if mirror else u0, u0 if mirror else u1)
        v = map_range(sep_p.outputs["Z"], lo.z, hi.z, v0, v1)
        comb = N.new("ShaderNodeCombineXYZ"); L.new(u, comb.inputs["X"]); L.new(v, comb.inputs["Y"])
        tex = N.new("ShaderNodeTexImage"); tex.image = img; tex.extension = "EXTEND"; tex.interpolation = "Cubic"
        L.new(comb.outputs[0], tex.inputs["Vector"])
        return tex.outputs["Color"]


    front_c = projected(front_img, fb, mirror=False)
    back_c = projected(back_img, bb, mirror=True)
    fac = map_range(sep_n.outputs["Y"], -BLEND_NY, BLEND_NY, 0.0, 1.0)   # -Y normal = faces the front camera
    mix = N.new("ShaderNodeMix"); mix.data_type = "RGBA"
    L.new(fac, mix.inputs["Factor"]); L.new(front_c, mix.inputs[6]); L.new(back_c, mix.inputs[7])
    emit = N.new("ShaderNodeEmission"); L.new(mix.outputs[2], emit.inputs["Color"])
    out = N.new("ShaderNodeOutputMaterial"); L.new(emit.outputs[0], out.inputs["Surface"])
    target = bpy.data.images.new("bake_target", BAKE_PX, BAKE_PX, alpha=False)
    tnode = N.new("ShaderNodeTexImage"); tnode.image = target; N.active = tnode

    scene.render.engine = "CYCLES"; scene.cycles.samples = 1; scene.cycles.device = "CPU"
    scene.render.bake.margin = 24; scene.render.bake.use_clear = True
    bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
    body.data.uv_layers.active = body.data.uv_layers[uv_name]
    bpy.ops.object.bake(type="EMIT")
    print("baked EMIT", BAKE_PX)

    # ---- 3. post: darken, height -> normal
    col = px_array(target)[:, :, :3]
    lum = col[:, :, 0] * 0.2126 + col[:, :, 1] * 0.7152 + col[:, :, 2] * 0.0722
    print("bake luma mean %.3f  p10 %.3f  p90 %.3f" % (lum.mean(), np.percentile(lum, 10), np.percentile(lum, 90)))
    albedo = save_image("miner_skin_albedo", col * SKIN_DARKEN, "JPEG")
    hgt = blur(lum, HEIGHT_BLUR_PX) * 12.0        # 12: height amplitude in pixels — ribs/muscle read at 1.5 m
    normal = save_image("miner_skin_normal", normal_from_height(hgt, NORMAL_STRENGTH), "PNG", "Non-Color")
    bpy.data.images.remove(target); bpy.data.images.remove(front_img); bpy.data.images.remove(back_img)

# ---- 4. final materials


def principled(mat, base=None, base_rgb=None, normal=None, uv_scale=1.0):
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N = nt.nodes; L = nt.links
    p = N.new("ShaderNodeBsdfPrincipled"); o = N.new("ShaderNodeOutputMaterial"); L.new(p.outputs[0], o.inputs["Surface"])
    p.inputs["Roughness"].default_value = ROUGHNESS; p.inputs["Metallic"].default_value = 0.0
    p.inputs["Specular IOR Level"].default_value = 0.2
    mapping = None
    if uv_scale != 1.0:
        uvn = N.new("ShaderNodeUVMap"); mapping = N.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, 1.0); L.new(uvn.outputs[0], mapping.inputs["Vector"])
    if base is not None:
        t = N.new("ShaderNodeTexImage"); t.image = base; L.new(t.outputs["Color"], p.inputs["Base Color"])
        if mapping: L.new(mapping.outputs[0], t.inputs["Vector"])
    elif base_rgb is not None:
        p.inputs["Base Color"].default_value = (*base_rgb, 1)
    if normal is not None:
        t = N.new("ShaderNodeTexImage"); t.image = normal; nm = N.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = NORMAL_STRENGTH
        L.new(t.outputs["Color"], nm.inputs["Color"]); L.new(nm.outputs[0], p.inputs["Normal"])
        if mapping: L.new(mapping.outputs[0], t.inputs["Vector"])


def polyhaven(folder, darken, name):
    """Diffuse (darkened, sRGB jpg) + normal (png), both resized to TIMBER_PX"""
    d = bpy.data.images.load(os.path.join(PH, folder, folder + "_Diffuse.jpg")); d.scale(TIMBER_PX, TIMBER_PX)
    n = bpy.data.images.load(os.path.join(PH, folder, folder + "_nor_gl.jpg")); n.scale(TIMBER_PX, TIMBER_PX)
    dn = px_array(n); bpy.data.images.remove(n)
    base = save_image(name + "_albedo", px_array(d) * darken, "JPEG"); bpy.data.images.remove(d)
    nor = save_image(name + "_normal", dn, "PNG", "Non-Color")
    return base, nor


wood_b, wood_n = polyhaven("rough_wood", WOOD_DARKEN, "timber")
rust_b, rust_n = polyhaven("rusty_metal_02", RUST_DARKEN, "iron")
if not SKIN_KEEP:
    principled(bpy.data.materials["살"], base=albedo, normal=normal)
else:
    for m in bpy.data.materials:                      # generated skin materials: keep the base-colour image, force matte
        if m.name.startswith("살") and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    n.inputs["Roughness"].default_value = ROUGHNESS; n.inputs["Metallic"].default_value = 0.0
    print("skin kept:", [m.name for m in bpy.data.materials if m.name.startswith("살")])
principled(bpy.data.materials["뒤틀린_갱목"], base=wood_b, normal=wood_n, uv_scale=WOOD_SCALE)
principled(bpy.data.materials["녹슨_주철"], base=rust_b, normal=rust_n, uv_scale=RUST_SCALE)
principled(bpy.data.materials["가죽끈"], base_rgb=STRAP_RGB)
for nm in ("낡은_황동", "탁한_석영"):      # helmet is part of the body (projected); these stay as dark flat colours
    if nm in bpy.data.materials:
        principled(bpy.data.materials[nm], base_rgb=(0.25, 0.20, 0.09) if "황동" in nm else (0.3, 0.29, 0.28))
used = {}
for o in [body] + timber:
    for s in o.material_slots:
        used[s.material.name] = used.get(s.material.name, 0) + 1
print("materials used", used)

# ---- 5. renders (Eevee): walk_crouch mid-step 3 views + face close-up, lit by one lamp from the front like the headlamp
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
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "PERSP"; cam_data.lens = 35
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
lamp = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "SPOT")); scene.collection.objects.link(lamp)
lamp.data.energy = 400; lamp.data.spot_size = math.radians(60); lamp.data.shadow_soft_size = 0.1
views = {"front": ((0, -4.5, 1.2), (math.radians(88), 0, 0)), "left": ((4.5, 0, 1.2), (math.radians(88), 0, math.radians(90))),
         "iso": ((-3.2, -3.2, 1.6), (math.radians(80), 0, math.radians(-45))), "face": ((0.3, -1.6, 1.5), (math.radians(90), 0, math.radians(10)))}
for vname, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; lamp.location = loc; lamp.rotation_euler = rot
    scene.render.filepath = os.path.join(RENDER, f"walk_crouch_f16_{vname}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", list(views))
for o in (cam, lamp):
    bpy.data.objects.remove(o, do_unlink=True)
for tr in arm.animation_data.nla_tracks:
    tr.mute = False
ad.action = None

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)

# ---- 6. export for Godot (same as stage 5)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_apply=True, export_yup=True, export_skins=True, export_image_format="AUTO")
print("exported", OUT_GLB, round(os.path.getsize(OUT_GLB) / 1e6, 2), "MB")
