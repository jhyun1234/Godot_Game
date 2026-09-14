"""Image -> GLB via the official microsoft/TRELLIS.2 Hugging Face Space (ZeroGPU, free, MIT-licensed outputs).
usage: gen_trellis2.py <image.png> <out.glb> [resolution 512|1024|1536] [seed] [decimation_target] [texture_size]
Quota: unauthenticated ~2 min GPU/day, free account 3.5 min (HF_TOKEN env), PRO 25 min. A 1024 run is ~20-60 s of GPU."""
import sys, os, shutil, time
from gradio_client import Client, handle_file

img, out = sys.argv[1], sys.argv[2]
res = sys.argv[3] if len(sys.argv) > 3 else "1024"
seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1234
decim = int(sys.argv[5]) if len(sys.argv) > 5 else 300000
tex = int(sys.argv[6]) if len(sys.argv) > 6 else 2048
t0 = time.time()
tok = os.environ.get("HF_TOKEN")
tok_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hf_token.txt")   # the user saves the token here (git 밖); Claude never types it
if not tok and os.path.exists(tok_file):
    tok = open(tok_file, encoding="utf-8").read().strip()
print("token:", "yes" if tok else "NO (unauthenticated: ~2 min/day quota)", flush=True)
c = Client("microsoft/TRELLIS.2", hf_token=tok, verbose=False)
c.predict(api_name="/start_session")
pre = c.predict(input=handle_file(img), api_name="/preprocess_image")
print("preprocessed %.0f s" % (time.time() - t0), flush=True)
c.predict(image=handle_file(pre["path"] if isinstance(pre, dict) else pre), seed=seed, resolution=res, api_name="/image_to_3d")
print("generated %.0f s" % (time.time() - t0), flush=True)
glb, dl = c.predict(decimation_target=decim, texture_size=tex, api_name="/extract_glb")
src = dl if isinstance(dl, str) else glb
shutil.copy(src, out)
print("OK", out, round(os.path.getsize(out) / 1e6, 2), "MB", "res", res, "seed", seed, "%.0f s" % (time.time() - t0))
