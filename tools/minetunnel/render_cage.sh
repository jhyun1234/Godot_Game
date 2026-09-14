#!/usr/bin/env bash
# 리프트 케이지를 스크립트로 빌드해 Documents/MineTunnel/Cage.blend 로 저장하고, 정거장 안에 세운 bright 렌더 2장을 build/ 에 뽑는다 (제안서 #21 A 단계).
#   bash tools/minetunnel/render_cage.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
mkdir -p build
out="$("$BLENDER" -b --python tools/minetunnel/build_cage.py -- "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[" || true
if ! echo "$out" | grep -q "^ok render.*b_gate"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback" -A8 | tail -40; exit 1
fi
ls -la build/cage_*.jpg
