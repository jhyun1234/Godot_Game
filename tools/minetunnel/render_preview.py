# render_preview.py - 확인용(bright) / 분위기(mood) 렌더를 renders/ 폴더에 저장
# 사용: 그냥 실행하면 3앵글 x 2버전 = 6장. 아래 VIEWS/TAG를 바꿔서 원하는 것만 뽑을 수 있다.
import bpy, os, math
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel")
OUT = os.path.join(PROJ, "renders"); os.makedirs(OUT, exist_ok=True)
TAG = "preview"                      # 파일명 접두어
RES = (1280, 960); SAMPLES = 48
VIEWS = {                            # 이름: (카메라 위치, 회전(도))
    "a_front": ((0.2, 0.5, 1.6), (88, 0, -4)),
    "b_left":  ((-0.6, 0.9, 1.6), (82, 0, -30)),
    "c_cart":  ((1.4, 1.5, 1.7), (80, 0, 25)),
}
DO_BRIGHT, DO_MOOD = True, True

sc = bpy.context.scene; O = bpy.data.objects
cam = O["CAM_Main"]
sc.render.resolution_x, sc.render.resolution_y = RES; sc.render.resolution_percentage = 100
if hasattr(sc.eevee, "taa_render_samples"): sc.eevee.taa_render_samples = SAMPLES
sc.render.image_settings.file_format = 'JPEG'; sc.render.image_settings.quality = 90
fog = next(n for n in bpy.data.materials["MAT_Fog"].node_tree.nodes if n.type == 'VOLUME_SCATTER')
fog_density = fog.inputs["Density"].default_value
ld = bpy.data.lights.get("LGT_Inspect") or bpy.data.lights.new("LGT_Inspect", 'AREA'); ld.energy = 900; ld.size = 3.0
insp = []
for i, y in enumerate((2.0, 6.0)):
    o = O.get(f"LGT_Inspect_{i}")
    if not o:
        o = bpy.data.objects.new(f"LGT_Inspect_{i}", ld); bpy.data.collections["LIGHTS"].objects.link(o)
    o.location = (0, y, 3.7); insp.append(o)
orig_loc, orig_rot = cam.location.copy(), cam.rotation_euler.copy()
def shoot(kind, bright):
    for o in insp: o.hide_render = not bright
    fog.inputs["Density"].default_value = 0.0 if bright else fog_density
    sc.view_settings.exposure = 0.6 if bright else 0.0
    for k, (loc, rot) in VIEWS.items():
        cam.location = loc; cam.rotation_euler = [math.radians(r) for r in rot]
        sc.render.filepath = os.path.join(OUT, f"{TAG}_{kind}_{k}.jpg")
        bpy.ops.render.render(write_still=True); print("saved", sc.render.filepath)
if DO_BRIGHT: shoot("bright", True)
if DO_MOOD: shoot("mood", False)
for o in insp: o.hide_render = True
fog.inputs["Density"].default_value = fog_density; sc.view_settings.exposure = 0.0
cam.location, cam.rotation_euler = orig_loc, orig_rot
