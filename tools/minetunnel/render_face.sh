#!/usr/bin/env bash
# 끝막이 벽·광석·자갈을 스크립트로 빌드해 Documents/MineTunnel/Face.blend 로 저장하고, 갱도 모듈 끝에 세운 bright 렌더 2장을 build/ 에 뽑는다 (제안서 #23 A 단계).
#   bash tools/minetunnel/render_face.sh
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
mkdir -p build
out="$("$BLENDER" -b --python tools/minetunnel/build_face.py -- "render=$(cygpath -w "$PWD/build")" 2>&1)" || true
echo "$out" | grep -E "^ok |^\[" || true
if ! echo "$out" | grep -q "^ok render.*c_ore"; then
	echo "!! 빌드/렌더 실패"; echo "$out" | grep -iE "error|traceback" -A8 | tail -40; exit 1
fi
ls -la build/face_*.jpg
