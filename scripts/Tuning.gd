class_name Tuning
extends RefCounted

## 모든 밸런스·연출 수치는 이 파일에만 둔다. (CLAUDE.md §7)
## 스크립트 안에 상수를 직접 쓰지 않는다.

# --- 이동 ---
const WALK_SPEED := 4.5          # m/s, 걷기 속도
const TIME_TO_TOP_SPEED := 0.12  # 초, 최고속까지 걸리는 시간
const TIME_TO_STOP := 0.10       # 초, 멈추는 데 걸리는 시간
const AIR_CONTROL := 0.25        # 공중에서의 조종력 (지상 대비 비율)

# --- 점프 / 중력 ---
const JUMP_HEIGHT := 1.0         # m, 제자리 점프로 오르는 높이
const GRAVITY := 24.0            # m/s^2, 기본 중력(9.8)보다 무겁게

# --- 시점 ---
const MOUSE_SENSITIVITY := 0.0022  # rad / 마우스 픽셀
const PITCH_LIMIT_DEG := 89.0      # 위아래로 꺾을 수 있는 한계

# --- 몸 크기 (통로·천장 설계의 기준값) ---
const BODY_RADIUS := 0.4   # m
const BODY_HEIGHT := 1.8   # m
const EYE_HEIGHT := 1.7    # m

# --- 갱도 격자 (#22 → #26 조각 카탈로그) ---
const GRID_CELL := 7.0           # m, 칸 하나. 조각은 7×7 (방 2×2 는 14×14). 조각 표는 scripts/PieceCatalog.gd

# --- 층 조립 (#27, scripts/MineAssembler.gd. 문법은 Opus5_채굴게임/Claude outputs/조립기_프로토타입_v6.py) ---
const MAP_SEED := 7              # 하나뿐인 시드. 층 i 는 +i, 포켓 +100, 소품 +200 (멀티 준비: 난수 시드는 하나). 봇·골든이 같은 판을 보게 고정
const MAP_FLOORS := 2            # 위층(y 0)·아래층(y -LIFT_DROP). 리프트는 그대로 한 번만 내려간다
const MAP_N := 35                # 칸 수 한 변 = 245 m (#25: 빈 갱도라면 끝 벽까지 걸어서 45~60초)
const ENTRY_STRAIGHT := 3        # 정거장 앞 직선 레일 칸 (21 m). 스폰·봇 동선이 여기 선다
const RING_MARGIN := 5           # 순환선 모퉁이가 격자 가장자리에서 떨어진 칸
const RING_WOBBLE := 3           # 순환선 중간점을 옆으로 흔드는 ±칸 — 구불구불
const SPURS_MIN := 2             # 지선(순환선 → 구석 종점) 수
const SPURS_MAX := 4
const SPUR_LEN_MIN := 6          # 지선 길이 (칸)
const SPUR_LEN_MAX := 11
const SPUR_TURN_P := 0.2         # 지선이 꺾일 확률
const BRANCHES := 70             # 횡갱(무레일 가지) 수
const BRANCH_LEN_MIN := 4        # 횡갱 길이 (칸)
const BRANCH_LEN_MAX := 12
const BRANCH_DEPTH := 5          # 가지의 가지 깊이
const TURN_P := 0.35             # 횡갱이 꺾일 확률
const LOOP_P := 0.5              # 걷다 다른 갱도에 닿으면 이어 붙일 확률 (= 고리)
const LOOPS_MAX := 22            # 고리 상한
const FAR_DIV := 70.0            # 뿌리(정거장)에서 먼 칸일수록 갈림 ↓: 건너뛸 확률 = 거리(칸) / 이 값
const BLOCKS := 4                # 채탄구역(방기둥 격자 3×3~5×5) 수
const ROOM_P := 0.7              # 막다른 끝이 목 + 방이 될 확률 (나머지는 끝막이)
const REFUGES := 2               # 층당 대피소
const PIECE_VIEW_RANGE := 40.0   # m, 이 밖의 조각 메시는 안 그린다 (Godot visibility range). 램프 14 + 안개 0.03 이라 안 보인다
# 소품은 무더기(2~3개)로 놓는다 (#27 수정: 벽에 하나씩 붙인 것은 램프 원뿔 밖이라 "소품이 있는지 모르겠다")
const PROP_CLUSTER_P := 0.2      # 직선 칸당 무더기 확률
const PROP_JUNCTION_P := 0.5     # 갈림(T·+) 칸당 무더기 확률 (모서리 크립 옆)
const PROP_CLUSTER_MIN := 2      # 무더기 크기
const PROP_CLUSTER_MAX := 3
const PROP_CLUSTER_R := 1.2      # m, 무더기 반지름
const PROP_WALL_GAP_MIN := 1.4   # m, 무더기 중심이 벽(공칭 3.5)에서 떨어지는 거리 — 복도 가운데서 램프 원뿔(40°) 안에 든다
const PROP_WALL_GAP_MAX := 2.2
const PROP_BIG_FRAC := 0.8       # 큰 것(통·상자·잔해·갱목) 비중. 납작한 것(삽·망치)·작은 것(양동이·석유등)은 나머지
const PROP_CAP := 1              # 끝막이 앞 무더기 수
const PROP_ROOM_2 := 3           # 방 2×2 구석 무더기 수
const PROP_ROOM_1 := 1           # 방 1×1 무더기 수

# --- 채굴 (#23 수정판: 채굴 벽은 없다. 캐는 것은 옆벽에 박힌 광맥 포켓뿐 — #24) ---
const MINE_DAMAGE := 25.0        # 1회 타격 데미지
const POCKET_HEALTH := 50.0      # 광맥 포켓 체력. 위 값이면 2타 — 첫 타에 자갈, 둘째 타에 덩이가 빠진다
const MINE_RANGE := 3.0          # m, 곡괭이가 닿는 거리
const MINE_COOLDOWN := 0.35      # 초, 타격 간격. 연타해도 이보다 빠르지 않다
const HIT_RECOIL := 0.12         # m, 맞은 블록이 뒤로 밀리는 거리
const HIT_RECOIL_TIME := 0.10    # 초, 밀렸다 돌아오는 데 걸리는 시간
const BREAK_TIME := 0.08         # 초, 부서질 때 줄어드는 시간
# --- 자갈·돌 조각 (WallChunk) ---
# 평타 자갈(mine_chips.gltf)과 붕괴 때 떨어지는 돌이 쓴다. 벽 파쇄 9벌은 #24 로 없어졌다.
const CHUNK_SPIN := 4.0          # rad/s, 조각이 도는 속도
const CHUNK_LIFE := 3.0          # 초, 이만큼 뒤에 사라지기 시작 (붕괴 돌)
const CHUNK_FADE := 0.5          # 초, 줄어들며 사라지는 시간
const CHUNK_LIMIT := 40          # 화면 안 조각 상한. 넘으면 오래된 것부터 지운다
const HIT_DUST := 12             # 알, 평타 먼지
const BREAK_DUST := 60           # 알, 포켓에서 덩이가 빠질 때 먼지
const SHAKE_AMOUNT := 0.06       # m, 카메라 흔들림 폭. 덩이가 빠질 때만
const SHAKE_TIME := 0.15         # 초

# --- 광맥 포켓 · 광석 (#23 수정판, #24 규칙: 광석은 재화, 채굴은 소음만) ---
# 광석은 조각과 달리 시간이 지나도 사라지지 않는다.
# 주우러 갈지 말지를 고르는 것이 이 게임의 긴장이라, 시간이 대신 지워주면 안 된다.
# 포켓 자리는 조각 안의 빈 노드 SLOT_Pocket_* 다 (#26·#27, build_piece.py). PocketSpawner 가 층의 자리를 전부 읽는다.
const POCKET_CHANCE := 0.10      # 자리당 켜질 확률. 층당 자리 약 1,600 (시드 7) → 기대 약 160개
const POCKET_MIN_PER_FLOOR := 1  # 층에 하나도 안 켜지면 첫 자리를 강제로 켠다. 시드는 MAP_SEED + 100 (#27)
const POCKET_WALL_OUT := 0.12    # m, 자리(SLOT_Pocket, 벽 공칭면 안쪽 0.08)에서 통로 쪽으로 더 내미는 거리. 벽 요철이 안쪽으로 0~0.3 이라
                                 # 자리 그대로면 요철이 깊은 곳에서 덩이가 파묻힌다 (#27 첫 캡처: 끝만 보임). 파묻힘/떠 있음 판정 손잡이
const POCKET_POP_OUT := 1.4      # m/s, 옆벽에서 통로 쪽으로 튀는 속도. 0.6 이면 벽에 붙어 구른다
const ORE_POP_UP := 2.2          # m/s, 위로 튀는 속도. 자갈(2.4)만큼 높아야 눈에 띈다
const ORE_POP_SIDE := 0.6        # m/s, 벽을 따라 좌우로 흔들리는 속도. 하나뿐이라 흩어질 필요가 없다
const ORE_SPIN := 4.0            # rad/s
const ORE_ROLL_DAMP := 4.0       # 구르기 감쇠. 충돌이 구(0.12)라 감쇠 없이는 자갈 바닥을 3.5m 넘게 굴러갔다(봇 실측) — 1~1.5m 에서 멎게
const ORE_MAGNET_DELAY := 1.5    # 초, 튀어나온 뒤 이만큼은 안 빨려온다.
                                 # 채굴 사거리(3.0)와 자석 반경(1.8)이 겹쳐서,
                                 # 이게 없으면 벽 앞에 선 채로 즉시 빨려들어가
                                 # 광석이 바닥에 구르는 것을 볼 새가 없다.
                                 # 0.8초로는 착지하기도 전에 풀려서 1.5초로 잡았다 —
                                 # 튀어서 바닥에 멎는 데까지가 그 정도다.
const ORE_MAGNET_RANGE := 1.8    # m, 이 안에 들면 몸으로 빨려온다
const ORE_PULL_SPEED := 6.0      # m/s, 빨려오는 속도
const ORE_COLLECT_DIST := 0.35   # m, 이만큼 가까워지면 줍힌다

# --- 곡괭이 ---
# 화면에 들리는 곡괭이는 충돌 판정이 없는 그림이다(뷰모델). 벽을 뚫고 보일 수 있다.
const PICK_POS := Vector3(0.32, -0.42, -0.60)  # 카메라 기준 오른쪽·아래·앞 (#23 렌더 pick_a2_hand_s075 와 같은 자리)
const PICK_SCALE := 0.75         # pick.gltf(자루 0.85·머리 0.46). A 단계 렌더 판정 0.75 (0.55 는 "너무 작다")
const PICK_TILT_DEG := -12.0     # 쉬고 있을 때 앞뒤로 눕힌 각도
const PICK_YAW_DEG := -90.0      # 머리를 앞뒤로 세우는 각도.
                                 # 0 이면 머리가 화면 가로로 누워 옆으로 후려치는
                                 # 모양이 된다. pick.gltf 는 머리 긴 축이 X, 양끝이
                                 # 뾰족해 KayKit 때의 -90 을 그대로 쓴다.
const PICK_ROLL_DEG := 10.0      # 옆으로 눕힌 각도. 크면 눕혀 든 것처럼 보인다
const PICK_SWING_DEG := 55.0     # 내려치는 각도
const PICK_DOWN_TIME := 0.12     # 초, 내려치는 데 걸리는 시간.
                                 # 데미지는 이 시점에 들어간다 — 곡괭이가 벽에 닿을 때다.
const PICK_UP_TIME := 0.23       # 초, 되돌리는 시간. 합쳐서 쿨다운 0.35 와 맞는다
const PICK_BOB_AMOUNT := 0.02    # m, 걸을 때 흔들리는 폭
const PICK_BOB_SPEED := 12.0     # rad/s

# --- 리프트 ---
const LIFT_DROP := 10.0          # m, 한 번에 내려가는 깊이 (#22: 8 → 10. 갱도 높이 5.6 이면 층 사이 바위가 남아야 한다). 위층 불빛이 사라진다
const LIFT_SPEED := 1.4          # m/s. 8m 에 약 5.7초 — 느려야 무섭다
const LIFT_ACCEL_TIME := 0.6     # 초, 최고속까지. 출발·도착에서 덜컹거리지 않게
const LIFT_GATE_TIME := 0.8      # 초, 케이지 문이 닫히는(열리는) 시간. 다 닫힌 뒤에 출발한다 (#21)

# --- 조명 (헤드램프) ---
# 갱도는 이 등 하나로 본다. 태양광은 없다.
const LAMP_ANGLE_DEG := 40.0     # 원뿔 반각. 시야(fov 80)보다 좁아야 가장자리가 어둡다.
                                 # 32 는 가까운 벽에 손전등 원반이 찍혔다(사용자 판정 09-08) → 40
const LAMP_ATTEN := 0.45         # 원뿔 가장자리가 꺼지는 정도. 크면 테두리가 또렷해진다.
                                 # 1.2 는 동그란 테두리가 눈에 띄어 손전등 같았다. 0.7 도 원반이 보여 0.45
# 램프의 몸 (#17 수정). 등이 카메라와 같은 축이면 빛에 방향이 없다.
const LAMP_FOLLOW_TIME := 0.10   # 초, 시점을 돌리면 램프가 이만큼 늦게 따라온다. 0 이면 카메라에 붙는다.
                                 # 멀미 나면 0.05
const LAMP_OFFSET := Vector3(0.0, 0.12, 0.0)  # m, 카메라 기준 램프 원점. 눈 위 이마 자리
const LAMP_BOB := 0.01           # 도, 걸을 때 위아래로 끄덕이는 각. 곡괭이 bob 속도(PICK_BOB_SPEED)와 같이 돈다.
                                 # 0.6 은 "너무 과하다"(사용자 09-08 2차 판정, 값 지정 0.1) → 0.1 도 "아직 큼"(#19 판정, 0.05) → 0.05 도 "출렁인다"(2차, 값 지정 0.01)
const LAMP_RANGE := 14.0         # m, 이보다 먼 것은 안 보인다. 12 로 줄여 봤더니 20m 방의 먼 벽이
                                 # 통째로 사라져 공간이 안 읽혔다 — 먼 곳은 안개가 서서히 잠그게 둔다
const LAMP_ENERGY := 5.0         # 벽이 젖은 검은 돌(반사율 약 1/3)이 되면서 2.2 → 5.0 (#17).
                                 # 실측(spawn 시점 화면 평균): 3.2 = 0.0097(안 보임) · 6.0 = 0.0152 · 9.0 = 0.0190.
                                 # 9.0 은 먼 벽은 좋은데 채굴 거리(1.8m)의 벽이 하얗게 탔다 —
                                 # 세기 대신 아래 감쇠를 낮춰 먼 곳을 살린다
const LAMP_DIST_ATTEN := 0.6     # 거리 감쇠 곡선. 1.0 = 거리 제곱으로 꺼짐(물리). 낮출수록 먼 곳까지
                                 # 고르게 간다 — 가까운 벽을 안 태우면서 먼 벽을 보이게 하는 손잡이
const LAMP_COLOR := Color(1.00, 0.96, 0.88)  # 거의 흰 빛 (#17 수정). 누런 빛(0.88/0.70, 0.86/0.62)은
                                             # 검은 돌을 갈색으로 만들었다(사용자 판정 "안 읽힌다")
const LAMP_SHADOW := true        # 창살·조각 그림자가 이 게임의 그림이다
const LAMP_TOGGLE_TIME := 0.15   # 초, F 로 끄고 켜는 트윈 (#32)
const DARK_ADAPT_AMBIENT := 3.0  # (#32 수정 2: 5.5 → 3.0. 사용자 F5 "끈 게 더 잘 보인다" — 환경광은 방향이 없어 원뿔 밖까지 비춘다. 후보 A 5.5/0.2·B 3.0/0.45·C 2.0/0.6 중 B)  램프를 끄고 눈이 적응한 끝의 환경광. 환경광 색이 (0.1, 0.12, 0.2) 로 어두워 0.12 로는 화면 밝기 0.0017 → 0.0024 뿐이었다 (#32 실측). 3.0 ≈ 밝기 0.025, 벽 윤곽만 겨우
const DARK_ADAPT_TIME := 4.0     # 초, 적응에 걸리는 시간. 켜면 즉시 평소로 (눈부심)
const DARK_ADAPT_FOG := 0.45     # 적응했을 때 거리 안개 밀도 (#32 수정 2: 0.2 → 0.45). 환경광은 거리가 없어 복도 끝까지 비추므로 안개로 잠근다 — 2 m 41 %·4 m 17 %·6 m 7 %. 레일 두 줄·곡괭이·옆 난간만 남는다
# 소음 (#32, 순서표 ⑥) — scripts/NoiseBus.gd. 반경 m. 듣는 괴물은 ⑦. 값은 ⑦b 판정 때 같이 움직인다
const NOISE_PICK := 25.0         # 곡괭이가 벽에 닿은 타격. 칸 3.5개 — 옆 갱도까지
const NOISE_REPAIR_FAIL := 40.0  # 정비 실패 "큰 소음". 타격의 1.6배
const NOISE_STEP := 6.0          # 발걸음. 같은 칸 안
const STEP_INTERVAL := 0.5       # 초, 걷기 4.5 m/s 에서 2.25 m 마다 한 걸음
const NOISE_CART := 20.0         # 달리는 광차, 1초마다
const NOISE_HUD_FADE := 1.0      # 초, 왼쪽 아래 원이 사라지는 시간
const NOISE_HUD_PX_PER_M := 2.0  # 반경 1 m 당 지름 px. 40 m → 지름 160
# 이동 세 자세 + 스태미나 + 곡괭이 던지기 (#34, 규칙 개정 4) — Player.gd · ThrownPick.gd. 판정은 ⑦b
const STANCE := {                # 자세: 속도 m/s · 발소리 간격 s · 발소리 반경 m. 걷기 줄은 위 WALK_SPEED·STEP_INTERVAL·NOISE_STEP 그대로
	"crouch": {"speed": 2.0, "step": 1.2, "radius": 2.0},         # Ctrl. 뚜벅…… 뚜벅…… 바로 옆에서만
	"walk": {"speed": WALK_SPEED, "step": STEP_INTERVAL, "radius": NOISE_STEP},
	"run": {"speed": 7.0, "step": 0.32, "radius": 14.0},          # Shift. 두 칸 건너에서도
}
const CROUCH_EYE := 1.0          # m, 숙였을 때 눈높이 (평소 EYE_HEIGHT 1.7). 광차 테두리 1.72 아래
const CROUCH_TIME := 0.15        # 초, 눈이 내려가고 올라오는 시간
const STAMINA_MAX := 100.0
const STAMINA_RUN := 20.0        # /s 달리면 닳음 (5초)
const STAMINA_WALK := 10.0       # /s 걸으면 참
const STAMINA_IDLE := 20.0       # /s 서 있으면 참. 탈진은 100 찰 때까지 정지 (5초)
const THROW_SPEED := 14.0        # m/s, 곡괭이 던지는 속도. 위로 THROW_UP_DEG 면 사거리 약 12 m (중력 24)
const THROW_UP_DEG := 10.0
const THROW_BODY_R := 0.15       # m, 던진 곡괭이 충돌 구
const NOISE_PICK_LAND := 20.0    # m, 착지 소음 (광차와 같은 급). 유인
const THROW_STUCK_S := 3.0       # 초, 착지 뒤 이만큼 지나면 얼린다 (틈에 끼지 않게)

# --- 갱도의 색과 공기 (제안서 #17, 질감 A·D) ---
# 팔레트 사본은 tools/palette.py 가 뽑는다. 색은 그 표에서 고친다 — 여기는 재질·공기·후처리.
const PALETTE_PATH := "res://assets/generated/palette/dungeon_texture.png"
const PALETTE_ROUGHNESS := 0.7   # KayKit 팔레트 재질(채굴 벽·리프트·파쇄 조각) 거칠기. 무광.
                                 # #17 의 0.22 + 광택막은 평평한 KayKit 벽에서 램프가 한 점 원반으로 맺혔다
                                 # ("광원 동그라미가 너무 크고 세다", #19 3차 판정). 젖음은 요철 있는 갱도 모듈 재질에만 준다
# 젖은 바위 (shaders/wet_rock.gdshader, #20 판정 뒤). 갱도 모듈·정거장의 MAT_RockWall·MAT_Floor.
# 균일한 광택막(#17~#19, 0.7)은 세 번 "젖은 게 아니라 반사가 센 것"으로 판정됐다. 젖음은 얼룩이다 —
# 세계 좌표 노이즈로 젖은 자리만 어둡게·번들거리게, 수직면은 세로로 흘러내린 자국.
const STONE_CLEARCOAT := 0.0     # 젖은 자리의 물막. #27 수정: 1.0 은 헤드램프가 벽·바닥에 흰 점으로 맺혔다(사용자 "광원이 비친다") → 0. 얼룩·흘러내림(WET_DARKEN 등)은 그대로
const WET_SCALE := 0.3           # 얼룩 노이즈 한 주기 = 1/0.3 ≈ 3.3m. 얼룩 크기 0.5~1.5m
const WET_LOW := 0.42            # 노이즈가 이 밑이면 마른 돌
const WET_HIGH := 0.60           # 이 위면 완전히 젖음. 둘 사이가 번짐 폭. 낮추면 더 넓게 젖는다
const WET_DARKEN := 0.5          # 젖은 자리 색 배율. 물이 스민 돌은 어둡다
const WET_ROUGHNESS := 0.45      # 젖은 자리 거칠기 (마른 자리는 텍스처 값). 0.1 은 거울 — 흰 점의 다른 반 (#27 수정)
const ROCK_SPECULAR := 0.25      # 마른 바위 반사율. 0.5 + 물막 = 램프 흰 점 (#27 수정)
const ROCK_NORMAL_SCALE := 1.6   # 큰 결(노멀맵) 강도. 1.0 은 "매끈한 이미지" (#27 수정)
const DETAIL_NORMAL_TILES := 6.0 # 미세 결: 같은 노멀맵을 이만큼 잘게 한 번 더 겹친다
const DETAIL_NORMAL_STRENGTH := 0.6  # 그 세기. 0 = 없음. 0.5 m 안에서 격자처럼 보이면 내린다
# 이음새 (#27 수정 2)
const TRIPLANAR := true          # 벽·바닥 텍스처를 UV 대신 세계 좌표 세 면에서 뽑는다 — 조각 경계에서 무늬가 안 끊긴다
const TRI_SCALE_WALL := 0.42     # 1/한 장 크기 (m). 박스 매핑과 같은 값 = 2.4 m 한 장
const TRI_SCALE_FLOOR := 0.70    # 바닥 1.4 m 한 장
const TRI_BLEND := 4.0           # 세 면 섞는 날카로움 (젖은 얼룩과 같은 값)
const COLLAR_THICK := 0.35       # m, 이음새 바위 칼라: 아치 윤곽 바깥 두께. 0 = 안 놓음. 벽 요철 0.3 보다 커야 한다
const COLLAR_DEPTH := 0.5        # m, 이음새 앞뒤 깊이
const COLLAR_INSET := 0.02       # m, 칼라 안쪽 면을 공칭 윤곽보다 이만큼 바깥에 — 이음새 선에서 벽과 겹쳐 떨리지 않게
const CRIB_FILL_W := 0.66        # m, 크립 속을 채우는 바위 기둥 한 변 (통나무 안쪽 0.5, 바깥 0.9). 0 = 안 채움. 사용자 스크린샷의 "틈" = 크립 속 빈 곳
# 갱도 설비 (#28) — 조립기가 직선 칸마다 왼쪽(케이블·풍관·배수로·라깅·갓등)·오른쪽(배수관·플랜지) 묶음을 놓는다. 근거 Opus5_채굴게임/Claude outputs/레퍼런스_갱도_설비.md
# 광차 (#29) — 순환선 Path3D 위를 돈다. MineAssembler._place_carts · scripts/MineCart.gd
const CART_COUNT := 3            # 순환선 위 광차 수 (규칙 3~4). 0 = 안 놓음
const CART_SPEED := 8.0          # m/s. 걷기 4.5 의 1.8배. 시드 7 순환선 약 960 m → 한 바퀴 2분. MAP_STRUCTURE "30초 안팎"(15 m/s)의 절반 — 손잡이
const CART_STOP_S := 6.0         # s, 순환선 시작(정거장 앞 직선 끝)에서 정차
const CART_BOARD_DIST := 3.0     # m, E 가 먹는 거리 (Board Area3D 반지름)
const CART_SEAT := Vector3(0.0, 0.62, 0.0)   # 짐칸 바닥 자리 (테두리 1.72 < 눈 0.62+1.7)
const CART_OFF_SIDE := 1.6       # m, 내릴 때 광차 오른쪽으로
const CART_CURVE_R := 3.5        # m, 꺾이는 칸의 호 반지름 (rail_curve 와 같다)
const CART_ARC_PTS := 6          # 호를 몇 점으로
const CART_LOOK := 2.0           # m, 광차가 바라보는 앞 점 거리 (#29-c). PathFollow3D 접선은 폴리라인 꼭짓점마다 튀어서 대신 이 점을 본다
# 갱목 광부 모델 (#36) — scenes/level/Miner.tscn · scripts/MinerBody.gd. 배치·행동은 #35 (아래 괴물)
const MINER_ANIM_SPEED := 0.7        # 기본 재생 배속(제자리 클립). 느릴수록 무섭다 — F5 로 0.5~1.0 판정
const MINER_SCALE := 1.5             # 사용자 F5 09-11: 1.0 은 "무섭지 않다" → 1.5배. 웅크린 키 1.92 × 1.5 ≈ 2.9 m, 선 키 3.75. 1.0 = 사람 크기(선 키 2.5)
const MINER_BLEND_S := 0.18          # s, 클립을 섞는 기본 시간 (#47). 0 이면 한 프레임에 자세가 튄다
const MINER_BLEND_POSE_S := 0.45     # s, 선 자세 ↔ 엎드린 자세처럼 차이가 큰 짝
const MINER_BLEND_BRIDGE_S := 0.15   # s, 엎드리기 클립(prone_down) 앞뒤 — 이 클립 자체가 다리 역할이라 짧게
const MINER_BLEND_HIT_S := 0.12      # s, 맞기·휘두르기로 들어갈 때. 타격은 빨라야 맞은 느낌이 난다
const MINER_BLEND_ROAR_S := 0.30     # s, 포효로 들어갈 때
const MINER_PRONE_FROM := 2.9        # s, prone_down(일어서기) 클립에서 선 자세인 시각. 여기서부터 뒤로 틀면 엎드리기가 된다 (#47)
const MINER_PRONE_TO := 2.1          # s, 같은 클립에서 네 발로 짚은 시각. 여기까지 오면 run 으로 넘긴다
const STALKER_HAND_GROUND := true    # #46 손 접지 켬/끔. false = 옛 동작(손이 바닥을 뚫는다) — 봇 사보타주용
const STALKER_GROUND_CLIPS: PackedStringArray = ["crawl", "run"]   # 손을 바닥에 붙일 클립. 선 자세 클립은 손이 1.4 m 위라 건드릴 일이 없다
const STALKER_HAND_CLEAR := 0.02     # m, 손끝 뼈가 바닥 위로 띄우는 값
const STALKER_HAND_LIFT_MAX := 0.80  # m, 한 팔을 끌어올리는 한도 (실측 최대 crawl 0.64). 넘으면 포기 — 팔이 안 닿는 자세다
# 괴물 (#35) — 한 마리 + 감독. scripts/Stalker.gd · Director.gd. 수치 판정은 ⑦b
const STALKER_R := 0.6               # m, 충돌 캡슐 반지름
const STALKER_H := 2.8               # m, 충돌 캡슐 높이 = 1.5배 웅크린 키(실측 2.81)
const STALKER_EYE_H := 2.4           # m, 눈(시선 레이) 높이
const STALKER_SPEED := {"wander": 2.5, "investigate": 4.0, "chase": 6.5, "retreat": 4.0, "search": 2.5}   # m/s. 걷는 사람(4.5)은 잡히고, 달리면(7.0) 5초 벌 수 있다
const STALKER_EAR_MUL := 1.0         # 소음 반경에 곱함 — 반경 안이면 듣는다 (카드 어둠 수색 ×1.5)
const STALKER_EYE_DEG := 60.0        # 눈 원뿔 반각. 램프 켜진 몸만, 시선이 안 가려야
const STALKER_EYE_M := 12.0          # m, 눈 사거리
const STALKER_LIGHT_M := 30.0        # m, 빛: 켜진 램프가 시선에 들면 그 자리로 천천히(배회 속도)
const STALKER_LOSE_S := 3.0          # s, 추격 중 이만큼 못 보면 마지막 자리 조사
const STALKER_SEARCH_CELLS := 3      # 수색 범위 (격자 칸)
const STALKER_SPOTS_MIN := 2         # 수색 곳 수
const STALKER_SPOTS_MAX := 3
const STALKER_DWELL_S := 2.0         # s, 곳마다 머무는 시간 (카드 ×2)
const STALKER_FOUND_M := 2.0         # m, 수색 자리에서 이 안에 숨어 있으면 들킴
const STALKER_CATCH_M := 1.5         # m, 잡는 거리 (추격 중)
const STALKER_STUN_S := 1.5          # s, 곡괭이 스턴
const STALKER_WANDER_CELLS := 3      # 배회 반경 (격자 칸)
const STALKER_WANDER_PAUSE_S := 1.0  # s, 배회 도착마다 멈춤
const STALKER_CLIPS := {"wander": "walk_crouch", "investigate": "walk_crouch", "search": "idle_crouch", "alert": "roar", "chase": "run_stand", "retreat": "walk_crouch", "stun": "hit", "catch": "attack_swipe", "climb": "crawl", "hang": "crawl", "land": "land_hard"}   # 낙하 클립은 STALKER_FALL_CLIP (#57). hang = 천장 기기 클립을 멈춰 두고 상체만 든다 (#59, 옛 #57 은 선 클립을 거꾸로). #48: 바닥 추격은 서서 달리기, 기는 것은 천장 전용. #49: 벽타기도 crawl — 사람 사다리 클립(climb_up/down)은 팔을 벌려 웃긴다
const STALKER_ALERT_S := 1.0         # s, 숨은 플레이어를 들키면 포효(roar)하고 이만큼 뒤에 추격 — 빠져나갈 틈. 0 이면 바로 추격
const STALKER_DROP_S := 0.0          # s, #47 엎드리기. #48 에서 바닥 추격이 '서서 달리기'가 되면서 안 쓴다(0). 기는 것은 천장 전용 — 0.6 으로 되돌리면 바닥에서도 엎드린다
# 천장 크롤러 (#48) — 벽타기·낙하 클립은 받는 중. 먼저 천장 이동부터
const STALKER_CEIL_ON := true        # 천장 기능 끄개. false = 전부 바닥 (사보타주)
const STALKER_CEIL_CLEAR := 0.35     # m, 천장면과 등(괴물 원점) 사이 틈
const STALKER_CEIL_MIN_H := 3.6      # m, 천장이 이보다 낮은 칸은 천장 길이 아니다 (실측: 직선 4.96 · 교차 5.39 · 곡선 3.05)
## 조각별 천장 높이 (m, 칸 가운데 통로 위쪽 면 중 가장 낮은 점 = 갓보 밑). 실측 — tools 없이 재려면 조각 gltf 정점을 읽으면 된다.
## 천장에는 충돌 상자가 없다(벽 상자 top 5.60 뿐) — 레이캐스트로는 못 잡아서 표로 쓴다.
const CEIL_H := {"straight": 4.96, "curve": 2.71, "t": 5.40, "cross": 5.39, "cap": 4.97, "neck": 3.08, "refuge": 4.99, "room_1": 4.94, "room_2": 5.75}
const STALKER_CEIL_RISE := 4.0       # m/s, 칸이 바뀌어 천장 높이가 달라질 때 따라 올라가는 속도
const STALKER_CEIL_EYE_H := -1.2     # m, 거꾸로 매달렸을 때 눈높이 (원점 아래)
const STALKER_CEIL_SPEED := 2.5      # m/s, 천장 이동 속도 (배회·조사·수색·철수)
const STALKER_CEIL_INV_SPEED := 4.0    # m/s, 천장에서 빛으로 알아챈 플레이어에게 다가가는 속도 (#53). 바닥 소음 조사와 같은 값 —
                                     # 2.5 로는 걷는 플레이어(4.5)에게도 못 따라와 머리 위에 머물기만 한다
const STALKER_CEIL_CHASE_SPEED := 6.5   # m/s, 천장에서 쫓을 때 (#52). 바닥 추격(STALKER_SPEED["chase"])과 같은 값 —
                                     # 2.5 로는 달리는 플레이어(7.0)에게서 초당 4.5 m 씩 뒤처져 머리 위에서 멀어지기만 했다(F5 09-13).
                                     # 6.5 면 초당 0.5 m 만 벌어져, 스태미나가 떨어지면 따라붙어 STALKER_FALL_TRIGGER_M 에서 떨어진다
const STALKER_CEIL_CLIPS := {"wander": "crawl", "investigate": "crawl", "search": "crawl", "chase": "run", "retreat": "crawl"}   # 천장에 붙어 있을 때 쓰는 클립 (거꾸로 재생되는 게 아니라 몸을 뒤집는다)
# 면 번갈기 · 벽 (#49). 배회는 천장 ↔ 바닥을 시계로 번갈고, 조사·수색·추격은 바닥이다. 오르내리기는 벽면 위의 crawl.
const STALKER_CEIL_DWELL_S := 12.0   # s, 천장에서 배회하는 시간. 끝나면 벽으로 내려온다
const STALKER_FLOOR_DWELL_S := 10.0  # s, 바닥에서 배회하는 시간. 끝나면 벽을 타고 올라간다 (오르내리는 데 6~7초씩 걸려 조용할 때 천장 체류는 약 40 %)
const STALKER_CEIL_P := 0.5          # 등장할 때 천장에 붙을 확률 (나머지는 바닥 곡선 칸)
const STALKER_WALL_SPEED := 1.2      # m/s, 벽·아치를 기어 오르내리는 속도 (벽 4.4 m + 아치 약 3.3 m = 6.4초)
const STALKER_WALL_LAND_OFF := 0.75  # m, 바닥에 내려설 때 벽면에서 몸 중심까지. 몸 반지름 0.6 + 여유 0.15 — 바깥 끝 3.01 로 벽 충돌체(3.20) 안쪽이다.
                                     # 이걸 안 두면 몸이 벽에 0.51 m 박힌 채로 물리가 켜져 밀려나가다 바닥 아래로 빠졌다 (#49 수정, 사용자 F5)
                                     # 오르내리는 동안 이 높이만큼에 걸쳐 STALKER_WALL_OFF 로 붙는다 (한 프레임에 안 튀게)
const STALKER_WALL_OFF := 0.05       # m, 벽면에서 몸 중심까지. 옛 값 0.7 은 충돌 상자(|x| 3.2~3.5) 기준이라 보이는 벽(3.16) 밖 허공이었다 — 사보타주로 되돌려 본다
const STALKER_RETREAT_CEIL_CELLS := 3   # 칸, 철수할 때 벽을 타고 올라간 뒤 천장으로 기어 멀어지는 거리 (#50. 3칸 = 21 m, 천장 2.5 m/s 로 8.4초)
const STALKER_FLOOR_MIN_Y := -0.1    # m, 괴물이 이 밑으로 내려가면 갇힌 것 — 칸 가운데 바닥으로 되돌린다 (#49 수정 그물)
const STALKER_SURF_TURN_S := 0.4     # s, 붙은 면이 바뀔 때 몸이 새 법선으로 도는 시간
# 벽을 탈 수 있는 조각 (#51). 이 셋만 옆벽이 칸 가운데에서 TUNNEL_WALL_X 인 곧은 면이다 — 갱목 기둥이 벽에 붙어 서고(build_piece.py POST_W 0.34,
# 기둥 안쪽면 3.5 − 0.34 = 3.16), 천장도 CEIL_H 3.6 이상이다(직선 4.96 · t 5.40 · cap 4.97).
# 곡선·목은 벽이 휘고 천장이 낮고(2.71 / 3.08), 교차는 닫힌 면이 없고, 방·대피소는 칸 가운데가 벽에서 3.16 이 아니다.
const STALKER_WALL_PIECES: Array[String] = ["straight", "t", "cap"]
const TUNNEL_WALL_X := 3.16          # m, 보이는 벽(갱목 기둥 안쪽면)까지. 조립기 단면(MineAssembler._collar_mesh)과 같은 값
const TUNNEL_ARCH_Y := 4.4           # m, 벽이 끝나고 아치가 시작하는 높이 (h_wall)
const TUNNEL_TOP_Y := 5.6            # m, 아치 꼭대기 (h_top). 실제 조각 천장은 CEIL_H 가 더 낮다 — 아치는 그 값으로 눌러 쓴다
const STALKER_FALL_TURN_S := 0.25    # s, 천장에서 놓고 몸이 뒤집히는 시간
const STALKER_FALL_TRIGGER_M := 7.5  # m, 천장에서 플레이어가 이 안에 들면 떨어진다 (낙하+착지 1.4초 동안 플레이어가 도망갈 거리를 감안)
const STALKER_LAND_FROM := 0.63      # s, land_hard 에서 발이 바닥에 닿는 시각 — 여기서부터 튼다
const STALKER_LAND_S := 0.67         # s, 착지 자세를 유지하는 시간. 끝나면 서서 달리기로 섞는다
# 낙하 = 매달림 → 머리부터 (#57). 레퍼런스 = 조사 #56(리커·에일리언·베르두고): 팔을 옆으로 벌리는 작품은 없다 — 발로 매달려 팔을 플레이어 쪽으로 뻗고 머리부터 떨어진다
const STALKER_HANG_S := 0.8          # s, 떨어지기로 한 뒤 천장에 멈춰 노려보는 시간(예고, #59). 0 = 옛 동작(바로 놓는다). #60 플레이어 멈춤을 넣으면 1.2
const STALKER_HANG_SWING_S := 0.25   # s, 그중 천장 기기 클립(crawl)으로 섞는 시간 — 다 섞이면 그 자리에 멈춘다
# 노려보기 (#59). F5(#58 뒤): 선 클립을 뒤집은 매달림은 곡예사처럼 읽힌다 → 리커처럼 엎드린 채 허리를 접어 상체를 내민다 (SpineGlare)
const STALKER_GLARE_ON := true       # 끄면 굽히지 않는다 (재기만 한다 — 사보타주용)
const STALKER_GLARE_RISE_S := 0.35   # s, 상체를 드는 시간 (팔 뻗기도 같이 오른다). 나머지가 노려보는 시간
const STALKER_GLARE_SPINE_DEG := 45.0   # °, 척추 세 마디 합계 굽힘 (마디마다 1/3)
const STALKER_GLARE_HIP_DEG := 10.0  # °, 엉덩이 뼈가 나눠 가지는 굽힘 (다리는 그만큼 되돌려 발을 천장에 둔다)
const STALKER_GLARE_BONE_MAX := 20.0 # °, 마디 하나가 굽는 최대 — 넘기면 허리 표면이 접혀 찌그러진다
const STALKER_GLARE_HEAD_DEG := 50.0 # °, 목·머리가 플레이어 쪽으로 더 돌 수 있는 최대 (반씩). 제안 40 → 6 m 앞 플레이어를 못 봤다(실측 일치 0.88, 상체가 62~66° 들려서)
const STALKER_GLARE_BREATH_DEG := 3.0   # °, 숨쉬기 — 척추 굽힘이 ± 이만큼 흔들린다
const STALKER_GLARE_BREATH_HZ := 0.8    # 초당 숨 횟수
const STALKER_GLARE_TILT_DEG := 15.0 # °, 고개 갸웃 (얼굴 축으로 천천히 기울여 그대로 둔다)
const STALKER_GLARE_TILT_AT := 0.2   # s, 노려보기 시작부터 갸웃 시작까지 (상체를 드는 중에 시작한다)
const STALKER_GLARE_TILT_S := 0.45   # s, 다 기울이는 시간 — 깜빡임(끝나기 STALKER_DROP_BLINK_AT 전) 무렵 끝난다. F5: 옛 0.25초에 꺾었다 돌아오기는 너무 빨랐다
const STALKER_GLARE_CRAWL_T := 0.0   # s, 멈춰 둘 crawl 시각
const STALKER_GLARE_FADE_S := 0.15   # s, 놓은 뒤 굽힘을 푸는 시간 — 한 프레임에 풀면 머리가 튄다
const STALKER_REACH_ON := true       # 팔 뻗기 켬/끔. false = 클립 팔 그대로 (봇 사보타주용)
const STALKER_REACH_FRAC := 0.9      # 팔 길이의 이 비율까지 뻗는다 — 다 펴면 막대처럼 보인다
const STALKER_REACH_AIM_Y := 1.2     # m, 뻗는 목표 = 플레이어 발 위 이 높이(가슴)
const STALKER_REACH_SIDE_M := 0.5    # m, 두 팔 목표를 가슴에서 좌우로 벌리는 거리 (#59). 0 이면 두 손이 노려보는 얼굴 바로 앞을 가린다(플레이어 시점 캡처 92n)
const STALKER_FALL_CLIP := "land_hard"   # 낙하 클립. land_hard 의 공중 구간(0 ~ STALKER_LAND_FROM)을 낙하 시간에 맞춰 늘여 튼다. "fall_air" = 옛 동작(Falling Idle, 팔을 벌린다)
const STALKER_FALL_UPRIGHT_AT := 0.9 # 낙하 시간의 이 비율에서 몸이 똑바로 선다 — 착지 전에 다 서 있게
# 낙하 가리기 (#58). F5(09-13 16-39-18 영상 7.1~7.3초): 공중에서 몸이 옆으로 누운 채 한 덩어리로 돌아 어색하다 → 조사 #56 7편 중 6편처럼 그 순간을 가린다.
# 헤드램프 **빛만** 끈다(Player.lamp_blackout) — lamp_on 은 그대로라 괴물 눈·감독 버릇 세기·눈 적응이 안 바뀐다
const STALKER_DROP_BLACK := true     # 끄면 #57 그대로 (되돌리기·사보타주용)
const STALKER_DROP_BLINK_AT := 0.15  # s, 매달림이 끝나기 이만큼 전에 한 번 깜빡 — "곧 온다"
const STALKER_DROP_BLINK_S := 0.05   # s, 예고 깜빡임이 꺼져 있는 시간 (3프레임)
const STALKER_DROP_DARK_AFTER := 0.12   # s, 착지한 뒤에도 더 꺼져 있는 시간 — 켜질 때 이미 웅크려 있게
const STALKER_DROP_LIGHT_S := 0.08   # s, 다시 켜지는 데 걸리는 시간 (툭 켜진다)
const STALKER_DROP_DUST := 80        # 알, 손을 놓은 천장에서 쏟아지는 흙먼지 (파괴 먼지 DEATH_DUST 와 같은 양)
const STALKER_CLIP_RUN_STAND := 4.05 # m/s, run_stand(zombie run) 실측 자연 속도. 추격 6.5 → 1.6배속
const MINER_CLIP_Y_OFFSET := {"climb_down": -2.61}   # m, 클립이 원점에서 떠 있는 만큼 몸을 내린다 (실측: 내려가는 클립은 첫 프레임이 3 m 위)
const STALKER_CLIP_WALK := 1.0       # m/s, walk_crouch 가 "제속도"로 보이는 이동 속도. 재생 배율 = 속도 ÷ 이 값 (최소 MINER_ANIM_SPEED). #45 세트 B Creeping Zombie Walk 의 실측 자연 속도는 0.45 — 그대로면 배회 2.5 에서 5.5배라 1.0 으로(2.5배, 미끄러짐 감수). 세트 A Crouched Walking 실측 1.24
const STALKER_CLIP_RUN := 3.0        # m/s, run 클립의 실측 자연 속도 (#45 세트 B running crawl 3.01. Mutant Run 3.11, zombie run 4.05). 추격 6.5 → 2.2배
const PRESSURE_UP := 2.0             # /s, 괴물이 숨어 있거나 PRESSURE_FAR_M 밖이면 오름
const PRESSURE_DOWN := 5.0           # /s, PRESSURE_NEAR_M 안이면 내림
const PRESSURE_FAR_M := 40.0
const PRESSURE_NEAR_M := 15.0
const PRESSURE_SEND := 80.0          # 여기 닿으면 시야 밖 곡선 칸에 내려놓음
const PRESSURE_RECALL := 20.0        # 여기 밑이면 철수
const PRESSURE_FLOOR_MUL := 0.25     # 층마다 오르는 속도 +25 % (층 수 = 난이도)
const SPAWN_CELLS_MIN := 3           # 등장 자리: 플레이어에서 격자 거리 (곡선 칸, 시야 밖)
const SPAWN_CELLS_MAX := 6
const SPAWN_BEHIND_DOT := 0.3        # 플레이어 앞 방향과 자리 방향의 내적이 이 밑이면 "시야 밖"
const CARD_LAMP_N := 3               # 카드 어둠 수색: 조사·수색·추격 중 20 m 안에서 램프를 끈 횟수
const CARD_CART_N := 2               # 카드 광차 들여다보기: 20 m 안에서 광차에 숙여 탄 횟수
const CARD_HABIT_M := 20.0
const CARD_EAR_MUL := 1.5            # 어둠 수색: 귀 반경 배율
const CARD_DWELL_MUL := 2.0          # 어둠 수색: 수색 머무는 시간 배율
const CARD_DARK_SPEED_MUL := 0.7     # 어둠 수색 텔: 조사·수색이 느려지고 머리를 좌우로 훑는다
const CARD_DARK_SWAY_DEG := 25.0
const CAUGHT_TEXT := "잡혔습니다."
const CAUGHT_TURN_S := 0.4           # s, 잡히면 시점이 괴물 쪽으로 돌아가는 시간. 램프도 같은 시간에 꺼진다
# 정비 1 (#30) — 고장난 지지목. scripts/Fault.gd · RepairPart.gd · RepairHud.gd. 시간값은 ⑦b 판정 전 참고값
const FAULT_SET := 1             # 직선 조각의 세트 번호 (0~3). 그 세트의 post_L 을 숨기고 cap 을 기울인다
const FAULT_CAP_TILT_DEG := 12.0 # 기운 갓보
# 자재함 (#31) — 정거장 앞 첫 직선 오른쪽 벽. E 로 부품 하나. scripts/PartsBin.gd
const ORE_PER_PART := 5          # 좋은 부품 하나에 광석 (사용자 09-10: 3 → 5). 모자라면 삐걱 부품(무한)
const SKILL_ZONE_GOOD_DEG := 90.0   # 좋은 부품 성공 구간 (삐걱 SKILL_ZONE_DEG 50)
const SKILL_INTERVAL_GOOD_MIN := 6.0   # 좋은 부품 체크 간격 (삐걱 3~5)
const SKILL_INTERVAL_GOOD_MAX := 9.0
const PART_GOOD_TINT := Color(1.0, 0.92, 0.75)   # 새 통나무 색 (삐걱은 TIMBER_TINT)
const BIN_SIZE := Vector3(1.2, 0.9, 0.9)
const BIN_DROP := 1.2            # m, 부품이 놓이는 거리 (자재함 앞, 통로 쪽)
const PART_SIZE := Vector3(0.3, 0.3, 2.6)
const CARRY_SPEED_MUL := 0.6     # 들고 있을 때 걷기 배율 (끌기와 같은 규칙). 점프 불가
const CARRY_REACH := 2.5         # m, E 가 먹는 거리 (줍기·세우기)
const REPAIR_HOLD_S := 12.0      # s, 자리당 E 를 누르고 있는 시간
const SKILL_INTERVAL_MIN := 3.0  # s, 스킬체크 간격
const SKILL_INTERVAL_MAX := 5.0
const SKILL_NEEDLE_RPS := 0.8    # 바늘 회전/초
const SKILL_ZONE_DEG := 50.0     # 성공 구간 ("삐걱 부품". 좋은 부품은 #31 에서 넓게)
const REPAIR_FAIL_BACK := 0.25   # 실패 시 진행 후퇴
const DANGER_REPAIR_FAIL := 15.0 # 게이지 (#24: 실패 +M > 성공 −N)
const DANGER_REPAIR_DONE := 5.0
const FAIL_SHAKE_AMOUNT := 0.06  # 실패 흔들림 = 붕괴 흔들림 폭. 소음은 ⑥
const FAIL_SHAKE_TIME := 0.3
const SVC_ON := 1                # 0 = 안 놓음 (비교·사보타주)
const SVC_CABLE_H := 3.2         # m, 케이블 걸이 높이 (광산안전기술기준 80조 "안전높이" = 머리 위)
const SVC_CABLE_SAG := 0.12      # m, 기둥 사이 처짐 (칸 경계에서도 처진다 — 세트 간격 1.75 가 칸을 넘어 이어져서)
const SVC_CABLE_R := 0.024       # m, 동력 케이블 반지름 (개장케이블 지름 48)
const SVC_DUCT_R := 0.30         # m, 풍관 반지름 (지름 600 = 24 in 표준)
const SVC_DUCT_H := 3.9          # m, 풍관 중심 높이 (어깨)
const SVC_DUCT_X := 2.05         # m, 풍관 중심이 갱도 가운데서 왼쪽으로
const SVC_DRAIN_R := 0.075       # m, 배수관 반지름 (지름 150)
const SVC_DRAIN_H := 0.32        # m, 배수관 중심 높이
const SVC_DRAIN_X := 3.05        # m, 배수관 x (오른쪽 벽, 기둥 안쪽 면 3.16 안)
const SVC_DITCH_W := 0.36        # m, 배수로 폭 (왼쪽 벽 옆 x −2.75)
const SVC_LAG_P := 0.45          # 기둥 사이 구간에 라깅(널판)이 있을 확률. 위쪽 2.4~4.4 m 만
const SVC_LAMP_EVERY := 2        # 참고값: 갓등은 세트 0·2 = 3.5 m 마다 (코드는 세트 번호로 박혀 있다)
const SVC_VALVE_EVERY := 8       # 직선 몇 칸마다 밸브+호스 변형
const SVC_JBOX_EVERY := 10       # 직선 몇 칸마다 접속함 변형
const SVC_SIGN_EVERY := 6        # 직선 몇 칸마다 전화기+표지 변형
const SVC_WATER_ROUGH := 0.3     # 배수로 물 거칠기. 0.05 는 거울 = 램프 흰 점
const SVC_TRI_MAX := 4000        # 칸당(L+R) 삼각형 상한
const DRIP_STRETCH := 4.0        # 수직면에서 얼룩을 세로로 늘리는 배율 — 흘러내린 자국
const WET_BAND := 1.2            # m, 바닥에서 이 높이까지는 더 젖는다 — 물은 아래에 고인다
const WET_BAND_ADD := 0.25       # 그 띠에서 노이즈에 더하는 값 (0.18 이면 WET_LOW 를 넘어 확실히 젖음)
const TIMBER_TINT := Color(0.6, 0.52, 0.45)  # 갱목(MAT_Timber) 텍스처에 곱하는 색. 1,1,1 = 텍스처 그대로.
                                 # Blender 의 나무 틴트는 내보내기에서 빠진다 — 여기서 곱한다.
                                 # medieval_wood + (0.42, 0.30, 0.20) 은 "어둡지만 오래된 느낌이 없다"(#19 2차 판정)
                                 # → 텍스처를 dark_wooden_planks 로 바꾸고(export.sh) 틴트는 약하게
const AMBIENT_ENERGY := 0.03     # 램프 밖의 잔광. 0.05 → 0.03. 0 이면 그림자 속이 완전 검정이라 형태가 안 읽힌다
const FOG_DENSITY := 0.03        # 거리 안개. 0.06 은 10m 너머 바닥 무늬까지 뿌옇게 지웠다. 0 이면 끔
const FOG_COLOR := Color(0.006, 0.008, 0.008)  # 잠기는 색. 검정에 가까운 청록.
                                 # 밝게 두면 램프를 꺼도 화면이 이 색으로 남아 "램프 끔 = 어두움" 검사가 깨진다
const VOLFOG_DENSITY := 0.012    # 부피 안개. 램프 원뿔이 공기 중에 빛줄기로 보이는 정도. 0 이면 끔.
                                 # 0.03 은 머리에 단 등이라 화면 전체가 뿌연 덩어리가 됐다(대비 죽음).
                                 # 램프를 이마에 달면 늘 빛줄기 안에서 본다 — 옅어야 한다
const VOLFOG_ALBEDO := Color(0.6, 0.6, 0.55)   # 공기 중 먼지 색. 약간 누런 회색
const VOLFOG_ANISOTROPY := 0.6   # 빛을 앞으로 뿌리는 정도. 클수록 빛줄기가 또렷
const ADJ_CONTRAST := 1.0        # 대비. 1.0 = 그대로. 올리지 마라 — Godot 은 0.5 를 축으로 늘리는데
                                 # 이 게임은 화면 대부분이 0.01~0.1 이라 1.15 만으로 전부 0 에 깔렸다
                                 # (실측: 화면 평균 0.0111 → 0.0026)
const ADJ_SATURATION := 0.75     # 채도. 1.0 = 그대로. 낮출수록 회색 광산
const VIGNETTE := 0.35           # 가장자리 어두워지는 세기. 0 = 없음
const GRAIN := 0.0               # 필름 그레인. 밝기에 곱한다. 0.025 는 "있는지 모르겠다", 0.08 은 "거슬린다"
                                 # (사용자 09-08 두 판정) — 끈다. 켜려면 이 둘만 올린다
const GRAIN_FLOOR := 0.0         # 어둠에서도 남는 알갱이의 바닥값 (0.015 였다). 검은 화면 검사(0.008) 실측 0.0037 안에서.
                                 # 잡음은 평균 0 이지만 검정에서 0 으로 잘려 램프 끔 밝기를 0.006 올렸다

# --- 평타 파편 ---
const CHIP_PER_HIT := 2          # 평타 한 번에 튀는 자갈 수.
                                 # 많으면 벽이 부서질 때와 구분이 안 된다
const CHIP_POP := 2.4            # m/s, 벽에서 튕겨나가는 속도. 조각(1.8)보다 빠르게
const CHIP_LIFE := 1.2           # 초, 파괴 조각(3.0)보다 짧게. 안 쌓이게

# --- 위험 게이지 ---
# #24 규칙 개정 2: 오르는 원인은 수리 실패뿐이다. 곡괭이·리프트·이동은 0.
# 코드 경로(Miner·Lift 의 add_danger)는 남겨 둔다 — 정비(순서표 ⑧)의 "수리 실패"가 같은 함수를 부른다.
# 그때까지 게임 안에서는 게이지가 안 움직인다. 봇은 add_danger 를 직접 넣어 떨림·붕괴를 잰다.
const DANGER_MAX := 100.0        # 바가 꽉 차는 값
const DANGER_PER_HIT := 0.0      # 곡괭이가 포켓에 닿을 때마다. #24 로 0 (1.5 였다)
const DANGER_PER_DROP := 0.0     # 리프트로 한 층 내려가는 동안 거리에 비례해. #24 로 0 (20 이었다)
const DANGER_TREMOR_FROM := 60.0 # 이 값부터 갱도가 주기적으로 떨린다
const DANGER_TREMOR_INTERVAL := 2.0  # 초
const DANGER_TREMOR_AMOUNT := 0.02   # m, 파괴 흔들림(0.06)의 1/3 폭
const DANGER_TREMOR_TIME := 0.4      # 초, 파괴 흔들림(0.15)보다 길게. 폭은 작고 오래
const DANGER_COLOR_LOW := Color(0.30, 0.80, 0.35)   # 0%
const DANGER_COLOR_MID := Color(0.95, 0.80, 0.20)   # 50%
const DANGER_COLOR_HIGH := Color(0.90, 0.20, 0.15)  # 100%

# --- 붕괴 (위험 100) ---
# 돌은 플레이어를 안 맞힌다 (조각 레이어). 죽이는 것은 게이지다.
const DEATH_SHAKE_AMOUNT := 0.15  # m, 파괴 흔들림(0.06)의 2.5배
const DEATH_SHAKE_TIME := 1.2     # 초
const DEATH_ROCKS := 24           # 개, 평타 자갈 메시를 머리 위에서 떨어뜨린다
const DEATH_ROCK_HEIGHT := 3.0    # m, 머리 위
const DEATH_ROCK_RADIUS := 2.5    # m
const DEATH_DUST := 80            # 알, 파괴 먼지(60)보다 많이
const DEATH_LAMP_FADE := 0.9      # 초, 램프 에너지 -> 0
const DEATH_BLACK_TIME := 1.2     # 초, 이때부터 검은 화면
const DEATH_BLACK_FADE := 0.3     # 초
const DEATH_RESTART_TIME := 3.0   # 초, 방을 다시 띄운다
const DEATH_TEXT := "광산이 무너졌습니다."

# 위 값에서 계산되는 것들. 직접 고치지 말고 위를 고친다.
static func accel() -> float:
	return WALK_SPEED / TIME_TO_TOP_SPEED

static func decel() -> float:
	return WALK_SPEED / TIME_TO_STOP

static func jump_velocity() -> float:
	return sqrt(2.0 * GRAVITY * JUMP_HEIGHT)

