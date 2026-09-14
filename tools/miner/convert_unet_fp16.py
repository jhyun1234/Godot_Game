"""One-time: Hunyuan3D-2.0 paint-turbo unet .bin (fp32, 7.3 GB) -> 4 fp16 safetensors shards, chunked so the mapped
working set stays ~3 GB on a 16 GB box. patch_unet_lowram.py makes the loader read the shards. Idempotent."""
import torch, gc, os, psutil
from safetensors.torch import save_file
d = r"C:\AI\HY3D2\Hunyuan3D2_WinPortable\HuggingFaceHub\tencent\Hunyuan3D-2\hunyuan3d-paint-v2-0-turbo\unet"
src = os.path.join(d, "diffusion_pytorch_model.bin")
if os.path.exists(os.path.join(d, "diffusion_pytorch_model.fp16.3.safetensors")):
    print("already converted"); raise SystemExit
keys = list(torch.load(src, map_location="cpu", weights_only=True, mmap=True).keys()); gc.collect()
K = 4; n = (len(keys) + K - 1) // K
for i in range(K):
    part = keys[i * n:(i + 1) * n]
    raw = torch.load(src, map_location="cpu", weights_only=True, mmap=True)
    sd = {k: raw[k].to(torch.float16).contiguous() for k in part}
    del raw; gc.collect()
    out = os.path.join(d, "diffusion_pytorch_model.fp16.%d.safetensors" % i)
    save_file(sd, out, metadata={"format": "pt"})
    print("shard", i, len(sd), "tensors", round(os.path.getsize(out) / 1e9, 2), "GB  RAM avail", round(psutil.virtual_memory().available / 1e9, 1))
    del sd; gc.collect()
