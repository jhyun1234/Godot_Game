# -*- coding: utf-8 -*-
"""곡괭이 뷰모델 조각 (제안서 #23). build_cage.py 와 같은 문법·같은 재질.

    blender -b --python tools/minetunnel/build_pick.py -- [render=<출력폴더>] [timber=<id>|none]

- 재질 2종(MAT_Timber·MAT_RustyMetal)은 MineTunnel.blend 에서 append 한다.
- 산출물: Documents/MineTunnel/Pick.blend. 컬렉션 PICK 하나 — export.sh 가 coll=PICK 으로 뽑는다.
- 좌표: Blender Z-up. 자루 = +Z(export_yup 으로 Godot +Y), 머리 긴 축 = X. 원점 = 손잡이(자루 아래 1/3).
  KayKit 곡괭이와 같은 축이라 Pickaxe.gd 의 PICK_YAW_DEG −90 · 스윙(X 회전) 을 안 건드린다. 양끝이 뾰족해 어느 끝이 앞이든 같다.
- 레퍼런스 공통점(2026-09-08 조사, 제안서 #23 표): 양끝 뾰족 뿔괭이(보령석탄박물관 유물·독일 Flügeleisen) / 머리 17½" ≈ 0.44 /
  짧은 자루 29~36" (갱내가 좁다) / 자루 3~4cm, 머리 쪽으로 굵어진다 / 납작 타원 눈을 감싸는 쇠 목 / 강철 머리, 녹.
- 머리는 커브(테이퍼)로 만든 뒤 메시로 바꿔 저장한다 — export_godot.py 의 커브 예외 목록을 안 늘린다.
- render= 를 주면 MineTunnel.blend 의 갱도 모듈을 append 해 눈높이 카메라에 Tuning.PICK_POS 자리로 곡괭이를 붙여 bright 1장을 쓴다.
  저장은 그 전이라 Pick.blend 에는 곡괭이만 원점에 있다.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Pick.blend")
MATS = ["MAT_Timber", "MAT_RustyMetal"]

# ---------------- 파라미터 (m) ----------------
HANDLE_LEN = 0.85        # 자루 (골동 29~36" 사이. 갱내가 좁아 짧다)
HANDLE_BUTT = -0.15      # 손잡이(원점) 아래로 이만큼이 자루 끝
HANDLE_R0, HANDLE_R1 = 0.015, 0.021   # 자루 반지름: 끝 0.030 → 머리 밑 0.042 (머리 쪽으로 굵어진다)
HANDLE_OVAL = 1.15       # 자루 단면 X:Y (손에 잡히는 타원)
HEAD_LEN = 0.46          # 머리 양끝 사이 (17½" = 0.44)
HEAD_R = 0.017           # 머리 가운데 반지름 (단면 0.034)
HEAD_DROOP = 0.07        # 양끝이 이만큼 처진다 (황새 부리)
COLLAR = (0.09, 0.075, 0.07)   # 눈을 감싸는 쇠 목 (eye 2½" × ¾" 이 안에 든다)
# Tuning.gd 와 같은 값 (렌더 배치용. 게임 값이 바뀌면 여기도)
PICK_POS = (0.32, -0.42, -0.60); PICK_SCALE = 0.55
PICK_TILT_DEG, PICK_YAW_DEG, PICK_ROLL_DEG = -12.0, -90.0, 10.0
HEAD_Z = HANDLE_BUTT + HANDLE_LEN                        # 머리 중심 높이 0.70

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

# ---------------- 재질 append (build_cage.py 와 같음) ----------------
assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in MATS if n in src.materials]
M = bpy.data.materials
missing = [n for n in MATS if n not in M]
assert not missing, "MineTunnel.blend 에 없는 재질: %s" % missing
print("ok 재질 append %d종" % len(MATS))
TIMBER_TEX = next((a[7:] for a in ARGS if a.startswith("timber=")), "dark_wooden_planks")
if TIMBER_TEX != "none":
    tdir = os.path.join(PROJ, "textures", TIMBER_TEX); swapped = 0
    for n in M["MAT_Timber"].node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            for k in ("Diffuse", "nor_gl", "Rough"):
                if f"_{k}." in n.image.name or f"_{k}." in n.image.filepath:
                    cand = [f for f in os.listdir(tdir) if f"_{k}." in f] if os.path.isdir(tdir) else []
                    if cand:
                        n.image = bpy.data.images.load(os.path.join(tdir, cand[0]), check_existing=True)
                        if k != "Diffuse": n.image.colorspace_settings.name = 'Non-Color'
                        swapped += 1
    print("ok 갱목 텍스처 %s (%d장)" % (TIMBER_TEX, swapped))
# 자루는 갱목보다 텍스처가 촘촘해야 한다 (자루 지름 4cm 에 1.4m 스케일이면 한 색). 박스매핑 스케일만 키운다.
for n in M["MAT_Timber"].node_tree.nodes:
    if n.type == 'MAPPING': n.inputs["Scale"].default_value = (6.0,) * 3

# ---------------- 유틸 (build_cage.py 와 같음) ----------------
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name); sc.collection.children.link(c)
    return c
def new_obj(name, data, c, mat=None, loc=(0,0,0), rot=(0,0,0)):
    o = bpy.data.objects.new(name, data); c.objects.link(o)
    if mat is not None and hasattr(data, "materials"): data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    return o
def box(name, size, loc, c, mat, rot=(0,0,0), bevel=0.006):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    if bevel:
        b = o.modifiers.new("Bevel", 'BEVEL'); b.width = bevel; b.segments = 2
    return o

pick = coll("PICK")
TIMBER, RUST = M["MAT_Timber"], M["MAT_RustyMetal"]

# ---------------- 자루: 고리 로프트 (모듈 소품 PRP_Pickaxe 와 같은 문법) ----------------
print("[1/3] 자루")
bm = bmesh.new(); rings = []
N = 14
for z, r in [(HANDLE_BUTT, HANDLE_R0 * 0.9), (HANDLE_BUTT + 0.02, HANDLE_R0), (0.0, HANDLE_R0 * 1.05),
             (HEAD_Z * 0.45, HANDLE_R0 * 1.1), (HEAD_Z - 0.12, HANDLE_R1), (HEAD_Z + 0.03, HANDLE_R1 * 0.95)]:
    rings.append([bm.verts.new(Vector((math.cos(a) * r * HANDLE_OVAL, math.sin(a) * r, z))) for a in [k * 2 * math.pi / N for k in range(N)]])
for a, b_ in zip(rings, rings[1:]):
    for k in range(N): bm.faces.new((a[k], a[(k + 1) % N], b_[(k + 1) % N], b_[k]))
bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("PICK_Handle"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
new_obj("PICK_Handle", me, pick, TIMBER)

# ---------------- 머리: 커브 + 테이퍼 → 메시. 양끝 뾰족, 끝이 처진다 ----------------
print("[2/3] 머리/목")
hc = bpy.data.curves.new("PICK_HeadCurve", 'CURVE'); hc.dimensions = '3D'
hc.bevel_depth = HEAD_R; hc.bevel_resolution = 3; hc.fill_mode = 'FULL'; hc.resolution_u = 16
s = hc.splines.new('BEZIER'); s.bezier_points.add(4)
hx = HEAD_LEN / 2
for bp, co in zip(s.bezier_points, [(-hx, 0, HEAD_Z - HEAD_DROOP), (-hx * 0.5, 0, HEAD_Z - HEAD_DROOP * 0.2), (0, 0, HEAD_Z),
                                    (hx * 0.5, 0, HEAD_Z - HEAD_DROOP * 0.2), (hx, 0, HEAD_Z - HEAD_DROOP)]):
    bp.co = co; bp.handle_left_type = bp.handle_right_type = 'AUTO'
tp = bpy.data.curves.new("PICK_Taper", 'CURVE'); ts = tp.splines.new('BEZIER'); ts.bezier_points.add(4)
for bp, co in zip(ts.bezier_points, [(0, 0.04, 0), (0.18, 0.75, 0), (0.5, 1.0, 0), (0.82, 0.75, 0), (1.0, 0.04, 0)]):
    bp.co = co; bp.handle_left_type = bp.handle_right_type = 'AUTO'
tpo = new_obj("PICK_Taper", tp, pick); hc.taper_object = tpo
hco = new_obj("PICK_HeadCurve", hc, pick, RUST)
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(hco.evaluated_get(dg), depsgraph=dg); me.name = "PICK_Head"
me.materials.append(RUST)
for p in me.polygons: p.use_smooth = True
new_obj("PICK_Head", me, pick)
bpy.data.objects.remove(hco, do_unlink=True); bpy.data.objects.remove(tpo, do_unlink=True)
bpy.data.curves.remove(hc); bpy.data.curves.remove(tp)
# 눈을 감싸는 쇠 목. 머리 중심을 감싼다
box("PICK_Collar", COLLAR, (0, 0, HEAD_Z - 0.005), pick, RUST, bevel=0.008)

# ---------------- 저장 ----------------
print("[3/3] 저장")
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
dg = bpy.context.evaluated_depsgraph_get()
tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in pick.objects if o.type == 'MESH')
print("ok 저장 %s  오브젝트 %d  삼각형 %d  (자루 %.2f 머리 %.2f)" % (OUT_BLEND, len(pick.objects), tris, HANDLE_LEN, HEAD_LEN))

# ---------------- 렌더 (bright, 검사용): 갱도 모듈 안, 눈높이 카메라에 붙여서 ----------------
if RENDER:
    with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
        dst.collections = [n for n in ("ENV", "TIMBER", "RAIL", "ROCKS", "PROPS") if n in src.collections]
    for c in dst.collections:
        sc.collection.children.link(c)
    for o in bpy.data.objects:                                    # 광차·안개·조명은 게임에 없다
        if o.name.startswith(("PRP_Cart", "PRP_MineCart", "ENV_FogVolume")) or o.type == 'LIGHT': o.hide_render = True
    fm = bpy.data.materials.get("MAT_Fog")
    if fm:
        for n in fm.node_tree.nodes:
            if n.type == 'VOLUME_SCATTER': n.inputs["Density"].default_value = 0.0
    lights = coll("LIGHTS")
    ld = bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 2500; ld.size = 4.0
    for i, y in enumerate((2.5, 7.5, 12.0)):
        new_obj(f"LGT_Inspect_{i}", ld, lights, loc=(0, y, 5.2))
    cam_data = bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22   # ≈ FOV 80 가로
    cam = new_obj("CAM_Main", cam_data, lights, loc=(0.0, 3.0, 1.7), rot=(math.radians(88), 0, 0)); sc.camera = cam
    # 헤드램프 하나 — 곡괭이 쇠에 하이라이트가 어떻게 맺히나
    hl = bpy.data.lights.new("LGT_Headlamp", 'SPOT'); hl.energy = 150; hl.spot_size = math.radians(40); hl.spot_blend = 0.45; hl.color = (1.0, 0.96, 0.88)
    hlo = new_obj("LGT_Headlamp", hl, lights, loc=(0, 0.12, 0)); hlo.parent = cam
    # 곡괭이를 카메라 로컬 PICK_POS 에. Godot: Pickaxe(rot X tilt) > Mesh(rot Y yaw, Z roll, scale). Blender 메시(Z-up) → Godot(Y-up) 은 X −90°.
    root = new_obj("PICK_Root", None, sc.collection); root.parent = cam
    root.matrix_parent_inverse.identity()
    root.matrix_basis = (Matrix.Translation(Vector(PICK_POS)) @ Matrix.Rotation(math.radians(PICK_TILT_DEG), 4, 'X')
                         @ Matrix.Rotation(math.radians(PICK_YAW_DEG), 4, 'Y') @ Matrix.Rotation(math.radians(PICK_ROLL_DEG), 4, 'Z')
                         @ Matrix.Diagonal((PICK_SCALE, PICK_SCALE, PICK_SCALE, 1)) @ Matrix.Rotation(math.radians(-90), 4, 'X'))
    for o in pick.objects:
        if o.parent is None: o.parent = root
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
    # 크기 판정용으로 두 배율을 찍는다: Tuning 값(0.55) + 비교판 0.75
    for tag, scl in (("a_hand", PICK_SCALE), ("a2_hand_s075", 0.75)):
        root.matrix_basis = (Matrix.Translation(Vector(PICK_POS)) @ Matrix.Rotation(math.radians(PICK_TILT_DEG), 4, 'X')
                             @ Matrix.Rotation(math.radians(PICK_YAW_DEG), 4, 'Y') @ Matrix.Rotation(math.radians(PICK_ROLL_DEG), 4, 'Z')
                             @ Matrix.Diagonal((scl, scl, scl, 1)) @ Matrix.Rotation(math.radians(-90), 4, 'X'))
        sc.render.filepath = os.path.join(RENDER, f"pick_{tag}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)
