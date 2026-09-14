"""Stage 11 (proposal #45): the TRELLIS.2 body replaces the local-Hunyuan body wholesale (licence: MIT; Hunyuan 2.x excludes Korea).
usage: blender -b --factory-startup -P blender/stage11_body.py [-- <body.glb> <head.glb>]
Inputs : mesh/trellis2_v1.glb (full body, 1024^3, 2K PBR), mesh/trellis2_head_512.glb (head+shoulders, 512^3)
Outputs: blender/miner_v3_stage11.blend  — Miner_Body (decimated, TRELLIS textures kept: body + head materials), Miner_Body_HI
         (full-res copy, HI_source collection), timber/straps/nails parented to Timber_Rig (stage-4 recipe, re-measured),
         blender/miner_body_for_mixamo.fbx (body only), blender/stage11_render/*.png
Method : normalise (height H, feet z 0, arms along x, front -y — checked: toes are in front of the hips), force roughness 1 /
         metallic 0 on the generated materials (the game is matte, the TRELLIS metallic map made it glossy), decimate to
         BODY_FACES keeping UVs, replace the head by the separately generated one (stage-8 recipe: narrowest neck slices,
         scale to neck width, bisect, cap, NECK_OVERLAP, strap over the seam), attach timber from measured landmarks."""
import bpy, os, sys, math
from mathutils import Vector

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
BODY_GLB = args[0] if args else os.path.join(ROOT, "mesh", "trellis2_v1.glb")
HEAD_GLB = args[1] if len(args) > 1 else os.path.join(ROOT, "mesh", "trellis2_head_512.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v3_stage11.blend")
FBX = os.path.join(ROOT, "blender", "miner_body_for_mixamo.fbx")
RENDER = os.path.join(ROOT, "blender", "stage11_render")
os.makedirs(RENDER, exist_ok=True)

H = 2.5
BODY_FACES = int(os.environ.get("BODY_FACES", "100000"))   # game body target (source 283k); the HI copy keeps everything
HEAD_FACES = int(os.environ.get("HEAD_FACES", "30000"))
NECK_LO, NECK_HI = 0.80, 0.95      # body: narrowest slice band (fraction of H)
HEAD_LO, HEAD_HI = 0.30, 0.65      # head mesh (with shoulders below): narrowest slice band of its own height
NECK_OVERLAP = 0.02
HEAD_SCALE_MUL = float(os.environ.get("HEAD_SCALE_MUL", "1.0"))
SLICE = 0.01
USE_HEAD = os.environ.get("USE_HEAD", "1") == "1"

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ------------------------------------------------------------------ helpers
def import_glb(path, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    obj = max(meshes, key=lambda o: len(o.data.polygons))
    for o in new:
        if o is not obj:
            if obj.parent == o:
                m = obj.matrix_world.copy(); obj.parent = None; obj.matrix_world = m
            bpy.data.objects.remove(o, do_unlink=True)
    select_only(obj); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = name
    return obj


def select_only(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o


def verts_world(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def bbox(pts):
    return Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)])


def matte(o):
    """the generated GLB materials: keep base colour, drop metallic/roughness maps, force matte"""
    for slot in o.material_slots:
        m = slot.material
        if not m or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for sock in ("Metallic", "Roughness", "Specular IOR Level"):
                    if sock in n.inputs:
                        for l in list(n.inputs[sock].links):
                            m.node_tree.links.remove(l)
                n.inputs["Roughness"].default_value = 1.0; n.inputs["Metallic"].default_value = 0.0


def slice_stats(pts, z, t=SLICE):
    s = [p for p in pts if z - t / 2 <= p.z < z + t / 2]
    if len(s) < 8:
        return None
    xs = [p.x for p in s]; ys = [p.y for p in s]
    return dict(z=z, w=max(xs) - min(xs), d=max(ys) - min(ys), cx=(max(xs) + min(xs)) / 2, cy=(max(ys) + min(ys)) / 2)


def narrowest(pts, zlo, zhi):
    best = None; z = zlo
    while z <= zhi:
        st = slice_stats(pts, z)
        if st and (best is None or st["w"] < best["w"]):
            best = st
        z += SLICE
    assert best, "no slices"
    return best


def bisect_keep(o, z, keep_above):
    select_only(o)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=keep_above, clear_outer=not keep_above, use_fill=True)
    bpy.ops.mesh.select_all(action="DESELECT"); bpy.ops.object.mode_set(mode="OBJECT")
    o.data.update()
    return len(o.data.polygons)


def decimate_to(o, faces):
    if len(o.data.polygons) <= faces:
        return
    select_only(o)
    d = o.modifiers.new("dec", "DECIMATE"); d.ratio = faces / len(o.data.polygons)
    bpy.ops.object.modifier_apply(modifier="dec")


def join_into(target, part):
    bpy.ops.object.select_all(action="DESELECT"); part.select_set(True); target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


# ------------------------------------------------------------------ 1. body in, normalised
body = import_glb(BODY_GLB, "Miner_Body")
pts = verts_world(body)
lo, hi = bbox(pts)
s = H / (hi.z - lo.z)
for v in body.data.vertices:
    p = body.matrix_world @ v.co
    v.co = Vector(((p.x - (lo.x + hi.x) / 2) * s, (p.y - (lo.y + hi.y) / 2) * s, (p.z - lo.z) * s))
body.matrix_world.identity(); body.data.update()
pts = verts_world(body)
feet = [p for p in pts if p.z < 0.08]; hips = [p for p in pts if 1.0 < p.z < 1.3 and abs(p.x) < 0.3]
fy = sum(p.y for p in feet) / len(feet); hy = sum(p.y for p in hips) / len(hips)
assert fy < hy, "front is not -y (toes y %.3f, hips y %.3f) — check the GLB orientation" % (fy, hy)
lo, hi = bbox(pts)
print("BODY normalised: faces %d  span x %.2f  depth y %.2f  height %.2f  toes y %.3f < hips y %.3f (front = -y)" % (
    len(body.data.polygons), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, fy, hy))
matte(body)
for slot in body.material_slots:
    if slot.material:
        slot.material.name = "살"
        print("BODY material", slot.material.name, "images", [n.image.name + " %dx%d" % tuple(n.image.size) for n in slot.material.node_tree.nodes if n.type == "TEX_IMAGE" and n.image])

# HI copy (full resolution) before decimation
hi_col = bpy.data.collections.new("HI_source"); scene.collection.children.link(hi_col)
hi_obj = body.copy(); hi_obj.data = body.data.copy(); hi_obj.name = "Miner_Body_HI"; hi_col.objects.link(hi_obj)
decimate_to(body, BODY_FACES)
print("BODY decimated: %d faces (target %d), uv layers %s" % (len(body.data.polygons), BODY_FACES, [u.name for u in body.data.uv_layers]))

# ------------------------------------------------------------------ 2. head swap (stage-8 recipe)
if USE_HEAD:
    bpts = verts_world(body)
    neck = narrowest(bpts, NECK_LO * H, NECK_HI * H)
    print("BODY neck z %.3f width %.3f depth %.3f centre (%.3f, %.3f)" % (neck["z"], neck["w"], neck["d"], neck["cx"], neck["cy"]))
    head = import_glb(HEAD_GLB, "Head_src")
    matte(head)
    for slot in head.material_slots:
        if slot.material:
            slot.material.name = "살_머리"
    hpts = verts_world(head)
    hz0, hz1 = min(p.z for p in hpts), max(p.z for p in hpts)
    hneck = narrowest(hpts, hz0 + HEAD_LO * (hz1 - hz0), hz0 + HEAD_HI * (hz1 - hz0))
    sc = neck["w"] / hneck["w"] * HEAD_SCALE_MUL
    for v in head.data.vertices:
        p = head.matrix_world @ v.co
        v.co = Vector(((p.x - hneck["cx"]) * sc + neck["cx"], (p.y - hneck["cy"]) * sc + neck["cy"], (p.z - hneck["z"]) * sc + neck["z"]))
    head.matrix_world.identity(); head.data.update()
    hpts = verts_world(head)
    print("HEAD src faces %d  neck width %.3f -> scale %.4f  top z %.3f (body top %.3f)  neck depth %.3f vs body %.3f" % (
        len(head.data.polygons), hneck["w"], sc, max(p.z for p in hpts), max(p.z for p in bpts), hneck["d"] * sc, neck["d"]))
    head_hi = head.copy(); head_hi.data = head.data.copy(); head_hi.name = "Head_hi"; hi_col.objects.link(head_hi)
    zc = neck["z"]
    print("BODY cut above z %.3f: %d -> %d" % (zc, len(body.data.polygons), bisect_keep(body, zc, keep_above=False)))
    print("HI   cut above z %.3f: %d -> %d" % (zc, len(hi_obj.data.polygons), bisect_keep(hi_obj, zc, keep_above=False)))
    print("HEAD cut below z %.3f: %d -> %d" % (zc - NECK_OVERLAP, len(head.data.polygons), bisect_keep(head, zc - NECK_OVERLAP, keep_above=True)))
    bisect_keep(head_hi, zc - NECK_OVERLAP, keep_above=True)
    decimate_to(head, HEAD_FACES)
    head_faces = len(head.data.polygons)
    join_into(body, head); join_into(hi_obj, head_hi)
    body.name = "Miner_Body"; hi_obj.name = "Miner_Body_HI"
    print("JOINED body faces %d (head %d), materials %s" % (len(body.data.polygons), head_faces, [s.material.name for s in body.material_slots if s.material]))
select_only(body); bpy.ops.object.shade_smooth()

# ------------------------------------------------------------------ 3. timber (stage-4 recipe, re-measured on this body)
rig = bpy.data.objects.new("Timber_Rig", None); scene.collection.objects.link(rig)


def mat(name, rgb):
    m = bpy.data.materials.new(name); m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1); p.inputs["Roughness"].default_value = 1.0; p.inputs["Metallic"].default_value = 0.0
    return m


M = {k: mat(k, c) for k, c in {"뒤틀린_갱목": (0.36, 0.28, 0.19), "녹슨_주철": (0.22, 0.11, 0.07), "가죽끈": (0.14, 0.09, 0.07),
                                "낡은_황동": (0.50, 0.40, 0.18), "탁한_석영": (0.75, 0.73, 0.70)}.items()}


def band(zlo, zhi, xmax=None, xmin=None, q=0.06):
    pts = [v.co for v in body.data.vertices if zlo <= v.co.z <= zhi and (xmax is None or v.co.x <= xmax) and (xmin is None or v.co.x >= xmin)]
    xs, zs = [p.x for p in pts], [p.z for p in pts]
    ys = sorted(p.y for p in pts); k = int(len(ys) * q)
    return dict(xmin=min(xs), xmax=max(xs), ymin=ys[k], ymax=ys[-1 - k], zc=sum(zs) / len(zs), n=len(pts))


def box(name, dims, loc, rot=(0, 0, 0), m="뒤틀린_갱목", parent=True):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object; o.name = name; o.scale = Vector(dims); o.data.materials.append(M[m])
    if parent:
        o.parent = rig
    return o


def strap(name, loc, rx, ry, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.012, location=loc, rotation=rot, major_segments=32, minor_segments=8)
    o = bpy.context.active_object; o.name = name; o.scale = Vector((rx, ry, 1)); o.data.materials.append(M["가죽끈"]); o.parent = rig
    sw = o.modifiers.new("hug", "SHRINKWRAP"); sw.target = body; sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.008
    return o


def nail(name, base, tilt_x_deg, length=0.14):
    t = math.radians(tilt_x_deg); axis = Vector((0, -math.sin(t), math.cos(t)))
    bpy.ops.mesh.primitive_cube_add(size=1, location=Vector(base) + axis * (length / 2), rotation=(t, 0, 0))
    o = bpy.context.active_object; o.name = name; o.scale = Vector((0.03, 0.03, length)); o.data.materials.append(M["녹슨_주철"]); o.parent = rig
    return o


chest = band(0.60 * H, 0.72 * H, xmax=0.35, xmin=-0.35)
arm_L = band(0.55 * H, 0.85 * H, xmin=0.55)
shin_R = band(0.15 * H, 0.30 * H, xmax=-0.02)
back_up = band(0.72 * H, 0.80 * H, xmax=0.35, xmin=-0.35)
hand_x = max(v.co.x for v in body.data.vertices)
print("LANDMARKS chest", chest); print("LANDMARKS arm_L", arm_L); print("LANDMARKS shin_R", shin_R, "hand_x", round(hand_x, 3))
cz = 0.66 * H; cy = chest["ymin"] - 0.015
box("Plank_Chest_A", (0.95, 0.03, 0.15), (0, cy, cz), rot=(0, math.radians(38), 0))
box("Plank_Chest_B", (0.95, 0.03, 0.15), (0, cy, cz), rot=(0, math.radians(-38), 0))
for i, z in enumerate((0.58 * H, 0.66 * H, 0.74 * H)):
    b = band(z - 0.02, z + 0.02, xmax=0.35, xmin=-0.35)
    strap(f"Strap_Torso_{i}", (0, (b["ymin"] + b["ymax"]) / 2, z), (b["xmax"] - b["xmin"]) / 2 + 0.03, (b["ymax"] - b["ymin"]) / 2 + 0.035)
fx = 0.62 * hand_x
fa = band(arm_L["zc"] - 0.08, arm_L["zc"] + 0.08, xmin=fx - 0.12, xmax=fx + 0.12)
box("Plank_Forearm_L", (0.36, 0.025, 0.06), (fx, fa["ymin"] - 0.012, fa["zc"]))
ar = max((fa["ymax"] - fa["ymin"]) / 2, 0.03) + 0.015
for i, x in enumerate((fx - 0.11, fx + 0.11)):
    strap(f"Strap_Forearm_{i}", (x, (fa["ymin"] + fa["ymax"]) / 2, fa["zc"]), ar, ar, rot=(0, math.radians(90), 0))
sx = (shin_R["xmin"] + shin_R["xmax"]) / 2; sz = 0.22 * H
box("Plank_Shin_R", (0.07, 0.025, 0.42), (sx, shin_R["ymin"] - 0.012, sz))
lr = max((shin_R["xmax"] - shin_R["xmin"]) / 2, (shin_R["ymax"] - shin_R["ymin"]) / 2) + 0.012
for i, z in enumerate((sz - 0.15, sz + 0.15)):
    strap(f"Strap_Shin_{i}", (sx, (shin_R["ymin"] + shin_R["ymax"]) / 2, z), lr, lr)
L = 1.15; ang = math.radians(-35); top = Vector((-0.33, 0, 0.90 * H)); axis = Vector((math.sin(ang), 0, math.cos(ang))); c = top - axis * (L / 2)
box("Plank_Back", (0.15, 0.03, L), (c.x, back_up["ymax"] + 0.018, c.z), rot=(0, ang, 0))
by = back_up["ymax"]
for i, (x, z) in enumerate(((-0.28, 0.79 * H), (-0.12, 0.81 * H), (0.05, 0.78 * H), (0.20, 0.80 * H), (0.30, 0.76 * H))):
    nail(f"Nail_{i}", (x, by - 0.02, z), tilt_x_deg=-65, length=0.22)
if USE_HEAD:
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.012, location=(neck["cx"], neck["cy"], neck["z"]), major_segments=32, minor_segments=8)
    st = bpy.context.active_object; st.name = "Strap_Neck"; st.scale = Vector((neck["w"] / 2 + 0.03, neck["d"] / 2 + 0.035, 1))
    st.data.materials.append(M["가죽끈"]); st.parent = rig
    sw = st.modifiers.new("hug", "SHRINKWRAP"); sw.target = body; sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.008

# ------------------------------------------------------------------ 4. save, FBX, renders
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND, "body faces", len(body.data.polygons))
select_only(body)
bpy.ops.export_scene.fbx(filepath=FBX, use_selection=True, apply_scale_options="FBX_SCALE_ALL", path_mode="COPY")
print("exported", FBX, round(os.path.getsize(FBX) / 1e6, 2), "MB")

hi_col.hide_render = True; hi_col.hide_viewport = True
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.2, 0.2, 0.2, 1)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3; scene.collection.objects.link(sun)
cam.data.lens = 50
views = {"front": ((0, -6, 1.3), (math.radians(88), 0, 0)), "back": ((0, 6, 1.3), (math.radians(88), 0, math.pi)),
         "left": ((6, 0, 1.3), (math.radians(88), 0, math.pi / 2)), "iso": ((-4.2, -4.2, 2.2), (math.radians(78), 0, math.radians(-45))),
         "face": ((0.25, -1.4, 2.25), (math.radians(90), 0, math.radians(10))), "hand": ((-1.3, -1.2, 1.85), (math.radians(90), 0, 0))}
for vname, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; sun.rotation_euler = rot
    scene.render.filepath = os.path.join(RENDER, f"stage11_{vname}.png"); bpy.ops.render.render(write_still=True)
print("rendered", list(views))
