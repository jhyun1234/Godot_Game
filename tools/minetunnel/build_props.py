# -*- coding: utf-8 -*-
"""소품 9종 (제안서 #27 소품 뿌리기). 모듈(build_tunnel.py)에 박혀 있던 상자·통·삽·망치·양동이·석유등·잔해·부러진 갱목을
따로 뽑아 Documents/MineTunnel/Props.blend 에 저장한다. 조립기(MineAssembler.gd)가 시드로 갱도에 뿌린다.

    blender -b --python tools/minetunnel/build_props.py            (bash tools/minetunnel/export.sh 가 Props.blend → mine_props.gltf)

규칙:
  - 소품마다 빈 오브젝트 PROP_<이름> 하나가 뿌리, 그 아래 메시. 뿌리는 전부 원점, 바닥(z 0)에 닿게 내린다.
  - 컬렉션 하나(PROPS). export.sh 가 coll=PROPS 로 한 파일(mine_props.gltf)로 뽑는다 — Godot 에서 자식 노드를 복제해 쓴다.
  - 충돌 없음(모듈 때와 같다). Poly Haven CC0 모델은 Documents/MineTunnel/models/ (build_tunnel.py 가 받아 둔 것).
"""
import bpy, bmesh, math, random, os, sys

PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Props.blend")
MODEL_DIR = os.path.join(PROJ, "models")
SEED = 7
random.seed(SEED)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in ("MAT_Timber", "MAT_Rock") if n in src.materials]
M = bpy.data.materials
for n in ("MAT_Timber", "MAT_Rock"): assert n in M, n

props = bpy.data.collections.new("PROPS"); sc.collection.children.link(props)

def new_obj(name, data, mat=None, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
    assert name not in bpy.data.objects, "이름 겹침: " + name
    o = bpy.data.objects.new(name, data); props.objects.link(o)
    if mat is not None and data is not None and hasattr(data, "materials") and not data.materials: data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    if parent: o.parent = parent
    return o
def box(name, size, loc, mat, rot=(0, 0, 0), parent=None):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, mat, loc, rot, parent)
    b = o.modifiers.new("Bevel", 'BEVEL'); b.width = 0.012; b.segments = 2
    return o
def rock_mesh(name, noise=0.25):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts: v.co += v.co.normalized() * random.uniform(-noise, noise)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    return me
def import_gltf(asset, name, rot=(0, 0, 0), scale=1.0):
    """Poly Haven 모델을 뿌리 PROP_<name> 아래로. build_tunnel.py 의 것과 같다."""
    before = set(o.name for o in bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL_DIR, asset, f"{asset}.gltf"))
    new = [o for o in bpy.data.objects if o.name not in before]; newset = set(new)
    root = new_obj(name, None, rot=rot)
    for o in new:
        for c in list(o.users_collection): c.objects.unlink(o)
        props.objects.link(o)
        if o.parent is None or o.parent not in newset: o.parent = root
    for o in new: o.name = f"{name}_{o.name}"
    root.scale = (scale,) * 3
    return root
def bbox(root):
    dg = bpy.context.evaluated_depsgraph_get()
    lo = [1e9] * 3; hi = [-1e9] * 3
    for o in [root] + list(root.children_recursive):
        if o.type != 'MESH': continue
        ev = o.evaluated_get(dg)
        for v in ev.data.vertices:
            p = ev.matrix_world @ v.co
            for i in range(3): lo[i] = min(lo[i], p[i]); hi[i] = max(hi[i], p[i])
    return lo, hi
def ground(root):
    """뿌리를 옮겨 가장 낮은 정점이 z 0, xy 가운데가 원점에 오게."""
    bpy.context.view_layer.update()
    lo, hi = bbox(root)
    root.location.x -= (lo[0] + hi[0]) / 2; root.location.y -= (lo[1] + hi[1]) / 2; root.location.z -= lo[2]
    bpy.context.view_layer.update()
    lo, hi = bbox(root)
    print("ok %-14s 크기 %.2f × %.2f × %.2f" % (root.name, hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))
def lay_flat(root):
    """세 축 회전 중 가장 납작해지는 것 — 삽·망치는 바닥에 눕는다."""
    best = None
    for rot in ((0, 0, 0), (math.pi / 2, 0, 0), (0, math.pi / 2, 0)):
        root.rotation_euler = rot; bpy.context.view_layer.update()
        lo, hi = bbox(root); h = hi[2] - lo[2]
        if best is None or h < best[0]: best = (h, rot)
    root.rotation_euler = best[1]

# ---------------- 소품 9 ----------------
ground(import_gltf("wooden_crate_01", "PROP_crate", (0, 0, 0.2)))
ground(import_gltf("wooden_crate_01", "PROP_crate_s", (0, 0, -0.35), 0.85))
br = import_gltf("wooden_barrels_01", "PROP_barrels")
for c in list(br.children_recursive):
    if "piece" in c.name: bpy.data.objects.remove(c, do_unlink=True)
for c, loc, rz in ((next(c for c in br.children_recursive if c.name.endswith("barrel01")), (0, 0, 0), 0.3),
                   (next(c for c in br.children_recursive if c.name.endswith("barrel02")), (0, 0.72, 0), -0.6)):
    c.parent = br; c.matrix_parent_inverse.identity(); c.location = loc; c.rotation_euler = (0, 0, rz)
ground(br)
sp = import_gltf("rusted_spade_01", "PROP_spade"); lay_flat(sp); ground(sp)
sl = import_gltf("sledgehammer_01", "PROP_sledge"); lay_flat(sl); ground(sl)
ground(import_gltf("wooden_bucket_01", "PROP_bucket", (0, 0, 1.2)))
ground(import_gltf("vintage_oil_lamp", "PROP_lamp", (0, 0, 0.6)))
# 돌무더기 (모듈의 PRP_Rubble 18개와 같은 규칙, 한 무더기)
rb = new_obj("PROP_rubble", None)
for i in range(18):
    r = random.uniform(0.1, 0.28)
    o = new_obj(f"PROP_rubble_{i}", rock_mesh(f"PROP_rubble_{i}"), M["MAT_Rock"],
                (random.uniform(-0.45, 0.45), random.uniform(-0.6, 0.6), r * 0.4 + random.uniform(0, 0.25)), (random.uniform(0, 6),) * 3, rb)
    o.scale = (r * random.uniform(0.8, 1.2), r * random.uniform(0.8, 1.2), r * random.uniform(0.5, 0.8))
ground(rb)
# 부러진 갱목 — 모듈의 PRP_BrokenPost 와 같은 각재·기울기
po = new_obj("PROP_post", None)
box("PROP_post_beam", (0.22, 0.22, 2.4), (0, 0, 0), M["MAT_Timber"], (1.3, 0.0, 0.3), po)   # 거의 누움 — 벽 없이도 뜨지 않는다
ground(po)

roots = [o for o in props.objects if o.name.startswith("PROP_") and o.parent is None]
assert len(roots) == 9, [o.name for o in roots]
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
dg = bpy.context.evaluated_depsgraph_get()
tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in bpy.data.objects if o.type == 'MESH')
print("ok 저장 %s  소품 %d  삼각형 %d" % (OUT_BLEND, len(roots), tris))
