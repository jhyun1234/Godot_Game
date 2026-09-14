"""Stage 10 (proposal #43): give the smooth torso the ribcage/organ relief of a separately generated torso — by SHRINKWRAP,
not by attaching. Vertex count, order, UVs and rig weights stay; no seam, no re-rig.
usage: blender -b --factory-startup -P blender/stage10_torso.py [-- <torso.glb>]
Inputs : blender/miner_v2_stage9.blend (Miner_Body 52.9k = body + head + hands, Miner_Body_HI 695k),
         blender/miner_v2_stage5.blend (the same body, rigged), mesh/torso_s50_o512.glb
         (torso.png was a two-torso sheet from Gemini; the SKELETON+ORGANS torso — image left — was cropped to torso_clean.png
          because only the bone side (the figure's right, -X) gets relief; the skin side keeps the smooth hide.)
Outputs: blender/miner_v2_stage10.blend (stage-9 file with both bodies morphed -> stage7_bake.py HI_BLEND / export),
         blender/miner_v2_stage5.blend overwritten (backup miner_v2_stage5_pretorso.blend), blender/stage10_render/*.png,
         RELIEF lines in the log (right-chest Laplacian RMS before/after, left chest for comparison).
Method : landmarks measured on the body (hips = widest arm-free slice above the crotch, crotch = lowest mid vertex, chest slice
         centre) and on the torso mesh (pelvis = widest slice in its lower third, bottom) -> uniform scale + translate.
         (Shoulders cannot be used: in the T-pose every chest slice runs into the arms.) Vertex group
         "Torso" = bone side (x < BONE_X) within the torso band, 5 cm fades. Shrinkwrap PROJECT along the body's Y axis (front/back) both
         ways, limit PROJECT_LIMIT: vertices that find the torso surface within the limit move onto it, the rest stay. Normal-
         direction projection was tried first: rays wander into rib gaps and the low mesh turns into spikes. The low body is
         then smoothed a little (SMOOTH_ITERS) — 1.2 cm vertices alias 2 cm ribs; the HI copy keeps the steps for the bake."""
import bpy, os, sys, math, collections, shutil
from mathutils import Vector, Matrix

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE9 = os.path.join(ROOT, "blender", "miner_v2_stage9.blend")
STAGE5 = os.path.join(ROOT, "blender", "miner_v2_stage5.blend")
BACKUP = os.path.join(ROOT, "blender", "miner_v2_stage5_pretorso.blend")
TORSO_GLB = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "mesh", "torso_s50_o512.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage10.blend")
RENDER = os.path.join(ROOT, "blender", "stage10_render")
os.makedirs(RENDER, exist_ok=True)

NECK_Z = 2.04                 # stage-8 neck cut (head starts here)
BAND_LO, BAND_HI = 0.86, 2.01 # torso band that may move (above the crotch 0.81, below the neck cut)
BONE_X = 0.03                 # only x < this (the figure's right) gets relief; skin side untouched
TORSO_XMAX = 0.30             # beyond this |x| it is arm/shoulder, never moved
FADE = 0.05                   # m, weight ramps to 0 over this at every edge of the group
PROJECT_LIMIT = float(os.environ.get("PROJECT_LIMIT", "0.08"))   # m, max move (6 cm left organ-deep vertices behind; 8 cm moves them consistently)
SMOOTH_ITERS = int(os.environ.get("SMOOTH_ITERS", "1"))            # low body only: the 1.2 cm mesh aliases 2 cm ribs into spikes; the HI copy keeps the steps for the normal bake
CELL = 0.03                   # relief metric grid (2 cm cells only see the 1.2 cm mesh noise)
RELIEF_MIN = 0.006            # m, right-chest Laplacian RMS after (measured: before 4.7 mm, after 7.0; HI 4.4 -> 7.4). The 11 mm of the proposal came from a patch that included the clavicle/neck edge
RELIEF_RATIO = 1.35           # right / left (before 1.25, after 1.48)


def verts_world(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def widest_slice(pts, zlo, zhi, t=0.01, xmax=None):
    """widest x-slice in the band; xmax excludes the T-pose arms when measuring the body (torso/deltoids only)"""
    best = None; z = zlo
    while z <= zhi:
        s = [p for p in pts if abs(p.z - z) < t / 2 and (xmax is None or abs(p.x) < xmax)]
        if len(s) >= 8:
            w = max(p.x for p in s) - min(p.x for p in s)
            if best is None or w > best[1]:
                best = (z, w, (max(p.x for p in s) + min(p.x for p in s)) / 2)
        z += t
    return best


def slice_yz(pts, z, t=0.01):
    s = [p for p in pts if abs(p.z - z) < t / 2 and abs(p.x) < 0.3]
    return dict(z=z, d=max(p.y for p in s) - min(p.y for p in s), cy=(max(p.y for p in s) + min(p.y for p in s)) / 2, n=len(s))


def relief(pts, x0, x1, z0, z1):
    """front-surface height map on a CELL grid (min y per cell, front half only) -> RMS of the Laplacian residual"""
    cells = {}
    for p in pts:
        if x0 <= p.x <= x1 and z0 <= p.z <= z1 and p.y < 0.05:
            k = (round(p.x / CELL), round(p.z / CELL))
            cells[k] = min(cells.get(k, 1e9), p.y)
    res = []
    for (i, j), y in cells.items():
        nb = [cells[(i + di, j + dj)] for di in (-1, 0, 1) for dj in (-1, 0, 1) if (di or dj) and (i + di, j + dj) in cells]
        if len(nb) >= 6:
            res.append(y - sum(nb) / len(nb))
    return math.sqrt(sum(r * r for r in res) / len(res)) if res else 0.0


def report_relief(pts, label):
    r = relief(pts, -0.20, -0.05, 1.50, 1.80); l = relief(pts, 0.05, 0.20, 1.50, 1.80)   # flat front of the chest: no clavicle, no side wrap
    print("RELIEF %s: right chest %.1f mm  left chest %.1f mm  ratio %.2f" % (label, r * 1000, l * 1000, r / l if l else 0))
    return r, l


def select_only(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o


def expose(o):
    def walk(lc):
        for c in lc.children:
            if o.name in c.collection.objects:
                c.exclude = False; c.hide_viewport = False
            walk(c)
    walk(bpy.context.view_layer.layer_collection)
    for c in o.users_collection:
        c.hide_viewport = False; c.hide_render = False
    o.hide_viewport = False; o.hide_set(False); o.hide_select = False
    assert o.visible_get() and o.name in bpy.context.view_layer.objects, o.name


# ============================================================ A. stage 9 file: morph low + HI
bpy.ops.wm.open_mainfile(filepath=STAGE9)
scene = bpy.context.scene
body = bpy.data.objects["Miner_Body"]; hi = bpy.data.objects["Miner_Body_HI"]; expose(hi)
bpts = verts_world(body)
crotch = min(p.z for p in bpts if abs(p.x) < 0.03 and 0.6 < p.z < 1.6)
sh_z, sh_w, sh_cx = widest_slice(bpts, crotch + 0.25, crotch + 0.55, xmax=0.45)   # HIPS: the T-pose arms merge with every chest slice, the pelvis is arm-free
chest = slice_yz(bpts, 1.70)
print("BODY landmarks: hips z %.3f width %.3f cx %.3f  crotch z %.3f  chest(1.70) depth %.3f cy %.3f" % (sh_z, sh_w, sh_cx, crotch, chest["d"], chest["cy"]))
before_lo = report_relief(bpts, "BEFORE low")

# torso in
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=TORSO_GLB)
new = [o for o in bpy.data.objects if o not in before]
tm = [o for o in new if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in tm:
    o.select_set(True)
bpy.context.view_layer.objects.active = tm[0]
if len(tm) > 1:
    bpy.ops.object.join()
torso = bpy.context.view_layer.objects.active; torso.name = "Torso_src"
for o in new:
    if o.type != "MESH" and o.name in bpy.data.objects:
        if torso.parent == o:
            m = torso.matrix_world.copy(); torso.parent = None; torso.matrix_world = m
        bpy.data.objects.remove(o, do_unlink=True)
select_only(torso); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
tpts = verts_world(torso)
tz0, tz1 = min(p.z for p in tpts), max(p.z for p in tpts)
t_sh = widest_slice(tpts, tz0 + 0.05 * (tz1 - tz0), tz0 + 0.35 * (tz1 - tz0), t=(tz1 - tz0) / 100)   # pelvis (iliac crests) in the lower third
s = sh_w / t_sh[1]
print("TORSO src faces %d height %.3f  pelvis z %.3f width %.3f -> scale %.4f (torso height after %.3f, body crotch->neck %.3f)" % (
    len(torso.data.polygons), tz1 - tz0, t_sh[0], t_sh[1], s, s * (tz1 - tz0), NECK_Z - crotch))
# uniform scale: pelvis width -> hip width, pelvis bottom -> crotch, pelvis centre x -> hip centre x; then y so the chest slice centres coincide
for v in torso.data.vertices:
    p = torso.matrix_world @ v.co
    v.co = Vector(((p.x - t_sh[2]) * s + sh_cx, p.y * s, (p.z - tz0) * s + crotch))
torso.matrix_world.identity(); torso.data.update()
tpts = verts_world(torso)
tchest = slice_yz(tpts, 1.70)
dy = chest["cy"] - tchest["cy"]
for v in torso.data.vertices:
    v.co.y += dy
torso.data.update(); tpts = verts_world(torso)
print("TORSO aligned: z %.3f..%.3f (body crotch %.3f)  chest(1.70) depth %.3f vs body %.3f  x %.3f..%.3f" % (
    min(p.z for p in tpts), max(p.z for p in tpts), crotch, slice_yz(tpts, 1.70)["d"], chest["d"], min(p.x for p in tpts), max(p.x for p in tpts)))


def ramp(v, lo, hi):
    """1 inside [lo+FADE, hi-FADE], 0 outside [lo, hi], linear in between"""
    return max(0.0, min(1.0, (v - lo) / FADE, (hi - v) / FADE))


def morph(o, label, smooth=0):
    vg = o.vertex_groups.new(name="Torso")
    n = 0
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        w = ramp(p.z, BAND_LO, BAND_HI) * ramp(p.x, -TORSO_XMAX, BONE_X + FADE) * (1.0 if p.y < 0.06 else 0.0)   # front half only
        if w > 0:
            vg.add([v.index], w, "REPLACE"); n += 1
    select_only(o)
    sw = o.modifiers.new("relief", "SHRINKWRAP")
    sw.target = torso; sw.wrap_method = "PROJECT"; sw.use_negative_direction = True; sw.use_positive_direction = True
    sw.use_project_y = True                      # project along the body's Y (front/back), not along wandering vertex normals
    sw.project_limit = PROJECT_LIMIT; sw.vertex_group = "Torso"
    bpy.ops.object.modifier_apply(modifier="relief")
    if smooth:
        sm = o.modifiers.new("soft", "SMOOTH"); sm.factor = 0.5; sm.iterations = smooth; sm.vertex_group = "Torso"
        bpy.ops.object.modifier_apply(modifier="soft")
    print("MORPH %s: %d weighted verts of %d, smooth %d" % (label, n, len(o.data.vertices), smooth))


morph(body, "low", SMOOTH_ITERS); morph(hi, "HI")
after_lo = report_relief(verts_world(body), "AFTER low")
report_relief(verts_world(hi), "AFTER HI")
torso.hide_render = True; torso.hide_viewport = True
# HI chest close-up, lit from the side (the ribs live here; the game mesh only carries the coarse cavity + the baked normal)
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); cam.data.lens = 50; scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
for o in bpy.data.objects:
    if o.type == "MESH" and o not in (hi,):
        o.hide_render = True
cam.location = (-0.7, -1.6, 1.6); cam.rotation_euler = (math.radians(86), 0, math.radians(-22)); sun.rotation_euler = (math.radians(60), 0, math.radians(-75))
scene.render.filepath = os.path.join(RENDER, "stage10_HI_chest_sidelit.png"); bpy.ops.render.render(write_still=True)
for o in bpy.data.objects:
    if o.type == "MESH" and o is not torso:
        o.hide_render = False
for o in (cam, sun):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)
morphed = [v.co.copy() for v in body.data.vertices]

# ============================================================ B. rigged file: copy the morphed positions by index, re-hug straps
if not os.path.exists(BACKUP):
    shutil.copy(STAGE5, BACKUP); print("backup", os.path.basename(BACKUP))
else:
    print("backup exists, restoring it first:", os.path.basename(BACKUP)); shutil.copy(BACKUP, STAGE5)
bpy.ops.wm.open_mainfile(filepath=STAGE5)
scene = bpy.context.scene
arm = bpy.data.objects["Miner_Rig"]; rb = bpy.data.objects["Miner_Body"]
arm.data.pose_position = "REST"; bpy.context.view_layer.update()
assert len(rb.data.vertices) == len(morphed), "rigged body %d verts vs stage-9 %d — not the same mesh" % (len(rb.data.vertices), len(morphed))
moved = 0
for v, co in zip(rb.data.vertices, morphed):
    if (v.co - co).length > 1e-6:
        moved += 1
    v.co = co
rb.data.update()
print("RIGGED body: %d verts moved" % moved)
report_relief(verts_world(rb), "AFTER rigged")
for o in bpy.data.objects:
    if o.name.startswith("Strap_Torso"):
        sw = o.modifiers.new("hug", "SHRINKWRAP"); sw.target = rb; sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.008
        select_only(o); bpy.ops.object.modifier_apply(modifier="hug")
        print("re-hugged", o.name)

# renders: rest-pose torso front / right-front lit from the side / walk_crouch front
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
for o in bpy.data.objects:
    if o.name.startswith("Gauge"):
        o.hide_render = True
views = {"torso_front": ((0, -2.6, 1.5), (math.radians(88), 0, 0), (math.radians(88), 0, 0)),
         "chest_sidelit": ((-0.7, -1.6, 1.6), (math.radians(86), 0, math.radians(-22)), (math.radians(60), 0, math.radians(-75))),
         "torso_sidelit": ((-0.9, -2.4, 1.5), (math.radians(88), 0, math.radians(-20)), (math.radians(60), 0, math.radians(-70))),
         "torso_left": ((-2.6, -0.4, 1.5), (math.radians(88), 0, math.radians(-80)), (math.radians(88), 0, math.radians(-80)))}
for vname, (loc, rot, srot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; sun.rotation_euler = srot
    scene.render.filepath = os.path.join(RENDER, f"stage10_{vname}.png")
    bpy.ops.render.render(write_still=True)
for o in (cam, sun):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=STAGE5)
print("saved", STAGE5)
r, l = after_lo
ok = r >= RELIEF_MIN and r >= RELIEF_RATIO * l
print("STAGE10 RELIEF %s (right %.1f mm >= %.0f, ratio %.2f >= %.1f; before %.1f)" % ("PASS" if ok else "FAIL", r * 1000, RELIEF_MIN * 1000, r / l if l else 0, RELIEF_RATIO, before_lo[0] * 1000))
