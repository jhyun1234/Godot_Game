# run.py - Scripting 탭에서 이 파일 하나만 열어 실행해도 됨. 순서: 빌드 -> 렌더 (내보내기는 필요할 때 EXPORT=True)
import os
PROJ = os.path.join(os.path.expanduser("~"), "Documents", "MineTunnel", "scripts")
BUILD, RENDER, EXPORT = True, True, False
for name, on in (("build_tunnel.py", BUILD), ("render_preview.py", RENDER), ("export_godot.py", EXPORT)):
    if on:
        print("==>", name); exec(compile(open(os.path.join(PROJ, name), encoding="utf-8").read(), name, "exec"), {})
