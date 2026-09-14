#!/usr/bin/env bash
# 바뀐 구간만 (#37). 임포트 -> 소스 검사(헤드리스, 값 검사) -> exe 익스포트 -> 봇 --only <구간> -> 화면 검수.
#   bash tools/quick.sh miner            # 구간 하나 (base maze cart repair lamp move miner)
#   bash tools/quick.sh lamp,miner       # 여럿
# 약 1분. 커밋 전에는 bash tools/build.sh 전체를 한 번 돈다 — 구간 사이 상태·다른 구간의 회귀는 여기서 안 보인다.
set -e
STAGES="${1:?구간 이름을 줘라: base maze cart repair lamp move miner}"
GODOT="/c/Users/anjyo/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe"
EXE="build/NewGame.exe"
cd "$(dirname "$0")/.."
mkdir -p build
touch build/.gdignore

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

echo "== 임포트"
timeout 600 "$GODOT" --headless --import --path . >/dev/null 2>&1 || true
run_stage "소스 검사" CHECK timeout 180 "$GODOT" --headless --path . -- --check
echo "== Windows 익스포트"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE" >/dev/null 2>&1
OUT="$(pwd -W)/build"
rm -f build/play_*.png
run_stage "플레이 봇 --only $STAGES (배포물, 창 모드)" PLAY timeout 300 "./$EXE" -- --play "$OUT" --only "$STAGES"
ls build/play_*.png
PY=""
for c in python python3 py; do
	if command -v "$c" >/dev/null 2>&1; then PY="$c"; break; fi
done
if [ -n "$PY" ]; then
	echo "== 화면 검수 (있는 캡처만 기준과 비교)"
	QC_PARTIAL=1 "$PY" tools/qc.py report || echo "!! qc.py 가 실패했다"
fi
echo "== 완료 (--only $STAGES). 커밋 전 build.sh 전체 1회."
