# -*- coding: utf-8 -*-
"""MineTunnel .blend -> Godot glTF (제안서 #19).

Documents/MineTunnel/scripts/export_godot.py 의 사본을 헤드리스용으로 고쳤다. 원본과 다른 점:
  - 조명 4개(헤드램프·전구 2·석유등)를 안 내보낸다 — 갱도는 헤드램프 하나 규칙 (DevBot 검사 "Light3D 1개")
  - 전구 발광 0 — 죽은 전구. 켜는 건 순서표 ⑥ 때
  - 광차(PRP_MineCart)를 뺀다 — 사용자 09-08: "광차는 안 둬도 된다. 아직은"
  - 텍스처를 1K 로 줄인다 (2K 는 50MB). .blend 는 저장하지 않으니 원본은 그대로다
  - GLB 대신 .gltf + .bin + textures/*.jpg — 파쇄·리프트 에셋과 같은 형식. Godot 이 jpg 를
    VRAM 압축으로 임포트하고, git 에는 재질 텍스처가 PNG 로 다시 뽑히지 않는다
  - 원복 코드 없음. 헤드리스로 열고 저장 없이 끝난다

    blender -b <.blend> --python tools/minetunnel/export_godot.py -- <출력폴더> [name=<gltf 이름>] [coll=<컬렉션>] [xcoll=<컬렉션>] [timber=<id>] [rock=<id>] [floor=<id>]

  name=   산출물 이름 (기본 mine_tunnel_module). #20 부터 조각이 여럿이라 .blend 마다 다르게 준다
  coll=   이 컬렉션의 오브젝트만 내보낸다 (피트: coll=PIT)
  xcoll=  이 컬렉션은 뺀다 (정거장: xcoll=PIT). 같은 .blend 에서 조각 둘을 나눠 뽑는 데 쓴다
  rock=   MAT_RockWall 텍스처를 Poly Haven 의 다른 것으로 (#27 수정 A 판정: rock_face_04). floor= 는 MAT_Floor. 둘은 2K 로 (TEX_MAX_BIG)
"""
import bpy, os, sys
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT_DIR = os.path.abspath(ARGS[0] if ARGS else "assets/generated/tunnel")
# 갱목 텍스처 교체 (#19 2차 판정 "오래된 느낌이 없다"). 두 번째 인자 timber=<polyhaven id>[:박스매핑 스케일].
# .blend 의 MAT_Timber(medieval_wood) 는 안 건드리고 내보내기용 재질에만 다른 텍스처를 꽂는다.
# 텍스처는 Documents/MineTunnel/textures/<id>/ 에 1K 로 받는다 (build_tunnel.py 와 같은 자리·이름).
TIMBER = None; TIMBER_SCALE = None
SWAP = {}                     # 재질 이름 -> (polyhaven id, 박스매핑 스케일 또는 None). rock=/floor= (#27 수정)
for a in ARGS[1:]:
    if a.startswith("timber="):
        v = a[7:].split(":"); TIMBER = v[0]; TIMBER_SCALE = float(v[1]) if len(v) > 1 else None
    elif a.startswith("rock=") or a.startswith("floor="):
        k, v = a.split("=", 1); v = v.split(":")
        SWAP["MAT_RockWall" if k == "rock" else "MAT_Floor"] = (v[0], float(v[1]) if len(v) > 1 else None)
TEX_DIR = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel", "textures")
def fetch_texture(asset, res="2k"):
    import json, urllib.request, glob
    def get(url):
        req = urllib.request.Request(url, headers={"User-Agent": "mine-tunnel-build"})
        return json.loads(urllib.request.urlopen(req, timeout=30).read().decode())
    files = get(f"https://api.polyhaven.com/files/{asset}")
    out = {}
    for m in ["Diffuse", "nor_gl", "Rough"]:
        if m not in files: continue
        entry = files[m].get(res) or files[m].get("1k")
        fmt = "jpg" if "jpg" in entry else list(entry.keys())[0]
        path = os.path.join(TEX_DIR, asset, f"{asset}_{m}.{fmt}")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not (os.path.exists(path) and os.path.getsize(path) > 500):
            req = urllib.request.Request(entry[fmt]["url"], headers={"User-Agent": "mine-tunnel-build"})
            with urllib.request.urlopen(req, timeout=180) as r, open(path, "wb") as f: f.write(r.read())
        img = bpy.data.images.load(path, check_existing=True)
        if m != "Diffuse": img.colorspace_settings.name = 'Non-Color'
        out[m] = img
    return out
TIMBER_IMGS = fetch_texture(TIMBER, "1k") if TIMBER else None
if TIMBER: print("ok 갱목 텍스처 교체 %s (%s)" % (TIMBER, ", ".join(sorted(TIMBER_IMGS))))
SWAP_IMGS = {m: fetch_texture(v[0], "2k") for m, v in SWAP.items()}
for m, v in SWAP.items(): print("ok %s 텍스처 교체 %s 2K (%s)" % (m, v[0], ", ".join(sorted(SWAP_IMGS[m]))))
os.makedirs(OUT_DIR, exist_ok=True)
NAME = next((a[5:] for a in ARGS if a.startswith("name=")), "mine_tunnel_module")
COLL = next((a[5:] for a in ARGS if a.startswith("coll=")), None)
XCOLL = next((a[6:] for a in ARGS if a.startswith("xcoll=")), None)
OUT = os.path.join(OUT_DIR, NAME + ".gltf")
TEX_MAX = 1024                                   # 이보다 큰 텍스처는 여기까지 줄인다
TEX_MAX_BIG = 2048                               # 벽·바닥(MAT_RockWall·MAT_Floor)은 2K — 1.6 m 앞에서 사진 한 장으로 읽혔다 (#27 수정)
BIG_MATS = ["MAT_RockWall", "MAT_Floor"]
EXCLUDE = ["ENV_FogVolume", "PRP_PickTaper", "LGT_Inspect_0", "LGT_Inspect_1", "PRP_MineCart"]
CURVES = ["PRP_Cable", "PRP_PickHead"]

O = bpy.data.objects; M = bpy.data.materials

# --- 내보내기용 재질 (원본과 같음: 박스매핑 -> UV, 젖음·AO·틴트·변위는 빠진다) ---
scales = {}
def make_export_mat(src_name):
    src = M[src_name]; dst = M.get(src_name + "_EXPORT") or M.new(src_name + "_EXPORT"); dst.use_nodes = True
    nt = dst.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial"); bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); nt.links.new(bsdf.outputs[0], out.inputs[0])
    imgs = {}
    for n in src.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image:
            for k in ("Diffuse", "nor_gl", "Rough"):
                if f"_{k}." in n.image.name or f"_{k}." in n.image.filepath: imgs[k] = n.image
        if n.type == 'MAPPING': scales[src_name] = n.inputs["Scale"].default_value[0]
    if src_name == "MAT_Timber" and TIMBER_IMGS:
        imgs = TIMBER_IMGS
        if TIMBER_SCALE: scales[src_name] = TIMBER_SCALE
    if src_name in SWAP_IMGS:
        imgs = SWAP_IMGS[src_name]
        if SWAP[src_name][1]: scales[src_name] = SWAP[src_name][1]
    for k, img in imgs.items():
        t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
        if k == "Diffuse": nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        elif k == "Rough": nt.links.new(t.outputs["Color"], bsdf.inputs["Roughness"])
        else:
            nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(t.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
for nm in ["MAT_RockWall", "MAT_Floor", "MAT_Timber", "MAT_RustyMetal", "MAT_Rock"]:
    if nm in M: make_export_mat(nm)          # Cage.blend(#21) 은 3종만 append 했다

def project_uv(o, scale):
    me = o.data
    if me.uv_layers: return
    uv = me.uv_layers.new(name="UVMap"); mw = o.matrix_world
    for poly in me.polygons:
        n = mw.to_3x3() @ poly.normal; ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            p = mw @ me.vertices[me.loops[li].vertex_index].co
            u, v = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
            uv.data[li].uv = (u*scale, v*scale)
for o in O:
    if o.type != 'MESH' or not o.data.materials: continue
    for i, m in enumerate(o.data.materials):
        if m and m.name in scales:
            project_uv(o, scales[m.name]); o.data.materials[i] = M[m.name + "_EXPORT"]

# --- 전구 발광 0 ---
bulb = M.get("MAT_Bulb")
if bulb and bulb.use_nodes:
    for n in bulb.node_tree.nodes:
        if n.type == 'EMISSION': n.inputs["Strength"].default_value = 0.0

# --- 텍스처 1K (벽·바닥은 2K) ---
big_imgs = set()
for nm in BIG_MATS:
    m = M.get(nm + "_EXPORT")
    if not m: continue
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image: big_imgs.add(n.image.name)
shrunk = 0
for img in bpy.data.images:
    w, h = img.size
    lim = TEX_MAX_BIG if img.name in big_imgs else TEX_MAX
    if w > lim or h > lim:
        f = lim / max(w, h); img.scale(max(1, int(w*f)), max(1, int(h*f))); shrunk += 1
print("ok 텍스처 축소 %d장 -> 최대 %dpx (벽·바닥 %d장은 %dpx)" % (shrunk, TEX_MAX, len(big_imgs), TEX_MAX_BIG))

# --- 제외 (광차는 자식까지) / 커브 -> 메시 ---
hidden = 0
for nm in EXCLUDE:
    o = O.get(nm)
    if not o: continue
    for x in [o] + list(o.children_recursive):
        x.hide_viewport = True; x.hide_set(True); hidden += 1
print("ok 제외 %d개 (광차 %s)" % (hidden, "포함" if O.get("PRP_MineCart") else "없음"))
if COLL or XCOLL:
    n = 0
    for o in O:
        names = {c.name for c in o.users_collection}
        if (COLL and COLL not in names) or (XCOLL and XCOLL in names):
            o.hide_viewport = True; o.hide_set(True); n += 1
    print("ok 컬렉션 필터 coll=%s xcoll=%s -> %d개 숨김" % (COLL, XCOLL, n))
dg = bpy.context.evaluated_depsgraph_get()
for nm in CURVES:
    o = O.get(nm)
    if not o: continue
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
    for m in o.data.materials: me.materials.append(M.get(m.name + "_EXPORT") or m)
    mo = bpy.data.objects.new(nm + "_mesh", me); o.users_collection[0].objects.link(mo)
    mo.matrix_world = o.matrix_world.copy(); mo.parent = o.parent
    if o.parent: mo.matrix_parent_inverse = o.matrix_parent_inverse.copy()
    o.hide_viewport = True; o.hide_set(True)

visible = [o for o in O if o.type == 'MESH' and not o.hide_get()]
tris = sum(len(o.evaluated_get(dg).data.loop_triangles) for o in visible)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLTF_SEPARATE', export_texture_dir="textures",
                          use_visible=True, export_apply=True,
                          export_lights=False, export_cameras=False, export_yup=True,
                          export_image_format='JPEG', export_jpeg_quality=85,
                          export_texcoords=True, export_normals=True, export_materials='EXPORT')
total = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(OUT_DIR) for f in fs)
print("ok export %s  메시 %d개  삼각형 %d  합계 %.1f MB" % (OUT, len(visible), tris, total / 1048576))
