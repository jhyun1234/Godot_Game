"""Mesh + concept image -> textured GLB with Hunyuan3D-2.0 paint (turbo), standalone (no server, no shape model).
usage: python gen_paint.py <mesh.glb> <concept.png> <out.glb>
python = C:\\AI\\HY3D2\\Hunyuan3D2_WinPortable\\python_standalone\\python.exe -s
Needs custom_rasterizer_kernel compiled (COMPILE_TEXGEN.bat) and weights
HuggingFaceHub/tencent/Hunyuan3D-2/{hunyuan3d-delight-v2-0, hunyuan3d-paint-v2-0-turbo}.
Output keeps the input coordinates; UVs are re-unwrapped by xatlas (texture 2048).

RAM rules (16 GB box — 2026-09-12 the first run bugchecked Windows 0x7A KERNEL_DATA_INPAGE_ERROR while loading the
second pipeline: both pipelines resident in RAM + ~9 GB of other apps -> paging storm -> page-in I/O error):
  * models go straight to the GPU (no cpu offload), one pipeline alive at a time: delight -> free -> multiview
  * refuse to start below RAM_NEED_GB available; a watchdog thread kills the process below RAM_KILL_GB"""
import os, sys, time, gc, threading
ROOT = r"C:\AI\HY3D2\Hunyuan3D2_WinPortable"
os.environ.setdefault("HY3DGEN_MODELS", os.path.join(ROOT, "HuggingFaceHub"))
os.environ.setdefault("HF_HUB_CACHE", os.path.join(ROOT, "HuggingFaceHub"))
os.environ.setdefault("HF_HUB_OFFLINE", "1")
sys.path.insert(0, os.path.join(ROOT, "Hunyuan3D-2"))

import psutil
RAM_NEED_GB = 6.0
RAM_KILL_GB = 1.2


def avail_gb():
    return psutil.virtual_memory().available / 1e9


def watchdog():
    while True:
        a = avail_gb()
        if a < RAM_KILL_GB:
            print("RAM watchdog: available %.2f GB < %.1f — aborting before Windows pages itself to death" % (a, RAM_KILL_GB), flush=True)
            os._exit(3)
        time.sleep(0.5)


if avail_gb() < RAM_NEED_GB:
    print("available RAM %.1f GB < %.1f GB needed — close other apps first" % (avail_gb(), RAM_NEED_GB)); sys.exit(2)
threading.Thread(target=watchdog, daemon=True).start()

import numpy as np, torch, trimesh
from PIL import Image
from rembg import remove
from hy3dgen.texgen.pipelines import Hunyuan3DPaintPipeline, Hunyuan3DTexGenConfig
from hy3dgen.texgen.utils.dehighlight_utils import Light_Shadow_Remover
from hy3dgen.texgen.utils.multiview_utils import Multiview_Diffusion_Net
from hy3dgen.texgen.utils.uv_warp_utils import mesh_uv_wrap
from hy3dgen.texgen.differentiable_renderer.mesh_render import MeshRender

mesh_in, img_in, out = sys.argv[1], sys.argv[2], sys.argv[3]
t0 = time.time()


def stamp(msg):
    print("%6.0f s  RAM avail %.1f GB  VRAM %.1f GB  %s" % (time.time() - t0, avail_gb(), torch.cuda.memory_allocated() / 1e9, msg), flush=True)


img = Image.open(img_in).convert("RGB")
img = remove(img)                                   # RGBA: paint recenters on the alpha, grey background must go
mesh = trimesh.load(mesh_in, force="mesh")
print("image", img.size, img.mode, "mesh verts", len(mesh.vertices), "faces", len(mesh.faces), "bbox", mesh.bounds.round(3).tolist())

base = os.path.join(ROOT, "HuggingFaceHub", "tencent", "Hunyuan3D-2")
cfg = Hunyuan3DTexGenConfig(os.path.join(base, "hunyuan3d-delight-v2-0"), os.path.join(base, "hunyuan3d-paint-v2-0-turbo"), "hunyuan3d-paint-v2-0-turbo")
cfg.device = "cuda"
pipe = Hunyuan3DPaintPipeline.__new__(Hunyuan3DPaintPipeline)   # assemble by hand: one model resident at a time
pipe.config = cfg; pipe.models = {}
pipe.render = MeshRender(default_resolution=cfg.render_size, texture_size=cfg.texture_size)
stamp("renderer ready")

# ---- 1. delight (remove light/shadow from the concept), then free it
img = pipe.recenter_image(img)
delight_png = os.path.splitext(out)[0] + "_delight.png"
if os.path.exists(delight_png) and os.path.getmtime(delight_png) > os.path.getmtime(img_in):
    # delight only depends on the concept image, not on the mesh: reuse the cached result (loading the 3.3 GB fp32 delight
    # unet spikes RAM by ~5 GB and trips the watchdog on a 16 GB box with a browser open — 2026-09-12 #43)
    img = Image.open(delight_png).convert("RGBA")
    stamp("delight reused from " + os.path.basename(delight_png))
else:
    delight = Light_Shadow_Remover(cfg); delight.pipeline.to("cuda")
    stamp("delight loaded")
    img = delight(img)
    img.save(delight_png)
    del delight; gc.collect(); torch.cuda.empty_cache()
    stamp("delight done, freed")

# ---- 2. multiview paint
mv = Multiview_Diffusion_Net(cfg); mv.pipeline.to("cuda")
pipe.models["multiview_model"] = mv
stamp("multiview loaded")
mesh = mesh_uv_wrap(mesh)
pipe.render.load_mesh(mesh)
elevs, azims, weights = cfg.candidate_camera_elevs, cfg.candidate_camera_azims, cfg.candidate_view_weights
normal_maps = pipe.render_normal_multiview(elevs, azims, use_abs_coor=True)
position_maps = pipe.render_position_multiview(elevs, azims)
camera_info = [(((azim // 30) + 9) % 12) // {-20: 1, 0: 1, 20: 1, -90: 3, 90: 3}[elev] + {-20: 0, 0: 12, 20: 24, -90: 36, 90: 40}[elev]
               for azim, elev in zip(azims, elevs)]
multiviews = mv([img], normal_maps + position_maps, camera_info)
stamp("multiview diffusion done")
for i, v in enumerate(multiviews):
    v.save(os.path.splitext(out)[0] + "_view%d.png" % i)
    multiviews[i] = v.resize((cfg.render_size, cfg.render_size))
texture, mask = pipe.bake_from_multiview(multiviews, elevs, azims, weights, method=cfg.merge_method)
mask_np = (mask.squeeze(-1).cpu().numpy() * 255).astype(np.uint8)
texture = pipe.texture_inpaint(texture, mask_np)
pipe.render.set_texture(texture)
textured = pipe.render.save_mesh()
stamp("baked + inpainted")
textured.export(out)
print("OK", out, round(os.path.getsize(out) / 1e6, 2), "MB", "verts", len(textured.vertices), "faces", len(textured.faces),
      "bbox", textured.bounds.round(3).tolist())
print("VRAM peak %.1f GB   RAM min avail seen: run watchdog log" % (torch.cuda.max_memory_allocated() / 1e9))
