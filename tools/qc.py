#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""tools/qc.py — 화면 검수. 숫자 검사가 못 보는 것을 눈으로 넘긴다.

`tools/build.sh` 의 검사 36개는 "값이 바뀌었나"만 잰다. 2일차의 곡괭이 버그가
그 검사를 전부 통과한 이유가 그거였다 — `돌긴 돌았다`는 통과였고, 어느 쪽으로
돌았는지는 아무도 안 물었다. 화면을 봐야 잡히는 종류였다.

이 도구는 플레이 봇이 이미 찍어 놓고 아무도 안 보던 `build/play_*.png` 를
**사람과 Claude 가 실제로 볼 수 있는 형태**로 만든다. 그리고 기준 이미지와
비교해서 "저번이랑 뭐가 달라졌는지"를 먼저 말해 준다.

    python tools/qc.py sheet                 캡처 전부를 라벨 붙은 한 장으로
    python tools/qc.py seq                   연속 캡처를 순서대로 + 궤적 한 장으로
    python tools/qc.py small                 168px 축소본 모음 (실루엣·가독성)
    python tools/qc.py golden save [메모]     지금 캡처를 기준으로 저장
    python tools/qc.py golden check          기준과 비교 -> 달라진 캡처 표 + 히트맵
    python tools/qc.py strip <영상> <시작> <끝> [장수]   연속 동작을 촘촘히
    python tools/qc.py trail <영상> <시작> <끝>          움직인 궤적을 한 장에
    python tools/qc.py report                sheet + small + golden check 한 번에

**연속 캡처**: `play_08_swing_0.png` ~ `_4.png` 처럼 이름 끝을 `_숫자` 로 맞추면
한 동작으로 묶어서 순서대로 붙이고, 궤적까지 한 장으로 합쳐 준다. 움직이는 중간에만
보이는 문제(어느 쪽으로 도는지)는 한 장짜리 캡처로는 절대 안 잡힌다.

출력은 전부 `build/qc/` 에 떨어진다 (build/ 는 .gitignore 대상 — 언제든 다시 만든다).
기준 이미지만 `tools/qc_golden/` 에 두고 git 에 커밋한다. 그래야 커밋 사이 비교가 된다.

의존: Pillow, numpy.  strip/trail 만 ffmpeg 를 쓴다.
    pip install pillow numpy
"""
import glob
import os
import shutil
import subprocess
import sys

# Windows 콘솔은 cp949 라서 "—" 하나에 UnicodeEncodeError 로 죽는다. 출력은 utf-8 로 고정.
for _st in (sys.stdout, sys.stderr):
    if hasattr(_st, "reconfigure"):
        _st.reconfigure(encoding="utf-8", errors="replace")

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow 가 없다.  pip install pillow numpy")
try:
    import numpy as np
except ImportError:
    sys.exit("numpy 가 없다.  pip install pillow numpy")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "build")
OUT = os.path.join(ROOT, "build", "qc")
GOLDEN = os.path.join(ROOT, "tools", "qc_golden")

# 달라졌다고 볼 기준. 픽셀 하나가 이만큼 넘게 변하고(TOL),
# 그런 픽셀이 전체의 이 비율을 넘으면(RATIO) 보고한다.
TOL = 12
RATIO = 0.004

BG = (18, 19, 24)
FG = (236, 240, 245)
DIM = (128, 136, 148)
HOT = (255, 138, 61)
OK = (53, 208, 90)


# ---------------------------------------------------------------- 공통

def _font(size):
    for p in (r"C:\Windows\Fonts\malgun.ttf", r"C:\Windows\Fonts\segoeui.ttf",
              r"C:\Windows\Fonts\arial.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                pass
    return ImageFont.load_default()


def shots(pattern="play_*.png"):
    fs = sorted(glob.glob(os.path.join(SHOTS, pattern)))
    if not fs:
        sys.exit("%s 에 %s 가 없다. 먼저 `bash tools/build.sh` 를 돌려라." % (SHOTS, pattern))
    return fs


def label(path):
    """play_08_swing.png -> 08_swing"""
    n = os.path.basename(path)
    return n[5:-4] if n.startswith("play_") else os.path.splitext(n)[0]


def groups(files):
    """이름 끝이 `_숫자` 면 한 동작으로 묶는다.

    play_08_swing_0.png ~ _4.png  ->  ("08_swing", [5장])
    play_02_wall.png              ->  ("02_wall",  [1장])
    반환 순서는 파일 순서를 따른다."""
    out, seen = [], {}
    for f in files:
        lab = label(f)
        i = lab.rfind("_")
        key, idx = (lab[:i], lab[i + 1:]) if i > 0 else (lab, "")
        if not idx.isdigit():
            key = lab
        if key in seen:
            seen[key].append(f)
        else:
            seen[key] = [f]
            out.append(key)
    # `_10` 이 `_2` 앞에 오지 않게 숫자로 정렬한다. 10장 넘는 동작(붕괴 16장)에서 걸렸다.
    def order(f):
        lab = label(f)
        i = lab.rfind("_")
        return int(lab[i + 1:]) if i > 0 and lab[i + 1:].isdigit() else -1
    return [(k, sorted(seen[k], key=order)) for k in out]


def trail_of(paths, thresh=26):
    """첫 장을 어둡게 깔고, 뒤 장에서 움직인 자리를 색으로 칠해 한 장에 겹친다.
    이른 시점=진한 주황, 늦은 시점=노랑. 어느 쪽으로 움직였는지가 한눈에 보인다."""
    base = np.asarray(Image.open(paths[0]).convert("RGB"), dtype=np.float32)
    canvas = base * 0.30
    for i, f in enumerate(paths[1:], 1):
        cur = np.asarray(Image.open(f).convert("RGB"), dtype=np.float32)
        if cur.shape != base.shape:
            continue
        mask = np.abs(cur - base).max(axis=2) > thresh
        k = i / max(1, len(paths) - 1)
        col = np.array([255, 110 + 130 * k, 40 + 20 * k], dtype=np.float32)
        a = 0.35 + 0.5 * k
        canvas[mask] = canvas[mask] * (1 - a) + col * a
    return Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8))


def grid(items, cols, cell_w, pad=14, cap_h=26, title=None):
    """items: [(PIL.Image, 캡션, 캡션색)] -> 타일 한 장."""
    f = _font(17)
    ft = _font(24)
    scaled = []
    for im, cap, col in items:
        h = max(1, round(im.height * cell_w / im.width))
        scaled.append((im.resize((cell_w, h), Image.LANCZOS), cap, col))
    cell_h = max(im.height for im, _, _ in scaled)
    rows = (len(scaled) + cols - 1) // cols
    top = 0 if not title else 46
    W = pad + cols * (cell_w + pad)
    H = top + pad + rows * (cell_h + cap_h + pad)
    sheet = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(sheet)
    if title:
        d.text((pad, 14), title, font=ft, fill=FG)
    for i, (im, cap, col) in enumerate(scaled):
        x = pad + (i % cols) * (cell_w + pad)
        y = top + pad + (i // cols) * (cell_h + cap_h + pad)
        sheet.paste(im, (x, y))
        d.rectangle([x - 1, y - 1, x + cell_w, y + im.height], outline=(52, 58, 70))
        d.text((x + 2, y + im.height + 5), cap, font=f, fill=col)
    return sheet


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, name)
    img.save(p)
    return p


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


QUIET = False          # report 가 켠다. 개별 명령이 각자 안내를 찍지 않게 한다.
SEEN = []              # 눌러 모은 "열어야 할 파일" 목록


def look_at(paths):
    """Claude 가 어떤 파일을 이미지로 열어야 하는지 명시한다. 이게 이 도구의 핵심이다."""
    for p in paths:
        if p not in SEEN:
            SEEN.append(p)
    if QUIET:
        return
    print("")
    print("눈으로 확인할 것 — 아래 파일을 이미지로 열어라:")
    for p in paths:
        print("  %s" % rel(p))


# ---------------------------------------------------------------- sheet

def cmd_sheet(_):
    fs = shots()
    gs = groups(fs)
    items = []
    for key, files in gs:
        cap = key if len(files) == 1 else "%s  (x%d seq)" % (key, len(files))
        items.append((Image.open(files[0]).convert("RGB"), cap,
                      DIM if len(files) == 1 else HOT))
    p = save(grid(items, 4, 420,
                  title="play captures   %d shots / %d actions" % (len(fs), len(gs))), "sheet.png")
    print("캡처 %d장 (%d동작) -> %s" % (len(fs), len(gs), rel(p)))
    look_at([p])
    return p


# ---------------------------------------------------------------- seq

def cmd_seq(_):
    """연속 캡처를 순서대로 붙이고, 궤적을 한 장으로 합친다.

    한 장짜리 캡처는 "지금 어떻게 생겼나"만 답한다. 어느 쪽으로 움직였는지는
    못 답한다 - 2일차의 곡괭이가 그래서 통과했다. 순서대로 늘어놓고 궤적을
    겹쳐야 방향이 보인다."""
    gs = [(k, v) for k, v in groups(shots()) if len(v) >= 2]
    if not gs:
        print("연속 캡처가 없다. 움직이는 동작은 play_NN_이름_0.png ~ _4.png 로")
        print("여러 장 찍어야 중간에만 보이는 문제가 잡힌다. (봇 쪽 작업 - 제안서 필요)")
        return []
    made = []
    for key, files in gs:
        items = [(Image.open(f).convert("RGB"), "%d" % i, DIM)
                 for i, f in enumerate(files)]
        n = min(len(files), 6)
        made.append(save(grid(items, n, 300, pad=8, cap_h=20,
                              title="%s   %d frames in order  ->  trail_%s.png" % (key, len(files), key)),
                         "seq_%s.png" % key))
        made.append(save(trail_of(files),
                         "trail_%s.png" % key))
        print("%s  %d장 -> seq_%s.png / trail_%s.png" % (key, len(files), key, key))
    print("   trail 은 진한 주황=이른 시점, 노랑=늦은 시점. 어느 쪽으로 움직였는지를 본다.")
    look_at(made)
    return made


# ---------------------------------------------------------------- small

def cmd_small(_):
    """168px 로 줄여서 본다. 실루엣이 안 읽히면 화면이 지저분한 것이다."""
    fs = shots()
    items = [(Image.open(f).convert("RGB"), label(f), DIM) for f in fs]
    p = save(grid(items, 6, 168, pad=10, cap_h=22,
                  title="168px  (silhouette / readability)"), "small.png")
    print("축소본 %d장 -> %s" % (len(fs), rel(p)))
    look_at([p])
    return p


# ---------------------------------------------------------------- golden

def cmd_golden(argv):
    sub = argv[0] if argv else "check"
    if sub == "save":
        os.makedirs(GOLDEN, exist_ok=True)
        for f in glob.glob(os.path.join(GOLDEN, "*.png")):
            os.remove(f)
        fs = shots()
        for f in fs:
            shutil.copy2(f, os.path.join(GOLDEN, os.path.basename(f)))
        note = " ".join(argv[1:]).strip()
        with open(os.path.join(GOLDEN, "NOTE.txt"), "w", encoding="utf-8") as fp:
            fp.write((note or "(메모 없음)") + "\n")
        print("기준 %d장 저장 -> %s" % (len(fs), rel(GOLDEN)))
        print("   메모: %s" % (note or "(없음)"))
        print("   이 폴더는 git 에 커밋해야 다음 커밋에서 비교가 된다.")
        return

    if not os.path.isdir(GOLDEN) or not glob.glob(os.path.join(GOLDEN, "*.png")):
        print("기준 이미지가 없다. 먼저:  python tools/qc.py golden save \"리프트 붙이기 전\"")
        return

    cur = {os.path.basename(f): f for f in shots()}
    old = {os.path.basename(f): f for f in sorted(glob.glob(os.path.join(GOLDEN, "*.png")))}
    added = sorted(set(cur) - set(old))
    gone = sorted(set(old) - set(cur))
    both = sorted(set(cur) & set(old))

    rows, tiles, changed = [], [], []
    for n in both:
        a = Image.open(old[n]).convert("RGB")
        b = Image.open(cur[n]).convert("RGB")
        if a.size != b.size:
            rows.append((label(n), "크기 %s -> %s" % (a.size, b.size), True))
            changed.append(n)
            continue
        d = np.abs(np.asarray(a, dtype=np.int16) - np.asarray(b, dtype=np.int16)).max(axis=2)
        mask = d > TOL
        ratio = float(mask.mean())
        hit = ratio > RATIO
        rows.append((label(n), "%.2f%%" % (ratio * 100), hit))
        if hit:
            changed.append(n)
            base = (np.asarray(b, dtype=np.float32) * 0.34).astype(np.uint8)
            base[mask] = HOT
            tiles.append((Image.fromarray(base), label(n) + "  %.2f%%" % (ratio * 100), HOT))

    print("")
    print("| 캡처 | 변화 | 판정 |")
    print("|---|---|---|")
    for name, val, hit in rows:
        print("| %s | %s | %s |" % (name, val, "**달라짐**" if hit else "같음"))
    for n in added:
        print("| %s | — | 새로 생김 |" % label(n))
    if os.environ.get("QC_PARTIAL") == "1":      # quick.sh (#37): 구간 하나만 찍어 나머지가 없는 게 정상 — 줄줄이 안 적는다
        print("| (없어진 %d장은 --only 로 안 찍은 것) | | |" % len(gone))
    else:
        for n in gone:
            print("| %s | — | 없어짐 |" % label(n))

    paths = []
    if tiles:
        paths.append(save(grid(tiles, 4, 420, title="changed vs golden  (orange = moved)"),
                          "diff.png"))
        side = []
        for n in changed[:6]:
            if n in old and n in cur:
                side.append((Image.open(old[n]).convert("RGB"), label(n) + "  BEFORE", DIM))
                side.append((Image.open(cur[n]).convert("RGB"), label(n) + "  AFTER", HOT))
        if side:
            paths.append(save(grid(side, 2, 460, title="before / after"), "before_after.png"))

    if changed:
        look_at(paths)
        if not QUIET:
            print("")
            print("달라진 캡처 %d장: %s" % (len(changed), ", ".join(label(n) for n in changed)))
            print("의도한 변화인지 눈으로 판정해야 한다. 숫자 검사는 이걸 못 잡는다.")
    elif not QUIET:
        print("")
        print("기준과 같다. 화면에 눈에 띄는 변화 없음.")
    if added:
        print("새 캡처: %s  — 기준을 다시 저장할 때가 됐다." % ", ".join(label(n) for n in added))
    return changed


# ---------------------------------------------------------------- 영상

def _ffmpeg():
    if not shutil.which("ffmpeg"):
        sys.exit("ffmpeg 가 PATH 에 없다. strip/trail 은 ffmpeg 가 필요하다.")


def _frames(video, t0, t1, n, tmp):
    _ffmpeg()
    os.makedirs(tmp, exist_ok=True)
    for f in glob.glob(os.path.join(tmp, "*.png")):
        os.remove(f)
    dur = max(1e-3, t1 - t0)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(t0), "-t", str(dur),
                    "-i", video, "-vf", "fps=%.4f" % (n / dur),
                    "-frames:v", str(n), os.path.join(tmp, "f%03d.png")], check=True)
    return sorted(glob.glob(os.path.join(tmp, "*.png")))


def cmd_strip(argv):
    if len(argv) < 3:
        sys.exit("사용법: qc.py strip <영상> <시작초> <끝초> [장수]")
    video, t0, t1 = argv[0], float(argv[1]), float(argv[2])
    n = int(argv[3]) if len(argv) > 3 else 24
    fs = _frames(video, t0, t1, n, os.path.join(OUT, "_tmp"))
    step = (t1 - t0) / max(1, len(fs) - 1)
    items = [(Image.open(f).convert("RGB"), "%.2fs" % (t0 + i * step), DIM)
             for i, f in enumerate(fs)]
    p = save(grid(items, 6, 300, pad=8, cap_h=20,
                  title="%s   %.2f~%.2fs  (%d)" % (os.path.basename(video), t0, t1, len(fs))),
             "strip.png")
    print("%d장 -> %s" % (len(fs), rel(p)))
    look_at([p])


def cmd_trail(argv):
    """움직인 자리를 색으로 칠해 한 장에 겹친다. 이른 시점=진한 주황, 늦은 시점=노랑.

    첫 프레임을 기준으로 삼는다. 카메라가 크게 움직이는 구간에서는 화면 전체가
    칠해져서 못 쓴다 — 시점이 거의 고정된 구간을 골라라."""
    if len(argv) < 3:
        sys.exit("사용법: qc.py trail <영상> <시작초> <끝초> [장수]")
    video, t0, t1 = argv[0], float(argv[1]), float(argv[2])
    n = int(argv[3]) if len(argv) > 3 else 18
    fs = _frames(video, t0, t1, n, os.path.join(OUT, "_tmp"))
    p = save(trail_of(fs), "trail.png")
    print("궤적 %d프레임 -> %s   (진한 주황=이른 시점, 노랑=늦은 시점)" % (len(fs), rel(p)))
    look_at([p])


# ---------------------------------------------------------------- report

def cmd_report(_):
    global QUIET
    QUIET = True
    cmd_sheet([])
    seqs = cmd_seq([])
    cmd_small([])
    changed = cmd_golden(["check"])
    QUIET = False
    print("")
    print("=" * 64)
    if changed is None:
        print(" 기준 이미지가 없어 회귀 비교를 못 했다.")
        print(' 기준을 만들어라:  python tools/qc.py golden save "<메모>"  후 tools/qc_golden/ 커밋')
    elif changed:
        print(" 달라진 캡처 %d장: %s" % (len(changed), ", ".join(label(n) for n in changed)))
        print(" 의도한 변화인지 눈으로 판정해야 한다. 숫자 검사는 이걸 못 잡는다.")
    else:
        print(" 기준과 달라진 캡처 없음.")
    if not seqs:
        print("")
        print(" 연속 캡처가 하나도 없다 - 움직이는 중간에만 보이는 문제는")
        print(" 지금 구성으로는 못 잡는다. 이번 작업이 움직임을 건드렸다면 그렇게 보고해라.")
    print("")
    print(" 열어야 할 이미지:")
    for p in SEEN:
        print("   %s" % rel(p))
    print("")
    print(" 위 이미지를 열어 보기 전에는 '통과'라고 보고하지 않는다. (CLAUDE.md 11)")
    print("=" * 64)


CMDS = {"sheet": cmd_sheet, "seq": cmd_seq, "small": cmd_small, "golden": cmd_golden,
        "strip": cmd_strip, "trail": cmd_trail, "report": cmd_report}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        print(__doc__)
        sys.exit(0)
    CMDS[sys.argv[1]](sys.argv[2:])
