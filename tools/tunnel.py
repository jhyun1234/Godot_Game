# 갱도 조각을 코드로 만든다 (제안서 #18, 시안 단계).
#
#   bash tools/tunnel.sh                 시안 3장 렌더 -> build/tunnel_A.png _B _C + build/tunnel_sheet.png
#   bash tools/tunnel.sh --export        (다음 제안서에서) assets/generated/tunnel/ 로 내보내기
#
# 사용자 결정 2026-09-08: KayKit 던전·광석·도구 팩을 전부 빼고, 갱도·소품을 한 스타일로 새로 만든다.
# 방향 (가) 목재 동발 갱도 — 검은 바위 굴 + 갈색 나무 지지목(ㅅ자 아닌 문틀형: 기둥 둘 + 갓보) + 레일 + 케이블.
# 치수 근거: 문경 석탄박물관 동발 규격(높이 1.5m, 지름 7~12cm). 영월 탄광문화촌 실제 갱도.
#
# 손으로 빚지 않는다 (CLAUDE.md §15). 상자·원기둥·구 + 노이즈 요철뿐이다 — 형태가 전부 아래 상수에서 나온다.
# 색은 텍스처 없이 재질 색 하나씩. Godot 이 gltf 의 재질 색을 그대로 읽는다. "젖음"은 팔레트가 아니라
# 요철(광택이 잔점으로 깨진다)에서 온다 — #17 의 결론.
#
# 좌표계: Blender Z-up. 조각은 y 방향으로 길이 LEN, 원점 = 바닥 한가운데 z=0. 내보낼 때 Y-up 으로 돌린다.
import math
import os
import random
import sys

import bmesh
import bpy

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
EXPORT = "--export" in ARGS
OUT = "assets/generated/tunnel"

# --- 치수 (m) ---
LEN = 4.0            # 조각 길이. KayKit 격자와 같다 (§15)
WIDTH = 3.0          # 안쪽 폭
HEIGHT = 2.4         # 안쪽 높이. 지금 방(4m)보다 낮아 답답해진다 — 의도
CELL = 0.25          # 바위 격자 한 칸. 작을수록 요철이 잘고 폴리곤이 는다
PROP_GAP = 1.0       # 동발 간격
POST_R = 0.06        # 동발 기둥 반지름 (지름 12cm)
CAP_R = 0.07         # 갓보 반지름
POST_INSET = 0.10    # 기둥이 벽에서 떨어진 거리
LAG_W = 0.18         # 천장 배판 폭
LAG_T = 0.04         # 〃 두께
LAGS = 5             # 배판 장수 (천장 가로로)
RAIL_GAUGE = 0.61    # 협궤. 광차 폭의 근거
RAIL_W, RAIL_H = 0.05, 0.08
TIE_W, TIE_T, TIE_GAP = 1.0, 0.12, 0.6   # 침목
CABLE_R = 0.02
CABLE_Z = 1.9
CABLE_X = WIDTH * 0.5 - 0.12

# --- 시안 변수. A 요철 약함 / B 요철 강함 / C 요철 강함 + 젖은 광택 ---
VARIANTS = {
    "A": dict(bump=0.08, wet=False),
    "B": dict(bump=0.25, wet=False),
    "C": dict(bump=0.25, wet=True),
}
NOISE_SCALE = 0.40   # 요철 덩어리 크기 (m 단위 비슷)
SEED = 7             # 배판 빠짐·기둥 기울기·잔해 자리. 봇은 시드 고정 (§15)
POST_TILT_DEG = 2.5  # 기둥이 제각각 기운 최대 각. 0 이면 자로 잰 듯 서서 가짜 같다
LAG_MISSING = 0.3    # 배판이 빠진 비율
RUBBLE = 10          # 벽 밑 잔돌 수

# --- 색 (sRGB 0~1) ---
ROCK = (0.020, 0.024, 0.030)      # 청흑 석탄암
ROCK_ROUGH, ROCK_ROUGH_WET = 0.55, 0.18
WOOD = (0.13, 0.075, 0.035)         # 갈색 갱목. 검은 벽의 대비
WOOD_ROUGH = 0.8
IRON = (0.12, 0.13, 0.14)         # 레일·곡괭이 머리
CABLE = (0.02, 0.02, 0.02)
ORE = (0.16, 0.10, 0.06)          # 철광석 덩이. 갈색 녹빛


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        bpy.data.meshes.remove(m)


def solid(name, rgb, rough=0.6, metal=0.0, coat=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if coat > 0.0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.1
    return mat


def finish(ob, mat, flat=True):
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.use_smooth = not flat
    return ob


def box(name, size, loc, mat, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(ob, mat)


def cyl(name, r, h, loc, mat, rot=(0.0, 0.0, 0.0), verts=8):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    return finish(ob, mat)


def rock_shell(bump, mat):
    """안쪽을 보는 상자(벽 둘·천장·바닥). 격자로 나누고 노이즈로 밀어 바위 굴을 만든다."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= WIDTH
        v.co.y *= LEN
        v.co.z *= HEIGHT
        v.co.z += HEIGHT * 0.5
    # 앞뒤 뚜껑(y 면)은 뚫는다 — 조각이 이어진다
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if abs(f.normal.y) > 0.9], context="FACES")
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=int(max(WIDTH, LEN, HEIGHT) / CELL), use_grid_fill=True)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])       # 안쪽을 본다
    me = bpy.data.meshes.new("rock")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Rock", me)
    bpy.context.collection.objects.link(ob)
    tex = bpy.data.textures.new("rock_noise", "CLOUDS")
    tex.noise_scale = NOISE_SCALE
    tex.noise_depth = 2
    mod = ob.modifiers.new("Bump", "DISPLACE")
    mod.texture = tex
    mod.strength = bump
    mod.mid_level = 0.5
    mod.direction = "NORMAL"
    # 바닥은 걷는 곳이라 요철을 1/3 로. 정점 그룹 가중치로 조절
    vg = ob.vertex_groups.new(name="bump")
    for v in me.vertices:
        w = 0.35 if v.co.z < 0.05 else 1.0
        vg.add([v.index], w, "REPLACE")
    mod.vertex_group = "bump"
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="Bump")
    return finish(ob, mat)


def props(mat_wood):
    parts = []
    n = int(LEN / PROP_GAP)
    x = WIDTH * 0.5 - POST_INSET
    rng = random.Random(SEED)
    for i in range(n):
        y = -LEN * 0.5 + PROP_GAP * (i + 0.5)
        for sx in (-x, x):
            tilt = (math.radians(rng.uniform(-POST_TILT_DEG, POST_TILT_DEG)), 0.0, 0.0)
            parts.append(cyl("Post", POST_R, HEIGHT - CAP_R, (sx, y, (HEIGHT - CAP_R) * 0.5), mat_wood, rot=tilt))
        parts.append(cyl("Cap", CAP_R, WIDTH - POST_INSET * 2 + POST_R * 2, (0.0, y, HEIGHT - CAP_R),
                         mat_wood, rot=(0.0, math.radians(90.0), 0.0)))
    # 천장 배판: 갓보 위를 세로로 가로지르는 널
    for j in range(LAGS):
        lx = -WIDTH * 0.5 + POST_INSET + (WIDTH - POST_INSET * 2) * (j + 0.5) / LAGS
        for k in range(n):                      # 갓보 사이 한 칸씩. 몇 장은 빠져 있다
            if rng.random() < LAG_MISSING:
                continue
            ly = -LEN * 0.5 + PROP_GAP * (k + 0.5)
            parts.append(box("Lag", (LAG_W, PROP_GAP * 0.96, LAG_T), (lx, ly, HEIGHT + LAG_T * 0.5), mat_wood))
    return parts


def rubble(mat):
    """벽 밑에 구르는 잔돌. 바위와 같은 재질."""
    rng = random.Random(SEED + 1)
    parts = []
    for i in range(RUBBLE):
        side = rng.choice((-1.0, 1.0))
        r = rng.uniform(0.06, 0.16)
        loc = (side * (WIDTH * 0.5 - rng.uniform(0.15, 0.5)), rng.uniform(-LEN * 0.5, LEN * 0.5), r * 0.6)
        parts.append(ore(loc, r, mat))
    return parts


def rails(mat_iron, mat_wood):
    parts = []
    for sx in (-RAIL_GAUGE * 0.5, RAIL_GAUGE * 0.5):
        parts.append(box("Rail", (RAIL_W, LEN, RAIL_H), (sx, 0.0, TIE_T + RAIL_H * 0.5), mat_iron))
    n = int(LEN / TIE_GAP)
    for i in range(n):
        y = -LEN * 0.5 + TIE_GAP * (i + 0.5)
        parts.append(box("Tie", (TIE_W, TIE_T, TIE_T), (0.0, y, TIE_T * 0.5), mat_wood))
    return parts


def cable(mat):
    return [cyl("Cable", CABLE_R, LEN, (CABLE_X, 0.0, CABLE_Z), mat, rot=(math.radians(90.0), 0.0, 0.0), verts=6)]


def pickaxe(loc, mat_wood, mat_iron):
    """벽에 기대 선 곡괭이. 스타일 대조용 — 같은 상자·원기둥 문법."""
    ang = math.radians(15.0)
    handle = cyl("PickHandle", 0.018, 0.9, loc, mat_wood, rot=(ang, 0.0, 0.0), verts=6)
    top = (loc[0], loc[1] - math.sin(ang) * 0.45, loc[2] + math.cos(ang) * 0.45)
    head = box("PickHead", (0.40, 0.035, 0.05), top, mat_iron, rot=(ang, 0.0, 0.0))
    tip1 = box("PickTip", (0.12, 0.03, 0.035), (top[0] + 0.24, top[1], top[2]), mat_iron, rot=(ang, 0.0, 0.0))
    tip2 = box("PickTip", (0.12, 0.03, 0.035), (top[0] - 0.24, top[1], top[2]), mat_iron, rot=(ang, 0.0, 0.0))
    return [handle, head, tip1, tip2]


def ore(loc, r, mat):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=r, location=loc)
    ob = bpy.context.active_object
    ob.name = "Ore"
    tex = bpy.data.textures.new("ore_noise", "CLOUDS")
    tex.noise_scale = r * 2.0
    mod = ob.modifiers.new("Bump", "DISPLACE")
    mod.texture = tex
    mod.strength = r * 0.6
    bpy.ops.object.modifier_apply(modifier="Bump")
    return finish(ob, mat)


def build(variant):
    v = VARIANTS[variant]
    clear()
    mat_rock = solid("rock", ROCK, rough=ROCK_ROUGH_WET if v["wet"] else ROCK_ROUGH,
                     coat=0.6 if v["wet"] else 0.0)
    mat_wood = solid("wood", WOOD, rough=WOOD_ROUGH)
    mat_iron = solid("iron", IRON, rough=0.5, metal=0.8)
    mat_cable = solid("cable", CABLE, rough=0.7)
    mat_ore = solid("ore", ORE, rough=0.5, metal=0.3)
    parts = [rock_shell(v["bump"], mat_rock)]
    parts += props(mat_wood) + rails(mat_iron, mat_wood) + cable(mat_cable) + rubble(mat_rock)
    piece = parts
    # 소품 (시안 대조용. 조각에는 안 들어간다)
    extras = pickaxe((WIDTH * 0.5 - POST_INSET - 0.16, 0.4, 0.45), mat_wood, mat_iron)
    extras += [ore((-0.9, -0.6, 0.12), 0.12, mat_ore), ore((-1.1, -0.35, 0.09), 0.09, mat_ore),
               ore((-0.75, -0.25, 0.08), 0.08, mat_ore)]
    return piece, extras


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    return ob


def export(ob, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", use_selection=True,
                              export_yup=True, export_apply=True)
    print("ok export %s (폴리곤 %d)" % (path, len(ob.data.polygons)))


def render(variant, piece, extras):
    """헤드램프 하나로 갱도 안에서 본다. 조각 3개를 이어 깊이가 읽히게."""
    sc = bpy.context.scene
    for k in (1, 2):
        for src in piece_objects(piece):
            dup = src.copy()
            dup.data = src.data
            dup.location = (src.location.x, src.location.y + LEN * k, src.location.z)
            bpy.context.collection.objects.link(dup)
    cam_d = bpy.data.cameras.new("CAM")
    cam_d.lens = 22.0                                     # fov 80 근사
    cam = bpy.data.objects.new("CAM", cam_d)
    cam.location = (0.3, -1.6, 1.7)
    cam.rotation_euler = (math.radians(86.0), 0.0, math.radians(-6.0))
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    lamp_d = bpy.data.lights.new("LGT", "SPOT")
    lamp_d.energy = 450.0
    lamp_d.spot_size = math.radians(80.0)
    lamp_d.spot_blend = 0.6
    lamp_d.color = (1.0, 0.96, 0.88)
    lamp_d.shadow_soft_size = 0.05
    lamp = bpy.data.objects.new("LGT", lamp_d)
    lamp.location = (cam.location.x, cam.location.y, cam.location.z + 0.12)
    lamp.rotation_euler = cam.rotation_euler
    bpy.context.collection.objects.link(lamp)
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg is not None:
        bg.inputs[0].default_value = (0.004, 0.005, 0.006, 1.0)
    sc.world = world
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.render.resolution_x, sc.render.resolution_y = 960, 720
    sc.render.image_settings.file_format = "PNG"
    sc.view_settings.view_transform = "Filmic" if "Filmic" in [i.name for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else sc.view_settings.view_transform
    os.makedirs("build", exist_ok=True)
    path = os.path.abspath("build/tunnel_%s.png" % variant)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("ok render %s" % path)


def piece_objects(piece):
    return piece if isinstance(piece, list) else [piece]


for name in VARIANTS:
    piece, extras = build(name)
    if EXPORT:
        ob = join(piece, "tunnel_" + name)
        export(ob, os.path.join(OUT, "tunnel_%s.gltf" % name))
        piece = [ob]
    render(name, piece, extras)
    total = sum(len(o.data.polygons) for o in piece)
    print("ok tunnel %s 폴리곤 %d" % (name, total))
