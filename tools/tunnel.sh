#!/usr/bin/env bash
# 갱도 조각 시안 (제안서 #18). Blender 헤드리스로 tools/tunnel.py 를 돌린다.
#
#   bash tools/tunnel.sh              시안 A/B/C 렌더 -> build/tunnel_*.png + build/tunnel_sheet.png
#   bash tools/tunnel.sh --export     + assets/generated/tunnel/ 로 내보내기 (승인 뒤에만)
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
out="$("$BLENDER" --background --python tools/tunnel.py -- "$@" 2>&1)" || true
echo "$out" | grep -E "^ok " || true
if ! echo "$out" | grep -q "^ok tunnel C"; then
	echo "!! 갱도 시안 실패"; echo "$out" | grep -iE "error|traceback" -A3 | tail -30; exit 1
fi
# 세 장을 한 장으로 (라벨 붙여)
python - <<'EOF'
from PIL import Image, ImageDraw
ims = [Image.open("build/tunnel_%s.png" % v).convert("RGB") for v in "ABC"]
w, h = ims[0].size
sheet = Image.new("RGB", (w * 3 + 40, h + 60), (20, 20, 22))
d = ImageDraw.Draw(sheet)
labels = ["A  bump 0.08  (low relief)", "B  bump 0.25  (high relief)", "C  bump 0.25 + wet coat"]
for i, im in enumerate(ims):
    sheet.paste(im, (10 + i * (w + 10), 50))
    d.text((14 + i * (w + 10), 18), labels[i], fill=(230, 230, 230))
sheet.save("build/tunnel_sheet.png")
print("ok sheet build/tunnel_sheet.png")
EOF
