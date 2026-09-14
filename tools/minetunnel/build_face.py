# -*- coding: utf-8 -*-
"""막장 끝막이 + 광석 덩이 + 자갈 (제안서 #23 수정판). tools/fracture.py 를 옮겨 고친 것 — 파쇄 9벌·박힌 광석은 #24 로 없어졌다(채굴 벽 없음).

    blender -b --python tools/minetunnel/build_face.py -- [render=<출력폴더>]

- 산출물: Documents/MineTunnel/Face.blend. 컬렉션 셋 — export.sh 가 나눠 뽑는다.
    ORE          ORE_Lump                광석 한 덩이 (ore.gltf). 광맥 포켓(OrePocket)도 같은 메시를 1.2배로 쓴다
    FACE_WALL    FACE_Wall               끝막이 7 × 4.4 × 1, 요철·천공 5·발밑 홈. 못 캔다 (mine_face.gltf)
    CHIPS        CHK_Chip_00..03         평타 자갈 4, 벽에서 잘라낸 것 0.15 (mine_chips.gltf)
- 좌표: Blender Z-up. 벽 원점 = 바닥 가운데. 앞면 = −Y(export_yup 으로 Godot +Z). 앞면 y −0.5, 뒷면 +0.5 → Godot 원점 −42 에 앞면 −41.5 (DevBot.BLOCK_FACE_Z).
- 자갈은 fracture.py 의 보로노이 셀 하나씩: 벽 가운데 0.6 구역에 점 4개 → 이웃과의 중간 평면으로 깎은 볼록 다면체 → 벽과 교집합 → 0.15 로 줄인다.
- 레퍼런스 공통점(2026-09-08 조사, 제안서 #23 표): 막장은 갱도 끝을 꽉 막은 바위 벽(7 전체) / 천공→발파(천공 자국 5) /
  발밑 언더컷(holing) 홈 / 광석은 검정·아금속 광택·깨진 평면.
- render= 를 주면 MineTunnel.blend 의 갱도 모듈을 append 해 모듈 끝(y 14)에 벽을 세우고 bright 2장(막장 3m · 광석 0.6m)을 쓴다.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Face.blend")
MATS = ["MAT_RockWall"]

# ---------------- 파라미터 (m) ----------------
W, H, T = 7.0, 4.4, 1.0          # 벽 폭·높이·두께. Tunnel.tscn 의 EndCap 충돌 상자(7 × 5.6 × 1)와 같은 폭·두께
GRID = 0.15                      # 앞면 요철 격자
DISP, DISP_FINE = 0.12, 0.04     # 요철 변위 (큰 결 ±0.12 + 잔결 ±0.04)
NOISE_SCALE, NOISE_FINE = 0.9, 3.5
UNDERCUT_H, UNDERCUT_D = 0.35, 0.30   # 발밑 홈 (holing)
HOLES = [(0.0, 2.0), (-0.6, 1.5), (0.6, 1.5), (-0.6, 2.5), (0.6, 2.5)]   # 천공 자국 (x, z). 가운데 V·마름모
HOLE_R, HOLE_DEPTH = 0.0225, 0.35
ORE_SIZE = (0.26, 0.20, 0.17)    # 광석 덩이 긴 변·중간·짧은 변. Ore.tscn 충돌 구 0.12 = 짧은 변의 반 근처
ORE_NOISE = 0.14
ORE_DISSOLVE_DEG = 16        # 이 각도 안의 이웃 면은 한 면으로
ORE_COLOR, ORE_ROUGH, ORE_METAL = (0.02, 0.022, 0.028, 1), 0.30, 0.55
SEED_BASE = 100
CHIP_COUNT, CHIP_SIZE, CHIP_REGION, CHIP_SEED = 4, 0.15, 0.6, 900
X0, X1, Z0, Z1 = -W / 2, W / 2, 0.0, H
CUT_T = 2.0                      # 자르는 틀 두께. 벽(1.0)보다 두껍게 — 앞뒤 면은 안 건드린다

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
random.seed(SEED_BASE)

# ---------------- 재질 ----------------
assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in MATS if n in src.materials]
M = bpy.data.materials
assert "MAT_RockWall" in M, "MineTunnel.blend 에 MAT_RockWall 이 없다"
ROCK = M["MAT_RockWall"]
ore_mat = M.new("MAT_Ore"); ore_mat.use_nodes = True
nt = ore_mat.node_tree; nt.nodes.clear(); out = nt.nodes.new("ShaderNodeOutputMaterial"); b = nt.nodes.new("ShaderNodeBsdfPrincipled")
b.inputs["Base Color"].default_value = ORE_COLOR; b.inputs["Roughness"].default_value = ORE_ROUGH; b.inputs["Metallic"].default_value = ORE_METAL
nt.links.new(b.outputs[0], out.inputs[0])
print("ok 재질 MAT_RockWall append + MAT_Ore")

# ---------------- 유틸 ----------------
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name); sc.collection.children.link(c)
    return c
def new_obj(name, data, c, mat=None, loc=(0,0,0), rot=(0,0,0)):
    o = bpy.data.objects.new(name, data); c.objects.link(o)
    if mat is not None and hasattr(data, "materials") and not data.materials: data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    return o
def select_only(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
def apply_bool(target, cutter, op):
    m = target.modifiers.new("cut", 'BOOLEAN'); m.operation = op; m.object = cutter; m.solver = 'EXACT'
    select_only(target); bpy.ops.object.modifier_apply(modifier="cut")

ore_c, wall_c, chips_c = coll("ORE"), coll("FACE_WALL"), coll("CHIPS")

# ---------------- 벽: 상자 → 0.15 격자 → 앞면 요철 + 언더컷 ----------------
print("[1/4] 벽")
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts: v.co.x *= W; v.co.y *= T; v.co.z = (v.co.z + 0.5) * H
def bisect_all(axis, val):
    no = Vector((1, 0, 0)) if axis == 'x' else Vector((0, 0, 1))
    co = no * val
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=co, plane_no=no)
nx, nz = int(round(W / GRID)), int(round(H / GRID))
for i in range(1, nx): bisect_all('x', X0 + W * i / nx)
for j in range(1, nz): bisect_all('z', H * j / nz)
front = [v for v in bm.verts if v.co.y < -T / 2 + 1e-4]
for v in front:
    p = Vector((v.co.x, v.co.z, 0.0))
    d = DISP * noise.noise(p * NOISE_SCALE) + DISP_FINE * noise.noise(p * NOISE_FINE + Vector((7.1, 3.3, 0)))
    v.co.y -= d                                       # −Y 가 바깥. 튀어나오면 y 가 더 작아진다
    if v.co.z < UNDERCUT_H - 1e-4: v.co.y += UNDERCUT_D    # 발밑 홈: 안으로 들어간다
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("FACE_Wall"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
wall = new_obj("FACE_Wall", me, wall_c, ROCK)
def front_y(x, z):
    """앞면 높이(요철 포함). 천공 자리를 잡는 데 쓴다."""
    best = min(wall.data.vertices, key=lambda v: (v.co.x - x) ** 2 + (v.co.z - z) ** 2 + (0 if v.co.y < 0 else 9))
    return best.co.y
# 천공 자국: 원기둥 5개 뺀다
for k, (x, z) in enumerate(HOLES):
    bmh = bmesh.new(); bmesh.ops.create_cone(bmh, cap_ends=True, segments=10, radius1=HOLE_R, radius2=HOLE_R, depth=HOLE_DEPTH + 0.3)
    hm = bpy.data.meshes.new(f"tmp_hole_{k}"); bmh.to_mesh(hm); bmh.free()
    y0 = front_y(x, z)
    h = new_obj(f"tmp_hole_{k}", hm, wall_c, loc=(x, y0 - 0.15 + (HOLE_DEPTH + 0.3) / 2, z), rot=(math.pi / 2, 0, 0))
    apply_bool(wall, h, 'DIFFERENCE')
    bpy.data.objects.remove(h, do_unlink=True); bpy.data.meshes.remove(hm)
print("ok 벽 %d면, 천공 %d, 언더컷 %.2f×%.2f" % (len(wall.data.polygons), len(HOLES), UNDERCUT_H, UNDERCUT_D))

# ---------------- 광석 덩이: 정이십면체 3단 + 노이즈 → 비슷한 면 합치기, 플랫 셰이딩 (깨진 면) ----------------
print("[2/4] 광석")
random.seed(SEED_BASE + 50)
bmo = bmesh.new(); bmesh.ops.create_icosphere(bmo, subdivisions=3, radius=1.0)
for v in bmo.verts: v.co += v.co.normalized() * random.uniform(-ORE_NOISE, ORE_NOISE)
# 비슷한 방향의 면을 합친다 — 크고 작은 깨진 면이 섞여야 광석이지, 고른 면은 다면체 장난감이다
bmesh.ops.dissolve_limit(bmo, angle_limit=math.radians(ORE_DISSOLVE_DEG), verts=bmo.verts[:], edges=bmo.edges[:])
bmesh.ops.triangulate(bmo, faces=[f for f in bmo.faces if len(f.verts) > 4])
for v in bmo.verts: v.co.x *= ORE_SIZE[0] / 2; v.co.y *= ORE_SIZE[1] / 2; v.co.z *= ORE_SIZE[2] / 2
ome = bpy.data.meshes.new("ORE_Lump"); bmo.to_mesh(ome); bmo.free()
for p in ome.polygons: p.use_smooth = False
lump = new_obj("ORE_Lump", ome, ore_c, ore_mat)
print("ok 광석 면 %d" % len(ome.polygons))

# ---------------- 자갈: 보로노이 셀 (fracture.py 그대로), 벽 가운데 0.6 구역을 4조각 → 0.15 ----------------
print("[3/4] 자갈")
def cell_cutter(site, others, name):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 20.0; v.co.y *= CUT_T; v.co.z *= 20.0; v.co += Vector((site.x, 0.0, site.z))
    for other in others:
        d = other - site
        if d.length < 1e-6: continue
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                     plane_co=(site + other) * 0.5, plane_no=d.normalized(), clear_outer=True)
        cut = [e for e in res['geom_cut'] if isinstance(e, bmesh.types.BMEdge)]
        if cut:
            bmesh.ops.edgenet_prepare(bm, edges=cut); bmesh.ops.contextual_create(bm, geom=cut)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return new_obj(name, me, chips_c)
def carve(src, cutter, name):
    select_only(src); bpy.ops.object.duplicate()
    piece = bpy.context.view_layer.objects.active
    for c in list(piece.users_collection): c.objects.unlink(piece)
    chips_c.objects.link(piece)
    apply_bool(piece, cutter, 'INTERSECT')
    if len(piece.data.polygons) == 0:
        bpy.data.objects.remove(piece, do_unlink=True); return None
    select_only(piece); bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
    piece.name = name; piece.data.name = name
    return piece
random.seed(CHIP_SEED)
center = Vector((0.0, 0.0, H / 2)); half = CHIP_REGION / 2
csites = [center + Vector((random.uniform(-half, half), 0.0, random.uniform(-half, half))) for _ in range(CHIP_COUNT)]
nc = 0
for k, s in enumerate(csites):
    cutter = cell_cutter(s, [o for o in csites if o is not s], f"tmp_chipcut_{k}")
    p = carve(wall, cutter, f"CHK_Chip_{nc:02d}")
    bpy.data.objects.remove(cutter, do_unlink=True)
    if p is None: continue
    longest = max(p.dimensions)
    if longest < 1e-4: bpy.data.objects.remove(p, do_unlink=True); continue
    p.scale = (CHIP_SIZE / longest,) * 3
    select_only(p); bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    p.location = (k * 0.5, 0.0, -1.0); nc += 1     # 부모 없이 나란히 — Godot 이 glTF 루트 바로 밑 MeshInstance3D 로 읽는다
print("ok 자갈 %d" % nc)

# ---------------- 저장 ----------------
print("[4/4] 저장")
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
dg = bpy.context.evaluated_depsgraph_get()
def tris(c): return sum(len(o.evaluated_get(dg).data.loop_triangles) for o in c.all_objects if o.type == 'MESH')
print("ok 저장 %s  벽 %d  광석 %d  자갈 합계 %d 삼각형" % (OUT_BLEND, tris(wall_c), len(ome.loop_triangles), tris(chips_c)))

# ---------------- 렌더 (bright, 검사용): 갱도 모듈 끝에 벽을 세워서 ----------------
if RENDER:
    print("[5/5] 렌더")
    with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
        dst.collections = [n for n in ("ENV", "TIMBER", "RAIL", "ROCKS", "PROPS") if n in src.collections]
    for c in dst.collections: sc.collection.children.link(c)
    for o in bpy.data.objects:
        if o.name.startswith(("PRP_Cart", "PRP_MineCart", "ENV_FogVolume")) or o.type == 'LIGHT': o.hide_render = True
    for o in chips_c.all_objects: o.hide_render = True          # 자갈은 안 찍는다
    fm = bpy.data.materials.get("MAT_Fog")
    if fm:
        for n in fm.node_tree.nodes:
            if n.type == 'VOLUME_SCATTER': n.inputs["Density"].default_value = 0.0
    root = new_obj("FACE_Root", None, sc.collection, loc=(0, 14.0 + T / 2, 0))   # 앞면이 모듈 끝 y 14
    for o in wall_c.objects:
        if o.parent is None: o.parent = root
    lump.location = (1.3, 12.0, ORE_SIZE[2] / 2 - 0.02); lump.rotation_euler = (0.3, 0.2, 0.9)   # 바닥에 떨어진 한 덩이
    lights = coll("LIGHTS")
    ld = bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 2500; ld.size = 4.0
    for i, y in enumerate((7.5, 11.0, 13.2)):
        new_obj(f"LGT_Inspect_{i}", ld, lights, loc=(0, y, 5.2))
    lf = bpy.data.lights.new("LGT_InspectFace", 'AREA'); lf.energy = 600; lf.size = 5.0          # 벽을 정면으로 — 위에서만 비추면 세로 벽이 검다
    new_obj("LGT_InspectFace", lf, lights, loc=(0, 10.5, 2.6), rot=(math.radians(90), 0, 0))
    cam_data = bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22
    cam = new_obj("CAM_Main", cam_data, lights); sc.camera = cam
    hl = bpy.data.lights.new("LGT_Headlamp", 'SPOT'); hl.energy = 150; hl.spot_size = math.radians(40); hl.spot_blend = 0.45; hl.color = (1.0, 0.96, 0.88)
    hlo = new_obj("LGT_Headlamp", hl, lights, loc=(0, 0.12, 0)); hlo.parent = cam
    w = bpy.data.worlds.new("World"); sc.world = w; w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND'); bg.inputs[0].default_value = (0.003, 0.004, 0.006, 1)
    engines = [i.identifier for i in sc.render.bl_rna.properties['engine'].enum_items]
    sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
    for attr, val in [("use_shadows", True), ("use_raytracing", True), ("taa_render_samples", 48)]:
        if hasattr(sc.eevee, attr):
            try: setattr(sc.eevee, attr, val)
            except Exception: pass
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = 0.6
    os.makedirs(RENDER, exist_ok=True)
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960; sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 90
    VIEWS = {"b_face": ((0.0, 11.0, 1.7), (88, 0, 0)),        # 막장 3m 앞, 눈높이 — 천공·홈·갱목 세트
             "c_ore": ((1.3, 11.45, 0.5), (52, 0, 0))}      # 바닥의 광석 0.6m 근접, 아래로 35°
    for k, (loc, rot) in VIEWS.items():
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot]
        if k == "c_ore":                                   # 광석은 게임처럼 헤드램프 하나로만 — 검은 아금속 광택은 한 방향 빛에서 읽힌다
            for o in lights.objects:
                if o.name.startswith("LGT_Inspect"): o.hide_render = True
            hl.energy = 25
        sc.render.filepath = os.path.join(RENDER, f"face_{k}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)
