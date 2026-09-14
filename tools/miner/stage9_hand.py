"""Stage 9 (proposal #42): replace the body's sausage hands with a separately generated hand (Hunyuan, hand-only image).
usage: blender -b --factory-startup -P blender/stage9_hand.py [-- <hand.glb>]
Inputs : blender/miner_v2_stage8.blend (Miner_Body 42.8k with the #41 head, Miner_Body_HI, timber), mesh/hand_s50_o512.glb
Outputs: blender/miner_v2_stage9.blend (same object names as stage 8 -> stage5b_retarget.py / stage7_bake.py read it),
         blender/stage9_render/*.png, and a SHARPNESS PASS/FAIL line per claw in the log.
Method : everything is measured. Body wrist = narrowest x-slice of each arm in WRIST_LO..WRIST_HI. Hand mesh: PCA long axis
         -> +X, the wrist end is the end whose 5 % slice is narrower (bone stub vs spread claws), the palm-only PCA refines
         the axis, the claws' curl (tip centroid offset from the palm axis) is rolled to -Z, the hooked short claw is put on
         the front (-Y, thumb side) by a Y-mirror if needed. Scale = body wrist width / hand wrist width, capped so the hand
         is at most HAND_LEN_MAX long. Body is cut outside the wrist, the hand inside the wrist minus WRIST_OVERLAP, holes
         capped, decimated, X-mirrored for the other arm, joined. Two wrist straps hide the seams."""
import bpy, os, sys, math
from mathutils import Vector, Matrix

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE8 = os.path.join(ROOT, "blender", os.environ.get("IN_BLEND", "miner_v2_stage8.blend"))
HAND_GLB = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "mesh", "hand_s50_o512.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage9.blend")
RENDER = os.path.join(ROOT, "blender", "stage9_render")
os.makedirs(RENDER, exist_ok=True)

WRIST_LO, WRIST_HI = 0.95, 1.25   # body: search the narrowest x-slice of each arm here (Hand bone head is at |x| 1.136; the blob hand starts at 1.09)
SLICE = 0.01                      # m
WRIST_OVERLAP = 0.02              # m, the hand shell reaches this far into the forearm
HAND_LEN_MAX = float(os.environ.get("HAND_LEN_MAX", "0.60"))     # m, wrist -> farthest claw tip (forearm is 0.50)
HAND_SCALE_MUL = float(os.environ.get("HAND_SCALE_MUL", "1.0"))  # F5 knob
HAND_FACES = 8000                 # per hand (body is 43k)
HAND_HI_FACES = 150000            # per hand in the HI copy (normal bake source)
TIP_BACK = 0.020                  # sharpness: the claw's cross-section this far back from the tip ...
TIP_SHELL = 0.005                 # ... (vertices at TIP_BACK +- this from the tip vertex) ...
TIP_WIDTH_MAX = 0.020             # ... must span at most this. Measured: generated claws 12-16 mm (8k-face game mesh), the old sausage 34 mm
CLAW_FRAC = 0.55                  # claws are separate components beyond this fraction of the hand length
CLAW_LEN_MIN = 0.10               # components shorter than this are knuckle nubs, not claws

bpy.ops.wm.open_mainfile(filepath=STAGE8)
scene = bpy.context.scene
body = bpy.data.objects["Miner_Body"]; hi = bpy.data.objects["Miner_Body_HI"]
rig = bpy.data.objects.get("Timber_Rig")
M = {m.name: m for m in bpy.data.materials}


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


expose(hi)


def verts_world(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def slice_yz(pts, x, t=SLICE):
    s = [p for p in pts if x - t / 2 <= p.x < x + t / 2]
    if len(s) < 6:
        return None
    ys = [p.y for p in s]; zs = [p.z for p in s]
    return dict(x=x, w=max(ys) - min(ys), h=max(zs) - min(zs), cy=(max(ys) + min(ys)) / 2, cz=(max(zs) + min(zs)) / 2, n=len(s))


def narrowest_x(pts, xlo, xhi):
    best = None; x = xlo
    while x <= xhi:
        st = slice_yz(pts, x)
        if st and (best is None or st["w"] + st["h"] < best["w"] + best["h"]):
            best = st
        x += SLICE
    assert best, "no slices in %.2f..%.2f" % (xlo, xhi)
    return best


def select_only(o):
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o


def bisect_keep(o, co, no, keep_positive):
    """cut o by the plane (co, no); keep the side the normal points to (or the other), cap the hole"""
    select_only(o)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.bisect(plane_co=co, plane_no=no, clear_inner=keep_positive, clear_outer=not keep_positive, use_fill=True)
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


def components(o, keep):
    """connected components (vertex index lists) of the sub-mesh of vertices where keep(world co) is true"""
    pts = verts_world(o)
    inside = [keep(p) for p in pts]
    parent = list(range(len(pts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]; i = parent[i]
        return i
    for e in o.data.edges:
        a, b = e.vertices
        if inside[a] and inside[b]:
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb
    groups = {}
    for i, ok in enumerate(inside):
        if ok:
            groups.setdefault(find(i), []).append(i)
    return [g for g in groups.values() if len(g) >= 20], pts


def sharpness(o, x_base, sign, label):
    """per claw (component beyond the palm, longer than CLAW_LEN_MIN): tip = vertex farthest from the root; width = span of the vertex ring TIP_BACK behind it"""
    comps, pts = components(o, lambda p: sign * p.x > x_base)
    rows = []
    for g in sorted(comps, key=len, reverse=True):
        root = [i for i in g if sign * pts[i].x < x_base + 0.015] or g          # vertices next to the cut plane = the claw's root
        base = sum((pts[i] for i in root), Vector()) / len(root)
        far = max(g, key=lambda i: (pts[i] - base).length)          # tip = farthest vertex from the root (the hooked claw curls back in x)
        tip = pts[far]
        length = (tip - base).length
        if length < CLAW_LEN_MIN:
            continue
        ring = [pts[i] for i in g if abs((pts[i] - tip).length - TIP_BACK) <= TIP_SHELL]
        width = max((a - b).length for a in ring for b in ring) if len(ring) > 1 else 0.0
        rows.append((width, length, len(g), len(ring), tip))
    print("SHARPNESS %s: %d claw components (length >= %.2f) beyond |x| %.3f" % (label, len(rows), CLAW_LEN_MIN, x_base))
    ok = True
    for k, (w, L, n, nr, tip) in enumerate(rows):
        res = "PASS" if w <= TIP_WIDTH_MAX else "FAIL"
        ok &= w <= TIP_WIDTH_MAX
        print("  claw %d: width %.1f mm at %.0f cm behind the tip (max %.0f, %d ring verts) length %.2f m verts %d tip (%.3f %.3f %.3f) %s" % (
            k, w * 1000, TIP_BACK * 100, TIP_WIDTH_MAX * 1000, nr, L, n, tip.x, tip.y, tip.z, res))
    if len(rows) < 4:
        print("  FAIL: fewer than 4 separate claws"); ok = False
    print("SHARPNESS %s RESULT %s" % (label, "PASS" if ok else "FAIL"))
    return ok


# ---- 1. body wrists (both arms), old-hand sharpness as the built-in sabotage reference
bpts = verts_world(body)
wrist = {}
for sign in (1, -1):
    side = [Vector((sign * p.x, p.y, p.z)) for p in bpts]        # fold the arm onto +x
    w = narrowest_x(side, WRIST_LO, WRIST_HI)
    wrist[sign] = w
    print("BODY wrist %+d: x %.3f  width %.3f  height %.3f  centre (%.3f, %.3f)  arm end x %.3f" % (sign, w["x"], w["w"], w["h"], w["cy"], w["cz"], max(p.x for p in side)))
old_len = max(p.x for p in bpts) - wrist[1]["x"]
sharpness(body, wrist[1]["x"] + CLAW_FRAC * old_len, 1, "OLD sausage hand (+x)")

# ---- 2. hand mesh in, measured, aligned to +x (the character's left arm)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=HAND_GLB)
new = [o for o in bpy.data.objects if o not in before]
hm = [o for o in new if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in hm:
    o.select_set(True)
bpy.context.view_layer.objects.active = hm[0]
if len(hm) > 1:
    bpy.ops.object.join()
hand = bpy.context.view_layer.objects.active; hand.name = "Hand_src"
for o in new:
    if o.type != "MESH" and o.name in bpy.data.objects:
        if hand.parent == o:
            m = hand.matrix_world.copy(); hand.parent = None; hand.matrix_world = m
        bpy.data.objects.remove(o, do_unlink=True)
select_only(hand); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print("HAND src faces %d" % len(hand.data.polygons))


def pca_axis(pts):
    c = sum(pts, Vector()) / len(pts)
    cov = [[0.0] * 3 for _ in range(3)]
    for p in pts:
        d = p - c
        for i in range(3):
            for j in range(3):
                cov[i][j] += d[i] * d[j]
    v = Vector((1, 0.3, 0.2)).normalized()          # power iteration -> largest eigenvector
    for _ in range(60):
        v = Vector((sum(cov[i][j] * v[j] for j in range(3)) for i in range(3))).normalized()
    return c, v


def apply_matrix(o, mat):
    for v in o.data.vertices:
        v.co = mat @ v.co
    o.data.update()


def rot_to_x(v):
    """rotation matrix taking unit vector v to +X"""
    return v.rotation_difference(Vector((1, 0, 0))).to_matrix().to_4x4()


def local_pts(o):
    return [v.co.copy() for v in o.data.vertices]


hpts = local_pts(hand)
c, axis = pca_axis(hpts)
apply_matrix(hand, rot_to_x(axis) @ Matrix.Translation(-c))
hpts = local_pts(hand)
x0, x1 = min(p.x for p in hpts), max(p.x for p in hpts); L = x1 - x0


def end_extent(frac_lo, frac_hi):
    s = [p for p in hpts if x0 + frac_lo * L <= p.x <= x0 + frac_hi * L]
    return (max(p.y for p in s) - min(p.y for p in s)) + (max(p.z for p in s) - min(p.z for p in s))


ext_lo, ext_hi = end_extent(0.02, 0.08), end_extent(0.92, 0.98)
print("HAND ends: extent at x-low end %.3f, x-high end %.3f (narrow one = wrist/bone stub)" % (ext_lo, ext_hi))
if ext_hi < ext_lo:                                   # wrist is at the high end: flip 180 deg about z
    apply_matrix(hand, Matrix.Rotation(math.pi, 4, "Z"))
    hpts = local_pts(hand); x0, x1 = min(p.x for p in hpts), max(p.x for p in hpts)
# refine the axis with the palm only (claws curl and tilt the whole-hand PCA)
palm = [p for p in hpts if p.x < x0 + 0.5 * L]
c, axis = pca_axis(palm)
if axis.x < 0:
    axis = -axis
apply_matrix(hand, rot_to_x(axis) @ Matrix.Translation(-c))
hpts = local_pts(hand); x0, x1 = min(p.x for p in hpts), max(p.x for p in hpts); L = x1 - x0
# roll: the claws' curl direction (tip-end centroid vs palm centroid, perpendicular to x) goes to -Z
tips = [p for p in hpts if p.x > x0 + 0.85 * L]; palm = [p for p in hpts if p.x < x0 + 0.5 * L]
curl = (sum(tips, Vector()) / len(tips)) - (sum(palm, Vector()) / len(palm)); curl.x = 0
print("HAND curl direction (y, z) = (%.3f, %.3f)" % (curl.y, curl.z))
ang = math.atan2(curl.y, -curl.z)                    # rotate about x so that curl -> (0, -1)
apply_matrix(hand, Matrix.Rotation(ang, 4, "X"))
hpts = local_pts(hand)
tips = [p for p in hpts if p.x > x0 + 0.85 * L]; palm = [p for p in hpts if p.x < x0 + 0.5 * L]
curl = (sum(tips, Vector()) / len(tips)) - (sum(palm, Vector()) / len(palm))
print("HAND curl after roll (y, z) = (%.3f, %.3f)  (want y ~ 0, z < 0)" % (curl.y, curl.z))
x0, x1 = min(p.x for p in hpts), max(p.x for p in hpts); L = x1 - x0
# wrist = narrowest slice past the bone stub (8..40 % of the length)
hw = narrowest_x(hpts, x0 + 0.08 * L, x0 + 0.40 * L)
print("HAND wrist: x %.3f (%.0f%% of length %.3f)  width %.3f  height %.3f  centre (%.3f, %.3f)" % (hw["x"], 100 * (hw["x"] - x0) / L, L, hw["w"], hw["h"], hw["cy"], hw["cz"]))
# chirality: the hooked short claw (component with the smallest x reach beyond the palm) must sit at -Y (thumb side, front) for the +x arm
comps, _ = components(hand, lambda p: p.x > x0 + 0.6 * L)
comps = sorted(comps, key=len, reverse=True)[:4]
if len(comps) >= 2:
    short = min(comps, key=lambda g: max(hpts[i].x for i in g))
    ys = sum(hpts[i].y for i in short) / len(short)
    print("HAND hooked claw centroid y %.3f (%d comps)" % (ys, len(comps)))
    if ys > 0:
        apply_matrix(hand, Matrix.Scale(-1, 4, Vector((0, 1, 0))))
        select_only(hand); bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
        hw["cy"] = -hw["cy"]; print("HAND mirrored in Y (thumb side to the front)")
# scale: wrist width match, capped by HAND_LEN_MAX; place on the +x arm
bw = wrist[1]
s_w = ((bw["w"] + bw["h"]) / (hw["w"] + hw["h"])) * HAND_SCALE_MUL
s_l = HAND_LEN_MAX / (x1 - hw["x"])
s = min(s_w, s_l)
print("HAND scale: by wrist %.4f (hand length %.3f) / by length cap %.4f -> %.4f, hand length %.3f, wrist %.3f x %.3f vs body %.3f x %.3f" % (
    s_w, s_w * (x1 - hw["x"]), s_l, s, s * (x1 - hw["x"]), s * hw["w"], s * hw["h"], bw["w"], bw["h"]))
apply_matrix(hand, Matrix.Translation((bw["x"], bw["cy"], bw["cz"])) @ Matrix.Scale(s, 4) @ Matrix.Translation((-hw["x"], -hw["cy"], -hw["cz"])))
hand.matrix_world.identity()
hpts = verts_world(hand)
print("HAND placed: x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (min(p.x for p in hpts), max(p.x for p in hpts), min(p.y for p in hpts), max(p.y for p in hpts), min(p.z for p in hpts), max(p.z for p in hpts)))

# ---- 3. cut, cap, decimate, mirror, join
hand_hi = hand.copy(); hand_hi.data = hand.data.copy(); hand_hi.name = "Hand_hi"; scene.collection.objects.link(hand_hi)
for sign in (1, -1):
    xw = wrist[sign]["x"]
    print("BODY cut outside x %+.3f: faces %d -> %d" % (sign * xw, len(body.data.polygons), bisect_keep(body, (sign * xw, 0, 0), (sign, 0, 0), keep_positive=False)))
    print("HI   cut outside x %+.3f: faces %d -> %d" % (sign * xw, len(hi.data.polygons), bisect_keep(hi, (sign * xw, 0, 0), (sign, 0, 0), keep_positive=False)))
xc = wrist[1]["x"] - WRIST_OVERLAP
print("HAND cut inside x %.3f: faces %d -> %d" % (xc, len(hand.data.polygons), bisect_keep(hand, (xc, 0, 0), (1, 0, 0), keep_positive=True)))
bisect_keep(hand_hi, (xc, 0, 0), (1, 0, 0), keep_positive=True)
decimate_to(hand_hi, HAND_HI_FACES)
decimate_to(hand, HAND_FACES)
print("HAND decimated to %d faces (target %d), HI %d" % (len(hand.data.polygons), HAND_FACES, len(hand_hi.data.polygons)))
hand_len = max(p.x for p in verts_world(hand)) - wrist[1]["x"]
sharp_ok = sharpness(hand, wrist[1]["x"] + CLAW_FRAC * hand_len, 1, "NEW hand (+x, game mesh)")
for o in (hand, hand_hi):
    o.data.materials.clear(); o.data.materials.append(M["살"])


def mirrored(o, name):
    m = o.copy(); m.data = o.data.copy(); m.name = name; scene.collection.objects.link(m)
    dx = wrist[-1]["x"] - wrist[1]["x"]; dy = wrist[-1]["cy"] - wrist[1]["cy"]; dz = wrist[-1]["cz"] - wrist[1]["cz"]
    apply_matrix(m, Matrix.Translation((-dx, dy, dz)) @ Matrix.Scale(-1, 4, Vector((1, 0, 0))))   # x-mirror, then shift to the -x wrist
    select_only(m); bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
    return m


hand_r = mirrored(hand, "Hand_R"); hand_hi_r = mirrored(hand_hi, "Hand_hi_R")
hand_faces = len(hand.data.polygons) * 2
join_into(body, hand); join_into(body, hand_r); join_into(hi, hand_hi); join_into(hi, hand_hi_r)
body.name = "Miner_Body"; hi.name = "Miner_Body_HI"
select_only(body); bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.01)
bpy.ops.object.mode_set(mode="OBJECT")
print("JOINED body faces %d (hands %d = %.0f%%)  HI faces %d" % (len(body.data.polygons), hand_faces, 100.0 * hand_faces / len(body.data.polygons), len(hi.data.polygons)))
sharpness(body, wrist[-1]["x"] + CLAW_FRAC * hand_len, -1, "NEW hand (-x, mirrored, joined)")

# ---- 4. wrist straps over the seams (stage-8 neck strap recipe, axis along x)
for sign, name in ((1, "Strap_Wrist_L"), (-1, "Strap_Wrist_R")):
    w = wrist[sign]
    bpy.ops.mesh.primitive_torus_add(major_radius=1, minor_radius=0.010, location=(sign * w["x"], w["cy"], w["cz"]), rotation=(0, math.pi / 2, 0), major_segments=32, minor_segments=8)
    strap = bpy.context.active_object; strap.name = name
    strap.scale = Vector((w["h"] / 2 + 0.025, w["w"] / 2 + 0.025, 1))   # rotated 90 deg about y: local x -> world z (height), local y -> world y (width)
    strap.data.materials.append(M["가죽끈"])
    if rig:
        strap.parent = rig
    sw = strap.modifiers.new("hug", "SHRINKWRAP"); sw.target = body; sw.wrap_mode = "OUTSIDE_SURFACE"; sw.offset = 0.008

bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)

# ---- 5. renders
for o in bpy.data.objects:
    if o.name.startswith("Gauge"):
        o.hide_render = True
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.lens = 50
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
hz = wrist[1]["cz"]
views = {"front": ((0, -6, 1.3), (math.radians(88), 0, 0)), "iso": ((-4.2, -4.2, 2.2), (math.radians(78), 0, math.radians(-45))),
         "hand_L_front": ((1.3, -1.6, hz), (math.radians(90), 0, 0)), "hand_L_top": ((1.3, 0, hz + 1.6), (0, 0, 0)),
         "hand_R_iso": ((-1.9, -1.1, hz + 0.6), (math.radians(65), 0, math.radians(-35)))}
for vname, (loc, rot) in views.items():
    cam.location = loc; cam.rotation_euler = rot; sun.rotation_euler = rot
    scene.render.filepath = os.path.join(RENDER, f"stage9_{vname}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", list(views))
print("STAGE9 SHARPNESS", "PASS" if sharp_ok else "FAIL")
