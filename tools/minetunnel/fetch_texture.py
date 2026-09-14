# -*- coding: utf-8 -*-
"""Poly Haven 텍스처 내려받기 (Blender 없이). 제안서 #27 수정 A 단계(텍스처 후보 비교)와 export_godot.py 의 rock=/floor= 인자가 쓴다.

    python tools/minetunnel/fetch_texture.py <id> [<id> ...] [res=2k]

Documents/MineTunnel/textures/<id>/<id>_{Diffuse,nor_gl,Rough}.jpg 로 받는다 (build_tunnel.py 와 같은 자리·이름). 있으면 건너뛴다.
"""
import json, os, sys, urllib.request

TEX_DIR = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel", "textures")
MAPS = ["Diffuse", "nor_gl", "Rough"]


def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "mine-tunnel-build"})
    return urllib.request.urlopen(req, timeout=60).read()


def fetch(asset, res="2k"):
    files = json.loads(_get(f"https://api.polyhaven.com/files/{asset}"))
    out = []
    for m in MAPS:
        if m not in files:
            print("!! %s 에 %s 없음" % (asset, m))
            continue
        entry = files[m].get(res) or files[m].get("1k")
        fmt = "jpg" if "jpg" in entry else list(entry.keys())[0]
        path = os.path.join(TEX_DIR, asset, f"{asset}_{m}.{fmt}")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not (os.path.exists(path) and os.path.getsize(path) > 500):
            with open(path, "wb") as f:
                f.write(_get(entry[fmt]["url"]))
        out.append(path)
    print("ok %s %s (%d장)" % (asset, res, len(out)))
    return out


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("res=")]
    res = next((a[4:] for a in sys.argv[1:] if a.startswith("res=")), "2k")
    for a in args:
        fetch(a, res)
