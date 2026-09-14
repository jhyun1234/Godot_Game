#!/usr/bin/env bash
# 갱도 모듈을 스크립트로 다시 빌드해 Documents/MineTunnel/MineTunnel.blend 에 저장하고, bright 렌더 2장(사람 캡슐 4개 포함)을 build/ 에 뽑는다 (제안서 #22 A 단계).
# 원본(4×4×8 판)은 MineTunnel_4x4.blend 로 남겨 둔다 — 없으면 먼저 사본을 뜬다.
#   bash tools/minetunnel/render_tunnel.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
MT="/c/Users/anjyo/Documents/MineTunnel"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
[ -f "$MT/MineTunnel_4x4.blend" ] || cp "$MT/MineTunnel.blend" "$MT/MineTunnel_4x4.blend"
mkdir -p build
out="$("$BLENDER" -b "$MT/MineTunnel.blend" --python tools/minetunnel/build_tunnel.py -- save "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[" || true
if ! echo "$out" | grep -q "^ok render.*b_cap"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback" -A8 | tail -40; exit 1
fi
ls -la build/tunnel_*.jpg
