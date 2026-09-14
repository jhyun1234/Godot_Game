# -*- coding: utf-8 -*-
"""광차 (제안서 #29). 모듈(build_tunnel.py)에 박혀 있던 큰 광차(시신 운반용)를 따로 뽑아 Documents/MineTunnel/Cart.blend 에 저장한다.
조립기(MineAssembler._place_carts)가 순환선 Path3D 위에 CART_COUNT 대 놓는다.

    blender -b --python tools/minetunnel/build_cart.py            (ONLY=mine_cart bash tools/minetunnel/export.sh 가 Cart.blend → mine_cart.gltf)

규칙:
  - 뿌리 빈 오브젝트 CART 하나, 원점 = 레일 가운데 바닥(z 0). 긴 축 = +Y (Godot 에서 −Z = 앞).
  - 바퀴 궤간 0.6 (rail_*.gltf 의 RAIL_GAUGE). 짐칸 바닥 z 0.60, 테두리 z 1.72. 충돌 없음(탑승은 코드가 자리를 잠근다).
  - 컬렉션 하나(CART). 재질은 MineTunnel.blend 의 MAT_RustyMetal·MAT_Rock.
"""
import bpy, bmesh, math, random, os
from mathutils import Vector

PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Cart.blend")
GAUGE = 0.6
random.seed(29)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in ("MAT_RustyMetal", "MAT_Rock") if n in src.materials]
M = bpy.data.materials
for n in ("MAT_RustyMetal", "MAT_Rock"): assert n in M, n

coll = bpy.data.collections.new("CART"); sc.collection.children.link(coll)

def new_obj(name, data, mat=None, loc=(0, 0, 0), rot=(0, 0, 0), parent=None):
    assert name not in bpy.data.objects, "이름 겹침: " + name
    o = bpy.data.objects.new(name, data); coll.objects.link(o)
    if mat is not None and data is not None and hasattr(data, "materials") and not data.materials: data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    if parent: o.parent = parent
    return o
def box(name, size, loc, mat, rot=(0, 0, 0), parent=None, bevel=0.012):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, mat, loc, rot, parent)
    if bevel:
        b = o.modifiers.new("Bevel", 'BEVEL'); b.width = bevel; b.segments = 2
    return o
def cyl(name, r, h, loc, mat, rot=(0, 0, 0), segs=16, parent=None):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, mat, loc, rot, parent)
    for p in me.polygons: p.use_smooth = True
    return o
def rock_mesh(name, noise=0.2):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts: v.co += v.co.normalized() * random.uniform(-noise, noise)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    return me

cart = new_obj("CART", None)
# 짐칸: 아래 좁고 위 넓은 통 (build_tunnel.py 의 광차 그대로)
bm = bmesh.new()
bot = [bm.verts.new(Vector((x * 0.76, y * 1.10, 0.60))) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
top = [bm.verts.new(Vector((x * 1.04, y * 1.44, 1.76))) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
bm.faces.new(bot[::-1])
for i in range(4): bm.faces.new((bot[i], bot[(i + 1) % 4], top[(i + 1) % 4], top[i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.solidify(bm, geom=bm.faces[:] + bm.edges[:] + bm.verts[:], thickness=0.06)
me = bpy.data.meshes.new("CART_Body"); bm.to_mesh(me); bm.free()
body = new_obj("CART_Body", me, M["MAT_RustyMetal"], parent=cart)
b = body.modifiers.new("Bevel", 'BEVEL'); b.width = 0.006; b.segments = 2
for z, sx, sy in ((1.72, 1.08, 1.48), (1.0, 0.90, 1.26)):     # 테두리 띠 2단
    box(f"CART_Rim_{int(z * 100)}a", (sx * 2 + 0.06, 0.08, 0.10), (0, -sy, z), M["MAT_RustyMetal"], parent=cart)
    box(f"CART_Rim_{int(z * 100)}b", (sx * 2 + 0.06, 0.08, 0.10), (0, sy, z), M["MAT_RustyMetal"], parent=cart)
    box(f"CART_Rim_{int(z * 100)}c", (0.08, sy * 2, 0.10), (-sx, 0, z), M["MAT_RustyMetal"], parent=cart)
    box(f"CART_Rim_{int(z * 100)}d", (0.08, sy * 2, 0.10), (sx, 0, z), M["MAT_RustyMetal"], parent=cart)
box("CART_Frame", (1.4, 2.2, 0.12), (0, 0, 0.56), M["MAT_RustyMetal"], parent=cart)
box("CART_Beam", (0.14, 2.6, 0.14), (0, 0, 0.42), M["MAT_RustyMetal"], parent=cart)
for j, y in enumerate((-0.8, 0.8)):                            # 축 2 + 바퀴 4 (궤간 0.6, 레일 위 z 0.30)
    cyl(f"CART_Axle_{j}", 0.025, GAUGE + 0.3, (0, y, 0.30), M["MAT_RustyMetal"], rot=(0, math.pi / 2, 0), segs=10, parent=cart)
    for k, x in enumerate((-GAUGE / 2, GAUGE / 2)):
        cyl(f"CART_Wheel_{j}{k}", 0.195, 0.075, (x, y, 0.30), M["MAT_RustyMetal"], rot=(0, math.pi / 2, 0), segs=24, parent=cart)
        cyl(f"CART_Flange_{j}{k}", 0.22, 0.02, (x + (0.048 if x < 0 else -0.048), y, 0.30), M["MAT_RustyMetal"], rot=(0, math.pi / 2, 0), segs=24, parent=cart)
for i, y in enumerate((-1.44, 1.44)):                          # 앞뒤 완충기(버퍼) + 고리
    cyl(f"CART_Buffer_{i}", 0.06, 0.16, (0, y + (0.08 if y < 0 else -0.08) * -1, 0.62), M["MAT_RustyMetal"], rot=(math.pi / 2, 0, 0), segs=10, parent=cart)
    box(f"CART_Hook_{i}", (0.14, 0.05, 0.14), (0, y + (0.16 if y < 0 else -0.16) * -1, 0.62), M["MAT_RustyMetal"], parent=cart, bevel=0.0)
for i in range(6):                                             # 바닥에 남은 광석 몇 덩이
    o = new_obj(f"CART_Ore_{i}", rock_mesh(f"CART_Ore_{i}"), M["MAT_Rock"],
                (random.uniform(-0.55, 0.55), random.uniform(-0.9, 0.9), 0.72), (random.uniform(0, 6),) * 3)
    o.scale = (random.uniform(0.12, 0.2),) * 3; o.parent = cart

dg = bpy.context.evaluated_depsgraph_get()
tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in coll.all_objects if o.type == 'MESH')
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("ok 저장 %s  오브젝트 %d  삼각형 %d" % (OUT_BLEND, len(coll.all_objects), tris))
