# -*- coding: utf-8 -*-
"""조각 카탈로그 13종 (제안서 #26 A 단계). 갱도 9 + 레일 덧씌우기 4 를 한 규칙으로 뽑아 Documents/MineTunnel/Pieces.blend 에 저장한다.

    blender -b --python tools/minetunnel/build_piece.py -- [render=<출력폴더>]      (bash tools/minetunnel/render_piece.sh)

규칙 하나:
  - 칸 7×7, 원점 = 칸 가운데 바닥. Blender Z-up. 면 N=+Y E=+X S=-Y W=-X (export_yup 으로 Godot 에서 N = -Z).
  - 뚫린 면 A = 모듈과 같은 아치 단면 7×5.6(벽 4.4). D = 문 3.5×3.0(벽 2.4). 두 종류의 윤곽 정점은 모든 조각에서 같은 자리(0.35 격자)에 있다.
  - 천장 = 뚫린 면들의 아치를 이은 높이 지도(불리언 없음). 막힌 면 = 그 자리 천장 높이까지의 벽.
  - 바위 요철은 통로 **안쪽으로만**(공칭 면이 가장 깊은 곳) 0~0.3, 뚫린 면 테두리 0.7 m 안에서 0 으로 잦아든다.
    → 어느 조각의 어느 면을 붙여도 정점이 맞고, 조각의 어떤 정점도 자기 칸 밖으로 안 나간다.
  - 충돌 상자 = 이름 끝 -convcolonly (Godot 임포터가 StaticBody3D 로). 포켓 자리 = 빈 노드 SLOT_Pocket_<조각>_<n>.
  - 소품(상자·통·삽·석유등·잔해)은 없다. 갱목·배관·케이블·죽은 전구·잔돌만.
컬렉션: PC_straight PC_curve PC_t PC_cross PC_cap PC_neck PC_room_2 PC_room_1 PC_refuge / RAIL_straight RAIL_curve RAIL_turnout RAIL_end.
전부 원점에 겹쳐 있다 — export.sh 가 coll= 로 하나씩 뽑는다. 렌더는 저장 뒤 컬렉션 인스턴스로 배치한다.
"""
import bpy, bmesh, math, random, os, sys
from mathutils import Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
SRC_BLEND = os.path.join(PROJ, "MineTunnel.blend")
OUT_BLEND = os.path.join(PROJ, "Pieces.blend")
MATS = ["MAT_RockWall", "MAT_Floor", "MAT_Timber", "MAT_RustyMetal", "MAT_Rock", "MAT_Cable", "MAT_Bulb"]

# ---------------- 파라미터 (m) ----------------
CELL = 7.0; HW = CELL / 2                    # 칸, 통로 반폭
H_WALL, H_TOP = 4.4, 5.6                     # 아치 A: 수직 벽·정점 (모듈 #22 와 같다)
D_HW, D_WALL, D_TOP = 1.75, 2.4, 3.0         # 문 D: 반폭·벽·정점 (목 ↔ 방)
GRID = 0.35                                  # 표면 격자. 7/0.35 = 20 칸, 3.5/0.35 = 10 칸 — 면 윤곽 정점이 모든 조각에서 같은 자리
DISP, DISP_FINE, DISP_FLOOR = 0.24, 0.06, 0.06   # 요철: 큰 결 + 잔결 (합 0.3), 바닥
NOISE_SCALE, NOISE_FINE = 0.7, 3.0
FADE = 0.7                                   # 뚫린 면 테두리에서 요철이 0 이 되는 거리
FADE_Z = 0.5                                 # 바닥선(z 0)에서 벽 요철이 0 이 되는 높이 — 바닥과 벽이 따로여도 틈이 없다
SET_SPACING, POST_W, CAP_W = 1.75, 0.34, 0.36
POST_H = H_WALL + 0.4
RAIL_GAUGE = 0.6
CRIB_W, CRIB_LOG = 0.9, 0.2                  # 갈림 모서리 크립 (통나무 쌓기)
ROOM2_R, ROOM2_TOP, ROOM2_DISP = 1.4, 6.5, 0.8   # 모서리 반지름: 문(남서 칸 가운데 ±1.75)이 직선 벽 안에 들려면 ≤ 1.75   # 방 2×2: 모서리 반지름·천장·벽 요철
ROOM1_R, ROOM1_TOP = 1.2, 5.6
REF_W, REF_D, REF_H = 2.45, 2.6, 2.1         # 대피소 벽감 (0.35 격자에 맞춘 값: 폭 7칸·높이 6칸)
CAP_T, CAP_HOLE_R, CAP_HOLE_D = 0.45, 0.0225, 0.25   # 막장 벽 두께(칸 안에 든다)·천공
CAP_HOLES = [(0.0, 2.0), (-0.6, 1.5), (0.6, 1.5), (-0.6, 2.5), (0.6, 2.5)]
UNDERCUT_H, UNDERCUT_D = 0.35, 0.25
BUFFER_Y = 2.7                               # 종점: 레일 끝. 버퍼는 그 0.2 앞, 벽(3.5)에서 0.8
TRI_MAX = 12000
SEED = 7
random.seed(SEED)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0

# ---------------- 재질 append ----------------
assert os.path.exists(SRC_BLEND), SRC_BLEND
with bpy.data.libraries.load(SRC_BLEND, link=False) as (src, dst):
    dst.materials = [n for n in MATS if n in src.materials]
M = bpy.data.materials
for n in ("MAT_RockWall", "MAT_Floor", "MAT_Timber", "MAT_RustyMetal", "MAT_Rock"): assert n in M, n
if "MAT_Cable" not in M:
    m = M.new("MAT_Cable"); m.use_nodes = True; m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1)
if "MAT_Bulb" not in M:
    m = M.new("MAT_Bulb"); m.use_nodes = True; m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1.0, 0.72, 0.4, 1)
print("ok 재질 append %d" % len([n for n in MATS if n in M]))

# ---------------- 유틸 ----------------
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name); sc.collection.children.link(c)
    return c
def new_obj(name, data, c, mat=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    assert name not in bpy.data.objects, "이름 겹침: " + name   # -convcolonly 접미사와 SLOT 이름은 .001 이 붙으면 안 된다
    o = bpy.data.objects.new(name, data); c.objects.link(o)
    if mat is not None and hasattr(data, "materials") and not data.materials: data.materials.append(mat)
    o.location = loc; o.rotation_euler = rot
    return o
def box(name, size, loc, c, mat, rot=(0, 0, 0), bevel=0.012):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    if bevel:
        b = o.modifiers.new("Bevel", 'BEVEL'); b.width = bevel; b.segments = 1
    return o
def cyl(name, r, h, loc, c, mat, rot=(0, 0, 0), segs=12):
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=h)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = new_obj(name, me, c, mat, loc, rot)
    for p in me.polygons: p.use_smooth = True
    return o
def rock_mesh(name, noise_amt=0.25):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts: v.co += v.co.normalized() * random.uniform(-noise_amt, noise_amt)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    return me
def jit(s): return random.uniform(-s, s)
def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def arch(u, h=H_WALL, a=H_TOP):
    """단면 높이. u = 폭 방향 -1..1. 반타원 — 모듈 프로파일과 같다."""
    return h + (a - h) * math.sqrt(max(0.0, 1.0 - u * u))
def curve_to_mesh(o):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
    for m in o.data.materials: me.materials.append(m)
    c = o.users_collection[0]; nm = o.name; mw = o.matrix_world.copy()
    bpy.data.objects.remove(o, do_unlink=True)
    mo = bpy.data.objects.new(nm, me); c.objects.link(mo); mo.matrix_world = mw
    for p in me.polygons: p.use_smooth = True
    return mo

class Opening:
    """뚫린 면(또는 문)의 직사각형. 요철이 여기서 0.7 m 안에서 0 이 된다."""
    def __init__(self, center, ax_u, ax_v, hu, hv):
        self.c = Vector(center); self.u = Vector(ax_u).normalized(); self.v = Vector(ax_v).normalized(); self.hu = hu; self.hv = hv
    def dist(self, p):
        d = Vector(p) - self.c
        du = clamp(abs(d.dot(self.u)) - self.hu, 0.0, 1e9); dv = clamp(abs(d.dot(self.v)) - self.hv, 0.0, 1e9)
        n = self.u.cross(self.v); dn = abs(d.dot(n))
        return math.sqrt(du * du + dv * dv + dn * dn)
def face_opening(face, cx=0.0, cy=0.0, hw=HW, top=H_TOP):
    """칸 (cx,cy) 의 face 쪽 아치 면 A (문이면 hw·top 을 바꾼다). 높이 방향은 0..top 가운데 top/2."""
    if face == 'N': return Opening((cx, cy + HW, top / 2), (1, 0, 0), (0, 0, 1), hw, top / 2)
    if face == 'S': return Opening((cx, cy - HW, top / 2), (1, 0, 0), (0, 0, 1), hw, top / 2)
    if face == 'E': return Opening((cx + HW, cy, top / 2), (0, 1, 0), (0, 0, 1), hw, top / 2)
    return Opening((cx - HW, cy, top / 2), (0, 1, 0), (0, 0, 1), hw, top / 2)

class Shell:
    """조각의 바위 표면 하나 (바닥·벽·천장). 패치를 모아 한 메시로 붙이고, 안쪽을 향하게 하고, 요철을 준다."""
    def __init__(self, name, c, inside_fn, openings, disp=DISP, floor_disp=DISP_FLOOR, floor_edge=None):
        self.name, self.c, self.inside, self.openings = name, c, inside_fn, openings
        self.disp, self.floor_disp, self.floor_edge = disp, floor_disp, floor_edge
        self.bm = bmesh.new(); self.patches = []
    def patch(self, rows):
        """rows: 점 2차원 리스트 (같은 길이). 이웃끼리 사각형."""
        vs = [[self.bm.verts.new(Vector(p)) for p in row] for row in rows]
        for j in range(len(vs) - 1):
            for i in range(len(vs[j]) - 1):
                quad = (vs[j][i], vs[j][i + 1], vs[j + 1][i + 1], vs[j + 1][i])
                if len({v.co.to_tuple(4) for v in quad}) < 3: continue
                uniq = []
                for v in quad:
                    if all((v.co - u.co).length > 1e-4 for u in uniq): uniq.append(v)
                if len(uniq) >= 3:
                    area = sum(((uniq[i].co - uniq[0].co).cross(uniq[i + 1].co - uniq[0].co)).length for i in range(1, len(uniq) - 1)) / 2
                    if area < 1e-6: continue
                    try: self.bm.faces.new(uniq)
                    except ValueError: pass
    def finish(self, seed=0):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        for f in bm.faces:
            cen = f.calc_center_median()
            if f.normal.dot(self.inside(cen) - cen) < 0: f.normal_flip()
        bm.normal_update()
        # 요철: 안쪽으로만. 뚫린 면 테두리·바닥선에서 0
        off = Vector((seed * 13.7, seed * 5.3, seed * 2.1))
        for v in bm.verts:
            p = v.co
            is_floor = abs(v.normal.z) > 0.7 and p.z < 0.05
            fade = clamp(min([o.dist(p) for o in self.openings] + [9.0]) / FADE)
            if is_floor:
                if self.floor_edge: fade *= clamp(self.floor_edge(p) / FADE_Z)
                amp = self.floor_disp; n = 0.5 + 0.5 * noise.noise(p * 1.1 + off)
                v.co += v.normal * (amp * fade * n)
            else:
                fade *= clamp(p.z / FADE_Z)
                n1 = 0.5 + 0.5 * noise.noise(p * NOISE_SCALE + off); n2 = 0.5 + 0.5 * noise.noise(p * NOISE_FINE + off + Vector((7.1, 3.3, 0)))
                v.co += v.normal * fade * (self.disp * n1 + DISP_FINE * n2)
        me = bpy.data.meshes.new(self.name); bm.to_mesh(me); bm.free()
        me.materials.append(M["MAT_RockWall"]); me.materials.append(M["MAT_Floor"])
        for p in me.polygons:
            p.use_smooth = True
            if p.normal.z > 0.7 and p.center.z < 0.35: p.material_index = 1
        return new_obj(self.name, me, self.c)

def lin(a, b, n):
    return [a + (b - a) * i / n for i in range(n + 1)]
NU = int(round(CELL / GRID))          # 폭 방향 칸 20
NZ = int(round(H_WALL / GRID))        # 벽 높이 칸 13 (4.4/0.35 = 12.6 → 13, 마지막 칸이 조금 짧다)

# ---------------- 표면 생성기 ----------------
def junction_shell(name, c, opens, inside=None, extra_openings=(), skip_wall=None):
    """정사각 칸. 천장 = 뚫린 면들의 아치 최대값. 막힌 면 = 그 자리 천장까지의 벽. opens: 'NESW' 부분집합."""
    ns = 'N' in opens or 'S' in opens; ew = 'E' in opens or 'W' in opens
    def ceil(x, y):
        z = 0.0
        if ns: z = max(z, arch(x / HW))
        if ew: z = max(z, arch(y / HW))
        return z
    openings = [face_opening(f) for f in opens] + list(extra_openings)
    sh = Shell(name, c, inside or (lambda p: Vector((0, 0, 2.0))), openings,
               floor_edge=lambda p: min(HW - abs(p.x), HW - abs(p.y)))
    xs = lin(-HW, HW, NU); ys = lin(-HW, HW, NU)
    sh.patch([[(x, y, ceil(x, y)) for x in xs] for y in ys])            # 천장
    sh.patch([[(x, y, 0.0) for x in xs] for y in ys])                    # 바닥
    for f in 'NESW':
        if f in opens: continue
        if skip_wall and skip_wall(f): continue
        rows = []
        for k in range(NZ + 1):
            t = min(1.0, k / NZ)
            if f in 'NS':
                y = HW if f == 'N' else -HW
                rows.append([(x, y, t * ceil(x, y)) for x in xs])
            else:
                x = HW if f == 'E' else -HW
                rows.append([(x, y, t * ceil(x, y)) for y in ys])
        sh.patch(rows)
    return sh

def sweep_shell(name, c, path, n_s, inside, openings, open_ends=(True, True), floor_edge=None):
    """경로를 따라 단면을 쓸어 만든다. path(s) -> (center, normal(폭 +u 방향), w, h, a). 목(깔때기)·곡선이 쓴다."""
    sh = Shell(name, c, inside, openings, floor_edge=floor_edge)
    us = lin(-1.0, 1.0, NU); ss = lin(0.0, 1.0, n_s)
    ceil_rows, floor_rows, wl, wr = [], [], [], []
    for s in ss:
        cen, nrm, w, h, a = path(s)
        ceil_rows.append([cen + nrm * (u * w) + Vector((0, 0, arch(u, h, a))) for u in us])
        floor_rows.append([cen + nrm * (u * w) for u in us])
        wl.append([cen - nrm * w + Vector((0, 0, min(1.0, k / NZ) * h)) for k in range(NZ + 1)])
        wr.append([cen + nrm * w + Vector((0, 0, min(1.0, k / NZ) * h)) for k in range(NZ + 1)])
    sh.patch(ceil_rows); sh.patch(floor_rows); sh.patch(wl); sh.patch(wr)
    for end, s in ((0, 0.0), (1, 1.0)):
        if open_ends[end]: continue
        cen, nrm, w, h, a = path(s)
        sh.patch([[cen + nrm * (u * w) + Vector((0, 0, min(1.0, k / NZ) * arch(u, h, a))) for u in us] for k in range(NZ + 1)])
    return sh

# ---------------- 갱목·설비 ----------------
def timber_set(c, tag, y, half=HW, post_h=POST_H, cap_w=CAP_W, post_w=POST_W, sides=("L", "R"), axis='y'):
    """세트 하나: 기둥 2 + 갓보 + 라깅. axis='y' 면 y 자리에 x 방향 갓보."""
    def P(x, y_): return (x, y_, 0) if axis == 'y' else (y_, x, 0)
    for side, x in (("L", -half), ("R", half)):
        if side not in sides: continue
        px = x + (post_w / 2 if x < 0 else -post_w / 2)          # 기둥은 칸 안쪽에 선다 (벽에 붙어)
        loc = P(px + jit(0.02), y + jit(0.02)); box(f"TMB_{tag}_post_{side}", (post_w, post_w, post_h), (loc[0], loc[1], post_h / 2 - 0.05), c, M["MAT_Timber"],
                                                     (jit(0.015), jit(0.015), jit(0.03)))
    size = (2 * half - 0.02, cap_w, cap_w) if axis == 'y' else (cap_w, 2 * half - 0.02, cap_w)
    loc = P(0, y); box(f"TMB_{tag}_cap", size, (loc[0], loc[1], post_h + 0.05 + jit(0.02)), c, M["MAT_Timber"], (jit(0.01), jit(0.01), jit(0.01)))
    for i in range(2):
        lx = random.uniform(-half + 0.5, half - 0.5)
        size = (0.3, SET_SPACING * 0.9, 0.05) if axis == 'y' else (SET_SPACING * 0.9, 0.3, 0.05)
        loc = P(lx, y + SET_SPACING / 2 * random.choice([-1, 1]))
        box(f"TMB_{tag}_lag_{i}", size, (loc[0], loc[1], post_h + 0.24 + jit(0.03)), c, M["MAT_Timber"], (jit(0.04), jit(0.03), jit(0.1)))
def crib(c, tag, x, y, h):
    """통나무 엇갈려 쌓기 (cog). 각재 CRIB_LOG, 한 변 CRIB_W."""
    n = int(h / CRIB_LOG)
    for k in range(n):
        z = CRIB_LOG / 2 + k * CRIB_LOG
        for j in (-1, 1):
            if k % 2 == 0: box(f"TMB_{tag}_crib_{k}_{j+1}", (CRIB_W, CRIB_LOG, CRIB_LOG), (x + jit(0.01), y + j * (CRIB_W - CRIB_LOG) / 2, z), c, M["MAT_Timber"], (0, 0, jit(0.02)), bevel=0)
            else: box(f"TMB_{tag}_crib_{k}_{j+1}", (CRIB_LOG, CRIB_W, CRIB_LOG), (x + j * (CRIB_W - CRIB_LOG) / 2, y + jit(0.01), z), c, M["MAT_Timber"], (0, 0, jit(0.02)), bevel=0)
def pipe_cable_straight(c, tag, y0=-HW, y1=HW, x_side=1):
    px = x_side * (HW - POST_W - 0.06)
    cyl(f"PRP_{tag}_pipe", 0.045, y1 - y0, (px, (y0 + y1) / 2, 1.25), c, M["MAT_RustyMetal"], rot=(math.pi / 2, 0, 0))
    for i, y in enumerate(lin(y0 + 0.875, y1 - 0.875, 3)):
        box(f"PRP_{tag}_bracket_{i}", (POST_W + 0.08, 0.06, 0.06), (x_side * (HW - (POST_W + 0.08) / 2), y, 1.25), c, M["MAT_RustyMetal"], bevel=0)
    cu = bpy.data.curves.new(f"PRP_{tag}_cable", 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = 0.012; cu.bevel_resolution = 2
    sp = cu.splines.new('NURBS'); pts = [(x_side * (HW - 0.2) + jit(0.02), y0 + i * (y1 - y0) / 5, POST_H - 0.1 - (0 if i % 2 == 0 else 0.14), 1.0) for i in range(6)]
    sp.points.add(len(pts) - 1)
    for p, co in zip(sp.points, pts): p.co = co
    sp.use_endpoint_u = True; sp.order_u = 3
    curve_to_mesh(new_obj(f"PRP_{tag}_cable", cu, c, M["MAT_Cable"]))
def dead_bulb(c, tag, loc):
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.04)
    me = bpy.data.meshes.new(f"PRP_{tag}_bulb"); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    new_obj(f"PRP_{tag}_bulb", me, c, M["MAT_Bulb"], loc)
    cyl(f"PRP_{tag}_socket", 0.02, 0.07, (loc[0], loc[1], loc[2] + 0.07), c, M["MAT_Cable"], segs=8)
    cyl(f"PRP_{tag}_wire", 0.006, 0.28, (loc[0], loc[1], loc[2] + 0.24), c, M["MAT_Cable"], segs=5)
def rocks(c, tag, n, region):
    """잔돌. region(rng) -> (x, y)."""
    for i in range(n):
        s = random.uniform(0.05, 0.14)
        x, y = region()
        o = new_obj(f"PRP_{tag}_rock_{i}", rock_mesh(f"PRP_{tag}_rock_{i}"), c, M["MAT_Rock"], (x, y, s * 0.35), (random.uniform(0, 6.28),) * 3)
        o.scale = (s * random.uniform(0.7, 1.3), s * random.uniform(0.7, 1.3), s * random.uniform(0.5, 0.9))
def col_box(c, tag, size, loc, rot=(0, 0, 0)):
    o = box(f"COL_{tag}-convcolonly", size, loc, c, None, rot, bevel=0)
    o.hide_render = True; o.display_type = 'WIRE'
    return o
def col_prism(c, tag, poly2d, h):
    """볼록 다각형 기둥 (곡선 바닥·방 바닥). 안쪽 점들의 볼록 껍질을 Godot 이 잡는다."""
    bm = bmesh.new()
    bot = [bm.verts.new(Vector((x, y, -0.5))) for x, y in poly2d]; top = [bm.verts.new(Vector((x, y, h))) for x, y in poly2d]
    bm.faces.new(bot[::-1]); bm.faces.new(top)
    n = len(poly2d)
    for i in range(n): bm.faces.new((bot[i], bot[(i + 1) % n], top[(i + 1) % n], top[i]))
    me = bpy.data.meshes.new(f"COL_{tag}-convcolonly"); bm.to_mesh(me); bm.free()
    o = new_obj(f"COL_{tag}-convcolonly", me, c); o.hide_render = True; o.display_type = 'WIRE'
    return o
def slot(c, tag, i, loc):
    new_obj(f"SLOT_Pocket_{tag}_{i}", None, c, loc=loc)
def wall_cols(c, tag, faces):
    """막힌 면의 벽 상자 (두께 0.3, 칸 안쪽)."""
    for f in faces:
        if f == 'N': col_box(c, f"{tag}_wall_{f}", (CELL, 0.3, H_TOP), (0, HW - 0.15, H_TOP / 2))
        if f == 'S': col_box(c, f"{tag}_wall_{f}", (CELL, 0.3, H_TOP), (0, -HW + 0.15, H_TOP / 2))
        if f == 'E': col_box(c, f"{tag}_wall_{f}", (0.3, CELL, H_TOP), (HW - 0.15, 0, H_TOP / 2))
        if f == 'W': col_box(c, f"{tag}_wall_{f}", (0.3, CELL, H_TOP), (-HW + 0.15, 0, H_TOP / 2))
SET_YS = [-2.625, -0.875, 0.875, 2.625]     # 세트 4. 이음새 너머 다음 조각의 -2.625 까지 1.75 — 간격이 조각을 넘어 이어진다
TRI = {}
def count(c):
    dg = bpy.context.evaluated_depsgraph_get()
    return sum(len(o.evaluated_get(dg).data.loop_triangles) for o in c.all_objects if o.type == 'MESH' and not o.hide_render)

# ================= 조각 =================
print("[1/4] 갱도 조각 9")

# --- 직선 (N·S) ---
c = coll("PC_straight"); t = "straight"
junction_shell(f"SHL_{t}", c, "NS").finish(1)
for k, y in enumerate(SET_YS): timber_set(c, f"{t}_{k}", y)
pipe_cable_straight(c, t); dead_bulb(c, t, (HW - 0.35, 1.2, POST_H - 0.35))
rocks(c, t, 12, lambda: (random.choice([-1, 1]) * random.uniform(0.8, HW - 0.3), random.uniform(-3.2, 3.2)))
col_box(c, f"{t}_floor", (CELL, CELL, 0.5), (0, 0, -0.25)); wall_cols(c, t, "EW")
for i, (x, y) in enumerate(((-HW + 0.08, -1.75), (HW - 0.08, -1.75), (-HW + 0.08, 1.75), (HW - 0.08, 1.75))): slot(c, t, i, (x, y, 1.9))
TRI[t] = count(c)

# --- 곡선 (S·W). 안쪽 모서리 C = (-3.5,-3.5). 가운데 반지름 3.5, 바깥 벽 7 ---
c = coll("PC_curve"); t = "curve"
CC = Vector((-HW, -HW, 0))
def curve_path(s):
    th = s * math.pi / 2                                  # 0 = S 면 가운데 (0,-3.5), 90° = W 면 가운데 (-3.5, 0)
    r = Vector((math.cos(th), math.sin(th), 0))
    return CC + r * HW, r, HW, H_WALL, H_TOP                 # 폭 +u = 바깥(r 커지는 쪽)
def curve_inside(p):
    th = math.atan2(p.y - CC.y, p.x - CC.x); r = Vector((math.cos(th), math.sin(th), 0))
    return CC + r * HW + Vector((0, 0, 2.0))
sh = sweep_shell(f"SHL_{t}", c, curve_path, 24, curve_inside, [face_opening('S'), face_opening('W')],
                 floor_edge=lambda p: CELL - (Vector((p.x, p.y, 0)) - CC).length)
sh.finish(2)
# 갱목: 바깥 호 기둥 3 + 안쪽 모서리 기둥 1, 갓보 부채
ip = CC + Vector((POST_W / 2, POST_W / 2, 0))
box(f"TMB_{t}_post_in", (POST_W, POST_W, POST_H), (ip.x, ip.y, POST_H / 2 - 0.05), c, M["MAT_Timber"])
for k, deg in enumerate((15, 45, 75)):
    th = math.radians(deg); r = Vector((math.cos(th), math.sin(th), 0))
    op = CC + r * (CELL - POST_W / 2 - 0.01)
    box(f"TMB_{t}_post_{k}", (POST_W, POST_W, POST_H), (op.x, op.y, POST_H / 2 - 0.05), c, M["MAT_Timber"], (0, 0, th))
    mid = (op + ip) / 2; L = (op - ip).length + 0.3
    box(f"TMB_{t}_cap_{k}", (L, CAP_W, CAP_W), (mid.x, mid.y, POST_H + 0.05 + jit(0.02)), c, M["MAT_Timber"], (0, 0, th))
    for i in range(2):
        rr = random.uniform(2.0, 6.2); th2 = th + math.radians(random.uniform(-12, 12)); q = CC + Vector((math.cos(th2), math.sin(th2), 0)) * rr
        box(f"TMB_{t}_lag_{k}_{i}", (0.3, 1.5, 0.05), (q.x, q.y, POST_H + 0.24 + jit(0.03)), c, M["MAT_Timber"], (jit(0.04), jit(0.03), th2 + jit(0.1)))
# 배관·케이블: 바깥 벽을 따라 호
for nm, rad, z, dep, mat in ((f"PRP_{t}_pipe", CELL - POST_W - 0.06, 1.25, 0.045, "MAT_RustyMetal"), (f"PRP_{t}_cable", CELL - 0.2, POST_H - 0.12, 0.012, "MAT_Cable")):
    cu = bpy.data.curves.new(nm, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = dep; cu.bevel_resolution = 2
    sp = cu.splines.new('NURBS'); pts = [(CC.x + math.cos(th) * rad, CC.y + math.sin(th) * rad, z - (0.0 if nm.endswith("pipe") or i % 2 == 0 else 0.12), 1.0)
                                          for i, th in enumerate(lin(0.0, math.pi / 2, 8))]
    sp.points.add(len(pts) - 1)
    for p, co in zip(sp.points, pts): p.co = co
    sp.use_endpoint_u = True; sp.order_u = 3
    curve_to_mesh(new_obj(nm, cu, c, M[mat]))
for i, deg in enumerate((22, 68)):
    th = math.radians(deg); q = CC + Vector((math.cos(th), math.sin(th), 0)) * (CELL - (POST_W + 0.08) / 2)
    box(f"PRP_{t}_bracket_{i}", (POST_W + 0.08, 0.06, 0.06), (q.x, q.y, 1.25), c, M["MAT_RustyMetal"], (0, 0, th), bevel=0)
th = math.radians(40); q = CC + Vector((math.cos(th), math.sin(th), 0)) * (CELL - 0.35); dead_bulb(c, t, (q.x, q.y, POST_H - 0.35))
def curve_rock_pos():
    th = random.uniform(0.1, math.pi / 2 - 0.1); rr = random.choice([random.uniform(0.6, 2.0), random.uniform(5.2, 6.6)])
    return CC.x + math.cos(th) * rr, CC.y + math.sin(th) * rr
rocks(c, t, 12, curve_rock_pos)
arc = [(CC.x + math.cos(th) * CELL, CC.y + math.sin(th) * CELL) for th in lin(0.0, math.pi / 2, 8)]
col_prism(c, f"{t}_floor", [(CC.x, CC.y)] + arc, 0.0)
for k in range(4):                                      # 바깥 호 벽: 현 4개
    th0, th1 = k * math.pi / 8, (k + 1) * math.pi / 8; thm = (th0 + th1) / 2
    chord = 2 * CELL * math.sin((th1 - th0) / 2); q = CC + Vector((math.cos(thm), math.sin(thm), 0)) * (CELL - 0.15)
    col_box(c, f"{t}_arc_{k}", (0.3, chord + 0.3, H_TOP), (q.x, q.y, H_TOP / 2), (0, 0, thm))
for i, deg in enumerate((30, 60)):
    th = math.radians(deg); q = CC + Vector((math.cos(th), math.sin(th), 0)) * (CELL - 0.08); slot(c, t, i, (q.x, q.y, 1.9))
TRI[t] = count(c)

# --- T (N·S·E, W 막힘) / + ---
for t, opens in (("t", "NSE"), ("cross", "NSEW")):
    c = coll(f"PC_{t}")
    junction_shell(f"SHL_{t}", c, opens).finish(3 if t == "t" else 4)
    corners = [(HW - CRIB_W / 2 - 0.02, HW - CRIB_W / 2 - 0.02), (HW - CRIB_W / 2 - 0.02, -HW + CRIB_W / 2 + 0.02)]
    if t == "cross": corners += [(-HW + CRIB_W / 2 + 0.02, HW - CRIB_W / 2 - 0.02), (-HW + CRIB_W / 2 + 0.02, -HW + CRIB_W / 2 + 0.02)]
    for k, (x, y) in enumerate(corners): crib(c, f"{t}_{k}", x, y, H_WALL)
    # 갓보 틀: 크립 위를 지나는 굵은 보. T 는 서쪽 기둥 4 + 동서 보 2 + 남북 보 1, + 는 네모 틀
    if t == "t":
        for k, y in enumerate(SET_YS): box(f"TMB_{t}_post_{k}", (POST_W, POST_W, POST_H), (-HW + POST_W / 2, y, POST_H / 2 - 0.05), c, M["MAT_Timber"])
        for k, y in enumerate((-2.625, 2.625)): box(f"TMB_{t}_capEW_{k}", (CELL - 0.02, CAP_W + 0.1, CAP_W + 0.1), (0, y * 1.1, H_WALL + 0.25), c, M["MAT_Timber"])
        box(f"TMB_{t}_capNS", (CAP_W + 0.1, CELL - 0.02, CAP_W + 0.1), (HW - CRIB_W / 2, 0, H_WALL + 0.25 + CAP_W + 0.1), c, M["MAT_Timber"])
    else:
        for k, y in enumerate((-2.9, 2.9)): box(f"TMB_{t}_capEW_{k}", (CELL - 0.02, CAP_W + 0.1, CAP_W + 0.1), (0, y, H_WALL + 0.25), c, M["MAT_Timber"])
        for k, x in enumerate((-2.9, 2.9)): box(f"TMB_{t}_capNS_{k}", (CAP_W + 0.1, CELL - 0.02, CAP_W + 0.1), (x, 0, H_WALL + 0.25 + CAP_W + 0.1), c, M["MAT_Timber"])
    for i in range(4):
        box(f"TMB_{t}_lag_{i}", (0.3, 2.0, 0.05), (random.uniform(-2.2, 2.2), random.uniform(-2.2, 2.2), H_WALL + 0.25 + 2 * (CAP_W + 0.1) + 0.05), c, M["MAT_Timber"], (0, 0, random.uniform(0, 3.1)))
    rocks(c, t, 10, lambda: (random.uniform(-2.5, 2.5), random.uniform(-2.5, 2.5)))
    col_box(c, f"{t}_floor", (CELL, CELL, 0.5), (0, 0, -0.25))
    if t == "t":
        wall_cols(c, t, "W")
        for i, y in enumerate((-1.75, 1.75)): slot(c, t, i, (-HW + 0.08, y, 1.9))
    for k, (x, y) in enumerate(corners): col_box(c, f"{t}_crib_{k}", (CRIB_W, CRIB_W, H_WALL), (x, y, H_WALL / 2))
    TRI[t] = count(c)

# --- 끝막이 (S 만 뚫림). N 면 = 막장 벽(천공·발밑 홈) ---
c = coll("PC_cap"); t = "cap"
junction_shell(f"SHL_{t}", c, "S").finish(5)
for k, y in enumerate(SET_YS): timber_set(c, f"{t}_{k}", y)
# 막장 벽: 칸 안에 드는 얇은 판 (앞면 y 3.05, 뒷면 3.5). 앞면 0.25 격자 요철 + 언더컷 + 천공 5 (불리언)
bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts: v.co.x *= CELL; v.co.y = HW - CAP_T / 2 + v.co.y * CAP_T; v.co.z = (v.co.z + 0.5) * H_TOP
def bisect(axis, val):
    no = Vector((1, 0, 0)) if axis == 'x' else Vector((0, 0, 1))
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=no * val, plane_no=no)
for i in range(1, 28): bisect('x', -HW + CELL * i / 28)
for j in range(1, 22): bisect('z', H_TOP * j / 22)
for v in bm.verts:
    if v.co.y < HW - CAP_T + 1e-4:
        p = Vector((v.co.x, v.co.z, 0.0)); d = 0.12 * noise.noise(p * 0.9) + 0.04 * noise.noise(p * 3.5 + Vector((7.1, 3.3, 0)))
        v.co.y -= d
        if v.co.z < UNDERCUT_H - 1e-4: v.co.y += UNDERCUT_D
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new(f"FACE_{t}_wall"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
wall = new_obj(f"FACE_{t}_wall", me, c, M["MAT_RockWall"])
def sel(o):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
for k, (x, z) in enumerate(CAP_HOLES):
    bmh = bmesh.new(); bmesh.ops.create_cone(bmh, cap_ends=True, segments=8, radius1=CAP_HOLE_R, radius2=CAP_HOLE_R, depth=CAP_HOLE_D + 0.3)
    hm = bpy.data.meshes.new(f"tmp_hole_{k}"); bmh.to_mesh(hm); bmh.free()
    h = new_obj(f"tmp_hole_{k}", hm, c, loc=(x, HW - CAP_T - 0.15 + (CAP_HOLE_D + 0.3) / 2, z), rot=(math.pi / 2, 0, 0))
    mod = wall.modifiers.new("cut", 'BOOLEAN'); mod.operation = 'DIFFERENCE'; mod.object = h; mod.solver = 'EXACT'
    sel(wall); bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(h, do_unlink=True); bpy.data.meshes.remove(hm)
rocks(c, t, 12, lambda: (random.uniform(-3.0, 3.0), random.uniform(0.5, 2.9)))
col_box(c, f"{t}_floor", (CELL, CELL, 0.5), (0, 0, -0.25)); wall_cols(c, t, "EW")
col_box(c, f"{t}_face", (CELL, CAP_T + 0.1, H_TOP), (0, HW - (CAP_T + 0.1) / 2, H_TOP / 2))
for i, x in enumerate((-HW + 0.08, HW - 0.08)): slot(c, t, i, (x, -1.75, 1.9))
TRI[t] = count(c)

# --- 목: S 아치 7×5.6 → N 문 3.5×3.0 깔때기 ---
c = coll("PC_neck"); t = "neck"
def neck_path(s):
    y = -HW + s * CELL
    return Vector((0, y, 0)), Vector((1, 0, 0)), HW + (D_HW - HW) * s, H_WALL + (D_WALL - H_WALL) * s, H_TOP + (D_TOP - H_TOP) * s
door_open = Opening((0, HW, D_TOP / 2), (1, 0, 0), (0, 0, 1), D_HW, D_TOP / 2)
sh = sweep_shell(f"SHL_{t}", c, neck_path, NU, lambda p: Vector((0, p.y, 1.5)), [face_opening('S'), door_open],
                 floor_edge=lambda p: neck_path((p.y + HW) / CELL)[2] - abs(p.x))
sh.finish(6)
for k, y in enumerate(SET_YS):
    s = (y + HW) / CELL; _, _, w, h, a = neck_path(s)
    timber_set(c, f"{t}_{k}", y, half=w, post_h=h + 0.3, cap_w=CAP_W * (0.6 + 0.4 * (1 - s)), post_w=POST_W * (0.7 + 0.3 * (1 - s)))
rocks(c, t, 8, lambda: (random.uniform(-1.4, 1.4), random.uniform(-3.0, 2.5)))
col_box(c, f"{t}_floor", (CELL, CELL, 0.5), (0, 0, -0.25))
for side in (-1, 1):                                    # 경사진 옆벽: 상자를 기울여
    ang = math.atan2(HW - D_HW, CELL); L = CELL / math.cos(ang)
    xm = side * (HW + D_HW) / 2
    col_box(c, f"{t}_wall_{'E' if side > 0 else 'W'}", (0.3, L + 0.3, H_TOP), (xm + side * 0.15 * math.cos(ang), 0, H_TOP / 2), (0, 0, side * ang))
col_box(c, f"{t}_lintel", (CELL, 0.3, H_TOP - D_TOP + 0.2), (0, HW - 0.15, D_TOP + (H_TOP - D_TOP + 0.2) / 2))
TRI[t] = count(c)

# --- 방 2×2 · 1×1: 모서리 둥근 뭉툭한 평면, 돔 천장, 문 D (남쪽 벽) ---
def room(t, half, corner_r, top, disp, cribs, door_cx, seed):
    c = coll(f"PC_{t}")
    a = half - corner_r
    assert door_cx - D_HW >= -a + 0.3, "문이 모서리에 걸린다"
    def sdf(p):
        q = Vector((max(abs(p.x) - a, 0.0), max(abs(p.y) - a, 0.0))); return q.length - corner_r
    def inside(p): return Vector((0, 0, 2.5))
    door = Opening((door_cx, -half, D_TOP / 2), (1, 0, 0), (0, 0, 1), D_HW, D_TOP / 2)
    sh = Shell(f"SHL_{t}", c, inside, [door], disp=disp, floor_edge=lambda p: -sdf(p))
    # 둘레 점 (x, y, zmin): 남쪽 벽(문 포함) → SE 모서리 → 동 → NE → 북 → NW → 서 → SW → 처음
    per = []
    x0d, x1d = door_cx - D_HW, door_cx + D_HW
    for x in lin(-a, x0d, max(1, int(round((x0d + a) / GRID)))): per.append((x, -half, 0.0))
    for x in lin(x0d, x1d, NU):                                # 문 21 점 (0.175) — 목의 N 면 정점과 자리가 같다
        per.append((x, -half, arch((x - door_cx) / D_HW, D_WALL, D_TOP)))
    for x in lin(x1d, a, max(1, int(round((a - x1d) / GRID)))): per.append((x, -half, 0.0))
    def corner(cx, cy, th0, th1):
        for th in lin(th0, th1, 8)[1:]: per.append((cx + math.cos(th) * corner_r, cy + math.sin(th) * corner_r, 0.0))
    corner(a, -a, -math.pi / 2, 0.0)
    for y in lin(-a, a, int(round(2 * a / GRID)))[1:]: per.append((half, y, 0.0))
    corner(a, a, 0.0, math.pi / 2)
    for x in lin(a, -a, int(round(2 * a / GRID)))[1:]: per.append((x, half, 0.0))
    corner(-a, a, math.pi / 2, math.pi)
    for y in lin(a, -a, int(round(2 * a / GRID)))[1:]: per.append((-half, y, 0.0))
    corner(-a, -a, math.pi, 1.5 * math.pi)
    per.append(per[0])
    NR = 6
    def dome(k): return H_WALL + (top - H_WALL) * math.sqrt(max(0.0, 1 - (k / NR) ** 2))
    sh.patch([[Vector((x * k / NR, y * k / NR, 0.0)) for x, y, _ in per] for k in range(NR + 1)])          # 바닥 (부채)
    sh.patch([[Vector((x * k / NR, y * k / NR, dome(k))) for x, y, _ in per] for k in range(NR + 1)])     # 천장 (돔)
    # 벽: 열 = 둘레 점, 줄 = zmin..H_WALL. 문 안쪽 열은 문 아치 위부터. 문 가장자리는 열 둘(바닥까지 벽 열 + 문 위 열)
    cols = []
    for i, (x, y, zmin) in enumerate(per):
        if zmin > 0 and abs(zmin - D_WALL) < 1e-6:           # 문 가장자리 (아치 높이 = D_WALL)
            if i > 0 and per[i - 1][2] == 0.0: cols.append((x, y, 0.0)); cols.append((x, y, zmin))
            else: cols.append((x, y, zmin)); cols.append((x, y, 0.0))
        else: cols.append((x, y, zmin))
    NZW = 7
    sh.patch([[Vector((x, y, zmin + (H_WALL - zmin) * min(1.0, k / NZW))) for x, y, zmin in cols] for k in range(NZW + 1)])
    sh.finish(seed)
    for k, (x, y) in enumerate(cribs):
        h = H_WALL + (top - H_WALL) * math.sqrt(max(0.0, 1 - (Vector((x, y)).length / half) ** 2)) - 0.05
        crib(c, f"{t}_{k}", x, y, h)
        col_box(c, f"{t}_crib_{k}", (CRIB_W, CRIB_W, H_WALL), (x, y, H_WALL / 2))
    rocks(c, t, 8 + len(cribs) * 2, lambda: (lambda ph, rr: (math.cos(ph) * rr, math.sin(ph) * rr))(random.uniform(0, 6.28), random.uniform(0.5, half * 0.8)))
    # 충돌: 바닥(둘레 볼록 기둥) + 벽 상자(직선 4, 남쪽은 문 양옆 2 + 인방) + 모서리 4
    col_prism(c, f"{t}_floor", [(x, y) for x, y, _ in per[::3]], 0.0)
    for f, (x, y, sx, sy) in {"N": (0, half - 0.15, 2 * a, 0.3), "E": (half - 0.15, 0, 0.3, 2 * a), "W": (-half + 0.15, 0, 0.3, 2 * a)}.items():
        col_box(c, f"{t}_wall_{f}", (sx, sy, H_TOP), (x, y, H_TOP / 2))
    for j, (xa, xb) in enumerate(((-a, x0d), (x1d, a))):
        if xb - xa > 0.05: col_box(c, f"{t}_wall_S{j}", (xb - xa, 0.3, H_TOP), ((xa + xb) / 2, -half + 0.15, H_TOP / 2))
    col_box(c, f"{t}_lintel", (2 * D_HW + 0.2, 0.3, H_TOP - D_TOP + 0.4), (door_cx, -half + 0.15, D_TOP + (H_TOP - D_TOP + 0.4) / 2))
    for k, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1))):
        ph = math.atan2(sy, sx); d = a + corner_r * 0.71 - 0.15
        col_box(c, f"{t}_corner_{k}", (0.3, corner_r * 1.5, H_TOP), (sx * d, sy * d, H_TOP / 2), (0, 0, ph + math.pi / 2))
    n_slot = 6 if half > 5 else 3
    for i in range(n_slot):
        ph = math.pi * (0.12 + 0.76 * i / max(1, n_slot - 1))
        d = Vector((math.cos(ph), math.sin(ph))); lo, hi = 0.0, 2 * half
        for _ in range(40):
            mid = (lo + hi) / 2
            if sdf(d * mid) < 0: lo = mid
            else: hi = mid
        q = d * (lo - 0.08); slot(c, t, i, (q.x, q.y, 1.9))
    TRI[t] = count(c)
room("room_2", CELL, ROOM2_R, ROOM2_TOP, ROOM2_DISP, [(-2.8, 2.4), (3.2, -1.6)], -HW, 7)   # 2×2: 문은 남서 칸 남면 가운데 (x -3.5)
room("room_1", HW, ROOM1_R, ROOM1_TOP, DISP, [], 0.0, 8)

# --- 대피소: 직선 + 동쪽 벽감(문) ---
c = coll("PC_refuge"); t = "refuge"
REF_Y0, REF_Y1, REF_X1 = -REF_W / 2, REF_W / 2, HW + REF_D
alcove_open = Opening((HW, 0, REF_H / 2), (0, 1, 0), (0, 0, 1), REF_W / 2, REF_H / 2)
def refuge_inside(p): return Vector((HW + REF_D / 2, 0, 1.0)) if p.x > HW + 0.05 else Vector((0, 0, 2.0))
sh = junction_shell(f"SHL_{t}", c, "NS", inside=refuge_inside, extra_openings=[alcove_open], skip_wall=lambda f: f == 'E')
# 동쪽 벽: 벽감 구멍을 비우고 짠다
ys = lin(-HW, HW, NU); zs = lin(0.0, H_WALL, NZ)
for j in range(NU):
    for k in range(NZ):
        y0, y1, z0, z1 = ys[j], ys[j + 1], zs[k], zs[k + 1]
        if y0 > REF_Y0 - 1e-4 and y1 < REF_Y1 + 1e-4 and z1 < REF_H + 1e-4: continue
        sh.patch([[(HW, y0, z0), (HW, y1, z0)], [(HW, y0, z1), (HW, y1, z1)]])
# 벽감 안: 바닥·뒷벽·옆벽 2·천장
ya = lin(REF_Y0, REF_Y1, 7); xa = lin(HW, REF_X1, 8); za = lin(0.0, REF_H, 6)
sh.patch([[(x, y, 0.0) for x in xa] for y in ya]); sh.patch([[(x, y, REF_H) for x in xa] for y in ya])
sh.patch([[(REF_X1, y, z) for y in ya] for z in za])
sh.patch([[(x, REF_Y0, z) for x in xa] for z in za]); sh.patch([[(x, REF_Y1, z) for x in xa] for z in za])
sh.finish(9)
for k, y in enumerate((-2.625, -1.6, 1.6, 2.625)): timber_set(c, f"{t}_{k}", y, sides=("L",) if abs(y) < 2 else ("L", "R"))
# 문틀 + 판문(30° 열림) + 표지 + 벤치 + 공기관
for side in (-1, 1): box(f"TMB_{t}_jamb_{side+1}", (0.16, 0.16, REF_H + 0.1), (HW - 0.08, side * (REF_W / 2 - 0.08), (REF_H + 0.1) / 2), c, M["MAT_Timber"])
box(f"TMB_{t}_head", (0.16, REF_W + 0.1, 0.16), (HW - 0.08, 0, REF_H + 0.08), c, M["MAT_Timber"])
door = new_obj(f"PRP_{t}_door", None, c, loc=(HW - 0.06, REF_Y0 + 0.16, 0.0), rot=(0, 0, math.radians(-30)))
for i in range(5):
    p = box(f"PRP_{t}_plank_{i}", (0.05, 0.42, REF_H - 0.12), (0, 0.22 + i * 0.44, (REF_H - 0.12) / 2 + 0.03), c, M["MAT_Timber"]); p.parent = door
for i, z in enumerate((0.5, 1.5)):
    b = box(f"PRP_{t}_batten_{i}", (0.04, REF_W - 0.4, 0.12), (0.045, (REF_W - 0.35) / 2, z), c, M["MAT_Timber"]); b.parent = door
h = box(f"PRP_{t}_handle", (0.05, 0.03, 0.18), (0.07, REF_W - 0.55, 1.05), c, M["MAT_RustyMetal"]); h.parent = door
box(f"PRP_{t}_sign", (0.04, 0.9, 0.3), (HW - 0.1, 0, REF_H + 0.4), c, M["MAT_Timber"])
font = bpy.data.fonts.load("C:/Windows/Fonts/malgun.ttf") if os.path.exists("C:/Windows/Fonts/malgun.ttf") else None
tc = bpy.data.curves.new(f"PRP_{t}_signtext", 'FONT'); tc.body = "대 피 소"; tc.size = 0.2; tc.extrude = 0.006; tc.align_x = 'CENTER'
if font: tc.font = font
txt = new_obj(f"PRP_{t}_signtext", tc, c, M["MAT_RustyMetal"], loc=(HW - 0.125, 0, REF_H + 0.32), rot=(math.radians(90), 0, math.radians(-90)))
curve_to_mesh(txt)
box(f"PRP_{t}_bench", (0.5, REF_W - 0.3, 0.06), (REF_X1 - 0.3, 0, 0.45), c, M["MAT_Timber"])
for side in (-1, 1): box(f"PRP_{t}_benchleg_{side+1}", (0.4, 0.06, 0.42), (REF_X1 - 0.3, side * (REF_W / 2 - 0.3), 0.21), c, M["MAT_Timber"])
cyl(f"PRP_{t}_airpipe", 0.03, REF_D + 0.3, (HW + REF_D / 2, REF_Y1 - 0.12, REF_H - 0.15), c, M["MAT_RustyMetal"], rot=(0, math.pi / 2, 0))
pipe_cable_straight(c, t, x_side=-1)
rocks(c, t, 8, lambda: (random.uniform(-3.0, -0.8), random.uniform(-3.2, 3.2)))
col_box(c, f"{t}_floor", (CELL + REF_D, CELL, 0.5), (REF_D / 2, 0, -0.25)); wall_cols(c, t, "W")
for j, (y0, y1) in enumerate(((-HW, REF_Y0), (REF_Y1, HW))): col_box(c, f"{t}_wall_E{j}", (0.3, y1 - y0, H_TOP), (HW - 0.15, (y0 + y1) / 2, H_TOP / 2))
col_box(c, f"{t}_lintel", (0.3, REF_W, H_TOP - REF_H), (HW - 0.15, 0, REF_H + (H_TOP - REF_H) / 2))
col_box(c, f"{t}_back", (0.3, REF_W, REF_H), (REF_X1 - 0.15, 0, REF_H / 2))
for j, y in enumerate((REF_Y0 + 0.15, REF_Y1 - 0.15)): col_box(c, f"{t}_side_{j}", (REF_D, 0.3, REF_H), (HW + REF_D / 2, y, REF_H / 2))
col_box(c, f"{t}_ceilA", (REF_D, REF_W, 0.3), (HW + REF_D / 2, 0, REF_H + 0.15))
for i, y in enumerate((-2.5, 2.5)): slot(c, t, i, (-HW + 0.08, y, 1.9))
TRI[t] = count(c)

# ================= 레일 덧씌우기 4 =================
print("[2/4] 레일 4")
def rail_straight(c, tag, y0, y1, sleepers=True):
    for side, x in (("L", -RAIL_GAUGE / 2), ("R", RAIL_GAUGE / 2)):
        box(f"RL_{tag}_rail_{side}", (0.06, y1 - y0, 0.10), (x, (y0 + y1) / 2, 0.15), c, M["MAT_RustyMetal"], bevel=0)
        box(f"RL_{tag}_foot_{side}", (0.12, y1 - y0, 0.02), (x, (y0 + y1) / 2, 0.11), c, M["MAT_RustyMetal"], bevel=0)
    if sleepers:
        y = y0 + 0.3; i = 0
        while y < y1 - 0.1:
            box(f"RL_{tag}_sleeper_{i}", (1.2, 0.2, 0.10), (jit(0.02), y, 0.05), c, M["MAT_Timber"], (0, jit(0.02), jit(0.03)), bevel=0.008); y += 0.6; i += 1
def arc_bar(name, c, mat, rr, w, h, z, th0, th1, n=16):
    """CC 둘레 호를 따라 쓸어 만든 각재 (곡선 레일)."""
    bm = bmesh.new(); rings = []
    for th in lin(th0, th1, n):
        r = Vector((math.cos(th), math.sin(th), 0)); ring = []
        for dr, dz in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
            ring.append(bm.verts.new(CC + r * (rr + dr) + Vector((0, 0, z + dz))))
        rings.append(ring)
    for a_, b_ in zip(rings, rings[1:]):
        for i in range(4): bm.faces.new((a_[i], a_[(i + 1) % 4], b_[(i + 1) % 4], b_[i]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    return new_obj(name, me, c, mat)
def rail_curve(c, tag, th0=0.0, th1=math.pi / 2, sleeper_from=0.0):
    for side, rr in (("L", HW - RAIL_GAUGE / 2), ("R", HW + RAIL_GAUGE / 2)):
        arc_bar(f"RL_{tag}_rail_{side}", c, M["MAT_RustyMetal"], rr, 0.06, 0.10, 0.15, th0, th1)
        arc_bar(f"RL_{tag}_foot_{side}", c, M["MAT_RustyMetal"], rr, 0.12, 0.02, 0.11, th0, th1)
    n = int(HW * (th1 - th0) / 0.6); i = 0
    for th in lin(th0, th1, n)[1:]:
        if th < sleeper_from: continue
        q = CC + Vector((math.cos(th), math.sin(th), 0)) * HW
        box(f"RL_{tag}_sleeper_{i}", (1.2, 0.2, 0.10), (q.x, q.y, 0.05), c, M["MAT_Timber"], (0, 0, th), bevel=0.008); i += 1
c = coll("RAIL_straight"); rail_straight(c, "straight", -HW, HW); TRI["rail_straight"] = count(c)
c = coll("RAIL_curve"); rail_curve(c, "curve"); TRI["rail_curve"] = count(c)
c = coll("RAIL_turnout"); rail_straight(c, "turnout", -HW, HW); rail_curve(c, "turnout_c", sleeper_from=math.radians(38)); TRI["rail_turnout"] = count(c)
c = coll("RAIL_end"); t = "end"
rail_straight(c, t, -HW, BUFFER_Y)
for side in (-1, 1): box(f"RL_{t}_bufpost_{side+1}", (0.2, 0.2, 0.7), (side * 0.55, BUFFER_Y + 0.2, 0.35), c, M["MAT_Timber"])
box(f"RL_{t}_bufbeam", (1.5, 0.3, 0.3), (0, BUFFER_Y + 0.2, 0.75), c, M["MAT_Timber"])
for side in (-1, 1): box(f"RL_{t}_bufbrace_{side+1}", (0.12, 0.9, 0.12), (side * 0.55, BUFFER_Y + 0.55, 0.45), c, M["MAT_Timber"], (math.radians(-45), 0, 0))
col_box(c, f"{t}_buffer", (1.5, 0.3, 0.9), (0, BUFFER_Y + 0.2, 0.45))
TRI["rail_end"] = count(c)

# ================= 저장 =================
print("[3/4] 저장")
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
over = [k for k, v in TRI.items() if v > TRI_MAX]
print("ok 저장 %s" % OUT_BLEND)
for k, v in TRI.items(): print("ok 조각 %-13s 삼각형 %6d %s" % (k, v, "!! 예산 초과" if v > TRI_MAX else ""))
print("ok 조각 13, 예산(%d) 초과 %d" % (TRI_MAX, len(over)))

# ================= 렌더 (저장 뒤. 컬렉션 인스턴스로 배치 — .blend 에는 안 남는다) =================
if RENDER:
    print("[4/4] 렌더")
    RC = coll("RENDER"); LC = coll("LIGHTS")
    for cname in list(bpy.data.collections.keys()):
        if cname.startswith(("PC_", "RAIL_")):
            bpy.context.view_layer.layer_collection.children[cname].exclude = True     # 원본은 안 찍는다 (인스턴스만)
    inst_n = [0]
    def inst(cname, loc, rot_deg=0):
        e = bpy.data.objects.new(f"INST_{cname}_{inst_n[0]}", None); inst_n[0] += 1
        e.instance_type = 'COLLECTION'; e.instance_collection = bpy.data.collections[cname]
        e.location = loc; e.rotation_euler = (0, 0, math.radians(rot_deg)); RC.objects.link(e); return e
    def clear_render():
        for o in list(RC.objects) + list(LC.objects): bpy.data.objects.remove(o, do_unlink=True)
    def dummy(spots):
        mat = bpy.data.materials.get("MAT_Dummy") or bpy.data.materials.new("MAT_Dummy"); mat.diffuse_color = (0.55, 0.55, 0.6, 1)
        for i, (x, y) in enumerate(spots):
            o = cyl(f"DUMMY_{inst_n[0]}_{i}", 0.4, 1.0, (x, y, 0.9), RC, mat, segs=16); inst_n[0] += 1
            for k, z in enumerate((0.4, 1.4)):
                bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.4)
                me = bpy.data.meshes.new(f"DUMMYc_{inst_n[0]}_{k}"); bm.to_mesh(me); bm.free(); inst_n[0] += 1
                new_obj(me.name, me, RC, mat, (x, y, z))
    def lights(points, energy=1800, size=3.5, kind='POINT'):
        for i, (x, y, z) in enumerate(points):
            ld = bpy.data.lights.new(f"LGT_{inst_n[0]}", kind); ld.energy = energy; inst_n[0] += 1
            if kind == 'AREA': ld.size = size
            else: ld.shadow_soft_size = 0.4
            new_obj(ld.name, ld, LC, loc=(x, y, z))
    def cap_at(x, y, rot): inst("PC_cap", (x, y, 0), rot)          # 뚫린 끝을 막는다 — 렌더에 검은 구멍이 안 남게
    cam_data = bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22
    cam = new_obj("CAM_Main", cam_data, sc.collection); sc.camera = cam
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
    def shoot(name, loc, rot_deg, ortho=None):
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot_deg]
        cam.data.type = 'ORTHO' if ortho else 'PERSP'
        if ortho: cam.data.ortho_scale = ortho
        sc.render.filepath = os.path.join(RENDER, f"piece_{name}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)
    # a: 곡선 안. 조각: 곡선(0,0) + 남쪽 직선(0,-7) + 서쪽 직선(-7,0, 90°). 레일도.
    inst("PC_curve", (0, 0, 0)); inst("RAIL_curve", (0, 0, 0))
    inst("PC_straight", (0, -CELL, 0)); inst("RAIL_straight", (0, -CELL, 0))
    inst("PC_straight", (-CELL, 0, 0), 90); inst("RAIL_straight", (-CELL, 0, 0), 90)
    inst("PC_straight", (0, -2 * CELL, 0)); inst("RAIL_straight", (0, -2 * CELL, 0))
    cap_at(0, -3 * CELL, 180); cap_at(-2 * CELL, 0, 90)
    dummy([(1.2, -1.5), (-2.0, -0.6)])
    lights([(0, -2, 4.2), (-2, 0, 4.2), (0, -8, 4.2), (-8, 0, 4.2), (0, -15, 4.2)], 900)
    shoot("a_curve_in", (1.5, -3.0, 1.7), (86, 0, 50))               # 곡선 안, 바깥 벽을 따라 서쪽 출구를 본다
    shoot("b_curve_seam", (0.6, -12.5, 1.7), (88, 0, 0))              # 남쪽 직선 안에서 곡선 쪽
    clear_render()
    # c: T 갈림 3m 앞 (남쪽 직선에서 북쪽을 본다. E 로 갈라짐)
    inst("PC_t", (0, 0, 0)); inst("RAIL_turnout", (0, 0, 0), 180)     # 분기: 직진 N-S + 곡선 N→E (180° 돌린 S→W)
    inst("PC_straight", (0, -CELL, 0)); inst("RAIL_straight", (0, -CELL, 0))
    inst("PC_straight", (0, CELL, 0)); inst("RAIL_straight", (0, CELL, 0))
    inst("PC_straight", (CELL, 0, 0), 90); inst("RAIL_straight", (CELL, 0, 0), 90)
    cap_at(0, 2 * CELL, 0); cap_at(0, -2 * CELL, 180); cap_at(2 * CELL, 0, -90)
    dummy([(2.2, 1.0)])
    lights([(0, 0, 4.4), (0, -6, 4.2), (0, 6, 4.2), (6, 0, 4.2)], 900)
    shoot("c_t", (0.0, -6.5, 1.7), (88, 0, 0))
    clear_render()
    # d: + 위에서 (bright, 뒷면 컬링으로 천장을 지운다)
    for m in (M["MAT_RockWall"], M["MAT_Floor"], M["MAT_Timber"], M["MAT_RustyMetal"], M["MAT_Rock"]): m.use_backface_culling = True
    inst("PC_cross", (0, 0, 0)); inst("RAIL_straight", (0, 0, 0))
    for (x, y, r) in ((0, -CELL, 0), (0, CELL, 0), (CELL, 0, 90), (-CELL, 0, 90)): inst("PC_straight", (x, y, 0), r)
    lights([(0, 0, 9), (6, 6, 9), (-6, -6, 9)], 3500, 6, 'AREA')
    shoot("d_cross_top", (0, -0.01, 24), (0, 0, 0), ortho=24)
    clear_render()
    # e: 직선에서 목 → 방 2×2 문 (방은 목 북쪽. 방 원점 = 2×2 가운데 = 목 칸 (0,0) 기준 (3.5, 10.5): 남서 칸이 (0, 7))
    inst("PC_straight", (0, -CELL, 0)); inst("PC_neck", (0, 0, 0)); inst("PC_room_2", (HW, CELL + HW, 0)); cap_at(0, -2 * CELL, 180)
    dummy([(0.6, -1.0)])
    lights([(0, -5, 4.2), (0, 0, 3.6), (0, 4.5, 2.4), (3.5, 10.5, 5.0)], 900)
    shoot("e_neck", (0.0, -9.0, 1.7), (88, 0, 0))
    # f: 방 안에서 문 쪽 (같은 배치)
    dummy([(4.5, 8.0)])
    lights([(3.5, 10.5, 5.6), (-1, 8, 4.5), (8, 13, 4.5)], 1100)
    shoot("f_room", (5.5, 13.5, 1.7), (84, 0, 126))
    clear_render()
    # g: 대피소 문 3m 앞 (서쪽에서 동쪽 벽감을 본다)
    inst("PC_refuge", (0, 0, 0)); inst("PC_straight", (0, -CELL, 0)); inst("PC_straight", (0, CELL, 0)); cap_at(0, 2 * CELL, 0); cap_at(0, -2 * CELL, 180)
    lights([(0, 0, 4.4), (4.6, 0, 1.5), (0, -5, 4.2), (0, 5, 4.2)], 900); LC.objects[1].data.energy = 120
    shoot("g_refuge", (-2.2, -1.2, 1.7), (86, 0, -78))
    clear_render()
    # h: 종점 = 끝막이 + 레일 종점
    inst("PC_cap", (0, 0, 0)); inst("RAIL_end", (0, 0, 0)); inst("PC_straight", (0, -CELL, 0)); inst("RAIL_straight", (0, -CELL, 0)); cap_at(0, -2 * CELL, 180)
    lights([(0, -1, 4.4), (0, 1.2, 3.0), (0, -6, 4.2)], 900)
    shoot("h_term", (0.4, -4.0, 1.7), (86, 0, 0))
    clear_render()
    # i: 카탈로그 시트 — 13 조각을 위에서 (뒷면 컬링, 라벨)
    names = [("PC_straight", "직선"), ("PC_curve", "곡선"), ("PC_t", "T"), ("PC_cross", "+"), ("PC_cap", "끝막이"),
             ("PC_neck", "목"), ("PC_room_2", "방 2×2"), ("PC_room_1", "방 1×1"), ("PC_refuge", "대피소"),
             ("RAIL_straight", "레일 직선"), ("RAIL_curve", "레일 곡선"), ("RAIL_turnout", "레일 분기"), ("RAIL_end", "레일 종점")]
    SP = 17.0
    for i, (cname, label) in enumerate(names):
        x, y = (i % 5) * SP - 2 * SP, -(i // 5) * SP + SP
        inst(cname, (x, y, 0))
        if cname.startswith("RAIL_"): inst("PC_cap" if cname == "RAIL_end" else ("PC_t" if cname == "RAIL_turnout" else ("PC_curve" if cname == "RAIL_curve" else "PC_straight")), (x, y, 0), 180 if cname == "RAIL_turnout" else 0)
        tc = bpy.data.curves.new(f"LBL_{i}", 'FONT'); tc.body = label; tc.size = 1.6; tc.align_x = 'CENTER'
        if font: tc.font = font
        new_obj(f"LBL_{i}", tc, RC, M["MAT_Bulb"], loc=(x, y - 9.0, 8.0))
    lights([(0, 0, 20), (-20, 10, 20), (20, -10, 20)], 40000, 30, 'AREA')
    shoot("i_sheet", (0, 0, 60), (0, 0, 0), ortho=90)
    print("ok render 9")
