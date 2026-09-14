# build_tunnel.py - 광산 갱도 모듈 전체 빌드 (Blender 5.2, MCP 또는 Scripting 탭에서 실행)
# 재실행 가능: 같은 이름의 컬렉션/오브젝트는 지우고 다시 만든다.
#   헤드리스: blender -b MineTunnel.blend --python build_tunnel.py -- save [render=<폴더>]   (bash tools/minetunnel/render_tunnel.sh)
#   #22 (2026-09-08): 격자 4 → 7. 폭 7 × 높이 5.6(벽 4.4) × 길이 14, 갱목 1.75 간격·기둥 0.34. 원본 4×4 판은 MineTunnel_4x4.blend.
import bpy, bmesh, math, random, os, glob, json, urllib.request, sys
from mathutils import Vector
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = next((a[7:] for a in ARGS if a.startswith("render=")), None)

# ---------------- 파라미터 ----------------
L, W, H_WALL, H_TOP = 14.0, 7.0, 4.4, 5.6    # 길이(Y) / 폭 / 수직벽 높이 / 아치 정점 (#22: 7m 격자 2칸, 비율 1.25 = 국내 복선 갱도 4.8×3.5)
SET_SPACING = 1.75                           # 갱목 세트 간격 (14 에 8세트)
POST_W, CAP_W = 0.34, 0.36                   # 갱목 기둥·갓보 각재 (#22: 7m 를 버티는 굵기. 4m 때 0.24·0.28)
RAIL_GAUGE = 0.6
SEED = 7
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
TEX_DIR = os.path.join(PROJ, "textures"); MODEL_DIR = os.path.join(PROJ, "models")
TEXTURES = {                                  # 재질명: (polyhaven id, 박스매핑 스케일, 젖음 여부, 틴트)
    "MAT_RockWall":   ("dark_rock",          0.42, True,  None),
    "MAT_Floor":      ("brown_mud_rocks_01", 0.70, True,  None),
    "MAT_Timber":     ("medieval_wood",      1.40, False, (0.75, 0.62, 0.5, 1)),
    "MAT_RustyMetal": ("rusty_metal_02",     2.50, False, None),
    "MAT_Rock":       ("dark_rock_02",       1.80, False, None),
}
MODELS = ["wooden_crate_01", "wooden_barrels_01", "rusted_spade_01", "sledgehammer_01", "vintage_oil_lamp", "wooden_bucket_01"]

random.seed(SEED)
sc = bpy.context.scene
sc.unit_settings.system = 'METRIC'; sc.unit_settings.scale_length = 1.0
post_h = H_WALL + 0.4
jit = lambda s: random.uniform(-s, s)

# ---------------- 유틸 ----------------
def coll(name):
    c = bpy.data.collections.get(name)
    if not c:
        c = bpy.data.collections.new(name); sc.collection.children.link(c)
    return c
def clear_coll(name):
    c = coll(name)
    for nm in [o.name for o in c.objects]:
        o = bpy.data.objects.get(nm)
        if o: bpy.data.objects.remove(o, do_unlink=True)
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

# ---------------- Poly Haven 다운로드 ----------------
def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "mine-tunnel-build"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read().decode())
def _dl(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and os.path.getsize(path) > 500: return
    req = urllib.request.Request(url, headers={"User-Agent": "mine-tunnel-build"})
    with urllib.request.urlopen(req, timeout=180) as r, open(path, "wb") as f: f.write(r.read())
def fetch_texture(asset, res="2k"):
    files = _get(f"https://api.polyhaven.com/files/{asset}")
    for m in ["Diffuse", "nor_gl", "Rough", "Displacement", "AO"]:
        if m not in files: continue
        entry = files[m].get(res) or files[m].get("1k")
        fmt = "jpg" if "jpg" in entry else list(entry.keys())[0]
        _dl(entry[fmt]["url"], os.path.join(TEX_DIR, asset, f"{asset}_{m}.{fmt}"))
def fetch_model(asset, res="1k"):
    files = _get(f"https://api.polyhaven.com/files/{asset}")
    g = files["gltf"].get(res) or files["gltf"][sorted(files["gltf"].keys())[0]]
    entry = g["gltf"]; d = os.path.join(MODEL_DIR, asset)
    _dl(entry["url"], os.path.join(d, f"{asset}.gltf"))
    for rel, info in entry.get("include", {}).items(): _dl(info["url"], os.path.join(d, rel))

print("[1/7] 텍스처/모델 다운로드")
for _, (asset, *_r) in TEXTURES.items(): fetch_texture(asset)
for a in MODELS: fetch_model(a)

# ---------------- 재질 ----------------
def load_img(asset, m):
    p = glob.glob(os.path.join(TEX_DIR, asset, f"{asset}_{m}.*"))
    if not p: return None
    img = bpy.data.images.load(p[0], check_existing=True)
    if m != "Diffuse": img.colorspace_settings.name = 'Non-Color'
    return img
def make_mat(name, asset, scale, wet, tint):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear(); N, Lk = nt.nodes, nt.links
    out = N.new("ShaderNodeOutputMaterial"); out.location = (900, 0)
    bsdf = N.new("ShaderNodeBsdfPrincipled"); bsdf.location = (550, 0); Lk.new(bsdf.outputs[0], out.inputs[0])
    tc = N.new("ShaderNodeTexCoord"); tc.location = (-1100, 0)
    mp = N.new("ShaderNodeMapping"); mp.location = (-900, 0); mp.inputs["Scale"].default_value = (scale,)*3
    Lk.new(tc.outputs["Object"], mp.inputs["Vector"])
    imgs = {}; y = 300
    for m in ["Diffuse", "nor_gl", "Rough", "AO", "Displacement"]:
        img = load_img(asset, m)
        if not img: continue
        n = N.new("ShaderNodeTexImage"); n.image = img; n.location = (-600, y); y -= 300
        n.projection = 'BOX'; n.projection_blend = 0.4; Lk.new(mp.outputs[0], n.inputs["Vector"]); imgs[m] = n
    col = imgs["Diffuse"].outputs["Color"]
    if "AO" in imgs:
        mx = N.new("ShaderNodeMix"); mx.data_type = 'RGBA'; mx.blend_type = 'MULTIPLY'; mx.location = (-200, 300)
        mx.inputs[0].default_value = 0.7; Lk.new(col, mx.inputs[6]); Lk.new(imgs["AO"].outputs["Color"], mx.inputs[7]); col = mx.outputs[2]
    if tint:
        mt = N.new("ShaderNodeMix"); mt.data_type = 'RGBA'; mt.blend_type = 'MULTIPLY'; mt.location = (0, 300)
        mt.inputs[0].default_value = 1.0; mt.inputs[7].default_value = tint; Lk.new(col, mt.inputs[6]); col = mt.outputs[2]
    r = imgs["Rough"].outputs["Color"]
    if wet:
        noise = N.new("ShaderNodeTexNoise"); noise.location = (-600, -900)
        noise.inputs["Scale"].default_value = 1.6; noise.inputs["Detail"].default_value = 6.0; noise.inputs["Roughness"].default_value = 0.65
        Lk.new(tc.outputs["Object"], noise.inputs["Vector"])
        ramp = N.new("ShaderNodeValToRGB"); ramp.location = (-350, -900)
        ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[1].position = 0.62; Lk.new(noise.outputs["Fac"], ramp.inputs[0])
        wm = N.new("ShaderNodeMix"); wm.data_type = 'FLOAT'; wm.location = (0, -300); wm.inputs[3].default_value = 0.12
        Lk.new(r, wm.inputs[2]); Lk.new(ramp.outputs[0], wm.inputs[0]); r = wm.outputs[0]
        dk = N.new("ShaderNodeMix"); dk.data_type = 'RGBA'; dk.blend_type = 'MULTIPLY'; dk.location = (150, 300)
        dk.inputs[7].default_value = (0.55, 0.55, 0.6, 1); Lk.new(ramp.outputs[0], dk.inputs[0]); Lk.new(col, dk.inputs[6]); col = dk.outputs[2]
        bsdf.inputs["Specular IOR Level"].default_value = 0.6
    Lk.new(col, bsdf.inputs["Base Color"]); Lk.new(r, bsdf.inputs["Roughness"])
    nm = N.new("ShaderNodeNormalMap"); nm.location = (200, -600)
    Lk.new(imgs["nor_gl"].outputs["Color"], nm.inputs["Color"]); Lk.new(nm.outputs[0], bsdf.inputs["Normal"])
    if "Displacement" in imgs:
        dn = N.new("ShaderNodeDisplacement"); dn.location = (550, -600); dn.inputs["Scale"].default_value = 0.02
        Lk.new(imgs["Displacement"].outputs["Color"], dn.inputs["Height"]); Lk.new(dn.outputs[0], out.inputs["Displacement"]); mat.displacement_method = 'BUMP'
    return mat
def simple_mat(name, color, rough=0.5, emission=None):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name); mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear(); out = nt.nodes.new("ShaderNodeOutputMaterial")
    if emission:
        e = nt.nodes.new("ShaderNodeEmission"); e.inputs["Color"].default_value = color; e.inputs["Strength"].default_value = emission; nt.links.new(e.outputs[0], out.inputs[0])
    else:
        b = nt.nodes.new("ShaderNodeBsdfPrincipled"); b.inputs["Base Color"].default_value = color; b.inputs["Roughness"].default_value = rough; nt.links.new(b.outputs[0], out.inputs[0])
    return mat

print("[2/7] 재질")
for name, (asset, scale, wet, tint) in TEXTURES.items(): make_mat(name, asset, scale, wet, tint)
simple_mat("MAT_Cable", (0.02, 0.02, 0.02, 1), 0.55)
simple_mat("MAT_Bulb", (1.0, 0.72, 0.4, 1), emission=12)
M = bpy.data.materials

# ---------------- 암반 쉘 + 바닥 ----------------
print("[3/7] 암반 쉘/바닥")
env = clear_coll("ENV")
hw = W/2 + 0.15
profile = [Vector((-hw, 0, -0.1)), Vector((-hw, 0, H_WALL))]
for i in range(1, 10):
    a = math.pi*(1 - i/10); profile.append(Vector((math.cos(a)*hw, 0, H_WALL + math.sin(a)*(H_TOP - H_WALL))))
profile += [Vector((hw, 0, H_WALL)), Vector((hw, 0, -0.1))]
bm = bmesh.new(); ny = int(L/0.25); rows = [[bm.verts.new(Vector((p.x, j*0.25, p.z))) for p in profile] for j in range(ny+1)]
for j in range(ny):
    for i in range(len(profile)-1): bm.faces.new((rows[j][i], rows[j][i+1], rows[j+1][i+1], rows[j+1][i]))
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-6], cuts=2, use_grid_fill=True)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
for f in bm.faces:
    c = f.calc_center_median()
    if f.normal.dot(Vector((-c.x, 0, 1.6 - c.z))) < 0: f.normal_flip()
me = bpy.data.meshes.new("ENV_RockShell"); bm.to_mesh(me); bm.free()
shell = new_obj("ENV_RockShell", me, env, M["MAT_RockWall"])
bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=20, y_segments=40, size=1.0)
for v in bm.verts: v.co.x *= hw; v.co.y = (v.co.y + 1.0)*L/2
me = bpy.data.meshes.new("ENV_Floor"); bm.to_mesh(me); bm.free()
floor = new_obj("ENV_Floor", me, env, M["MAT_Floor"])
def add_disp(o, name, size, strength, sub=2):
    s = o.modifiers.new("Subdiv", 'SUBSURF'); s.subdivision_type = 'SIMPLE'; s.levels = sub; s.render_levels = sub
    for suf, sc_, st in (("", size, strength), ("_fine", size*0.25, strength*0.35)):
        t = bpy.data.textures.get(name+suf) or bpy.data.textures.new(name+suf, 'CLOUDS'); t.noise_scale = sc_; t.noise_depth = 5
        d = o.modifiers.new("Displace"+suf, 'DISPLACE'); d.texture = t; d.strength = st; d.mid_level = 0.5; d.texture_coords = 'GLOBAL'
    sm = o.modifiers.new("Smooth", 'SMOOTH'); sm.factor = 0.3
    for p in o.data.polygons: p.use_smooth = True
add_disp(shell, "Noise_Rock", 0.9, 0.4); add_disp(floor, "Noise_Floor", 0.6, 0.12)
fv = box("ENV_FogVolume", (W+0.6, L+0.4, H_TOP+0.4), (0, L/2, H_TOP/2), env, None, bevel=0)
fm = bpy.data.materials.get("MAT_Fog") or bpy.data.materials.new("MAT_Fog"); fm.use_nodes = True
nt = fm.node_tree; nt.nodes.clear(); out = nt.nodes.new("ShaderNodeOutputMaterial"); vs = nt.nodes.new("ShaderNodeVolumeScatter")
vs.inputs["Density"].default_value = 0.022; vs.inputs["Anisotropy"].default_value = 0.5; vs.inputs["Color"].default_value = (0.85, 0.8, 0.72, 1)
nt.links.new(vs.outputs[0], out.inputs["Volume"]); fv.data.materials.append(fm); fv.display_type = 'WIRE'; fv.hide_select = True

# ---------------- 갱목 / 레일 / 돌 ----------------
print("[4/7] 갱목/레일/돌")
timber = clear_coll("TIMBER")
n_sets = int(L/SET_SPACING)
for k, y in enumerate([SET_SPACING/2 + i*SET_SPACING for i in range(n_sets)]):
    for side, x in (("L", -W/2), ("R", W/2)):
        box(f"PRP_Post_{k}{side}", (POST_W, POST_W, post_h), (x+jit(0.03), y+jit(0.03), post_h/2-0.05), timber, M["MAT_Timber"], (jit(0.02), jit(0.015), jit(0.03)))
    box(f"PRP_Cap_{k}", (W+0.5, CAP_W, CAP_W), (jit(0.03), y, post_h+0.05+jit(0.02)), timber, M["MAT_Timber"], (jit(0.01), jit(0.02), jit(0.01)))
    for i in range(random.randint(3, 5)):
        box(f"PRP_Lag_{k}_{i}", (0.3, SET_SPACING, 0.05), (random.uniform(-W/2+0.3, W/2-0.3), y+SET_SPACING/2, post_h+0.22+jit(0.03)), timber, M["MAT_Timber"], (jit(0.05), jit(0.03), jit(0.15)))
    for i in range(random.randint(1, 3)):
        side = random.choice([-1, 1])
        box(f"PRP_WallLag_{k}_{i}", (0.05, SET_SPACING-0.05, 0.28), (side*(W/2-0.05), y+SET_SPACING/2, random.uniform(0.6, H_WALL-0.8)), timber, M["MAT_Timber"], (jit(0.04), jit(0.02), jit(0.02)))
rail = clear_coll("RAIL")
for side, x in (("L", -RAIL_GAUGE/2), ("R", RAIL_GAUGE/2)):
    box(f"PRP_Rail_{side}", (0.06, L, 0.10), (x, L/2, 0.15), rail, M["MAT_RustyMetal"])
    box(f"PRP_RailFoot_{side}", (0.12, L, 0.02), (x, L/2, 0.11), rail, M["MAT_RustyMetal"])
for i in range(int(L/0.6)):
    box(f"PRP_Sleeper_{i}", (1.2, 0.2, 0.10), (jit(0.02), 0.3+i*0.6+jit(0.03), 0.05), rail, M["MAT_Timber"], (0, jit(0.02), jit(0.03)))
rocks = clear_coll("ROCKS")
for i in range(40):
    o = new_obj(f"PRP_Rock_{i}", rock_mesh(f"PRP_Rock_{i}"), rocks, M["MAT_Rock"])
    s = random.choice([random.uniform(0.05, 0.12)]*4 + [random.uniform(0.15, 0.32)])
    o.scale = (s*random.uniform(0.7, 1.3), s*random.uniform(0.7, 1.3), s*random.uniform(0.5, 0.9))
    o.location = (random.choice([-1, 1])*random.uniform(0.8, W/2-0.05), random.uniform(0.2, L-0.2), s*0.35)
    o.rotation_euler = (random.uniform(0, 6.28),)*3

# ---------------- 소품 ----------------
print("[5/7] 소품")
props = clear_coll("PROPS")
cu = bpy.data.curves.new("PRP_Cable", 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = 0.012; cu.bevel_resolution = 3
sp = cu.splines.new('NURBS'); pts = [(W/2-0.2+jit(0.02), i*L/8, post_h-0.1+(0 if i % 2 == 0 else -0.14), 1.0) for i in range(9)]
sp.points.add(len(pts)-1)
for p, co in zip(sp.points, pts): p.co = co
sp.use_endpoint_u = True; sp.order_u = 3
new_obj("PRP_Cable", cu, props, M["MAT_Cable"])
PIPE_X = W/2 - POST_W - 0.06                   # 갱목 기둥 안쪽면 바로 앞 — 기둥을 뚫지 않고 그 앞을 한 줄로 지난다 (#22 수정: 사용자 "나무 뒤에 박혀 끊어져 있다")
cyl("PRP_Pipe", 0.045, L, (PIPE_X, L/2, 1.25), props, M["MAT_RustyMetal"], rot=(math.pi/2, 0, 0), segs=12)
for i, y in enumerate([SET_SPACING/2 + k*SET_SPACING for k in range(n_sets)]):   # 기둥마다 받침 — 배관을 기둥 앞에 건다
    box(f"PRP_PipeBracket_{i}", (W/2 - PIPE_X + 0.02, 0.06, 0.06), ((PIPE_X + W/2)/2, y, 1.25), props, M["MAT_RustyMetal"])
# 광차 (시신 운반용, 큰 사이즈)
cart = new_obj("PRP_MineCart", None, props, loc=(0, 4.4, 0))
bm = bmesh.new()
bot = [bm.verts.new(Vector((x*0.76, y*1.10, 0.60))) for x, y in ((-1,-1),(1,-1),(1,1),(-1,1))]
top = [bm.verts.new(Vector((x*1.04, y*1.44, 1.76))) for x, y in ((-1,-1),(1,-1),(1,1),(-1,1))]
bm.faces.new(bot[::-1])
for i in range(4): bm.faces.new((bot[i], bot[(i+1)%4], top[(i+1)%4], top[i]))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bmesh.ops.solidify(bm, geom=bm.faces[:]+bm.edges[:]+bm.verts[:], thickness=0.06)
me = bpy.data.meshes.new("PRP_CartBody"); bm.to_mesh(me); bm.free()
body = new_obj("PRP_CartBody", me, props, M["MAT_RustyMetal"]); body.parent = cart
b = body.modifiers.new("Bevel", 'BEVEL'); b.width = 0.006; b.segments = 2
for z, sx, sy in ((1.72, 1.08, 1.48), (1.0, 0.90, 1.26)):
    box(f"PRP_CartRim_{int(z*100)}a", (sx*2+0.06, 0.08, 0.10), (0, -sy, z), props, M["MAT_RustyMetal"], parent=cart)
    box(f"PRP_CartRim_{int(z*100)}b", (sx*2+0.06, 0.08, 0.10), (0, sy, z), props, M["MAT_RustyMetal"], parent=cart)
box("PRP_CartFrame", (1.4, 2.2, 0.12), (0, 0, 0.56), props, M["MAT_RustyMetal"], parent=cart)
for j, y in enumerate((-0.8, 0.8)):
    cyl(f"PRP_CartAxle_{j}", 0.02, 0.8, (0, y, 0.30), props, M["MAT_RustyMetal"], rot=(0, math.pi/2, 0), parent=cart)
    for k, x in enumerate((-0.33, 0.33)):
        cyl(f"PRP_CartWheel_{j}{k}", 0.195, 0.075, (x, y, 0.30), props, M["MAT_RustyMetal"], rot=(0, math.pi/2, 0), segs=24, parent=cart)
for i in range(9):
    o = new_obj(f"PRP_CartOre_{i}", rock_mesh(f"PRP_CartOre_{i}", 1, 0.2), props, M["MAT_Rock"], (random.uniform(-0.7, 0.7), random.uniform(-1.0, 1.0), random.uniform(1.5, 1.8)), (random.uniform(0, 6),)*3)
    o.scale = (random.uniform(0.16, 0.29),)*3; o.parent = cart
# 알전구
bulbs = []
for i, y in enumerate((L*3/8, L*3/4), 1):
    lp = (W/2-0.35, y, post_h-0.35); bulbs.append(lp)
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.04)
    me = bpy.data.meshes.new(f"PRP_BulbGlass_{i}"); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    new_obj(f"PRP_BulbGlass_{i}", me, props, M["MAT_Bulb"], lp)
    cyl(f"PRP_BulbSocket_{i}", 0.02, 0.07, (lp[0], lp[1], lp[2]+0.07), props, M["MAT_Cable"], segs=10)
    cyl(f"PRP_BulbWire_{i}", 0.006, 0.28, (lp[0], lp[1], lp[2]+0.24), props, M["MAT_Cable"], segs=6)
# 돌무더기 + 부러진 갱목
for i in range(18):
    r = random.uniform(0.1, 0.28)
    o = new_obj(f"PRP_Rubble_{i}", rock_mesh(f"PRP_Rubble_{i}", 1), props, M["MAT_Rock"], (W/2-0.5+random.uniform(-0.45, 0.25), L/2+3.0+random.uniform(-0.6, 0.6), r*0.4+random.uniform(0, 0.25)), (random.uniform(0, 6),)*3)
    o.scale = (r*random.uniform(0.8, 1.2), r*random.uniform(0.8, 1.2), r*random.uniform(0.5, 0.8))
box("PRP_BrokenPost", (0.22, 0.22, 2.4), (W/2-0.9, L/2+3.3, 1.05), props, M["MAT_Timber"], (0.55, 0.25, 0.3))
# 곡괭이 (자체 제작)
pk = new_obj("PRP_Pickaxe", None, props, loc=(-W/2+1.05, 2.75, 0.0), rot=(0.32, -0.15, 1.1))
bm = bmesh.new(); rings = []
for z, r in [(0.0, 0.024), (0.15, 0.021), (0.5, 0.018), (0.8, 0.017), (0.88, 0.021), (0.93, 0.024)]:
    rings.append([bm.verts.new(Vector((math.cos(a)*r*1.15, math.sin(a)*r, z))) for a in [k*2*math.pi/14 for k in range(14)]])
for a, b_ in zip(rings, rings[1:]):
    for k in range(14): bm.faces.new((a[k], a[(k+1)%14], b_[(k+1)%14], b_[k]))
bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1]); bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("PRP_PickHandle"); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
new_obj("PRP_PickHandle", me, props, M["MAT_Timber"]).parent = pk
hc = bpy.data.curves.new("PRP_PickHead", 'CURVE'); hc.dimensions = '3D'; hc.bevel_depth = 0.028; hc.bevel_resolution = 4; hc.fill_mode = 'FULL'
s2 = hc.splines.new('BEZIER'); s2.bezier_points.add(4)
for bp, co in zip(s2.bezier_points, [(-0.42, 0, 0.78), (-0.22, 0, 0.90), (0, 0, 0.93), (0.22, 0, 0.90), (0.42, 0, 0.78)]):
    bp.co = co; bp.handle_left_type = bp.handle_right_type = 'AUTO'
tp = bpy.data.curves.new("PRP_PickTaper", 'CURVE'); ts = tp.splines.new('BEZIER'); ts.bezier_points.add(2)
for bp, co in zip(ts.bezier_points, [(0, 0.05, 0), (0.5, 1.0, 0), (1.0, 0.05, 0)]):
    bp.co = co; bp.handle_left_type = bp.handle_right_type = 'AUTO'
tpo = new_obj("PRP_PickTaper", tp, props); tpo.hide_render = True; tpo.hide_viewport = True; hc.taper_object = tpo
new_obj("PRP_PickHead", hc, props, M["MAT_RustyMetal"]).parent = pk
eye = box("PRP_PickEye", (0.09, 0.06, 0.075), (0, 0, 0.905), props, M["MAT_RustyMetal"], bevel=0.008, parent=pk)
# Poly Haven 모델 임포트
def import_gltf(asset, name, loc, rot=(0,0,0), scale=1.0):
    before = set(o.name for o in bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL_DIR, asset, f"{asset}.gltf"))
    new = [o for o in bpy.data.objects if o.name not in before]; newset = set(new)
    root = new_obj(name, None, props, loc=loc, rot=rot)
    for o in new:
        for c in list(o.users_collection): c.objects.unlink(o)
        props.objects.link(o)
        if o.parent is None or o.parent not in newset: o.parent = root
    for o in new: o.name = f"{name}_{o.name}"
    root.scale = (scale,)*3
    return root
import_gltf("wooden_crate_01", "PRP_CrateA", (-W/2+0.55, 2.4, 0.0), (0, 0, 0.2))
import_gltf("wooden_crate_01", "PRP_CrateB", (-W/2+0.62, 3.15, 0.0), (0, 0, -0.35), 0.85)
br = import_gltf("wooden_barrels_01", "PRP_Barrels", (-W/2+0.5, 4.3, 0.0))
for c in list(br.children_recursive):
    if "piece" in c.name: bpy.data.objects.remove(c, do_unlink=True)
for c, loc, rz in ((next(c for c in br.children_recursive if c.name.endswith("barrel01")), (0, 0, 0), 0.3),
                   (next(c for c in br.children_recursive if c.name.endswith("barrel02")), (0, 0.72, 0), -0.6)):
    c.parent = br; c.matrix_parent_inverse.identity(); c.location = loc; c.rotation_euler = (0, 0, rz)
import_gltf("rusted_spade_01", "PRP_Spade", (W/2-0.32, 1.6, 0.53), (0.05, -0.28, 0.4))
import_gltf("sledgehammer_01", "PRP_Sledge", (-W/2+1.05, 1.85, 0.06), (math.pi/2, 0, 0.7))
import_gltf("wooden_bucket_01", "PRP_Bucket", (W/2-0.7, 2.6, 0.0), (0, 0, 1.2))
import_gltf("vintage_oil_lamp", "PRP_OilLamp", (-W/2+0.60, 2.38, 0.35), (0, 0, 0.6))

# ---------------- 조명 / 카메라 / 월드 ----------------
print("[6/7] 조명/카메라")
lights = clear_coll("LIGHTS")
def light(name, kind, loc, energy, color, size=0.05, spot=None, parent=None):
    ld = bpy.data.lights.get(name) or bpy.data.lights.new(name, kind); ld.energy = energy; ld.color = color; ld.shadow_soft_size = size
    if kind == 'SPOT': ld.spot_size = math.radians(spot[0]); ld.spot_blend = spot[1]
    o = new_obj(name, ld, lights, loc=loc)
    if parent: o.parent = parent
    return o
cam_data = bpy.data.cameras.get("CAM_Main") or bpy.data.cameras.new("CAM_Main"); cam_data.lens = 22
cam = new_obj("CAM_Main", cam_data, lights, loc=(0.2, 0.5, 1.6), rot=(math.radians(88), 0, math.radians(-4))); sc.camera = cam
light("LGT_Headlamp", 'SPOT', (0.05, 0.12, 0.0), 70, (1.0, 0.93, 0.8), spot=(58, 0.75), parent=cam)
light("LGT_Bulb_1", 'POINT', bulbs[0], 40, (1.0, 0.72, 0.4), 0.04)
light("LGT_Bulb_2", 'POINT', bulbs[1], 30, (1.0, 0.72, 0.4), 0.04)
light("LGT_OilLamp", 'POINT', (-W/2+0.60, 2.38, 0.65), 14, (1.0, 0.62, 0.3), 0.03)
w = sc.world or bpy.data.worlds.new("World"); sc.world = w; w.use_nodes = True
bg = next(n for n in w.node_tree.nodes if n.type == 'BACKGROUND'); bg.inputs[0].default_value = (0.003, 0.004, 0.006, 1)
engines = [i.identifier for i in sc.render.bl_rna.properties['engine'].enum_items]
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
for attr, val in [("use_shadows", True), ("use_raytracing", True), ("volumetric_samples", 64), ("use_volumetric_shadows", True), ("taa_render_samples", 64)]:
    if hasattr(sc.eevee, attr):
        try: setattr(sc.eevee, attr, val)
        except Exception: pass
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = 0.0
print("[7/7] 완료 - 오브젝트", len(bpy.data.objects))

def dummy_people(c, spots, mat):
    """사람 크기 캡슐(지름 0.8, 키 1.8). 렌더 판정용 — 저장·내보내기에는 안 들어간다 (저장 뒤에 만든다)."""
    for i, (x, y) in enumerate(spots):
        cyl(f"DUMMY_Body_{i}", 0.4, 1.0, (x, y, 0.9), c, mat, segs=20)
        for k, z in enumerate((0.4, 1.4)):
            bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=0.4)
            me = bpy.data.meshes.new(f"DUMMY_Cap_{i}{k}"); bm.to_mesh(me); bm.free()
            for pg in me.polygons: pg.use_smooth = True
            new_obj(f"DUMMY_Cap_{i}{k}", me, c, mat, (x, y, z))

if "save" in ARGS:
    bpy.ops.wm.save_mainfile()
    dg = bpy.context.evaluated_depsgraph_get()
    tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in bpy.data.objects if o.type == 'MESH' and not o.hide_render)
    print("ok 저장 %s  삼각형 %d  (폭 %.1f 높이 %.1f 길이 %.1f)" % (bpy.data.filepath, tris, W, H_TOP, L))
if RENDER:
    # bright 렌더 2장 + 사람 크기 캡슐 4개 (판정용. 저장 뒤라 .blend 에는 안 남는다)
    dm = coll("DUMMY"); dummy_people(dm, [(-2.4, 5.0), (-0.8, 5.0), (0.8, 5.0), (2.4, 5.0)], simple_mat("MAT_Dummy", (0.55, 0.55, 0.6, 1), 0.6))
    for o in [cart] + list(cart.children_recursive): o.hide_render = True   # 광차는 게임에 안 들어간다 (내보내기 제외) — 렌더에서도 뺀다
    ld = bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 2500; ld.size = 4.0
    for i, y in enumerate((2.5, 7.5, 12.0)):
        new_obj(f"LGT_Inspect_{i}", ld, lights, loc=(0, y, H_TOP - 0.4))
    for o in bpy.data.objects:
        if o.type == 'LIGHT' and not o.name.startswith("LGT_Inspect"): o.hide_render = True
    fm2 = bpy.data.materials["MAT_Fog"]; next(n for n in fm2.node_tree.nodes if n.type == 'VOLUME_SCATTER').inputs["Density"].default_value = 0.0
    sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = 0.6
    os.makedirs(RENDER, exist_ok=True)
    sc.render.resolution_x, sc.render.resolution_y = 1280, 960; sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 90
    if hasattr(sc.eevee, "taa_render_samples"): sc.eevee.taa_render_samples = 48
    VIEWS = {"a_people": ((0.0, 0.4, 1.7), (88, 0, 0)),        # 눈높이. 캡슐 4개가 나란히 — 폭이 읽히나
             "b_cap": ((0.0, 1.2, 1.7), (118, 0, 0))}          # 갓보를 올려다보기 (90 = 수평, 118 = 위로 28°) — 높이가 읽히나
    for k, (loc, rot) in VIEWS.items():
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot]
        sc.render.filepath = os.path.join(RENDER, f"tunnel_{k}.jpg")
        bpy.ops.render.render(write_still=True); print("ok render", sc.render.filepath)

