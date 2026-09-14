#!/usr/bin/env bash
# MineTunnel 조각들을 Godot 용 glTF 로 다시 뽑는다 (제안서 #19 모듈, #20 정거장·피트). 산출물이 커밋돼 있어 평소에는 돌릴 일이 없다.
#   bash tools/minetunnel/export.sh                       # 세 조각 전부, 갱목 dark_wooden_planks
#   bash tools/minetunnel/export.sh timber=rough_wood:1.4  # 갱목 텍스처만 Poly Haven 의 다른 것으로 (스케일 생략 가능)
#   bash tools/minetunnel/export.sh timber=none            # .blend 그대로 (medieval_wood)
#   bash tools/minetunnel/export.sh timber=dark_wooden_planks rock=<id>[:스케일] floor=<id>   # 벽·바닥 텍스처 (#27 수정. 인자를 주면 기본값 대신)
# 조각:
#   MineTunnel.blend  -> mine_tunnel_module.gltf   (build_tunnel.py 로 만든 .blend. 고치려면 Documents/MineTunnel 에서 다시 빌드·저장)
#   Shaft.blend       -> shaft_station.gltf (xcoll=PIT) + shaft_pit.gltf (coll=PIT)   (build_shaft.py 산출물. bash tools/minetunnel/render_shaft.sh)
#   Cage.blend        -> lift_cage.gltf (coll=CAGE)   (build_cage.py 산출물, #21. bash tools/minetunnel/render_cage.sh)
#   Pick.blend        -> pick.gltf (coll=PICK)        (build_pick.py 산출물, #23. bash tools/minetunnel/render_pick.sh)
#   Face.blend        -> mine_face.gltf (coll=FACE_WALL) + ore.gltf (coll=ORE) + mine_chips.gltf (coll=CHIPS)   (build_face.py, #23. render_face.sh)
#   Props.blend       -> mine_props.gltf (coll=PROPS)   (build_props.py, #27 소품 9종)
#   Pieces.blend      -> piece_*.gltf 9 (coll=PC_*) + rail_*.gltf 4 (coll=RAIL_*)   (build_piece.py, #26. render_piece.sh). 카탈로그 표는 scripts/PieceCatalog.gd
# 스물한 조각을 한 폴더에 뽑는다 — 재질·텍스처가 같아 파일 이름이 같고, 한 벌만 남는다.
set -e
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
MT="/c/Users/anjyo/Documents/MineTunnel"
OUT_DIR="assets/generated/tunnel"
cd "$(dirname "$0")/../.."
[ -x "$BLENDER" ] || { echo "!! Blender 를 못 찾았다: $BLENDER"; exit 1; }
for b in MineTunnel Shaft Cage Pick Face Pieces Props Cart; do [ -f "$MT/$b.blend" ] || { echo "!! .blend 를 못 찾았다: $MT/$b.blend"; exit 1; }; done
# 기본 갱목 텍스처. .blend 의 medieval_wood 는 "오래된 느낌이 없다"(#19 2차 판정) → dark_wooden_planks (Poly Haven CC0).
# 벽은 rock_face_04 2K (#27 수정 A 판정, 사용자 선택). 바닥은 .blend 그대로(brown_mud_rocks_01)지만 2K 로 다시 받는다.
[ $# -eq 0 ] && set -- "timber=dark_wooden_planks" "rock=rock_face_04" "floor=brown_mud_rocks_01"
[ "$1" = "timber=none" ] && shift
# ONLY=<이름> 이면 그 조각 하나만 뽑고 폴더는 안 지운다 (#29: build_piece.py 가 B 값을 잃어 전체 재내보내기는 방·대피소를 되돌린다 — HANDOFF -7)
[ -z "$ONLY" ] && rm -rf "$OUT_DIR"
export_piece() {   # <blend> <name> [추가 인자...]
	local blend="$1" name="$2"; shift 2
	[ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && return 0
	local out
	out="$("$BLENDER" -b "$MT/$blend.blend" --python tools/minetunnel/export_godot.py -- "$OUT_DIR" "name=$name" "$@" 2>&1)" || true
	echo "$out" | grep -E "^ok " || true
	if ! echo "$out" | grep -q "^ok export"; then
		echo "!! 내보내기 실패: $name"; echo "$out" | grep -iE "error|traceback" -A5 | tail -40; exit 1
	fi
}
export_piece MineTunnel mine_tunnel_module "$@"
export_piece Shaft shaft_station xcoll=PIT "$@"
export_piece Shaft shaft_pit coll=PIT "$@"
export_piece Cage lift_cage coll=CAGE "$@"
export_piece Pick pick coll=PICK "$@"
export_piece Face mine_face coll=FACE_WALL "$@"
export_piece Face ore coll=ORE "$@"
export_piece Face mine_chips coll=CHIPS "$@"
export_piece Pieces piece_straight coll=PC_straight "$@"
export_piece Pieces piece_curve coll=PC_curve "$@"
export_piece Pieces piece_t coll=PC_t "$@"
export_piece Pieces piece_cross coll=PC_cross "$@"
export_piece Pieces piece_cap coll=PC_cap "$@"
export_piece Pieces piece_neck coll=PC_neck "$@"
export_piece Pieces piece_room_2 coll=PC_room_2 "$@"
export_piece Pieces piece_room_1 coll=PC_room_1 "$@"
export_piece Pieces piece_refuge coll=PC_refuge "$@"
export_piece Pieces rail_straight coll=RAIL_straight "$@"
export_piece Pieces rail_curve coll=RAIL_curve "$@"
export_piece Pieces rail_turnout coll=RAIL_turnout "$@"
export_piece Pieces rail_end coll=RAIL_end "$@"
export_piece Props mine_props coll=PROPS "$@"          # 소품 9종 한 파일 (#27). 조립기가 자식을 복제해 뿌린다
export_piece Cart mine_cart coll=CART "$@"            # 광차 (#29). 조립기가 순환선 위에 CART_COUNT 대
# 텍스처가 정말 1K 인지, 조명이 정말 빠졌는지 산출물에서 확인한다
PYTHONIOENCODING=utf-8 python - <<'PY'
import glob, json, os
from PIL import Image
imgs = [f for f in glob.glob("assets/generated/tunnel/textures/*") if not f.endswith(".import")]
big = [(f, Image.open(f).size) for f in imgs if max(Image.open(f).size) > 2048]
big2k = [f for f in imgs if max(Image.open(f).size) > 1024]
print("ok 텍스처 %d장, 2K 초과 %d장, 2K %d장(벽·바닥 6장이어야 한다: %s)" % (len(imgs), len(big), len(big2k), sorted(os.path.basename(f) for f in big2k)))
assert len(big2k) == 6, big2k
bad = 0
for gp in sorted(glob.glob("assets/generated/tunnel/*.gltf")):
    g = json.load(open(gp, encoding="utf-8"))
    lights = "KHR_lights_punctual" in g.get("extensionsUsed", [])
    print("ok %s: 노드 %d, 메시 %d, 재질 %d, 조명 확장 %s" % (gp.split("/")[-1], len(g["nodes"]), len(g["meshes"]), len(g["materials"]), "있음!" if lights else "없음"))
    bad += lights
assert not big and not bad
PY
# Godot 임포트 설정. 헤드리스 임포트는 텍스처를 무압축·밉맵 없음으로 들여온다(에디터의 detect_3d 를 안 밟는다) —
# 멀리서 반짝인다. 한 번 임포트해 .import 를 만들고, VRAM 압축 + 밉맵 (+노멀맵) 으로 고쳐 다시 임포트한다.
GODOT="/c/Users/anjyo/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
timeout 600 "$GODOT" --headless --import --path . >/dev/null 2>&1 || true
PYTHONIOENCODING=utf-8 python - <<'PY'
import glob, io
n = 0
for p in glob.glob("assets/generated/tunnel/textures/*.import"):
    s = io.open(p, encoding="utf-8").read()
    t = s.replace("compress/mode=0", "compress/mode=2").replace("mipmaps/generate=false", "mipmaps/generate=true")
    if "nor_gl" in p: t = t.replace("compress/normal_map=0", "compress/normal_map=1")
    if t != s: io.open(p, "w", encoding="utf-8", newline="\n").write(t); n += 1
print("ok 텍스처 import 설정 %d장 고침 (VRAM 압축 + 밉맵)" % n)
PY
timeout 600 "$GODOT" --headless --import --path . >/dev/null 2>&1 || true
ls -la "$OUT_DIR"
du -sh "$OUT_DIR"
