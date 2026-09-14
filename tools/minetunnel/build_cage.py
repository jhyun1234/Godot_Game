# -*- coding: utf-8 -*-
"""리프트 케이지 조각 (제안서 #21). build_shaft.py 와 같은 문법·같은 재질.

    blender -b --python tools/minetunnel/build_cage.py -- [render=<출력폴더>] [timber=<id>|none]

- 재질 3종(MAT_RustyMetal·MAT_Timber·MAT_Cable)은 MineTunnel.blend 에서 append 한다.
- 산출물: Documents/MineTunnel/Cage.blend. 컬렉션 CAGE 하나 — export.sh 가 coll=CAGE 로 뽑는다.
- 좌표: Blender Z-up, 원점 = 상판 윗면 가운데(z 0). +Y 가 문(갱도) 쪽. #22: 상판 4.4, 기둥 3.0 (7m 격자·케이지 칸 5.0). export_yup 으로 Blender +Y → Godot −Z.
  Godot 의 Lift.tscn 충돌체(Deck 2.4 · 난간 3면 · Riders)는 그대로 — 상판 크기가 같다.
- 레퍼런스 공통점(2026-09-08 조사, 제안서 #21 표): 철제 틀 + 보닛 / 가이드 슈(양 옆 가운데, 가이드 x ±1.40~1.50 을 문다) /
  안전 문(철봉, 바깥 여닫이 2짝) / 로프 걸이(귀퉁이 봉 4 → 킹핀 → 로프 하나) / 바닥에 레일(광차를 싣는다).
- 문 두 짝(CAGE_GateL·CAGE_GateR)은 원점이 경첩(앞 기둥). 닫힌 상태(각 0)로 저장한다. 여는 건 Lift.gd 가 rotation.y 로.
- render= 를 주면 Shaft.blend 의 정거장을 append 해 케이지 칸(y 4.8, 180° 회전)에 세우고 bright 2장을 그 폴더에 쓴다.
  저장은 그 전에 하므로 Cage.blend 에는 케이지만 원점에 있다.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
SHAFT_BLEND = os.path.join(PROJ, "Shaft.blend")
OUT_BLEND = os.path.join(PROJ, "Cage.blend")
MATS = ["MAT_RustyMetal", "MAT_Timber", "MAT_Cable"]

# ---------------- 파라미터 (m) ----------------
DECK = 4.4              # 상판 한 변 (#22: 4명 + 광차. 2.4 → 4.4). Lift.tscn 의 Deck 충돌체와 같다 — 바꾸면 씬·봇 좌표가 같이 바뀐다
DECK_H = 0.12           # 널 두께
PLANKS = 8
PLANK_GAP = 0.03
ANGLE = 0.06            # 상판 테두리 앵글
POST = 0.07             # 기둥 각재
POST_H = 3.0            # 기둥 높이 (#22). 보닛 마루 3.3 < 정거장 열림 4.4
BAR = 0.03              # 측면 세로 봉
BAR_GAP = 0.15
BAR_H = POST_H - POST   # 완전히 가둔다 — 사용자 09-08 "점프로 넘을 수 있을 거 같다". 위 틀까지. 난간 충돌체도 같은 높이로(Lift.tscn)
BONNET = 4.5            # 보닛 한 변
BONNET_T = 0.03
BONNET_RISE = 0.3       # 가운데 마루 높이
SHOE = (0.20, 0.30, 0.30)   # 가이드 슈 (X 두께 · Y 폭 · Z 높이). x 1.20~1.40 = 가이드 안쪽면
SHOE_LIP = 0.08         # 가이드 옆을 무는 귀 (x 1.40~1.48 < 벽판 안쪽면 1.50)
GUIDE_W = 0.20          # 정거장 PRP_Guide 의 Y 폭
SHOE_Z = (-0.05, 2.10)  # 아래·위 슈 중심 높이
KINGPIN_Z = 4.0         # 로프 걸이 꼭짓점 (보닛 마루 3.3 + 0.7)
ROPE_R = 0.03
ROPE_LEN = 8.0          # 샤프트 10 안에서 끝이 안 보이게 (#9: 램프 사거리 안)
GATE_W = (DECK - 2 * 0.07) / 2 - 0.01   # 문 한 짝 폭 (기둥 사이의 반. 4.4 상판이면 2.12)
GATE_H = POST_H - 0.10  # 문도 위 틀까지 — 옆이 막혔는데 문만 낮으면 문으로 뛰어넘는다
GATE_Z0 = 0.05
RAIL_GAUGE = 0.6
HALF = DECK / 2
PX = HALF - POST / 2    # 기둥 중심 ±1.165

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

# ---------------- 재질 append (build_shaft.py 와 같음) ----------------
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

# ---------------- 유틸 (build_shaft.py 와 같음) ----------------
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
        b = o.modifiers.new("Bevel", 'BEVEL'); b.width = bevel; b.segments = 1
    return o
def cyl(name, r, h, loc, c, mat, rot=(0,0,0), segs=12):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    for p in me.polygons: p.use_smooth = True
    return o
def rod(name, a, b, r, c, mat, segs=8):
    """a 에서 b 로 가는 봉."""
    a, b = Vector(a), Vector(b); d = b - a
    o = cyl(name, r, d.length, (a + b) / 2, c, mat, segs=segs)
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return o
def join(objs, name, origin):
    """여러 조각을 한 오브젝트로 합치고 원점을 origin 으로 옮긴다 (문짝 — Lift.gd 가 경첩 기준으로 돌린다)."""
    with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
        bpy.ops.object.join()
    o = objs[0]; o.name = name; o.data.name = name
    o.data.transform(o.matrix_world)                  # join 은 active 의 로컬 좌표로 합친다 — 세계 좌표로 편 뒤 원점을 옮긴다
    o.data.transform(Matrix.Translation(-Vector(origin))); o.matrix_world = Matrix.Translation(Vector(origin))
    return o

cage = coll("CAGE")
RUST, TIMBER, CABLE = M["MAT_RustyMetal"], M["MAT_Timber"], M["MAT_Cable"]

# ---------------- 상판 ----------------
print("[1/5] 상판")
pw = (DECK - PLANK_GAP * (PLANKS - 1)) / PLANKS
for i in range(PLANKS):                                   # 널은 X 로 길게, Y 로 쌓는다 — 레일(Y)과 직각
    y = -HALF + pw / 2 + i * (pw + PLANK_GAP)
    box(f"CAGE_Deck_{i}", (DECK, pw, DECK_H), (0, y, -DECK_H / 2), cage, TIMBER, bevel=0.004)
for k, (sx, sy) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):   # 테두리 앵글 — 널 끝을 문다
    size = (ANGLE, DECK + 2 * ANGLE, ANGLE) if sx else (DECK + 2 * ANGLE, ANGLE, ANGLE)
    box(f"CAGE_Angle_{k}", size, (sx * (HALF + ANGLE / 2), sy * (HALF + ANGLE / 2), -ANGLE / 2 + 0.01), cage, RUST, bevel=0.003)
for k, y in enumerate((-0.9, 0.0, 0.9)):                  # 상판 밑 가로 보
    box(f"CAGE_Sill_{k}", (DECK + 2 * ANGLE, 0.08, 0.10), (0, y, -DECK_H - 0.05), cage, RUST, bevel=0.003)
for side, x in (("L", -RAIL_GAUGE / 2), ("R", RAIL_GAUGE / 2)):    # 상판 레일 — 광차를 싣는다 (충돌 없음)
    box(f"CAGE_Rail_{side}", (0.06, DECK, 0.06), (x, 0, 0.03), cage, RUST, bevel=0.003)

# ---------------- 틀: 기둥 4 + 가운데 기둥 2 + 위 틀 ----------------
print("[2/5] 틀/봉/보닛")
for sx in (-1, 1):
    for sy in (-1, 1):
        box(f"CAGE_Post_{sx > 0:d}{sy > 0:d}", (POST, POST, POST_H), (sx * PX, sy * PX, POST_H / 2), cage, RUST, bevel=0.004)
    box(f"CAGE_Stile_{sx > 0:d}", (POST, 0.10, POST_H + DECK_H + 0.1), (sx * PX, 0, (POST_H - DECK_H - 0.1) / 2), cage, RUST, bevel=0.004)   # 슈가 붙는 가운데 기둥
for k, (sx, sy) in enumerate(((0, 1), (0, -1), (1, 0), (-1, 0))):
    size = (POST, DECK, POST) if sx else (DECK, POST, POST)
    box(f"CAGE_Head_{k}", size, (sx * PX, sy * PX, POST_H - POST / 2), cage, RUST, bevel=0.004)
# 측면 세로 봉 3면 (문 쪽 +Y 는 비운다) + 위 가로 봉
span = DECK - 2 * POST
n_bar = int(span / BAR_GAP)
for side, (sx, sy) in {"S": (0, -1), "E": (1, 0), "W": (-1, 0)}.items():
    for i in range(1, n_bar):
        t = -span / 2 + span * i / n_bar
        loc = (t, sy * PX, BAR_H / 2) if sy else (sx * PX, t, BAR_H / 2)
        box(f"CAGE_Bar_{side}{i}", (BAR, BAR, BAR_H), loc, cage, RUST, bevel=0.0)
    size = (span, 0.04, 0.04) if sy else (0.04, span, 0.04)
    box(f"CAGE_Mid_{side}", size, (sx * PX, sy * PX, 1.1), cage, RUST, bevel=0.002)   # 허리 높이 가로 봉 (봉이 2.3 이라 중간을 잡아준다)
# 보닛: 두 장을 가운데 마루로 기울여 얹는다 + 밑 보 2
tilt = math.atan2(BONNET_RISE, BONNET / 2)
for k, sy in enumerate((-1, 1)):
    ln = math.hypot(BONNET / 2, BONNET_RISE)
    box(f"CAGE_Bonnet_{k}", (BONNET, ln, BONNET_T), (0, sy * BONNET / 4, POST_H + BONNET_RISE / 2 + BONNET_T), cage, RUST, rot=(-sy * tilt, 0, 0), bevel=0.003)
for k, x in enumerate((-0.7, 0.7)):
    box(f"CAGE_Ridge_{k}", (0.06, BONNET - 0.1, 0.06), (x, 0, POST_H + 0.03), cage, RUST, bevel=0.002)

# ---------------- 가이드 슈 4 (양 옆 가운데, 아래·위) ----------------
print("[3/5] 슈/로프 걸이")
for sx in (-1, 1):
    for k, z in enumerate(SHOE_Z):
        box(f"CAGE_Shoe_{sx > 0:d}{k}", SHOE, (sx * (HALF + SHOE[0] / 2), 0, z), cage, RUST, bevel=0.004)
        for j, sy in enumerate((-1, 1)):                  # 가이드 옆을 무는 귀
            box(f"CAGE_ShoeLip_{sx > 0:d}{k}{j}", (SHOE_LIP, 0.04, SHOE[2]), (sx * (HALF + SHOE[0] + SHOE_LIP / 2), sy * (GUIDE_W / 2 + 0.02), z), cage, RUST, bevel=0.003)
        for j, sy in enumerate((-0.1, 0.1)):              # 볼트
            cyl(f"CAGE_ShoeBolt_{sx > 0:d}{k}{j}", 0.014, 0.03, (sx * (HALF - 0.01), sy, z + 0.1), cage, RUST, rot=(0, math.pi / 2, 0), segs=8)
# 로프 걸이: 보닛 귀퉁이 4 → 킹핀 → 로프
top = POST_H + BONNET_RISE + BONNET_T
for k, (sx, sy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
    a = (sx * (HALF - 0.15), sy * (HALF - 0.15), POST_H + 0.02)
    rod(f"CAGE_Bridle_{k}", a, (0, 0, KINGPIN_Z - 0.1), 0.02, cage, RUST)
    cyl(f"CAGE_BridleEye_{k}", 0.05, 0.03, a, cage, RUST, segs=10)
cyl("CAGE_KingPin", 0.07, 0.3, (0, 0, KINGPIN_Z), cage, RUST, segs=12)
cyl("CAGE_Rope", ROPE_R, ROPE_LEN, (0, 0, KINGPIN_Z + 0.15 + ROPE_LEN / 2), cage, CABLE, segs=10)

# ---------------- 문 2짝 (원점 = 경첩, 닫힌 상태로 저장) ----------------
print("[4/5] 문")
GY = PX                                                   # 문은 앞 기둥 면(y +1.165)에
def gate(tag, hx, sgn):
    parts = []
    z_mid = GATE_Z0 + GATE_H / 2
    xc = hx + sgn * GATE_W / 2
    for k, z in enumerate((GATE_Z0 + 0.015, GATE_Z0 + GATE_H - 0.015)):
        parts.append(box(f"g{tag}_rail{k}", (GATE_W, 0.03, 0.03), (xc, GY, z), cage, RUST, bevel=0.0))
    for k, x in enumerate((hx + sgn * 0.015, hx + sgn * (GATE_W - 0.015))):
        parts.append(box(f"g{tag}_stile{k}", (0.03, 0.03, GATE_H), (x, GY, z_mid), cage, RUST, bevel=0.0))
    for i in range(1, 7):
        parts.append(box(f"g{tag}_bar{i}", (0.02, 0.02, GATE_H - 0.03), (hx + sgn * GATE_W * i / 7, GY, z_mid), cage, RUST, bevel=0.0))
    for k, f in enumerate((1 / 4, 1 / 2, 3 / 4)):
        parts.append(box(f"g{tag}_mid{k}", (GATE_W - 0.03, 0.02, 0.02), (xc, GY, GATE_Z0 + GATE_H * f), cage, RUST, bevel=0.0))
    for k, z in enumerate((GATE_Z0 + 0.15, GATE_Z0 + GATE_H - 0.15)):    # 경첩
        parts.append(cyl(f"g{tag}_hinge{k}", 0.025, 0.08, (hx + sgn * 0.03, GY + 0.03, z), cage, RUST, segs=8))
    parts.append(box(f"g{tag}_handle", (0.05, 0.05, 0.18), (hx + sgn * (GATE_W - 0.06), GY + 0.035, z_mid), cage, TIMBER, bevel=0.003))
    return join(parts, f"CAGE_Gate{tag}", (hx, GY, 0))
gate("L", -PX, +1)
gate("R", PX, -1)

# ---------------- 저장 ----------------
print("[5/5] 저장")
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
dg = bpy.context.evaluated_depsgraph_get()
tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in cage.objects if o.type == 'MESH')
print("ok 저장 %s  오브젝트 %d  삼각형 %d" % (OUT_BLEND, len(cage.objects), tris))

# ---------------- 렌더 (bright, 검사용): 정거장 안에 세워서 ----------------
if RENDER:
    assert os.path.exists(SHAFT_BLEND), SHAFT_BLEND
    with bpy.data.libraries.load(SHAFT_BLEND, link=False) as (src, dst):
        dst.collections = [n for n in ("ENV", "TIMBER", "RAIL", "ROCKS", "PROPS") if n in src.collections]
    for c in dst.collections:
        sc.collection.children.link(c)
    # 케이지를 케이지 칸(y 4.8)에, 문이 갱도(−Y) 를 보게 180° 돌려 세운다 — 저장 뒤라 Cage.blend 는 원점 그대로
    CAGE_Y = 5.0 + 5.0 / 2                                # build_shaft.py 의 L_DRIFT + HOLE/2 (케이지 칸 가운데)
    root = new_obj("CAGE_Root", None, sc.collection, loc=(0, CAGE_Y, 0), rot=(0, 0, math.pi))
    for o in cage.objects:
        if o.parent is None: o.parent = root
    # 문을 열어 둔 채 찍는다 (게임에서 정거장에 서 있을 때의 모습). L +90°, R −90° = 바깥쪽
    bpy.data.objects["CAGE_GateL"].rotation_euler.z = math.radians(90)
    bpy.data.objects["CAGE_GateR"].rotation_euler.z = math.radians(-90)
    lights = coll("LIGHTS")
    ld = bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 900; ld.size = 3.0
    for i, (y, z, e) in enumerate(((2.0, 5.0, 1500), (CAGE_Y, 8.5, 1500), (2.4, 3.2, 400))):
        d = ld.copy(); d.energy = e; new_obj(f"LGT_Inspect_{i}", d, lights, loc=(0, y, z))
    cam_data = bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22
    cam = new_obj("CAM_Main", cam_data, lights); sc.camera = cam
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
    # 사람 크기 캡슐 3개를 상판에 (판정용). 케이지는 180° 돌아 있으니 로컬 -Y 가 갱도 쪽
    dm = coll("DUMMY"); dmat = bpy.data.materials.new("MAT_Dummy"); dmat.diffuse_color = (0.55, 0.55, 0.6, 1)
    for i, (x, y) in enumerate([(-1.3, CAGE_Y - 1.2), (1.3, CAGE_Y - 1.2), (-1.3, CAGE_Y + 1.2)]):
        cyl(f"DUMMY_Body_{i}", 0.4, 1.0, (x, y, 0.9), dm, dmat, segs=20)
        for k, z in enumerate((0.4, 1.4)):
            bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=0.4)
            me = bpy.data.meshes.new(f"DUMMY_Cap_{i}{k}"); bm.to_mesh(me); bm.free()
            for pg in me.polygons: pg.use_smooth = True
            new_obj(f"DUMMY_Cap_{i}{k}", me, dm, dmat, (x, y, z))
    VIEWS = {"a_far": ((0.0, 0.5, 1.8), (88, 0, 0)),                     # 갱도에서 정거장 보기 (봇 11_lift_far 자리)
             "b_gate": ((0.6, CAGE_Y - DECK/2 - 1.6, 1.4), (80, 0, 8))}  # 열린 문 앞 1.6m — 문·슈·보닛·캡슐 3개
    for k, (loc, rot) in VIEWS.items():
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot]
        sc.render.filepath = os.path.join(RENDER, f"cage_{k}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)
