extends Node

## 개발용 자동 실행 스크립트. 실행 옵션이 없으면 아무 일도 하지 않는다.
##
##   exe -- --check              숫자 검사 (헤드리스 가능)
##   exe -- --play <출력폴더>     봇이 실제 입력을 주입해 조작
##   exe -- --play <출력폴더> --only <구간,…>   그 구간만 (#37). 구간: base(걷기·포켓·리프트·붕괴 = 인라인 전부) ·
##                               maze(미로·소품·설비·이음새) · cart · repair · lamp · move · miner. 없으면 전부. tools/quick.sh 가 쓴다
##   exe -- --shot <png경로>      스크린샷 한 장
##   godot --write-movie <avi> --fixed-fps 60 -- --film <fixed|nodeck|nodeck_floor>
##                               쇼츠 촬영 (검사 아님). 소스 씬은 안 건드리고 실행 중에 변형을 건다
##
## 봇은 플레이어를 코드로 옮기지 않고 진짜 입력 이벤트를 던진다.
## 조작 경로를 건너뛰면 "검사는 PASS인데 마우스가 안 먹는" 사각지대가 생긴다.

const ROOM_PATH := "res://scenes/level/Tunnel.tscn"
# --film 도 갱도에서 돈다 (#20 부터 리프트가 갱도 정거장에 있다). 옛 방은 TestRoom.tscn 에 남아 있다.
const FILM_ROOM_PATH := ROOM_PATH

# --- 봇 판정 기준 (CLAUDE.md §7: 수치는 밖에 둔다. 이건 검사 기준이라 Tuning 이 아니라 여기) ---
const LOOK_PUSH_X := 300.0      # 주입할 마우스 좌우 이동량 (px)
const LOOK_PUSH_Y := 120.0      # 주입할 마우스 상하 이동량 (px)
const LOOK_MIN_YAW := 0.3       # 이만큼(rad)은 돌아가야 통과
const LOOK_MIN_PITCH := 0.1
const WALK_FRAMES := 60         # W 를 누르고 있는 물리 프레임 수
const WALK_MIN_DIST := 3.5      # m, 이만큼은 가야 통과
const JUMP_MIN_HEIGHT := 0.85   # m
const JUMP_MAX_HEIGHT := 1.15   # m
const WALL_FRAMES := 90         # 벽으로 밀어붙이는 프레임 수
# 갱도 뒤(+Z)는 수갱 정거장(#20). 뒤로 걸으면 리프트에 올라타고 남쪽 난간(안쪽면 z 5.94)에 막힌다.
# 리프트가 없으면 샤프트로 떨어져 뒷벽(z 6.3)까지 날아가므로 이 선을 넘는다.
const STATION_END_Z := 9.3      # 난간 안쪽면 9.64 - 몸 반지름 0.4 + 여유 (#22: 케이지 4.4, 케이지 칸 가운데 z 7.5)
const FLOOR_Y := 0.0            # 바닥 충돌 상자 윗면. 바닥 메시 요철 ±0.06 은 발이 살짝 잠기는 걸로 둔다
const LOWER_FLOOR_Y := -10.0    # 아래층 바닥 (= FLOOR_Y - Tuning.LIFT_DROP. #22: 층 간격 10)
# 광맥 포켓 (#23 수정판). 채굴 벽은 없다 — 막장은 못 캐는 끝막이(mine_face.gltf), 캐는 것은 옆벽 포켓뿐 (#24).
const MINE_HITS := 2            # 25 데미지 x 2 = 포켓 체력 50
const END_CAP_DIST := 3.0       # m, 끝막이 캡처 거리 — 천공 자국·발밑 홈이 읽히는 거리. 끝막이 벽은 칸 가운데에서 3.05 (#27: 자리는 조립 자료에서)
const POCKET_FAR := 4.5         # m, 포켓에서 이만큼 떨어지면 사거리(3.0) 밖
const POCKET_STAND := 1.8       # m, 포켓 앞에 서는 거리 (사거리 안)
const AIM_STEPS := 60           # 마우스 주입으로 포켓을 조준하는 최대 반복
const AIM_PUSH := 60.0          # px, 한 번에 주입하는 최대 마우스 이동
const AIM_TOL := 0.01           # rad, 이 안에 들면 조준 끝
const HIT_SHOTS := 5            # 1타 자갈 연속 캡처 장수
const HIT_SHOT_GAP := 5         # 프레임
const POP_BACK_AFTER := 10      # 2타 클릭 뒤 이만큼 지나(곡괭이가 닿은 0.12초 = 7프레임 뒤) S 로 뒷걸음
const POP_BACK_FRAMES := 45     # S 를 누르는 프레임 수. 4.5m/s × 0.75초 ≈ 3.4m → 포켓에서 5m. 30(2.25m)은 굴러온 광석이 자석(1.8m) 안에 들어 채갔다
const POP_SETTLE_FRAMES := 240  # 4초. 광석이 튀어 바닥에 멎기까지의 상한 — 장수는 정하지 않는다
const POP_SHOT_GAP := 6         # 프레임
const POP_STILL_SPEED := 0.05   # m/s, 이 밑이면 멎은 것
const POP_STILL_FRAMES := 12    # 이만큼 연속으로 멎어 있어야 끝
const POP_MIN_OUT := 0.6        # m, 광석이 벽에서 통로 쪽으로 이만큼은 나와야 한다 (POCKET_POP_OUT 1.4)
const ORE_LOOK_DIST := 2.0      # m, 광석 근접 캡처 거리. 자석 반경(1.8) 바로 밖
# 갱도 구조 (#19 → #20 → #22 7m 격자). MineTunnel 모듈 7×5.6×14m 를 위층 z 0 / -14 / -28 에 셋, 아래층(y -10) z 0 에 하나.
# 수갱 정거장 조각(shaft_station) 위층·아래층 + 섬프(shaft_pit). 케이지 칸 z 5.0~10.0, 리프트(상판 4.4)가 그 위에.
const STATIONS := 3             # Stations 자식: 정거장 2 + 섬프 1
const COLLIDERS := 14           # 정거장 갱도부 바닥·좌벽·우벽 3 × 2층 / 정거장 끝벽 2 / 샤프트 벽 5 / 섬프 바닥 1 (#27: 갱도 상자는 조각 안 -convcolonly). 세트·판·레일·소품은 충돌 없음
const WIDTH_MIN_X := 2.75       # m, 오른쪽 벽으로 밀면 이만큼은 가야 한다 (#27 조각 벽 충돌체 안쪽면 3.2 = 요철 0.3 안쪽 - 몸 0.4 - 여유. 모듈 때 3.35 → 2.9. 4m 갱도면 1.45) — #22 폭 검사
const WIDTH_FRAMES := 60
const CAGE_CORNER := 1.9        # m, 케이지 상판 귀퉁이 (상판 4.4 의 반 2.2 - 0.3). 2.4 상판이면 밖이라 떨어진다 — #22 케이지 크기 검사
const WET_MATERIALS := ["MAT_RockWall", "MAT_Floor"]  # Atmosphere 가 clearcoat 를 얹는 재질 이름 앞부분
const DRY_MATERIAL := "MAT_Timber"                     # 여기엔 안 얹어야 한다 (젖음은 돌만)
# 갱목 광부 모델 (#36) · 괴물 (#35). 클립 길이는 GLB 에서 읽은 값(walk_crouch 32프레임/30fps)
const MINER_CLIP_LEN := 4.067   # s, walk_crouch 길이 (#45 세트 B: Creeping Zombie Walk 121 프레임 @30. 세트 A Crouched Walking 은 1.067)
const MINER_CLIP_TOL := 0.05
const MINER_HAND_X := 1.156      # 손 정점 = 메시(rest, 배율 전) |x| 가 이 밖 (#42: Hand 뼈 머리 1.136 + 2 cm)
const MINER_HAND_FRAC := 0.15    # 손 정점 / 몸 정점 하한 (#42): 실측 — 따로 붙인 손 41,505 / 111,922 = 37 % · 옛 소시지 손 약 8 %(Blender 정점 2,217 / 27,474). 옛 GLB 로 되돌리면 FAIL
const MINER_CHEST_RELIEF_MIN := 0.010   # m, 오른쪽(뼈 쪽, x<0) 가슴 앞면 3 cm 격자 라플라시안 RMS 하한. #45 TRELLIS 몸 실측 17.3 mm(갈비가 형태) · #43 밀착 몸 7.0 · 그 전 4.7 — 옛 GLB 로 되돌리면 FAIL
const MINER_CHEST_RATIO := 1.0          # 오른쪽 / 왼쪽 요철 비 하한. #45: TRELLIS 몸은 살 쪽도 찢긴 살이라(왼쪽 14.6 mm) 좌우 비는 뜻이 없어 1.0 (#43 때 1.35)
const MINER_VERTS_MIN := 50000  # 몸 메시 정점 하한 (#41): GLB 실측 — 옛 전신 한 덩어리 31,535 · 머리 따로 붙인 것 70,698 (UV 이음새로 정점이 갈라진다). 옛 GLB 로 되돌리면 FAIL
const STALKER_FAR_M := 11.0     # m, 먼 캡처 거리 (램프 14 안, 눈 12 안 — 눈높이 차까지 12 안에 들게)
const STALKER_NEAR_M := 8.0     # m, 눈 시험 거리 (원뿔 안, 사거리 12 안)
const STALKER_POSE_JUMP_M := 0.25   # m, 자세가 바뀔 때 머리가 한 프레임에 움직여도 되는 최대 (#47). 실측 0.21(클립이 가장 빠른 구간), 안 섞으면 약 1.3 m 튄다
const STALKER_HAND_SINK_M := 0.05   # m, 기는 동안 손끝이 바닥 밑으로 들어가도 되는 깊이 (#46). 보정 없으면 0.48~0.52 잠긴다
const STALKER_CEIL_KEEP_M := 0.15   # m, 천장 이동 중 붙은 높이가 흔들려도 되는 포폭 (#48)
const STALKER_GLARE_LIFT_OVER := 15.0  # °, 노려보는 동안 상체(엉덩이 → Spine2)가 천장면에서 들린 각이 천장 기기 자세 최대보다 더 들려야 하는 몫 (#59).
                                       #   crawl 자체가 상체를 40.7° 까지 든다 — 고정 문턱 35 는 굽힘을 꺼도(39.6°) 통과했다 (사보타주로 확인)
const STALKER_GLARE_AIM_MIN := 0.9     # 노려보는 동안 얼굴 앞 방향과 플레이어 눈 방향 일치 하한 (#59. 0.9 = 약 26° 안)
const STALKER_GLARE_GAP_M := 0.1       # m, 노려보는 동안 엉덩이·발–천장 거리가 천장 기기 자세 최대보다 더 떨어져도 되는 몫 (#59)
const STALKER_GLARE_BREATH_M := 0.01   # m, 노려보는 동안 머리 높이가 흔들린 폭 하한 — 숨쉬기 (#59. ±3° 면 약 0.1)
const STALKER_GLARE_TILT_MIN := 10.0   # °, 고개 갸웃 최대각 하한 (#59. 제안 15)
const STALKER_AIM_MIN := 0.5        # 매달린 팔(어깨 → 손)과 플레이어 가슴 방향 일치 하한, 두 팔 평균 (#57. 1 = 정확히 · 0.5 = 60° 안)
const STALKER_SPREAD_MAX := 1.6     # 매달림~낙하 두 손 사이 ÷ 어깨 너비 상한 (#57). 실측으로 정한다 — 아래 print 참고
const STALKER_LAND_TILT_DEG := 10.0 # °, 착지 직전 공중 프레임에서 몸이 선 각 상한 (#57)
const STALKER_RELIGHT_F := 18       # 물리 프레임, 착지 → 램프 다시 켜짐(에너지 90 %) 상한 (#58). STALKER_DROP_DARK_AFTER 0.12 + 켜기 0.08 = 12 + 여유
const STALKER_DROP_JUMP_M := 1.0    # m, 매달림~낙하에 머리가 물리 프레임 하나에 움직여도 되는 높이 (#57). 떨어지는 속도(최대 약 8 m/s = 0.14)
                                    #   + 엉덩이에서 2.2 m 떨어진 머리가 270° 를 0.32초에 도는 몫(프레임당 약 0.5)에 여유.
                                    #   놓는 순간 몸 높이가 0 으로 되돌아간 버그는 3.68. 캡처 멈춤 뒤 애니메이션 따라잡기(1.26~1.49)는 _drop_watch 가 뺀다
const WALL_GAP_MAX_M := 0.10        # m, 벽을 타는 동안 몸 중심과 벽면 사이 (#49). 옆 값 0.7 은 보이는 벽(3.16) 밖 허공이었다 — 사보타주로 되돌려 본다
const WALL_COLLIDER_X := 3.20       # m, 조각 벽 충돌체 안쪽면 (#27). 보이는 벽 3.16 보다 밖이라 그 사이는 허공이다
const WALL_LAND_CLEAR_M := 0.15     # m, 바닥에 내려선 몸(반지름 0.6)과 벽 충돌체 사이 최소 틈 (#49 수정)
const WALL_LAND_WALK_M := 0.5       # m, 내려선 뒤 2초 안에 이만큼은 가야 한다 (안 갇혔다)
const STALKER_SINK_Y := -0.05       # m, 괴물이 바닥 밑으로 내려가도 되는 깊이
const CLIMB_STUCK_FRAMES := 135     # 프레임(time_scale 4 배 = 게임 9초), 벽 한 번 오르내리는 데 6.6초 — 이보다 오래 climb 이면 갇힌 것 (#49 수정 3)
const BODY_UP_MAX_DEG := 15.0       # 도, 벽에서 벗어난 뒤 몸의 위가 면 법선에서 벌어져도 되는 각 (#49 수정 2: 안 세워 주면 머리를 바닥에 박고 걷는다)
const SURF_TURN_MAX_DEG := 30.0     # 도, 붙은 면의 법선이 한 프레임에 돌아도 되는 각 (#49 아치 전환)
const RETREAT_CLIMB_UP_FRAMES := 480  # 프레임(8초), 철수하려고 벽을 한 번 오르는 데 6.6초 + 여유. 넘으면 소리에 뒤집혀 내려왔다 다시 오른 것 (#55)
const RETREAT_CLIMB_FRAMES := 540    # 프레임(9초), 철수가 끊겨 내려오는 데 6.6초. 그 뒤로도 벽에 붙어 있으면 같은 자리에서 다시 타고 올라간 것 (#54)
const CEIL_CHASE_GAIN_M := 0.6      # m/s, 달려 도망치는 플레이어와 벌어지는 최대 속도 (#52). 달리기 7.0 − 천장 추격 6.5 = 0.5 에 여유 0.1.
                                    # 옛 천장 속도 2.5 로는 4.5 m/s 로 멀어졌다 — 사보타주로 되돌려 본다
const QUIET_FRAMES := 1800             # 물리 프레임, 번갈기 검사 길이 (time_scale 4 = 게임 120초). #59: 60초(900)는 난수 순서에 따라 20~28 % 로 흔들렸다
const CEIL_DWELL_PCT := [25.0, 60.0]   # %, 조용한 120초 동안 천장 체류 비율 (#49). 한 주기 = 바닥 10 + 벽 6.6 + 천장 12 + 벽 6.6 = 35.2 s 라
                                       # 정상 상태는 34 %, 바닥에서 시작하는 60초 창에서는 27 % 로 읽힌다 (제안서의 "약 40 %"는 천장에서 시작한 값)
const NOISE_DOWN_FRAMES := 180      # 프레임, 천장에서 소음을 듣고 내려오기 시작하기까지 (= 3초)
const SKIN_NEAR_M := 6.0        # m, 재질 밝기 검사 거리 (#39). 램프 원뿔 안, 몸이 화면 가운데 원을 채운다
const SKIN_CLOSE_M := 3.0       # m, 재질 캡처 97 (해골·근육이 읽히나)
const SKIN_FACE_M := 1.5        # m, 캡처 99 (#40): 잡히는 거리의 얼굴
const SKIN_FACE_UP_DEG := 45.0  # 캡처 99 시선 올림: 1.5 m 앞 머리(1.5배 웅크림 약 2.9 m) − 눈 1.7 → atan(1.2/1.5) ≈ 39°. 15°·30° 는 가슴만 찍혔다
const SKIN_HAND_M := 2.2        # m, 캡처 99b (#42): 1.5 m 는 몸통이 화면을 다 덮어 손이 안 잡혔다
const SKIN_HAND_DOWN_DEG := 12.0   # 99b (#42): 시선 아래 — 웅크린 손이 허리 높이, 양옆
const SKIN_DISK_R := 80         # px, 화면 가운데 원 = 6 m 괴물 몸통. 밖 = 2~3 m 벽
const SKIN_LUMA_ON_MIN := 0.03  # 켜고 6 m 가운데 밝기 하한 — 이 밑이면 검댕이 너무 짙어 안 보인다
const SKIN_LUMA_ON_MAX := 0.25  # 상한 — 위면 블록아웃처럼 하얗게 뜬 것
const SKIN_LUMA_OFF_GAIN := 0.004  # 끄고 4 s: 괴물 원 − 벽 가장자리. 위면 실루엣이 남은 것 (#32 수정 2: 벽 가장자리 0.0114)
const SKIN_ROUGH_MIN := 0.9     # 광부 재질 전부 무광
const SKIN_TEST := true         # 임시 bisect
const STALKER_HIDE_WAIT := 1500 # 프레임, 철수 → 숨김 상한 (25 s). #50 부터 벽 6.6초 + 천장 8.4초를 거쳐 사라진다
# 사거리 밖 검사에서 버튼을 누르고 있는 프레임 수.
# 부술 수 있다면 확실히 부서지고도 남을 길이여야 한다 — 짧으면 "사거리 밖"과
# "덜 쳤음"을 구분 못 해서, 사거리가 뚫려도 검사가 통과한다. 실제로 통과했다.
# 2번 치는 데 2 x 0.35초 = 42프레임. 그 세 배를 잡는다.
const MINE_FAR_FRAMES := 150
const ORE_FAR := 4.0            # m, 자석 반경(1.8) 밖. 여기서는 안 줍혀야 한다
const ORE_SETTLE_FRAMES := 90   # 광석이 튀었다가 바닥에 멎을 때까지
# 리프트 (#20 에서 갱도로 돌아왔다). 정거장 케이지 칸 가운데 (0, 0, 4.8). 상판 2.4x2.4, 난간 세 면, 트인 면은 갱도 쪽(-Z).
const LIFT_CENTER := Vector3(0.0, 0.0, 7.5)
const LIFT_RAIL_FRAMES := 70    # 난간 쪽으로 밀어붙이는 프레임 수
const LIFT_RAIL_Z := STATION_END_Z   # 남쪽 난간 안쪽면(z=5.94)에서 몸 반지름(0.4)을 뺀 선에 여유. 이보다 멀리 가면 난간을 뚫은 것
const LIFT_MIN_DROP := 9.5      # m, E 한 번에 이만큼은 내려가야 한다 (설계 10.0)
const LIFT_RIDE_GAP := 0.30     # m, 내려가는 동안 사람과 상판의 높이 차 허용치.
                                # 상판 충돌체가 없으면 사람이 그대로 8m 를 떨어져서 이 값이 8.05 로 벌어진다 (#10 사보타주)
const LIFT_DROP_FRAMES := 600   # 10초. 7.7초면 닿는다
const LIFT_SHOT_GAP := 40       # 하강 캡처 간격. 장수는 정하지 않는다 — 멎을 때까지 (#12)
# 케이지 문 (#21). E → 문이 LIFT_GATE_TIME 에 닫힘 → 출발. 닫히는 동안 Gate 충돌체가 켜져 못 내린다.
const GATE_SHOT_GAP := 12       # 문 닫힘 캡처 간격. 장수는 정하지 않는다 — 다 닫힐 때까지
const GATE_MAX_FRAMES := 90     # 1.5초. 0.8초면 닫힌다
const GATE_PUSH_FRAMES := 30    # 하강 중 문 쪽(-Z)으로 미는 프레임 수
const ROOF_MAX_RISE := JUMP_MAX_HEIGHT   # m, 케이지 안 점프. 지붕 3.0 은 머리(1.8 + 점프 1.0) 위라 닿지 않는다 — 지붕 충돌체는 노드 검사로만 본다 (#21 수정 때는 2.4 지붕에 0.6 에서 막혔다)
const LIFT_GATE_Z := LIFT_CENTER.z - 2.2 + 0.4 - 0.05   # 문 안쪽면(z 3.6)에서 몸 반지름(0.4)을 뺀 선에 여유. 이보다 앞이면 문을 뚫은 것
const DROP_MID_Y := 5.0         # m, 이만큼 내려간 시점에 위험을 잰다 (#24: 하강은 0 — 중간에도 그대로여야 한다)
# 헤드램프 판정. 트인 자리에서 먼 벽을 볼 때의 화면 밝기.
# 태양광이 켜져 있으면 모서리(램프가 안 닿는 곳)까지 밝아진다.
const LAMP_GRID := 32           # 화면 밝기를 잴 때 가로·세로로 뽑는 점 수
# 실측(화면 평균 밝기):
#   2026-09-06 옛 회색 벽 — 켬 0.0317 / 끔 0.0109
#   2026-09-08 #17 젖은 검은 돌 + 안개 — 켬 0.0182 / 끔 0.0095
#   2026-09-08 #17 수정 (원뿔 40°·흰 빛·clearcoat·그레인 바닥값) — 켬 0.0331 / 끔 0.0117
#     끔이 오른 것은 그레인 바닥값이 검정에서 0 으로 잘려 평균이 조금 뜨는 탓
#   2026-09-08 #19 MineTunnel 갱도 (입구에서 -Z, 밝은 갱목) — 켬 0.1195 / 끔 0.0080   <- 지금 기준
#     켬이 3.6배 오른 것은 갱목 텍스처가 밝아서다(틴트가 내보내기에서 빠짐). 문턱은 그대로 둔다 —
#     램프가 죽으면 0.008 로 떨어져 MIN_LIT 에 걸리고, 모듈 조명 4개가 살아나면 MAX_DARK 에 걸린다
#   태양광 되살린 사보타주(09-06) — 켬 0.0949 / 끔 0.0802   <- 여기서 FAIL 이 나야 한다
const LAMP_MIN_LIT := 0.022     # 램프를 켜면 이만큼은 밝아야 한다 (램프가 죽으면 0.008 로 걸린다)
const LAMP_MAX_DARK := 0.018    # 램프를 끄면 이 밑으로 떨어져야 한다.
const ADAPT_MIN_LUMA := 0.010   # F 로 끄고 4초 뒤 눈 적응(#32)으로 가장자리(가까운 벽)가 이만큼은 보여야 한다. #32 수정 2: 0.020 → 0.010 (B 실측 0.0114).
                                #   0.008 은 사보타주(환경광 0.03)를 못 잡았다 — 안개 색(0.006/0.008)이 0.45 로 짙어지면 그것만으로 0.0086 이 된다
const ADAPT_NEAR_GAIN := 0.002  # 가장자리 − 가운데. 적응이 있으면 가까운 것이 먼 것보다 밝다 (B 0.0032 / 환경광 0.03 사보타주 0.0009)
const ADAPT_MAX_LUMA := 0.080   # 그래도 이보다 밝으면 "끄기"가 의미 없다
const ADAPT_DISK_R := 150       # px, 화면 가운데 원 = 먼 복도 (#32 수정). 가장자리 = 그 밖 (2~3 m 벽)
const BOT_WINDOW := Vector2i(1140, 641)  # 봇 창 = 캡처 크기 (-31b). 골든과 화면 비율 검사(램프 적응 가운데 원 등)가 이 크기로 재져 있다
const ADAPT_CENTER_RATIO := 0.5 # 적응 뒤 가운데 원 밝기는 램프 켠 가운데의 이 비율 밑 — 환경광은 거리가 없어 복도 끝까지 비췄다 (사용자 F5: "끄면 더 잘 보인다")
                                # 다른 빛(태양광·모듈 전구 등)이 남아 있으면 안 떨어진다
# 램프 지연 (#17 수정). 마우스로 시점을 홱 돌린 직후 램프는 뒤에 남아 있다가 따라붙는다.
# LAMP_FOLLOW_TIME 0.10초 = 물리 프레임당 15% 씩 좁힌다. 1프레임 뒤 잔여 85%, 30프레임 뒤 0.7%.
const LAMP_LAG_MIN_DEG := 5.0    # 돌린 직후 process 2프레임: 최소 이만큼 뒤처져야 한다.
                                 # 붙어 있으면(FOLLOW_TIME 0 사보타주) 정확히 0.0. 정상은 10~27° —
                                 # 직전 png 저장 stall 뒤 첫 process delta 가 커서 실행마다 다르다. 15 는 10.2 로 걸렸다
const LAMP_LAG_FRAMES := 30      # 이만큼 뒤에는 따라붙어 있어야 한다
const LAMP_LAG_MAX_DEG := 2.0
# 빛줄기 캡처 (#17). 제자리 90° 회전 5장. 부피 안개 속 램프 원뿔이 쓸고 가는 것.
const BEAM_SHOTS := 5
const BEAM_TURN_DEG := 90.0
const BEAM_SHOT_GAP := 6        # 프레임. 부피 안개는 몇 프레임에 걸쳐 수렴한다
# 스윙 하나는 내려치기 0.12 + 되돌리기 0.23 = 0.35초(21프레임). 그 두 배를 잡는다.
const SWING_IDLE_FRAMES := 45
# 스윙 연속 캡처. 한 장짜리는 "지금 어떻게 생겼나"만 답한다 — 2일차에 곡괭이가
# 뒤로 도는데도 통과한 이유. 클릭 기준 0·5·10·15·20 프레임, 내려가는 중과
# 되돌아오는 중이 둘 다 들어간다. 첫 장(0)은 쉬는 자세라야 qc.py 궤적의 바탕이 된다.
const SWING_SHOTS := 5
const SWING_SHOT_GAP := 5
# 위험 게이지 떨림. 60 이상이면 2초마다 Head 가 0.02m 폭으로 흔들린다.
# 3초면 최소 한 번은 떨린다. 59 에서는 Head 가 한 치도 안 움직여야 한다.
const TREMOR_FRAMES := 180
const TREMOR_SHOT_GAP := 20     # 9장. 떨림 0.4초(24프레임)가 20 간격 사이에 낀다
const TREMOR_MIN_OFFSET := 0.005  # m, 떨렸다고 볼 Head 이동량 (폭 0.02 의 1/4)
const TREMOR_MAX_STILL := 0.0005  # m, 안 떨릴 때 허용 이동량
# 붕괴. 맨 끝에서 값을 넣어 죽인다. 방이 다시 뜨면 앞의 참조가 전부 죽는다.
const DEATH_FRAMES := 150         # 2.5초. 재시작(3.0초) 전에 끝내야 참조가 산다
const DEATH_SHOT_GAP := 10        # 15장
const DEATH_MIN_ROCKS := 12       # 30프레임 뒤 방에 떨어지는 돌. 24개 중 상한(40)에 밀려도 이만큼
const DEATH_MAX_LAMP := 0.1       # 60프레임(1초) 뒤 램프 에너지. 0.9초에 0 이 된다
const DEATH_MAX_MOVE := 0.05      # m, 죽은 뒤 W 30프레임 이동 허용치
const DEATH_MAX_LUMA := 0.008     # 90프레임(1.5초) 뒤 화면 밝기. 글자만 남는다
const DEATH_RESTART_WAIT := 120   # 재시작을 기다리는 최대 프레임 (3.0초 - 2.5초 + 여유)
# 조각 카탈로그 (#26). 조각은 갱도 밖 빈자리에 하나씩 세워 재고 찍는다 — Tunnel 씬은 안 건드린다 (조립은 #27).
const CATALOG_Y := -60.0          # m, 세우는 자리 (아래층 -10 보다 훨씬 밑, 아무것도 없다)
const CATALOG_COUNT := 13         # 갱도 9 + 레일 4
const CATALOG_FACES := 18         # 뚫린 면 수 (A 16 + D 2). 표에서 X 를 뺀 것 — 표를 줄이면 여기도
const CATALOG_MIN_OUTLINE := 40   # 뚫린 면 테두리 정점 최소 수 (아치 21 + 바닥 21 - 겹침. 벽 기둥이 이웃 것이면 없어도 된다 — 곡선 안쪽 모서리·갈림 모퉁이)
const CATALOG_SETTLE := 40        # 프레임, 조각 바닥에 내려서기
# 층 조립 (#27, MineAssembler). 실측값은 시드 7·8 의 첫 조립에서 확정 — Tuning 의 MAP_SEED·손잡이를 바꾸면 여기도 바뀐다
const LAYER_CELLS := [551, 528]   # 층마다 칸 수 (시드 7 · 8)
const LAYER_RAIL := [137, 150]    # 층마다 레일 칸
const LAYER_ROOMS_MIN := 5        # 층당 방(목) 최소
const LAYER_CURVES_MIN := 100     # 층당 곡선 최소 (#25: 직선만인 길은 없다)
const LAYER_JUNC_MIN := 50        # 층당 갈림 최소
const LAYER_TERMS_MIN := 2        # 층당 종점(레일 막다른 끝) 최소
const POCKETS_TOTAL := 318        # 두 층 포켓 수 (위층 167 · 아래층 151. 자리 약 1,600 × 10% + 층마다 최소 1)
const PROPS_TOTAL := [372, 357]   # 층마다 소품 수 (#27 수정: 무더기 2~3개 × 직선 20%·갈림 50%·끝막이·방)
const PROP_YAWS_MIN := 5          # 소품 각도가 이만큼은 달라야 한다 (전부 같으면 복제품)
const MAZE_STAND := 1.5           # m, 조각의 뚫린 면 밖에서 이만큼 떨어져 선다 (면은 칸 가운데에서 3.5)
const CURVE_WALK_FRAMES := 60     # 곡선 안으로 W 를 누르는 프레임 (5장)
const CURVE_WALK_MIN := 3.0       # m, 그동안 이만큼은 가야 한다
const MAP_PX := 12                # 평면도 한 칸 픽셀
# #27 수정: 램프 흰 점·질감·소품 무더기
const SPOT_MAX_RATIO := 1.6       # 벽 1.6 m·바닥 캡처: 중앙 200×200 안에서 가장 밝은 30×30 덩이의 평균 ÷ 200×200 평균.
                                  # 물막(clearcoat 1) 흰 점이 있으면 1.9~2.3, 없으면 1.25~1.37 (실측 #27 수정). 최대 밝기로 재면 밝은 텍스처(rock_face_04)도 1.0 이라 못 가른다
const SPOT_BOX := 200             # px
const SPOT_BLOB := 30             # px, 흰 점 크기(지름 약 20 px)보다 조금 큰 창
const TEX_BIG := 2048             # 벽·바닥 알베도 한 변
const CLUSTER_VISIBLE_FRAC := 0.8 # 무더기 중 이만큼은 복도 가운데 5 m 뒤에서 램프 원뿔 안·8 m 안
const CLUSTER_VIEW_DIST := 5.0    # m, 칸 가운데에서 뚫린 면 쪽으로
const CLUSTER_MAX_DIST := 8.0     # m
# #27 수정 2: 이음새 틈
const SLIT_MAX_PX := 400          # 갈림 모서리 캡처(램프 원 안, 반지름 230 px) 검은 픽셀(밝기 < 0.01) 평균 상한. 칼라 전 1,400~1,950, 직선-직선 40~160
const SLIT_DISK_R := 230          # px
const SLIT_LUMA := 0.010
const SEAM_STAND := 1.3           # m, 이음새 가운데 바닥점에서 옆으로 — 벽(3.5)까지 2.2 m
const SEAM_STAND_D := 0.6         # m, 문(목 ↔ 방) 이음새는 반폭 1.75 라 이만큼만 (--seams 첫 실행에서 문 5곳이 카메라가 벽 안이라 최악으로 잡혔다)
const DIR3: Array[Vector3] = [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0)]   # N E S W
const YAW_OF: Array[float] = [0.0, -PI / 2.0, PI, PI / 2.0]   # 그쪽을 보는 player.rotation.y

var _out_dir := "build"
var _failed := false
var _only: PackedStringArray = []   # --only 구간 이름 (#37). 비어 있으면 전부
const STAGES: PackedStringArray = ["base", "maze", "cart", "repair", "lamp", "move", "stalker"]
# 연속 캡처는 메모리에 담아 뒀다가 동작이 끝난 뒤 한꺼번에 저장한다.
# save_png 는 게임을 잠깐 멈추고, 스윙 도중에 다섯 번 멈추면 찍히는 각도가
# 실행마다 달라진다.
var _burst: Array[Image] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--check" in args:
		_run.call_deferred(_check_routine)
	elif "--play" in args:
		var i := args.find("--play")
		_out_dir = args[i + 1] if i + 1 < args.size() else "build"
		var j := args.find("--only")
		if j >= 0 and j + 1 < args.size():
			_only = args[j + 1].split(",", false)
		_run.call_deferred(_play_routine)
	elif "--shot" in args:
		var i := args.find("--shot")
		var path: String = args[i + 1] if i + 1 < args.size() else "build/shot.png"
		_run.call_deferred(_shot_routine.bind(path))
	elif "--seams" in args:
		var i := args.find("--seams")
		_out_dir = args[i + 1] if i + 1 < args.size() else "build"
		_run.call_deferred(_seams_routine)
	elif "--tour" in args:
		var i := args.find("--tour")
		_out_dir = args[i + 1] if i + 1 < args.size() else "build/tour"
		_run.call_deferred(_tour_routine)
	elif "--texcmp" in args:
		var i := args.find("--texcmp")
		_out_dir = args[i + 1] if i + 1 < args.size() else "build"
		_run.call_deferred(_texcmp_routine)
	elif "--mapdump" in args:
		var i := args.find("--mapdump")
		_out_dir = args[i + 1] if i + 1 < args.size() else "build/mapdump.json"
		_run.call_deferred(_mapdump_routine)
	elif "--film" in args:
		var i := args.find("--film")
		var variant: String = args[i + 1] if i + 1 < args.size() else "fixed"
		if variant == "cart":
			_run.call_deferred(_film_cart, ROOM_PATH)
		elif variant in ["maze", "lamp", "services"]:
			_run.call_deferred(_film_mine.bind(variant), ROOM_PATH)
		elif variant == "walk_room":
			_run.call_deferred(_film_walk.bind(variant), "res://scenes/level/TestRoom.tscn")
		elif variant == "walk_tunnel":
			_run.call_deferred(_film_walk.bind(variant), "res://scenes/level/Tunnel.tscn")
		else:
			_run.call_deferred(_film_routine.bind(variant), FILM_ROOM_PATH)


## 템플릿 메뉴를 건너뛰고 방(갱도)만 띄운다. 개발용 경로라서 SceneLoader 를 쓰지 않는다
## (CLAUDE.md §5 의 SceneLoader 규칙은 사람이 지나는 화면 전환에 대한 것).
func _run(routine: Callable, path: String = ROOM_PATH) -> void:
	var tree := get_tree()
	await tree.process_frame
	if tree.current_scene != null:
		tree.current_scene.queue_free()
		await tree.process_frame
	var room: Node3D = (load(path) as PackedScene).instantiate()
	tree.root.add_child(room)
	tree.current_scene = room
	await tree.process_frame
	await routine.call(room)


# ---------------- --check : 숫자 검사 ----------------

func _check_routine(room: Node3D) -> void:
	var player := room.get_node_or_null("Player") as CharacterBody3D
	_check(player != null, "Player 노드 존재")
	_check(room.get_node_or_null("Player/Head/Camera3D") != null, "카메라 존재")
	var lamp := room.get_node_or_null("Player/Head/Headlamp") as SpotLight3D
	_check(lamp != null and lamp.visible and lamp.light_energy > 0.0,
		"헤드램프가 카메라에 달려 켜져 있음")
	_check(room.get_node_or_null("Sun") == null, "태양광 없음 (갱도는 헤드램프 하나)")
	# 개발용 표시 (#38): 디버그 빌드(에디터·소스 검사)에만 있고 배포물(release)에선 _ready 가 지운다
	var dbg := room.get_node_or_null("Player/DebugHud")
	var dbg_alive: bool = dbg != null and not dbg.is_queued_for_deletion()
	_check(dbg_alive == OS.is_debug_build(), "DebugHud 는 디버그 빌드에만 (debug %s, 있음 %s)" % [OS.is_debug_build(), dbg_alive])
	# 모듈 glTF 에 조명이 딸려 들어오면 여기서 걸린다 (export_godot.py 가 조명을 빼고 내보낸다).
	var lights := _count_lights(room)
	_check(lights == 1, "씬 안 Light3D 가 헤드램프 하나 (실제 %d)" % lights)
	# 질감 (#17 → #19). 재질 손질은 실행 중에 일어나므로 씬 파일이 아니라 떠 있는 노드를 본다.
	await _wait(2)          # 후처리 레이어는 call_deferred 로 붙는다
	var modules := room.get_node("Layers")     # #27: 조각들. 이름은 그대로 — 아래 젖음·틴트 검사가 같이 쓴다
	for prefix in WET_MATERIALS:
		var mi := _mesh_with_material(modules, prefix)
		_check(mi != null, "%s 재질을 쓰는 메시가 있음" % prefix)
		var coat: float = _material_clearcoat(mi, prefix)
		_check(is_equal_approx(coat, Tuning.STONE_CLEARCOAT),
			"%s clearcoat %.2f = STONE_CLEARCOAT (젖은 막)" % [prefix, coat])
	# 곡괭이 뷰모델 (#23): 갱도와 같은 재질(MAT_Timber·MAT_RustyMetal)의 pick.gltf. KayKit 팔레트가 남으면 걸린다.
	var pick_node := room.get_node_or_null("Player/Head/Camera3D/Pickaxe")
	_check(pick_node != null and _mesh_with_material(pick_node, "MAT_RustyMetal") != null
		and _mesh_with_material(pick_node, "MAT_Timber") != null and not _any_palette(pick_node),
		"곡괭이 뷰모델 재질 = 갱도의 MAT_RustyMetal·MAT_Timber (팔레트 없음)")
	# 광맥 포켓 (#23 수정판): 스포너가 시드로 놓는다. 수·층마다 최소 1·재질.
	var spawner := room.get_node_or_null("Pockets")
	var pockets: Array = spawner.pockets() if spawner != null and spawner.has_method("pockets") else []
	_check(pockets.size() == POCKETS_TOTAL, "광맥 포켓 %d개 (시드 %d, 실제 %d)" % [POCKETS_TOTAL, Tuning.MAP_SEED, pockets.size()])
	var upper := 0
	var lower := 0
	for p in pockets:
		if (p as Node3D).global_position.y > LOWER_FLOOR_Y * 0.5:
			upper += 1
		else:
			lower += 1
	_check(upper >= Tuning.POCKET_MIN_PER_FLOOR and lower >= Tuning.POCKET_MIN_PER_FLOOR,
		"층마다 포켓 최소 %d (위층 %d · 아래층 %d)" % [Tuning.POCKET_MIN_PER_FLOOR, upper, lower])
	_check(not pockets.is_empty() and _mesh_with_material(pockets[0], "MAT_Ore") != null
		and not _any_palette(pockets[0]), "포켓 재질 MAT_Ore (ore.gltf, 팔레트 없음)")
	var dry := _mesh_with_material(modules, DRY_MATERIAL)
	_check(dry != null and _material_clearcoat(dry, DRY_MATERIAL) < 0.0,
		"%s 에는 clearcoat 없음 (젖음은 돌만)" % DRY_MATERIAL)
	var tint := _material_albedo(dry, DRY_MATERIAL)
	_check(tint.is_equal_approx(Tuning.TIMBER_TINT),
		"%s 에 어두운 갈색 틴트 %s = TIMBER_TINT" % [DRY_MATERIAL, tint])
	var env: Environment = (room.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.fog_enabled and is_equal_approx(env.fog_density, Tuning.FOG_DENSITY)
		and env.volumetric_fog_enabled
		and is_equal_approx(env.volumetric_fog_density, Tuning.VOLFOG_DENSITY)
		and env.adjustment_enabled
		and is_equal_approx(env.adjustment_saturation, Tuning.ADJ_SATURATION),
		"안개 %.2f · 부피 안개 %.2f · 채도 %.2f 가 Tuning 대로"
			% [env.fog_density, env.volumetric_fog_density, env.adjustment_saturation])
	var post := Atmosphere.post_material()
	_check(room.get_node_or_null("PostFx/Rect") != null and post != null
		and is_equal_approx(post.get_shader_parameter("vignette"), Tuning.VIGNETTE)
		and is_equal_approx(post.get_shader_parameter("grain"), Tuning.GRAIN),
		"후처리 레이어 (비네트 %.2f · 그레인 %.2f)" % [Tuning.VIGNETTE, Tuning.GRAIN])
	_check(room.get_node("Collision").get_child_count() == COLLIDERS,
		"충돌 상자 %d개 (정거장 갱도부 3×2 · 정거장 끝벽 2 · 샤프트 5 · 섬프 1 — 갱도는 조각 안)" % COLLIDERS)
	# 수갱 정거장 (#20). 조각이 같은 재질 이름을 쓰므로 젖음도 같은 검사로 잡는다.
	var stations := room.get_node_or_null("Stations")
	_check(stations != null and stations.get_child_count() == STATIONS,
		"수갱 정거장 조각 %d개 (정거장 2 + 섬프)" % STATIONS)
	if stations != null:
		for prefix in WET_MATERIALS:
			var smi := _mesh_with_material(stations, prefix)
			var scoat: float = _material_clearcoat(smi, prefix) if smi != null else -1.0
			_check(smi != null and is_equal_approx(scoat, Tuning.STONE_CLEARCOAT),
				"정거장 %s clearcoat %.2f (젖은 막)" % [prefix, scoat])
		var sdry := _mesh_with_material(stations, DRY_MATERIAL)
		_check(sdry != null and _material_albedo(sdry, DRY_MATERIAL).is_equal_approx(Tuning.TIMBER_TINT),
			"정거장 세트·판(%s)에 TIMBER_TINT" % DRY_MATERIAL)
	var lift := room.get_node_or_null("Lift") as AnimatableBody3D
	_check(lift != null and lift.get_node_or_null("Mesh") != null, "리프트가 정거장에 있음")
	var rails := 0
	if lift != null:
		for c in lift.get_children():
			if c is CollisionShape3D and c.name.begins_with("Rail"):
				rails += 1
	_check(rails == 3, "리프트 난간 충돌체 3개 (실제 %d)" % rails)
	_check(lift != null and lift.get_node_or_null("Deck") != null, "리프트 상판 충돌체")
	_check(lift != null and lift.sync_to_physics, "리프트가 sync_to_physics")
	_check(lift != null and lift.global_position.is_equal_approx(LIFT_CENTER),
		"리프트 위치 %s = 케이지 칸 가운데 %s" % [lift.global_position if lift else Vector3.INF, LIFT_CENTER])
	# 케이지 (#21): KayKit 상자가 아니라 갱도와 같은 재질의 케이지. 문 두 짝은 glTF 노드, 문 충돌체는 씬에.
	_check(lift != null and lift.get_node_or_null("Mesh/CAGE_GateL") != null
		and lift.get_node_or_null("Mesh/CAGE_GateR") != null, "케이지 문짝 2개 (lift_cage.gltf)")
	_check(lift != null and lift.get_node_or_null("Gate") is CollisionShape3D, "케이지 문 충돌체")
	_check(lift != null and lift.get_node_or_null("Roof") is CollisionShape3D, "케이지 지붕 충돌체")
	_check(lift != null and _mesh_with_material(lift, "MAT_RustyMetal") != null
		and _mesh_with_material(lift, "MAT_Timber") != null, "케이지 재질 = 갱도의 MAT_RustyMetal·MAT_Timber")
	_check(lift != null and not _any_palette(lift), "케이지에 KayKit 팔레트 없음")
	_check(lift != null and is_equal_approx(lift.gate_open_ratio(), 1.0)
		and (lift.get_node("Gate") as CollisionShape3D).disabled, "정거장에서 문 열림 (충돌체 꺼짐)")
	await _catalog_checks(room)
	await _layer_checks(room, player)
	if player == null:
		return _finish("CHECK")

	player.global_position = Vector3(0.0, 3.0, -4.0)
	await _wait(180)
	_check(player.is_on_floor(), "바닥에 착지 (is_on_floor)")
	_check(absf(player.global_position.y - FLOOR_Y) < 0.15,
		"착지 높이 %.3f (기대 %.2f)" % [player.global_position.y, FLOOR_Y])

	player.global_position = Vector3(0.0, 1.0, -3.0)
	for i in 60:
		player.velocity = Vector3(0.0, 0.0, 30.0)
		player.move_and_slide()
		await _wait(1)
	_check(player.global_position.z < STATION_END_Z,
		"갱도 뒤로 밀면 리프트 난간에 막힘 (z=%.2f, 한계 %.1f)" % [player.global_position.z, STATION_END_Z])

	_finish("CHECK")


# ---------------- --play : 실제 입력 주입 ----------------

func _play_routine(room: Node3D) -> void:
	var player := room.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		_check(false, "Player 노드 존재")
		return _finish("PLAY")
	var head: Node3D = player.get_node("Head")

	# 창 크기 고정 (-31b). 템플릿 start_up 이 user://player_config.cfg 의 ScreenResolution 을 복원한다 —
	# 사람이 F5 창을 끌어 줄이면 그 값이 저장돼 봇 캡처가 1140 → 1022 px 로 좁아졌다.
	get_window().size = BOT_WINDOW
	await _wait(20)
	var shot_size: Vector2i = get_viewport().get_texture().get_image().get_size()
	_check(shot_size == BOT_WINDOW, "봇 캡처 크기 %s = %s (저장된 창 크기에 안 끌려감)" % [shot_size, BOT_WINDOW])
	await _shot("00_start")
	_pause_directors(room, true)   # 감독은 40 s 면 괴물을 내려놓는다 (#35) — 다른 구간을 재는 동안 봇을 쫓아 잡으면 방이 다시 떠 전부 죽는다. stalker 구간이 스스로 켠다
	# --only (#37): base 가 없으면 이름 붙은 구간 함수만 돌고 끝. base 가 있으면 아래 인라인 전부 + 이름 붙은 구간만
	if not _only.is_empty() and not "base" in _only:
		await _only_stages(room, player, head)
		return _finish("PLAY")

	# 1. 마우스 좌우
	var yaw0: float = player.rotation.y
	_inject_motion(Vector2(LOOK_PUSH_X, 0.0))
	await _wait(3)
	_check(absf(player.rotation.y - yaw0) >= LOOK_MIN_YAW,
		"마우스 좌우가 시점에 닿음 (yaw %.3f → %.3f)" % [yaw0, player.rotation.y])

	# 1-1. 램프가 늦게 따라온다 (#17 수정). 30프레임 뒤엔 붙어 있어야 한다.
	#      카메라에 붙은 옛 구조면 첫 값이 0 으로 걸린다.
	#      물리 프레임으로 기다리면 안 된다 — 직전 save_png 가 게임을 멈춰 물리 3프레임이 한 번에
	#      따라잡히고 그 사이 process 가 0회라, 램프를 안 옮기는 사보타주(FOLLOW_TIME 0)도 37.8° 로
	#      통과했다. 램프는 process 에서 움직이므로 process 프레임을 두 번 지나고 잰다(잔여 약 72%).
	await get_tree().process_frame
	await get_tree().process_frame
	var lag_now: float = player.lamp_lag_deg()
	_check(lag_now >= LAMP_LAG_MIN_DEG,
		"돌린 직후 램프가 뒤처짐 (%.1f°, 최소 %.0f°)" % [lag_now, LAMP_LAG_MIN_DEG])
	await _wait(LAMP_LAG_FRAMES)
	var lag_later: float = player.lamp_lag_deg()
	_check(lag_later <= LAMP_LAG_MAX_DEG,
		"%d프레임 뒤 램프가 따라붙음 (%.2f°, 최대 %.0f°)" % [LAMP_LAG_FRAMES, lag_later, LAMP_LAG_MAX_DEG])

	# 2. 마우스 상하
	var pitch0: float = head.rotation.x
	_inject_motion(Vector2(0.0, LOOK_PUSH_Y))
	await _wait(3)
	_check(absf(head.rotation.x - pitch0) >= LOOK_MIN_PITCH,
		"마우스 상하가 시점에 닿음 (pitch %.3f → %.3f)" % [pitch0, head.rotation.x])

	# 3. W 로 전진. 갱도 가운데(레일 위)를 -Z 로 걷는다. 레일·침목·잔돌은 충돌이 없다
	player.global_position = Vector3(0.0, 0.2, -2.0)
	player.rotation.y = 0.0
	await _wait(20)
	var from: Vector3 = player.global_position
	_inject_key(KEY_W, true)
	await _wait(WALK_FRAMES)
	_inject_key(KEY_W, false)
	var walked: float = Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	_check(walked >= WALK_MIN_DIST, "W 로 %.2f m 이동 (최소 %.1f)" % [walked, WALK_MIN_DIST])
	await _shot("01_walk")

	# 3b. 갱도 폭 (#22). 오른쪽(+X) 벽으로 걸어가면 벽 안쪽면(3.35)에서 몸 반지름을 뺀 선까지 간다 — 4m 갱도면 1.45 에서 막힌다.
	player.global_position = Vector3(0.0, 0.2, -6.0)
	player.rotation.y = -PI / 2.0      # +X 를 본다
	await _wait(20)
	_inject_key(KEY_W, true)
	await _wait(WIDTH_FRAMES)
	_inject_key(KEY_W, false)
	_check(player.global_position.x >= WIDTH_MIN_X,
		"갱도 폭: 오른쪽 벽까지 x=%.2f (최소 %.1f — 4명 나란히)" % [player.global_position.x, WIDTH_MIN_X])
	# 3c. 네 명 나란히 — 사람 크기 더미 3개를 왼쪽에 세우고 한 장 (캡처용. 충돌 없음. 찍고 지운다)
	var dummies := _spawn_dummies(room, [Vector3(-2.4, 0.0, -6.5), Vector3(-0.8, 0.0, -6.5), Vector3(0.8, 0.0, -6.5)])
	player.global_position = Vector3(2.4, 0.2, -3.0)
	player.rotation.y = 0.25
	head.rotation.x = 0.0
	await _wait(30)
	await _shot("23_four_abreast")
	for d in dummies:
		d.queue_free()
	await _wait(2)
	# 오른쪽 벽을 따라 배관을 본다 (#22 수정: 배관이 갱목 기둥 앞을 한 줄로 지나야 한다 — 사용자 "나무 뒤에 박혀 끊어져 있다")
	player.global_position = Vector3(2.2, 0.2, -4.0)
	player.rotation.y = -0.55
	head.rotation.x = deg_to_rad(-8.0)
	await _wait(30)
	await _shot("26_wall_pipe")

	# 4. 스페이스로 점프
	await _wait(30)
	var ground: float = player.global_position.y
	_inject_key(KEY_SPACE, true)
	await _wait(2)
	_inject_key(KEY_SPACE, false)
	var peak := ground
	for i in 120:
		await _wait(1)
		peak = maxf(peak, player.global_position.y)
		if i > 20 and player.is_on_floor():
			break
	var height: float = peak - ground
	_check(height >= JUMP_MIN_HEIGHT and height <= JUMP_MAX_HEIGHT,
		"점프 높이 %.3f m (허용 %.2f~%.2f)" % [height, JUMP_MIN_HEIGHT, JUMP_MAX_HEIGHT])
	_check(player.is_on_floor(), "점프 후 다시 착지")

	# 5. 갱도 뒤(+Z)로 걸어가면 정거장을 지나 리프트에 올라타고 난간에 막힌다. 이동은 키 입력으로 한다.
	#    리프트가 없으면 샤프트로 떨어져 뒷벽까지 날아간다 — 그러면 이 선을 넘는다.
	player.global_position = Vector3(0.0, 0.2, 0.0)
	player.rotation.y = PI
	await _wait(20)
	_inject_key(KEY_W, true)
	await _wait(WALL_FRAMES * 2)     # #22: 정거장 갱도부 5 + 케이지 4.4 — 난간까지 9.6m
	_inject_key(KEY_W, false)
	_check(player.global_position.z < STATION_END_Z,
		"정거장 뒤로 안 나감 (z=%.2f, 한계 %.1f)" % [player.global_position.z, STATION_END_Z])
	_check(player.is_on_floor() and absf(player.global_position.y - FLOOR_Y) < 0.15,
		"걸어서 리프트에 올라섬 (y=%.3f, 기대 %.2f)" % [player.global_position.y, FLOOR_Y])
	# 막장 한 장 — 끝막이(못 캐는 바위 벽)가 갱도 끝을 막고 선 모습. 천공 자국·발밑 홈이 보여야 한다.
	# #27: 위층 첫 끝막이 자리를 조립 자료에서 읽는다 (벽은 칸 가운데에서 3.05 — 뚫린 면 쪽으로 0.05 에 서면 벽까지 3 m)
	var asm := _asm(room)
	var cap_cell: Vector2i = _first_cell(asm.floors[0], "cap") if asm != null else Vector2i(-1, -1)
	if cap_cell.x >= 0:
		var cf: int = MineAssembler._first_bit(asm.floors[0].open[cap_cell])
		_stand_at(player, head, MineAssembler.cell_world(cap_cell, asm.floors[0].y) + DIR3[cf] * (END_CAP_DIST - 3.05 + 0.1), (cf + 2) % 4)
	await _wait(30)
	await _shot("02_end_cap")

	# 5-0. 미로 (#27): 곡선 안으로 걷기 · T · 방 · 대피소 · 종점 · 소품 · 평면도 2장
	if _stage("maze"):
		await _maze_shots(room, player, head)
	# 제안서별 구간 (#29~#36). --only 로 하나씩 돈다 (#37)
	await _proposal_stages(room, player, head)

	# 5-1. 화면을 밝히는 것이 헤드램프 하나인가.
	#      "어두운 구석"을 찾아 재려 했더니 램프 원뿔이 화면을 거의 덮어서
	#      쓸 자리가 없었다. 자리를 고르는 대신 램프를 껐다 켜서 차이를 잰다 —
	#      끄고도 화면이 밝으면 다른 빛이 남아 있는 것이다.
	#      입구에 서서 갱도 안쪽(-Z)을 본다 — 24m 가 안개 속으로 이어지는 화면.
	player.global_position = Vector3(0.0, 0.2, -2.0)
	player.rotation.y = 0.0
	head.rotation.x = 0.0
	await _wait(20)
	var lamp := player.get_node_or_null("Head/Headlamp") as SpotLight3D
	var lit := await _screen_luma()
	await _shot("09_lamp")
	var dark := lit
	if lamp != null:
		lamp.visible = false
		await _wait(2)
		dark = await _screen_luma()
		await _shot("10_lamp_off")
		lamp.visible = true
		await _wait(2)
	print("ok 밝기 램프켬 %.4f / 램프끔 %.4f" % [lit, dark])
	_check(lit >= LAMP_MIN_LIT,
		"램프를 켜면 화면이 보인다 (밝기 %.4f, 최소 %.3f)" % [lit, LAMP_MIN_LIT])
	_check(dark <= LAMP_MAX_DARK,
		"램프를 끄면 갱도가 어두워진다 (밝기 %.4f, 최대 %.3f)" % [dark, LAMP_MAX_DARK])

	# 5-2. 빛줄기 (#17). 갱도 가운데서 제자리 90° 회전하며 5장 — 램프 원뿔이 부피 안개와
	#      벽 요철을 쓸고 가는 것을 본다. 숫자는 못 재고(사용자 F5) 캡처만 남긴다.
	player.global_position = Vector3(0.0, 0.2, -6.0)
	player.rotation.y = 0.0
	head.rotation.x = 0.0
	await _wait(20)
	for i in BEAM_SHOTS:
		player.rotation.y = deg_to_rad(BEAM_TURN_DEG * float(i) / float(BEAM_SHOTS - 1))
		await _wait(BEAM_SHOT_GAP)
		await _grab()
	_flush_burst("19_beam")
	player.rotation.y = 0.0

	# 6. 광맥 포켓 (#23 수정판). 스포너가 시드로 놓은 자리를 읽어 위층 첫 포켓 앞으로 간다.
	#    막장은 못 캐는 끝막이라 칠 것이 없다 — 캐는 것은 옆벽에 박힌 덩이뿐 (#24).
	var spawner: Node3D = room.get_node("Pockets")
	var pockets_first: Array = spawner.pockets()
	var pocket_pos_first: Array[Vector3] = []
	for p in pockets_first:
		pocket_pos_first.append((p as Node3D).global_position)
	var pocket: OrePocket = null
	for p in pockets_first:
		if (p as Node3D).global_position.y > LOWER_FLOOR_Y * 0.5:
			pocket = p
			break
	if pocket == null:
		_check(false, "위층에 광맥 포켓이 있음")
		return _finish("PLAY")
	var pocket_at: Vector3 = pocket.global_position
	var out: Vector3 = pocket.get_meta("out", Vector3(-signf(pocket_at.x), 0.0, 0.0))     # 벽에서 통로 쪽 (#27: 스포너가 조각 원점 쪽으로 적는다)
	var pockets_before := _count_pockets(room)
	player.rotation.y = 0.0
	head.rotation.x = 0.0

	# 6-1. 사거리 밖(4.5m)에서 포켓을 조준하고 클릭해도 안 먹는다.
	player.global_position = pocket_at * Vector3(1.0, 0.0, 1.0) + out * POCKET_FAR + Vector3(0.0, 0.2, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(20)
	await _aim_at(player, head, pocket_at)
	var nz_far: int = NoiseBus.total
	_inject_button(MOUSE_BUTTON_LEFT, true)
	await _wait(MINE_FAR_FRAMES)
	_inject_button(MOUSE_BUTTON_LEFT, false)
	# 해제 이벤트는 다음 입력 처리에서야 먹는다. 같은 프레임에 1.8m 로 옮기면 아직 눌린 채로 포켓을 한 번 친다 (실제로 그랬다)
	await _wait(2)
	_check(_count_pockets(room) == pockets_before and _count_chunks(room) == 0,
		"사거리 밖 %.1fm 클릭은 안 먹음 (포켓 %d개, 자갈 %d)" % [POCKET_FAR, _count_pockets(room), _count_chunks(room)])
	_check(_noise_kind(NoiseBus.since(nz_far), "pick").is_empty(), "허공 휘두름은 소음 0 (#32)")

	# 6-2. 1.8m 앞에서 마우스로 돌아 포켓을 조준한다 — 레이가 포켓을 맞출 때까지.
	player.global_position = pocket_at * Vector3(1.0, 0.0, 1.0) + out * POCKET_STAND + Vector3(0.0, 0.2, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(20)
	var aimed: bool = await _aim_at(player, head, pocket_at)
	var ray := player.get_node("Head/Camera3D/MineRay") as RayCast3D
	ray.force_raycast_update()
	_check(aimed and ray.get_collider() == pocket, "마우스로 돌아 포켓 조준 (레이가 포켓을 맞춤)")
	await _shot("03_pocket_aim")
	var pick: Node3D = player.get_node_or_null("Head/Camera3D/Pickaxe")
	_check(pick != null, "곡괭이가 화면에 들려 있음")
	var danger_before: float = player.danger
	await _wait_pick_idle(pick)

	# 7. 1타: 곡괭이가 돌고, 닿는 순간 자갈이 튀고, 포켓은 남는다. 스윙 연속 캡처는 여기서 —
	#    클릭 기준 0·5·10·15·20 프레임, 내려가는 중과 되돌아오는 중이 둘 다 들어간다. 첫 장(0)은 쉬는 자세.
	var chunks_before := _count_chunks(room)
	var pitch_before: float = pick.rotation.x if pick != null else 0.0
	var nz_hit: int = NoiseBus.total
	await _grab()
	_inject_button(MOUSE_BUTTON_LEFT, true)
	await _wait(4)
	_inject_button(MOUSE_BUTTON_LEFT, false)
	if pick != null:
		# 내려치는 데 0.12초(7프레임) 걸린다. 4프레임 시점이라 아직 도는 중이고, 데미지도 아직 안 들어갔어야 한다.
		_check(absf(pick.rotation.x - pitch_before) > 0.05,
			"클릭에 곡괭이가 돌아감 (%.3f -> %.3f rad)" % [pitch_before, pick.rotation.x])
	_check(_count_chunks(room) == chunks_before, "클릭 직후에는 아직 안 맞음 (곡괭이가 내려가는 중)")
	await _wait(SWING_SHOT_GAP - 4)
	for k in range(1, SWING_SHOTS):
		await _grab()
		if k < SWING_SHOTS - 1:
			await _wait(SWING_SHOT_GAP)
	_flush_burst("08_swing")
	await _shot("82_noise_hud")                                     # 왼쪽 아래 소음 원 (#32) — 타격 뒤 0.4초, 아직 보인다
	var picks := _noise_kind(NoiseBus.since(nz_hit), "pick")
	_check(Tuning.NOISE_PICK > 0.0 and picks.size() == 1 and picks[0]["radius"] == Tuning.NOISE_PICK
		and (picks[0]["pos"] as Vector3).distance_to(player.global_position) <= 3.0,
		"1타 → 곡괭이 소음 1회 (실제 %d), 반경 %.0f > 0, 자리 = 타격점" % [picks.size(), Tuning.NOISE_PICK])
	# 자갈이 튀어 떨어지는 동안 — 1타 연속 캡처
	for k in HIT_SHOTS:
		await _grab()
		await _wait(HIT_SHOT_GAP)
	_flush_burst("05_pocket_hit")
	_check(_count_chunks(room) - chunks_before == Tuning.CHIP_PER_HIT,
		"1타에 자갈 %d개 튐 (기대 %d)" % [_count_chunks(room) - chunks_before, Tuning.CHIP_PER_HIT])
	_check(_count_pockets(room) == pockets_before, "1타 뒤 포켓은 남아 있음 (%d개)" % _count_pockets(room))
	await _wait_pick_idle(pick)

	# 8. 2타: 덩이가 벽에서 빠져나와 통로로 구른다. 멎을 때까지 찍는다 — 장수는 정하지 않는다.
	#    곡괭이가 닿은 뒤 S 로 뒷걸음친다 — 자석(1.8m)이 광석을 채가기 전에 물러나야 바닥에 구르는 것을 본다.
	await _grab()
	_inject_button(MOUSE_BUTTON_LEFT, true)
	await _wait(4)
	_inject_button(MOUSE_BUTTON_LEFT, false)
	await _wait(POP_BACK_AFTER - 4)
	_inject_key(KEY_S, true)
	var ore: Ore = null
	var rest_frames := 0
	for i in POP_SETTLE_FRAMES:
		await _wait(1)
		if i == POP_BACK_FRAMES:
			_inject_key(KEY_S, false)
		if i % POP_SHOT_GAP == 0:
			await _grab()
		if ore == null:
			ore = _first_ore(room)
			continue
		if not is_instance_valid(ore):
			break                    # 자석이 채갔다 — 아래 검사가 잡는다
		rest_frames = rest_frames + 1 if ore.linear_velocity.length() < POP_STILL_SPEED else 0
		if rest_frames >= POP_STILL_FRAMES and i > POP_BACK_FRAMES:
			break
	_inject_key(KEY_S, false)
	_flush_burst("06_pocket_pop")
	_check(_count_pockets(room) == pockets_before - 1, "2타에 포켓이 빠짐 (남은 %d개)" % _count_pockets(room))
	_check(_count_ore(room) == 1, "광석 1개 나옴 (실제 %d)" % _count_ore(room))
	_check(ore != null and rest_frames >= POP_STILL_FRAMES,
		"광석이 %d프레임 안에 바닥에 멎음" % POP_SETTLE_FRAMES)
	if ore != null:
		# 벽에 붙어 구르면 POCKET_POP_OUT 이 약한 것
		var came_out: float = (ore.global_position - pocket_at).dot(out)
		_check(came_out >= POP_MIN_OUT,
			"광석이 벽에서 통로 쪽으로 %.2f m 나옴 (최소 %.1f)" % [came_out, POP_MIN_OUT])
	# 채굴은 소음만 낸다 (#24). 두 타 동안 위험이 안 움직여야 한다.
	_check(is_equal_approx(player.danger, danger_before),
		"2타 동안 위험 변화 0 (%.1f -> %.1f)" % [danger_before, player.danger])
	var danger_mined: float = player.danger

	# 8-1. 광석 근접 한 장 — 자석 반경 바로 밖(2.0m)에서 내려다본다. 안에 서면 빨려와서 못 본다.
	var ore_pos: Vector3 = ore.global_position if ore != null else pocket_at
	player.global_position = ore_pos + Vector3(0.0, 0.2, ORE_LOOK_DIST)
	player.velocity = Vector3.ZERO
	await _wait(10)
	await _aim_at(player, head, ore_pos)
	await _wait(20)
	await _shot("07_ore")

	# 9-1. 자석 밖에서는 안 줍힌다.
	player.global_position = ore_pos + Vector3(0.0, 0.2, ORE_FAR)
	await _wait(30)
	_check(player.ore_count == 0 and _count_ore(room) == 1,
		"자석 밖 %.1fm 에서는 안 줍힘 (%d개)" % [ORE_FAR, player.ore_count])

	# 9-2. 다가가면 줍힌다.
	player.global_position = ore_pos + Vector3(0.0, 0.2, 0.6)
	await _wait(60)
	_check(player.ore_count == 1, "다가가서 광석 1개 주움 (실제 %d)" % player.ore_count)
	_check(_count_ore(room) == 0, "주운 광석은 사라짐 (남은 %d개)" % _count_ore(room))

	# 9-3. 줍기는 위험을 안 올린다.
	_check(is_equal_approx(player.danger, danger_mined),
		"줍기는 위험을 안 올림 (%.1f)" % player.danger)

	# 10-0. 갱도에서 정거장 입구를 멀리서 본다 (#22 수정: 게이트 봉·배관이 벽에 붙어 있는지 — 사용자 09-08 "안전바가 벽에서 떨어져 있다").
	player.global_position = Vector3(0.0, 0.15, -6.0)
	player.rotation.y = PI
	head.rotation.x = deg_to_rad(-4.0)
	await _wait(60)
	await _shot("25_station_far")

	# 10-1. 리프트 (#20 에서 부활). 먼저 갱도에서 정거장을 본다 — 안에서 찍으면 무엇인지 안 보인다.
	player.global_position = LIFT_CENTER + Vector3(0.0, 0.15, -4.2)
	player.rotation.y = PI
	head.rotation.x = deg_to_rad(-8.0)
	await _wait(60)
	await _shot("11_lift_far")

	# 상판은 바닥과 높이가 같아 턱 없이 올라선다.
	player.global_position = LIFT_CENTER + Vector3(0.0, 1.2, 0.0)
	player.velocity = Vector3.ZERO
	await _wait(120)
	_check(player.is_on_floor() and absf(player.global_position.y - FLOOR_Y) < 0.15,
		"리프트 위에 섬 (y=%.3f, 기대 %.2f)" % [player.global_position.y, FLOOR_Y])
	await _shot("12_lift")

	# 케이지 안에서 점프하면 지붕에 막힌다 (#21 수정). 없으면 머리가 보닛을 뚫고 나간다.
	var jump_base: float = player.global_position.y
	var jump_top: float = jump_base
	_inject_key(KEY_SPACE, true)
	await _wait(4)
	_inject_key(KEY_SPACE, false)
	for i in 50:
		await _wait(1)
		jump_top = maxf(jump_top, player.global_position.y)
	_check(jump_top - jump_base < ROOF_MAX_RISE,
		"케이지 안 점프가 지붕을 안 넘음 (올라간 높이 %.2f m, 한계 %.2f)" % [jump_top - jump_base, ROOF_MAX_RISE])
	await _wait(30)

	# 케이지 네 자리 (#22). 상판 네 귀퉁이에 서면 바닥이고 난간 안 — 2.4 상판이면 귀퉁이가 밖이라 떨어진다.
	for corner in [Vector3(-CAGE_CORNER, 0.0, -CAGE_CORNER), Vector3(CAGE_CORNER, 0.0, -CAGE_CORNER),
			Vector3(-CAGE_CORNER, 0.0, CAGE_CORNER), Vector3(CAGE_CORNER, 0.0, CAGE_CORNER)]:
		player.global_position = LIFT_CENTER + corner + Vector3(0.0, 0.3, 0.0)
		player.velocity = Vector3.ZERO
		await _wait(40)
		var rel: Vector3 = player.global_position - LIFT_CENTER
		_check(player.is_on_floor() and absf(rel.y) < 0.15 and absf(rel.x) < 2.2 and absf(rel.z) < 2.2,
			"케이지 귀퉁이 (%+.1f, %+.1f) 에 섬 (y=%.2f)" % [corner.x, corner.z, rel.y])
	var cage_dummies := _spawn_dummies(room, [LIFT_CENTER + Vector3(1.4, 0.0, -1.4), LIFT_CENTER + Vector3(-1.4, 0.0, 1.4), LIFT_CENTER + Vector3(1.4, 0.0, 1.4)])
	player.global_position = LIFT_CENTER + Vector3(-1.7, 0.2, -1.7)
	player.rotation.y = -3.0 * PI / 4.0   # (+X, +Z) 대각선 — 케이지 안쪽을 본다
	head.rotation.x = deg_to_rad(-6.0)
	await _wait(30)
	await _shot("24_cage_corner")
	for d in cage_dummies:
		d.queue_free()
	await _wait(2)
	player.global_position = LIFT_CENTER + Vector3(0.0, 0.2, 0.0)
	player.velocity = Vector3.ZERO

	# 난간 쪽(+Z, 사다리 칸 칸막이 방향)으로 걸어도 못 나간다. 시점을 돌려 W 로 민다 — 코드로 옮기지 않는다.
	player.rotation.y = PI
	head.rotation.x = 0.0
	await _wait(20)
	_inject_key(KEY_W, true)
	await _wait(LIFT_RAIL_FRAMES)
	_inject_key(KEY_W, false)
	_check(player.global_position.z < LIFT_RAIL_Z,
		"난간에 막힘 (z=%.2f, 한계 %.2f)" % [player.global_position.z, LIFT_RAIL_Z])
	await _shot("13_lift_rail")

	# 10-2. 리프트가 내려가고, 사람이 실려 간다.
	var lift3 := room.get_node_or_null("Lift") as AnimatableBody3D
	if lift3 == null:
		_check(false, "리프트 노드 존재")
		return _finish("PLAY")

	# 리프트 밖에서 누르면 안 먹는다. 먼저 이것부터 — 먹으면 아래 검사가 무의미해진다
	player.global_position = LIFT_CENTER + Vector3(0.0, 0.15, -4.2)
	await _wait(30)
	var y_before: float = lift3.global_position.y
	_inject_key(KEY_E, true)
	await _wait(4)
	_inject_key(KEY_E, false)
	await _wait(60)
	_check(is_equal_approx(lift3.global_position.y, y_before),
		"리프트 밖에서 누른 E 는 안 먹음 (y=%.2f)" % lift3.global_position.y)

	# 올라타서 누르면 내려간다. 그동안 사람과 상판의 높이 차를 지켜본다.
	# 내려가는 동안은 트인 쪽(-Z, 갱도)을 조금 내려다본다. 위를 보면 리프트 지붕뿐이다.
	player.global_position = LIFT_CENTER + Vector3(0.0, 1.0, 0.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	head.rotation.x = deg_to_rad(-18.0)
	await _wait(90)
	var top_y: float = lift3.global_position.y
	var ride_gap := 0.0
	# 10-2a. 문 (#21). E 를 누르면 문이 먼저 닫히고, 다 닫힌 뒤에야 내려간다.
	var gate_l := lift3.get_node("Mesh/CAGE_GateL") as Node3D   # 상태값이 아니라 실제 문짝 각도를 본다
	_check(is_equal_approx(lift3.gate_open_ratio(), 1.0) and absf(rad_to_deg(gate_l.rotation.y) - 90.0) < 1.0,
		"E 전 문 열림 (%.2f, 문짝 %.0f°)" % [lift3.gate_open_ratio(), rad_to_deg(gate_l.rotation.y)])
	await _grab()                       # 0프레임: E 직전. 문이 열려 있고 위층 정거장이 보이는 상태
	_inject_key(KEY_E, true)
	await _wait(4)
	_inject_key(KEY_E, false)
	var gate_frames := -1
	var moved_while_closing := 0.0
	for i in GATE_MAX_FRAMES:
		await _wait(1)
		moved_while_closing = maxf(moved_while_closing, absf(lift3.global_position.y - top_y))
		if (i + 5) % GATE_SHOT_GAP == 0:
			await _grab()
		if lift3.is_gate_closed():
			gate_frames = i + 5
			break
	var gate_want := int(ceil(Tuning.LIFT_GATE_TIME * 60.0)) + 6
	_check(gate_frames >= 0 and gate_frames <= gate_want,
		"E 뒤 %d프레임에 문 닫힘 (허용 %d)" % [gate_frames, gate_want])
	_check(moved_while_closing < 0.001,
		"문이 닫히는 동안 리프트는 안 움직임 (%.3f m)" % moved_while_closing)
	_check(absf(rad_to_deg(gate_l.rotation.y)) < 1.0, "문짝이 실제로 닫힘 (%.0f°)" % rad_to_deg(gate_l.rotation.y))
	_check(not (lift3.get_node("Gate") as CollisionShape3D).disabled, "닫힌 문에 충돌체 켜짐")
	await _grab()                       # 닫힌 문
	_flush_burst("22_lift_gate")        # 열림 → 닫힘. 장수는 닫힐 때까지
	await _grab()                       # 14_lift_down 0프레임: 문이 닫혀 출발 직전
	var danger_mid := -1.0
	var gate_push_z := INF
	for i in LIFT_DROP_FRAMES:
		await _wait(1)
		var gap: float = absf(player.global_position.y - lift3.global_position.y)
		ride_gap = maxf(ride_gap, gap)
		if (i + 5) % LIFT_SHOT_GAP == 0:    # 출발 기준 프레임 = 이번 1 + i (+ 여유 4)
			await _grab()
		# 하강 중 문 쪽(-Z)으로 민다 — 문 충돌체가 없으면 상판에서 걸어 나가 샤프트로 떨어진다
		if i == 60:
			_inject_key(KEY_W, true)
		if i == 60 + GATE_PUSH_FRAMES:
			_inject_key(KEY_W, false)
			gate_push_z = player.global_position.z
		if danger_mid < 0.0 and lift3.global_position.y < top_y - DROP_MID_Y:
			danger_mid = player.danger
		if not lift3.is_moving() and lift3.global_position.y < top_y - 1.0:
			break
	var dropped: float = top_y - lift3.global_position.y
	_check(dropped >= LIFT_MIN_DROP,
		"E 한 번에 %.2f m 내려감 (최소 %.1f)" % [dropped, LIFT_MIN_DROP])
	_check(ride_gap <= LIFT_RIDE_GAP,
		"내려가는 동안 사람이 상판에 실려 있음 (최대 틈 %.3f m, 허용 %.2f)"
			% [ride_gap, LIFT_RIDE_GAP])
	_check(gate_push_z > LIFT_GATE_Z,
		"하강 중 문에 막힘 (z=%.2f, 한계 %.2f)" % [gate_push_z, LIFT_GATE_Z])
	_flush_burst("14_lift_down")        # 멎은 뒤에 저장. 하강 중엔 게임을 안 멈춘다
	await _wait(int(ceil(Tuning.LIFT_GATE_TIME * 60.0)) + 6)
	_check(is_equal_approx(lift3.gate_open_ratio(), 1.0)
		and (lift3.get_node("Gate") as CollisionShape3D).disabled, "도착 뒤 문 열림 (%.2f)" % lift3.gate_open_ratio())
	await _shot("20_lift_bottom")

	# 10-3. 아래층으로 걸어 내린다 — 상판과 아래층 바닥이 같은 높이라야 한다.
	head.rotation.x = 0.0
	_inject_key(KEY_W, true)
	await _wait(WALK_FRAMES)
	_inject_key(KEY_W, false)
	await _wait(20)
	_check(player.is_on_floor() and absf(player.global_position.y - LOWER_FLOOR_Y) < 0.15
		and player.global_position.z < LIFT_CENTER.z - 1.5,
		"아래층 갱도로 걸어 내려섬 (y=%.3f 기대 %.1f, z=%.2f)" % [player.global_position.y, LOWER_FLOOR_Y, player.global_position.z])
	await _shot("21_lower_drift")

	# 10-4. 위험 게이지. #24: 리프트 하강은 위험을 안 올린다 (DANGER_PER_DROP 0). 중간에도 도착 뒤에도 그대로.
	_check(is_equal_approx(danger_mid, danger_mined),
		"%.0fm 내려간 시점 위험 변화 0 (%.1f)" % [DROP_MID_Y, danger_mid])
	_check(is_equal_approx(player.danger, danger_mined),
		"리프트 하강 뒤 위험 변화 0 (%.2f)" % player.danger)
	# 60fps 규칙(규칙.md A-3)의 참고값. 검사는 아니다 — 창 크기·GPU 에 따라 다르다.
	# 시작 직후(셰이더 컴파일 중)에 재면 3 이 나온다. 아래층 갱도에서 잰다.
	print("ok fps %.0f (아래층 갱도, 삼각형 %d)" % [Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	await _shot("15_danger")
	# 떨림 문턱 바로 아래에서는 안 떨린다. 값은 add_danger 로 직접 넣는다 — #24 로 게임 안에서는 정비(⑧)까지 안 오른다.
	player.add_danger(Tuning.DANGER_TREMOR_FROM - 1.0 - player.danger)
	var head0: Vector3 = head.position
	var still := 0.0
	for i in TREMOR_FRAMES:
		await _wait(1)
		still = maxf(still, (head.position - head0).length())
	_check(still <= TREMOR_MAX_STILL,
		"위험 %.0f 에서는 안 떨림 (Head 이동 %.4f m)" % [player.danger, still])
	# 문턱을 넘기면 떨린다. 20프레임마다 찍는다.
	player.add_danger(11.0)
	var moved := 0.0
	for i in TREMOR_FRAMES:
		await _wait(1)
		moved = maxf(moved, (head.position - head0).length())
		if i % TREMOR_SHOT_GAP == 0:
			await _grab()
	_flush_burst("16_tremor")
	_check(moved >= TREMOR_MIN_OFFSET,
		"위험 %.0f 에서는 떨림 (Head 이동 %.4f m, 최소 %.3f)"
			% [player.danger, moved, TREMOR_MIN_OFFSET])

	# 10b. 조각 카탈로그 캡처 13 (#26). 갱도 밖 빈자리에 조각을 하나씩 세우고 헤드램프로 한 장씩.
	await _catalog_shots(room, player, head)

	# 11. 위험 100 -> 무너진다. 맨 끝이다 — 방이 다시 뜨면 위 참조가 전부 죽는다.
	#     게임 안에서는 정비(⑧)까지 안 오른다 (#24). 값을 넣어 죽인다.
	player.global_position = Vector3(0.0, 0.2, -10.0)
	player.rotation.y = 0.0
	head.rotation.x = 0.0
	await _wait(30)
	var rocks_before := _count_rocks(room)
	var lamp3 := player.get_node_or_null("Head/Headlamp") as SpotLight3D
	var died_seen := [false]
	player.died.connect(func() -> void: died_seen[0] = true)
	await _grab()                       # 0: 죽기 직전
	player.add_danger(500.0)
	_check(is_equal_approx(player.danger, Tuning.DANGER_MAX),
		"위험은 %.0f 를 안 넘음 (%.1f)" % [Tuning.DANGER_MAX, player.danger])
	_check(player.dead and died_seen[0], "100 에 닿는 순간 죽음 (dead, died 시그널)")
	var pos_dead: Vector3 = player.global_position
	_inject_key(KEY_W, true)
	for i in DEATH_FRAMES:
		await _wait(1)
		if (i + 1) % DEATH_SHOT_GAP == 0:
			await _grab()
		if i == 29:
			_check(_count_rocks(room) - rocks_before >= DEATH_MIN_ROCKS,
				"돌 %d개 떨어짐 (최소 %d)" % [_count_rocks(room) - rocks_before, DEATH_MIN_ROCKS])
			_inject_key(KEY_W, false)
			var moved_dead: float = (player.global_position - pos_dead).length()
			_check(moved_dead <= DEATH_MAX_MOVE,
				"죽은 뒤 W 가 안 먹음 (이동 %.3f m, 허용 %.2f)" % [moved_dead, DEATH_MAX_MOVE])
		if i == 59:
			var energy: float = lamp3.light_energy if lamp3 != null else 99.0
			_check(energy <= DEATH_MAX_LAMP,
				"램프가 꺼짐 (에너지 %.2f, 최대 %.1f)" % [energy, DEATH_MAX_LAMP])
		if i == 89:
			var luma := await _screen_luma()
			_check(luma <= DEATH_MAX_LUMA,
				"검은 화면 (밝기 %.4f, 최대 %.3f)" % [luma, DEATH_MAX_LUMA])
	_flush_burst("17_collapse")
	# 방이 다시 뜬다. 옛 방 노드가 사라지고 current_scene 이 새 것으로 바뀐다
	var restarted := false
	for i in DEATH_RESTART_WAIT:
		await _wait(1)
		if not is_instance_valid(room) or get_tree().current_scene != room:
			restarted = true
			break
	_check(restarted, "%.1f초 뒤 방이 다시 뜸" % Tuning.DEATH_RESTART_TIME)
	if restarted:
		await _wait(20)
		var room2 := get_tree().current_scene as Node3D
		var player2 := room2.get_node_or_null("Player") as CharacterBody3D
		_check(player2 != null and not player2.dead and is_zero_approx(player2.danger)
			and player2.ore_count == 0,
			"새 방: 살아 있고 위험 0, 철 0")
		# 시드 고정: 다시 뜬 방의 포켓이 처음과 같은 자리라야 한다 (매번 랜덤이면 봇·골든이 다른 것을 본다)
		var pos2: Array[Vector3] = []
		for p in (room2.get_node("Pockets") as Node3D).pockets():
			pos2.append((p as Node3D).global_position)
		var same := pos2.size() == pocket_pos_first.size()
		for i in mini(pos2.size(), pocket_pos_first.size()):
			same = same and pos2[i].is_equal_approx(pocket_pos_first[i])
		_check(same, "새 방: 포켓 %d개가 같은 자리 (시드 %d, 처음 %d개)" % [pos2.size(), Tuning.MAP_SEED, pocket_pos_first.size()])
		await _shot("18_restart")
		# 괴물에게 잡힘 (#35) — 방이 또 다시 뜨므로 맨 끝 (18 캡처 뒤)
		if _stage("stalker"):
			await _stalker_catch_run(room2)

	_finish("PLAY")


## 곡괭이가 멎을 때까지 기다린다. 최대 SWING_IDLE_FRAMES 프레임.
func _wait_pick_idle(pick: Node3D) -> void:
	if pick == null or not pick.has_method("is_swinging"):
		return
	for i in SWING_IDLE_FRAMES:
		if not pick.is_swinging():
			return
		await _wait(1)
	_check(false, "곡괭이가 %d프레임 안에 안 멎음" % SWING_IDLE_FRAMES)


# ---------------- 밝기 재기 ----------------

## 화면 전체의 평균 밝기. 격자로 점을 뽑아 잰다 (전 픽셀을 읽으면 느리다).
func _screen_luma() -> float:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	for gy in LAMP_GRID:
		for gx in LAMP_GRID:
			var x := int((gx + 0.5) * w / LAMP_GRID)
			var y := int((gy + 0.5) * h / LAMP_GRID)
			var c := img.get_pixel(x, y)
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	return sum / float(LAMP_GRID * LAMP_GRID)


## 화면 가운데 원(반지름 r px) 안 또는 밖의 평균 밝기 (#32 수정). 안 = 먼 복도, 밖 = 가까운 벽·바닥
func _screen_luma_disk(r: float, inside: bool) -> float:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return 0.0
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for gy in LAMP_GRID:
		for gx in LAMP_GRID:
			var x := int((gx + 0.5) * w / LAMP_GRID)
			var y := int((gy + 0.5) * h / LAMP_GRID)
			if (Vector2(x - w * 0.5, y - h * 0.5).length() <= r) != inside:
				continue
			var c := img.get_pixel(x, y)
			sum += c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			n += 1
	return sum / float(maxi(n, 1))


# ---------------- --shot ----------------

func _shot_routine(room: Node3D, path: String) -> void:
	await _wait(30)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("ok shot %s (err %d)" % [path, err])
	get_tree().quit(0 if err == OK else 1)


# ---------------- --film : 촬영 (쇼츠 재료) ----------------
# 검사가 아니다. Godot --write-movie 와 같이 돌려 리프트 장면을 같은 시점·같은 길이로 찍는다.
#   variant  fixed        정상
#            nodeck       상판 충돌체를 끈다 — 구멍으로 빠진다 (커밋 bfa8445 사보타주와 같은 상태)
#            nodeck_floor 상판 충돌체를 끄고, 리프트 밑에 방바닥을 다시 깐다 — #9 시절 상태.
#                         리프트만 내려가고 사람은 그 자리에 남는다.
const FILM_STAND := 180       # 서 있는 프레임 (3초)
const FILM_FALL := 10         # E 직후 바로 아래를 본다
const FILM_TILT := 40        # 리프트를 따라 시선을 내리는 프레임 (하강 5.7초에 맞춤)
const FILM_HOLD := 420        # 내려다본 채 (7초) — 리프트가 멎고(E+5.7초) 2초 더
const FILM_YAW := 180.0       # 남쪽 난간을 보고 선다
const FILM_OFF_X := 0.6       # 케이블(중앙)에서 동쪽으로 비켜 선다 — 내려다볼 때 케이블이 선으로 보인다
# 사람은 제자리에서 안 움직인다 (사용자 판정 09-07: 물러나면 "내가 내렸다"로 읽힌다).
# 대신 시선이 두 단계 — 정면으로 케이지가 가라앉는 걸 보고, 그 뒤에 아래를 본다.
const FILM_PITCH0 := -35.0    # 널판이 화면 아래를 채우는 각
const FILM_PITCH_RIDE := -18.0  # 정상 하강은 봇과 같은 각 — 트인 북쪽, 불빛이 사라지는 게 보인다
const FILM_PITCH1 := -88.0    # 리프트가 멀어진 뒤 내려다보는 각

# walk_room / walk_tunnel — 4편 0~2초 하드컷용. 씬 기본 위치에서 정면(-Z)을 보고 W 로 곧장 걷는다.
# 두 방의 걸음 속도·시선각이 같아야 컷이 붙는다 (Tuning.WALK_SPEED, 아래 각).
const FILM_WALK_STAND := 60      # 서 있는 프레임 (1초) — in-point 여유
const FILM_WALK_FRAMES := 240    # W 를 누르는 프레임 (4초). 방은 벽(z=-5.5)에서 멈춘다
const FILM_WALK_TAIL := 30
const FILM_WALK_PITCH := -5.0    # 살짝 아래 — 램프 원 안에 바닥·벽·갱목이 같이 든다

func _film_walk(room: Node3D, variant: String) -> void:
	var player := room.get_node("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	head.rotation.x = deg_to_rad(FILM_WALK_PITCH)
	var start := player.global_position
	await _wait(FILM_WALK_STAND)
	_inject_key(KEY_W, true)
	await _wait(FILM_WALK_FRAMES)
	_inject_key(KEY_W, false)
	await _wait(FILM_WALK_TAIL)
	print("ok film %s: from %s to %s (%.2f m)" % [variant, start, player.global_position, start.distance_to(player.global_position)])
	get_tree().quit(0)


func _film_routine(room: Node3D, variant: String) -> void:
	var player := room.get_node("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	var lift := room.get_node("Lift") as AnimatableBody3D
	if "nodeck" in variant:
		(lift.get_node("Deck") as CollisionShape3D).disabled = true
	if "floor" in variant:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.2, 0.2, 3.2)
		cs.shape = box
		body.add_child(cs)
		room.add_child(body)
		body.global_position = LIFT_CENTER + Vector3(0.0, -0.1, 0.0)   # 윗면 = 방바닥 높이
	player.global_position = LIFT_CENTER + Vector3(0.0 if ("nodeck" not in variant) else FILM_OFF_X, 1.0, 0.0)
	player.velocity = Vector3.ZERO
	var ride := not ("nodeck" in variant)
	player.rotation.y = 0.0 if ride else deg_to_rad(FILM_YAW)
	head.rotation.x = deg_to_rad(FILM_PITCH_RIDE if ride else FILM_PITCH0)
	await _wait(FILM_STAND)
	_inject_key(KEY_E, true)
	await _wait(4)
	_inject_key(KEY_E, false)
	await _wait(FILM_FALL)
	for i in (0 if ride else FILM_TILT):
		head.rotation.x = deg_to_rad(lerpf(FILM_PITCH0, FILM_PITCH1, float(i + 1) / FILM_TILT))
		await _wait(1)
	await _wait(FILM_HOLD)
	print("ok film %s: player %s lift y=%.2f" % [variant, player.global_position, lift.global_position.y])
	get_tree().quit(0)


# ---------------- 조각 카탈로그 (#26) ----------------

## 카탈로그 13 조각을 exe 안에서 잰다: 로드·재질·조명 / 뚫린 면 테두리가 기준 윤곽 위에 있나 / 충돌체·포켓 자리 수 / 삼각형 예산.
func _catalog_checks(room: Node3D) -> void:
	var loaded: Array = []          # [이름, 노드, 표]
	for name in PieceCatalog.PIECES:
		var n := _spawn_piece(room, PieceCatalog.piece_path(name))
		if n != null:
			loaded.append([name, n, PieceCatalog.PIECES[name]])
	for name in PieceCatalog.RAILS:
		var n := _spawn_piece(room, PieceCatalog.rail_path(name))
		if n != null:
			loaded.append(["rail_" + name, n, PieceCatalog.RAILS[name]])
	_check(loaded.size() == CATALOG_COUNT, "카탈로그 조각 %d개 로드 (갱도 9 + 레일 4, 실제 %d)" % [CATALOG_COUNT, loaded.size()])
	var bad_mat := ""
	var bad_light := ""
	var bad_tri := ""
	var bad_col := ""
	var bad_slot := ""
	for e in loaded:
		var name: String = e[0]
		var n: Node3D = e[1]
		var table: Dictionary = e[2]
		if not _all_materials_prefixed(n, "MAT_"):
			bad_mat += name + " "
		if _count_lights(n) > 0:
			bad_light += name + " "
		var tris := _tri_count(n)
		if tris > PieceCatalog.TRI_MAX:
			bad_tri += "%s(%d) " % [name, tris]
		var cols := _count_of(n, "StaticBody3D")
		if cols != int(table["cols"]):
			bad_col += "%s(%d≠%d) " % [name, cols, table["cols"]]
		if table.has("slots"):
			var slots := _count_prefix(n, "SLOT_Pocket_")
			if slots != int(table["slots"]):
				bad_slot += "%s(%d≠%d) " % [name, slots, table["slots"]]
	_check(bad_mat.is_empty(), "조각 재질 전부 MAT_ (팔레트·기본 재질 없음)%s" % (" — " + bad_mat if bad_mat else ""))
	_check(bad_light.is_empty(), "조각 안 Light3D 0%s" % (" — " + bad_light if bad_light else ""))
	_check(bad_tri.is_empty(), "조각당 삼각형 ≤ %d%s" % [PieceCatalog.TRI_MAX, " — " + bad_tri if bad_tri else ""])
	_check(bad_col.is_empty(), "충돌체(StaticBody3D, -convcolonly) 수 = 카탈로그 표%s" % (" — " + bad_col if bad_col else ""))
	_check(bad_slot.is_empty(), "포켓 자리(SLOT_Pocket_*) 수 = 카탈로그 표%s" % (" — " + bad_slot if bad_slot else ""))
	# 면 맞음. 기준 윤곽: A = 직선의 S 면, D = 목의 N 면. 조각의 뚫린 면 테두리 정점이 전부 기준 윤곽(선분) 위에 있어야 한다.
	var by_name := {}
	for e in loaded:
		by_name[e[0]] = e[1]
	var ref := {}
	ref["A"] = _face_outline(by_name["straight"], "straight", "S")
	ref["D"] = _face_outline(by_name["neck"], "neck", "N")
	_check(ref["A"].size() >= CATALOG_MIN_OUTLINE and ref["D"].size() >= CATALOG_MIN_OUTLINE,
		"기준 윤곽 정점 A %d · D %d (최소 %d)" % [ref["A"].size(), ref["D"].size(), CATALOG_MIN_OUTLINE])
	var bad_face := ""
	var faces_checked := 0
	for name in PieceCatalog.PIECES:
		if not by_name.has(name):
			continue
		var faces: Dictionary = PieceCatalog.PIECES[name]["faces"]
		for f in faces:
			var kind: String = faces[f]
			if kind == PieceCatalog.CLOSED:
				continue
			var outline := _face_outline(by_name[name], name, f)
			var worst := _outline_deviation(outline, ref[kind])
			faces_checked += 1
			if outline.size() < CATALOG_MIN_OUTLINE or worst > PieceCatalog.FACE_TOL:
				bad_face += "%s.%s(%d점, %.1fmm) " % [name, f, outline.size(), worst * 1000.0]
	_check(bad_face.is_empty() and faces_checked == CATALOG_FACES,
		"뚫린 면 %d개의 테두리가 기준 윤곽 위 (오차 ≤ %.0f mm)%s" % [faces_checked, PieceCatalog.FACE_TOL * 1000.0, " — " + bad_face if bad_face else ""])
	for e in loaded:
		(e[1] as Node).queue_free()
	await _wait(2)


func _spawn_piece(room: Node3D, path: String, at: Vector3 = Vector3(0.0, CATALOG_Y, 0.0), yaw_deg: float = 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var n := packed.instantiate() as Node3D
	room.add_child(n)
	n.global_position = at
	n.rotation.y = deg_to_rad(yaw_deg)
	return n


## 조각의 한 면(평면) 위에 놓인 메시 테두리(한 삼각형만 쓰는 변)의 정점들. (u, y) — u 는 면을 따라, 문이면 door_x 를 뺀다.
## 바위 껍질(SHL_*)만 본다 — 갱목·레일은 면에 걸쳐 있지 않다.
func _face_outline(piece: Node3D, name: String, face: String) -> PackedVector2Array:
	var plane: Array = PieceCatalog.face_plane(name, face)
	var cx: float = PieceCatalog.PIECES[name].get("door_x", 0.0) if PieceCatalog.PIECES[name]["faces"][face] == PieceCatalog.OPEN_D else 0.0
	return _outline_on(piece, "SHL_", plane[0], plane[1], cx)


## 노드 로컬 평면(axis = value) 위에 놓인 메시(prefix) 테두리 정점들. 정거장(ENV_, z 0)도 이걸로 잰다 (#27).
func _outline_on(piece: Node3D, prefix: String, axis: int, value: float, cx: float) -> PackedVector2Array:
	var inv: Transform3D = piece.global_transform.affine_inverse()
	var edges := {}        # "a|b" -> 횟수 (a, b = 0.5 mm 로 반올림한 정점 키)
	var pos := {}          # 키 -> Vector3
	var shells: Array = []
	_collect_prefix(piece, prefix, shells)
	for mi in shells:
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		var xf: Transform3D = inv * (mi as MeshInstance3D).global_transform
		for si in m.get_surface_count():
			var arrays: Array = m.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var keys: PackedInt64Array = PackedInt64Array()
			keys.resize(verts.size())
			for i in verts.size():
				var p: Vector3 = xf * verts[i]
				var k := _vkey(p)
				keys[i] = k
				pos[k] = p
			var count: int = idx.size() if idx.size() > 0 else verts.size()
			for t in range(0, count, 3):
				for j in 3:
					var a: int = keys[idx[t + j]] if idx.size() > 0 else keys[t + j]
					var b: int = keys[idx[t + (j + 1) % 3]] if idx.size() > 0 else keys[t + (j + 1) % 3]
					if a == b:
						continue
					var ek: String = "%d|%d" % [mini(a, b), maxi(a, b)]
					edges[ek] = edges.get(ek, 0) + 1
	var out := PackedVector2Array()
	var seen := {}
	for ek in edges:
		if edges[ek] != 1:
			continue
		var ab: PackedStringArray = ek.split("|")
		var pa: Vector3 = pos[int(ab[0])]
		var pb: Vector3 = pos[int(ab[1])]
		if absf(pa[axis] - value) > 0.001 or absf(pb[axis] - value) > 0.001:
			continue
		for p in [pa, pb]:
			var k := _vkey(p)
			if seen.has(k):
				continue
			seen[k] = true
			var u: float = (p.x if axis == 2 else p.z) - cx
			out.append(Vector2(absf(u), p.y))     # 윤곽은 좌우 대칭 — 면의 방향과 무관하게 잰다
	return out


func _vkey(p: Vector3) -> int:
	return int(roundf(p.x * 2000.0)) * 4000000 + int(roundf(p.y * 2000.0)) * 2000 + int(roundf(p.z * 2000.0)) + 2000000000


## 윤곽 정점들이 기준 윤곽(정점을 이은 폴리라인 — 바닥 줄·벽 기둥·아치 줄)에서 얼마나 떨어져 있나. 가장 먼 값.
func _outline_deviation(outline: PackedVector2Array, refp: PackedVector2Array) -> float:
	var segs := _outline_segments(refp)
	var worst := 0.0
	for p in outline:
		var best := 1e9
		for s in segs:
			best = minf(best, _dist_to_segment(p, s[0], s[1]))
		worst = maxf(worst, best)
	return worst


## 기준 정점 집합 → 선분. 같은 u 에 정점이 4개 이상 세로로 있으면 벽 기둥, y≈0 은 바닥 줄, 나머지는 아치 줄.
func _outline_segments(pts: PackedVector2Array) -> Array:
	var floor_row: Array = []
	var arch_row: Array = []
	var walls := {}     # u -> [Vector2...]
	for p in pts:
		if p.y < 0.02:
			floor_row.append(p)
		elif _is_wall_u(p.x, pts):
			if not walls.has(p.x):
				walls[p.x] = []
			walls[p.x].append(p)
		else:
			arch_row.append(p)
	for u in walls:
		var col: Array = walls[u]
		col.sort_custom(func(a, b): return a.y < b.y)
		arch_row.append(col[col.size() - 1])      # 기둥 꼭대기는 아치 줄의 끝점이기도 하다
	var segs: Array = []
	floor_row.sort_custom(func(a, b): return a.x < b.x)
	arch_row.sort_custom(func(a, b): return a.x < b.x)
	for row in [floor_row, arch_row]:
		for i in row.size() - 1:
			segs.append([row[i], row[i + 1]])
	for u in walls:
		var col: Array = walls[u]
		for i in col.size() - 1:
			segs.append([col[i], col[i + 1]])
		segs.append([Vector2(u, 0.0), col[0]])
	return segs


## 그 u 에 정점이 4개 이상 세로로 있으면 벽 기둥이다 (아치·바닥 줄은 u 하나에 1~2개).
func _is_wall_u(u: float, pts: PackedVector2Array) -> bool:
	var n := 0
	for p in pts:
		if absf(p.x - u) < 0.0005:
			n += 1
	return n >= 4


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return (p - a).length()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return (p - (a + ab * t)).length()


func _collect_prefix(n: Node, prefix: String, out: Array) -> void:
	if n is MeshInstance3D and n.name.begins_with(prefix):
		out.append(n)
	for c in n.get_children():
		_collect_prefix(c, prefix, out)


func _count_prefix(n: Node, prefix: String) -> int:
	var k := 1 if n.name.begins_with(prefix) else 0
	for c in n.get_children():
		k += _count_prefix(c, prefix)
	return k


func _count_of(n: Node, cls: String) -> int:
	var k := 1 if n.get_class() == cls else 0
	for c in n.get_children():
		k += _count_of(c, cls)
	return k


func _tri_count(n: Node) -> int:
	var k := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var arrays: Array = m.surface_get_arrays(si)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			k += (idx.size() if idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	for c in n.get_children():
		k += _tri_count(c)
	return k


func _all_materials_prefixed(n: Node, prefix: String) -> bool:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var mat := m.surface_get_material(si)
			if mat == null or not mat.resource_name.begins_with(prefix):
				return false
	for c in n.get_children():
		if not _all_materials_prefixed(c, prefix):
			return false
	return true


## --play: 조각 13 을 하나씩 세우고 남쪽 입구 눈높이에서 헤드램프로 한 장. 바닥 충돌체에 내려서는 것도 같이 본다.
func _catalog_shots(room: Node3D, player: CharacterBody3D, head: Node3D) -> void:
	var order: Array = []
	for name in PieceCatalog.PIECES:
		order.append([name, [PieceCatalog.piece_path(name), 0.0], ""])
	for name in PieceCatalog.RAILS:
		var r: Dictionary = PieceCatalog.RAILS[name]
		order.append(["rail_" + name, [PieceCatalog.piece_path(r["body"]), r.get("body_rot", 0.0)], PieceCatalog.rail_path(name)])
	var at := Vector3(0.0, CATALOG_Y, 0.0)
	var on_floor_all := true
	var k := 40
	for e in order:
		var name: String = e[0]
		var body := _spawn_piece(room, e[1][0], at, e[1][1])
		var rail: Node3D = _spawn_piece(room, e[2], at) if e[2] != "" else null
		# 서는 자리: 남쪽 입구 안쪽 눈높이에서 -Z 를 본다. 방 2×2 는 문(x -3.5, z 7) 안쪽, 대피소는 서쪽에서 벽감(+X)을 본다
		var stand := Vector3(0.0, 0.2, 2.8)
		var yaw := 0.0
		if name == "room_2":
			stand = Vector3(-3.5, 0.2, 5.5)
		elif name in ["curve", "rail_curve"]:
			stand = Vector3(1.5, 0.2, 2.8)      # 남쪽 입구 오른쪽에서 서쪽 출구 쪽(북서)을 본다 — 휜 벽과 레일 호
			yaw = 40.0
		elif name == "rail_turnout":
			stand = Vector3(1.0, 0.2, 3.3)      # 분기 곡선(남→서)이 왼쪽으로 갈라지는 것이 보이게
			yaw = 30.0
		elif name == "refuge":
			stand = Vector3(-1.2, 0.2, 2.0)
			yaw = -90.0
		player.global_position = at + stand
		player.rotation.y = deg_to_rad(yaw)
		head.rotation.x = 0.0
		player.velocity = Vector3.ZERO
		await _wait(CATALOG_SETTLE)
		if not player.is_on_floor() or absf(player.global_position.y - (at.y + FLOOR_Y)) > 0.15:
			on_floor_all = false
			print("FAIL 카탈로그 %s: 바닥에 못 섬 (y %.2f)" % [name, player.global_position.y - at.y])
		await _shot("%d_cat_%s" % [k, name])
		k += 1
		body.queue_free()
		if rail != null:
			rail.queue_free()
		await _wait(2)
	_check(on_floor_all, "카탈로그 조각 %d개 모두 바닥 충돌체 위에 섬 (-convcolonly)" % order.size())


# ---------------- 질감 (#17 → #19) ----------------

## 사람 크기 캡슐 더미 (지름 0.8 × 키 1.8). 캡처용 — 충돌 없음, 찍은 뒤 queue_free (#22).
func _spawn_dummies(room: Node3D, feet: Array) -> Array:
	var out := []
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.6)
	for p in feet:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		mi.mesh = cm
		mi.material_override = mat
		room.add_child(mi)
		mi.global_position = p + Vector3(0.0, 0.9, 0.0)
		out.append(mi)
	return out


## 노드 밑에 KayKit 팔레트(dungeon_texture)를 쓰는 메시가 하나라도 있나 (#21 케이지 검사).
func _any_palette(n: Node) -> bool:
	if n is MeshInstance3D and Atmosphere.uses_palette(n):
		return true
	for c in n.get_children():
		if _any_palette(c):
			return true
	return false


## 노드 밑에서 이름이 prefix 로 시작하는 재질을 쓰는 첫 MeshInstance3D (깊이 우선).
## glTF 재질은 Blender 이름(MAT_RockWall_EXPORT 등)을 resource_name 으로 달고 들어온다.
func _mesh_with_material(n: Node, prefix: String) -> MeshInstance3D:
	if n == null:
		return null
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat != null and mat.resource_name.begins_with(prefix):
					return mi
	for c in n.get_children():
		var m := _mesh_with_material(c, prefix)
		if m != null:
			return m
	return null


## 그 메시에서 prefix 재질의 젖은 물막. 젖은 바위 셰이더(#20 판정 뒤)면 wet_clearcoat 파라미터,
## StandardMaterial3D 면 clearcoat. 꺼져 있거나 셰이더가 안 붙었으면 -1.
func _material_clearcoat(mi: MeshInstance3D, prefix: String) -> float:
	if mi == null or mi.mesh == null:
		return -1.0
	for i in mi.mesh.get_surface_count():
		var any := mi.mesh.surface_get_material(i)
		if any == null or not any.resource_name.begins_with(prefix):
			continue
		if any is ShaderMaterial:
			var sm := any as ShaderMaterial
			if sm.shader != null and sm.shader.resource_path.ends_with("wet_rock.gdshader"):
				return float(sm.get_shader_parameter("wet_clearcoat"))
			return -1.0
		var mat := any as StandardMaterial3D
		if mat != null:
			return mat.clearcoat if mat.clearcoat_enabled else -1.0
	return -1.0


## 그 메시에서 prefix 재질의 albedo_color. 없으면 검정.
func _material_albedo(mi: MeshInstance3D, prefix: String) -> Color:
	if mi == null or mi.mesh == null:
		return Color.BLACK
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if mat != null and mat.resource_name.begins_with(prefix):
			return mat.albedo_color
	return Color.BLACK


func _count_lights(n: Node) -> int:
	var k := 1 if n is Light3D else 0
	for c in n.get_children():
		k += _count_lights(c)
	return k


# ---------------- 조준 ----------------

## 마우스 주입으로 카메라가 target 을 보게 돌린다. 코드로 회전을 쓰지 않는다 — 시점 경로를 지난다.
## AIM_STEPS 안에 AIM_TOL 로 들어오면 true.
func _aim_at(player: CharacterBody3D, head: Node3D, target: Vector3) -> bool:
	var cam := head.get_node("Camera3D") as Node3D
	for i in AIM_STEPS:
		var d: Vector3 = target - cam.global_position
		var want_yaw := atan2(-d.x, -d.z)
		var want_pitch := atan2(d.y, Vector2(d.x, d.z).length())
		var dyaw := wrapf(want_yaw - player.rotation.y, -PI, PI)
		var dpitch := want_pitch - head.rotation.x
		if absf(dyaw) < AIM_TOL and absf(dpitch) < AIM_TOL:
			return true
		# Player: rotate_y(-rel.x * SENS), pitch -= rel.y * SENS
		var rel := Vector2(-dyaw / Tuning.MOUSE_SENSITIVITY, -dpitch / Tuning.MOUSE_SENSITIVITY)
		rel.x = clampf(rel.x, -AIM_PUSH, AIM_PUSH)
		rel.y = clampf(rel.y, -AIM_PUSH, AIM_PUSH)
		_inject_motion(rel)
		await _wait(1)
	return false


# ---------------- 세기 ----------------
# 자갈·광석은 포켓과 같은 부모(Pockets) 밑에 들어간다. 자식 수만 세면 섞이므로
# 타입으로 가른다.

func _count_pockets(room: Node3D) -> int:
	var n := 0
	for c in room.get_node("Pockets").get_children():
		if c is OrePocket:
			n += 1
	return n


func _count_chunks(room: Node3D) -> int:
	var n := 0
	for c in room.get_node("Pockets").get_children():
		if c is WallChunk:
			n += 1
	return n


## 붕괴 때 떨어지는 돌. 플레이어의 부모(방 루트) 밑에 붙는다 — Pockets 가 아니다.
func _count_rocks(room: Node3D) -> int:
	var n := 0
	for c in room.get_children():
		if c is WallChunk:
			n += 1
	return n


func _first_ore(room: Node3D) -> Ore:
	for c in room.get_node("Pockets").get_children():
		if c is Ore:
			return c as Ore
	return null


func _count_ore(room: Node3D) -> int:
	var n := 0
	for c in room.get_node("Pockets").get_children():
		if c is Ore:
			n += 1
	return n


# ---------------- 입력 주입 ----------------

func _inject_motion(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = Vector2(get_viewport().get_visible_rect().size) * 0.5
	Input.parse_input_event(ev)


func _inject_button(button: MouseButton, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = Vector2(get_viewport().get_visible_rect().size) * 0.5
	Input.parse_input_event(ev)


func _inject_key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


# ---------------- 공통 ----------------

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(_out_dir + "/play_" + name + ".png")


## 연속 캡처 한 장. 메모리에만 담는다 — 파일은 _flush_burst 가 쓴다.
func _grab() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		_burst.append(img)


## 담아 둔 캡처를 play_<name>_0.png ~ 로 저장한다. qc.py 가 `_숫자` 로 한 동작으로 묶는다.
func _flush_burst(name: String) -> void:
	for i in _burst.size():
		_burst[i].save_png("%s/play_%s_%d.png" % [_out_dir, name, i])
	print("ok 연속 캡처 %s %d장" % [name, _burst.size()])
	_burst.clear()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("ok " + label)
	else:
		print("FAIL " + label)
		_failed = true


func _finish(tag: String) -> void:
	if _failed:
		print("!! %s 실패" % tag)
		get_tree().quit(1)
	else:
		print("%s PASS" % tag)
		get_tree().quit(0)


# ---------------- 층 조립 (#27) ----------------

func _asm(room: Node3D) -> MineAssembler:
	return room.get_node_or_null("Layers") as MineAssembler


## 조각 이름으로 첫 칸 (조립 순서대로 — 시드가 같으면 같은 칸). rail_name 을 주면 그 레일이 얹힌 칸만. 없으면 (-1, -1).
func _first_cell(fd: MineAssembler.FloorData, name: String, rail_name: String = "") -> Vector2i:
	for c in fd.pieces:
		if fd.pieces[c]["name"] != name:
			continue
		if rail_name != "" and not (fd.rails.has(c) and fd.rails[c].size() > 0 and fd.rails[c][0]["name"] == rail_name):
			continue
		return c
	return Vector2i(-1, -1)


## 발 위치와 보는 방향(면 번호 N E S W)으로 세운다.
## 플레이어 시점을 월드 한 점으로 돌린다 (#49 벽타기 캡처 — 괴물이 벽 위에 있어 정면 고정으로는 화면 밖이다)
func _look_at_point(player: CharacterBody3D, head: Node3D, at: Vector3) -> void:
	var to: Vector3 = at - player.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	head.rotation.x = clampf(atan2(to.y - Tuning.EYE_HEIGHT, Vector2(to.x, to.z).length()), -1.2, 1.2)


func _stand_at(player: CharacterBody3D, head: Node3D, feet: Vector3, look: int) -> void:
	player.global_position = feet + Vector3(0.0, 0.2, 0.0)
	player.rotation.y = YAW_OF[look]
	head.rotation.x = 0.0
	player.velocity = Vector3.ZERO


## #57 천장 낙하 한 번(매달림 → 낙하 → 착지)을 지켜본다. 매달림(없으면 놓는 순간)부터 every 프레임마다 캡처, 최대 shots 장.
## 팔 벌림·팔 방향은 보정 안에서 잰 값(MinerBody.hand_spread/reach_aim)이다 — 밖에서 뼈를 읽으면 보정 전 자세가 나온다(#46)
func _drop_watch(st: Stalker, player: CharacterBody3D, every: int, shots: int, skip: int = 0) -> Dictionary:
	var r := {"hang_at": -1, "fall_at": -1, "land_at": -1, "fall_clip": "", "land_dist": -1.0, "ceil": st.ceiling_y(st.position),
		"lift_min": INF, "head_aim_min": INF, "hip_gap": -INF, "foot_gap": -INF, "head_lo": INF, "head_hi": -INF, "tilt_max": 0.0, "aim_min": INF, "spread_max": 0.0,
		"head_first": false, "tilt_deg": -1.0, "land_low": INF, "land_raw": INF}
	r["spread_fall"] = 0.0
	r["head_pf"] = false
	r["jump_max"] = 0.0
	r["jump_state"] = ""
	r["jump_pf"] = -1
	r["prev_hy"] = INF
	r["prev_clip"] = ""
	r["prev_cpos"] = 0.0
	r["stalls"] = 0
	r["skip"] = 0
	# #58 램프: 매달림부터 다시 켜질 때까지 lamp_on·환경광이 그대로인가 · 예고 깜빡임 · 떨어지는 동안 화면 밝기 · 다시 켜진 시각
	r["lamp_on_all"] = true
	r["amb_ok"] = true
	r["blink_low"] = false
	r["blink_back"] = false
	r["dark_luma"] = -1.0
	r["luma_n"] = 0
	r["dust"] = -1
	r["relight_pf"] = -1
	r["relight_state"] = ""
	r["max_en"] = 0.0
	var lamp := player.get_node_or_null("Head/Headlamp") as SpotLight3D
	# 머리 한 프레임 이동은 물리 프레임마다 잰다 — 화면 프레임 사이에 물리가 두 번 돌면 한 번의 튐이 둘로 나뉘어 절반으로 보였다(같은 코드가 0.74 / 1.28).
	# 캡처(_grab)가 GPU 를 기다리는 동안은 화면 프레임 없이 물리만 돈다 — 애니메이션(화면 프레임에서 돈다)이 멈췄다가 밀린 시간을 한꺼번에
	# 따라잡아 머리가 1.26 m 떨어졌다(디버그: 물리 8프레임 동안 클립 시각 0.00 → 한 프레임에 0.15, 뼈 자세는 그 **다음** 프레임에 바뀐다).
	# 같은 클립인데 시각이 물리 2.5프레임 넘게 건너뛴 프레임과 그 다음 프레임은 비교하지 않는다. 클립이 바뀐 프레임(놓는 순간)은 비교한다 — 잡으려는 버그가 거기서 난다
	var on_pf := func() -> void:
		if st.state == "hang" or st.state == "fall":
			var hy: float = st.body.head_y()
			var clip: String = st.body.current_clip()
			var cpos: float = st.body.clip_position()
			var lump: bool = clip == r.prev_clip and cpos - float(r.prev_cpos) > 2.5 / 60.0 * maxf(st.body.speed(), 0.01)
			if lump:
				r.stalls += 1
				r.skip = 2
			if int(r.skip) > 0:
				r.skip -= 1
			elif r.prev_hy < INF and absf(hy - float(r.prev_hy)) > r.jump_max:
				r.jump_max = absf(hy - float(r.prev_hy))
				r.jump_state = st.state
				r.jump_pf = Engine.get_physics_frames()
			r.prev_hy = hy
			r.prev_clip = clip
			r.prev_cpos = cpos
		else:
			r.prev_hy = INF
			r.prev_clip = ""
	get_tree().physics_frame.connect(on_pf)
	var swing_f: int = ceili(Tuning.STALKER_HANG_SWING_S * 60.0)
	var rise_f: int = ceili(Tuning.STALKER_GLARE_RISE_S * 60.0)
	var grabs := 0
	var next_grab := -1
	for k in 400:                                                            # 시각은 물리 프레임으로 잰다 — 캡처(_grab)가 한 바퀴에 화면 프레임을 더 먹어 k 는 실제보다 적게 센다
		await _wait(1)
		var pf: int = Engine.get_physics_frames()
		var s: String = st.state
		if r.hang_at < 0 and s == "hang":
			r.hang_at = pf
		if r.fall_at < 0 and s == "fall":
			r.fall_at = pf
			r.fall_clip = st.body.current_clip()
		if r.land_at < 0 and s == "land":
			r.land_at = pf
			r.land_dist = Vector2(st.global_position.x - player.global_position.x, st.global_position.z - player.global_position.z).length()
		if s == "hang":
			var gl: SpineGlare = st.body.glare                               # #59 그려진 자세 (보정 안에서 잰 값)
			if pf - int(r.hang_at) >= swing_f:                               # crawl 로 다 섞인 뒤부터 (그 전은 천장 달리기 클립이 섞여 있다)
				r.hip_gap = maxf(r.hip_gap, gl.hip_gap)
				r.foot_gap = maxf(r.foot_gap, gl.foot_gap)
			if pf - int(r.hang_at) >= rise_f:                                # 상체를 다 든 뒤부터
				r.aim_min = minf(r.aim_min, st.body.reach_aim())
				r.spread_max = maxf(r.spread_max, st.body.hand_spread())
				r.lift_min = minf(r.lift_min, gl.lift_deg)
				r.head_aim_min = minf(r.head_aim_min, gl.head_aim)
				r.head_lo = gl.head_pos if r.head_lo is float else (r.head_lo as Vector3).min(gl.head_pos)   # 숨쉬기는 상체가 60° 넘게 들려 머리가 거의 앞뒤로 움직인다 — 높이가 아니라 자리 폭으로 잰다
				r.head_hi = gl.head_pos if r.head_hi is float else (r.head_hi as Vector3).max(gl.head_pos)
			r.tilt_max = maxf(r.tilt_max, gl.tilt_deg)
		if s == "fall":
			r.spread_max = maxf(r.spread_max, st.body.hand_spread())
			r.spread_fall = maxf(r.spread_fall, st.body.hand_spread())
			if not r.head_pf and pf - int(r.fall_at) >= 9:
				r.head_pf = true
				r.head_first = st.body.head_y() < st.body.hip_y()
			r.tilt_deg = rad_to_deg(st.body.global_transform.basis.y.normalized().angle_to(Vector3.UP))   # 마지막 공중 프레임 값이 남는다
		var en: float = lamp.light_energy if lamp != null else -1.0
		if int(r.hang_at) >= 0:
			r.max_en = maxf(r.max_en, en)
			if int(r.relight_pf) < 0:
				r.lamp_on_all = r.lamp_on_all and player.lamp_on
				r.amb_ok = r.amb_ok and is_equal_approx(Atmosphere.ambient(), Tuning.AMBIENT_ENERGY)
		if s == "hang":
			if en <= Tuning.LAMP_ENERGY * 0.05:
				r.blink_low = true
			elif r.blink_low and en >= Tuning.LAMP_ENERGY * 0.9:
				r.blink_back = true
		if s == "fall" and int(r.dust) < 0:
			r.dust = st.fd.root.get_children().filter(func(c: Node) -> bool: return c is Dust).size()
		if int(r.land_at) >= 0 and int(r.relight_pf) < 0 and en >= Tuning.LAMP_ENERGY * 0.9:
			r.relight_pf = pf
			r.relight_state = st.state
		if player.lamp_on and s == "fall" and int(r.luma_n) < 2 and pf - int(r.fall_at) >= 6 + 9 * int(r.luma_n):   # 놓고 0.1초 · 0.25초. 꺼 둔 램프 재생은 안 잰다 — 캡처 없는 재생으로 남겨 둔다(아래 머리 한 프레임 검사)
			r.luma_n += 1
			r.dark_luma = maxf(r.dark_luma, await _screen_luma())
		if s == "land" and pf - int(r.land_at) <= 40:                       # 착지 클립은 한 손이 바닥을 짚는다 — 그려진 손끝과 보정 전 손끝
			r.land_low = minf(r.land_low, st.body.hand_clear_drawn())
			r.land_raw = minf(r.land_raw, st.body.hand_clear_raw())
		var start: int = int(r.hang_at) if int(r.hang_at) >= 0 else int(r.fall_at)
		if start >= 0:
			start += skip
		if start >= 0 and grabs < shots and pf >= maxi(next_grab, start):
			await _grab()
			grabs += 1
			next_grab = maxi(next_grab, start) + every
		if int(r.land_at) >= 0 and pf - int(r.land_at) >= 40:
			break
	get_tree().physics_frame.disconnect(on_pf)
	return r


## 칸의 뚫린 면 f 밖(이웃 칸 쪽) dist 에 서서 조각 안을 본다.
func _stand_before(player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData, c: Vector2i, f: int, dist: float) -> void:
	_stand_at(player, head, MineAssembler.cell_world(c, fd.y) + DIR3[f] * (Tuning.GRID_CELL * 0.5 + dist), (f + 2) % 4)


func _maze_shots(room: Node3D, player: CharacterBody3D, head: Node3D) -> void:
	var asm := _asm(room)
	if asm == null or asm.floors.is_empty():
		_check(false, "Layers (MineAssembler) 가 있음")
		return
	var fd: MineAssembler.FloorData = asm.floors[0]
	# 곡선: 뚫린 면 하나 밖에 서서 안을 보고 W — 벽을 따라 미끄러진다. 끝난 칸이 뚫린 칸이어야 한다 (벽 안으로 안 들어감)
	var curve := _first_cell(fd, "curve")
	if curve.x >= 0:
		_stand_before(player, head, fd, curve, MineAssembler._first_bit(fd.open[curve]), MAZE_STAND)
		await _wait(20)
		var from: Vector3 = player.global_position
		_inject_key(KEY_W, true)
		for k in 5:
			await _grab()
			await _wait(CURVE_WALK_FRAMES / 5)
		_inject_key(KEY_W, false)
		_flush_burst("53_maze_curve")
		var end_cell := MineAssembler.cell_of(player.global_position)
		var walked: float = (player.global_position - from).length()
		_check(walked >= CURVE_WALK_MIN and (fd.open.has(end_cell) or fd.cover.has(end_cell)),
			"곡선 안으로 %.1f m 걸어 뚫린 칸에 있음 (칸 %s, 최소 %.1f)" % [walked, end_cell, CURVE_WALK_MIN])
	var t := _first_cell(fd, "t")
	if t.x >= 0:
		_stand_before(player, head, fd, t, MineAssembler._first_bit(fd.open[t]), MAZE_STAND)
		await _wait(30)
		await _shot("54_maze_t")
	var room2 := _first_cell(fd, "room_2")
	if room2.x >= 0:
		var p: Dictionary = fd.pieces[room2]
		var door_face: int = MineAssembler.world_face("room_2", p["r"], "S")
		_stand_at(player, head, (p["node"] as Node3D).global_position, door_face)
		await _wait(30)
		await _shot("55_room")
	var refuge := _first_cell(fd, "refuge")
	if refuge.x >= 0:
		var p: Dictionary = fd.pieces[refuge]
		var alcove: int = MineAssembler.world_face("refuge", p["r"], "E")
		_stand_at(player, head, MineAssembler.cell_world(refuge, fd.y) - DIR3[alcove] * 1.0, alcove)
		await _wait(30)
		await _shot("56_refuge")
	var term := _first_cell(fd, "cap", "end")
	if term.x >= 0:
		_stand_before(player, head, fd, term, MineAssembler._first_bit(fd.open[term]), MAZE_STAND)
		await _wait(30)
		await _shot("57_term")
	for prop in fd.props:
		var c := MineAssembler.cell_of(prop.global_position)
		if fd.pieces.has(c) and fd.pieces[c]["name"] == "straight" and fd.kind.get(c, "") != "stub":   # 입구 직선(stub)은 #36 광부(3배)가 화면을 막는다
			_stand_before(player, head, fd, c, MineAssembler._first_bit(fd.open[c]), MAZE_STAND)
			await _wait(30)
			await _shot("58_props")
			break
	for i in asm.floors.size():
		_draw_map(asm.floors[i], "%s/play_%d_map_%d.png" % [_out_dir, 59 + i, i])
	# #27 수정: 사용자 지적 자리 — 벽 1.6 m 정면 · 바닥 내려다봄 · 소품 무더기 복도 5 m
	_stand_at(player, head, TEXCMP_WALL_STAND, 1)
	await _wait(30)
	var wall_spot := await _spot_ratio_center()
	await _shot("61_wall_close")
	_check(wall_spot <= SPOT_MAX_RATIO, "벽 1.6 m 정면: 가장 밝은 덩이 ÷ 중앙 평균 %.2f ≤ %.1f (램프 흰 점 없음. 있으면 2.3)" % [wall_spot, SPOT_MAX_RATIO])
	player.global_position = TEXCMP_FLOOR_STAND
	player.rotation.y = 0.0
	head.rotation.x = deg_to_rad(-80.0)
	player.velocity = Vector3.ZERO
	await _wait(30)
	var floor_spot := await _spot_ratio_center()
	await _shot("62_floor_down")
	_check(floor_spot <= SPOT_MAX_RATIO, "바닥 내려다봄: 가장 밝은 덩이 ÷ 중앙 평균 %.2f ≤ %.1f (있으면 1.9)" % [floor_spot, SPOT_MAX_RATIO])
	for cl in fd.clusters:
		var c: Vector2i = cl["cell"]
		if fd.pieces.has(c) and fd.pieces[c]["name"] == "straight" and fd.kind.get(c, "") != "stub":   # 입구 직선은 광부가 막는다 (#36)
			_stand_before(player, head, fd, c, MineAssembler._first_bit(fd.open[c]), CLUSTER_VIEW_DIST - Tuning.GRID_CELL * 0.5)
			await _wait(30)
			await _shot("63_props_corridor")
			break
	# #27 수정 2: 갈림 모서리 이음새 — 직선 칸과 T·+ 사이 이음새의 오른쪽 벽을 본다. 검은 픽셀(벽 뒤 빈 공간)이 없어야 한다
	var slit_sum := 0
	var slit_n := 0
	for pair in [["t", "64_seam_t"], ["cross", "65_seam_cross"]]:
		var found := false
		for sm in fd.seams:
			var c: Vector2i = sm["cell"]
			var nb: Vector2i = c + MineAssembler.DIR_VEC[sm["face"]]
			if not (fd.pieces.has(c) and fd.pieces.has(nb)):
				continue
			var names: Array = [fd.pieces[c]["name"], fd.pieces[nb]["name"]]
			if "straight" in names and pair[0] in names:
				await _seam_view(player, head, fd, sm)
				var dark := await _dark_px_in_disk()
				await _shot(pair[1])
				slit_sum += dark
				slit_n += 1
				found = true
				break
		if not found:
			print("FAIL 이음새 %s 를 못 찾음" % pair[0])
	_check(slit_n == 2 and slit_sum / maxi(slit_n, 1) <= SLIT_MAX_PX,
		"갈림 모서리 이음새 검은 픽셀 평균 %d ≤ %d (칼라 전 1,400~1,950)" % [slit_sum / maxi(slit_n, 1), SLIT_MAX_PX])
	# 갱도 설비 (#28): 정거장에서 가장 가까운 직선 칸 — 왼쪽 벽 위(케이블·풍관) · 오른쪽 벽 허리(배관) · 바닥(배수로) · 밸브 칸
	var svc_cell := _nearest_straight(fd, fd.entry)
	if svc_cell.x >= 0:
		_svc_stand(player, head, fd, svc_cell, -1, 1.3, 30.0)
		await _wait(30)
		await _shot("66_svc_left")
		_svc_stand(player, head, fd, svc_cell, 1, 1.3, -15.0)
		await _wait(30)
		await _shot("67_svc_right")
		_svc_stand(player, head, fd, svc_cell, -1, 0.6, -55.0)
		await _wait(30)
		await _shot("68_svc_ditch")
	for sv in fd.services:
		if sv["side"] == "R" and sv["variant"] == 1:
			_svc_stand(player, head, fd, sv["cell"], 1, 1.3, -10.0, -1.6)
			await _wait(30)
			await _shot("69_svc_valve")
			break


# ---------------- --only 구간 (#37) ----------------

## 이 구간을 돌리나. --only 가 비면 전부
func _stage(name: String) -> bool:
	return _only.is_empty() or name in _only


## 제안서별 구간. 전부 위층 fd 에서, 각 함수가 _stand_at 로 자리를 새로 잡아 서로 안 이어진다
func _proposal_stages(room: Node3D, player: CharacterBody3D, head: Node3D) -> void:
	var asm := _asm(room)
	if asm == null or asm.floors.is_empty():
		return
	var fd: MineAssembler.FloorData = asm.floors[0]
	if _stage("cart"):     # 광차 (#29): 순환선 시작(정거장 앞 직선 끝) 옆에 서서 정차하는 광차를 기다려 E 로 타고, 달리는 동안 5장, E 로 내린다
		await _cart_ride(player, head, fd)
	if _stage("repair"):   # 정비 1 (#30): 부품 줍기 → 느린 걸음 → 고장에 세우기 → E 홀드 → 스킬체크 실패 강제 → 성공으로 끝까지
		await _repair_run(player, head, fd)
	if _stage("lamp"):     # 소음·램프 (#32): 서 있기 0 / 걷기 발걸음 → F 끄기 → 4초 적응 → F 켜기
		await _noise_lamp_run(player, head)
	if _stage("move"):     # 이동 세 자세 + 스태미나 + 곡괭이 던지기 (#34)
		await _move_run(room, player, head)
	if _stage("stalker"):  # 괴물 (#35): 등장·배회·소음 조사·눈·추격·놓침·광차 수색+카드·램프 카드·철수·스턴. 잡힘은 맨 끝(_stalker_catch_run)
		await _stalker_run(room, player, head, fd)


## --only 에 base 가 없을 때: 이름 붙은 구간만. 모르는 이름은 FAIL (오타로 아무것도 안 돌고 PASS 하지 않게)
func _only_stages(room: Node3D, player: CharacterBody3D, head: Node3D) -> void:
	for n in _only:
		_check(n in STAGES, "--only 구간 이름 '%s' (있는 것: %s)" % [n, ", ".join(STAGES)])
	if _stage("maze"):
		await _maze_shots(room, player, head)
	await _proposal_stages(room, player, head)
	if _stage("stalker"):
		await _stalker_catch_run(room)


func _noise_kind(list: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in list:
		if e["kind"] == kind:
			out.append(e)
	return out


# ---------------- 이동 세 자세 · 스태미나 · 던지기 (#34) ----------------

## 입구(0, −2)에서 -Z 로. 자세별 1초 이동 = 속도 ±10 %, 발걸음 수·반경 = 표 / 숙이면 눈 1.0 / 달리기 5.5초 → 탈진·정지 → 100 → 풀림 /
## 던지기 → 뷰모델 숨김·못 침 → 착지 소음 1·반경 / E → 복귀. 캡처 83_crouch · 84_run_0~4 · 85_throw_0~4 · 86_pick_floor · 87_exhausted
func _move_run(room: Node3D, player: CharacterBody3D, head: Node3D) -> void:
	var stances := {"crouch": KEY_CTRL, "walk": KEY_NONE, "run": KEY_SHIFT}
	for st in ["crouch", "walk", "run"]:
		_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)
		player.stamina = Tuning.STAMINA_MAX
		await _wait(20)
		var mod: Key = stances[st]
		if mod != KEY_NONE:
			_inject_key(mod, true)
		_inject_key(KEY_W, true)
		await _wait(20)                                            # 가속·눈 내려감
		var eye: float = head.position.y
		var p0: Vector3 = player.global_position
		var nz0: int = NoiseBus.total
		if st == "crouch":
			await _shot("83_crouch")
		var frames := 0
		while frames < 60:
			if st == "run" and frames % 12 == 0:
				await _grab()
			await _wait(1)
			frames += 1
		var v: float = player.global_position.distance_to(p0)
		var steps := _noise_kind(NoiseBus.since(nz0), "step")
		var st_now: String = player.stance                         # 키를 떼기 전에 읽는다
		_inject_key(KEY_W, false)
		if mod != KEY_NONE:
			_inject_key(mod, false)
		if st == "run":
			_flush_burst("84_run")
		var row: Dictionary = Tuning.STANCE[st]
		var want_speed: float = row["speed"]
		var want_steps: int = int(1.0 / row["step"]) + 1
		_check(want_speed > 0.5 and st_now == st, "%s: 자세 %s" % [st, st_now])
		_check(absf(v - want_speed) <= want_speed * 0.1, "%s 1초 이동 %.2f m = %.1f ±10 %% (> 0)" % [st, v, want_speed])
		var r_ok: bool = steps.size() > 0 and steps[0]["radius"] == row["radius"] and row["radius"] > 0.0
		_check(r_ok and absi(steps.size() - want_steps) <= 1, "%s 발걸음 %d회 (표 %d ±1), 반경 %.0f > 0" % [st, steps.size(), want_steps, row["radius"]])
		if st == "crouch":
			_check(absf(eye - Tuning.CROUCH_EYE) <= 0.05 and Tuning.CROUCH_EYE <= Tuning.EYE_HEIGHT - 0.5, "숙이면 눈높이 %.2f = %.1f (평소 %.1f 보다 0.5 넘게 낮다 — 사보타주 1.7 은 통과했었다)" % [eye, Tuning.CROUCH_EYE, Tuning.EYE_HEIGHT])
		await _wait(20)
	_check(absf(head.position.y - Tuning.EYE_HEIGHT) <= 0.05, "Ctrl 떼면 눈높이 %.2f = %.1f" % [head.position.y, Tuning.EYE_HEIGHT])
	# 달리며 점프 (사용자 09-11: Shift 중 스페이스가 안 먹었다). Shift+W 0.5초 뒤 스페이스 → 0.4 s 안에 0.5 m 넘게 뜬다. 숙인 채(Ctrl)는 안 뜬다
	_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)
	player.stamina = Tuning.STAMINA_MAX
	await _wait(20)
	_inject_key(KEY_SHIFT, true)
	_inject_key(KEY_W, true)
	await _wait(30)
	var jy0: float = player.global_position.y
	await _tap(KEY_SPACE)
	var jy_top := jy0
	for k in 24:
		await _wait(1)
		jy_top = maxf(jy_top, player.global_position.y)
	_inject_key(KEY_W, false)
	_inject_key(KEY_SHIFT, false)
	_check(jy_top - jy0 >= 0.5, "달리며(Shift) 스페이스 → %.2f m 뜸 (≥ 0.5)" % (jy_top - jy0))
	await _wait(40)
	_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)
	await _wait(20)
	_inject_key(KEY_CTRL, true)
	await _wait(15)
	var cy0: float = player.global_position.y
	await _tap(KEY_SPACE)
	var cy_top := cy0
	for k in 24:
		await _wait(1)
		cy_top = maxf(cy_top, player.global_position.y)
	_inject_key(KEY_CTRL, false)
	_check(cy_top - cy0 < 0.2, "숙인 채(Ctrl) 스페이스 → 안 뜬다 (%.2f m)" % (cy_top - cy0))
	await _wait(15)
	# 탈진: Shift+W 를 5.5초 → 스태미나 0·정지. 떼고 기다리면 100 에서 풀린다
	_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)
	player.stamina = Tuning.STAMINA_MAX
	await _wait(20)
	_inject_key(KEY_SHIFT, true)
	_inject_key(KEY_W, true)
	await _wait(int(Tuning.STAMINA_MAX / Tuning.STAMINA_RUN * 60.0) + 30)
	var pe: Vector3 = player.global_position
	await _wait(30)
	var moved_ex: float = player.global_position.distance_to(pe)
	_check(Tuning.STAMINA_RUN > 0.0 and player.exhausted and player.stamina < Tuning.STAMINA_MAX and moved_ex < 0.3,
		"5.5초 달림 → 탈진 %s, 0.5초 이동 %.2f m < 0.3 (스태미나 %.0f)" % [player.exhausted, moved_ex, player.stamina])
	_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)           # 38 m 달려 벽에 닿았을 수 있다 — 입구로 (탈진은 그대로)
	await _wait(3)
	await _shot("87_exhausted")
	_inject_key(KEY_W, false)
	_inject_key(KEY_SHIFT, false)
	var waited := 0
	while player.exhausted and waited < 480:
		await _wait(1)
		waited += 1
	_inject_key(KEY_W, true)
	var pr: Vector3 = player.global_position
	await _wait(30)
	_inject_key(KEY_W, false)
	_check(not player.exhausted and waited < 480 and player.global_position.distance_to(pr) > 1.0,
		"%.1f초 뒤 탈진 풀림, 다시 걷는다 (0.5초 %.2f m > 1)" % [waited / 60.0, player.global_position.distance_to(pr)])
	# 던지기
	_stand_at(player, head, Vector3(0.0, 0.0, -2.0), 0)
	await _wait(20)
	var pick: Node3D = player.get_node("Head/Camera3D/Pickaxe")
	var nz_t: int = NoiseBus.total
	_inject_button(MOUSE_BUTTON_RIGHT, true)
	await _wait(1)
	_inject_button(MOUSE_BUTTON_RIGHT, false)
	await _wait(2)
	_check(not player.has_pick and not pick.visible, "오른쪽 클릭 → 곡괭이 던짐 (has_pick %s, 뷰모델 보임 %s)" % [player.has_pick, pick.visible])
	for k in 5:
		await _grab()
		await _wait(6)
	_flush_burst("85_throw")
	var thrown: ThrownPick = room.find_child("ThrownPick", true, false) as ThrownPick
	var waited_land := 0
	while thrown != null and not thrown.landed and waited_land < 180:
		await _wait(1)
		waited_land += 1
	var lands := _noise_kind(NoiseBus.since(nz_t), "pick_land")
	var d_land: float = thrown.land_pos.distance_to(player.global_position) if thrown != null else -1.0
	_check(thrown != null and thrown.landed and lands.size() == 1 and lands[0]["radius"] == Tuning.NOISE_PICK_LAND and Tuning.NOISE_PICK_LAND > 0.0,
		"착지 소음 1회 (실제 %d), 반경 %.0f > 0" % [lands.size(), Tuning.NOISE_PICK_LAND])
	_check(d_land >= 3.0 and d_land <= 16.0, "착지 거리 %.1f m (3~16)" % d_land)
	var chunks0 := _count_chunks(room)
	_inject_button(MOUSE_BUTTON_LEFT, true)
	await _wait(4)
	_inject_button(MOUSE_BUTTON_LEFT, false)
	await _wait(10)
	_check(not pick.is_swinging() and not pick.visible and _count_chunks(room) == chunks0, "곡괭이 없이는 클릭해도 안 친다")
	if thrown != null:
		_stand_at(player, head, thrown.global_position + Vector3(0.0, 0.0, 1.2) - Vector3(0.0, thrown.global_position.y, 0.0), 0)
		head.rotation.x = deg_to_rad(-40.0)
		await _wait(20)
		await _shot("86_pick_floor")
		await _tap(KEY_E)
		await _wait(6)
	_check(player.has_pick and pick.visible and room.find_child("ThrownPick", true, false) == null, "E → 곡괭이 회수 (has_pick %s, 몸체 남음 %s)" % [player.has_pick, room.find_child("ThrownPick", true, false) != null])
	head.rotation.x = 0.0


# ---------------- 갱목 광부 (#36) ----------------

## 층마다 Director.paused (#35). 봇이 재는 동안 감독이 괴물을 내려놓지 않게
func _pause_directors(room: Node3D, on: bool) -> void:
	var asm := _asm(room)
	if asm == null:
		return
	for fd in asm.floors:
		if fd.director != null:
			fd.director.paused = on


## 가슴 앞면 높이맵(3 cm 격자, 칸마다 가장 앞 z)의 라플라시안 잔차 RMS (#43). 패치 = 가슴 평평한 앞면(z 1.50~1.80, 쇄골·옆구리 제외). 매끈한 통이면 작고 갈비가 있으면 크다. Blender stage10 과 같은 계산.
func _chest_relief(vs: PackedVector3Array, x0: float, x1: float) -> float:
	var cell := 0.03
	var cells := {}
	for v in vs:
		if v.x >= x0 and v.x <= x1 and v.y >= 1.50 and v.y <= 1.80 and v.z > -0.05:
			var k := Vector2i(roundi(v.x / cell), roundi(v.y / cell))
			cells[k] = maxf(cells.get(k, -1e9), v.z)
	var sum2 := 0.0
	var n := 0
	for k in cells:
		var nb := 0
		var acc := 0.0
		for di in [-1, 0, 1]:
			for dj in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var kk := Vector2i(k.x + di, k.y + dj)
				if cells.has(kk):
					nb += 1
					acc += cells[kk]
		if nb >= 6:
			var r: float = cells[k] - acc / nb
			sum2 += r * r
			n += 1
	return sqrt(sum2 / n) if n > 0 else 0.0


## 재질 (#39): 6 m 정면 켬 밝기(하얗게 안 뜨고, 보이긴 한다) → 3 m 캡처 97 → 6 m 끄고 4 s: 실루엣이 벽보다 밝지 않다 + 캡처 98. 램프는 켠 채로 돌려준다. 괴물은 hold 상태
func _skin_run(st: Stalker, head: Node3D) -> void:
	st.place(Vector3(0.0, 0.0, -12.5 - SKIN_NEAR_M), Vector3(0.0, 0.0, -12.5))
	await _wait(30)
	var on_c: float = await _screen_luma_disk(SKIN_DISK_R, true)
	_check(on_c >= SKIN_LUMA_ON_MIN and on_c <= SKIN_LUMA_ON_MAX, "재질: 램프 켜고 %.0f m 정면 가운데 밝기 %.4f (%.2f ~ %.2f — 하얗게 안 뜨고 보인다)" % [SKIN_NEAR_M, on_c, SKIN_LUMA_ON_MIN, SKIN_LUMA_ON_MAX])
	st.place(Vector3(0.0, 0.0, -12.5 - SKIN_CLOSE_M), Vector3(0.0, 0.0, -12.5))
	await _tap(KEY_F)                        # #45: 램프를 보면 한 프레임에 추격(run = 네발 기기)이라 얼굴·손이 안 보인다 → 램프 끄고 수색 자세(서서 두리번)로 세운 뒤 정지, 다시 켜고 찍는다
	await _wait(12)
	st.force_state("search")
	await _wait(20)
	st.set_frozen(true)
	await _tap(KEY_F)
	await _wait(30)
	await _shot("97_stalker_skin")
	st.place(Vector3(0.0, 0.0, -12.5 - SKIN_FACE_M), Vector3(0.0, 0.0, -12.5))   # #40: 잡히는 거리에서 얼굴 — 시선을 올려 본다
	head.rotation.x = deg_to_rad(SKIN_FACE_UP_DEG)
	await _wait(30)
	await _shot("99_stalker_face")
	st.place(Vector3(0.0, 0.0, -12.5 - SKIN_HAND_M), Vector3(0.0, 0.0, -12.5))   # #42: 조금 물러나 시선을 내려 손(발톱 4개)
	head.rotation.x = deg_to_rad(-SKIN_HAND_DOWN_DEG)
	await _wait(30)
	await _shot("99b_stalker_hand")
	head.rotation.x = 0.0
	st.set_frozen(false)
	st.place(Vector3(0.0, 0.0, -12.5 - SKIN_NEAR_M), Vector3(0.0, 0.0, -12.5))
	await _tap(KEY_F)
	await _wait(240)
	var off_c: float = await _screen_luma_disk(SKIN_DISK_R, true)
	var off_e: float = await _screen_luma_disk(SKIN_DISK_R, false)
	await _shot("98_stalker_lamp_off")
	_check(off_c - off_e <= SKIN_LUMA_OFF_GAIN, "재질: 끄고 4 s, %.0f m 괴물 가운데 %.4f − 벽 가장자리 %.4f = %.4f ≤ %.3f (실루엣이 안 남는다)" % [SKIN_NEAR_M, off_c, off_e, off_c - off_e, SKIN_LUMA_OFF_GAIN])
	await _tap(KEY_F)
	await _wait(12)
	# 개발용 정지 (#43 F5, 숫자 8): 60 프레임 동안 자리·클립 시각이 그대로, 풀면 클립이 돈다. 키는 DebugHud 가 받으므로 배포물(봇)에선 API 로, 디버그 실행에선 키로
	st.hold = false
	st.force_state("chase")
	var clip_frames := 0
	while st.body.clip_position() < 0.0 and clip_frames < 90:                 # 추격 클립이 돌 때까지 (길이 잡히면 _move 가 튼다)
		await _wait(1)
		clip_frames += 1
	var clip_before: String = st.body.current_clip()
	if OS.is_debug_build():
		await _tap(KEY_8)
	else:
		st.set_frozen(true)
	await _wait(2)
	var fz0: bool = st.frozen and st.body.is_paused()
	var p0: Vector3 = st.global_position
	var t0: float = st.body.clip_position()
	await _wait(60)
	var moved: float = st.global_position.distance_to(p0)
	var t1: float = st.body.clip_position()
	if OS.is_debug_build():
		await _tap(KEY_8)
	else:
		st.set_frozen(false)
	await _wait(6)
	var back: bool = not st.frozen and not st.body.is_paused() and st.body.clip_position() >= 0.0
	_check(fz0 and t0 >= 0.0 and moved < 0.001 and t0 == t1 and back, "정지 키 8: 클립 %s(%d 프레임 뒤) 정지 %s · 60 프레임 이동 %.3f m · 클립 시각 %.2f → %.2f · 재개 %s" % [clip_before, clip_frames, fz0, moved, t0, t1, back])
	st.hold = true
	st.force_state("wander")
	st.place(Vector3(0.0, 0.0, -12.5 - STALKER_FAR_M), Vector3(0.0, 0.0, -12.5))
	await _wait(12)

## 위층 fd 에서. 봇이 압박·상태·자리를 직접 넣고 읽는다 (Director.paused 로 감독을 세워 두고 잰다). 캡처 91~95. 잡힘(96)은 _stalker_catch_run
func _stalker_run(room: Node3D, player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData) -> void:
	var st := fd.stalker as Stalker
	var dr := fd.director as Director
	if st == null or dr == null:
		_check(false, "Stalker · Director 있음")
		return
	var g: float = Tuning.GRID_CELL
	# 0. 준비: 입구 직선 z −12.5 에서 −Z 를 본다, 램프 켠 채, 서 있기
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	if not player.lamp_on:
		await _tap(KEY_F)
	await _wait(20)
	# 1. 압박 80 → 등장: 곡선 칸, 격자 거리 3~6, 시야 밖(후보가 있으면), 클립 walk_crouch. 앞 구간 동안 감독은 멈춰 있었다 — 여기서 처음부터
	st.hide_away()
	dr.pressure = 0.0
	dr.paused = false
	await _wait(2)
	_check(st.state == "hidden" and not st.visible and dr.pressure < 1.0, "시작은 숨김 (상태 %s, 압박 %.1f)" % [st.state, dr.pressure])
	dr.pressure = Tuning.PRESSURE_SEND
	await _wait(2)
	var sc: Vector2i = dr.last_spawn_cell
	var pc: Vector2i = MineAssembler.cell_of(player.global_position)
	var dist: Dictionary = MineAssembler.grid_dist(fd, pc, Tuning.SPAWN_CELLS_MAX + 2)
	var gd: int = dist.get(sc, -1)
	var want_piece: String = "straight" if st.on_ceiling else "curve"             # #49 절반은 천장(직선 칸) · 절반은 바닥(곡선 칸)
	_check(st.state == "wander" and st.visible and sc.x >= 0 and fd.pieces.has(sc) and fd.pieces[sc]["name"] == want_piece
		and gd >= Tuning.SPAWN_CELLS_MIN and gd <= Tuning.SPAWN_CELLS_MAX and (dr.last_spawn_behind or dr.last_behind_cands == 0)
		and MineAssembler.cell_of(st.position) == sc,
		"압박 80 → 등장: 상태 %s · %s 칸 %s (천장 %s) · 격자 거리 %d (3~6) · 시야 밖 %s (후보 %d) · 클립 %s" % [st.state, want_piece, sc, st.on_ceiling, gd, dr.last_spawn_behind, dr.last_behind_cands, st.body.current_clip()])
	st.set_ceiling(false)                                                        # 뒤 검사는 바닥 기준이다
	dr.paused = true                                                          # 여기부터 감독은 손 뗀다 — 압박이 내려가 철수하면 재는 게 깨진다
	# 캡처 91: 직선 끝(z −24.5)에 놓고 12 m 에서 본다. 램프가 켜져 있어 눈이 보고 추격으로 넘어간다 — 찍고 되돌린다
	st.hold = true
	st.place(Vector3(0.0, 0.0, -12.5 - STALKER_FAR_M), Vector3(0.0, 0.0, -12.5))
	await _wait(30)
	await _shot("91_stalker_far")
	var saw: String = st.state
	if SKIN_TEST:
		await _skin_run(st, head)
	# 2. 램프 끄고(먼저 — 켜진 채 되돌리면 빛 감각이 다시 조사로 보낸다) 배회로 되돌려 서 있기 2초(소음 0) → 배회 그대로, 안 온다
	await _tap(KEY_F)
	await _wait(12)
	st.force_state("wander")
	st.hold = false
	var d0: float = st.global_position.distance_to(player.global_position)
	await _wait(120)
	var d1: float = st.global_position.distance_to(player.global_position)
	_check((saw == "chase" or saw == "drop") and st.state == "wander" and d1 > 3.0, "램프 켜면 12 m 에서 봄(%s = 엎드리기/추격) · 끄고 서 있기 2초 → 배회 %s, 거리 %.1f → %.1f (안 온다)" % [saw, st.state, d0, d1])
	# 3. 소음 → 조사 → 수색. 그동안 벽 관통 0. 플레이어 옆을 지나면 93 한 장
	var noise_at: Vector3 = Vector3(0.0, fd.y, -8.5)                              # 플레이어(−12.5) 뒤 4 m — 옆을 지나간다
	var nd: float = st.global_position.distance_to(noise_at)
	var budget := int((nd / Tuning.STALKER_SPEED["investigate"] + 1.5) * 60.0)
	NoiseBus.make(noise_at, Tuning.NOISE_PICK, "pick", player)
	await _wait(1)
	var went_inv: bool = st.state == "investigate"
	var viol := 0
	var reached := -1
	var passed := false
	for k in budget:
		await _wait(1)
		if not fd.open.has(MineAssembler.cell_of(st.position)):
			viol += 1
		if not passed and st.global_position.distance_to(player.global_position) <= 3.0:
			passed = true
			await _shot("93_lamp_pass")
		if st.global_position.distance_to(noise_at) <= 1.5:
			reached = k
			break
	_check(went_inv and reached >= 0, "소음(25 m) → 조사 → %d프레임에 1.5 m 안 (한도 %d, %.1f m ÷ 4.0 + 1.5 s)" % [reached, budget, nd])
	_check(viol == 0, "조사 길에서 벽 관통 0 (실제 %d프레임)" % viol)
	await _wait(60)
	_check(st.state == "search" and st.body.current_clip() == "idle_crouch" or st.state == "search" and st.body.current_clip() == "walk_crouch", "도착 1초 뒤 수색 (상태 %s, 클립 %s)" % [st.state, st.body.current_clip()])
	# 4. 램프 끈 채 숙여 원뿔 안 8 m 정지 3초 → 추격 아님. F → 1초 안 추격, 클립 run
	st.force_state("wander")
	st.hold = true
	st.place(Vector3(0.0, 0.0, -12.5 - STALKER_NEAR_M), Vector3(0.0, 0.0, -12.5))
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	_inject_key(KEY_CTRL, true)
	await _wait(180)
	_check(st.state != "chase" and not player.lamp_on, "램프 끄고 숙여 8 m 앞 3초 → 추격 아님 (상태 %s)" % st.state)
	_inject_key(KEY_CTRL, false)
	await _tap(KEY_F)
	var chase_at := -1
	for k in 60:
		await _wait(1)
		if st.state == "chase":
			chase_at = k
			break
	_check(chase_at >= 0 and st.body.current_clip() == "run_stand", "F 켬 → %d프레임에 추격 (≤ 60), 클립 %s" % [chase_at, st.body.current_clip()])
	# 4b. 자세가 튀지 않는지 (#47 섞는 시간): 상태를 갈아 끼우며 머리 높이의 한 프레임 변화량을 잰다.
	#     #48 에서 바닥 추격이 서서 달리기가 되어 '엎드리기'(drop)는 안 쓴다 — 대신 수색→추격→잡기→맞기를 이어서 본다.
	var pos_before: Vector3 = st.position
	st.hold = true
	st.place(Vector3(0.0, 0.0, -18.5), Vector3(0.0, 0.0, -12.5))
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	st.force_state("search")
	await _wait(6)
	var y_prev: float = st.body.head_y()
	var y_jump := 0.0
	var seq: Array = ["chase", "catch", "hit" if false else "stun", "search"]
	for nxt in seq:
		st.force_state(nxt)
		for k in 24:
			await _wait(1)
			var y: float = st.body.head_y()
			y_jump = maxf(y_jump, absf(y - y_prev))
			y_prev = y
	_check(y_jump <= STALKER_POSE_JUMP_M,
		"자세 전환: 수색→추격→잡기→스턴→수색 동안 머리 한 프레임 최대 %.2f m (≤ %.2f)" % [y_jump, STALKER_POSE_JUMP_M])
	st.hold = false
	st.place(pos_before, Vector3(0.0, 0.0, -12.5))
	st.last_seen = Vector3(0.0, fd.y, -12.5)
	st.force_state("chase")
	st._lose_left = Tuning.STALKER_LOSE_S
	# 5. 추격 속도: 플레이어를 정거장(z +8, 눈 12 m 밖)으로 옮기고 1초 — 마지막 자리(8 m 앞)로 6.5 m/s
	st.hold = false
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)
	var p0: Vector3 = st.global_position
	await _wait(60)
	var moved: float = Vector2(st.global_position.x - p0.x, st.global_position.z - p0.z).length()
	var want_c: float = Tuning.STALKER_SPEED["chase"]
	var fwd: Vector3 = st.global_transform.basis.z
	var yaw_err: float = rad_to_deg(Vector3(fwd.x, 0.0, fwd.z).angle_to(Vector3(0.0, 0.0, 1.0)))
	_check(st.state == "chase" and absf(moved - want_c) <= want_c * 0.1, "추격 1초 이동 %.2f m = %.1f ±10 %%" % [moved, want_c])
	_check(yaw_err <= 10.0, "앞면이 이동 방향 (오차 %.1f° ≤ 10)" % yaw_err)
	# 캡처 92: 플레이어를 11 m 앞(z −4)에 두고 다가오는 5장, 잡히기 전에 뺀다. (#45: 8.5 m 는 무거운 메시의 캡처 5장 동안 6.5 m/s 로 닿아 잡힘 → 방이 다시 떠 뒤 검사가 깨졌다)
	st.place(Vector3(0.0, 0.0, -15.0), Vector3(0.0, 0.0, -4.0))
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	for k in 5:
		await _grab()
		await _wait(8)
	_flush_burst("92_stalker_chase")
	# 4c. 손 접지 (#46): 제자리에서 기는 1초 동안 **그려진** 손끝 높이. 보정 전 값도 같이 봐서 "고칠 게 있었다"를 확인한다.
	#     고도는 SkeletonModifier3D 결과를 그린 뒤 뼈를 원래 자세로 되돌린다 — 밖에서 뼈를 읽으면 보정 전 값이 나온다.
	st.hold = true
	st.place(Vector3(0.0, 0.0, -7.5), Vector3(0.0, 0.0, -4.0))               # 3.5 m — 손이 화면에서 보이는 거리 (잡힘 1.5 m 밖)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	head.rotation.x = deg_to_rad(-18.0)                                      # 손이 닿는 바닥을 내려다본다
	st.body.play("crawl")                                                    # #48 뒤로 바닥에서는 기지 않는다 — 같은 코드의 '바닥 면' 쪽을 클립을 직접 틀어 본다
	var hand_drawn := INF
	var hand_raw := INF
	for k in 60:
		await _wait(1)
		st.body.play("crawl")
		hand_drawn = minf(hand_drawn, st.body.hand_clear_drawn())
		hand_raw = minf(hand_raw, st.body.hand_clear_raw())
		if k % 12 == 1:
			await _grab()
	_flush_burst("92b_stalker_hand")
	head.rotation.x = 0.0
	st.hold = false
	_check(hand_drawn >= -STALKER_HAND_SINK_M and hand_raw <= -0.2,
		"손 접지: 그려진 손끝 %+.3f m (≥ %.2f) · 보정 전 %+.3f m (≤ −0.20, 고칠 게 있었다) · 클립 %s" % [hand_drawn, -STALKER_HAND_SINK_M, hand_raw, st.body.current_clip()])
	# 4d. 천장 (#48): 천장에 붙여 1초 배회 — 붙은 높이·거꾸로 매달림·속도. 캡처는 올려다본 5장
	st.force_state("wander")
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -4.0))
	var ceil_h: float = st.ceiling_y(st.position)
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)                      # 속도를 재는 동안 플레이어를 눈 밖에 둔다 (보면 쫓아오느라 안 움직인다)
	st.investigate(Vector3(0.0, fd.y, -21.0))                                # 곧은 복도 안쪽 — 배회는 도착해서 멈추므로 속도를 못 잰다
	st.set_ceiling(true)                                                     # 길을 바닥에서 잡은 뒤에 붙인다 — #49 부터 천장에서 조사를 부르면 벽을 타고 내려온다
	await _wait(20)
	var attach: float = st.position.y
	var head_below: float = st.body.head_y() - st.global_position.y
	var cp0: Vector3 = st.position
	var y_min: float = attach
	var y_max: float = attach
	var ceil_moved := 0.0                                                    # 모퉁이를 돌 수 있으니 직선 거리가 아니라 간 거리를 더한다
	var ceil_stuck := 0
	var ceil_cols := 0
	var ceil_hand := INF                                                     # 천장면에서 손이 가장 깊이 들어간 거리 (그려진 값, − = 면 속)
	var ceil_hand_raw := INF
	for k in 60:
		await _wait(1)
		var step: float = Vector2(st.position.x - cp0.x, st.position.z - cp0.z).length()
		ceil_moved += step
		if step < 0.01:
			ceil_stuck += 1
		ceil_cols += st.get_slide_collision_count()
		cp0 = st.position
		y_min = minf(y_min, st.position.y)
		y_max = maxf(y_max, st.position.y)
		ceil_hand = minf(ceil_hand, st.body.hand_clear_drawn())
		ceil_hand_raw = minf(ceil_hand_raw, st.body.hand_clear_raw())
	_check(ceil_h > Tuning.STALKER_CEIL_MIN_H and absf(attach - (ceil_h - Tuning.STALKER_CEIL_CLEAR)) <= 0.05 and head_below < -0.5,
		"천장: 천장 %.2f m 밑 %.2f m 에 붙음(틈 %.2f) · 머리가 원점보다 %.2f m 아래(거꾸로)" % [ceil_h, attach, ceil_h - attach, head_below])
	# 이 구간은 investigate 로 움직이므로 기준값도 천장 조사 속도다 (#53 부터 천장 속도가 상태별이다 — 배회 2.5 · 조사 4.0 · 추격 6.5)
	_check(absf(ceil_moved - Tuning.STALKER_CEIL_INV_SPEED) <= Tuning.STALKER_CEIL_INV_SPEED * 0.2 and (y_max - y_min) <= STALKER_CEIL_KEEP_M,
		"천장 이동(조사) 1초 %.2f m = %.1f ±20 %% · 높이 흔들림 %.3f m (≤ %.2f) · 멈춘 프레임 %d · 닿음 %d" % [ceil_moved, Tuning.STALKER_CEIL_INV_SPEED, y_max - y_min, STALKER_CEIL_KEEP_M, ceil_stuck, ceil_cols])
	_check(ceil_hand >= -STALKER_HAND_SINK_M,
		"천장 손 접지: 손이 천장면에서 %+.3f m (≥ %.2f, − = 천장 속) · 보정 전 %+.3f m" % [ceil_hand, -STALKER_HAND_SINK_M, ceil_hand_raw])
	st.hold = true
	st.place(Vector3(0.0, 0.0, -13.0), Vector3(0.0, 0.0, -4.0))              # 9 m — 낙하 문턱(7.5) 밖. 안 그러면 캡처 도중 떨어진다
	st.position.y = st.ceiling_y(st.position) - Tuning.STALKER_CEIL_CLEAR
	st.force_state("wander")                                                 # 추격이 아니어야 낙하 판정이 안 돌고, 수색은 #49 부터 바닥으로 내려간다
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	head.rotation.x = deg_to_rad(22.0)                                       # 천장을 올려다본다
	for k in 5:
		await _grab()
		await _wait(6)
	_flush_burst("92d_stalker_ceiling")
	head.rotation.x = 0.0
	# #59 노려보기 기준값: 천장 기기 자세(굽힘 없음)에서 엉덩이·발–천장 거리 최대. crawl 한 바퀴 동안
	var crawl_hip := -INF
	var crawl_foot := -INF
	var crawl_lift := -INF
	st.body.play("crawl")                                                    # hold 중인 배회는 클립을 안 바꾼다 — 앞 구간의 run 이 남아 있었다
	for k in clampi(ceili(st.body.clip_length("crawl") / maxf(st.body.speed(), 0.01) * 60.0), 30, 300):
		await _wait(1)
		crawl_hip = maxf(crawl_hip, st.body.glare.hip_gap)
		crawl_foot = maxf(crawl_foot, st.body.glare.foot_gap)
		crawl_lift = maxf(crawl_lift, st.body.glare.lift_deg)
	print("ok 천장 기기 자세 (#59 기준, 클립 %s): 엉덩이–천장 최대 %.2f m · 발 %.2f m · 상체 들린 각 최대 %.1f°" % [st.body.current_clip(), crawl_hip, crawl_foot, crawl_lift])
	# 4e. 낙하 (#48 → #57 → #59): 천장에서 7.5 m 안에 플레이어가 들면 엎드린 채 상체를 들어 노려보고 팔을 뻗고(hang) → 머리부터 떨어져 몸을 세우고(fall) → 착지 → 서서 달린다.
	#     #57 레퍼런스(조사 #56 리커·에일리언·베르두고): 팔을 옆으로 안 벌린다 · 멈춰 노려본다 · 머리부터. 캡처 92f = 플레이어 시점 0.1초 간격
	#     사보타주: STALKER_FALL_CLIP "fall_air" + STALKER_REACH_ON false → 팔 벌림 FAIL / STALKER_HANG_S 0 → 매달림 FAIL /
	#     STALKER_GLARE_ON false → 노려보기·숨쉬기 FAIL / hang 클립 idle_crouch(옛 #57) → 엉덩이·발 천장 FAIL
	st.hold = false
	st.place(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -4.0))
	st.position.y = st.ceiling_y(st.position) - Tuning.STALKER_CEIL_CLEAR
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	st.force_state("chase")
	var drop_r: Dictionary = await _drop_watch(st, player, 6, 14)
	_flush_burst("92f_stalker_fall")
	print("ok 낙하 실측: 매달림 %d → 놓음 %d → 착지 %d 프레임 · 두 손 사이 ÷ 어깨 최대 %.2f (공중만 %.2f) · 팔 방향 최소 %.2f · 착지 직전 기울기 %.1f° · 착지 손끝-바닥 %+.3f (보정 전 %+.3f)" % [drop_r.hang_at, drop_r.fall_at, drop_r.land_at, drop_r.spread_max, drop_r.spread_fall, drop_r.aim_min, drop_r.tilt_deg, drop_r.land_low, drop_r.land_raw])
	_check(drop_r.fall_at >= 0 and drop_r.land_at > drop_r.fall_at and drop_r.fall_clip == Tuning.STALKER_FALL_CLIP and st.position.y <= 0.1,
		"천장에서 떨어짐: %d프레임에 놓음(클립 %s = %s) → %d프레임에 착지(%.2f초), 바닥 y %.2f" % [drop_r.fall_at, drop_r.fall_clip, Tuning.STALKER_FALL_CLIP, drop_r.land_at, float(drop_r.land_at - drop_r.fall_at) / 60.0, st.position.y])
	_check(drop_r.hang_at >= 0 and drop_r.fall_at - drop_r.hang_at >= int(Tuning.STALKER_HANG_S * 60.0) - 2 and drop_r.lift_min >= crawl_lift + STALKER_GLARE_LIFT_OVER and drop_r.head_aim_min >= STALKER_GLARE_AIM_MIN,
		"노려보기 (#59): %d프레임 (≥ %d) · 상체가 천장면에서 들린 각 최소 %.1f° (≥ 기기 자세 최대 %.1f + %.0f) · 얼굴이 플레이어 눈을 봄 최소 %.2f (≥ %.1f)" % [drop_r.fall_at - drop_r.hang_at if drop_r.hang_at >= 0 else -1, int(Tuning.STALKER_HANG_S * 60.0) - 2, drop_r.lift_min, crawl_lift, STALKER_GLARE_LIFT_OVER, drop_r.head_aim_min, STALKER_GLARE_AIM_MIN])
	_check(drop_r.hip_gap <= crawl_hip + STALKER_GLARE_GAP_M and drop_r.foot_gap <= crawl_foot + STALKER_GLARE_GAP_M,
		"엉덩이·발은 천장에 (#59): 엉덩이–천장 최대 %.2f m (≤ 기기 자세 %.2f + %.1f) · 발 %.2f m (≤ %.2f + %.1f)" % [drop_r.hip_gap, crawl_hip, STALKER_GLARE_GAP_M, drop_r.foot_gap, crawl_foot, STALKER_GLARE_GAP_M])
	var breath_m: float = (drop_r.head_hi - drop_r.head_lo).length() if drop_r.head_lo is Vector3 else -1.0
	_check(breath_m >= STALKER_GLARE_BREATH_M and drop_r.tilt_max >= STALKER_GLARE_TILT_MIN,
		"숨쉬기·갸웃 (#59): 노려보는 동안 머리 자리 흔들림 폭 %.3f m (≥ %.2f) · 고개 기울기 최대 %.1f° (≥ %.0f)" % [breath_m, STALKER_GLARE_BREATH_M, drop_r.tilt_max, STALKER_GLARE_TILT_MIN])
	_check(drop_r.aim_min >= STALKER_AIM_MIN,
		"매달린 팔이 플레이어 가슴을 가리킴: 두 팔 평균 최소 %.2f (≥ %.1f, 1 = 정확히)" % [drop_r.aim_min, STALKER_AIM_MIN])
	_check(drop_r.spread_max <= STALKER_SPREAD_MAX,
		"매달림~낙하 두 손 사이 ÷ 어깨 너비 최대 %.2f (≤ %.2f — 팔을 옆으로 안 벌린다)" % [drop_r.spread_max, STALKER_SPREAD_MAX])
	_check(drop_r.head_first and drop_r.tilt_deg >= 0.0 and drop_r.tilt_deg <= STALKER_LAND_TILT_DEG,
		"머리부터: 놓고 0.15초 뒤 머리 < 엉덩이 %s · 착지 직전 몸 기울기 %.1f° (≤ %.0f)" % [drop_r.head_first, drop_r.tilt_deg, STALKER_LAND_TILT_DEG])
	_check(drop_r.blink_low and drop_r.blink_back,
		"예고 깜빡임 (#58): 매달림 동안 램프가 한 번 꺼졌다 켜짐 (꺼짐 %s · 돌아옴 %s)" % [drop_r.blink_low, drop_r.blink_back])
	_check(drop_r.dark_luma >= 0.0 and drop_r.dark_luma <= LAMP_MAX_DARK and int(drop_r.dust) >= 1,
		"떨어지는 동안 화면 밝기 최대 %.4f (≤ %.3f — 공중에서 도는 몸이 안 보인다) · 흙먼지 %d (≥ 1)" % [drop_r.dark_luma, LAMP_MAX_DARK, drop_r.dust])
	_check(int(drop_r.relight_pf) >= 0 and int(drop_r.relight_pf) - int(drop_r.land_at) <= STALKER_RELIGHT_F and drop_r.relight_state == "land",
		"착지 %d프레임 뒤 램프 다시 켜짐 (≤ %d) · 켜진 순간 괴물 %s (= land, 이미 웅크려 있다)" % [int(drop_r.relight_pf) - int(drop_r.land_at), STALKER_RELIGHT_F, drop_r.relight_state])
	_check(drop_r.lamp_on_all and drop_r.amb_ok,
		"빛만 꺼진다: lamp_on 내내 true %s · 환경광 평소 %s (괴물 눈·감독 버릇·눈 적응은 lamp_on 을 본다)" % [drop_r.lamp_on_all, drop_r.amb_ok])
	_check(drop_r.land_low >= -STALKER_HAND_SINK_M,
		"착지 손 접지: 손끝이 바닥에서 %+.3f m (≥ %.2f) · 보정 전 %+.3f m (#48 부터 착지 클립 손이 바닥을 뚫었다)" % [drop_r.land_low, -STALKER_HAND_SINK_M, drop_r.land_raw])
	var chase_clip := ""
	for k in 120:
		await _wait(1)
		if st.state == "chase":
			chase_clip = st.body.current_clip()
			break
	_check(chase_clip == "run_stand" and drop_r.land_dist >= 0.0 and drop_r.land_dist <= 6.0,
		"착지 뒤 서서 달리기(클립 %s) · 착지 순간 플레이어와 %.1f m (≤ 6)" % [chase_clip, drop_r.land_dist])
	# 4e-1. 옆에서 본 낙하 (#57): 팔을 뻗는 방향과 몸이 뒤집히는 모습은 플레이어 시점에서는 겹쳐 안 읽힌다 — 벽 쪽 카메라를 잠깐 켠다. 캡처 92l
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -4.0))
	st.force_state("wander")
	st.set_ceiling(true)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	var side_cam := Camera3D.new()
	fd.root.add_child(side_cam)
	side_cam.position = Vector3(2.8, 2.2, -9.0)
	side_cam.look_at(fd.root.to_global(Vector3(0.0, 2.4, -9.5)))
	side_cam.make_current()
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	st.force_state("chase")
	st.hold = false
	await _drop_watch(st, player, 3, 12, ceili(Tuning.STALKER_HANG_SWING_S * 60.0))   # 늘어진 뒤부터 0.05초 간격 — 공중은 0.35초라 촘촘해야 뒤집히는 게 찍힌다
	_flush_burst("92l_stalker_drop_side")
	(player.get_node("Head/Camera3D") as Camera3D).make_current()
	side_cam.queue_free()
	# 4e-1a. 노려보기 가까이 (#59): 4 m 앞에서 올려다본 정면(92n) · 옆에서 본 허리 접힘(92o — 찌그러짐은 숫자로 못 재서 캡처로 본다).
	#        상체를 다 든 뒤부터 0.083초 간격 5장 = 노려봄 · 갸웃 구간
	for g59_view in ["front", "side"]:
		st.hold = true
		st.set_ceiling(false)
		st.place(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -4.0))
		st.force_state("wander")
		st.set_ceiling(true)
		var g59_cam: Camera3D = null
		var g59_z: float = -6.0 if g59_view == "front" else -4.0
		_stand_at(player, head, Vector3(0.0, fd.y, g59_z), 0)
		if g59_view == "front":
			_look_at_point(player, head, fd.root.to_global(Vector3(0.0, ceil_h - 1.5, -8.8)))
		else:
			g59_cam = Camera3D.new()
			fd.root.add_child(g59_cam)
			g59_cam.position = Vector3(2.8, 2.2, -9.2)                                  # 벽 앞 사람 키 — 천장을 25° 쯤 올려다본다 (천장 가까이 두면 옆으로 누운 화면이 된다)
			g59_cam.look_at(fd.root.to_global(Vector3(0.0, ceil_h - 1.2, -9.4)))
			g59_cam.make_current()
		st.last_seen = Vector3(0.0, fd.y, g59_z)
		st.force_state("chase")
		st.hold = false
		await _drop_watch(st, player, 5, 5, ceili(Tuning.STALKER_GLARE_RISE_S * 60.0))
		st.hold = true
		_flush_burst("92n_stalker_glare" if g59_view == "front" else "92o_stalker_glare_side")
		if g59_cam != null:
			(player.get_node("Head/Camera3D") as Camera3D).make_current()
			g59_cam.queue_free()
	# 4e-1b. 정전 순간 (#58): 놓기 직전 ~ 다시 켜진 뒤를 플레이어 시점 0.05초 간격으로. 캡처 92m
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -4.0))
	st.force_state("wander")
	st.set_ceiling(true)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	st.force_state("chase")
	st.hold = false
	await _drop_watch(st, player, 3, 14, int(Tuning.STALKER_HANG_S * 60.0) - 9)
	_flush_burst("92m_stalker_blackout")
	# 4e-1c. 램프를 꺼 둔 채 떨어지면 (#58): 깜빡임도 다시 켜기도 없다 — 플레이어가 끈 램프는 플레이어 것
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -4.0))
	st.force_state("wander")
	st.set_ceiling(true)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	var bo_lamp0: bool = player.lamp_on
	player.set_lamp(false)
	await _wait(12)
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	st.force_state("chase")
	st.hold = false
	var off_r: Dictionary = await _drop_watch(st, player, 999, 0)
	st.hold = true                                                           # 착지한 자리에 세운다 — 1초 기다리는 동안 쫓아와 잡으면 방이 다시 떠 뒤 검사(4e-2)가 전부 죽는다
	await _wait(60)
	var off_en: float = (player.get_node("Head/Headlamp") as SpotLight3D).light_energy
	_check(int(off_r.land_at) >= 0 and not player.lamp_on and off_en <= 0.01 and off_r.max_en <= 0.01,
		"램프를 꺼 둔 채 낙하: 도중 에너지 최대 %.2f · 착지 1초 뒤 %.2f (≤ 0.01) · lamp_on %s (false 그대로)" % [off_r.max_en, off_en, player.lamp_on])
	# 머리 한 프레임 이동(#57)은 캡처·밝기 샘플이 하나도 없는 이 재생에서 잰다 — 캡처가 GPU 를 기다리는 동안 애니메이션이 밀렸다 한꺼번에
	# 따라잡는 착시(1.26~1.49 m)가 빌드마다 다른 프레임에 새어 나와, 캡처 있는 재생(92f)에서 재면 검사가 흔들렸다. 잡으려는 버그는 놓는 순간(+0)이라 램프와 상관없다
	_check(off_r.jump_max <= STALKER_DROP_JUMP_M,
		"매달림~낙하 머리가 물리 프레임 하나에 움직인 높이 최대 %.2f m (≤ %.1f — 몸이 한 프레임 안 튄다, 캡처 없는 재생) · %s 상태, 놓은 뒤 %+d 프레임 · 애니메이션이 한꺼번에 따라잡은 프레임 %d개 건너뜀" % [off_r.jump_max, STALKER_DROP_JUMP_M, off_r.jump_state, int(off_r.jump_pf) - int(off_r.fall_at), off_r.stalls])
	st.hold = true
	player.set_lamp(bo_lamp0)
	await _wait(12)
	# 4e-2. 천장 추격 속도 (#52): 천장에서 쫓을 때는 바닥 추격과 같은 6.5 m/s 로 기어 온다.
	#       ① 추격 1초 이동 = STALKER_CEIL_CHASE_SPEED ±20 % ② 달려 도망치는 플레이어와 벌어지는 속도 ≤ CEIL_CHASE_GAIN_M
	#       ③ 플레이어가 멈추면 4초 안에 떨어진다. 캡처 92j = 머리 위로 따라붙어 떨어지는 5장.
	#       사보타주 = _speed() 를 옛 코드(천장이면 늘 STALKER_CEIL_SPEED 2.5)로 되돌리면 ①②가 FAIL 한다.
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -21.0), Vector3(0.0, 0.0, -11.0))             # 곧은 복도 안쪽 끝. 플레이어와 10 m — 낙하 문턱(7.5) 밖
	st.force_state("wander")
	st.set_ceiling(true)
	_stand_at(player, head, Vector3(0.0, fd.y, -11.0), 2)                    # 괴물에게 등을 보이고 정거장 쪽(+Z)으로 달린다
	var cc_lamp0: bool = player.lamp_on                                      # 램프 상태를 기억해 둔다 — 뒤 캡처(92e·92g)가 이 밝기로 찍힌다
	if not player.lamp_on:
		await _tap(KEY_F)                                                    # 램프가 켜져 있어야 천장의 눈이 계속 본다 (눈 사거리 12 m)
	player.stamina = Tuning.STAMINA_MAX
	st.last_seen = player.global_position
	st.force_state("chase")
	st.hold = false
	var cc_p0: Vector3 = st.position
	var cc_run0: Vector3 = player.global_position
	var cc_gap0: float = Vector2(st.global_position.x - player.global_position.x, st.global_position.z - player.global_position.z).length()
	_inject_key(KEY_SHIFT, true)
	_inject_key(KEY_W, true)
	await _wait(60)
	var cc_1s: float = Vector2(st.position.x - cc_p0.x, st.position.z - cc_p0.z).length()
	await _wait(30)
	var cc_gap1: float = Vector2(st.global_position.x - player.global_position.x, st.global_position.z - player.global_position.z).length()
	var cc_ran: float = Vector2(player.global_position.x - cc_run0.x, player.global_position.z - cc_run0.z).length()
	_inject_key(KEY_W, false)
	_inject_key(KEY_SHIFT, false)
	var cc_gain: float = (cc_gap1 - cc_gap0) / 1.5
	_check(absf(cc_1s - Tuning.STALKER_CEIL_CHASE_SPEED) <= Tuning.STALKER_CEIL_CHASE_SPEED * 0.2 and st.on_ceiling,
		"천장 추격 1초 %.2f m = %.1f ±20 %% (배회 천장 속도는 %.1f 그대로) · 아직 천장 %s" % [cc_1s, Tuning.STALKER_CEIL_CHASE_SPEED, Tuning.STALKER_CEIL_SPEED, st.on_ceiling])
	_check(cc_ran >= 8.0 and cc_gain <= CEIL_CHASE_GAIN_M,
		"달려 도망치는 1.5초: 플레이어 %.1f m 달림(≥ 8) · 거리 %.1f → %.1f m, 초당 %+.2f m 벌어짐 (≤ %.1f. 옛 천장 속도 2.5 면 +4.5)" % [cc_ran, cc_gap0, cc_gap1, cc_gain, CEIL_CHASE_GAIN_M])
	var cc_fall := -1
	for k in 240:
		if k % 8 == 0 and k <= 32:
			_look_at_point(player, head, st.global_position)                 # 멈춰서 머리 위를 올려다본다
			await _grab()
		else:
			await _wait(1)
		if cc_fall < 0 and st.state in ["hang", "fall", "land"]:              # #57 떨어지기로 한 순간 = 매달림 시작
			cc_fall = k
		if cc_fall >= 0 and k - cc_fall > 20:
			break
	_flush_burst("92j_stalker_ceil_chase")
	head.rotation.x = 0.0
	_check(cc_fall >= 0 and cc_fall <= 240,
		"멈추자 %.2f초에 떨어짐 (≤ 4.0 — 따라붙어 %.1f m 안으로 들어왔다)" % [float(cc_fall) / 60.0, Tuning.STALKER_FALL_TRIGGER_M])
	if player.lamp_on != cc_lamp0:
		await _tap(KEY_F)                                                    # 램프를 원래 상태로 — 안 되돌리면 뒤 캡처(92e 벽타기·92g 내려오기)가 어둡게 찍힌다
	# 4f. 벽타기 (#49): 바닥에서 벽·아치를 기어 천장까지. 몸 중심이 보이는 벽면에 붙어 있나 · 손이 벽 밖으로 안 나가나 ·
	#     면 법선이 한 프레임에 30° 넘게 안 튀나 · 클립이 crawl 인가(사람 사다리 동작 climb_up 은 안 쓴다)
	st.hold = false
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -4.0))
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)                      # 눈 밖으로 — 타는 동안 쫓지 않게
	var cell_x: float = MineAssembler.cell_world(MineAssembler.cell_of(st.position)).x
	var climbed: bool = st.climb_to_ceiling()
	var climb_clip: String = st.body.current_clip()
	var wall_x: float = st.position.x
	_stand_at(player, head, Vector3(-signf(st.position.x) * 2.0, fd.y, st.position.z + 5.0), 0)   # 반대쪽 벽 5 m 뒤에서 옆으로 겨냥해 본다 (오르는 동안은 감각이 안 돈다)
	var climb_at := -1
	var wall_gap_min := 99.0
	var wall_gap_max := -99.0
	var wall_hand := INF
	var turn_max := 0.0
	var nrm_prev: Vector3 = st.body.surface_normal
	for k in 600:
		await _wait(1)
		if k % 90 == 0 and k <= 360:
			_look_at_point(player, head, st.global_position)
			await _grab()
		if st.state == "climb":
			if st.position.y >= Tuning.STALKER_WALL_LAND_OFF + 0.1 and st.position.y <= Tuning.TUNNEL_ARCH_Y:   # 곧은 벽 구간에서만 (밑동은 바닥 자리에서 벽으로 누워든다, 아치는 면이 휜다)
				var gap: float = Tuning.TUNNEL_WALL_X - absf(st.position.x - cell_x)
				wall_gap_min = minf(wall_gap_min, gap)
				wall_gap_max = maxf(wall_gap_max, gap)
			wall_hand = minf(wall_hand, st.body.hand_clear_drawn())
			turn_max = maxf(turn_max, rad_to_deg(nrm_prev.angle_to(st.body.surface_normal)))
		nrm_prev = st.body.surface_normal
		if st.on_ceiling:
			climb_at = k
			break
	_flush_burst("92e_stalker_climb")
	head.rotation.x = 0.0
	_check(climbed and climb_at >= 0 and climb_clip == "crawl",
		"벽타기: %.2f초에 천장 도달 · 클립 %s (crawl 이어야 한다 — 사람 사다리 동작은 안 쓴다)" % [float(climb_at) / 60.0, climb_clip])
	_check(wall_gap_min >= 0.0 and wall_gap_max <= WALL_GAP_MAX_M,
		"벽 자리: 몸 중심이 벽면에서 %.3f ~ %.3f m (0 ~ %.2f). 옛 값 0.7 은 충돌 상자 기준이라 보이는 벽 밖 허공이었다" % [wall_gap_min, wall_gap_max, WALL_GAP_MAX_M])
	_check(wall_hand >= -STALKER_HAND_SINK_M and turn_max <= SURF_TURN_MAX_DEG,
		"벽 손 접지 %+.3f m (≥ %.2f) · 면 법선 한 프레임 최대 %.1f° (≤ %.0f, 아치 전환)" % [wall_hand, -STALKER_HAND_SINK_M, turn_max, SURF_TURN_MAX_DEG])
	# 4g. 내려오기 (#49): 천장에서 벽을 타고 **머리부터** 내려온다. 캡처 92g
	st.hold = true
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)                      # 눈 밖으로 — 가까이 있으면 내려오는 대신 떨어진다
	st.climb_down_to_floor()
	await _wait(10)
	var down_clip: String = st.body.current_clip()
	_stand_at(player, head, Vector3(-signf(st.position.x) * 2.0, fd.y, st.position.z + 5.0), 0)
	var down_at := -1
	var head_up := 0                                                         # 머리가 엉덩이보다 위였던 프레임 (0 이어야 머리부터)
	for k in 600:
		await _wait(1)
		if k % 90 == 0 and k <= 360:
			_look_at_point(player, head, st.global_position)
			await _grab()
		if st.state == "climb" and st.position.y > 1.0 and st.body.head_y() > st.body.hip_y():
			head_up += 1
		if not st.on_ceiling and st.position.y <= 0.05 and st.state != "climb":
			down_at = k
			break
	var land_cell_x: float = MineAssembler.cell_world(MineAssembler.cell_of(st.position)).x
	var land_gap: float = WALL_COLLIDER_X - (absf(st.position.x - land_cell_x) + Tuning.STALKER_R)   # 몸 바깥 끝과 벽 충돌체 사이
	st.hold = false
	var land_p0: Vector3 = st.position
	var land_low: float = st.position.y
	for k in 120:                                                            # 내려선 자리 그대로 두고 2초 — 걷는지, 바닥을 뚫는지
		await _wait(1)
		land_low = minf(land_low, st.position.y)
		if k == 5:
			_look_at_point(player, head, st.global_position)
			await _grab()
		elif k == 8:
			_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)              # 눈 밖으로 — 5 m 앞에 두면 쫓아와 잡고 방이 다시 떠 뒤 검사가 전부 죽는다
	_flush_burst("92g_stalker_walldown")
	head.rotation.x = 0.0
	var land_moved: float = Vector2(st.position.x - land_p0.x, st.position.z - land_p0.z).length()
	var land_up_deg: float = rad_to_deg(st.body.global_transform.basis.y.angle_to(Vector3.UP))
	_check(down_at >= 0 and down_clip == "crawl" and head_up == 0,
		"내려오기: %.2f초에 바닥 (클립 %s) · 머리가 엉덩이보다 위였던 프레임 %d (0 = 머리부터)" % [float(down_at) / 60.0, down_clip, head_up])
	_check(land_gap >= WALL_LAND_CLEAR_M and land_moved >= WALL_LAND_WALK_M and land_low >= STALKER_SINK_Y and land_up_deg <= BODY_UP_MAX_DEG,
		"내려선 자리: 몸과 벽 충돌체 사이 %.2f m (≥ %.2f) · 2초 동안 %.2f m 걸음 (≥ %.1f, 안 갇혔다) · 바닥 밑 최저 %+.3f m (≥ %.2f) · 몸이 선 각 %.1f° (≤ %.0f, 벽 자세가 안 남았다)" % [land_gap, WALL_LAND_CLEAR_M, land_moved, WALL_LAND_WALK_M, land_low, STALKER_SINK_Y, land_up_deg, BODY_UP_MAX_DEG])
	# 4g-2. 직선이 아닌 칸에서도 벽타기 (#51): T·끝막이 칸에서 벽을 찾아 천장까지 오른다.
	#       옆벽이 정말 칸 가운데에서 TUNNEL_WALL_X(3.16) 인지 여기서 잰다 — 조립기 갱목 기둥 안쪽면 값이다.
	#       사보타주 = Tuning.STALKER_WALL_PIECES 를 ["straight"] 로 되돌리면 둘 다 "벽 못 찾음" 으로 FAIL 한다.
	st.hold = false
	st.set_ceiling(false)
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)                      # 정거장 앞 — T·끝막이 칸에서 멀어 쫓지 않는다
	for pname in ["t", "cap"]:
		var w51_cell := Vector2i(-1, -1)
		for c in fd.pieces:
			if fd.pieces[c]["name"] == pname:
				w51_cell = c
				break
		if w51_cell.x < 0:
			_check(false, "%s 칸이 층에 없다 — 벽타기를 못 잰다" % pname)
			continue
		var w51_at: Vector3 = MineAssembler.cell_world(w51_cell)
		st.place(w51_at, w51_at + Vector3(0.0, 0.0, -4.0))
		st.force_state("wander")
		await _wait(4)
		var w51_up: bool = st.climb_to_ceiling()
		var w51_clip: String = st.body.current_clip() if w51_up else ""
		var w51_gap_min := 99.0
		var w51_gap_max := -99.0
		var w51_ceil := -1
		for k in 900:
			await _wait(1)
			if st.state == "climb" and st.position.y >= Tuning.STALKER_WALL_LAND_OFF + 0.1 and st.position.y <= Tuning.TUNNEL_ARCH_Y:
				var ctr: Vector3 = st._cl["center"]                              # 붙은 벽의 축·칸 가운데 (직선이면 x, 옆으로 난 칸이면 z 일 수 있다)
				var off: float = (st.position.x - ctr.x) if int(st._cl["axis"]) == 0 else (st.position.z - ctr.z)
				w51_gap_min = minf(w51_gap_min, Tuning.TUNNEL_WALL_X - absf(off))
				w51_gap_max = maxf(w51_gap_max, Tuning.TUNNEL_WALL_X - absf(off))
			if st.on_ceiling:
				w51_ceil = k
				break
		_check(w51_up and w51_ceil >= 0 and w51_clip == "crawl" and w51_gap_min >= 0.0 and w51_gap_max <= WALL_GAP_MAX_M,
			"%s 칸(%d,%d) 벽타기: 벽 찾음 %s · %.2f초에 천장 %.2f m · 클립 %s · 몸 중심이 벽면에서 %.3f ~ %.3f m (0 ~ %.2f)" % [
				pname, w51_cell.x, w51_cell.y, w51_up, float(w51_ceil) / 60.0, st.ceiling_y(st.position), w51_clip, w51_gap_min, w51_gap_max, WALL_GAP_MAX_M])
		st.set_ceiling(false)
	# 4h. 천장/바닥 번갈기 (#49): 감독을 켠 채 조용히 120초 — 천장 체류 25~60 %, 오르내림 2회 이상.
	#     Engine.time_scale 4배로 돌려 실제로는 30초. #59: 60초는 배회 난수 순서에 따라 20~28 % 로 흔들려(앞 구간 하나 늘자 FAIL) 두 배로 늘렸다. 램프는 꺼 두고 소음도 안 낸다(조용한 상태를 재는 것이다).
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)
	if player.lamp_on:
		await _tap(KEY_F)                                                    # 램프부터 끔다 — 켜져 있으면 빛 감각이 바로 조사를 부른다 (30 m)
	await _wait(4)
	st.hold = false
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -4.0))
	st.force_state("wander")
	dr.paused = false
	dr._surf_left = Tuning.STALKER_FLOOR_DWELL_S                             # 시계를 바닥 기준으로 맞추고 시작한다 (앞 검사에서 남은 값 무시)
	Engine.time_scale = 4.0
	var ceil_frames := 0
	var climb_frames := 0
	var wander_frames := 0
	var climbs := 0
	var was_climb := false
	var sink_low := 0.0
	var pose_bad := 0.0
	var climb_run := 0
	var climb_run_max := 0
	var want_frames := 0
	var straight_frames := 0                                                 # 벽이 있는 칸에 있으면서도 못 올라간 프레임 (#51)
	for k in QUIET_FRAMES:
		await _wait(1)
		dr.pressure = maxf(dr.pressure, Tuning.PRESSURE_SEND)
		if st.state == "climb":
			climb_frames += 1
			climb_run += 1
			climb_run_max = maxi(climb_run_max, climb_run)
		elif st.state == "wander":
			climb_run = 0
			wander_frames += 1
			if not st.on_ceiling and dr._surf_left <= 0.0:
				want_frames += 1
				var cc := MineAssembler.cell_of(st.position)
				straight_frames += 0 if st._wall_of(st.position).is_empty() else 1                                      # 벽이 있는데도 못 올라간 시간 (#51. 벽 판정 자체가 막는지 가른다)
		sink_low = minf(sink_low, st.position.y)
		if st.state != "climb":                                              # 벽에서 벗어나 있는 동안 몸이 면(바닥 위 / 천장 아래)을 향하나
			pose_bad = maxf(pose_bad, rad_to_deg(st.body.global_transform.basis.y.angle_to(Vector3.DOWN if st.on_ceiling else Vector3.UP)))
		if st.on_ceiling:
			ceil_frames += 1
		if st.state == "climb" and not was_climb:
			climbs += 1
		was_climb = st.state == "climb"
	Engine.time_scale = 1.0
	dr.paused = true
	var ceil_pct: float = 100.0 * float(ceil_frames) / float(QUIET_FRAMES)
	_check(climb_run_max <= CLIMB_STUCK_FRAMES,
		"한 번 벽에 붙어 있던 최대 시간 %.1f 초 (≤ %.0f — 넘으면 벽타기에 갇힌 것)" % [climb_run_max / 15.0, CLIMB_STUCK_FRAMES / 15.0])
	_check(sink_low >= STALKER_SINK_Y and pose_bad <= BODY_UP_MAX_DEG,
		"번갈기 120초 내내 바닥 밑 최저 %+.3f m (≥ %.2f — 바닥을 안 뚫는다) · 벽 밖에서 몸이 면과 어긋난 최대 각 %.1f° (≤ %.0f)" % [sink_low, STALKER_SINK_Y, pose_bad, BODY_UP_MAX_DEG])
	_check(ceil_pct >= CEIL_DWELL_PCT[0] and ceil_pct <= CEIL_DWELL_PCT[1] and climbs >= 2,
		"조용한 120초: 천장 체류 %.0f %% (%.0f~%.0f) · 오르내림 %d회 (≥ 2) · 배회 %.0f s · 벽 %.0f s · 올라가려는데 못 간 시간 %.0f s (그 중 탈 벽이 있던 %.0f s)" % [ceil_pct, CEIL_DWELL_PCT[0], CEIL_DWELL_PCT[1], climbs, wander_frames / 15.0, climb_frames / 15.0, want_frames / 15.0, straight_frames / 15.0])
	# 4i-2. 빛으로 알아챈 천장의 괴물은 내려오지 않고 천장으로 다가온다 (#53).
	#       램프 켠 플레이어를 15 m(눈 사거리 12 밖 · 빛 감각 30 안) 앞에 두면 조사로 바뀌고, 벽으로 내려오지 않고 천장을 기어 온다.
	#       ① 1초 안에 investigate + 내려온 프레임 0 ② 천장 조사 속도 = STALKER_CEIL_INV_SPEED ±20 % ③ 5초 안에 추격 → 낙하.
	#       사보타주 = investigate() 의 `and not curious` 를 지우면 ①이 FAIL 한다(옛 동작 = 곧바로 벽으로 내려옴).
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -24.5), Vector3(0.0, 0.0, -4.0))              # 20.5 m — 천장 조사 구간을 길게 재려고 복도 안쪽 끝에 둔다
	st.force_state("wander")
	st.set_ceiling(true)
	_stand_at(player, head, Vector3(0.0, fd.y, -4.0), 0)
	var ci_lamp0: bool = player.lamp_on
	if not player.lamp_on:
		await _tap(KEY_F)                                                    # 램프를 켠다 — 빛 감각(30 m)이 도는 조건이다
	head.rotation.x = deg_to_rad(18.0)                                       # 천장을 올려다본다
	st.hold = false
	var ci_inv := -1
	var ci_down := 0
	var ci_chase := -1
	var ci_fall := -1
	var ci_moved := 0.0
	var ci_frames := 0
	var ci_gap_chase := -1.0
	var ci_prev: Vector3 = st.position
	for k in 480:
		if k % 30 == 0 and k >= 60 and k <= 180:                              # 20 m 밖은 램프가 안 닿아 검게 찍힌다 — 1~3초(다가온 뒤 ~ 낙하)를 5장에 담는다
			_look_at_point(player, head, st.global_position)
			await _grab()
		else:
			await _wait(1)
		if st.state == "investigate":
			if ci_inv < 0:
				ci_inv = k
			if st.on_ceiling:                                                # 천장 조사 속도는 천장에 붙어 있는 프레임만 센다
				ci_moved += Vector2(st.position.x - ci_prev.x, st.position.z - ci_prev.z).length()
				ci_frames += 1
			else:
				ci_down += 1
		if ci_inv >= 0 and ci_chase < 0 and st.state == "climb":
			ci_down += 1                                                     # 조사로 바뀐 뒤 벽에 붙었다 = 옛 동작(내려옴)
		if ci_chase < 0 and st.state == "chase":
			ci_chase = k
			ci_gap_chase = Vector2(st.global_position.x - player.global_position.x, st.global_position.z - player.global_position.z).length()
		if ci_fall < 0 and st.state in ["hang", "fall", "land"]:              # #57 떨어지기로 한 순간 = 매달림 시작
			ci_fall = k
		ci_prev = st.position
		if ci_fall >= 0 and k - ci_fall > 20:
			break
	st.hold = true                                                           # 착지한 자리에서 멈춰 세운다 — 안 세우면 서 있는 플레이어를 잡아 방이 다시 뜨고 뒤 검사가 전부 죽는다
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)
	_flush_burst("92k_stalker_ceil_come")
	head.rotation.x = 0.0
	var ci_speed: float = (ci_moved / float(ci_frames)) * 60.0 if ci_frames > 0 else 0.0
	_check(ci_inv >= 0 and ci_inv <= 60 and ci_down == 0,
		"빛 감각 → %d프레임에 조사 · 조사 뒤 벽·바닥으로 내려온 프레임 %d (0 이어야 한다 — 천장으로 다가온다)" % [ci_inv, ci_down])
	_check(ci_frames >= 20 and absf(ci_speed - Tuning.STALKER_CEIL_INV_SPEED) <= Tuning.STALKER_CEIL_INV_SPEED * 0.2,
		"천장 조사 속도 %.2f m/s = %.1f ±20 %% (천장에 붙어 조사한 %.2f초 동안 %.1f m)" % [ci_speed, Tuning.STALKER_CEIL_INV_SPEED, ci_frames / 60.0, ci_moved])
	_check(ci_chase >= 0 and ci_fall > ci_chase and ci_fall <= 300,
		"%.2f초에 추격으로(거리 %.1f m ≤ 눈 12) → %.2f초에 낙하 (≤ 5.0)" % [float(ci_chase) / 60.0, ci_gap_chase, float(ci_fall) / 60.0])
	if player.lamp_on != ci_lamp0:
		await _tap(KEY_F)                                                    # 램프를 원래 상태로 — 뒤 검사(소음 조사)는 빛 감각이 안 도는 것을 전제한다
	# 4i. 소음 → 3초 안에 내려오기 시작 (조사·수색은 바닥에서 한다)
	st.hold = true
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -4.0))
	st.force_state("wander")
	st.set_ceiling(true)
	st.hold = false
	await _wait(10)
	NoiseBus.make(Vector3(0.0, fd.y, -21.0), Tuning.NOISE_PICK, "pick", player)
	var down_start := -1
	for k in NOISE_DOWN_FRAMES + 60:
		await _wait(1)
		if st.state == "climb" or not st.on_ceiling:
			down_start = k
			break
	var inv_at := -1
	for k in 900:                                                            # 벽 6.6초 + 여유 — 내려와서 조사까지 가야 한다 (climb 에 갇히면 여기서 걸린다)
		await _wait(1)
		if st.position.y <= 0.05 and not st.on_ceiling and (st.state == "investigate" or st.state == "search"):
			inv_at = k
			break
	_check(down_start >= 0 and down_start <= NOISE_DOWN_FRAMES and inv_at >= 0,
		"천장에서 소음 → %d프레임에 내려오기 시작 (≤ %d = 3초) → %.1f초에 바닥에서 조사 (상태 %s, y %.2f)" % [down_start, NOISE_DOWN_FRAMES, float(inv_at) / 60.0, st.state, st.position.y])
	st.set_ceiling(false)
	st.hold = false
	st.place(Vector3(0.0, 0.0, -12.0), Vector3(0.0, 0.0, -4.0))              # 바닥으로 되돌린다 — 뒤 검사(놓침)가 이어서 쓴다
	st.last_seen = Vector3(0.0, fd.y, -4.0)
	st.force_state("chase")                                                  # 6번(놓침)이 이어서 쓴다 — 플레이어는 바로 정거장으로 빠진다
	st._lose_left = Tuning.STALKER_LOSE_S                                    # 강제 추격은 놓침 시계를 안 감는다
	# 6. 놓침: 정거장으로 빼면(눈 밖) 3초 뒤 마지막 자리 조사
	_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)
	var lost_at := -1
	for k in int(Tuning.STALKER_LOSE_S * 60.0) + 60:
		await _wait(1)
		if st.state == "investigate":
			lost_at = k
			break
	_check(lost_at >= int(Tuning.STALKER_LOSE_S * 60.0) - 10 and lost_at >= 0, "놓치고 %d프레임 뒤 마지막 자리 조사 (≈ %.0f s)" % [lost_at, Tuning.STALKER_LOSE_S])
	# 7. 광차 숨기: 정차 광차에 숙여 타고 수색 5초 → 들킴 0. 카드(광차 2) → 광차 옆 2초 → 들킴 → 추격. 캡처 94
	var cart: PathFollow3D = fd.carts[0] if not fd.carts.is_empty() else null
	if cart != null:
		cart.start(0.0)
		cart._stop_left = 40.0                                                 # 봇: 시험 동안 서 있게 (정차 6초를 늘린다)
		for other in fd.carts:                                                 # 다른 광차는 반 바퀴 건너에 세운다 — 정거장에 같이 서 있으면 E 로 내리는 순간 그 광차가 다시 태운다 (#39 에서 걸림: 앞 구간이 길어지면 광차 위상이 밀린다)
			if other != cart:
				other.start(other._length * 0.5)
				other._stop_left = 40.0
		var start: Vector3 = MineAssembler.cell_world(fd.ring[0], fd.y)
		var nxt: Vector2i = fd.ring[1]
		var dir: Vector3 = Vector3(nxt.x - fd.ring[0].x, 0.0, nxt.y - fd.ring[0].y)
		var right: Vector3 = dir.cross(Vector3.UP)
		_stand_at(player, head, start + right * (Tuning.CART_OFF_SIDE + 0.4), 0)
		await _wait(20)
		await _tap(KEY_E)
		await _wait(10)
		_inject_key(KEY_CTRL, true)
		await _wait(15)
		_check(player.ride == cart and player.is_hidden(), "광차에 숙여 탐 → 숨음 (ride %s, hidden %s)" % [player.ride != null, player.is_hidden()])
		var near: Dictionary = MineAssembler.grid_dist(fd, fd.ring[0], 2)
		var from_cell: Vector2i = fd.ring[0]
		for c in near.keys():
			if near[c] == 2:
				from_cell = c
				break
		st.place(MineAssembler.cell_world(from_cell), start - Vector3(0.0, fd.y, 0.0))
		st.found_count = 0
		st.force_state("search")
		await _wait(300)
		_check(st.found_count == 0 and st.state != "chase" and not dr.card_cart, "카드 전 수색 5초 → 들킴 0 (상태 %s)" % st.state)
		dr.cart_habit = Tuning.CARD_CART_N
		dr.apply_cards()
		st.place(MineAssembler.cell_world(from_cell), start - Vector3(0.0, fd.y, 0.0))
		st.force_state("search")
		var peeked := false
		var found_at := -1
		for k in 600:
			await _wait(1)
			if not peeked and st.state == "search" and st.global_position.distance_to(cart.global_position) <= 3.0 and st._dwell_left > 0.0:
				peeked = true
				var to_st: Vector3 = st.global_position - player.global_position   # 짐칸 안에서 괴물 쪽을 올려본다 — 테두리 위로 머리·어깨가 보인다
				player.rotation.y = atan2(-to_st.x, -to_st.z)
				head.rotation.x = deg_to_rad(25.0)
				await _wait(2)
				await _shot("94_cart_peek")
			if st.found_count >= 1:
				found_at = k
				break
		var alert_state: String = st.state
		_inject_key(KEY_CTRL, false)                                            # 들켰다 — 포효(STALKER_ALERT_S) 안에 내려서 달아난다. 잡히면 방이 다시 떠 뒤 검사가 전부 죽는다
		await _tap(KEY_E)
		await _wait(2)
		_stand_at(player, head, Vector3(0.0, fd.y, 8.0), 0)
		await _wait(int((Tuning.STALKER_ALERT_S + Tuning.STALKER_DROP_S) * 60.0) + 10)   # 포효 + 엎드리기 (#47)
		_check(dr.card_cart and st.peek_carts and peeked and found_at >= 0 and alert_state == "alert" and st.state == "chase" and not player.dead,
			"카드 광차 들여다보기 → 광차 옆 멈춤(%s) → %d프레임에 들킴 → 포효(%s) → 추격(%s), 살아 있음 %s [ride %s, 플레이어 %s, 괴물 %s, 램프 %s]" % [peeked, found_at, alert_state, st.state, not player.dead, player.ride != null, player.global_position, st.global_position, player.lamp_on])
		cart._stop_left = 0.1
	else:
		_check(false, "광차 있음")
	# 8. 램프 카드: 반경 6 소음을 8 m 밖에서 → 카드 전 안 들림 / 카드(램프 3) 후 들림(6 × 1.5 = 9 ≥ 8)
	dr.lamp_habit = 0
	dr.cart_habit = 0
	dr.card_dark = false
	dr.card_cart = false
	dr.apply_cards()
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	if player.lamp_on:
		await _tap(KEY_F)
		await _wait(12)                                                        # lamp_on 이 다음 물리 프레임에 꺼진다 — 켜진 채 되돌리면 눈이 바로 추격
	st.force_state("wander")
	st.hold = true
	st.place(Vector3(0.0, 0.0, -12.5 - STALKER_NEAR_M), Vector3(0.0, 0.0, -12.5))
	await _wait(10)
	NoiseBus.make(player.global_position, Tuning.NOISE_STEP, "step", player)
	await _wait(10)
	var deaf: bool = st.state == "wander"
	dr.lamp_habit = Tuning.CARD_LAMP_N
	dr.apply_cards()
	NoiseBus.make(player.global_position, Tuning.NOISE_STEP, "step", player)
	await _wait(2)
	_check(deaf and dr.card_dark and is_equal_approx(st.ear_mul, Tuning.CARD_EAR_MUL) and st.state == "investigate", "반경 6 소음 8 m 밖: 카드 전 안 들림(%s) · 카드 어둠 수색(귀 ×%.1f) 뒤 조사(%s)" % [deaf, st.ear_mul, st.state])
	dr.lamp_habit = 0
	dr.card_dark = false
	dr.apply_cards()
	# 9. 철수 (#50): 압박 25 + 괴물 8 m 안 → −5/s → 20 에서 철수 → **벽을 타고 천장으로 올라가** 시야 밖에서 사라진다. 캡처 92h
	st.hold = false
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -20.0))              # 플레이어에게 등을 보인다 — 눈에 띄면 철수 대신 추격이다
	_stand_at(player, head, Vector3(0.0, fd.y, -5.0), 0)                      # 7.5 m 뒤에서 등을 본다 (도망쳤다가 뒤돌아본 시점)
	if player.lamp_on:
		await _tap(KEY_F)                                                    # 램프를 끈다 — 켜 두면 빛 감각(30 m)이 조사를 불러 철수 대신 다가온다
	st.force_state("wander")
	dr.pressure = 25.0
	dr.paused = false
	var retreat_at := -1
	for k in 180:
		await _wait(1)
		if st.state == "retreat" or st.state == "climb" or st.state == "hidden":
			retreat_at = k
			break
	_check(retreat_at >= 0, "압박 25, 8 m 안 → %d프레임에 철수 시작 (≤ 180. 지금 압박 %.1f, 거리 %.1f, 상태 %s, paused %s)" % [retreat_at, dr.pressure, st.global_position.distance_to(player.global_position), st.state, dr.paused])
	await _tap(KEY_F)                                                        # 철수가 시작된 뒤엔 램프를 켜도 안전하다 (retreat·climb 는 감각을 안 본다) — 캡처를 위해
	var hid_at := -1
	var saw_climb: bool = st.state == "climb"
	var saw_ceiling: bool = st.on_ceiling
	for k in STALKER_HIDE_WAIT:
		if st.state == "hidden":
			hid_at = k
			break
		if st.state == "climb":
			saw_climb = true
		if st.on_ceiling:
			saw_ceiling = true
		if k % 90 == 0 and k <= 360:
			_look_at_point(player, head, st.global_position)
			await _grab()
		else:
			await _wait(1)
	_flush_burst("92h_stalker_retreat_up")
	head.rotation.x = 0.0
	_check(hid_at >= 0 and not st.visible and saw_climb and saw_ceiling,
		"철수: 벽타기 %s → 천장 %s → %.1f 초 뒤 숨김 (한도 %.0f s)" % [saw_climb, saw_ceiling, hid_at / 60.0, STALKER_HIDE_WAIT / 60.0])
	if player.lamp_on:
		await _tap(KEY_F)                                                    # 뒤 검사(스턴)는 램프 끈 상태를 전제한다 — 캡처 때문에 켠 것을 되돌린다
	dr.paused = true
	# 9b. 철수는 끊겨도 끝난다 (#54): 천장으로 물러나던 길이 끊겨 벽에서 내려오면, 배회로 돌아가지 않고 걸어서 마저 물러나 사라진다.
	#     F5 영상(Bug2.mp4) 재현 — 압박 0(플레이어가 6 m 옆) + 천장 철수가 중간에 끊김.
	#     끊김은 `climb_down_to_floor()` 로 직접 만든다 — 게임에서는 천장 낮은 칸(곡선 2.71 · 목 3.08)을 만났을 때 _move 가 같은 것을 부른다.
	#     사보타주 = _resume_after_climb 의 철수 이어가기를 지우면, 내려서자마자 감독이 같은 자리에서 다시 벽을 태운다(벽타기 ≥ 1회로 FAIL).
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -6.5))
	_stand_at(player, head, Vector3(0.0, fd.y, -6.5), 2)                     # 6 m 옆에서 본다 — 15 m 안이라 압박이 계속 0 이다
	var rl_lamp0: bool = player.lamp_on
	player.set_lamp(false)                                                   # 램프가 켜져 있으면 추격이 되어 철수를 못 잰다
	st.force_state("wander")
	st.hold = false
	dr.paused = false
	var rl_up := -1
	for k in 900:                                                            # 압박 0 → 감독이 철수를 부른다 → 벽을 타고 천장으로
		await _wait(1)
		dr.pressure = 0.0
		if st.on_ceiling:
			rl_up = k
			break
	st.climb_down_to_floor()                                                 # 여기서 천장 길이 끊긴다
	var rl_land := -1
	var rl_climb_f := 0                                                      # 끊은 뒤 벽에 붙어 있던 프레임 — 내려오는 6.6초면 충분하다. 더 길면 다시 타고 올라간 것이다
	var rl_hid := -1
	for k in 1800:                                                           # 30초 — 벽 6.6 + 걸어서 물러나기
		await _wait(1)
		dr.pressure = 0.0
		if st.state == "climb":
			rl_climb_f += 1
		if rl_land < 0 and st.state != "climb" and not st.on_ceiling and st.position.y <= 0.05:
			rl_land = k
		if st.state == "hidden":
			rl_hid = k
			break
	dr.paused = true
	player.set_lamp(rl_lamp0)
	_check(rl_up >= 0 and rl_land >= 0 and rl_climb_f <= RETREAT_CLIMB_FRAMES and rl_hid >= 0,
		"압박 0 · 플레이어 6 m: %.1f초에 천장 도달 → 천장 길 끊음 → 바닥에 내려선 시각 %s → 그 뒤 벽에 붙어 있던 %.1f초 (≤ %.0f = 내려오는 시간 + 여유. 넘으면 또 타고 올라간 것) → 사라짐 %s" % [
			float(rl_up) / 60.0,
			"%.1f초" % (float(rl_land) / 60.0) if rl_land >= 0 else "못 잡음(내려서자마자 또 벽에 붙었다)",
			rl_climb_f / 60.0, RETREAT_CLIMB_FRAMES / 60.0,
			"%.1f초" % (float(rl_hid) / 60.0) if rl_hid >= 0 else "30초 안에 안 사라짐"])
	# 9c. 철수 벽타기는 소리로 안 뒤집힌다 (#55): 물러나려고 벽을 오르는 중에 발밑에서 곡괭이 소음이 나도 끝까지 올라가 사라진다.
	#     F5 영상(2026-09-13 12-26-13.mp4) 1:03~1:13 벽타기 약 11초 — 오르다 소리에 뒤집혀 내려왔다가 다시 오른 모양이다.
	#     사보타주 = _on_noise 의 `or _retreat_on` 을 지우면 높이가 줄고(뒤집힘) 조사가 끼어들어 벽타기가 8초를 넘는다.
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -12.5), Vector3(0.0, 0.0, -6.5))
	_stand_at(player, head, Vector3(0.0, fd.y, -6.5), 2)
	var rn_lamp0: bool = player.lamp_on
	player.set_lamp(false)
	st.force_state("wander")
	st.hold = false
	dr.paused = false
	var rn_start := -1
	for k in 300:                                                            # 압박 0 → 철수 → 벽을 오르기 시작
		await _wait(1)
		dr.pressure = 0.0
		if st.state == "climb":
			rn_start = k
			break
	var rn_prev_s: float = st._climb_s
	var rn_down := 0                                                         # 천장에 닿기 전에 벽 위 거리(_climb_s)가 줄어든 프레임 = 뒤집힘.
	                                                                         # 높이(y)로 재면 안 된다 — 아치 꼭대기에서 몸이 면에서 0.05 → 0.35 m 떨어지며 y 가 조금 준다(뒤집힘 없이 16프레임)
	var rn_ceil := -1                                                        # 오르기 시작부터 천장까지 프레임
	var rn_inv := 0
	var rn_hid := -1
	for k in 1800:
		await _wait(1)
		dr.pressure = 0.0
		if k == 120:
			NoiseBus.make(Vector3(st.global_position.x, fd.y, st.global_position.z), Tuning.NOISE_PICK, "pick", player)   # 오르기 2초 뒤, 괴물 발밑
		if rn_ceil < 0:
			if st.on_ceiling:
				rn_ceil = k
			elif st.state == "climb" and st._climb_s < rn_prev_s - 0.0001:
				rn_down += 1
		rn_prev_s = st._climb_s
		if st.state == "investigate":
			rn_inv += 1
		if st.state == "hidden":
			rn_hid = k
			break
	dr.paused = true
	player.set_lamp(rn_lamp0)
	_check(rn_start >= 0 and rn_ceil >= 0 and rn_ceil <= RETREAT_CLIMB_UP_FRAMES and rn_down == 0 and rn_inv == 0 and rn_hid >= 0,
		"철수 벽타기 중 발밑 소음: 천장까지 %s (≤ %.0f) · 벽 위 거리가 줄어든 프레임 %d (0 = 안 뒤집힘) · 조사 끼어듦 %d프레임 (0) · 사라짐 %s" % [
			"%.1f초" % (float(rn_ceil) / 60.0) if rn_ceil >= 0 else "못 닿음", RETREAT_CLIMB_UP_FRAMES / 60.0, rn_down, rn_inv,
			"%.1f초" % (float(rn_hid) / 60.0) if rn_hid >= 0 else "30초 안에 안 사라짐"])
	st.hold = true
	st.set_ceiling(false)
	st.place(Vector3(0.0, 0.0, -15.5), Vector3(0.0, 0.0, -12.5))             # 뒤 검사(스턴)가 쓰는 자리로 되돌린다
	# 10. 스턴: 3 m 앞, 램프 끈 채 오른쪽 클릭 → 곡괭이가 맞음 → 1.5초 이동 0, 클립 hit, 곡괭이가 발밑 → 풀리면 수색. 캡처 95
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	player.set_lamp(false)                                                      # 램프 끈 상태를 여기서 못박는다 — 켜져 있으면 스턴이 풀리자마자 눈에 띄어 수색 대신 추격이 된다.
	                                                                            # F 키 주입으로 끄던 것은 프레임에 따라 두 번 먹혀 도로 켜지는 일이 있었다(실측, k=7 에 다시 true)
	st.appear(MineAssembler.cell_of(Vector3(0.0, 0.0, -15.5)), MineAssembler.cell_of(Vector3(0.0, 0.0, -15.5)))
	st.hold = true
	st.place(Vector3(0.0, 0.0, -15.5), Vector3(0.0, 0.0, -12.5))
	head.rotation.x = deg_to_rad(-8.0)
	await _wait(20)
	var sp0: Vector3 = st.global_position
	_inject_button(MOUSE_BUTTON_RIGHT, true)
	await _wait(2)
	_inject_button(MOUSE_BUTTON_RIGHT, false)
	var stun_at := -1
	for k in 40:
		await _wait(1)
		if st.state == "stun":
			stun_at = k
			break
	_check(stun_at >= 0 and st.body.current_clip() == "hit", "오른쪽 클릭 → %d프레임에 곡괭이 맞아 스턴 (클립 %s)" % [stun_at, st.body.current_clip()])
	await _wait(20)
	var still_mid: String = st.state                                            # 0.33 s 뒤에도 스턴이어야 한다 (스턴 0 이면 한 프레임에 풀린다 — hold 라 이동 0 은 증거가 아니다)
	await _shot("95_stun")
	await _wait(int(Tuning.STALKER_STUN_S * 60.0) - 30)
	var still_late: String = st.state                                           # 1.33 s
	var moved_stun: float = st.global_position.distance_to(sp0)
	var thrown := room.find_child("ThrownPick", true, false) as Node3D
	var pick_d: float = thrown.global_position.distance_to(st.global_position) if thrown != null else 99.0
	_check(still_mid == "stun" and still_late == "stun" and moved_stun < 0.05 and pick_d <= 1.5 + Tuning.STALKER_R,
		"스턴 %.1f초: 0.3 s 뒤 %s · 1.3 s 뒤 %s · 이동 %.2f m (< 0.05) · 곡괭이가 발밑 %.2f m" % [Tuning.STALKER_STUN_S, still_mid, still_late, moved_stun, pick_d])
	await _wait(40)
	_check(st.state == "search", "스턴 풀리면 제자리 수색 (상태 %s · 램프 %s · 거리 %.1f m)" % [st.state, player.lamp_on, st.global_position.distance_to(player.global_position)])
	st.hold = false
	if thrown != null:
		_stand_at(player, head, Vector3(thrown.global_position.x, fd.y, thrown.global_position.z + 1.2), 0)
		await _wait(20)
		await _tap(KEY_E)
		await _wait(6)
	_check(player.has_pick, "E → 곡괭이 회수 (has_pick %s)" % player.has_pick)
	st.hide_away()
	_stand_at(player, head, Vector3(0.0, fd.y, -2.0), 0)
	if not player.lamp_on:
		await _tap(KEY_F)
	await _wait(12)
	dr.paused = false


## 잡힘 (#35): 방이 다시 뜨므로 play 의 맨 끝. 1.2 m 앞에서 추격 → 즉시 잡힘 → 시점이 돌아가고 램프가 꺼지고 검은 화면 "잡혔습니다." 돌 0. 캡처 96 연속
func _stalker_catch_run(room: Node3D) -> void:
	var player := room.get_node_or_null("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head") if player != null else null
	var asm := _asm(room)
	if player == null or asm == null or asm.floors.is_empty():
		_check(false, "잡힘 시험: Player · Layers 있음")
		return
	var fd: MineAssembler.FloorData = asm.floors[0]
	var st := fd.stalker as Stalker
	var dr := fd.director as Director
	if st == null or dr == null:
		_check(false, "잡힘 시험: Stalker · Director 있음")
		return
	dr.paused = true
	_stand_at(player, head, Vector3(0.0, fd.y, -12.5), 0)
	if not player.lamp_on:
		await _tap(KEY_F)
	await _wait(20)
	var rocks0: int = _count_rocks(room)
	var lamp := player.get_node_or_null("Head/Headlamp") as SpotLight3D
	st.appear(MineAssembler.cell_of(Vector3(0.0, 0.0, -14.0)), MineAssembler.cell_of(Vector3(0.0, 0.0, -14.0)))
	st.place(Vector3(1.0, 0.0, -13.7), Vector3(0.0, 0.0, -12.5))                 # 1.2 m 앞·오른쪽 — 시점이 돌아가는 게 보인다
	st.last_seen = player.global_position
	st.force_state("chase")
	var yaw0: float = player.rotation.y
	var caught_at := -1
	for k in 30:
		await _wait(1)
		if player.dead:
			caught_at = k
			break
	for k in 5:
		await _grab()
		await _wait(18)
	_flush_burst("96_caught")
	_check(caught_at >= 0 and st.state == "catch" and st.body.current_clip() == "attack_swipe", "1.2 m 앞 추격 → %d프레임에 잡힘 (상태 %s, 클립 %s)" % [caught_at, st.state, st.body.current_clip()])
	_check(player.death_text == Tuning.CAUGHT_TEXT and _count_rocks(room) == rocks0, "글자 '%s' · 떨어지는 돌 %d = %d" % [player.death_text, _count_rocks(room), rocks0])
	_check(absf(angle_difference(yaw0, player.rotation.y)) >= deg_to_rad(20.0), "시점이 괴물 쪽으로 돎 (%.0f°)" % rad_to_deg(absf(angle_difference(yaw0, player.rotation.y))))
	_check(lamp != null and lamp.light_energy <= 0.001, "램프 꺼짐 (energy %.3f)" % (lamp.light_energy if lamp != null else -1.0))


# ---------------- 소음·램프 (#32) ----------------

## 입구(0, −2)에서. 서 있기 1초 → 발걸음 0, W 1초 → ≥ 1·반경 NOISE_STEP. F → 램프 0·끈 직후 어둡다 → 1초마다 4장(적응이 보인다) →
## 4초 뒤 ADAPT_MIN~MAX → F → LAMP_ENERGY·환경광 즉시 평소. 캡처 81_lamp_off_0~4
func _noise_lamp_run(player: CharacterBody3D, head: Node3D) -> void:
	player.global_position = Vector3(0.0, 0.2, -2.0)
	player.rotation.y = 0.0
	head.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	await _wait(20)
	var nz0: int = NoiseBus.total
	await _wait(60)
	var still: int = _noise_kind(NoiseBus.since(nz0), "step").size()
	nz0 = NoiseBus.total
	_inject_key(KEY_W, true)
	await _wait(60)
	_inject_key(KEY_W, false)
	var steps := _noise_kind(NoiseBus.since(nz0), "step")
	_check(still == 0 and Tuning.NOISE_STEP > 0.0 and steps.size() >= 1 and steps.size() <= 4 and steps[0]["radius"] == Tuning.NOISE_STEP,
		"서 있기 1초 발걸음 %d = 0 · 걷기 1초 발걸음 %d (1~4), 반경 %.0f > 0" % [still, steps.size(), Tuning.NOISE_STEP])
	await _wait(30)
	player.global_position = Vector3(0.0, 0.2, -2.0)
	player.rotation.y = 0.0
	head.rotation.x = 0.0
	player.velocity = Vector3.ZERO
	await _wait(20)
	var lamp := player.get_node_or_null("Head/Headlamp") as SpotLight3D
	var lit: float = await _screen_luma()
	var lit_center: float = await _screen_luma_disk(ADAPT_DISK_R, true)
	await _tap(KEY_F)
	await _wait(12)                                                # 트윈 0.15초
	_check(lamp != null and not player.lamp_on and lamp.light_energy <= 0.001, "F → 램프 꺼짐 (energy %.2f, lamp_on %s)" % [lamp.light_energy if lamp != null else -1.0, player.lamp_on])
	var dark0: float = await _screen_luma()
	await _shot("81_lamp_off_0")
	for k in range(1, 5):
		await _wait(60)
		await _shot("81_lamp_off_%d" % k)
	var adapted: float = await _screen_luma()
	var adapted_center: float = await _screen_luma_disk(ADAPT_DISK_R, true)
	var adapted_edge: float = await _screen_luma_disk(ADAPT_DISK_R, false)
	print("ok 밝기 F 전 %.4f (가운데 %.4f) / 끈 직후 %.4f / 4초 뒤 %.4f (가운데 %.4f · 가장자리 %.4f, 환경광 %.3f, 안개 %.3f)" % [lit, lit_center, dark0, adapted, adapted_center, adapted_edge, Atmosphere.ambient(), Atmosphere.fog()])
	# #32 수정: 적응은 가까운 것만 보여야 한다 — 먼 복도(가운데 원)는 램프 켠 것의 절반 밑, 가까운 벽(가장자리)은 보인다
	_check(Tuning.DARK_ADAPT_FOG > Tuning.FOG_DENSITY and is_equal_approx(Atmosphere.fog(), Tuning.DARK_ADAPT_FOG) and adapted_center < lit_center * ADAPT_CENTER_RATIO,
		"적응해도 먼 복도는 램프보다 어둡다 (가운데 %.4f < 켬 %.4f × %.1f, 안개 %.3f)" % [adapted_center, lit_center, ADAPT_CENTER_RATIO, Atmosphere.fog()])
	_check(adapted_edge >= ADAPT_MIN_LUMA and adapted_edge - adapted_center >= ADAPT_NEAR_GAIN,
		"적응하면 가까운 벽은 보인다 (가장자리 %.4f ≥ %.3f, 가운데보다 %.4f ≥ %.3f 밝다)" % [adapted_edge, ADAPT_MIN_LUMA, adapted_edge - adapted_center, ADAPT_NEAR_GAIN])
	_check(dark0 <= LAMP_MAX_DARK, "F 로 끈 직후 어둡다 (밝기 %.4f ≤ %.3f)" % [dark0, LAMP_MAX_DARK])
	# 화면 전체의 하한은 #32 수정으로 가장자리 검사(위)로 옮겼다 — 가운데(먼 복도)는 일부러 어둡다
	_check(Tuning.DARK_ADAPT_AMBIENT >= Tuning.AMBIENT_ENERGY * 2.0 and adapted <= ADAPT_MAX_LUMA and adapted >= dark0 * 1.5,
		"4초 뒤 눈 적응: 밝기 %.4f (≤ %.3f, 끈 직후 %.4f 의 ≥ 1.5배)" % [adapted, ADAPT_MAX_LUMA, dark0])
	await _tap(KEY_F)
	await _wait(12)
	_check(player.lamp_on and lamp != null and is_equal_approx(lamp.light_energy, Tuning.LAMP_ENERGY) and is_equal_approx(Atmosphere.ambient(), Tuning.AMBIENT_ENERGY) and is_equal_approx(Atmosphere.fog(), Tuning.FOG_DENSITY),
		"F → 램프 켜짐 (energy %.2f = %.2f) · 환경광 즉시 평소 %.3f · 안개 %.3f" % [lamp.light_energy if lamp != null else -1.0, Tuning.LAMP_ENERGY, Atmosphere.ambient(), Atmosphere.fog()])


## 평면도. 프로토타입 그림과 같은 색: 레일 갈색 · 횡갱 회색 · 채탄구역 연두 · 기둥 검정 · 방 초록 · 끝막이 남색 · 대피소 보라 · 정거장 보라.
func _draw_map(fd: MineAssembler.FloorData, path: String) -> void:
	var n: int = Tuning.MAP_N
	var px := MAP_PX
	var img := Image.create(n * px, n * px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.09, 0.09, 0.11))
	var fills := {"pillar": Color(0.23, 0.2, 0.2), "room": Color(0.37, 0.55, 0.43), "station": Color(0.47, 0.43, 0.63), "rock": Color(0.2, 0.19, 0.18)}
	for c in fd.kind:
		if fills.has(fd.kind[c]):
			img.fill_rect(Rect2i(c.x * px + 1, c.y * px + 1, px - 2, px - 2), fills[fd.kind[c]])
	var w := int(px * 0.56)
	var a := (px - w) / 2
	for c in fd.open:
		var k: String = fd.kind.get(c, "")
		if k == "room":
			continue
		var col := Color(0.59, 0.59, 0.55)
		if fd.rail.has(c):
			col = Color(0.69, 0.55, 0.34)
		elif k == "block":
			col = Color(0.53, 0.59, 0.53)
		elif k == "cap":
			col = Color(0.27, 0.27, 0.31)
		elif k == "refuge":
			col = Color(0.55, 0.39, 0.55)
		var x0: int = c.x * px
		var y0: int = c.y * px
		img.fill_rect(Rect2i(x0 + a, y0 + a, w, w), col)
		var m: int = fd.open[c]
		if m & 1:
			img.fill_rect(Rect2i(x0 + a, y0, w, a), col)
		if m & 4:
			img.fill_rect(Rect2i(x0 + a, y0 + a + w, w, px - a - w), col)
		if m & 8:
			img.fill_rect(Rect2i(x0, y0 + a, a, w), col)
		if m & 2:
			img.fill_rect(Rect2i(x0 + a + w, y0 + a, px - a - w, w), col)
	img.save_png(path)
	print("ok 평면도 %s (칸 %d)" % [path.get_file(), fd.open.size()])


func _layer_checks(room: Node3D, player: CharacterBody3D) -> void:
	var asm := _asm(room)
	_check(asm != null and asm.floors.size() == Tuning.MAP_FLOORS, "층 %d개 조립 (Layers/MineAssembler)" % Tuning.MAP_FLOORS)
	if asm == null:
		return
	print("ok 조립 시간 %d ms (참고값 — 검사 아님)" % asm.build_ms)
	var spawner := room.get_node_or_null("Pockets")
	var pockets: Array = spawner.pockets() if spawner != null and spawner.has_method("pockets") else []
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var st: Dictionary = fd.stats
		var tag := "층 %d(시드 %d)" % [i, fd.seed]
		_check(st["cells"] == LAYER_CELLS[i], "%s 칸 %d = 실측 %d" % [tag, st["cells"], LAYER_CELLS[i]])
		_check(st["open_holes"] == 0, "%s 안 맞는 면 0 (실제 %d)" % [tag, st["open_holes"]])
		_check(st["reach"], "%s 정거장에서 모든 칸에 닿음 (가장 먼 곳 %.0f m)" % [tag, st["far_m"]])
		_check(st["rail_loops"] >= 1 and st["terms"] >= LAYER_TERMS_MIN and st["rail"] == LAYER_RAIL[i],
			"%s 레일 고리 %d(≥1) · 종점 %d(≥%d) · 레일 칸 %d = 실측 %d" % [tag, st["rail_loops"], st["terms"], LAYER_TERMS_MIN, st["rail"], LAYER_RAIL[i]])
		_check(st["rooms"] >= LAYER_ROOMS_MIN and st["blocks"] == Tuning.BLOCKS and st["refuges"] == Tuning.REFUGES,
			"%s 방 %d(≥%d) · 채탄구역 %d(=%d) · 대피소 %d(=%d)" % [tag, st["rooms"], LAYER_ROOMS_MIN, st["blocks"], Tuning.BLOCKS, st["refuges"], Tuning.REFUGES])
		_check(st["curves"] >= LAYER_CURVES_MIN and st["junctions"] >= LAYER_JUNC_MIN,
			"%s 곡선 %d(≥%d) · 갈림 %d(≥%d) · 고리 %d" % [tag, st["curves"], LAYER_CURVES_MIN, st["junctions"], LAYER_JUNC_MIN, st["loops"]])
		# 정거장 앞 직선: 입구부터 ENTRY_STRAIGHT 칸이 N-S 레일 직선
		var straight_ok := true
		for k in Tuning.ENTRY_STRAIGHT:
			var c := fd.entry + Vector2i(0, -k)
			if fd.open.get(c, 0) != 5 or not fd.rail.has(c):
				straight_ok = false
		_check(straight_ok, "%s 정거장 앞 %d칸 직선 레일" % [tag, Tuning.ENTRY_STRAIGHT])
		# 조각·회전 = 칸의 뚫린 면 (조각 표의 면을 r 만큼 돌린 것이 칸의 면과 같다), 노드 자리·각도도 같다
		var bad := 0
		var checked := 0
		var pieces_n := 0
		var rails_n := 0
		for c in fd.open:
			if fd.station.has(c):
				continue
			if not fd.pieces.has(c) or not fd.pieces[c].has("node"):
				bad += 1
				continue
			var p: Dictionary = fd.pieces[c]
			checked += 1
			var wm := MineAssembler.rotate_mask(MineAssembler.faces_mask(PieceCatalog.PIECES[p["name"]]["faces"]), p["r"])
			var node: Node3D = p["node"]
			var want := MineAssembler.cell_world(c)
			if p["name"] == "room_2":
				want += Basis(Vector3.UP, p["r"] * PI * 0.5) * Vector3(Tuning.GRID_CELL * 0.5, 0.0, -Tuning.GRID_CELL * 0.5)
			if wm != fd.open[c] or not node.position.is_equal_approx(want) or not is_equal_approx(node.rotation.y, p["r"] * PI * 0.5):
				bad += 1
		for c in fd.rails:
			for rl in fd.rails[c]:
				rails_n += 1
				var wm := MineAssembler.rotate_mask(MineAssembler._rail_mask(rl["name"]), rl["r"])
				var rm := 0
				for f in 4:
					if (fd.open[c] & (1 << f)) and (fd.rail.has(c + MineAssembler.DIR_VEC[f]) or fd.station.has(c + MineAssembler.DIR_VEC[f])):
						rm |= 1 << f
				if fd.rails[c].size() == 1 and wm != rm:
					bad += 1
		_check(bad == 0, "%s 조각·레일의 회전이 칸의 뚫린 면과 일치 (%d칸, 어긋남 %d)" % [tag, checked, bad])
		# 겹침 0: 조각 노드 수 = 조각 칸 수, 2×2 방 나머지 칸·대피소 예약 칸은 비어 있다
		for ch in fd.root.get_children():
			if ch.name.begins_with("P_"):
				pieces_n += 1
			elif ch.name.begins_with("R_"):
				rails_n -= 1
		var reserved_ok := true
		for c in fd.cover:
			if fd.open.has(c) or fd.pieces.has(c):
				reserved_ok = false
		for c in fd.kind:
			if fd.kind[c] in ["rock", "pillar"] and (fd.open.has(c) or fd.pieces.has(c)):
				reserved_ok = false
		_check(pieces_n == fd.pieces.size() and pieces_n == fd.open.size() and rails_n == 0 and reserved_ok,
			"%s 겹침 0: 조각 노드 %d = 칸 %d, 레일 노드 = 레일 표, 예약 칸(방 %d·바위 %d) 비어 있음" % [tag, pieces_n, fd.open.size(), fd.cover.size(), st["refuges"]])
		# 같은 시드로 다시 짜면 같은 배치
		var again := asm.build_layout(fd.seed, i)
		_check(MineAssembler.hash_of(again) == asm.layout_hash(i), "%s 같은 시드로 두 번 조립 = 같은 배치" % tag)
		# 40 m 밖 조각 끄기: 조각 메시 전부 visibility_range_end = PIECE_VIEW_RANGE
		var meshes: Array = []
		_collect_meshes(fd.root, meshes)
		var ranged := 0
		for mi in meshes:
			if is_equal_approx((mi as MeshInstance3D).visibility_range_end, Tuning.PIECE_VIEW_RANGE):
				ranged += 1
		_check(not meshes.is_empty() and ranged == meshes.size(), "%s 메시 %d개 전부 visibility_range_end %.0f m (실제 %d)" % [tag, meshes.size(), Tuning.PIECE_VIEW_RANGE, ranged])
		# 괴물 + 감독 (#35): 층마다 Stalker 1·Director 1, 시작은 숨김·압박 0, MinerPreview 0. 몸(#36) 클립 8 이름·walk_crouch 길이
		var stalker := fd.root.get_node_or_null("Stalker") as Stalker
		var director := fd.root.get_node_or_null("Director") as Director
		_check(stalker != null and stalker == fd.stalker and director != null and director == fd.director and stalker.state == "hidden"
			and not stalker.visible and director.pressure < Tuning.PRESSURE_SEND * 0.1 and fd.root.get_node_or_null("MinerPreview") == null,
			"%s Stalker 1 · Director 1 · 시작 숨김(%s) · 압박 %.1f (< %.0f, 검사까지 몇 프레임 오른다) · MinerPreview 0" % [tag, stalker.state if stalker != null else "-", director.pressure if director != null else -1.0, Tuning.PRESSURE_SEND * 0.1])
		if stalker != null and stalker.body != null:
			var names := Array(stalker.body.clip_names())
			names.sort()
			var want := Array(MinerBody.CLIPS)
			want.sort()
			_check(names == want, "%s 광부 클립 %d개 이름 일치 (%s)" % [tag, names.size(), ", ".join(names)])
			var len_walk: float = stalker.body.clip_length("walk_crouch")
			_check(absf(len_walk - MINER_CLIP_LEN) <= MINER_CLIP_TOL, "%s walk_crouch 길이 %.3f s (= %.3f ± %.2f)" % [tag, len_walk, MINER_CLIP_LEN, MINER_CLIP_TOL])
			# 머리 따로 붙임 (#41): 가장 큰 메시(몸)의 정점 수
			var body_verts := 0
			var hand_verts := 0
			var body_arrays: PackedVector3Array = PackedVector3Array()
			for mi in stalker.body.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				if mesh != null:
					var n := 0
					var nh := 0
					var all_vs := PackedVector3Array()
					for si in mesh.get_surface_count():
						var vs := mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array
						n += vs.size()
						all_vs.append_array(vs)
						for v in vs:
							if absf(v.x) > MINER_HAND_X:
								nh += 1
					if n > body_verts:
						body_verts = n
						hand_verts = nh
						body_arrays = all_vs
			# #45: 몸이 한 덩어리 생성(TRELLIS.2)이라 "따로 붙인 증거" 검사(정점 하한·손 정점 비율)는 뜻이 없어 뺐다. 정점 수는 로그로만
			_check(body_verts > 0, "%s 광부 몸 메시 정점 %d (참고: #43 111,922)" % [tag, body_verts])
			# 몸통 요철 (#43): 오른쪽(뼈 쪽) 가슴 앞면이 왼쪽(살 쪽)보다 거칠다. 메시 좌표는 Y-up (Blender z → y, 앞 = +z)
			var relief_r := _chest_relief(body_arrays, -0.20, -0.05)
			var relief_l := _chest_relief(body_arrays, 0.05, 0.20)
			_check(relief_r >= MINER_CHEST_RELIEF_MIN and relief_r >= MINER_CHEST_RATIO * relief_l,
				"%s 광부 가슴 요철 오른쪽 %.1f mm ≥ %.0f · 왼쪽 %.1f mm 의 %.2f배 ≥ %.1f (갈비가 형태인 메시)" % [tag, relief_r * 1000.0, MINER_CHEST_RELIEF_MIN * 1000.0, relief_l * 1000.0, relief_r / maxf(relief_l, 1e-6), MINER_CHEST_RATIO])
			# 손 따로 붙임 (#42): 손목 밖 정점 비율
			print("  광부 손목 밖 정점 %d / 몸 %d = %.0f%% (참고, #42 검사는 #45 에서 뺌)" % [hand_verts, body_verts, 100.0 * hand_verts / maxi(body_verts, 1)])
			# 재질 (#39): 텍스처 있는 재질 ≥ 3(살·갱목·주철. 가죽끈은 단색), 전부 무광(거칠기 ≥ 0.9·금속성 0)
			var mats: Array[BaseMaterial3D] = []
			for mi in stalker.body.find_children("*", "MeshInstance3D", true, false):
				for si in (mi as MeshInstance3D).get_surface_override_material_count():
					var m := (mi as MeshInstance3D).get_active_material(si) as BaseMaterial3D
					if m != null and not mats.has(m):
						mats.append(m)
			var textured := 0
			var matte := 0
			for m in mats:
				if m.albedo_texture != null:
					textured += 1
				if m.roughness >= SKIN_ROUGH_MIN and is_zero_approx(m.metallic):
					matte += 1
			_check(textured >= 3 and matte == mats.size() and not mats.is_empty(), "%s 광부 재질 %d개: 텍스처 %d (≥ 3) · 무광 %d (전부, 거칠기 ≥ %.1f·금속성 0)" % [tag, mats.size(), textured, matte, SKIN_ROUGH_MIN])
		# 격자 길: 정거장 입구 → 가장 먼 칸. 길이 = BFS 거리, 걸음마다 뚫린 면으로 이웃 칸 (대각선·벽 통과 없음)
		var dmap: Dictionary = MineAssembler.grid_dist(fd, fd.entry, 10000)
		var far := fd.entry
		for c in dmap.keys():
			if dmap[c] > dmap[far]:
				far = c
		var gp: Array[Vector2i] = MineAssembler.grid_path(fd, fd.entry, far)
		var steps_ok := gp.size() >= 2 and gp[0] == fd.entry and gp[gp.size() - 1] == far
		for k in range(1, gp.size()):
			var dv: Vector2i = gp[k] - gp[k - 1]
			var f: int = MineAssembler.DIR_VEC.find(dv)
			if f < 0 or not fd.open.has(gp[k]) or not (fd.open[gp[k - 1]] & (1 << f)):
				steps_ok = false
		_check(steps_ok and gp.size() - 1 == dmap[far], "%s grid_path 입구→가장 먼 칸 %s: %d걸음 = BFS 거리 %d, 전부 뚫린 면으로 이웃" % [tag, far, gp.size() - 1, dmap[far]])
		# 포켓: 층마다 ≥ 1, 전부 SLOT 자리 위, 통로 쪽 방향이 적혀 있다
		var on_floor := 0
		var on_slot := 0
		for pk in pockets:
			var pn := pk as Node3D
			if absf(pn.global_position.y - fd.y) > Tuning.LIFT_DROP * 0.5:
				continue
			on_floor += 1
			var slot := pn.get_meta("slot", null) as Node3D
			if slot != null and pn.has_meta("out") and pn.global_position.is_equal_approx(slot.global_position + (pn.get_meta("out") as Vector3) * Tuning.POCKET_WALL_OUT):
				on_slot += 1
		_check(on_floor >= Tuning.POCKET_MIN_PER_FLOOR and on_slot == on_floor,
			"%s 포켓 %d개(≥%d), 전부 SLOT_Pocket 자리에서 통로 쪽 %.2f m (%d)" % [tag, on_floor, Tuning.POCKET_MIN_PER_FLOOR, Tuning.POCKET_WALL_OUT, on_slot])
		# 소품: 수 = 실측, 바닥 위, 뚫린 칸 안, 각도 다양
		var props_ok := 0
		var yaws := {}
		for pr in fd.props:
			var c := MineAssembler.cell_of(pr.global_position)
			if absf(pr.global_position.y - fd.y) < 0.05 and (fd.open.has(c) or fd.cover.has(c)):
				props_ok += 1
			yaws[snappedf(pr.rotation.y, 0.01)] = true
		_check(fd.props.size() == PROPS_TOTAL[i] and props_ok == fd.props.size() and yaws.size() >= PROP_YAWS_MIN,
			"%s 소품 %d개 = 실측 %d, 전부 바닥 위·뚫린 칸 안 (%d), 각도 %d가지" % [tag, fd.props.size(), PROPS_TOTAL[i], props_ok, yaws.size()])
	_check(asm.floors.size() < 2 or asm.layout_hash(0) != asm.layout_hash(1), "시드 %d 와 %d 는 다른 배치" % [Tuning.MAP_SEED, Tuning.MAP_SEED + 1])
	# 정거장 A 면(갱도 쪽 z 0)의 테두리 정점이 기준 윤곽(직선 조각 S 면) 위 — #26 이 안 잰 유일한 이음새
	var station := room.get_node_or_null("Stations/Station_top") as Node3D
	var ref_piece := _spawn_piece(room, PieceCatalog.piece_path("straight"))
	if station != null and ref_piece != null:
		var ref := _face_outline(ref_piece, "straight", "S")
		var outline := _outline_on(station, "ENV_", 2, 0.0, 0.0)
		var worst := _outline_deviation(outline, ref)
		# #27 실측: 정거장(#20, 격자 0.25·요철 무감쇠)의 입구 테두리는 정점 20개, 기준 윤곽에서 최대 208 mm — 조각과 달리 입구에서 요철이 0 으로 안 잦아든다.
		# 검사가 아니라 참고값으로 남긴다. 고치려면 build_shaft.py 갱도부 입구 0.7 m 안에서 요철을 0 으로 (조각 규칙과 같게) — 별도 제안서.
		print("ok 정거장 갱도 쪽 A 면 테두리 %d점, 기준 윤곽에서 최대 %.0f mm (참고값 — 검사 아님. 조각끼리는 %.0f mm)" % [outline.size(), worst * 1000.0, PieceCatalog.FACE_TOL * 1000.0])
		ref_piece.queue_free()
		await _wait(2)
	if player != null:
		var sc := MineAssembler.cell_of(player.global_position)
		_check(asm.floors[0].open.has(sc), "플레이어 스폰 칸 %s 이 뚫린 칸" % sc)
	# #27 수정: 벽·바닥 재질 = 2K 알베도 · 물막 0 · 반사·미세 결 = Tuning
	for prefix in WET_MATERIALS:
		var mi := _mesh_with_material(room.get_node("Layers"), prefix)
		var sm: ShaderMaterial = null
		if mi != null:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si)
				if m is ShaderMaterial and (m as ShaderMaterial).resource_name.begins_with(prefix):
					sm = m
		var tex: Texture2D = sm.get_shader_parameter("albedo_tex") if sm != null else null
		var w: int = tex.get_width() if tex != null else 0
		_check(w == TEX_BIG, "%s 알베도 %d px = %d (2K)" % [prefix, w, TEX_BIG])
		var want_scale: float = Tuning.TRI_SCALE_FLOOR if prefix == "MAT_Floor" else Tuning.TRI_SCALE_WALL
		_check(sm != null and sm.get_shader_parameter("use_triplanar") == Tuning.TRIPLANAR
			and is_equal_approx(sm.get_shader_parameter("tri_scale"), want_scale),
			"%s 세계 좌표 삼면 %s · 배율 %.2f = Tuning" % [prefix, Tuning.TRIPLANAR, want_scale])
		_check(sm != null and is_equal_approx(sm.get_shader_parameter("wet_clearcoat"), Tuning.STONE_CLEARCOAT)
			and is_equal_approx(sm.get_shader_parameter("specular_value"), Tuning.ROCK_SPECULAR)
			and is_equal_approx(sm.get_shader_parameter("detail_strength"), Tuning.DETAIL_NORMAL_STRENGTH)
			and is_equal_approx(sm.get_shader_parameter("normal_scale"), Tuning.ROCK_NORMAL_SCALE),
			"%s 물막 %.1f · 반사 %.2f · 미세 결 %.1f · 노멀 %.1f = Tuning" % [prefix, Tuning.STONE_CLEARCOAT, Tuning.ROCK_SPECULAR, Tuning.DETAIL_NORMAL_STRENGTH, Tuning.ROCK_NORMAL_SCALE])
	# 이음새 칼라 (#27 수정 2): 층마다 칼라 수 = 이음새 수
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var holder := fd.root.get_node_or_null("Collars")
		var n: int = holder.get_child_count() if holder != null else 0
		_check(fd.seams.size() > 0 and n == fd.seams.size() and Tuning.COLLAR_THICK > 0.0,
			"층 %d 이음새 칼라 %d = 이음새 %d (두께 %.2f)" % [i, n, fd.seams.size(), Tuning.COLLAR_THICK])
	# 갱도 설비 (#28): 직선 칸 × 2 = Services 자식 수 · 자리·회전 = 조각 · 삼각형 · L 묶음이 풍관 위~배수로를 덮는다
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var holder := fd.root.get_node_or_null("Services")
		var n: int = holder.get_child_count() if holder != null else 0
		var straights := 0
		for c in fd.pieces:
			if fd.pieces[c]["name"] == "straight":
				straights += 1
		_check(Tuning.SVC_ON > 0 and straights > 0 and n == straights * 2 and fd.services.size() == n,
			"층 %d 설비 묶음 %d = 직선 %d × 2 (SVC_ON %d)" % [i, n, straights, Tuning.SVC_ON])
		var bad_rot := 0
		var tri_l := 0
		var tri_r := 0
		var hi := -99.0
		var missing := 0          # 재질로 요소를 센다: L 에 물(배수로)·풍관·케이블, R 에 녹슨 배관
		for sv in fd.services:
			var mi: MeshInstance3D = sv["node"]
			var piece: Node3D = fd.pieces[sv["cell"]]["node"]
			if absf(angle_difference(mi.rotation.y, piece.rotation.y)) > 0.001 or (mi.position - piece.position).length() > 0.001:
				bad_rot += 1
			var tri := 0
			var names: Array[String] = []
			for k in mi.mesh.get_surface_count():
				tri += (mi.mesh as ArrayMesh).surface_get_array_len(k) / 3
				var mat := mi.mesh.surface_get_material(k)
				names.append(mat.resource_name if mat != null else "")
			var want: Array = ["SVC_Water", "SVC_Duct", "MAT_Cable"] if sv["side"] == "L" else ["MAT_RustyMetal"]
			for w in want:
				if names.filter(func(nm: String): return nm.begins_with(w)).is_empty():
					missing += 1
			if sv["side"] == "L":
				tri_l = maxi(tri_l, tri)
				hi = maxf(hi, mi.mesh.get_aabb().end.y)
			else:
				tri_r = maxi(tri_r, tri)
		_check(bad_rot == 0, "층 %d 설비 자리·회전 = 조각 (어긋남 %d)" % [i, bad_rot])
		_check(tri_l > 0 and tri_l + tri_r <= Tuning.SVC_TRI_MAX, "층 %d 설비 삼각형 칸당 최대 %d ≤ %d (L %d + R %d)" % [i, tri_l + tri_r, Tuning.SVC_TRI_MAX, tri_l, tri_r])
		_check(missing == 0 and hi >= Tuning.SVC_DUCT_H + Tuning.SVC_DUCT_R - 0.05,
			"층 %d 묶음마다 물·풍관·케이블 / 녹슨 배관 재질 있음 (빠짐 %d) · L 위 %.2f ≥ 풍관 위 %.2f" % [i, missing, hi, Tuning.SVC_DUCT_H + Tuning.SVC_DUCT_R])
	# 광차 (#29): 순환선 닫힘·인접·전부 레일 / 광차 수·곡선 위 / 달리는 광차의 2초 이동 = CART_SPEED × 2
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var ring: Array = fd.ring
		var bad := 0
		for k in range(1, ring.size()):
			var d: Vector2i = (ring[k] as Vector2i) - (ring[k - 1] as Vector2i)
			if absi(d.x) + absi(d.y) != 1 or not fd.rail.has(ring[k]):
				bad += 1
		_check(ring.size() >= 100 and ring[0] == ring[ring.size() - 1] and bad == 0,
			"층 %d 순환선 %d칸, 첫 = 끝 %s, 인접·레일 아님 %d" % [i, ring.size(), ring[0] == ring[ring.size() - 1], bad])
		var dup := 0                                  # 겹친 연속 점 = 길이 0 구간 → 광차 회전이 0 벡터로 튄다 (#29-b)
		for k in range(1, fd.rail_path.curve.point_count):
			if fd.rail_path.curve.get_point_position(k).is_equal_approx(fd.rail_path.curve.get_point_position(k - 1)):
				dup += 1
		_check(dup == 0, "층 %d 순환선 곡선 겹친 점 %d = 0" % [i, dup])
		var spur := 0                                 # 되돌아가는 칸 (A→B→A) — 그 끝에서 광차가 180° 뒤집힌다 (#29-c)
		for k in range(1, ring.size() - 1):
			if ring[k - 1] == ring[k + 1]:
				spur += 1
		_check(spur == 0, "층 %d 순환선 되돌아가는 칸 %d = 0" % [i, spur])
		var curve: Curve3D = fd.rail_path.curve      # 한 바퀴를 물리 프레임(8 m/s ÷ 60) 단위로 재서 광차가 보는 방향(CART_LOOK 앞 점)의 yaw 변화 최대
		var L: float = curve.get_baked_length()
		var step: float = Tuning.CART_SPEED / 60.0
		var frames := int(L / step)
		var max_dy := 0.0
		var prev_yaw := 0.0
		for k in frames + 1:
			var a: Vector3 = curve.sample_baked(fposmod(step * k, L))
			var b: Vector3 = curve.sample_baked(fposmod(step * k + Tuning.CART_LOOK, L))
			var yaw := atan2(-(b.x - a.x), -(b.z - a.z))
			if k > 0:
				max_dy = maxf(max_dy, rad_to_deg(absf(angle_difference(prev_yaw, yaw))))
			prev_yaw = yaw
		_check(max_dy <= 4.0, "층 %d 광차 시선 yaw 프레임당 최대 %.2f° ≤ 4 (%d 프레임)" % [i, max_dy, frames])
		var off := 0
		for cart in fd.carts:
			var pf := cart as PathFollow3D
			if fd.rail_path.curve.get_closest_point(pf.position).distance_to(pf.position) > 0.05:
				off += 1
		_check(Tuning.CART_COUNT > 0 and fd.carts.size() == Tuning.CART_COUNT and off == 0, "층 %d 광차 %d = %d (> 0), 곡선에서 벗어남 %d" % [i, fd.carts.size(), Tuning.CART_COUNT, off])
	if not asm.floors.is_empty() and not asm.floors[0].carts.is_empty():
		var fd0: MineAssembler.FloorData = asm.floors[0]
		var mover: PathFollow3D = null
		for cart in fd0.carts:
			if not cart.is_stopped():
				mover = cart
				break
		if mover != null:
			var p0: float = mover.progress
			var nz0: int = NoiseBus.total
			await _wait(120)
			var moved: float = mover.progress - p0
			if moved < 0.0:
				moved += fd0.rail_path.curve.get_baked_length()
			var want: float = Tuning.CART_SPEED * 2.0
			_check(want > 0.5 and absf(moved - want) <= want * 0.1, "달리는 광차 2초 이동 %.1f m = %.1f ±10 %% (> 0)" % [moved, want])
			var run_n := 0                                    # 소음 (#32): 달리는 광차는 1초마다, 정차 광차는 0
			var stop_n := 0
			for e in _noise_kind(NoiseBus.since(nz0), "cart"):
				if e["who"] == mover:
					run_n += 1
				elif e["who"] is Node and (e["who"] as Node).is_stopped():
					stop_n += 1
			_check(Tuning.NOISE_CART > 0.0 and run_n >= 1 and run_n <= 3 and stop_n == 0,
				"달리는 광차 2초 소음 %d회 (1~3, 반경 %.0f > 0) · 정차 광차 %d = 0" % [run_n, Tuning.NOISE_CART, stop_n])
		else:
			_check(false, "달리는 광차가 없다 (전부 정차)")
	else:
		_check(false, "광차가 없다 (CART_COUNT %d)" % Tuning.CART_COUNT)
	# 정비 1 (#30): 층마다 고장 = timber 칸, 기둥 숨김·갓보 기울기 / 부품 수
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var timber := 0
		for c in fd.kind:
			if fd.kind[c] == "timber":
				timber += 1
		var bad_f := 0
		for f in fd.faults:
			if f.post_visible() or absf(f.cap_tilt_deg() - Tuning.FAULT_CAP_TILT_DEG) > 0.1 or f.state != "broken":
				bad_f += 1
		_check(timber > 0 and fd.faults.size() == timber and bad_f == 0, "층 %d 고장 %d = timber 칸 %d, 오른쪽 기둥 숨김·갓보 %.0f° 아닌 것 %d" % [i, fd.faults.size(), timber, Tuning.FAULT_CAP_TILT_DEG, bad_f])
		_check(fd.bin != null and fd.bin.parts.is_empty() and Tuning.ORE_PER_PART > 0, "층 %d 자재함 1, 시작 부품 0 (광석 %d = 좋은 부품)" % [i, Tuning.ORE_PER_PART])
	# 소품 무더기: 크기 2~3 · 반지름 안 · 복도 가운데 5 m 뒤에서 램프 원뿔 안
	for i in asm.floors.size():
		var fd: MineAssembler.FloorData = asm.floors[i]
		var bad_size := 0
		var seen := 0
		var visible := 0
		for cl in fd.clusters:
			var members: Array = cl["members"]
			var center: Vector3 = cl["center"]
			if members.size() < Tuning.PROP_CLUSTER_MIN or members.size() > Tuning.PROP_CLUSTER_MAX:
				bad_size += 1
			for m in members:
				if ((m as Node3D).position - center).length() > Tuning.PROP_CLUSTER_R + 0.01:
					bad_size += 1
			var c: Vector2i = cl["cell"]
			if not fd.pieces.has(c) or not (fd.pieces[c]["name"] in ["straight", "t", "cross"]):
				continue
			seen += 1
			var f: int = MineAssembler._first_bit(fd.open[c])
			var eye: Vector3 = MineAssembler.cell_world(c) + DIR3[f] * CLUSTER_VIEW_DIST + Vector3(0.0, Tuning.EYE_HEIGHT, 0.0)
			var look: Vector3 = -DIR3[f]
			var to: Vector3 = center + Vector3(0.0, 0.4, 0.0) - eye
			if to.length() <= CLUSTER_MAX_DIST and rad_to_deg(look.angle_to(to)) <= Tuning.LAMP_ANGLE_DEG:
				visible += 1
		var frac: float = float(visible) / maxf(1.0, float(seen))
		_check(not fd.clusters.is_empty() and bad_size == 0 and frac >= CLUSTER_VISIBLE_FRAC,
			"층 %d 소품 무더기 %d개: 크기 %d~%d·반지름 %.1f 안 (어긋남 %d), 복도 5 m 뒤 램프 원뿔 안 %d/%d (≥ %.0f%%)"
				% [i, fd.clusters.size(), Tuning.PROP_CLUSTER_MIN, Tuning.PROP_CLUSTER_MAX, Tuning.PROP_CLUSTER_R, bad_size, visible, seen, CLUSTER_VISIBLE_FRAC * 100.0])


func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


# ---------------- --texcmp : 텍스처 후보 비교판 (#27 수정 A 단계) ----------------
# Documents/MineTunnel/textures/<id>/ 의 2K 텍스처(tools/minetunnel/fetch_texture.py 가 받는다)를 실행 중에 젖은 바위 재질에 끼우고
# 사용자 지적 자리 두 곳(벽 1.6 m 정면 · 바닥 내려다봄)을 찍는다. 반사 제거·미세 결(TEXCMP_LOOK)을 적용한 채로. 내보내기·씬은 안 건드린다.

const TEXCMP_DIR := "C:/Users/anjyo/Documents/MineTunnel/textures/"
const TEXCMP_WALL: Array[String] = ["dark_rock", "rock_face_04", "quarry_wall", "rock_wall_08"]
const TEXCMP_FLOOR: Array[String] = ["brown_mud_rocks_01", "rocky_gravel", "gravel_floor_02", "rubble"]
const TEXCMP_LOOK := {"wet_clearcoat": 0.0, "wet_roughness": 0.45, "specular_value": 0.25, "normal_scale": 1.6, "detail_strength": 0.6}
const TEXCMP_WALL_STAND := Vector3(1.7, 0.2, -10.5)     # 정거장 앞 직선 칸, 오른쪽 벽(3.2~3.5) 1.6 m 앞에서 +X 를 본다
const TEXCMP_FLOOR_STAND := Vector3(-1.0, 0.2, -10.5)   # 레일 옆에서 -80° 내려다본다


func _texcmp_routine(room: Node3D) -> void:
	var player := room.get_node_or_null("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	await _wait(30)
	for id in TEXCMP_WALL:
		var n: int = Atmosphere.texcmp_apply("MAT_RockWall", _texcmp_textures(id), TEXCMP_LOOK)
		_stand_at(player, head, TEXCMP_WALL_STAND, 1)
		await _wait(30)
		await _shot("texcmp_wall_%s" % id)
		print("ok 벽 후보 %s (재질 %d)" % [id, n])
	Atmosphere.texcmp_apply("MAT_RockWall", _texcmp_textures(TEXCMP_WALL[0]), TEXCMP_LOOK)   # 벽은 지금 것으로 되돌려 놓고 바닥을 찍는다
	for id in TEXCMP_FLOOR:
		var n: int = Atmosphere.texcmp_apply("MAT_Floor", _texcmp_textures(id), TEXCMP_LOOK)
		player.global_position = TEXCMP_FLOOR_STAND
		player.rotation.y = 0.0
		head.rotation.x = deg_to_rad(-80.0)
		player.velocity = Vector3.ZERO
		await _wait(30)
		await _shot("texcmp_floor_%s" % id)
		print("ok 바닥 후보 %s (재질 %d)" % [id, n])
	_finish("TEXCMP")


func _texcmp_textures(id: String) -> Dictionary:
	var out := {}
	for pair in [["albedo", "Diffuse"], ["normal", "nor_gl"], ["rough", "Rough"]]:
		var path: String = "%s%s/%s_%s.jpg" % [TEXCMP_DIR, id, id, pair[1]]
		var img := Image.load_from_file(path)
		if img == null:
			print("FAIL 텍스처 없음 %s" % path)
			continue
		img.generate_mipmaps()
		out[pair[0]] = ImageTexture.create_from_image(img)
	return out


## 램프 흰 점 검사 (#27 수정): 화면 중앙 SPOT_BOX 안에서 가장 밝은 SPOT_BLOB 덩이의 평균 ÷ 전체 평균. 헤드램프가 카메라 축에 있어 거울 반사는 늘 화면 가운데 근처에 맺힌다.
func _spot_ratio_center() -> float:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return 9.0
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w / 2 - SPOT_BOX / 2
	var y0 := h / 2 - SPOT_BOX / 2
	var lum := PackedFloat32Array()
	lum.resize(SPOT_BOX * SPOT_BOX)
	var total := 0.0
	for y in SPOT_BOX:
		for x in SPOT_BOX:
			var c := img.get_pixel(x0 + x, y0 + y)
			var v := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			lum[y * SPOT_BOX + x] = v
			total += v
	var mean := total / float(SPOT_BOX * SPOT_BOX)
	var best := 0.0
	for by in range(0, SPOT_BOX - SPOT_BLOB + 1, 10):
		for bx in range(0, SPOT_BOX - SPOT_BLOB + 1, 10):
			var sum := 0.0
			for y in range(by, by + SPOT_BLOB, 2):
				for x in range(bx, bx + SPOT_BLOB, 2):
					sum += lum[y * SPOT_BOX + x]
			best = maxf(best, sum / float((SPOT_BLOB / 2) * (SPOT_BLOB / 2)))
	return best / maxf(mean, 0.001)


# ---------------- 이음새 (#27 수정 2) ----------------

## 이음새 가운데 바닥점에서 진행 방향의 오른쪽으로 SEAM_STAND 떨어져 서서 오른쪽 벽(이음새 세로선)을 본다
func _seam_view(player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData, sm: Dictionary) -> void:
	var f: int = sm["face"]
	var seam: Vector3 = (sm["pos"] as Vector3) + Vector3(0.0, fd.y, 0.0)
	var side: int = (f + 1) % 4
	var stand: float = SEAM_STAND if sm["kind"] == "A" else SEAM_STAND_D     # 문(3.5 폭)은 옆으로 덜 — 1.3 이면 카메라가 벽 안에 들어간다
	_stand_at(player, head, seam + DIR3[side] * stand, side)
	await _wait(30)


## 램프 원(화면 가운데 반지름 SLIT_DISK_R) 안의 검은 픽셀 수 — 벽 뒤 빈 공간(배경색)은 램프가 못 비추니 검다
func _dark_px_in_disk() -> int:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return 999999
	var w := img.get_width()
	var h := img.get_height()
	var cx := w / 2
	var cy := h / 2
	var n := 0
	for y in range(cy - SLIT_DISK_R, cy + SLIT_DISK_R, 2):
		for x in range(cx - SLIT_DISK_R, cx + SLIT_DISK_R, 2):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > SLIT_DISK_R * SLIT_DISK_R:
				continue
			var c := img.get_pixel(x, y)
			if c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722 < SLIT_LUMA:
				n += 1
	return n * 4      # 2 px 간격 표본 → 픽셀 수


## --seams : 위층 이음새 전수 조사. 이음새마다 오른쪽 벽을 보고 검은 픽셀을 세어 가장 나쁜 5곳을 seam_worst_<n>_<칸>.png 로 남긴다 (사용자 스크린샷 자리 특정용)
func _seams_routine(room: Node3D) -> void:
	var player := room.get_node_or_null("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	var asm := _asm(room)
	var fd: MineAssembler.FloorData = asm.floors[0]
	await _wait(30)
	var scores: Array = []
	for sm in fd.seams:
		await _seam_view(player, head, fd, sm)
		var dark := await _dark_px_in_disk()
		scores.append([dark, sm])
	scores.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(5, scores.size()):
		var sm: Dictionary = scores[k][1]
		await _seam_view(player, head, fd, sm)
		await _shot("seam_worst_%d_%d_%d_%s" % [k, sm["cell"].x, sm["cell"].y, MineAssembler.DIR_NAME[sm["face"]]])
		var nb: Vector2i = sm["cell"] + MineAssembler.DIR_VEC[sm["face"]]
		print("ok 이음새 나쁜 곳 %d: 칸 %s 면 %s 검은 픽셀 %d (%s-%s)" % [k, sm["cell"], MineAssembler.DIR_NAME[sm["face"]], scores[k][0],
			fd.pieces[sm["cell"]]["name"] if fd.pieces.has(sm["cell"]) else "?", fd.pieces[nb]["name"] if fd.pieces.has(nb) else "정거장"])
	var total := 0
	for s in scores:
		total += s[0]
	print("ok 이음새 %d곳 평균 검은 픽셀 %d" % [scores.size(), total / maxi(scores.size(), 1)])
	_finish("SEAMS")


# ---------------- 갱도 설비 (#28) ----------------

func _nearest_straight(fd: MineAssembler.FloorData, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for c in fd.pieces:
		if fd.pieces[c]["name"] != "straight":
			continue
		var d: float = Vector2(c - from).length()
		if d < bd:
			bd = d
			best = c
	return best


## 직선 칸 가운데서 조각 기준 왼쪽(−1)·오른쪽(+1) 벽 쪽으로 off 만큼 가 서서 그 벽을 본다. pitch = 고개 (양수 위)
func _svc_stand(player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData, c: Vector2i, side: int, off: float, pitch: float, dz: float = 0.0) -> void:
	var piece: Node3D = fd.pieces[c]["node"]
	var dir: Vector3 = piece.transform.basis * Vector3(float(side), 0.0, 0.0)
	var along: Vector3 = piece.transform.basis * Vector3(0.0, 0.0, dz)      # 조각 로컬 z (밸브는 −1.6)
	var look := 0
	for f in 4:
		if DIR3[f].dot(dir) > 0.9:
			look = f
	_stand_at(player, head, MineAssembler.cell_world(c, fd.y) + dir * off + along, look)
	head.rotation.x = deg_to_rad(pitch)


# ---------------- --tour <폴더> : 맵 구경 스크린샷 10장 (검사 아님, 사용자에게 보여주는 용) ----------------
## 위층을 돈다: 정거장 앞 · 직선 · 곡선 · T · + · 목→방 · 방 안 · 대피소 · 막장 · 밸브 칸 배수로.
func _tour_routine(room: Node3D) -> void:
	var asm := _asm(room)
	if asm == null or asm.floors.is_empty():
		print("FAIL 조립 없음")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var player := room.get_node("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	var fd: MineAssembler.FloorData = asm.floors[0]
	var n := 0
	# 1. 정거장 앞 입구 칸에서 갱도 안쪽을 본다
	_stand_at(player, head, MineAssembler.cell_world(fd.entry, fd.y), 0)
	await _wait(40)
	await _shot("tour_%02d_entry" % n); n += 1
	# 2. 직선 복도 (정거장 가까운 직선), 복도 방향
	var st := _nearest_straight(fd, fd.entry)
	if st.x >= 0:
		_stand_before(player, head, fd, st, MineAssembler._first_bit(fd.open[st]), CLUSTER_VIEW_DIST - Tuning.GRID_CELL * 0.5)
		await _wait(30)
		await _shot("tour_%02d_straight" % n); n += 1
	# 3~5. 곡선 · T · +
	for pair in [["curve", "curve"], ["t", "t_junction"], ["cross", "cross"]]:
		var c := _first_cell(fd, pair[0])
		if c.x >= 0:
			_stand_before(player, head, fd, c, MineAssembler._first_bit(fd.open[c]), MAZE_STAND)
			await _wait(30)
			await _shot("tour_%02d_%s" % [n, pair[1]]); n += 1
	# 6. 목 → 방 문
	var neck := _first_cell(fd, "neck")
	if neck.x >= 0:
		var p: Dictionary = fd.pieces[neck]
		var a_face: int = MineAssembler.world_face("neck", p["r"], "S")
		_stand_before(player, head, fd, neck, a_face, MAZE_STAND)
		await _wait(30)
		await _shot("tour_%02d_neck" % n); n += 1
	# 7. 방 2×2 안, 문 쪽
	var room2 := _first_cell(fd, "room_2")
	if room2.x >= 0:
		var p: Dictionary = fd.pieces[room2]
		var door_face: int = MineAssembler.world_face("room_2", p["r"], "S")
		_stand_at(player, head, (p["node"] as Node3D).global_position, door_face)
		await _wait(30)
		await _shot("tour_%02d_room" % n); n += 1
	# 8. 대피소 문
	var refuge := _first_cell(fd, "refuge")
	if refuge.x >= 0:
		var p: Dictionary = fd.pieces[refuge]
		var alcove: int = MineAssembler.world_face("refuge", p["r"], "E")
		_stand_at(player, head, MineAssembler.cell_world(refuge, fd.y) - DIR3[alcove] * 1.0, alcove)
		await _wait(30)
		await _shot("tour_%02d_refuge" % n); n += 1
	# 9. 막장 (레일 종점)
	var term := _first_cell(fd, "cap", "end")
	if term.x < 0:
		term = _first_cell(fd, "cap")
	if term.x >= 0:
		_stand_before(player, head, fd, term, MineAssembler._first_bit(fd.open[term]), MAZE_STAND)
		await _wait(30)
		await _shot("tour_%02d_face" % n); n += 1
	# 10. 밸브 칸에서 바닥 배수로 쪽 비스듬히
	for sv in fd.services:
		if sv["side"] == "R" and sv["variant"] == 1:
			_svc_stand(player, head, fd, sv["cell"], 1, 0.4, -25.0, -1.6)
			await _wait(30)
			await _shot("tour_%02d_valve" % n); n += 1
			break
	print("ok tour %d장 -> %s" % [n, _out_dir])
	get_tree().quit(0)


# ---------------- 광차 (#29) ----------------

func _cart_ride(player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData) -> void:
	if fd.carts.is_empty() or fd.ring.size() < 4:
		_check(false, "광차 없음")
		return
	var start: Vector3 = MineAssembler.cell_world(fd.ring[0], fd.y)
	var nxt: Vector2i = fd.ring[1]
	var dir: Vector3 = Vector3(nxt.x - fd.ring[0].x, 0.0, nxt.y - fd.ring[0].y)
	var look := 0
	for f in 4:
		if DIR3[f].dot(dir) > 0.9:
			look = f
	var right: Vector3 = dir.cross(Vector3.UP)                     # 진행 방향의 오른쪽 옆
	_stand_at(player, head, start + right * (Tuning.CART_OFF_SIDE + 0.4), look)
	player.rotation.y = YAW_OF[(look + 3) % 4]                     # 레일 쪽(왼쪽)을 본다
	var cart: PathFollow3D = null
	for _k in 1500:                                                # 최대 25초 기다린다 (정차 6초, 간격 40초)
		await _wait(1)
		for c in fd.carts:
			if c.is_stopped() and (c as Node3D).global_position.distance_to(player.global_position) <= Tuning.CART_BOARD_DIST:
				cart = c
		if cart != null:
			break
	if cart == null:
		_check(false, "정차한 광차가 25초 안에 안 왔다")
		return
	await _shot("70_cart_wait")
	_inject_key(KEY_E, true)
	await _wait(1)
	_inject_key(KEY_E, false)
	await _wait(60)
	var d0: float = player.global_position.distance_to((cart as Node3D).global_position)
	_check(player.ride == cart and d0 < 1.5, "E → 광차에 탐 (거리 %.2f < 1.5, ride %s)" % [d0, player.ride != null])
	for _k in 500:                                                 # 정차가 끝나 움직일 때까지
		if not cart.is_stopped():
			break
		await _wait(1)
	var from: Vector3 = player.global_position
	player.rotation.y = YAW_OF[look]
	head.rotation.x = deg_to_rad(-6.0)
	await _wait(3)                                                 # 시점을 돌린 프레임은 검게 찍힌다
	var yaw_prev: float = player.global_rotation.y                 # 5초 = 40 m, 첫 곡선을 지난다. 사용자가 보는 시점 yaw 가 프레임당 4° 넘게 튀면 FAIL (#29-c)
	var yaw_max := 0.0
	var turned := 0.0
	for k in 300:
		if k % 36 == 0 and k < 180:
			await _grab()
		await _wait(1)
		var y: float = player.global_rotation.y
		var dy: float = absf(angle_difference(yaw_prev, y))
		yaw_max = maxf(yaw_max, dy)
		turned += dy
		yaw_prev = y
	_flush_burst("71_cart_ride")
	_check(turned >= deg_to_rad(60.0) and yaw_max <= deg_to_rad(4.0), "탑승 5초 동안 시점 %.0f° 돎 (≥ 60, 곡선 지남) · 프레임당 최대 %.2f° ≤ 4" % [rad_to_deg(turned), rad_to_deg(yaw_max)])
	var went: float = player.global_position.distance_to(from)
	_check(player.ride == cart and went >= 5.0, "광차와 함께 %.1f m 이동 (≥ 5)" % went)
	_inject_key(KEY_E, true)
	await _wait(1)
	_inject_key(KEY_E, false)
	await _wait(30)
	var rail_d: float = fd.rail_path.curve.get_closest_point(player.global_position - fd.root.global_position - fd.rail_path.position).distance_to(player.global_position - fd.root.global_position - fd.rail_path.position)
	_check(player.ride == null and rail_d >= 1.0 and player.is_on_floor(), "E → 내림 (레일에서 %.2f m ≥ 1, 바닥 %s)" % [rail_d, player.is_on_floor()])
	await _shot("72_cart_off")


## --film maze / lamp / services : 롱폼 1편 재료 (검사 아님). 괴물·감독을 멈추고 소음 원·디버그 표시를 숨긴다.
##   ./build/NewGame.exe --resolution 1920x1080 --write-movie <out>.avi --fixed-fps 60 -- --film maze
##   maze     정거장 입구에서 방까지 격자 길을 따라 걷는다 (13초)
##   lamp     직선 복도에서 2초 켠 채 → F → 7초 (눈 적응 4초가 끝까지 보인다)
##   services 설비가 붙은 직선 칸으로 걸어 들어가 멈추고 좌우를 둘러본다 (6초)
const FILM_MAZE_FRAMES := 780
const FILM_MAZE_TURN := 0.08       # 한 프레임에 목표 방향으로 도는 비율
const FILM_MAZE_REACH := 1.2       # m, 이만큼 다가가면 다음 이음새로
const FILM_LAMP_LIT := 120
const FILM_LAMP_DARK := 420
const FILM_SVC_WALK := 150
const FILM_SVC_PAN := 210

func _film_prep(room: Node3D) -> void:
	var asm := _asm(room)
	if asm != null:
		for fd in asm.floors:
			if fd.director != null:
				fd.director.set("paused", true)
	var player := room.get_node("Player")
	for n in player.get_children():                    # 철 수·게이지·수리·소음 원·디버그 — 화면 글자 전부. PostFx 는 방에 붙어 있어 안 건드린다
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false


## --mapdump <json> : 층마다 격자(뚫린 면 비트·칸 종류·레일·순환선)를 JSON 으로 쓴다. 롱폼 "시드가 바뀌면 미로가 바뀐다" 그림용 (검사 아님)
func _mapdump_routine(room: Node3D) -> void:
	var out := []
	for fd in _asm(room).floors:
		var cells := []
		for c in fd.open:
			cells.append([c.x, c.y, fd.open[c], fd.kind.get(c, ""), fd.pieces[c]["name"] if fd.pieces.has(c) else ""])
		var ring := []
		for c in fd.ring:
			ring.append([c.x, c.y])
		out.append({"index": fd.index, "seed": Tuning.MAP_SEED + fd.index, "n": Tuning.MAP_N, "cells": cells, "ring": ring})
	var f := FileAccess.open(_out_dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("ok mapdump 층 %d -> %s" % [out.size(), _out_dir])
	get_tree().quit(0)


## 촬영이 끝났을 때 괴물이 한 층이라도 보였으면 FAIL — 1편은 괴물 0 (롱폼 시리즈_설계 §4)
func _film_end(room: Node3D, label: String) -> void:
	var shown := 0
	for fd in _asm(room).floors:
		if fd.stalker != null and (fd.stalker as Node3D).visible:
			shown += 1
	if shown > 0:
		print("FAIL film %s: 괴물 보임 %d층" % [label, shown])
		get_tree().quit(1)
		return
	print("ok film %s: 괴물 보임 0" % label)
	get_tree().quit(0)


func _film_mine(room: Node3D, variant: String) -> void:
	_film_prep(room)
	var asm := _asm(room)
	var player := room.get_node("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	var fd: MineAssembler.FloorData = asm.floors[0]
	if variant == "lamp":
		var st := _nearest_straight(fd, fd.entry)
		_stand_before(player, head, fd, st, MineAssembler._first_bit(fd.open[st]), CLUSTER_VIEW_DIST - Tuning.GRID_CELL * 0.5)
		head.rotation.x = deg_to_rad(-6.0)
		var yaw0: float = player.rotation.y
		for k in FILM_LAMP_LIT + FILM_LAMP_DARK:
			if k == FILM_LAMP_LIT:
				_inject_key(KEY_F, true)
			elif k == FILM_LAMP_LIT + 2:
				_inject_key(KEY_F, false)
			player.rotation.y = yaw0 + deg_to_rad(4.0) * sin(k / 60.0 * 0.4)
			await _wait(1)
		print("ok film lamp: lamp_on %s" % player.lamp_on)
	elif variant == "maze":
		var target := _first_cell(fd, "room_2")
		var path := MineAssembler.grid_path(fd, fd.entry, target)
		if path.size() < 3:
			print("FAIL film maze: 길 %d칸" % path.size())
			get_tree().quit(1)
			return
		var marks: Array[Vector3] = []                  # 칸 사이 이음새 가운데 — 곡선 칸도 여기는 늘 뚫려 있다
		for i in path.size() - 1:
			marks.append((MineAssembler.cell_world(path[i], fd.y) + MineAssembler.cell_world(path[i + 1], fd.y)) * 0.5)
		marks.append(MineAssembler.cell_world(path[-1], fd.y))
		_stand_at(player, head, MineAssembler.cell_world(fd.entry, fd.y), 0)
		head.rotation.x = deg_to_rad(-5.0)
		var wi := 0
		var to0: Vector3 = marks[0] - player.global_position
		player.rotation.y = atan2(-to0.x, -to0.z)
		await _wait(30)
		_inject_key(KEY_W, true)
		for k in FILM_MAZE_FRAMES:
			var to: Vector3 = marks[wi] - player.global_position
			if Vector2(to.x, to.z).length() < FILM_MAZE_REACH:
				if wi == marks.size() - 1:
					break
				wi += 1
				to = marks[wi] - player.global_position
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-to.x, -to.z), FILM_MAZE_TURN)
			await _wait(1)
		_inject_key(KEY_W, false)
		await _wait(30)
		print("ok film maze: 길 %d칸 중 %d번째 이음새까지" % [path.size(), wi])
	elif variant == "services":
		var cell := Vector2i(-1, -1)
		var bd := 1e9
		for sv in fd.services:
			var d: float = Vector2(sv["cell"] - fd.entry).length()
			if d < bd and fd.kind.get(sv["cell"], "") != "stub":
				bd = d
				cell = sv["cell"]
		if cell.x < 0:
			print("FAIL film services: 설비 칸 없음")
			get_tree().quit(1)
			return
		_stand_before(player, head, fd, cell, MineAssembler._first_bit(fd.open[cell]), MAZE_STAND + Tuning.GRID_CELL)
		head.rotation.x = deg_to_rad(-3.0)
		_inject_key(KEY_W, true)
		await _wait(FILM_SVC_WALK)
		_inject_key(KEY_W, false)
		var yaw0: float = player.rotation.y
		for k in FILM_SVC_PAN:
			player.rotation.y = yaw0 + deg_to_rad(28.0) * sin(k / float(FILM_SVC_PAN) * TAU)
			await _wait(1)
		print("ok film services: 칸 %s" % cell)
	_film_end(room, variant)


## --film cart : 광차 타고 순환선 20초 (검사 아님, 쇼츠·보고용). --write-movie 와 같이 돌린다.
##   "$GODOT" --path . --windowed --write-movie <out>.avi --fixed-fps 60 -- --film cart
const FILM_CART_FRAMES := 1200      # 20초
func _film_cart(room: Node3D) -> void:
	_film_prep(room)
	var asm := _asm(room)
	var player := room.get_node("Player") as CharacterBody3D
	var head: Node3D = player.get_node("Head")
	var fd: MineAssembler.FloorData = asm.floors[0]
	var start: Vector3 = MineAssembler.cell_world(fd.ring[0], fd.y)
	var nxt: Vector2i = fd.ring[1]
	var dir: Vector3 = Vector3(nxt.x - fd.ring[0].x, 0.0, nxt.y - fd.ring[0].y)
	var look := 0
	for f in 4:
		if DIR3[f].dot(dir) > 0.9:
			look = f
	_stand_at(player, head, start + dir.cross(Vector3.UP) * (Tuning.CART_OFF_SIDE + 0.4), look)
	player.rotation.y = YAW_OF[(look + 3) % 4]
	var cart: PathFollow3D = null
	for _k in 1500:
		await _wait(1)
		for c in fd.carts:
			if c.is_stopped() and (c as Node3D).global_position.distance_to(player.global_position) <= Tuning.CART_BOARD_DIST:
				cart = c
		if cart != null:
			break
	if cart == null:
		print("FAIL 광차 없음")
		get_tree().quit(1)
		return
	await _wait(20)
	_inject_key(KEY_E, true)
	await _wait(1)
	_inject_key(KEY_E, false)
	await _wait(10)
	cart.set("_stop_left", 0.0)                      # 촬영은 바로 출발
	head.rotation.x = deg_to_rad(-6.0)
	var yaw0: float = YAW_OF[look]
	for k in FILM_CART_FRAMES:                       # 앞을 보되 천천히 좌우를 둘러본다 (±22°)
		player.rotation.y = yaw0 + deg_to_rad(22.0) * sin(k / 60.0 * 0.5)
		yaw0 = player.rotation.y - deg_to_rad(22.0) * sin(k / 60.0 * 0.5)
		await _wait(1)
		yaw0 = player.rotation.y - deg_to_rad(22.0) * sin(k / 60.0 * 0.5)
	print("ok film cart %d frames, cart progress %.1f" % [FILM_CART_FRAMES, cart.progress])
	_film_end(room, "cart")


# ---------------- 정비 1 (#30) ----------------

func _tap(code: Key) -> void:
	_inject_key(code, true)
	await _wait(1)
	_inject_key(code, false)


func _repair_run(player: CharacterBody3D, head: Node3D, fd: MineAssembler.FloorData) -> void:
	if fd.bin == null or fd.faults.size() < 2:
		_check(false, "자재함·고장 없음")
		return
	_inject_key(KEY_E, false)
	var bin: Node3D = fd.bin
	# 자재함 앞(통로 쪽 1.6 m)에서 +X(자재함)를 본다. 광석 0 → E → 삐걱 부품
	_stand_at(player, head, bin.global_position + Vector3(-1.6, 0.0, 0.0), 1)
	head.rotation.x = deg_to_rad(-20.0)
	player.add_ore(-player.ore_count)
	await _wait(20)
	await _tap(KEY_E)
	await _wait(5)
	_check(bin.parts.size() == 1 and bin.parts[0].quality == "creaky" and player.ore_count == 0,
		"광석 0 에서 E → 삐걱 부품 (부품 %d, 품질 %s, 광석 %d)" % [bin.parts.size(), bin.parts[0].quality if not bin.parts.is_empty() else "-", player.ore_count])
	var part: Node3D = bin.parts[0]
	await _tap(KEY_E)
	await _wait(10)
	_check(player.carry == part and part.get_parent().name == "Carry", "E → 부품을 듦 (carry %s)" % [player.carry != null])
	await _shot("74_carry")
	# 느린 걸음: 북쪽(정거장 앞 직선)으로 W. 30프레임 뒤 1초 이동 = 걷기 × 배율
	player.rotation.y = YAW_OF[0]
	head.rotation.x = 0.0
	_inject_key(KEY_W, true)
	_inject_key(KEY_SHIFT, true)                                   # 들고는 Shift 를 눌러도 못 달린다 (#34)
	await _wait(30)
	var p0: Vector3 = player.global_position
	await _wait(60)
	var v: float = player.global_position.distance_to(p0)
	_inject_key(KEY_W, false)
	_inject_key(KEY_SHIFT, false)
	var want: float = Tuning.WALK_SPEED * Tuning.CARRY_SPEED_MUL
	_check(Tuning.CARRY_SPEED_MUL < 0.99 and absf(v - want) <= want * 0.1 and player.stance != "run", "들고 걷기(Shift 눌러도) %.2f m/s = %.2f ±10 %% (배율 %.1f, 자세 %s)" % [v, want, Tuning.CARRY_SPEED_MUL, player.stance])
	# 고장 앞으로 순간이동: Socket 위치에서 통로 쪽으로 1.5 m, 기둥 자리를 본다
	var fault: Node3D = fd.faults[0]
	var socket: Node3D = fault.get_node("Socket")
	var wall_dir: Vector3 = (socket.global_position - fault.global_position)
	wall_dir.y = 0.0
	wall_dir = wall_dir.normalized()
	var stand: Vector3 = socket.global_position + (-wall_dir) * 1.9      # 소켓 반지름 2.5 안, 갓보(4.8 m)가 화면에 들게 뒤로
	stand.y = fault.global_position.y
	var look := 0
	for f in 4:
		if DIR3[f].dot(wall_dir) > 0.9:
			look = f
	_stand_at(player, head, stand, look)
	head.rotation.x = deg_to_rad(55.0)                              # 기운 갓보·빠진 기둥이 원 안에
	await _wait(20)
	await _shot("73_fault")
	await _tap(KEY_E)
	await _wait(5)
	_check(fault.state == "socketed" and fault.post_visible() and player.carry == null, "고장 앞 E → 부품 세움 (기둥 보임 %s, state %s)" % [fault.post_visible(), fault.state])
	await _shot("75_socket")
	# E 홀드
	var danger0: float = player.danger
	_inject_key(KEY_E, true)
	await _wait(60)
	_check(fault.repairing and fault.progress > 0.0 and player.repair_target == fault, "E 홀드 60프레임 → 진행 %.2f > 0" % fault.progress)
	# 첫 스킬체크: 바늘이 구간 밖일 때 스페이스 → 실패
	for _k in 600:
		if fault.skill_active:
			break
		await _wait(1)
	_check(fault.skill_active, "스킬체크가 10초 안에 떴다")
	for k in 5:
		await _grab()
		await _wait(6)
	_flush_burst("76_skillcheck")
	for _k in 200:
		if fault.skill_active and not fault.in_zone() and fault.needle > 5.0:
			break
		await _wait(1)
	var prog_before: float = fault.progress
	var fails0: int = fault.fails
	var nz_fail: int = NoiseBus.total
	await _tap(KEY_SPACE)
	await _wait(6)                                                 # 주입한 키는 다음 물리 프레임에 먹는다 — 2 프레임은 모자랐다 (#31 에서 한 번 헛돌았다)
	var fail_noise := _noise_kind(NoiseBus.since(nz_fail), "repair_fail")
	_check(Tuning.NOISE_REPAIR_FAIL > Tuning.NOISE_PICK and fail_noise.size() == 1 and fail_noise[0]["radius"] == Tuning.NOISE_REPAIR_FAIL,
		"실패 → 큰 소음 1회 (실제 %d), 반경 %.0f > 곡괭이 %.0f (#32)" % [fail_noise.size(), Tuning.NOISE_REPAIR_FAIL, Tuning.NOISE_PICK])
	_check(Tuning.REPAIR_FAIL_BACK > 0.05 and Tuning.DANGER_REPAIR_FAIL > 0.5 and fault.fails == fails0 + 1
		and fault.progress <= maxf(prog_before - Tuning.REPAIR_FAIL_BACK + 0.02, 0.0) + 0.001
		and is_equal_approx(player.danger, danger0 + Tuning.DANGER_REPAIR_FAIL),
		"구간 밖 스페이스 → 실패: 진행 %.2f → %.2f (−%.2f), 게이지 %.0f → %.0f (+%.0f)" % [prog_before, fault.progress, Tuning.REPAIR_FAIL_BACK, danger0, player.danger, Tuning.DANGER_REPAIR_FAIL])
	var danger_after_fail: float = player.danger
	# 성공: 바늘이 구간 안일 때만 스페이스. 12초 + 후퇴분 → 최대 40초
	for _k in 2400:
		if fault.state == "done":
			break
		if fault.skill_active and fault.in_zone():
			await _tap(KEY_SPACE)
		await _wait(1)
	_inject_key(KEY_E, false)
	await _wait(5)
	_check(Tuning.DANGER_REPAIR_DONE > 0.5 and fault.state == "done" and fault.fails == fails0 + 1 and absf(fault.cap_tilt_deg()) < 0.01
		and is_equal_approx(player.danger, danger_after_fail - Tuning.DANGER_REPAIR_DONE),
		"구간 안 스페이스로 끝까지 → 수리 완료 (실패 %d, 갓보 %.1f°, 게이지 %.0f → %.0f, −%.0f)" % [fault.fails - fails0, fault.cap_tilt_deg(), danger_after_fail, player.danger, Tuning.DANGER_REPAIR_DONE])
	await _shot("77_repaired")
	_check(fault.zone_deg == Tuning.SKILL_ZONE_DEG and fault.part_quality == "creaky", "삐걱 부품 고장: 구간 %.0f° = %.0f" % [fault.zone_deg, Tuning.SKILL_ZONE_DEG])
	# 자재함 (#31): 광석 ORE_PER_PART → E → 좋은 부품 → 둘째 고장에 세워 넓은 링
	_stand_at(player, head, bin.global_position + Vector3(-1.6, 0.0, 0.0), 1)
	head.rotation.x = deg_to_rad(-15.0)
	player.add_ore(Tuning.ORE_PER_PART)
	await _wait(20)
	await _shot("78_bin")
	await _tap(KEY_E)
	await _wait(5)
	var good: Node3D = bin.parts[bin.parts.size() - 1] if bin.parts.size() >= 2 else null
	_check(good != null and good.quality == "good" and player.ore_count == 0 and Tuning.ORE_PER_PART > 0,
		"광석 %d → E → 좋은 부품 (품질 %s, 남은 광석 %d)" % [Tuning.ORE_PER_PART, good.quality if good != null else "-", player.ore_count])
	_stand_at(player, head, bin.global_position + Vector3(-2.8, 0.0, 0.0), 1)   # 한 걸음 물러나 밝은 통나무(자재함 앞 1.2 m)를 내려다본다
	head.rotation.x = deg_to_rad(-35.0)
	await _wait(10)
	await _shot("79_part_good")
	await _tap(KEY_E)
	await _wait(10)
	var fault2: Node3D = fd.faults[1]
	var socket2: Node3D = fault2.get_node("Socket")
	var wd2: Vector3 = socket2.global_position - fault2.global_position
	wd2.y = 0.0
	wd2 = wd2.normalized()
	var stand2: Vector3 = socket2.global_position + (-wd2) * 1.9
	stand2.y = fault2.global_position.y
	var look2 := 0
	for f in 4:
		if DIR3[f].dot(wd2) > 0.9:
			look2 = f
	_stand_at(player, head, stand2, look2)
	head.rotation.x = deg_to_rad(30.0)
	await _wait(20)
	await _tap(KEY_E)
	await _wait(5)
	_check(fault2.state == "socketed" and fault2.zone_deg == Tuning.SKILL_ZONE_GOOD_DEG and fault2.int_min >= Tuning.SKILL_INTERVAL_GOOD_MIN - 0.01 and fault2.part_quality == "good",
		"좋은 부품 세움 → 구간 %.0f° = %.0f, 간격 ≥ %.0f s" % [fault2.zone_deg, Tuning.SKILL_ZONE_GOOD_DEG, Tuning.SKILL_INTERVAL_GOOD_MIN])
	_inject_key(KEY_E, true)
	for _k in 700:
		if fault2.skill_active:
			break
		await _wait(1)
	_check(fault2.skill_active, "좋은 부품 스킬체크가 %.0f초 안에 떴다" % (Tuning.SKILL_INTERVAL_GOOD_MAX + 2.0))
	for k in 5:
		await _grab()
		await _wait(6)
	_flush_burst("80_skill_wide")
	_inject_key(KEY_E, false)
