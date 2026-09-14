#!/usr/bin/env bash
# 임포트 -> 소스 검사 -> exe 익스포트 -> 배포물 검사 -> 플레이 봇 -> 화면 검수.
#   bash tools/build.sh          # 전부
#   bash tools/build.sh --shot   # + 배포물 스크린샷 build/shot.png (168px 축소본도)
#   QC=0 bash tools/build.sh     # 화면 검수만 건너뛴다 (평소에는 쓰지 마라)
#
# 소스에서만 통과한 검사는 통과가 아니다. 중간 두 단계는 배포물 자체를 돌린다.
# 그리고 숫자 검사만 통과한 것도 통과가 아니다 - 마지막 단계가 화면을 본다.
set -e
GODOT="/c/Users/anjyo/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
EXE="build/NewGame.exe"
cd "$(dirname "$0")/.."
mkdir -p build
touch build/.gdignore

# 출력에서 ok / FAIL 만 보여주고, 지정한 PASS 표시가 없으면 실패로 본다.
run_stage() {
	local label="$1" want="$2"; shift 2
	echo "== $label"
	local out
	out="$("$@" 2>&1)" || true
	echo "$out" | grep -E "^(ok|FAIL|!!)" || true
	if echo "$out" | grep -q "^FAIL"; then echo "!! $label 실패"; exit 1; fi
	if ! echo "$out" | grep -q "^$want PASS"; then
		echo "!! $label 이 '$want PASS' 를 출력하지 않았다"
		echo "$out" | tail -20
		exit 1
	fi
}

echo "== 임포트 (--import: class_name 캐시. --quit 는 캐시를 안 만들어 멈춘다)"
timeout 600 "$GODOT" --headless --import --path . >/dev/null 2>&1 || true

run_stage "소스 검사" CHECK timeout 180 "$GODOT" --headless --path . -- --check

echo "== Windows 익스포트"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE" >/dev/null 2>&1
ls -la "$EXE"

run_stage "배포물 검사" CHECK timeout 180 "./$EXE" --headless -- --check

# 봇은 창 모드로 돈다 — 실제 마우스·키 이벤트가 게임까지 닿는지 보는 것이 목적이다.
# 배포물에서 상대 경로는 res:// 로 읽혀 저장이 안 된다. 절대 경로를 넘긴다.
OUT="$(pwd -W)/build"
# 지난 실행의 캡처를 지운다. 봇이 더 안 찍는 이름이 남으면 qc.py 가 그걸 묶음에 섞는다.
rm -f build/play_*.png
# 봇 한 바퀴 184 s (#36) → 300 s 넘음 (#55, 22_lift_gate 에서 잘림). 검사가 늘 때마다 길어진다 — 넘으면 PASS 줄 없이 죽어 "PLAY PASS 를 출력하지 않았다"로 보인다
run_stage "플레이 봇 (배포물, 창 모드)" PLAY timeout 600 "./$EXE" -- --play "$OUT"
ls build/play_*.png

# 화면 검수. 플레이 봇이 찍어 놓고 아무도 안 보던 캡처를 볼 수 있는 형태로 만든다.
# 캡처가 달라졌다고 실패로 만들지 않는다 - 눈에 보이는 작업이면 달라지는 게 정상이고,
# 매번 실패하면 아무도 안 읽게 된다. 대신 무엇이 달라졌고 어느 파일을 열어야 하는지 남긴다.
if [ "${QC:-1}" = "1" ]; then
	PY=""
	for c in python python3 py; do
		if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
	done
	if [ -z "$PY" ]; then
		echo "!! python 을 못 찾았다 - 화면 검수를 건너뛴다"
	else
		echo "== 화면 검수 (tools/qc.py)"
		"$PY" tools/qc.py report || echo "!! qc.py 가 실패했다 - pip install pillow numpy 확인"
	fi
fi

if [ "${1:-}" = "--shot" ]; then
	echo "== 스크린샷 (배포물)"
	timeout 120 "./$EXE" -- --shot "$(pwd -W)/build/shot.png" >/dev/null 2>&1 || true
	ls -la build/shot.png
	if command -v ffmpeg >/dev/null; then
		ffmpeg -y -loglevel error -i build/shot.png -vf scale=168:-1 build/shot_168.png
		ls -la build/shot_168.png
	fi
fi
echo "== 완료"
echo ""
echo "  숫자 검사는 여기까지다. 화면은 build/qc/ 안에 있다."
echo "  그 이미지를 열어 보기 전에는 '통과'라고 보고하지 않는다. (CLAUDE.md 11)"
