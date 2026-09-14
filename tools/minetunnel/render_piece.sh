#!/usr/bin/env bash
# 조각 카탈로그 13종을 스크립트로 빌드해 Documents/MineTunnel/Pieces.blend 로 저장하고, bright 렌더 9장을 build/ 에 뽑는다 (제안서 #26 A 단계).
#   bash tools/minetunnel/render_piece.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
mkdir -p build
out="$("$BLENDER" -b --python tools/minetunnel/build_piece.py -- "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[|!!" || true
if ! echo "$out" | grep -q "^ok render 9"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback|assert" -A8 | tail -60; exit 1
fi
ls -la build/piece_*.jpg
