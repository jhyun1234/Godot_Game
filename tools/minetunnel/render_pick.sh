#!/usr/bin/env bash
# 곡괭이 뷰모델을 스크립트로 빌드해 Documents/MineTunnel/Pick.blend 로 저장하고, 갱도 안 눈높이에 든 bright 렌더 1장을 build/ 에 뽑는다 (제안서 #23 A 단계).
#   bash tools/minetunnel/render_pick.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
mkdir -p build
out="$("$BLENDER" -b --python tools/minetunnel/build_pick.py -- "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[" || true
if ! echo "$out" | grep -q "^ok render.*pick_a2_hand"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback" -A8 | tail -40; exit 1
fi
ls -la build/pick_*.jpg
