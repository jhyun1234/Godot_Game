"""Stage 8 (proposal #41): replace the body's blob head with a separately generated head (Hunyuan, head-only image).
usage: blender -b --factory-startup -P blender/stage8_head.py [-- <head.glb>]
Inputs : blender/miner_v2_stage4.blend (Miner_Body 33k, Miner_Body_HI 201k, timber), mesh/head_s50_o512.glb
Outputs: blender/miner_v2_stage8.blend (same object names as stage 4 -> stage5_merge.py / stage7_bake.py read it),
         blender/miner_body_for_mixamo.fbx (body+head joined, for the Mixamo re-rig), blender/stage8_render/*.png
Method : both meshes are measured, not eyeballed — the neck is the narrowest horizontal slice; the head is scaled so its
         neck width equals the body's, translated so the two neck slices coincide; the body is cut above the neck, the
         head below it (overlap NECK_OVERLAP into the body), holes capped, joined. A leather strap hides the seam."""
import bpy, bmesh, os, sys, math
from mathutils import Vector

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE4 = os.path.join(ROOT, "blender", "miner_v2_stage4.blend")
HEAD_GLB = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "mesh", "head_s50_o512.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage8.blend")
FBX = os.path.join(ROOT, "blender", "miner_body_for_mixamo.fbx")
RENDER = os.path.join(ROOT, "blender", "stage8_render")
os.makedirs(RENDER, exist_ok=True)

H = 2.5                       # standing height (stage 4)
NECK_LO, NECK_HI = 0.80, 0.95 # body: search the narrowest slice in this height band (fraction of H)
HEAD_LO, HEAD_HI = 0.25, 0.70 # head mesh: search band (fraction of its own height; shoulders below, helmet above)
SLICE = 0.01                  # m, slice thickness for width measurement
NECK_OVERLAP = 0.02           # m, head shell reaches this far down into the body's neck
HEAD_FACES = 15000            # decimate target for the game head (body is 33k)
HEAD_HI_FACES = 250000        # HI copy keeps this much of the 1.9M-face source (normal bake source; body HI is 201k)
HEAD_SCALE_MUL = float(os.environ.get("HEAD_SCALE_MUL", "1.0"))   # >1 = bigger head (F5 knob)

bpy.ops.wm.open_mainfile(filepath=STAGE4)
scene = bpy.context.scene
body = bpy.data.objects["Miner_Body"]; hi = bpy.data.objects["Miner_Body_HI"]


def expose(o):
    """HI lives in the excluded 'HI_source' collection: operators silently skip objects that are not in the view layer"""
    def walk(lc):
        for c in lc.children:
            if o.name in c.collection.objects:
                c.exclude = False; c.hide_viewport = False
            walk(c)
    walk(bpy.context.view_layer.layer_collection)
    for c in o.users_collection:            # stage 4 hid the collection itself (data-level flag) — bisect is CANCELLED on invisible objects
        c.hide_viewport = False; c.hide_render = False
    o.hide_viewport = False; o.hide_set(False); o.hide_select = False
    assert o.visible_get(), o.name + " still invisible"
    assert o.name in bpy.context.view_layer.objects, o.name + " still not in the view layer"


expose(hi)
rig = bpy.data.objects.get("Timber_Rig")
M = {m.name: m for m in bpy.data.materials}


def verts_world(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def slice_stats(pts, z, t=SLICE):
    s = [p for p in pts if z - t / 2 <= p.z < z + t / 2]
    if len(s) < 8:
        return None
    xs = [p.x for p in s]; ys = [p.y for p in s]
    return dict(z=z, w=max(xs) - min(xs), d=max(ys) - min(ys), cx=(max(xs) + min(xs)) / 2, cy=(max(ys) + min(ys)) / 2, n=len(s))


def narrowest(pts, zlo, zhi):
    best = None
    z = zlo
    while z <= zhi:
        st = slice_stats(pts, z)
        if st and (best is None or st["w"] < best["w"]):
            best = st
        z += SLICE
    assert best, "no slices"
    return best


# ---- 1. body neck
bpts = verts_world(body)
neck = narrowest(bpts, NECK_LO * H, NECK_HI * H)
print("BODY neck z %.3f  width %.3f  depth %.3f  centre (%.3f, %.3f)  top z %.3f" % (neck["z"], neck["w"], neck["d"], neck["cx"], neck["cy"], max(p.z for p in bpts)))

# ---- 2. head mesh in, measured, aligned
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=HEAD_GLB)
new = [o for o in bpy.data.objects if o not in before]
hmeshes = [o for o in new if o.type == "MESH"]
for o in hmeshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = hmeshes[0]
if len(hmeshes) > 1:
    bpy.ops.object.join()
head = bpy.context.view_layer.objects.active; head.name = "Head_src"
for o in new:
    if o.type != "MESH" and o.name in bpy.data.objects:
        if head.parent == o:
            m = head.matrix_world.copy(); head.parent = None; head.matrix_world = m
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT"); head.select_set(True); bpy.context.view_layer.objects.active = head
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
hpts = verts_world(head)
hz0, hz1 = min(p.z for p in hpts), max(p.z for p in hpts)
hneck = narrowest(hpts, hz0 + HEAD_LO * (hz1 - hz0), hz0 + HEAD_LO * 0 + HEAD_HI * (hz1 - hz0))
print("HEAD src faces %d  height %.3f  neck z %.3f width %.3f depth %.3f centre (%.3f, %.3f)" % (len(head.data.polygons), hz1 - hz0, hneck["z"], hneck["w"], hneck["d"], hneck["cx"], hneck["cy"]))
s = neck["w"] / hneck["w"] * HEAD_SCALE_MUL
for v in head.data.vertices:
    p = head.matrix_world @ v.co
    v.co = Vector(((p.x - hneck["cx"]) * s + neck["cx"], (p.y - hneck["cy"]) * s + neck["cy"], (p.z - hneck["z"]) * s + neck["z"]))
head.matrix_world.identity(); head.data.update()
hpts = verts_world(head)
print("HEAD aligned: scale %.4f  top z %.3f (body top %.3f, ratio %.3f)  neck depth %.3f vs body %.3f" % (
    s, max(p.z for p in hpts), max(p.z for p in bpts), max(p.z for p in hpts) / max(p.z for p in bpts), hneck["d"] * s, neck["d"]))


# ---- 3. cut + cap + join
def bisect_keep(o, z, keep_above):
    """cut o by the plane z, keep one side, cap the hole"""
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=keep_above, clear_outer=not keep_above, use_fill=True)
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    o.data.update()
    return len(o.data.polygons)


def decimate_to(o, faces):
    if len(o.data.polygons) <= faces:
        return
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    d = o.modifiers.new("dec", "DECIMATE"); d.ratio = faces / len(o.data.polygons)
    bpy.ops.object.modifier_apply(modifier="dec")


def join_into(target, part):
    bpy.ops.object.select_all(action="DESELECT"); part.select_set(True); target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


# HI copy gets the full-resolution head; the game body gets the decimated one
head_hi = head.copy(); head_hi.data = head.data.copy(); head_hi.name = "Head_hi"; scene.collection.objects.link(head_hi)
zc = neck["z"]
print("BODY cut above z %.3f: faces %d -> %d" % (zc, len(body.data.polygons), bisect_keep(body, zc, keep_above=False)))
print("HI   cut above z %.3f: faces %d -> %d" % (zc, len(hi.data.polygons), bisect_keep(hi, zc, keep_above=False)))
print("HEAD cut below z %.3f: faces %d -> %d" % (zc - NECK_OVERLAP, len(head.data.polygons), bisect_keep(head, zc - NECK_OVERLAP, keep_above=True)))
bisect_keep(head_hi, zc - NECK_OVERLAP, keep_above=True)
decimate_to(head_hi, HEAD_HI_FACES)
decimate_to(head, HEAD_FACES)
print("HEAD decimated to %d faces (target %d)" % (len(head.data.polygons), HEAD_FACES))
for o in (head, head_hi):
    o.data.materials.clear(); o.data.materials.append(M["살"])
head_faces = len(head.data.polygons)
join_into(body, head); join_into(hi, head_hi)
body.name = "Miner_Body"; hi.name = "Miner_Body_HI"
# the head came without UVs: re-unwrap the whole game body (textures are re-baked from paint/HI anyway, stage 7)
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
bpy.ops.object.mode_set(mode="OBJECT")
print("UV re-unwrapped:", [u.name for u in body.data.uv_layers])
print("JOINED body faces %d (head %d = %.0f%%)  HI faces %d" % (len(body.data.polygons), head_faces, 100.0 * head_faces / len(body.data.polygons), len(hi.data.polygons)))

# ---- 4. neck strap over the seam (stage-4 strap(): torus + shrinkwrap)
bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.012, location=(neck["cx"], neck["cy"], zc), major_segments=32, minor_segments=8)
strap = bpy.context.active_object; strap.name = "Strap_Neck"
strap.scale = Vector((neck["w"] / 2 + 0.03, neck["d"] / 2 + 0.035, 1))
strap.data.materials.append(M["가죽끈"])
if rig:
    strap.parent = rig
sw = strap.modifiers.new("hug", "SHRINKWRAP"); sw.target = body; sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.008

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)

# ---- 5. FBX for Mixamo (body only, same as stage 4)
bpy.ops.object.select_all(action="DESELECT"); body.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.fbx(filepath=FBX, use_selection=True, apply_scale_options="FBX_SCALE_ALL", path_mode="COPY")
print("exported", FBX, round(os.path.getsize(FBX) / 1e6, 2), "MB")

# ---- 6. renders: front / left / iso / face, flat grey, one sun
for o in bpy.data.objects:
    if o.name.startswith("Gauge"):
        o.hide_render = True
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
views = {"front": ((0, -6, 1.3), (math.radians(88), 0, 0)), "left": ((6, 0, 1.3), (math.radians(88), 0, math.radians(90))),
         "iso": ((-4.2, -4.2, 2.2), (math.radians(78), 0, math.radians(-45))), "face": ((0.25, -1.4, 2.25), (math.radians(90), 0, math.radians(10)))}
for vname, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; sun.rotation_euler = rot
    scene.render.filepath = os.path.join(RENDER, f"stage8_{vname}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", list(views))
