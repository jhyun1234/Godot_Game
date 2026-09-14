# Patch Hunyuan3D-2.0 paint unet loader for 16GB-RAM boxes. Idempotent.
# Stock from_pretrained builds the 1.8B-param 2.5D unet in fp32 on the CPU (7.3 GB) and then torch.load()s the
# 7.3 GB .bin on top of it (14+ GB RAM) -> 2026-09-12 Windows bugcheck 0x7A (paging storm). Patched: build on the
# meta device (0 RAM), read the fp16 safetensors (3.7 GB, mmap), assign tensors without copying.
p = r"C:\AI\HY3D2\Hunyuan3D2_WinPortable\HuggingFaceHub\tencent\Hunyuan3D-2\hunyuan3d-paint-v2-0-turbo\unet\modules.py"
s = open(p, encoding="utf-8").read()
if "assign=True" in s:
    print("already patched"); raise SystemExit
old = """        unet = UNet2DConditionModel(**config)
        unet = UNet2p5DConditionModel(unet)
        unet_ckpt = torch.load(unet_ckpt_path, map_location='cpu', weights_only=True)
        unet.load_state_dict(unet_ckpt, strict=True)
        unet = unet.to(torch_dtype)
        return unet
"""
new = """        # ponytail: meta-device build + mmap safetensors + assign — RAM stays near 0 instead of 14 GB (16 GB box)
        with torch.device('meta'):
            unet = UNet2DConditionModel(**config)
            unet = UNet2p5DConditionModel(unet)
        # the .bin is the turbo checkpoint the stock loader uses; the sibling .safetensors is a DIFFERENT model (extra
        # IP-adapter keys, conv_in/attn_multiview weights differ far beyond fp16 rounding) — painting with it gave mud
        torch_dtype = torch.float16    # diffusers does not forward torch_dtype to custom unet classes -> fp32 default = 7.3 GB RAM
        import glob
        from safetensors.torch import load_file
        shards = sorted(glob.glob(os.path.join(pretrained_model_name_or_path, 'diffusion_pytorch_model.fp16.*.safetensors')))
        if shards:                      # fp16 shards converted from the .bin (convert_unet_fp16.py) — mmap, ~3.7 GB file-backed
            unet_ckpt = {}
            for sh in shards:
                unet_ckpt.update(load_file(sh, device='cpu'))
        else:                           # stock .bin: mapping the whole 7.3 GB fp32 file blows a 16 GB box — convert first
            raw = torch.load(unet_ckpt_path, map_location='cpu', weights_only=True, mmap=True)
            unet_ckpt = {k: v.to(torch_dtype) for k, v in raw.items()}
            del raw
        unet.load_state_dict(unet_ckpt, strict=True, assign=True)
        left = [n for n, t in list(unet.named_parameters()) + list(unet.named_buffers()) if t.is_meta]
        assert not left, 'tensors not in checkpoint stayed on meta: %s' % left[:5]
        unet = unet.to(torch_dtype)
        return unet
"""
assert s.count(old) == 1, "anchor not found"
open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("patched")
