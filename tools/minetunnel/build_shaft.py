# -*- coding: utf-8 -*-
"""수갱 정거장 + 샤프트 + 피트 조각 (제안서 #20). build_tunnel.py 와 같은 문법·같은 재질.

    blender -b --python tools/minetunnel/build_shaft.py -- [render=<출력폴더>]

- 재질 5종(MAT_RockWall·Floor·Timber·RustyMetal·Rock)은 새로 만들지 않고 MineTunnel.blend 에서 append 한다.
- 산출물: Documents/MineTunnel/Shaft.blend. 컬렉션 ENV / TIMBER / RAIL / ROCKS / PROPS / LIGHTS = 정거장,
  PIT = 피트(아래층 홀 밑바닥). export_godot.py 가 coll=/xcoll= 로 나눠 내보낸다.
- 좌표: Blender Z-up, 바닥 z=0, 길이 Y. 갱도부 y 0~3.3, 케이지 칸(3x3) y 3.3~6.3, 사다리 칸 y 6.3~7.5, z -0.1~8.0(윗층 바닥까지).
- 레퍼런스 공통점(2026-09-08 조사): 목재 틀(세트) 1.5m 간격 + 뒤판 / 케이지 칸 + 사다리 칸 / 틀에 붙는 가이드 /
  정거장에 게이트·케프·벨, 레일은 케이지까지 / 맨 아래 섬프. 출처는 docs/HANDOFF.md #20.
  피트는 원점(0,0,0)이 홀 가운데 — Godot 에서 아래층 홀 자리에 놓는다.
- render= 를 주면 bright 렌더 3장(a: 갱도에서 정거장 보기, b: 위에서 내려다보기, c: 올려다보기)을 그 폴더에 쓴다.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Shaft.blend")
MATS = ["MAT_RockWall", "MAT_Floor", "MAT_Timber", "MAT_RustyMetal", "MAT_Rock", "MAT_Cable"]

# ---------------- 파라미터 ----------------
W, H_WALL, H_TOP = 7.0, 4.4, 5.6       # 모듈과 같은 단면 (#22: 7m 격자)
L_DRIFT = 5.0                           # 갱도부 길이 (샤프트 앞까지). 케이지 칸 가운데 = 5.0 + 2.5 = 7.5 (Godot LIFT_CENTER)
HOLE = 6.2                              # 케이지 칸 **폭**(X) — 갱도 폭(7)에 세트 0.2·판 0.05 만 안쪽.
HOLE_Y = 5.0                            # 케이지 칸 **깊이**(Y) — 케이지 4.4 + 앞뒤 0.3. 바닥이 케이지 앞 0.3 까지 온다 (넓히면 앞에 구멍) 케이지(4.4)와의 틈은 번턴(bunton)에 단 가이드가 메운다
                                        # (#22 수정: 5.0 이면 세트 벽판이 갱도 벽에서 0.9 안쪽에 떠 보인다 — 사용자 "안전바가 벽에서 떨어져 있다")
CAGE_DECK = 4.4                         # build_cage.py DECK. 가이드·케프 자리는 케이지 기준
MANWAY = 1.4                            # 사다리 칸 (케이지 칸 뒤). 배관·케이블·사다리
Y0, Y1 = L_DRIFT, L_DRIFT + HOLE_Y      # 케이지 칸 y 5.0~10.0
Y2 = Y1 + MANWAY                        # 사다리 칸 끝 y 7.5
SHAFT_H = 10.0                          # 자기 바닥부터 윗층 바닥까지 (= Tuning.LIFT_DROP. #22: 8 → 10)
SET = 0.2                               # 샤프트 세트 각재 (8x8인치)
LAG = 0.05                              # 세트 뒤 판(lagging) 두께
ROCK = SET + LAG                        # 안치수에서 바위면까지
SET_Z = [-0.1 + 1.5*k for k in range(7)]   # 세트 높이 7단 (5ft 간격, 10m). -0.1 = 문지방이 바닥과 같은 높이
Z_HEAD = SET_Z[3]                       # 정거장 열림의 위 보 (4.4 = 갱도 벽 높이)
PIT_D = 2.0                             # 섬프 깊이
SET_SPACING = 1.75                      # 갱도부 갱목 간격 (모듈과 같게)
RAIL_GAUGE = 0.6
POST = 0.34                             # 갱도부 갱목 기둥 한 변 (모듈과 같게)
SEED = 11
GRID = 0.25
random.seed(SEED)
jit = lambda s: random.uniform(-s, s)
hw = W / 2 + 0.15
post_h = H_WALL + 0.4

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

# ---------------- 재질 append ----------------
assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in MATS if n in src.materials]
M = bpy.data.materials
missing = [n for n in MATS if n not in M]
assert not missing, "MineTunnel.blend 에 없는 재질: %s" % missing
print("ok 재질 append %d종" % len(MATS))
# 갱목 텍스처를 게임과 같은 것으로 (export.sh 기본 timber=dark_wooden_planks, #19 2차 판정). 렌더 판정이 게임 화면과 맞게.
# .blend 의 MAT_Timber 는 medieval_wood 인데 Shaft.blend 는 스크립트 산출물이라 여기서 바꿔도 원본은 그대로다.
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

# ---------------- 유틸 (build_tunnel.py 와 같음) ----------------
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name); sc.collection.children.link(c)
    return c
def new_obj(name, data, c, mat=None, loc=(0,0,0), rot=(0,0,0)):
    o = bpy.data.objects.get(name)
    if o: bpy.data.objects.remove(o, do_unlink=True)
    o = bpy.data.objects.new(name, data); c.objects.link(o)
    if mat is not None and hasattr(data, "materials"): data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    return o
def box(name, size, loc, c, mat, rot=(0,0,0), bevel=0.012, parent=None):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    if bevel:
        b = o.modifiers.new("Bevel", 'BEVEL'); b.width = bevel; b.segments = 2
    if parent: o.parent = parent
    return o
def cyl(name, r, h, loc, c, mat, rot=(0,0,0), segs=16, parent=None):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    for p in me.polygons: p.use_smooth = True
    if parent: o.parent = parent
    return o
def rock_mesh(name, subdiv=2, noise=0.25):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in bm.verts: v.co += v.co.normalized()*random.uniform(-noise, noise)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    return me
def add_disp(o, name, size, strength, sub=2):
    s = o.modifiers.new("Subdiv", 'SUBSURF'); s.subdivision_type = 'SIMPLE'; s.levels = sub; s.render_levels = sub
    for suf, sc_, st in (("", size, strength), ("_fine", size*0.25, strength*0.35)):
        t = bpy.data.textures.get(name+suf) or bpy.data.textures.new(name+suf, 'CLOUDS'); t.noise_scale = sc_; t.noise_depth = 5
        d = o.modifiers.new("Displace"+suf, 'DISPLACE'); d.texture = t; d.strength = st; d.mid_level = 0.5; d.texture_coords = 'GLOBAL'
    sm = o.modifiers.new("Smooth", 'SMOOTH'); sm.factor = 0.3
    for p in o.data.polygons: p.use_smooth = True
def solid(o, t=0.3):
    m = o.modifiers.new("Solidify", 'SOLIDIFY'); m.thickness = t; m.offset = -1.0   # 법선 뒤쪽(바깥)으로 두께
def steps(a, b, step=GRID):
    n = max(1, int(round((b - a) / step))); return [a + (b - a) * i / n for i in range(n + 1)]
def panel(name, us, vs, pos, want, c, mat, skip=None):
    """us x vs 격자 판. pos(u,v)->점, want(center)->법선이 향해야 할 방향, skip(center)->이 칸을 뺀다."""
    bm = bmesh.new()
    rows = [[bm.verts.new(pos(u, v)) for v in vs] for u in us]
    for i in range(len(us) - 1):
        for j in range(len(vs) - 1):
            quad = (rows[i][j], rows[i+1][j], rows[i+1][j+1], rows[i][j+1])
            ctr = sum((q.co for q in quad), Vector()) / 4
            if skip and skip(ctr): continue
            bm.faces.new(quad)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.dot(want(f.calc_center_median())) < 0: f.normal_flip()
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return new_obj(name, me, c, mat)
def arch_z(x):
    """단면 아치의 높이. |x| >= hw 면 수직벽 높이."""
    r = min(1.0, abs(x) / hw); return H_WALL + math.sqrt(max(0.0, 1.0 - r*r)) * (H_TOP - H_WALL)

# ---------------- 갱도부 암반 쉘 + 바닥 (y 0~4.5) ----------------
print("[1/5] 갱도부")
env = coll("ENV")
angles = sorted([math.pi*(1 - i/10) for i in range(1, 10)] + [math.acos(-HOLE/2/hw), math.acos(HOLE/2/hw)], reverse=True)
profile = [Vector((-hw, 0, -0.1)), Vector((-hw, 0, H_WALL))]
profile += [Vector((math.cos(a)*hw, 0, H_WALL + math.sin(a)*(H_TOP - H_WALL))) for a in angles]
profile += [Vector((hw, 0, H_WALL)), Vector((hw, 0, -0.1))]
bm = bmesh.new(); ny = int(L_DRIFT/GRID); rows = [[bm.verts.new(Vector((p.x, j*GRID, p.z))) for p in profile] for j in range(ny+1)]
for j in range(ny):
    for i in range(len(profile)-1): bm.faces.new((rows[j][i], rows[j][i+1], rows[j+1][i+1], rows[j+1][i]))
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-6], cuts=2, use_grid_fill=True)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
for f in bm.faces:
    c = f.calc_center_median()
    if f.normal.dot(Vector((-c.x, 0, 1.6 - c.z))) < 0: f.normal_flip()
me = bpy.data.meshes.new("ENV_RockShell"); bm.to_mesh(me); bm.free()
shell = new_obj("ENV_RockShell", me, env, M["MAT_RockWall"])
add_disp(shell, "Noise_Rock", 0.9, 0.4)
floor = panel("ENV_Floor", steps(-hw, hw, 2*hw/20), steps(0, L_DRIFT), lambda u, v: Vector((u, v, 0)),
              lambda c: Vector((0, 0, 1)), env, M["MAT_Floor"])
add_disp(floor, "Noise_Floor", 0.6, 0.12); solid(floor, 0.3)   # 밑면이 있어야 샤프트에서 올려다볼 때 뚫려 보이지 않는다
# 갱도 끝벽 (y=Y0-0.1 면, |x| 1.6~hw): 갱도는 여기서 끝나고 가운데 3m(케이지 칸)만 열린다. 샤프트 세트 기둥 바깥쪽
for side in (-1, 1):
    xs = steps(HOLE/2 + SET/2, hw, 0.22) if side > 0 else steps(-hw, -HOLE/2 - SET/2, 0.22)
    p = panel("ENV_End%s" % ("R" if side > 0 else "L"), xs, steps(-0.1, H_TOP), lambda u, v: Vector((u, Y0 - SET/2, v)),
              lambda c: Vector((0, -1, 0)), env, M["MAT_RockWall"], skip=lambda c: c.z > arch_z(c.x))
    add_disp(p, "Noise_Rock", 0.9, 0.4)

# ---------------- 샤프트 바위 벽 (세트·판 뒤, z -0.1 ~ 8.0). 판 틈으로 보인다 ----------------
print("[2/5] 샤프트")
zs = steps(-0.1, SHAFT_H)
RX = HOLE/2 + ROCK                      # 바위면 x = ±1.75
RY0, RY2 = Y0 - ROCK, Y2 + ROCK         # 바위면 y 앞 3.05 / 뒤 7.75
walls = {
    "ENV_ShaftW": (steps(RY0, RY2), lambda u, v: Vector((-RX, u, v)), Vector((1, 0, 0)), None),
    "ENV_ShaftE": (steps(RY0, RY2), lambda u, v: Vector((RX, u, v)), Vector((-1, 0, 0)), None),
    "ENV_ShaftBack": (steps(-RX, RX), lambda u, v: Vector((u, RY2, v)), Vector((0, -1, 0)), None),
    # 갱도 쪽 벽은 정거장 열림(바닥~위 보) 만큼 뚫려 있다. 위로는 아치보다 조금 낮게 잘라 바위 턱이 남게.
    "ENV_ShaftFront": (steps(-RX, RX), lambda u, v: Vector((u, RY0, v)), Vector((0, 1, 0)),
                       lambda c: 0.0 < c.z < max(Z_HEAD, arch_z(c.x) - 0.2) and abs(c.x) < HOLE/2 + SET),
}
for nm, (us, pos, n, skip) in walls.items():
    p = panel(nm, us, zs, pos, lambda c, n=n: n, env, M["MAT_RockWall"], skip=skip)
    add_disp(p, "Noise_Rock", 0.9, 0.4)   # 뒷면은 바위 속이라 두께 없음

# ---------------- 샤프트 세트 (틀) + 판 + 기둥 + 가이드 ----------------
# 레퍼런스 공통점: 목재 사각 수갱은 벽판·끝판·칸막이 보로 된 틀을 5ft(1.5m) 마다 쌓고, 틀 뒤에 판(lagging)을 대 바위를 막는다.
# 케이지 칸과 사다리 칸을 칸막이로 나누고, 가이드(4x8인치)는 틀에 붙인다. (911metallurgist 「Shaft Timbering」, de.wikipedia Schacht)
print("[3/5] 세트/판/가이드")
timber = coll("TIMBER")
XP = HOLE/2 + SET/2                     # 벽판·기둥 중심 x = ±1.6
YF, YB = Y0 - SET/2, Y2 + SET/2         # 앞 끝판 y 3.2 / 뒤 끝판 y 7.6
for k, z in enumerate(SET_Z):
    for side, x in (("L", -XP), ("R", XP)):
        box(f"PRP_WallPlate_{k}{side}", (SET, Y2 - Y0 + 2*SET, SET), (x, (YF + YB)/2, z + jit(0.01)), timber, M["MAT_Timber"], (jit(0.01), 0, jit(0.005)))
    box(f"PRP_EndPlateB_{k}", (HOLE + 2*SET, SET, SET), (0, YB, z), timber, M["MAT_Timber"], (0, jit(0.01), 0))
    box(f"PRP_Divider_{k}", (HOLE, SET, SET), (0, Y1, z), timber, M["MAT_Timber"], (0, jit(0.01), 0))
    if z <= -0.05 or z >= Z_HEAD - 0.01:          # 정거장 열림(바닥 위 ~ 위 보)에는 앞 끝판이 없다. 바닥 것은 문지방, 2.9 것은 위 보
        box(f"PRP_EndPlateF_{k}", (HOLE + 2*SET, SET, SET), (0, YF, z), timber, M["MAT_Timber"], (0, jit(0.01), 0))
# 기둥(studdle): 세트 사이 네 귀퉁이 + 칸막이 양끝. 정거장 열림 양옆 기둥이 문틀이 된다
for nm, (x, y) in {"FL": (-XP, YF), "FR": (XP, YF), "ML": (-XP, Y1), "MR": (XP, Y1), "BL": (-XP, YB), "BR": (XP, YB)}.items():
    box(f"PRP_Post_{nm}", (SET, SET, SHAFT_H + 0.2), (x, y, SHAFT_H/2 - 0.1), timber, M["MAT_Timber"], (jit(0.004), jit(0.004), 0))
# 판(lagging): 세트 뒤, 바위 앞. 가로 널 0.25 를 쌓고 20% 는 빠져 바위가 보인다. 정거장 열림 쪽(앞)은 위 보 위부터만
LAG_MISS = 0.4          # 널이 빠진 비율 (사용자 09-08 "더 낡게": 0.2 → 0.4)
LAG_BROKEN = 0.2        # 남은 널 중 부러져 반쪽만 남은 비율
LAG_SAG = 0.2           # 남은 널 중 한쪽이 처져 기운 비율
def lagging(tag, pos, size_fn, miss=LAG_MISS, z0=-0.1, z1=SHAFT_H, skip=None):
    """널을 z0~z1 에 0.25 간격으로 쌓는다. miss 만큼 빠지고, 남은 것 중 일부는 부러지거나(반쪽) 처진다(기욺).
    널의 긴 축은 size 의 큰 성분 — 부러진 널은 그 축으로 반만 남기고 한쪽으로 민다."""
    for i, z in enumerate(steps(z0 + 0.125, z1 - 0.125, 0.25)):
        if skip and skip(z): continue
        if random.random() < miss: continue
        size = list(size_fn()); loc = list(pos(z)); rot = [jit(0.01), jit(0.01), jit(0.008)]
        ax = 0 if size[0] > size[1] else 1            # 긴 축
        r = random.random()
        if r < LAG_BROKEN:
            keep = random.uniform(0.35, 0.6); full = size[ax]
            size[ax] = full * keep; loc[ax] += random.choice([-1, 1]) * (full - size[ax]) / 2
            rot[1 - ax] += jit(0.03)                   # 부러진 끝이 살짝 들림
        elif r < LAG_BROKEN + LAG_SAG:
            rot[1 - ax] += random.choice([-1, 1]) * random.uniform(0.05, 0.14)   # 한쪽이 처져 기운다
            loc[2] -= 0.03
        box(f"PRP_Lag_{tag}_{i}", tuple(size), tuple(loc), timber, M["MAT_Timber"], tuple(rot), bevel=0.006)
LX = HOLE/2 + SET + LAG/2               # 판 중심 x = ±1.725
lagging("W", lambda z: (-LX, (YF + YB)/2 + jit(0.02), z), lambda: (LAG, Y2 - Y0 + 2*SET - 0.05, 0.24))
lagging("E", lambda z: (LX, (YF + YB)/2 + jit(0.02), z), lambda: (LAG, Y2 - Y0 + 2*SET - 0.05, 0.24))
lagging("B", lambda z: (jit(0.02), Y2 + SET + LAG/2, z), lambda: (HOLE + 2*SET - 0.05, LAG, 0.24))
lagging("F", lambda z: (jit(0.02), Y0 - SET - LAG/2, z), lambda: (HOLE + 2*SET - 0.05, LAG, 0.24), skip=lambda z: -0.05 < z < Z_HEAD + 0.1)
# 칸막이 판: 케이지 칸과 사다리 칸 사이. 얇은 널, 30% 빠짐 — 틈으로 사다리·배관이 보인다
lagging("D", lambda z: (jit(0.02), Y1 + SET/2 + 0.02, z), lambda: (HOLE - 0.05, 0.03, 0.24), miss=LAG_MISS + 0.1)
# 가이드: 케이지 양옆. 벽판 안쪽면에 붙는 4x8인치 목재, 세트마다 볼트 2개
# 가이드는 케이지 기준 x ±(2.2 + 0.25). 벽판(XP)까지 세트마다 번턴(가로 목재)이 잇는다 — 실제 수갱의 bunton
GUIDE_X = CAGE_DECK/2 + 0.25
for side in ("W", "E"):
    sgn = -1 if side == "W" else 1
    gx = sgn * GUIDE_X
    box(f"PRP_Guide_{side}", (0.10, 0.20, SHAFT_H + 0.1), (gx, (Y0 + Y1)/2, SHAFT_H/2 - 0.05), timber, M["MAT_Timber"])
    bl = XP - SET/2 - (GUIDE_X + 0.05)              # 가이드 바깥면 → 벽판 안쪽면
    for k, z in enumerate(SET_Z):
        box(f"PRP_Bunton_{side}{k}", (bl + 0.02, SET, SET), (sgn * (GUIDE_X + 0.05 + bl/2), (Y0 + Y1)/2, z), timber, M["MAT_Timber"], (jit(0.01), 0, jit(0.005)))
        for j, dy in enumerate((-0.06, 0.06)):
            cyl(f"PRP_GuideBolt_{side}{k}{j}", 0.014, 0.03, (gx - sgn * 0.05, (Y0 + Y1)/2 + dy, z + 0.12), timber, M["MAT_RustyMetal"], rot=(0, math.pi/2, 0), segs=8)
# 정거장: 케프(케이지 받침 쇠) 2 + 바닥 철판 + 게이트 봉(열린 채, 갱도 쪽으로 젖혀짐) + 신호벨
for side, x in (("L", -CAGE_DECK/2 + 0.18), ("R", CAGE_DECK/2 - 0.18)):
    box(f"PRP_Kep_{side}", (0.14, 0.26, 0.08), (x, Y0 + 0.2, 0.04), timber, M["MAT_RustyMetal"], bevel=0.004)
box("PRP_LandingPlate", (HOLE + 0.4, 0.34, 0.02), (0, YF - 0.28, 0.01), timber, M["MAT_RustyMetal"], bevel=0.002)
# 게이트 봉: 경첩은 갱도 벽(기둥 안쪽면)에. 열린 채 벽을 따라 누워 있다 — 케이지 칸(5.0)이 갱도(7.0)보다 좁아 샤프트 기둥에 달면 방 가운데 떠 보인다 (#22 수정)
gate_y = YF - 0.3
GX = -(W/2 - POST - 0.05)                       # 기둥 안쪽면 바로 앞 x = -3.11
GATE_LEN = L_DRIFT - 0.6
cyl("PRP_GateHinge", 0.03, 0.5, (GX - 0.05, gate_y, 1.0), timber, M["MAT_RustyMetal"], segs=10)
cyl("PRP_GateBar", 0.035, GATE_LEN, (GX, gate_y - GATE_LEN/2, 1.0), timber, M["MAT_RustyMetal"], rot=(math.pi/2, 0, 0), segs=10)
box("PRP_GateHandle", (0.06, 0.06, 0.25), (GX, gate_y - GATE_LEN + 0.1, 0.9), timber, M["MAT_Timber"], bevel=0.004)
for k, y in enumerate((gate_y - 0.6, gate_y - GATE_LEN + 0.6)):   # 벽에 거는 고리 2개 — 봉이 벽에 붙어 있는 이유
    box(f"PRP_GateHook_{k}", (W/2 - 0.05 + GX, 0.05, 0.05), ((GX - W/2 + 0.05)/2, y, 1.0), timber, M["MAT_RustyMetal"], bevel=0.003)
box("PRP_Bell", (0.12, 0.10, 0.18), (XP + 0.02, YF - 0.2, 1.6), timber, M["MAT_RustyMetal"], bevel=0.004)
cyl("PRP_BellWire", 0.005, SHAFT_H - 1.7, (XP + 0.02, YF - 0.2, 1.7 + (SHAFT_H - 1.7)/2), timber, M["MAT_Cable"], segs=6)
# 사다리 칸: 사다리 2구간(어긋나게) + 중간 발판 + 배관 2 + 케이블
def ladder(tag, x, z0, z1, y):
    for side, dx in (("a", -0.2), ("b", 0.2)):
        box(f"PRP_Ladder_{tag}{side}", (0.05, 0.05, z1 - z0), (x + dx, y, (z0 + z1)/2), timber, M["MAT_Timber"], bevel=0.004)
    for i, z in enumerate(steps(z0 + 0.15, z1 - 0.15, 0.3)):
        cyl(f"PRP_Rung_{tag}{i}", 0.015, 0.4, (x, y, z), timber, M["MAT_Timber"], rot=(0, math.pi/2, 0), segs=8)
ladder("lo", -0.55, -0.1, SHAFT_H/2 + 0.05, Y2 - 0.12)
ladder("hi", 0.55, SHAFT_H/2 - 0.05, SHAFT_H, Y2 - 0.12)
for i, x in enumerate(steps(-HOLE/2 + 0.2, HOLE/2 - 0.2, 0.26)):     # 발판: 위 사다리 구멍 자리만 비운다
    if 0.3 < x < 0.9: continue
    box(f"PRP_Platform_{i}", (0.24, MANWAY - 0.08, 0.05), (x, (Y1 + Y2)/2, SHAFT_H/2), timber, M["MAT_Timber"], (jit(0.01), 0, 0), bevel=0.004)
props = coll("PROPS")
for i, (x, r) in enumerate(((-1.2, 0.045), (-1.0, 0.08))):
    cyl(f"PRP_ShaftPipe_{i}", r, SHAFT_H + 0.1, (x, Y1 + 0.35, SHAFT_H/2 - 0.05), props, M["MAT_RustyMetal"], segs=12)
    for k, z in enumerate(SET_Z): box(f"PRP_ShaftPipeBracket_{i}{k}", (0.06, 0.16, 0.05), (x, Y1 + 0.2, z + 0.35), props, M["MAT_RustyMetal"], bevel=0.003)
cu = bpy.data.curves.new("PRP_Cable", 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = 0.012; cu.bevel_resolution = 3
sp = cu.splines.new('NURBS')
pts = [(W/2-0.2+jit(0.02), i*L_DRIFT/4, post_h-0.1+(0 if i % 2 == 0 else -0.14), 1.0) for i in range(5)]   # 갱도 벽을 따라
pts += [(XP - 0.1, Y0 + 0.2, post_h - 0.1, 1.0), (1.3, Y1 + 0.5, post_h + 0.4, 1.0), (1.3, Y1 + 0.5, SHAFT_H + 0.2, 1.0)]  # 샤프트로 꺾여 올라간다
sp.points.add(len(pts)-1)
for p, co in zip(sp.points, pts): p.co = co
sp.use_endpoint_u = True; sp.order_u = 3
new_obj("PRP_Cable", cu, props, M["MAT_Cable"])
PIPE_X = W/2 - POST - 0.06                      # 갱목 기둥 안쪽면 바로 앞 (모듈과 같은 x — 이음새에서 이어진다)
cyl("PRP_Pipe", 0.045, L_DRIFT, (PIPE_X, L_DRIFT/2, 1.25), props, M["MAT_RustyMetal"], rot=(math.pi/2, 0, 0), segs=12)
for k, y in enumerate([SET_SPACING/2 + i*SET_SPACING for i in range(int(L_DRIFT/SET_SPACING))]):   # 기둥마다 받침
    box(f"PRP_PipeBracket_{k}", (W/2 - PIPE_X + 0.02, 0.06, 0.06), ((PIPE_X + W/2)/2, y, 1.25), props, M["MAT_RustyMetal"])

# ---------------- 갱도부 갱목 / 레일 / 돌 ----------------
print("[4/5] 갱목/레일/돌")
n_sets = int(L_DRIFT/SET_SPACING)
for k, y in enumerate([SET_SPACING/2 + i*SET_SPACING for i in range(n_sets)]):
    for side, x in (("L", -W/2), ("R", W/2)):
        box(f"PRP_DriftPost_{k}{side}", (POST, POST, post_h), (x+jit(0.03), y+jit(0.03), post_h/2-0.05), timber, M["MAT_Timber"], (jit(0.02), jit(0.015), jit(0.03)))
    box(f"PRP_Cap_{k}", (W+0.5, 0.36, 0.36), (jit(0.03), y, post_h+0.05+jit(0.02)), timber, M["MAT_Timber"], (jit(0.01), jit(0.02), jit(0.01)))
    for i in range(random.randint(3, 5)):
        box(f"PRP_CeilLag_{k}_{i}", (0.3, SET_SPACING, 0.05), (random.uniform(-W/2+0.3, W/2-0.3), y+SET_SPACING/2, post_h+0.22+jit(0.03)), timber, M["MAT_Timber"], (jit(0.05), jit(0.03), jit(0.15)))
rail = coll("RAIL")
L_RAIL = Y0 - SET - 0.02                # 레일은 문지방까지 간다 — 광차를 케이지에 싣는다 (차막이 없음)
for side, x in (("L", -RAIL_GAUGE/2), ("R", RAIL_GAUGE/2)):
    box(f"PRP_Rail_{side}", (0.06, L_RAIL, 0.10), (x, L_RAIL/2, 0.15), rail, M["MAT_RustyMetal"])
    box(f"PRP_RailFoot_{side}", (0.12, L_RAIL, 0.02), (x, L_RAIL/2, 0.11), rail, M["MAT_RustyMetal"])
for i in range(int(L_RAIL/0.6)):
    box(f"PRP_Sleeper_{i}", (1.2, 0.2, 0.10), (jit(0.02), 0.3+i*0.6+jit(0.03), 0.05), rail, M["MAT_Timber"], (0, jit(0.02), jit(0.03)))
rocks = coll("ROCKS")
for i in range(6):
    o = new_obj(f"PRP_Rock_{i}", rock_mesh(f"PRP_Rock_{i}"), rocks, M["MAT_Rock"])
    s = random.choice([random.uniform(0.05, 0.12)]*4 + [random.uniform(0.15, 0.32)])
    o.scale = (s*random.uniform(0.7, 1.3), s*random.uniform(0.7, 1.3), s*random.uniform(0.5, 0.9))
    o.location = (random.choice([-1, 1])*random.uniform(0.8, W/2-0.05), random.uniform(0.2, L_DRIFT-0.4), s*0.35)
    o.rotation_euler = (random.uniform(0, 6.28),)*3

# ---------------- 섬프 (맨 아래층 밑, 원점 = 케이지 칸 가운데). 세트 없이 맨 바위, 물은 나중 ----------------
print("[5/5] 섬프/카메라")
pit = coll("PIT")
px = RX; py0, py1 = -(HOLE_Y/2 + ROCK), HOLE_Y/2 + MANWAY + ROCK      # 케이지 칸 가운데 기준 y -1.75 ~ 2.95
pf = panel("PIT_Floor", steps(-px, px, 0.2), steps(py0, py1, 0.2), lambda u, v: Vector((u, v, -PIT_D)), lambda c: Vector((0, 0, 1)), pit, M["MAT_Floor"])
add_disp(pf, "Noise_Floor", 0.6, 0.12, sub=1)
pzs = steps(-PIT_D - 0.1, -0.1)
for nm, us, pos, n in (("PIT_WallW", steps(py0, py1), lambda u, v: Vector((-px, u, v)), Vector((1, 0, 0))),
                       ("PIT_WallE", steps(py0, py1), lambda u, v: Vector((px, u, v)), Vector((-1, 0, 0))),
                       ("PIT_WallS", steps(-px, px), lambda u, v: Vector((u, py0, v)), Vector((0, 1, 0))),
                       ("PIT_WallN", steps(-px, px), lambda u, v: Vector((u, py1, v)), Vector((0, -1, 0)))):
    p = panel(nm, us, pzs, pos, lambda c, n=n: n, pit, M["MAT_RockWall"]); add_disp(p, "Noise_Rock", 0.9, 0.4, sub=1)
for i in range(12):
    r = random.uniform(0.1, 0.3)
    o = new_obj(f"PIT_Rubble_{i}", rock_mesh(f"PIT_Rubble_{i}", 1), pit, M["MAT_Rock"], (random.uniform(-1.3, 1.3), random.uniform(-1.3, 2.5), -PIT_D + r*0.4 + random.uniform(0, 0.15)), (random.uniform(0, 6),)*3)
    o.scale = (r*random.uniform(0.8, 1.2), r*random.uniform(0.8, 1.2), r*random.uniform(0.5, 0.8))
box("PIT_BrokenPost", (0.22, 0.22, 1.6), (0.6, -0.4, -PIT_D + 0.35), pit, M["MAT_Timber"], (0.9, 0.2, 0.5))
box("PIT_BrokenLag", (0.05, 1.1, 0.24), (-0.9, 1.8, -PIT_D + 0.2), pit, M["MAT_Timber"], (0.3, 0.1, 0.8), bevel=0.006)

# ---------------- 카메라 / 검사등 / 월드 ----------------
lights = coll("LIGHTS")
cam_data = bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22
cam = new_obj("CAM_Main", cam_data, lights, loc=(0.3, 0.3, 1.6), rot=(math.radians(86), 0, math.radians(-4))); sc.camera = cam
ld = bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 900; ld.size = 3.0
for i, (y, z) in enumerate(((1.2, 3.7), ((Y0 + Y1)/2, 6.5), ((Y0 + Y1)/2, 1.8))):
    new_obj(f"LGT_Inspect_{i}", ld, lights, loc=(0, y, z))
w = bpy.data.worlds.new("World"); sc.world = w; w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND'); bg.inputs[0].default_value = (0.003, 0.004, 0.006, 1)
engines = [i.identifier for i in sc.render.bl_rna.properties['engine'].enum_items]
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
for attr, val in [("use_shadows", True), ("use_raytracing", True), ("taa_render_samples", 48)]:
    if hasattr(sc.eevee, attr):
        try: setattr(sc.eevee, attr, val)
        except Exception: pass
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = 0.6


bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
dg = bpy.context.evaluated_depsgraph_get()
tris = {c.name: sum(len(o.evaluated_get(dg).data.loop_triangles) for o in c.objects if o.type == 'MESH') for c in bpy.data.collections}
print("ok 저장 %s  오브젝트 %d  삼각형 %s" % (OUT_BLEND, len(bpy.data.objects), tris))

# ---------------- 렌더 (bright, 검사용) ----------------
if RENDER:
    os.makedirs(RENDER, exist_ok=True)
    for o in pit.objects: o.hide_render = True          # 피트는 원점에 있어 정거장 렌더에 끼면 안 된다
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960; sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 90
    VIEWS = {"a_hole": ((0.3, 0.3, 1.6), (86, 0, -4)),                # 갱도에서 정거장 열림 보기 (게이트·케프·세트·가이드)
             "b_down": ((0.0, (Y0 + Y1)/2, SHAFT_H - 3.5), (0, 0, 0)),          # 케이지 칸 위 4.5m 에서 내려다보기
             "c_up": ((0.0, (Y0 + Y1)/2 + 0.6, 0.6), (180, 0, 0))}    # 케이지 칸 바닥에서 올려다보기 (세트가 쌓인 것)
    for k, (loc, rot) in VIEWS.items():
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot]
        sc.render.filepath = os.path.join(RENDER, f"shaft_{k}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)
