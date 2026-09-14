"""Side-by-side comparison of body candidates: same normalisation (height 2.5 m, feet z 0, arms along x, front -y),
same 4 views + face/hand close-ups, same light, plus numbers (faces, texture sizes, claw tip width, chest relief).
usage: blender -b --factory-startup -P scripts/compare_bodies.py -- <out_dir> <label=path.glb> [label=path.glb ...]
Writes <out_dir>/<label>_<view>.png and <out_dir>/numbers.json. The contact sheet is made afterwards with PIL (compare_sheet.py)."""
import bpy, sys, os, math, json
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir = args[0]; cands = [a.split("=", 1) for a in args[1:]]
os.makedirs(out_dir, exist_ok=True)
H = 2.5


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    body = max(meshes, key=lambda o: len(o.data.polygons))     # the body (timber/straps are separate small meshes in the game GLB)
    for o in bpy.data.objects:
        o.select_set(False)
    for o in meshes:
        if o is not body:
            bpy.data.objects.remove(o, do_unlink=True)
    body.select_set(True); bpy.context.view_layer.objects.active = body
    for m in list(body.modifiers):            # armature etc.: rest pose is what we compare
        body.modifiers.remove(m)
    body.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return body


def pts_of(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


def normalise(body):
    """height 2.5, feet z 0, arm span along x, front toward -y (the concept's decayed side ends up on -x by the claw check below)"""
    pts = pts_of(body)
    lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
    ext = hi - lo
    # T-pose: arm span (3.3) > height (2.5) > depth (0.4) -> largest extent = span, second = up, smallest = depth
    order = sorted(range(3), key=lambda i: -ext[i]); span, up, depth = order
    s = H / ext[up]
    c = (lo + hi) / 2
    for v in body.data.vertices:
        p = body.matrix_world @ v.co
        q = Vector(((p[span] - c[span]) * s, (p[depth] - c[depth]) * s, (p[up] - lo[up]) * s))
        v.co = q
    body.matrix_world.identity(); body.data.update()
    # front = the side where the face/helmet lamp and the toes point: toes stick out in front -> feet slice (z<0.08) centroid y sign
    pts = pts_of(body)
    feet = [p for p in pts if p.z < 0.08] or pts; hips = [p for p in pts if 1.0 < p.z < 1.3 and abs(p.x) < 0.3] or pts
    fy = sum(p.y for p in feet) / len(feet); hy = sum(p.y for p in hips) / len(hips)
    print("  orient: axes span/up/depth =", span, up, depth, " feet y %.3f hips y %.3f" % (fy, hy))
    if fy > hy:                                  # toes point +y: flip so the front is -y (rotate 180 about z)
        for v in body.data.vertices:
            v.co.x, v.co.y = -v.co.x, -v.co.y
        body.data.update()
    return body


def slice_yz(pts, x, t=0.01):
    s = [p for p in pts if x - t / 2 <= p.x < x + t / 2]
    if len(s) < 6:
        return None
    ys = [p.y for p in s]; zs = [p.z for p in s]
    return dict(x=x, w=max(ys) - min(ys), h=max(zs) - min(zs))


def wrist_x(pts, sign):
    best = None; x = 0.85
    while x <= 1.35:
        st = slice_yz([Vector((sign * p.x, p.y, p.z)) for p in pts if 1.4 < p.z < 2.2], x)
        if st and (best is None or st["w"] + st["h"] < best[0]):
            best = (st["w"] + st["h"], x)
        x += 0.01
    return best[1] if best else None


def components(o, keep):
    pts = pts_of(o); inside = [keep(p) for p in pts]; parent = list(range(len(pts)))

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
    g = {}
    for i, ok in enumerate(inside):
        if ok:
            g.setdefault(find(i), []).append(i)
    return [v for v in g.values() if len(v) >= 20], pts


def claws(o, sign):
    """claw components beyond 55 % of the hand; returns list of (width 2 cm behind tip in mm, length m)"""
    pts = pts_of(o)
    wx = wrist_x(pts, sign)
    if wx is None:
        return []
    end = max(sign * p.x for p in pts)
    base = wx + 0.55 * (end - wx)
    comps, pts = components(o, lambda p: sign * p.x > base)
    rows = []
    for g in comps:
        root = [i for i in g if sign * pts[i].x < base + 0.015] or g
        b = sum((pts[i] for i in root), Vector()) / len(root)
        far = max(g, key=lambda i: (pts[i] - b).length); tip = pts[far]
        if (tip - b).length < 0.08:
            continue
        ring = [pts[i] for i in g if abs((pts[i] - tip).length - 0.02) <= 0.005]
        w = max((a - c).length for a in ring for c in ring) if len(ring) > 1 else 0.0
        rows.append((round(w * 1000, 1), round((tip - b).length, 2)))
    return sorted(rows, key=lambda r: -r[1])


def relief(pts, x0, x1, z0, z1, C=0.03):
    cells = {}
    for p in pts:
        if x0 <= p.x <= x1 and z0 <= p.z <= z1 and p.y < 0.05:
            k = (round(p.x / C), round(p.z / C)); cells[k] = min(cells.get(k, 1e9), p.y)
    res = []
    for (i, j), y in cells.items():
        nb = [cells[(i + di, j + dj)] for di in (-1, 0, 1) for dj in (-1, 0, 1) if (di or dj) and (i + di, j + dj) in cells]
        if len(nb) >= 6:
            res.append(y - sum(nb) / len(nb))
    return round(math.sqrt(sum(r * r for r in res) / len(res)) * 1000, 1) if res else 0.0


def textures():
    return sorted({(i.name, i.size[0]) for i in bpy.data.images if i.size[0] > 0})


def render_views(body, label):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 768
    w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.22, 0.22, 0.22, 1)
    for m in bpy.data.materials:                    # same shading for all: matte (the game forces roughness 1 / metallic 0 anyway)
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "BSDF_PRINCIPLED":
                    n.inputs["Roughness"].default_value = 1.0; n.inputs["Metallic"].default_value = 0.0
                    for l in list(n.inputs["Metallic"].links) + list(n.inputs["Roughness"].links):
                        m.node_tree.links.remove(l)
    if not body.data.materials or all(m is None for m in body.data.materials):
        m = bpy.data.materials.new("grey"); m.use_nodes = True; body.data.materials.append(m)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3.5; scene.collection.objects.link(sun)
    cam.data.type = "ORTHO"
    views = {"front": ((0, -8, 1.25), (math.pi / 2, 0, 0), 3.4), "back": ((0, 8, 1.25), (math.pi / 2, 0, math.pi), 3.4),
             "left": ((8, 0, 1.25), (math.pi / 2, 0, math.pi / 2), 3.0),
             "face": ((0.3, -8, 2.2), (math.pi / 2, 0, 0), 0.7), "hand": ((-1.3, -8, 1.8), (math.pi / 2, 0, 0), 0.8), "chest": ((0, -8, 1.6), (math.pi / 2, 0, 0), 1.1)}
    for n, (loc, rot, scale) in views.items():
        cam.location = loc; cam.rotation_euler = rot; cam.data.ortho_scale = scale
        sun.rotation_euler = (math.radians(60), 0, math.radians(-35)) if n in ("chest", "face", "hand") else rot
        scene.render.filepath = os.path.join(out_dir, f"{label}_{n}.png"); bpy.ops.render.render(write_still=True)


numbers = {}
for label, path in cands:
    reset()
    body = load(path)
    raw_faces = len(body.data.polygons)
    normalise(body)
    pts = pts_of(body)
    cl = {s: claws(body, s) for s in (1, -1)}
    numbers[label] = dict(path=path, faces=raw_faces, verts=len(body.data.vertices), textures=textures(),
                          claws_left=cl[1], claws_right=cl[-1],
                          chest_relief_right=relief(pts, -0.20, -0.05, 1.50, 1.80), chest_relief_left=relief(pts, 0.05, 0.20, 1.50, 1.80),
                          span_x=round(max(p.x for p in pts) - min(p.x for p in pts), 2))
    print("NUMBERS", label, json.dumps(numbers[label], ensure_ascii=False))
    render_views(body, label)
json.dump(numbers, open(os.path.join(out_dir, "numbers.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("DONE", out_dir)
