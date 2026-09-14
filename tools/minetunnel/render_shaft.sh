#!/usr/bin/env bash
# 수갱 정거장 조각을 스크립트로 빌드해 Documents/MineTunnel/Shaft.blend 로 저장하고, bright 렌더 2장을 build/ 에 뽑는다 (제안서 #20 A 단계).
#   bash tools/minetunnel/render_shaft.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
mkdir -p build
out="$("$BLENDER" -b --python tools/minetunnel/build_shaft.py -- "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[" || true
if ! echo "$out" | grep -q "^ok render.*c_up"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback" -A8 | tail -40; exit 1
fi
ls -la build/shaft_*.jpg
