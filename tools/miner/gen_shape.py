"""Image -> GLB via the running Hunyuan3D-2.1 gradio server. usage: gen_shape.py <image> <out.glb> [steps] [octree] [seed]"""
import sys, shutil
from gradio_client import Client, handle_file

img, out = sys.argv[1], sys.argv[2]
steps = int(sys.argv[3]) if len(sys.argv) > 3 else 30
octree = int(sys.argv[4]) if len(sys.argv) > 4 else 256
seed = int(sys.argv[5]) if len(sys.argv) > 5 else 1234

c = Client("http://127.0.0.1:8080/", verbose=False)
res = c.predict(image=handle_file(img), mv_image_front=None, mv_image_back=None, mv_image_left=None, mv_image_right=None,
                steps=steps, guidance_scale=5.0, seed=seed, octree_resolution=octree,
                check_box_rembg=True, num_chunks=8000, randomize_seed=False, api_name="/shape_generation")
file_out, _html, stats, seed_used = res
src = file_out if isinstance(file_out, str) else (file_out.get("path") or file_out.get("value")) if isinstance(file_out, dict) else file_out[0]
if not src:   # gradio 5: the file may come back without a path — fall back to the newest save_dir/<uuid>/white_mesh.glb
    import glob, os
    src = max(glob.glob(r"C:\AI\HY3D2\Hunyuan3D2_WinPortable\Hunyuan3D-2.1\save_dir\*\white_mesh.glb"), key=os.path.getmtime)
shutil.copy(src, out)
print("OK", out, "seed", seed_used)
print(stats)
