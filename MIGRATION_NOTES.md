# MIGRATION_NOTES — Godot 프로토타입의 실제 상태 (Unity 이전용)

이 문서 하나로 새 Unity 프로젝트 세션에 맥락을 넘기는 것이 목표다.
**사실만 적었다.** 추측·개선 제안은 넣지 않았다. 확인하지 못한 것은 "확인 불가" 또는 "문서상 불명확"으로 적었다.

- 조사 기준: 2026-09-14, `C:\Users\anjyo\Tunnel\new-game` 작업 폴더 (Godot 4.7.2, Forward Plus, Jolt Physics)
- 인용 약어: **H** = `docs/HANDOFF.md`, **C** = `CLAUDE.md`. `H:123` = 그 파일 123번째 줄
- 커밋 기록: HANDOFF가 말하는 "커밋함 / 커밋 안 함"은 **옛 git 히스토리(커밋 130개, 저장소 밖 로컬 백업)** 기준이다. 이 저장소는 커밋 0개에서 새로 시작했다
- 룩·렌더링·조명 값은 [`LOOK_REFERENCE.md`](LOOK_REFERENCE.md)에 따로 있다

## 목차
1. 구현된 기능 목록
2. `.gd` 파일별 역할
3. 씬 구조
4. 에셋 목록
5. 에셋 생성 파이프라인 (괴물 `tools/miner/` · 갱도 `tools/minetunnel/`)
6. Godot 고유 기능 의존 부분
7. 미해결 문제
8. `Tuning.gd` 수치 전체

---

## 1. 구현된 기능 목록

**표시 기준**
- **완성**: 코드가 동작하고, 봇 검사가 있고, HANDOFF에 사용자 플레이(F5) 통과 기록이 있다
- **부분**: 동작하지만 F5 판정이 대기·불명확이거나, CLAUDE.md §15 설계 중 일부만 만들어졌다
- **껍데기만**: 코드 경로나 이름만 있고 실제로는 동작하지 않는다

| 기능 | 표시 | 있는 것 | 근거 · 빠진 것 |
|---|---|---|---|
| 1인칭 이동 | 부분 | 숙이기 2.0 / 걷기 4.5 / 달리기 7.0 m/s, 점프, 스태미나(화면 표시 없음), 탈진 | 봇 +17 (H:228). F5 판정 문서상 불명확 (H:229). 부품을 들거나 광차를 탄 동안 못 달림 (C:434) |
| 헤드램프 | 부분 | SpotLight3D 하나, F로 끄기, 끈 뒤 4초 눈 적응, 괴물 낙하 순간 정전 | #58 정전 F5 "확실히 괜찮았다" (H:7). #32 눈 적응 뒤 F5는 불명확 (H:223). 켜고 끄는 소리 없음 (H:234) |
| 채굴 | 완성 | 곡괭이 뷰모델, 옆벽 광맥 포켓을 두 번 치면 광석이 굴러 나옴, 자석으로 줍기, "철 N" HUD | #23 F5 "확인했다" (H:299). 광물은 철 하나 (H:912). 채굴 소리 없음 (H:913). 판 사이 광석 유지는 미구현 (H:712) |
| 곡괭이 던지기 | 부분 | 포물선 투척, 착지 소음(유인), 괴물 스턴 1.5초, E로 줍기 | 봇 검사 있음 (H:228, H:214). F5 판정 불명확. 사거리 8 m (H:229) |
| 리프트 | 완성 | 케이지 하강·상승, 옆 여닫이 문 2짝(코드 회전), 문이 닫힌 뒤 출발 | #21 "케이지 좋다, 문 OK" (H:617), #22 "문도 OK" (H:317). 층이 2개라 한 번만 내려감 |
| 갱도 조립기 | 부분 | 시드로 층당 245 m(35×35칸) 미로, 조각 13종, 소품 무더기, 설비(케이블·풍관·배수로·갓등·배관), 층 2개(시드 7·8) | #27 F5 대기 (H:272). 펌프장·갱목 구간 조각 없음 (C:432). 위층은 임시 미로 (C:428). 곡선·갈림에서 설비 끊김 (H:254) |
| 광차 | 부분 | 순환선 Path3D 위 3대, 8 m/s, 정거장 앞 6초 정차, E로 타고 내리기 | 봇 +4 (H:246). F5 판정 불명확. 종점 광차 없음, 서로 안 피함, 소리 없음 (H:248) |
| 정비 | 부분 | 지지목 고장(층당 4), 자재함에서 부품(광석 5개 = 좋은 부품 / 없으면 삐걱 부품), 나르기·세우기, E 누르고 있기 + 스킬체크, 실패 게이지 +15 / 성공 −5 | 봇 +7·+5 (H:243, H:239). F5 판정 불명확. 고장은 지지목 1종만, 배수관·가스는 없음 (H:705) |
| 위험 게이지 · 붕괴 · 사망 | 부분 | 게이지 0~100, 100이면 붕괴 연출 후 현재 씬 재시작, 괴물에게 잡혀도 사망 | 봇 8 (H:483). **설계의 공유 게이지(상한 100 + 60×(n−1))는 코드에 없음** — `DANGER_MAX` 100 고정 (C:437). 복귀 정산 미착수 (H:917) |
| └ 곡괭이·리프트로 게이지 오르기 | 껍데기만 | `Miner.gd:54` `add_danger(DANGER_PER_HIT)`, `Lift.gd:94` 경로가 남아 있음 | 값이 `DANGER_PER_HIT`·`DANGER_PER_DROP` = 0 (#24 규칙: 오르는 원인은 수리 실패뿐, C:439) |
| 소음 | 부분 | `NoiseBus` 오토로드: 곡괭이 25 · 정비 실패 40 · 발걸음 6 · 광차 20 m 반경, 왼쪽 아래 원 HUD | 봇 +9 (H:233). **소리 파일 0개** (H:706) |
| 갱도 괴물 AI | 부분 | `Stalker` 한 마리/층. 감각 셋(귀·눈·빛), 상태 14개(hidden·wander·investigate·search·alert·chase·retreat·stun·catch·drop·climb·hang·fall·land), 격자 BFS 길찾기, 벽·천장 기어가기, 천장 추격 6.5 m/s, 천장 낙하 + 노려보기(#59) | #49·#51·#52~#55 통과 (H:144, H:46). #57 어색 (H:30). **#59 F5 대기** (H:6). #61 검사 FAIL (H:12) |
| 감독 | 부분 | `Director` 한 개/층. 압박 0~100, 80에서 시야 밖 곡선 칸에 등장, 20 밑이면 철수, 배움 카드 2장(어둠 수색·광차 들여다보기) | #35 F5 1차 "무서운가·수치 판정은 아직" (H:200). 설계 카드 5장 중 3장 없음 (C:461-462, H:716) |
| 괴물 모델 · 애니메이션 | 부분 | `miner_rigged.glb` (TRELLIS.2 몸 + 머리, Mixamo 리깅, 클립 14개), 손 접지 IK(`ArmGround`), 척추 굽힘(`SpineGlare`) | #36 "안 무섭다" (H:217) → #42 통과 (H:195) → #45 몸 교체 F5 대기 (H:183). 텍스처 확정은 보류 (H:198). 몸에 노멀·러프니스 텍스처 없음 (LOOK_REFERENCE §6-5) |
| └ `climb_up`·`climb_down` 클립 | 껍데기만 | GLB에 들어 있음 | 코드가 쓰지 않음, 벽은 `crawl` 클립으로 오르내림 (H:154) |
| 템플릿 메뉴 → 게임 | 부분 | 오프닝 → 메인 메뉴 → 새 게임 → `Tunnel.tscn`, 옵션·크레딧 창 (Maaack 템플릿) | `project.godot:14,160`. **일시정지 메뉴는 연결 안 됨** (H:909, 코드로 확인) |
| 개발 봇 · 빌드 검사 | 부분 | `DevBot` 오토로드(숫자 검사·입력 주입 봇·캡처), `build.sh`(임포트 → 소스 검사 → exe → 배포물 검사 → 봇 → 화면 검수), `quick.sh` 구간 실행, `qc.py` 골든 비교 | 마지막 기록 #59 후 FAIL 1 (#61) (H:3). 골든 기준 이미지 `tools/qc_golden/`은 저장소에 없음(로컬 백업) |
| 영상 촬영 `--film` | 완성 | `--write-movie`와 함께 cart·maze·lamp·services·walk_room·walk_tunnel 변형 촬영 | 검사가 아닌 촬영 도구 (H:349, DevBot.gd:273-285) |
| 오디오 | 없음 | — | 저장소 전체에 소리 파일 0개 |
| 협동(최대 4인) | 없음 | — | 순서표 ⑤ 뒤 (H:721) |
| 맨 위 층·검수대·계약·시신·파쇄장·동물·상점·결말 | 없음 | — | 순서표 ②④⑤⑦c⑨⑪⑩ 미착수 (H:712-719) |

---

## 2. `.gd` 파일별 역할

게임 코드 `scripts/` 31개. 템플릿 코드(`addons/`) 81개는 제외했다.
붙는 곳은 네 종류다: **씬**(`.tscn`에 붙음) · **오토로드** · **코드**(다른 스크립트가 `set_script`/`.new()`로 붙임) · **정적**(`class_name` 상수·함수만 씀).

| 파일 (줄) | 하는 일 | 붙는 곳 |
|---|---|---|
| `Tuning.gd` (464) | 모든 밸런스·연출 수치(상수 339개). 다른 스크립트는 상수를 직접 쓰지 않고 여기서 읽는다. 전체 값은 8절 | 정적 `class_name Tuning` |
| `Player.gd` (461) | 1인칭 이동·마우스 시점·점프·세 자세·스태미나, 헤드램프 설정과 끄기/정전, 광석 수, 위험 게이지, 붕괴·잡힘 사망, 부품 들기, 광차 타기, 곡괭이 던지기, 흔들림 | 씬 `Player.tscn` 루트 `CharacterBody3D` |
| `Miner.gd` (58) | 카메라 정면 레이로 닿은 광맥 포켓을 친다. 곡괭이 `struck` 시그널을 받아 타격 | 씬 `Player.tscn` `Head/Camera3D/MineRay` (RayCast3D) |
| `Pickaxe.gd` (65) | 화면에 들린 곡괭이 뷰모델. 휘두르기는 위치·회전을 코드로 흔든다. 머리가 벽에 닿는 순간 `struck` | 씬 `Pickaxe.tscn` 루트 (Player 카메라 밑) |
| `ThrownPick.gd` (89) | 던져진 곡괭이 강체. 첫 착지에 큰 소음, 괴물에 닿으면 스턴, E로 회수 | 코드 `Player.gd:372` `ThrownPick.new()` |
| `OrePocket.gd` (86) | 옆벽 광맥 포켓. 두 번 치면 자갈·먼지를 튀기고 광석을 굴려 보낸다 | 씬 `OrePocket.tscn` 루트 `StaticBody3D`, `PocketSpawner`가 배치 |
| `PocketSpawner.gd` (62) | 조립된 조각의 빈 노드 `SLOT_Pocket_*`를 읽어 확률로 포켓을 붙인다. 층마다 최소 1 | 씬 `Tunnel.tscn` `Pockets` |
| `Ore.gd` (55) | 광석 한 덩이 강체. 시간이 지나도 안 사라짐, 주우면 삭제. (머리 주석의 "MinableBlock이 만든다"는 옛 설명 — 실제 호출은 `OrePocket.gd:85`) | 씬 `Ore.tscn` 루트 `RigidBody3D`, 정적 `Ore.spawn` |
| `WallChunk.gd` (68) | 자갈·돌 조각 강체(장식). 수명·상한 40. (머리 주석의 MinableBlock은 옛 설명 — 호출은 `OrePocket.gd:66`, `Player.gd:190` 붕괴 돌) | 정적 `WallChunk.spawn` |
| `Dust.gd` (20) | 한 번 터지고 사라지는 먼지 파티클 | 씬 `Dust.tscn` 루트 `GPUParticles3D`, 정적 `Dust.burst` (OrePocket·Player·Stalker) |
| `Lift.gd` (108) | 리프트 케이지. E → 문 닫힘 → 아래층까지 이동 → 문 열림. `AnimatableBody3D` + sync_to_physics라 위에 선 플레이어를 실어 나름. 문은 glTF 노드 `CAGE_GateL/R` 회전 | 씬 `Lift.tscn` 루트 |
| `MineAssembler.gd` (1481) | 층 조립기. 층마다 35×35 격자에 순환선·지선·횡갱·고리·채탄구역·방·대피소를 짜고 조각 glTF로 놓는다. 이음새 칼라·크립 속 바위·설비 메시(SurfaceTool)·소품·광차·고장·자재함·괴물·감독 배치. 격자 BFS `grid_path` | 씬 `Tunnel.tscn` `Layers` |
| `PieceCatalog.gd` (74) | 조각 카탈로그 표: glTF 파일, 칸 크기, 네 면 종류(아치 A / 문 D / 막힘 X) | 정적 |
| `MineCart.gd` (72) | 광차 하나. 순환선 위를 돌고 정차, E로 타고 내림. 달리면 소음 | 코드 `MineAssembler.gd:1256` `set_script` (`PathFollow3D`) |
| `Fault.gd` (147) | 고장난 지지목(broken → socketed → done). 누르고 있기 진행 + 스킬체크, 실패 +게이지·흔들림, 성공 −게이지. 시그널 `repaired`, `failed` | 코드 `MineAssembler.gd:1334` `set_script` |
| `RepairPart.gd` (16) | 부품 통나무. 품질 `creaky`/`good`. E로 줍기 | 코드 `PartsBin.gd:56` `set_script` |
| `PartsBin.gd` (63) | 자재함. E마다 부품 하나, 광석 5개 이상이면 광석을 빼고 좋은 부품 | 코드 `MineAssembler.gd:1390` `set_script` |
| `Stalker.gd` (957) | 괴물 몸통 AI. 감각 셋, 상태 14개, 붙는 면(점 + 법선)으로 바닥·벽·천장 통일, 격자 길, 천장 낙하·노려보기. 시그널 `state_changed`, `caught_player` | 코드 `MineAssembler.gd:1407` `Stalker.new()` (`CharacterBody3D`), 몸은 `Miner.tscn` 인스턴스 (`Stalker.gd:79`) |
| `Director.gd` (135) | 감독. 압박 0~100을 세어 괴물 등장·철수를 정하고, 플레이어 버릇을 세어 배움 카드 2장을 켠다 | 코드 `MineAssembler.gd:1412` `Director.new()` |
| `MinerBody.gd` (218) | 괴물 모델 래퍼. GLB의 AnimationPlayer에서 클립 재생(`play`), 반복 클립 설정, 섞는 시간, IK 모디파이어 부착 | 씬 `Miner.tscn` 루트 `Node3D` |
| `ArmGround.gd` (176) | 기는 클립에서 손이 바닥을 뚫는 것을 2뼈 IK로 올림. 천장 낙하 때 팔 뻗기 모드 | 코드 `MinerBody.gd:38` (`SkeletonModifier3D`) |
| `SpineGlare.gd` (128) | #59 천장 노려보기. 엉덩이·척추를 굽혀 상체를 들고 목·머리를 플레이어 눈으로, 숨쉬기·고개 갸웃 | 코드 `MinerBody.gd:34` (`SkeletonModifier3D`, ArmGround보다 먼저) |
| `Atmosphere.gd` (268) | 실행 중 재질 교체(벽·바닥 → 젖은 바위 셰이더, 갱목 색, KayKit 팔레트), 환경 안개·볼류메트릭 안개·색 보정 적용, 비네트 후처리 레이어, 눈 적응 트윈 | 오토로드 |
| `NoiseBus.gd` (28) | 소음 이벤트 버스. `make()`로 알리고 시그널 `made`로 뿌림. 로그를 봇·괴물이 읽음 | 오토로드 |
| `DevBot.gd` (4349) | 개발용 자동 실행. 실행 인자 `--check`/`--play`/`--only`/`--shot`/`--seams`/`--tour`/`--texcmp`/`--mapdump`/`--film`. 인자가 없으면 아무것도 안 함 | 오토로드 |
| `OreHud.gd` (17) | 왼쪽 아래 "철 N" | 씬 `OreHud.tscn` 루트 `CanvasLayer` (Player 안 `Hud`) |
| `DangerHud.gd` (26) | 오른쪽 아래 위험 게이지 바, 색 3단계 | 씬 `DangerHud.tscn` (Player 안) |
| `DeathScreen.gd` (24) | 붕괴·잡힘 때 검은 화면과 글자 (layer 10) | 씬 `DeathScreen.tscn` (Player 안) |
| `RepairHud.gd` (44) | 수리 진행 바와 스킬체크 링. `_draw`로만 그림 | 씬 `Player.tscn` `RepairHud` (CanvasLayer) |
| `NoiseHud.gd` (44) | 마지막 소음 반경 원. `_draw`로만 그림 | 씬 `Player.tscn` `NoiseHud` |
| `DebugHud.gd` (80) | 개발용 괴물 표시(압박·상태·거리·카드), 숫자 9 즉시 등장 · 8 정지 · 0 끔. 배포물(release)에서는 스스로 삭제 | 씬 `Player.tscn` `DebugHud` |

---

## 3. 씬 구조

### 3-1. 게임 진입
`project.godot`: 시작 씬 `addons/scenes/opening/opening.tscn` → 메인 메뉴 `addons/scenes/menus/main_menu/main_menu.tscn` → 새 게임 `scenes/level/Tunnel.tscn` (`[maaacks_game_template] game_scene_path`). 사망하면 `SceneLoader.reload_current_scene` (`Player.gd:110,133`).

### 3-2. `scenes/level/Tunnel.tscn` (본 게임)
```
Tunnel (Node3D)
├── WorldEnvironment            Environment_tunnel (값은 LOOK_REFERENCE §4)
├── Stations (Node3D)
│   ├── Station_top             shaft_station.gltf
│   ├── Station_bottom          shaft_station.gltf
│   └── Pit                     shaft_pit.gltf
├── Lift                        Lift.tscn
├── Collision (StaticBody3D)    정거장·수갱 충돌 상자 14개 (Floor, WallL/R, StripL/R, ShaftL/R/Back/FrontMid/FrontSump, SumpFloor, Floor_B, WallL_B/R_B)
├── Layers (Node3D)             MineAssembler.gd — 실행 중 층을 만든다 (아래 3-3)
├── Pockets (Node3D)            PocketSpawner.gd — Layers 다음이어야 함 (조각이 먼저 놓여야 자리를 읽음)
└── Player                      Player.tscn
```

### 3-3. 실행 중 `Layers` 아래에 만들어지는 것 (`MineAssembler.gd`)
```
Layers
└── Floor_<i> (Node3D, y = 층 높이)          _place() :519
    ├── <조각 인스턴스들>                       PieceCatalog의 glTF, 칸 가운데, rotation.y만 90° 단위 (_spawn :633)
    ├── Props        X_<n>_<종류>              소품 (mine_props.gltf의 PROP_* 노드 복제) :671
    ├── Collars      C_<x>_<y>_<면>            조각 이음새 바위 칼라 :786
    ├── CribFill     K_<x>_<y>_<n>             크립(통나무 기둥) 속 바위 :872
    ├── Services     S_<x>_<y>_<변형>          설비 메시 (SurfaceTool로 생성) :916
    ├── Carts
    │   └── RailPath (Path3D)
    │       └── Cart_<k> (PathFollow3D, MineCart.gd)
    │           ├── Model
    │           └── Board (Area3D)
    ├── Faults
    │   └── Fault_<k> (Fault.gd)
    │       ├── Socket (Area3D)
    │       └── Broken                          부러진 기둥 (PROP_post)
    ├── Parts                                   자재함이 만든 부품이 놓임
    ├── Bin (PartsBin.gd) ─ Body, Lid, Reach (Area3D)
    ├── Stalker (CharacterBody3D, Stalker.gd) ─ Miner.tscn 인스턴스
    └── Director (Director.gd)
```
조각 안에는 코드가 이름으로 찾는 노드가 있다: `SLOT_Pocket_*`(포켓 자리), `TMB_straight_<n>_post_R`·`TMB_straight_<n>_cap`(고장 지지목, `Fault.gd:36-37`), `SHL_*`(이음새 껍데기, `MineAssembler.gd:808`), `PROP_*`(소품 원본, `:663`).

### 3-4. `scenes/player/Player.tscn`
```
Player (CharacterBody3D, Player.gd)      캡슐 0.4 × 1.8 m, 눈높이 1.7 m (H:343)
├── Collider
├── Head (Node3D)
│   ├── Camera3D                         fov 80
│   │   ├── Pickaxe                      Pickaxe.tscn
│   │   ├── Carry (Node3D)               든 부품 자리
│   │   └── MineRay (RayCast3D, Miner.gd) 정면 3 m, mask 4
│   └── Headlamp (SpotLight3D)           속성은 코드에서 넣음, top_level
├── Magnet (Area3D)                      광석 줍기, mask 8
├── Hud                                  OreHud.tscn
├── DangerHud                            DangerHud.tscn
├── DeathScreen                          DeathScreen.tscn
├── RepairHud (CanvasLayer, RepairHud.gd)
├── NoiseHud (CanvasLayer, NoiseHud.gd)
└── DebugHud (CanvasLayer, DebugHud.gd)
```

### 3-5. 나머지 씬
| 씬 | 트리 |
|---|---|
| `scenes/level/Lift.tscn` | Lift (AnimatableBody3D, Lift.gd) ─ Mesh(lift_cage.gltf), Deck, RailSouth/East/West, Roof, Gate(충돌), Riders(Area3D) |
| `scenes/level/Miner.tscn` | Miner (Node3D, MinerBody.gd) ─ miner_rigged(miner_rigged.glb) |
| `scenes/level/OrePocket.tscn` | OrePocket (StaticBody3D, OrePocket.gd) ─ Mesh(ore.gltf), Collider |
| `scenes/level/Ore.tscn` | Ore (RigidBody3D, Ore.gd) ─ Mesh(ore.gltf), Collider |
| `scenes/player/Pickaxe.tscn` | Pickaxe (Node3D, Pickaxe.gd) ─ Mesh(pick.gltf) |
| `scenes/fx/Dust.tscn` | Dust (GPUParticles3D, Dust.gd) |
| `scenes/ui/OreHud.tscn` | Hud (CanvasLayer, OreHud.gd) ─ Label |
| `scenes/ui/DangerHud.tscn` | DangerHud (CanvasLayer) ─ Bar(ProgressBar) |
| `scenes/ui/DeathScreen.tscn` | DeathScreen (CanvasLayer) ─ Black(ColorRect) ─ Label |
| `scenes/level/TestRoom.tscn` | 옛 시험 방. KayKit 바닥·벽 타일, Player, OrePocket, Lift. 지금은 `DevBot --film walk_room`만 씀 (DevBot.gd:281) |

---

## 4. 에셋 목록

| 위치 | 파일 수 · 용량 | 내용 | 용도 |
|---|---|---|---|
| `assets/generated/tunnel/` | 151개 · 49.9 MB | glTF 23개: 조각 `piece_{straight,curve,t,cross,neck,cap,refuge,room_1,room_2}`, 레일 `rail_{straight,curve,turnout,end}`, `shaft_station`, `shaft_pit`, `lift_cage`, `mine_cart`, `mine_face`(끝막이), `mine_chips`(자갈), `mine_props`(소품 9종), `mine_tunnel_module`, `ore`, `pick` | 갱도 전체, 리프트, 광차, 곡괭이, 광석 |
| `assets/generated/tunnel/textures/` | (위에 포함) | Poly Haven CC0: `rock_face_04`(벽), `brown_mud_rocks_01`(바닥), `dark_rock_02`(바위), `dark_wooden_planks`(갱목), `rusty_metal_02`(녹슨 철) — Diffuse / nor_gl / Rough. 소품 6종(wooden_crate_01, wooden_barrels_01, wooden_bucket_01, sledgehammer_01, rusted_spade_01, vintage_oil_lamp) — diff / nor_gl / arm, 1K | 갱도·소품 재질 |
| `assets/generated/monster/` | 18개 · 25.5 MB | `miner_rigged.glb` (16.1 MB, 클립 14개), 추출 텍스처 `_Image_0.webp`·`_Image_0_1.webp`(살), `_timber_*`, `_iron_*`, 그리고 참조가 확인되지 않은 `_miner_skin_albedo.jpg`·`_miner_skin_normal.png` | 괴물 |
| `assets/generated/palette/` | 2개 | `dungeon_texture.png` (KayKit 팔레트 사본, `tools/palette.py`) | 리프트 옛 판·TestRoom·KayKit 재질 |
| `assets/kaykit/dungeon/` | 636개 · 5.9 MB (glTF 211) | KayKit Dungeon Pack 1.1 FREE | `TestRoom.tscn` 바닥·벽만 사용 |
| `assets/kaykit/resourcebits/` | 231개 · 3.5 MB (glTF 76) | KayKit Resource Bits | 게임 코드·씬에서 참조 없음 |
| `assets/kaykit/rpgtools/` | 156개 · 1.2 MB (glTF 49) | KayKit RPG Tools Bits | 게임 코드·씬에서 참조 없음 |
| 괴물 애니메이션 클립 | GLB 안 14개 | `idle_crouch`, `walk_crouch`, `crawl`, `run`, `attack_swipe`, `hit`, `death`, `roar`, `prone_down`, `run_stand`, `climb_up`, `climb_down`, `fall_air`, `land_hard` (`MinerBody.gd:8-9`). 반복: idle_crouch·walk_crouch·crawl·run. 원본은 Mixamo FBX | 괴물 |
| 셰이더 | 2개 | `shaders/wet_rock.gdshader`(젖은 바위), `shaders/post.gdshader`(비네트·그레인) | LOOK_REFERENCE §4, §6-3 |
| **사운드** | **0개** | — | 없음 |
| 저장소 밖 원본 | — | `Documents/MineTunnel/*.blend` (MineTunnel, Shaft, Cage, Pick, Face, Pieces, Props, Cart), `Documents/MineTunnel/blender/mixamo/*.fbx`, `Documents/MineTunnel/mesh/*.glb`, 컨셉 그림, `Documents/MineTunnel/MINER_ASSET_PIPELINE.md` | 5절 파이프라인의 입력 |

---

## 5. 에셋 생성 파이프라인

Unity에서 FBX를 다시 뽑을 때 쓰는 순서다. 스크립트 사본은 저장소의 `tools/`에 있고, 원본은 저장소 밖 `Documents/MineTunnel/`에 있다.
사본과 원본의 차이: `tools/miner/clean_watermark.py`, `tools/minetunnel/build_tunnel.py`, `tools/minetunnel/export_godot.py`가 원본과 다르다. `export_godot.py`는 헤드리스용으로 고친 사본이다 (H:541-543).

### 5-1. 괴물 — `tools/miner/`

**지금 `assets/generated/monster/miner_rigged.glb`를 만든 순서** (#45 → #47 → #48)

1. 컨셉 그림(사용자, Gemini) → `clean_watermark.py` → `miner_front_Tpose_clean.png`
2. `gen_trellis2.py` — Hugging Face Space `microsoft/TRELLIS.2`로 이미지 → PBR GLB, `mesh/trellis2_v1.glb` (1024, 74 s, 28만 면) (H:187)
3. 머리 `mesh/trellis2_head_512.glb` 생성 (69 s) (H:185). 입력 이미지는 문서상 불명확
4. `stage11_body.py` (Blender 헤드리스) — TRELLIS 몸 + 머리 + 갱목 부착 → `miner_v3_stage11.blend`, `miner_body_for_mixamo.fbx` (H:185)
5. **[수동] Mixamo 리깅 — 사용자가 직접** (H:184)
6. **[수동] Mixamo 클립 받기** — With Skin(#45), Without Skin·In Place(#47·#48) → `Documents/MineTunnel/blender/mixamo/*.fbx` (H:177, H:182, H:184)
7. (클립 고르기용) `review_clips.py` → 후보 21개 시트 (H:183)
8. `stage5_merge.py` — Mixamo 클립을 리그 하나로 합침 → `mesh/miner_rigged.glb`
   - 기준 FBX `Crouch Idle`(With Skin)에서 리그·메시를 가져오고, 나머지 FBX는 액션만 남긴다 (:28, :87-103)
   - FBX 파일 이름을 Godot 클립 이름으로 바꾼다 (`CLIP_SETS` A/B, 지금 B) (:17-25)
   - Hips 위치의 선형 이동을 빼서 제자리 클립으로 만든다. `prone_down`·`land_hard`는 y를 남긴다 (:70-83)
   - `BODY_FROM_BLEND`이면 Mixamo 몸 대신 stage11 텍스처 몸을 쓰고 가중치를 NEAREST로 옮긴다 (:132-157)
   - 갱목을 본에 부모 (:29-37, :167-175). 클립마다 NLA 트랙 하나로 glTF 내보내기 (:200-218)
9. `stage6_material.py` — `SKIN_KEEP=1`(기본)이면 살 재질은 거칠기 1·금속 0만 적용. 갱목 `rough_wood`, 못 `rusty_metal_02` (Poly Haven) → GLB (H:185, stage6_material.py:32, :199-200)
10. **[수동 복사]** `Documents/MineTunnel/mesh/` → `assets/generated/monster/` (H:218). 복사 스크립트는 없다
11. #47: `prone_down` 클립 추가 후 stage5_merge 재실행 (H:182). #48: 클립 5개(`climb_up`, `climb_down`, `fall_air`, `land_hard`, `run_stand`) 추가 후 재실행 (H:177). 이 뒤에 stage6도 다시 돌렸는지는 문서상 불명확

**stage 파일별 역할**

| 파일 | 하는 일 | 쓰는 경로 |
|---|---|---|
| `stage4_build.py` | 옛 Hunyuan 몸 GLB → 키 2.5 m → 리토폴 → 갱목 → Mixamo용 FBX | 옛 경로 |
| `stage5_merge.py` | Mixamo 클립 합치기 + 제자리화 + 갱목 부모 → `miner_rigged.glb` | **현재** |
| `stage5b_retarget.py` | 새 몸(머리·손 교체본)을 기존 리그에 가중치 이식. 재리깅 없음 | 옛 경로 (#41·#42) |
| `stage6_material.py` | 재질: 컨셉 투영 베이크(`SKIN_KEEP=0`일 때), 갱목·못 텍스처 → GLB | **현재** (`SKIN_KEEP=1`) |
| `stage7_bake.py` | `export`: 저폴리 몸 내보내기 / `bake`: paint 색 + 고폴리 노멀 굽기 → GLB | 옛 경로 (#40) |
| `stage8_head.py` | 따로 생성한 머리를 목에 붙임 | 옛 경로 (#41) |
| `stage9_hand.py` | 따로 생성한 손을 손목에 붙임 + 발톱 날카로움 검사 | 옛 경로 (#42) |
| `stage10_torso.py` | 몸통 요철을 Shrinkwrap으로 옮김 | 옛 경로 (#43) |
| `stage11_body.py` | TRELLIS.2 몸으로 통째 교체 + TRELLIS 머리 + 갱목 → Mixamo용 FBX | **현재** |

옛 Hunyuan 경로 순서: `gen_shape`(Hunyuan3D-2.1 로컬 서버) → `stage4` → [Mixamo] → `stage5_merge` → `stage6` → `stage7 export` → `gen_paint`(Hunyuan3D-2.0 paint 로컬) → `stage7 bake` → #41 머리 `gen_shape` → `stage8` → `stage5b` → #42 손 `stage9` → `stage5b` → #43 `stage10` (H:194-207). HANDOFF에는 Hunyuan 2.0·2.1 라이선스가 한국을 제외한다고 적혀 있다 (H:188). 지금 GLB에 Hunyuan 산출물이 남아 있는지는 문서상 불명확하다.

**보조 스크립트**: `gen_shape.py`(Hunyuan 2.1 gradio `127.0.0.1:8080`), `gen_paint.py`(Hunyuan 2.0 paint), `COMPILE_TEXGEN.bat`·`convert_unet_fp16.py`·`patch_unet_lowram.py`(Hunyuan 로컬 설치용 1회), `turnaround.py`·`render_glb_textured.py`(4방향 렌더), `compare_bodies.py`(후보 몸 비교).

### 5-2. 갱도·소품 — `tools/minetunnel/`

1. `MineTunnel.blend` 원본은 사용자가 Blender 5.2로 따로 만들었다 (H:536). 다시 빌드할 때는 `render_tunnel.sh` → `build_tunnel.py -- save`. Poly Haven 텍스처 `dark_rock`, `brown_mud_rocks_01`, `medieval_wood`, `rusty_metal_02`, `dark_rock_02`와 모델 6종을 받는다 (build_tunnel.py:19-25)
2. MineTunnel.blend의 재질을 가져다 쓰는 파생 .blend 7개 빌드:
   - `build_shaft.py` → Shaft.blend (수갱 정거장 + 피트)
   - `build_cage.py` → Cage.blend (리프트 케이지)
   - `build_pick.py` → Pick.blend (곡괭이)
   - `build_face.py` → Face.blend (끝막이 + 광석 + 자갈)
   - `build_piece.py` → Pieces.blend (조각 13종)
   - `build_props.py` → Props.blend (소품 9종)
   - `build_cart.py` → Cart.blend (광차)
   - 실행은 `render_*.sh` 또는 `blender -b --python`
3. `bash tools/minetunnel/export.sh` — `export_godot.py`로 .blend 8개에서 glTF 23개를 뽑는다
   - 기본 텍스처 교체: `timber=dark_wooden_planks rock=rock_face_04 floor=brown_mud_rocks_01` (export.sh:25). 조명은 빼고, 텍스처는 1K(벽·바닥 2K)
   - 텍스처·조명이 들어갔는지 검사(:63-78) → Godot 임포트 → `.import`를 VRAM 압축·밉맵으로 고침 → 재임포트 (:81-93)
   - `ONLY=<name>`이 없으면 `assets/generated/tunnel/`을 먼저 비운다 (:28)
4. `bash tools/build.sh`

**주의 (H:269-270)**: 저장소의 `build_piece.py`에는 #26 B단계 값이 들어 있지 않다(A 값 그대로, build_piece.py:30,42). HANDOFF는 "그때까지 export.sh 는 돌리지 마라"고 적는다. 지금 조각 형상의 기준은 커밋된 `assets/generated/tunnel/*.gltf`뿐이다.

### 5-3. 스크립트가 기대는 로컬 경로
- Blender: `/c/Program Files/Blender Foundation/Blender 5.2/blender.exe` (export.sh:17, render_*.sh:5, tunnel.sh:7)
- Godot: `/c/Users/anjyo/Downloads/Godot_v4.7.2-stable_win64.exe/...console.exe` (build.sh:10, quick.sh:8, export.sh:81)
- MineTunnel 원본: `C:\Users\anjyo\Documents\MineTunnel` (stage5_merge:8, stage5b:11, stage6:11, stage7:15, stage8:12, stage9:15, stage10:21, stage11:14, export.sh:18, render_tunnel.sh:7) · `~/Documents/MineTunnel` (build_*.py, export_godot:36, fetch_texture:10)
- Hunyuan 로컬 설치: `C:\AI\HY3D2\` (gen_paint:3,13 · gen_shape:18 · convert_unet_fp16:5 · patch_unet_lowram:5)
- CUDA 12.9 · VS BuildTools (COMPILE_TEXGEN.bat:4-5)

---

## 6. Godot 고유 기능 의존 부분

Unity에 1:1 대응이 없거나 구조가 달라서 다시 설계해야 하는 곳이다. 여기에는 **지금 무엇을 쓰는지**만 적었다.

### 6-1. 엔진·프로젝트 설정
| 항목 | 현재 | 출처 |
|---|---|---|
| 물리 엔진 | **Jolt Physics** | `project.godot` `3d/physics_engine="Jolt Physics"` |
| 충돌 레이어 | 1 지형 · 2 플레이어 · 3 채굴가능 · 4 광석 · 5 괴물 | `project.godot` `[layer_names]`. 코드 6개 파일에서 `collision_layer`/`collision_mask`를 직접 씀 |
| 입력 액션 | `move_forward/back/left/right`, `jump`, `interact`(E), `mine`(좌클릭), `lamp`(F), `crouch`(Ctrl), `run`(Shift), `throw`(우클릭), `debug_spawn`, `debug_freeze`, `debug_hud` + `ui_*` | `project.godot` `[input]` |
| 오토로드 (전역 싱글턴) | `Atmosphere`, `NoiseBus`, `DevBot` (게임) + `SceneLoader`, `ProjectMusicController`, `ProjectUISoundController` (템플릿) | `project.godot:22-29` |
| 정적 클래스 | `class_name` 13개. `Tuning`(상수 전부), `PieceCatalog`(표)는 인스턴스 없이 씀 | `scripts/` |
| `@export` | 0개 — 에디터 인스펙터로 넣는 값이 없고 수치는 전부 `Tuning.gd` | 검색 |

### 6-2. Maaack's Game Template 1.6.0
- 오프닝, 메인 메뉴, 옵션 메뉴(그래픽·오디오·키 리바인딩), 크레딧, 로딩 화면이 전부 템플릿이다 (`addons/`, C:191)
- 게임 코드가 템플릿에 직접 기대는 곳은 `SceneLoader.reload_current_scene` 두 곳뿐이다 (`Player.gd:110,133`)
- 템플릿 설정(`project.godot [maaacks_game_template]`): `main_menu_scene_path`, `game_scene_path = Tunnel.tscn`, `ending_scene_path`, `loading_scene_path`
- 템플릿의 `PlayerConfig`·`AppSettings`·`GlobalState`를 게임 코드가 쓰는 곳은 0곳 (검색)
- 일시정지 메뉴(`addons/scenes/windows/pause_menu.tscn`)는 게임 씬에 연결되어 있지 않다 (H:909)
- 메뉴 번역 파일 `.translation`(en, fr)은 템플릿 것이다

### 6-3. 애니메이션
- **AnimationPlayer**: 괴물 GLB가 임포트할 때 만든 것 하나뿐이다. `MinerBody.gd`가 `find_child("AnimationPlayer")`로 찾아 `play`하고, 반복 클립의 `loop_mode`를 코드로 켠다 (:24, :31). 클립 짝마다 섞는 시간은 `set_blend_time` (H:3)
- **AnimationTree·상태머신 리소스**: 0개. 괴물 상태 전환은 `Stalker.gd` 코드의 문자열 상태로 한다
- **GLB 임포트 설정**: `animation/import=true`, `fps=30`, `trimming=false`, `remove_immutable_tracks=true` (`miner_rigged.glb.import:33-37`)
- **SkeletonModifier3D**: `ArmGround`(2뼈 IK), `SpineGlare`(척추·목 굽힘)가 클립이 뼈를 놓은 뒤 자세를 고친다. 붙이는 순서가 결과를 바꾼다 — SpineGlare를 먼저 붙인다 (`MinerBody.gd:34-38`). HANDOFF: 봇이 재는 자세도 모디파이어 안에서 재야 그려진 자세와 맞는다 (#46 함정, H:18)
- **애니메이션 파일로 만든 연출은 없다**: 리프트 문(rotation.y), 곡괭이 휘두르기·흔들림, 카메라 흔들림, 램프 끄기·정전, 사망 연출은 전부 코드와 `Tween`(6개 파일, 13곳), `create_timer`로 한다. 규칙 "애니메이션은 만들지 않는다" (C:420)

### 6-4. 시그널
- 선언 11개: `Player.ore_changed/danger_changed/died`, `Fault.repaired/failed`, `Lift.arrived`, `NoiseBus.made`, `OrePocket.broken`, `Pickaxe.struck`, `Stalker.state_changed/caught_player`
- 연결은 **전부 코드의 `.connect()`**이다. `.tscn`의 `[connection]`은 0개
- HUD는 부모가 곧 플레이어라는 전제로 `get_parent()`에서 시그널을 잇는다 (OreHud, DangerHud, DeathScreen)
- `Atmosphere`가 `SceneTree.node_added`를 받아 새로 들어오는 모든 MeshInstance3D의 재질을 바꾸고, WorldEnvironment가 들어오면 환경 값을 넣는다 (`Atmosphere.gd:41`)

### 6-5. 물리·노드 타입
| Godot 기능 | 쓰는 곳 |
|---|---|
| `CharacterBody3D` + `move_and_slide` | 플레이어, 괴물 |
| `AnimatableBody3D` + sync_to_physics | 리프트 — 위에 선 CharacterBody3D를 자동으로 실어 나른다 (`Lift.gd` 머리 주석) |
| `Path3D` / `PathFollow3D` | 광차가 순환선을 따라 달림 (`MineCart.gd`, `MineAssembler.gd:1230`) |
| `RigidBody3D` | 광석, 자갈·돌 조각, 던진 곡괭이 |
| `Area3D` | 줍기 자석, 광차 탑승, 고장 소켓, 자재함·부품 손 닿는 범위, 리프트 탑승자 |
| `RayCast3D` | 채굴 레이, 괴물 시선 |
| `GPUParticles3D` | 먼지 |
| `CanvasLayer` + `_draw()` | HUD 전부. 수리·소음 HUD는 UI 씬 없이 코드로 그림 |
| `set_meta` / `get_meta` | 포켓 자리 방향 (`PocketSpawner.gd`) |
| `set_script` 실행 중 부착 | 광차, 고장, 자재함, 부품 |

### 6-6. 절차적 생성·렌더
- **조각 배치**: glTF 인스턴스를 7 m 칸 가운데에 두고 `rotation.y`만 90° 단위로 돌린다. 조각 경계 정점이 격자에 맞아 어떻게 붙어도 이어진다 (`PieceCatalog.gd` 머리 주석)
- **길찾기**: 내비메시가 아니라 조립기 격자 BFS (`MineAssembler.grid_path`, C:463)
- **설비 메시**: `SurfaceTool`/`ArrayMesh`로 코드에서 튜브·상자·구를 만든다 (`MineAssembler.gd`, 17곳). 재질도 코드에서 만든다 (LOOK_REFERENCE §6-4)
- **이름 규칙 의존**: glTF 노드·재질 이름으로 찾는다 — `SLOT_Pocket_*`, `TMB_straight_<n>_post_R/cap`, `SHL_*`, `PROP_*`, `CAGE_GateL/R`, 재질 `MAT_RockWall`/`MAT_Floor`/`MAT_Timber`(내보내기가 `_EXPORT`를 붙임)
- **셰이더**: Godot Shading Language `.gdshader` 2개 (wet_rock: spatial, post: canvas_item + `hint_screen_texture`)
- **노이즈**: `FastNoiseLite` → `NoiseTexture2D` (젖은 얼룩)
- **시드**: `Tuning.MAP_SEED` 하나에서 층 +i, 포켓 +100, 소품 +200 (C:432)

### 6-7. 개발·검사 도구
- `OS.get_cmdline_user_args()`로 exe에 인자를 넘겨 봇을 돌린다 (`DevBot.gd:243`). `--write-movie`(Godot 내장 영상 기록)로 촬영한다
- `OS.is_debug_build()`로 배포물에서 디버그 HUD를 지운다 (`DebugHud.gd`)
- 검사 원칙: 소스가 아니라 **익스포트한 exe**에서 돌린다 (`build.sh`)

---

## 7. 미해결 문제

### 7-1. 지금 안 되는 것 · 알려진 버그
| # | 문제 | 상태 | 출처 |
|---|---|---|---|
| 1 | 괴물이 천장에 한 번 올라가면 평균 약 7초만 머묾(설계 12초). 조용한 120초 중 천장 24 %(검사 문턱 25 %), 벽 44 % | build.sh FAIL 1. 원인 모름(#54 천장 길 끊김 의심) | H:3, H:12 |
| 2 | 천장→벽·벽→바닥 모서리에서 몸이 벽·바닥을 뚫음. 원인: 몸 가운데 한 점의 법선으로 몸 전체를 돌림 | 고쳤는지 문서상 불명확 | H:43-45 |
| 3 | F 키 입력이 한 프레임에 두 번 먹혀 램프가 도로 켜짐 | 봇에서만 봄, 사람 입력으로는 재현 안 해 봄 | H:61 |
| 4 | 일시정지 메뉴 미연결 | 미연결 | H:909 |
| 5 | 소리 파일 0개 (채굴·램프·광차·괴물 전부 무음) | 미착수 | H:706, H:913 |
| 6 | 광차: 물리 계단 13 cm, 곡선 시점 튐 2·4곳 남음, 종점 광차 없음, 서로 안 피함 | 그대로 | H:235-236, H:248 |
| 7 | 설비가 곡선·갈림에서 끊김, 배관 2줄, 표지 글자 없음 | F5 판정 기록 없음 | H:254 |
| 8 | 정거장 ↔ 조각 이음새 단차 208 mm | 작은 제안서 감으로 남음 | H:282, H:704 |
| 9 | 램프에 하얗게 뜨는 것: 곡괭이 머리, 케이지 봉, 자재함 | F5에서 거슬리면 조정 | H:304, H:667, H:240 |
| 10 | 광석이 줍기 전에는 안 사라짐, 상한 없음 | 그대로 | Ore.gd:55 |
| 11 | 괴물 모델: #41 "뭉개진 부분" 남음(위치 모름), 텍스처 확정 보류, 몸에 노멀 텍스처 없음 | 보류 | H:196, H:198 |
| 12 | 공유 게이지 상한 공식·복귀 정산·판 사이 광석 유지 미구현 | 미착수 | C:437, H:917, H:712 |

### 7-2. 막혔던 것 · 보류된 것
| # | 내용 | 상태 | 출처 |
|---|---|---|---|
| 13 | #59 천장 노려보기 자세 F5 판정 | 판정 전에 멈춤 | H:6, H:14 |
| 14 | #60 "노려보는 동안 플레이어 멈춤 + 시선 끌기" | 번호만 있음. `scripts/`에서 `#60` 검색 0건 | H:6 |
| 15 | ⑦b′ 쫓아오던 괴물이 갑자기 벽을 타고 올라가면 이유가 안 보임 | 괴물 모델·애니·텍스처를 끝낸 뒤로 보류. 그때 에일리언 아이솔레이션 조사부터 | H:58-59, H:711 |
| 16 | 보류 ②: 천장 철수가 플레이어 머리 위를 지나감 | 사용자 "일단 놔둬라" | H:48, H:52 |
| 17 | ⑦b 시간값 판정(압박·감각 반경·카드 문턱·자세·스킬체크) | 미착수. #52·#53으로 천장 속도가 바뀌어 압박 하락 속도 재측정 필요 | H:710, H:56 |
| 18 | #57 낙하에서 안 한 것: 손 먼저 짚는 착지, 발로 천장 움켜쥐기 | 안 함 | H:38 |
| 19 | `build_piece.py`에 #26 B단계 값 없음 → `export.sh`를 다시 돌리면 조각이 옛 형상으로 바뀜 | 미복원 | H:269-270 |
| 20 | Hunyuan 2.0·2.1 라이선스 한국 제외 | 현재 GLB에 산출물이 남았는지 문서상 불명확 | H:188 |
| 21 | F5 판정 기록 없이 "볼 것" 목록만 남은 제안서: #29 광차, #30 정비, #31 자재함, #32 소음·램프, #34 이동, #35 괴물 | 문서상 불명확 | H:248, H:244, H:240, H:223, H:229, H:200 |

### 7-3. 검사 도구의 한계
| # | 내용 | 출처 |
|---|---|---|
| 22 | 골든 이미지 비교가 물리 장면(광석 구르기·붕괴·떨림)에서 실행마다 1~6 % "달라짐" — 문턱 0.4 %보다 큼 | H:438-440, H:13 |
| 23 | "좋은 부품 스킬체크 11초" 간헐 FAIL (재실행하면 통과) | H:206 |
| 24 | 소스 실행에서만 "갈림 이음새 검은 픽셀" FAIL, 배포물은 통과. 원인 미확인 | H:219 |
| 25 | `53_maze_curve` 캡처가 검게 나온 기록 | H:228, H:233 |
| 26 | 봇이 돈 뒤 템플릿이 창 크기를 1140×641로 복원해 사람 F5 창도 그 크기가 됨 | H:64 |
| 27 | 에디터 실행 파일로 봇을 돌리면 `Player.tscn`에 uid가 붙음 (되돌리는 방법만 기록) | H:222 |

### 7-4. 문서끼리 안 맞는 곳
- `docs/HANDOFF.md` "아직 없는 것"(H:903-917) 중 `.git` 56 MB, 부순 벽이 안 돌아옴, 조각 상한 40 봇 측정은 **옛 기록**이다. `MinableBlock.gd` 파일이 없고, 채굴 벽 파쇄는 삭제됐다 (C:448)
- HANDOFF 순서표(H:710)는 #52·#53을 "F5 대기"로 적었지만, 0번 기록(H:46)은 "통과"로 적었다
- `Ore.gd:4`, `WallChunk.gd:4` 머리 주석의 "MinableBlock이 만든다"는 옛 설명이다 (2절 참고)
- "구조에서 알아둘 것"(H:724-)의 `Modules` 노드와 4 m 격자는 옛 설명이다. 지금 `Tunnel.tscn`에 `Modules`는 없고 격자는 7 m다
- `Tuning.gd:353` `FAULT_SET` 주석은 "post_L 을 숨기고"라고 적지만, 코드는 `post_R`을 숨긴다 (`Fault.gd:36`, 머리 주석 `Fault.gd:2-3` "오른쪽 기둥")

---

## 8. `Tuning.gd` 수치 전체

`scripts/Tuning.gd`에서 **스크립트로 그대로 뽑은** 상수 339개다 (손으로 옮기지 않았다). 게임 감각(이동 속도·램프·안개·괴물 파라미터·정비 시간값)이 전부 여기 있다.
- **구역 제목**: `Tuning.gd` 안 주석 블록의 첫 줄이다. 긴 제목은 잘랐다
- **주석 열**: 원문 주석이다. 옛 값·사용자 판정 기록이 섞여 있다
- **"값" 열**: 값이 다른 상수로 계산되면 그 식을 그대로 적었다
- **단위**: 주석에 적힌 대로다 (m, m/s, 초, 도)
- **판정 상태**: ⑦b 시간값 판정 전 참고값이 많다 (주석에 "⑦b"로 표시)

#### 이동 (Tuning.gd:7)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 8 | `WALK_SPEED` | `4.5` | m/s, 걷기 속도 |
| 9 | `TIME_TO_TOP_SPEED` | `0.12` | 초, 최고속까지 걸리는 시간 |
| 10 | `TIME_TO_STOP` | `0.10` | 초, 멈추는 데 걸리는 시간 |
| 11 | `AIR_CONTROL` | `0.25` | 공중에서의 조종력 (지상 대비 비율) |

#### 점프 / 중력 (Tuning.gd:13)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 14 | `JUMP_HEIGHT` | `1.0` | m, 제자리 점프로 오르는 높이 |
| 15 | `GRAVITY` | `24.0` | m/s^2, 기본 중력(9.8)보다 무겁게 |

#### 시점 (Tuning.gd:17)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 18 | `MOUSE_SENSITIVITY` | `0.0022` | rad / 마우스 픽셀 |
| 19 | `PITCH_LIMIT_DEG` | `89.0` | 위아래로 꺾을 수 있는 한계 |

#### 몸 크기 (통로·천장 설계의 기준값) (Tuning.gd:21)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 22 | `BODY_RADIUS` | `0.4` | m |
| 23 | `BODY_HEIGHT` | `1.8` | m |
| 24 | `EYE_HEIGHT` | `1.7` | m |

#### 갱도 격자 (#22 → #26 조각 카탈로그) (Tuning.gd:26)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 27 | `GRID_CELL` | `7.0` | m, 칸 하나. 조각은 7×7 (방 2×2 는 14×14). 조각 표는 scripts/PieceCatalog.gd |

#### 층 조립 (#27, scripts/MineAssembler.gd. 문법은 Opus5_채굴게임/Claude outputs/조립기… (Tuning.gd:29)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 30 | `MAP_SEED` | `7` | 하나뿐인 시드. 층 i 는 +i, 포켓 +100, 소품 +200 (멀티 준비: 난수 시드는 하나). 봇·골든이 같은 판을 보게 고정 |
| 31 | `MAP_FLOORS` | `2` | 위층(y 0)·아래층(y -LIFT_DROP). 리프트는 그대로 한 번만 내려간다 |
| 32 | `MAP_N` | `35` | 칸 수 한 변 = 245 m (#25: 빈 갱도라면 끝 벽까지 걸어서 45~60초) |
| 33 | `ENTRY_STRAIGHT` | `3` | 정거장 앞 직선 레일 칸 (21 m). 스폰·봇 동선이 여기 선다 |
| 34 | `RING_MARGIN` | `5` | 순환선 모퉁이가 격자 가장자리에서 떨어진 칸 |
| 35 | `RING_WOBBLE` | `3` | 순환선 중간점을 옆으로 흔드는 ±칸 — 구불구불 |
| 36 | `SPURS_MIN` | `2` | 지선(순환선 → 구석 종점) 수 |
| 37 | `SPURS_MAX` | `4` |  |
| 38 | `SPUR_LEN_MIN` | `6` | 지선 길이 (칸) |
| 39 | `SPUR_LEN_MAX` | `11` |  |
| 40 | `SPUR_TURN_P` | `0.2` | 지선이 꺾일 확률 |
| 41 | `BRANCHES` | `70` | 횡갱(무레일 가지) 수 |
| 42 | `BRANCH_LEN_MIN` | `4` | 횡갱 길이 (칸) |
| 43 | `BRANCH_LEN_MAX` | `12` |  |
| 44 | `BRANCH_DEPTH` | `5` | 가지의 가지 깊이 |
| 45 | `TURN_P` | `0.35` | 횡갱이 꺾일 확률 |
| 46 | `LOOP_P` | `0.5` | 걷다 다른 갱도에 닿으면 이어 붙일 확률 (= 고리) |
| 47 | `LOOPS_MAX` | `22` | 고리 상한 |
| 48 | `FAR_DIV` | `70.0` | 뿌리(정거장)에서 먼 칸일수록 갈림 ↓: 건너뛸 확률 = 거리(칸) / 이 값 |
| 49 | `BLOCKS` | `4` | 채탄구역(방기둥 격자 3×3~5×5) 수 |
| 50 | `ROOM_P` | `0.7` | 막다른 끝이 목 + 방이 될 확률 (나머지는 끝막이) |
| 51 | `REFUGES` | `2` | 층당 대피소 |
| 52 | `PIECE_VIEW_RANGE` | `40.0` | m, 이 밖의 조각 메시는 안 그린다 (Godot visibility range). 램프 14 + 안개 0.03 이라 안 보인다 |

#### 소품은 무더기(2~3개)로 놓는다 (#27 수정: 벽에 하나씩 붙인 것은 램프 원뿔 밖이라 "소품이 있는지 모르겠다") (Tuning.gd:53)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 54 | `PROP_CLUSTER_P` | `0.2` | 직선 칸당 무더기 확률 |
| 55 | `PROP_JUNCTION_P` | `0.5` | 갈림(T·+) 칸당 무더기 확률 (모서리 크립 옆) |
| 56 | `PROP_CLUSTER_MIN` | `2` | 무더기 크기 |
| 57 | `PROP_CLUSTER_MAX` | `3` |  |
| 58 | `PROP_CLUSTER_R` | `1.2` | m, 무더기 반지름 |
| 59 | `PROP_WALL_GAP_MIN` | `1.4` | m, 무더기 중심이 벽(공칭 3.5)에서 떨어지는 거리 — 복도 가운데서 램프 원뿔(40°) 안에 든다 |
| 60 | `PROP_WALL_GAP_MAX` | `2.2` |  |
| 61 | `PROP_BIG_FRAC` | `0.8` | 큰 것(통·상자·잔해·갱목) 비중. 납작한 것(삽·망치)·작은 것(양동이·석유등)은 나머지 |
| 62 | `PROP_CAP` | `1` | 끝막이 앞 무더기 수 |
| 63 | `PROP_ROOM_2` | `3` | 방 2×2 구석 무더기 수 |
| 64 | `PROP_ROOM_1` | `1` | 방 1×1 무더기 수 |

#### 채굴 (#23 수정판: 채굴 벽은 없다. 캐는 것은 옆벽에 박힌 광맥 포켓뿐 — #24) (Tuning.gd:66)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 67 | `MINE_DAMAGE` | `25.0` | 1회 타격 데미지 |
| 68 | `POCKET_HEALTH` | `50.0` | 광맥 포켓 체력. 위 값이면 2타 — 첫 타에 자갈, 둘째 타에 덩이가 빠진다 |
| 69 | `MINE_RANGE` | `3.0` | m, 곡괭이가 닿는 거리 |
| 70 | `MINE_COOLDOWN` | `0.35` | 초, 타격 간격. 연타해도 이보다 빠르지 않다 |
| 71 | `HIT_RECOIL` | `0.12` | m, 맞은 블록이 뒤로 밀리는 거리 |
| 72 | `HIT_RECOIL_TIME` | `0.10` | 초, 밀렸다 돌아오는 데 걸리는 시간 |
| 73 | `BREAK_TIME` | `0.08` | 초, 부서질 때 줄어드는 시간 |

#### 자갈·돌 조각 (WallChunk) (Tuning.gd:74)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 76 | `CHUNK_SPIN` | `4.0` | rad/s, 조각이 도는 속도 |
| 77 | `CHUNK_LIFE` | `3.0` | 초, 이만큼 뒤에 사라지기 시작 (붕괴 돌) |
| 78 | `CHUNK_FADE` | `0.5` | 초, 줄어들며 사라지는 시간 |
| 79 | `CHUNK_LIMIT` | `40` | 화면 안 조각 상한. 넘으면 오래된 것부터 지운다 |
| 80 | `HIT_DUST` | `12` | 알, 평타 먼지 |
| 81 | `BREAK_DUST` | `60` | 알, 포켓에서 덩이가 빠질 때 먼지 |
| 82 | `SHAKE_AMOUNT` | `0.06` | m, 카메라 흔들림 폭. 덩이가 빠질 때만 |
| 83 | `SHAKE_TIME` | `0.15` | 초 |

#### 광맥 포켓 · 광석 (#23 수정판, #24 규칙: 광석은 재화, 채굴은 소음만) (Tuning.gd:85)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 89 | `POCKET_CHANCE` | `0.10` | 자리당 켜질 확률. 층당 자리 약 1,600 (시드 7) → 기대 약 160개 |
| 90 | `POCKET_MIN_PER_FLOOR` | `1` | 층에 하나도 안 켜지면 첫 자리를 강제로 켠다. 시드는 MAP_SEED + 100 (#27) |
| 91 | `POCKET_WALL_OUT` | `0.12` | m, 자리(SLOT_Pocket, 벽 공칭면 안쪽 0.08)에서 통로 쪽으로 더 내미는 거리. 벽 요철이 안쪽으로 0~0.3 이라 자리 그대로면 요철이 깊은 곳에서 덩이가 파묻힌다 (#27 첫 캡처: 끝만 보임). 파묻힘/떠 있음 판정 손잡이 |
| 93 | `POCKET_POP_OUT` | `1.4` | m/s, 옆벽에서 통로 쪽으로 튀는 속도. 0.6 이면 벽에 붙어 구른다 |
| 94 | `ORE_POP_UP` | `2.2` | m/s, 위로 튀는 속도. 자갈(2.4)만큼 높아야 눈에 띈다 |
| 95 | `ORE_POP_SIDE` | `0.6` | m/s, 벽을 따라 좌우로 흔들리는 속도. 하나뿐이라 흩어질 필요가 없다 |
| 96 | `ORE_SPIN` | `4.0` | rad/s |
| 97 | `ORE_ROLL_DAMP` | `4.0` | 구르기 감쇠. 충돌이 구(0.12)라 감쇠 없이는 자갈 바닥을 3.5m 넘게 굴러갔다(봇 실측) — 1~1.5m 에서 멎게 |
| 98 | `ORE_MAGNET_DELAY` | `1.5` | 초, 튀어나온 뒤 이만큼은 안 빨려온다. 채굴 사거리(3.0)와 자석 반경(1.8)이 겹쳐서, 이게 없으면 벽 앞에 선 채로 즉시 빨려들어가 광석이 바닥에 구르는 것을 볼 새가 없다. 0.8초로는 착지하기도 전에 풀려서 1.5초로 잡았다 — 튀어서 바닥에 멎는 데까지가 그 정도다. |
| 104 | `ORE_MAGNET_RANGE` | `1.8` | m, 이 안에 들면 몸으로 빨려온다 |
| 105 | `ORE_PULL_SPEED` | `6.0` | m/s, 빨려오는 속도 |
| 106 | `ORE_COLLECT_DIST` | `0.35` | m, 이만큼 가까워지면 줍힌다 |

#### 곡괭이 (Tuning.gd:108)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 110 | `PICK_POS` | `Vector3(0.32, -0.42, -0.60)` | 카메라 기준 오른쪽·아래·앞 (#23 렌더 pick_a2_hand_s075 와 같은 자리) |
| 111 | `PICK_SCALE` | `0.75` | pick.gltf(자루 0.85·머리 0.46). A 단계 렌더 판정 0.75 (0.55 는 "너무 작다") |
| 112 | `PICK_TILT_DEG` | `-12.0` | 쉬고 있을 때 앞뒤로 눕힌 각도 |
| 113 | `PICK_YAW_DEG` | `-90.0` | 머리를 앞뒤로 세우는 각도. 0 이면 머리가 화면 가로로 누워 옆으로 후려치는 모양이 된다. pick.gltf 는 머리 긴 축이 X, 양끝이 뾰족해 KayKit 때의 -90 을 그대로 쓴다. |
| 117 | `PICK_ROLL_DEG` | `10.0` | 옆으로 눕힌 각도. 크면 눕혀 든 것처럼 보인다 |
| 118 | `PICK_SWING_DEG` | `55.0` | 내려치는 각도 |
| 119 | `PICK_DOWN_TIME` | `0.12` | 초, 내려치는 데 걸리는 시간. 데미지는 이 시점에 들어간다 — 곡괭이가 벽에 닿을 때다. |
| 121 | `PICK_UP_TIME` | `0.23` | 초, 되돌리는 시간. 합쳐서 쿨다운 0.35 와 맞는다 |
| 122 | `PICK_BOB_AMOUNT` | `0.02` | m, 걸을 때 흔들리는 폭 |
| 123 | `PICK_BOB_SPEED` | `12.0` | rad/s |

#### 리프트 (Tuning.gd:125)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 126 | `LIFT_DROP` | `10.0` | m, 한 번에 내려가는 깊이 (#22: 8 → 10. 갱도 높이 5.6 이면 층 사이 바위가 남아야 한다). 위층 불빛이 사라진다 |
| 127 | `LIFT_SPEED` | `1.4` | m/s. 8m 에 약 5.7초 — 느려야 무섭다 |
| 128 | `LIFT_ACCEL_TIME` | `0.6` | 초, 최고속까지. 출발·도착에서 덜컹거리지 않게 |
| 129 | `LIFT_GATE_TIME` | `0.8` | 초, 케이지 문이 닫히는(열리는) 시간. 다 닫힌 뒤에 출발한다 (#21) |

#### 조명 (헤드램프) (Tuning.gd:131)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 133 | `LAMP_ANGLE_DEG` | `40.0` | 원뿔 반각. 시야(fov 80)보다 좁아야 가장자리가 어둡다. 32 는 가까운 벽에 손전등 원반이 찍혔다(사용자 판정 09-08) → 40 |
| 135 | `LAMP_ATTEN` | `0.45` | 원뿔 가장자리가 꺼지는 정도. 크면 테두리가 또렷해진다. 1.2 는 동그란 테두리가 눈에 띄어 손전등 같았다. 0.7 도 원반이 보여 0.45 |

#### 램프의 몸 (#17 수정). 등이 카메라와 같은 축이면 빛에 방향이 없다. (Tuning.gd:137)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 138 | `LAMP_FOLLOW_TIME` | `0.10` | 초, 시점을 돌리면 램프가 이만큼 늦게 따라온다. 0 이면 카메라에 붙는다. 멀미 나면 0.05 |
| 140 | `LAMP_OFFSET` | `Vector3(0.0, 0.12, 0.0)` | m, 카메라 기준 램프 원점. 눈 위 이마 자리 |
| 141 | `LAMP_BOB` | `0.01` | 도, 걸을 때 위아래로 끄덕이는 각. 곡괭이 bob 속도(PICK_BOB_SPEED)와 같이 돈다. 0.6 은 "너무 과하다"(사용자 09-08 2차 판정, 값 지정 0.1) → 0.1 도 "아직 큼"(#19 판정, 0.05) → 0.05 도 "출렁인다"(2차, 값 지정 0.01) |
| 143 | `LAMP_RANGE` | `14.0` | m, 이보다 먼 것은 안 보인다. 12 로 줄여 봤더니 20m 방의 먼 벽이 통째로 사라져 공간이 안 읽혔다 — 먼 곳은 안개가 서서히 잠그게 둔다 |
| 145 | `LAMP_ENERGY` | `5.0` | 벽이 젖은 검은 돌(반사율 약 1/3)이 되면서 2.2 → 5.0 (#17). 실측(spawn 시점 화면 평균): 3.2 = 0.0097(안 보임) · 6.0 = 0.0152 · 9.0 = 0.0190. 9.0 은 먼 벽은 좋은데 채굴 거리(1.8m)의 벽이 하얗게 탔다 — 세기 대신 아래 감쇠를 낮춰 먼 곳을 살린다 |
| 149 | `LAMP_DIST_ATTEN` | `0.6` | 거리 감쇠 곡선. 1.0 = 거리 제곱으로 꺼짐(물리). 낮출수록 먼 곳까지 고르게 간다 — 가까운 벽을 안 태우면서 먼 벽을 보이게 하는 손잡이 |
| 151 | `LAMP_COLOR` | `Color(1.00, 0.96, 0.88)` | 거의 흰 빛 (#17 수정). 누런 빛(0.88/0.70, 0.86/0.62)은 검은 돌을 갈색으로 만들었다(사용자 판정 "안 읽힌다") |
| 153 | `LAMP_SHADOW` | `true` | 창살·조각 그림자가 이 게임의 그림이다 |
| 154 | `LAMP_TOGGLE_TIME` | `0.15` | 초, F 로 끄고 켜는 트윈 (#32) |
| 155 | `DARK_ADAPT_AMBIENT` | `3.0` | (#32 수정 2: 5.5 → 3.0. 사용자 F5 "끈 게 더 잘 보인다" — 환경광은 방향이 없어 원뿔 밖까지 비춘다. 후보 A 5.5/0.2·B 3.0/0.45·C 2.0/0.6 중 B)  램프를 끄고 눈이 적응한 끝의 환경광. 환경광 색이 (0.1, 0.12, 0.2) 로 어두워 0.12 로는 화면 밝기 0.0017 → 0.0024 뿐이었다 (#32 실측). 3.0 ≈ 밝기 0.025, 벽 윤곽만 겨우 |
| 156 | `DARK_ADAPT_TIME` | `4.0` | 초, 적응에 걸리는 시간. 켜면 즉시 평소로 (눈부심) |
| 157 | `DARK_ADAPT_FOG` | `0.45` | 적응했을 때 거리 안개 밀도 (#32 수정 2: 0.2 → 0.45). 환경광은 거리가 없어 복도 끝까지 비추므로 안개로 잠근다 — 2 m 41 %·4 m 17 %·6 m 7 %. 레일 두 줄·곡괭이·옆 난간만 남는다 |

#### 소음 (#32, 순서표 ⑥) — scripts/NoiseBus.gd. 반경 m. 듣는 괴물은 ⑦. 값은 ⑦b 판정 때 같이 움… (Tuning.gd:158)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 159 | `NOISE_PICK` | `25.0` | 곡괭이가 벽에 닿은 타격. 칸 3.5개 — 옆 갱도까지 |
| 160 | `NOISE_REPAIR_FAIL` | `40.0` | 정비 실패 "큰 소음". 타격의 1.6배 |
| 161 | `NOISE_STEP` | `6.0` | 발걸음. 같은 칸 안 |
| 162 | `STEP_INTERVAL` | `0.5` | 초, 걷기 4.5 m/s 에서 2.25 m 마다 한 걸음 |
| 163 | `NOISE_CART` | `20.0` | 달리는 광차, 1초마다 |
| 164 | `NOISE_HUD_FADE` | `1.0` | 초, 왼쪽 아래 원이 사라지는 시간 |
| 165 | `NOISE_HUD_PX_PER_M` | `2.0` | 반경 1 m 당 지름 px. 40 m → 지름 160 |

#### 이동 세 자세 + 스태미나 + 곡괭이 던지기 (#34, 규칙 개정 4) — Player.gd · ThrownPick.gd. 판… (Tuning.gd:166)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 167 | `STANCE` | `{` | 자세: 속도 m/s · 발소리 간격 s · 발소리 반경 m. 걷기 줄은 위 WALK_SPEED·STEP_INTERVAL·NOISE_STEP 그대로 |
| 172 | `CROUCH_EYE` | `1.0` | m, 숙였을 때 눈높이 (평소 EYE_HEIGHT 1.7). 광차 테두리 1.72 아래 |
| 173 | `CROUCH_TIME` | `0.15` | 초, 눈이 내려가고 올라오는 시간 |
| 174 | `STAMINA_MAX` | `100.0` |  |
| 175 | `STAMINA_RUN` | `20.0` | /s 달리면 닳음 (5초) |
| 176 | `STAMINA_WALK` | `10.0` | /s 걸으면 참 |
| 177 | `STAMINA_IDLE` | `20.0` | /s 서 있으면 참. 탈진은 100 찰 때까지 정지 (5초) |
| 178 | `THROW_SPEED` | `14.0` | m/s, 곡괭이 던지는 속도. 위로 THROW_UP_DEG 면 사거리 약 12 m (중력 24) |
| 179 | `THROW_UP_DEG` | `10.0` |  |
| 180 | `THROW_BODY_R` | `0.15` | m, 던진 곡괭이 충돌 구 |
| 181 | `NOISE_PICK_LAND` | `20.0` | m, 착지 소음 (광차와 같은 급). 유인 |
| 182 | `THROW_STUCK_S` | `3.0` | 초, 착지 뒤 이만큼 지나면 얼린다 (틈에 끼지 않게) |

#### 갱도의 색과 공기 (제안서 #17, 질감 A·D) (Tuning.gd:184)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 186 | `PALETTE_PATH` | `"res://assets/generated/palette/dungeon_texture.png"` |  |
| 187 | `PALETTE_ROUGHNESS` | `0.7` | KayKit 팔레트 재질(채굴 벽·리프트·파쇄 조각) 거칠기. 무광. #17 의 0.22 + 광택막은 평평한 KayKit 벽에서 램프가 한 점 원반으로 맺혔다 ("광원 동그라미가 너무 크고 세다", #19 3차 판정). 젖음은 요철 있는 갱도 모듈 재질에만 준다 |

#### 젖은 바위 (shaders/wet_rock.gdshader, #20 판정 뒤). 갱도 모듈·정거장의 MAT_RockWall·M… (Tuning.gd:190)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 193 | `STONE_CLEARCOAT` | `0.0` | 젖은 자리의 물막. #27 수정: 1.0 은 헤드램프가 벽·바닥에 흰 점으로 맺혔다(사용자 "광원이 비친다") → 0. 얼룩·흘러내림(WET_DARKEN 등)은 그대로 |
| 194 | `WET_SCALE` | `0.3` | 얼룩 노이즈 한 주기 = 1/0.3 ≈ 3.3m. 얼룩 크기 0.5~1.5m |
| 195 | `WET_LOW` | `0.42` | 노이즈가 이 밑이면 마른 돌 |
| 196 | `WET_HIGH` | `0.60` | 이 위면 완전히 젖음. 둘 사이가 번짐 폭. 낮추면 더 넓게 젖는다 |
| 197 | `WET_DARKEN` | `0.5` | 젖은 자리 색 배율. 물이 스민 돌은 어둡다 |
| 198 | `WET_ROUGHNESS` | `0.45` | 젖은 자리 거칠기 (마른 자리는 텍스처 값). 0.1 은 거울 — 흰 점의 다른 반 (#27 수정) |
| 199 | `ROCK_SPECULAR` | `0.25` | 마른 바위 반사율. 0.5 + 물막 = 램프 흰 점 (#27 수정) |
| 200 | `ROCK_NORMAL_SCALE` | `1.6` | 큰 결(노멀맵) 강도. 1.0 은 "매끈한 이미지" (#27 수정) |
| 201 | `DETAIL_NORMAL_TILES` | `6.0` | 미세 결: 같은 노멀맵을 이만큼 잘게 한 번 더 겹친다 |
| 202 | `DETAIL_NORMAL_STRENGTH` | `0.6` | 그 세기. 0 = 없음. 0.5 m 안에서 격자처럼 보이면 내린다 |

#### 이음새 (#27 수정 2) (Tuning.gd:203)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 204 | `TRIPLANAR` | `true` | 벽·바닥 텍스처를 UV 대신 세계 좌표 세 면에서 뽑는다 — 조각 경계에서 무늬가 안 끊긴다 |
| 205 | `TRI_SCALE_WALL` | `0.42` | 1/한 장 크기 (m). 박스 매핑과 같은 값 = 2.4 m 한 장 |
| 206 | `TRI_SCALE_FLOOR` | `0.70` | 바닥 1.4 m 한 장 |
| 207 | `TRI_BLEND` | `4.0` | 세 면 섞는 날카로움 (젖은 얼룩과 같은 값) |
| 208 | `COLLAR_THICK` | `0.35` | m, 이음새 바위 칼라: 아치 윤곽 바깥 두께. 0 = 안 놓음. 벽 요철 0.3 보다 커야 한다 |
| 209 | `COLLAR_DEPTH` | `0.5` | m, 이음새 앞뒤 깊이 |
| 210 | `COLLAR_INSET` | `0.02` | m, 칼라 안쪽 면을 공칭 윤곽보다 이만큼 바깥에 — 이음새 선에서 벽과 겹쳐 떨리지 않게 |
| 211 | `CRIB_FILL_W` | `0.66` | m, 크립 속을 채우는 바위 기둥 한 변 (통나무 안쪽 0.5, 바깥 0.9). 0 = 안 채움. 사용자 스크린샷의 "틈" = 크립 속 빈 곳 |

#### 갱도 설비 (#28) — 조립기가 직선 칸마다 왼쪽(케이블·풍관·배수로·라깅·갓등)·오른쪽(배수관·플랜지) 묶음을 놓는다. 근… (Tuning.gd:212)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 214 | `CART_COUNT` | `3` | 순환선 위 광차 수 (규칙 3~4). 0 = 안 놓음 |
| 215 | `CART_SPEED` | `8.0` | m/s. 걷기 4.5 의 1.8배. 시드 7 순환선 약 960 m → 한 바퀴 2분. MAP_STRUCTURE "30초 안팎"(15 m/s)의 절반 — 손잡이 |
| 216 | `CART_STOP_S` | `6.0` | s, 순환선 시작(정거장 앞 직선 끝)에서 정차 |
| 217 | `CART_BOARD_DIST` | `3.0` | m, E 가 먹는 거리 (Board Area3D 반지름) |
| 218 | `CART_SEAT` | `Vector3(0.0, 0.62, 0.0)` | 짐칸 바닥 자리 (테두리 1.72 < 눈 0.62+1.7) |
| 219 | `CART_OFF_SIDE` | `1.6` | m, 내릴 때 광차 오른쪽으로 |
| 220 | `CART_CURVE_R` | `3.5` | m, 꺾이는 칸의 호 반지름 (rail_curve 와 같다) |
| 221 | `CART_ARC_PTS` | `6` | 호를 몇 점으로 |
| 222 | `CART_LOOK` | `2.0` | m, 광차가 바라보는 앞 점 거리 (#29-c). PathFollow3D 접선은 폴리라인 꼭짓점마다 튀어서 대신 이 점을 본다 |

#### 갱목 광부 모델 (#36) — scenes/level/Miner.tscn · scripts/MinerBody.gd. 배치·행동… (Tuning.gd:223)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 224 | `MINER_ANIM_SPEED` | `0.7` | 기본 재생 배속(제자리 클립). 느릴수록 무섭다 — F5 로 0.5~1.0 판정 |
| 225 | `MINER_SCALE` | `1.5` | 사용자 F5 09-11: 1.0 은 "무섭지 않다" → 1.5배. 웅크린 키 1.92 × 1.5 ≈ 2.9 m, 선 키 3.75. 1.0 = 사람 크기(선 키 2.5) |
| 226 | `MINER_BLEND_S` | `0.18` | s, 클립을 섞는 기본 시간 (#47). 0 이면 한 프레임에 자세가 튄다 |
| 227 | `MINER_BLEND_POSE_S` | `0.45` | s, 선 자세 ↔ 엎드린 자세처럼 차이가 큰 짝 |
| 228 | `MINER_BLEND_BRIDGE_S` | `0.15` | s, 엎드리기 클립(prone_down) 앞뒤 — 이 클립 자체가 다리 역할이라 짧게 |
| 229 | `MINER_BLEND_HIT_S` | `0.12` | s, 맞기·휘두르기로 들어갈 때. 타격은 빨라야 맞은 느낌이 난다 |
| 230 | `MINER_BLEND_ROAR_S` | `0.30` | s, 포효로 들어갈 때 |
| 231 | `MINER_PRONE_FROM` | `2.9` | s, prone_down(일어서기) 클립에서 선 자세인 시각. 여기서부터 뒤로 틀면 엎드리기가 된다 (#47) |
| 232 | `MINER_PRONE_TO` | `2.1` | s, 같은 클립에서 네 발로 짚은 시각. 여기까지 오면 run 으로 넘긴다 |
| 233 | `STALKER_HAND_GROUND` | `true` | #46 손 접지 켬/끔. false = 옛 동작(손이 바닥을 뚫는다) — 봇 사보타주용 |
| 234 | `STALKER_GROUND_CLIPS` | `["crawl", "run"]` | 손을 바닥에 붙일 클립. 선 자세 클립은 손이 1.4 m 위라 건드릴 일이 없다 |
| 235 | `STALKER_HAND_CLEAR` | `0.02` | m, 손끝 뼈가 바닥 위로 띄우는 값 |
| 236 | `STALKER_HAND_LIFT_MAX` | `0.80` | m, 한 팔을 끌어올리는 한도 (실측 최대 crawl 0.64). 넘으면 포기 — 팔이 안 닿는 자세다 |

#### 괴물 (#35) — 한 마리 + 감독. scripts/Stalker.gd · Director.gd. 수치 판정은 ⑦b (Tuning.gd:237)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 238 | `STALKER_R` | `0.6` | m, 충돌 캡슐 반지름 |
| 239 | `STALKER_H` | `2.8` | m, 충돌 캡슐 높이 = 1.5배 웅크린 키(실측 2.81) |
| 240 | `STALKER_EYE_H` | `2.4` | m, 눈(시선 레이) 높이 |
| 241 | `STALKER_SPEED` | `{"wander": 2.5, "investigate": 4.0, "chase": 6.5, "retreat": 4.0, "search": 2.5}` | m/s. 걷는 사람(4.5)은 잡히고, 달리면(7.0) 5초 벌 수 있다 |
| 242 | `STALKER_EAR_MUL` | `1.0` | 소음 반경에 곱함 — 반경 안이면 듣는다 (카드 어둠 수색 ×1.5) |
| 243 | `STALKER_EYE_DEG` | `60.0` | 눈 원뿔 반각. 램프 켜진 몸만, 시선이 안 가려야 |
| 244 | `STALKER_EYE_M` | `12.0` | m, 눈 사거리 |
| 245 | `STALKER_LIGHT_M` | `30.0` | m, 빛: 켜진 램프가 시선에 들면 그 자리로 천천히(배회 속도) |
| 246 | `STALKER_LOSE_S` | `3.0` | s, 추격 중 이만큼 못 보면 마지막 자리 조사 |
| 247 | `STALKER_SEARCH_CELLS` | `3` | 수색 범위 (격자 칸) |
| 248 | `STALKER_SPOTS_MIN` | `2` | 수색 곳 수 |
| 249 | `STALKER_SPOTS_MAX` | `3` |  |
| 250 | `STALKER_DWELL_S` | `2.0` | s, 곳마다 머무는 시간 (카드 ×2) |
| 251 | `STALKER_FOUND_M` | `2.0` | m, 수색 자리에서 이 안에 숨어 있으면 들킴 |
| 252 | `STALKER_CATCH_M` | `1.5` | m, 잡는 거리 (추격 중) |
| 253 | `STALKER_STUN_S` | `1.5` | s, 곡괭이 스턴 |
| 254 | `STALKER_WANDER_CELLS` | `3` | 배회 반경 (격자 칸) |
| 255 | `STALKER_WANDER_PAUSE_S` | `1.0` | s, 배회 도착마다 멈춤 |
| 256 | `STALKER_CLIPS` | `{"wander": "walk_crouch", "investigate": "walk_crouch", "search": "idle_crouch", "alert": "roar", "chase": "run_stand", "retreat": "walk_crouch", "stun": "hit", "catch": "attack_swipe", "climb": "crawl", "hang": "crawl", "land": "land_hard"}` | 낙하 클립은 STALKER_FALL_CLIP (#57). hang = 천장 기기 클립을 멈춰 두고 상체만 든다 (#59, 옛 #57 은 선 클립을 거꾸로). #48: 바닥 추격은 서서 달리기, 기는 것은 천장 전용. #49: 벽타기도 crawl — 사람 사다리 클립(climb_up/down)은 팔을 벌려 웃긴다 |
| 257 | `STALKER_ALERT_S` | `1.0` | s, 숨은 플레이어를 들키면 포효(roar)하고 이만큼 뒤에 추격 — 빠져나갈 틈. 0 이면 바로 추격 |
| 258 | `STALKER_DROP_S` | `0.0` | s, #47 엎드리기. #48 에서 바닥 추격이 '서서 달리기'가 되면서 안 쓴다(0). 기는 것은 천장 전용 — 0.6 으로 되돌리면 바닥에서도 엎드린다 |

#### 천장 크롤러 (#48) — 벽타기·낙하 클립은 받는 중. 먼저 천장 이동부터 (Tuning.gd:259)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 260 | `STALKER_CEIL_ON` | `true` | 천장 기능 끄개. false = 전부 바닥 (사보타주) |
| 261 | `STALKER_CEIL_CLEAR` | `0.35` | m, 천장면과 등(괴물 원점) 사이 틈 |
| 262 | `STALKER_CEIL_MIN_H` | `3.6` | m, 천장이 이보다 낮은 칸은 천장 길이 아니다 (실측: 직선 4.96 · 교차 5.39 · 곡선 3.05) |
| 265 | `CEIL_H` | `{"straight": 4.96, "curve": 2.71, "t": 5.40, "cross": 5.39, "cap": 4.97, "neck": 3.08, "refuge": 4.99, "room_1": 4.94, "room_2": 5.75}` |  |
| 266 | `STALKER_CEIL_RISE` | `4.0` | m/s, 칸이 바뀌어 천장 높이가 달라질 때 따라 올라가는 속도 |
| 267 | `STALKER_CEIL_EYE_H` | `-1.2` | m, 거꾸로 매달렸을 때 눈높이 (원점 아래) |
| 268 | `STALKER_CEIL_SPEED` | `2.5` | m/s, 천장 이동 속도 (배회·조사·수색·철수) |
| 269 | `STALKER_CEIL_INV_SPEED` | `4.0` | m/s, 천장에서 빛으로 알아챈 플레이어에게 다가가는 속도 (#53). 바닥 소음 조사와 같은 값 — 2.5 로는 걷는 플레이어(4.5)에게도 못 따라와 머리 위에 머물기만 한다 |
| 271 | `STALKER_CEIL_CHASE_SPEED` | `6.5` | m/s, 천장에서 쫓을 때 (#52). 바닥 추격(STALKER_SPEED["chase"])과 같은 값 — 2.5 로는 달리는 플레이어(7.0)에게서 초당 4.5 m 씩 뒤처져 머리 위에서 멀어지기만 했다(F5 09-13). 6.5 면 초당 0.5 m 만 벌어져, 스태미나가 떨어지면 따라붙어 STALKER_FALL_TRIGGER_M 에서 떨어진다 |
| 274 | `STALKER_CEIL_CLIPS` | `{"wander": "crawl", "investigate": "crawl", "search": "crawl", "chase": "run", "retreat": "crawl"}` | 천장에 붙어 있을 때 쓰는 클립 (거꾸로 재생되는 게 아니라 몸을 뒤집는다) |

#### 면 번갈기 · 벽 (#49). 배회는 천장 ↔ 바닥을 시계로 번갈고, 조사·수색·추격은 바닥이다. 오르내리기는 벽면 위의 cr… (Tuning.gd:275)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 276 | `STALKER_CEIL_DWELL_S` | `12.0` | s, 천장에서 배회하는 시간. 끝나면 벽으로 내려온다 |
| 277 | `STALKER_FLOOR_DWELL_S` | `10.0` | s, 바닥에서 배회하는 시간. 끝나면 벽을 타고 올라간다 (오르내리는 데 6~7초씩 걸려 조용할 때 천장 체류는 약 40 %) |
| 278 | `STALKER_CEIL_P` | `0.5` | 등장할 때 천장에 붙을 확률 (나머지는 바닥 곡선 칸) |
| 279 | `STALKER_WALL_SPEED` | `1.2` | m/s, 벽·아치를 기어 오르내리는 속도 (벽 4.4 m + 아치 약 3.3 m = 6.4초) |
| 280 | `STALKER_WALL_LAND_OFF` | `0.75` | m, 바닥에 내려설 때 벽면에서 몸 중심까지. 몸 반지름 0.6 + 여유 0.15 — 바깥 끝 3.01 로 벽 충돌체(3.20) 안쪽이다. 이걸 안 두면 몸이 벽에 0.51 m 박힌 채로 물리가 켜져 밀려나가다 바닥 아래로 빠졌다 (#49 수정, 사용자 F5) 오르내리는 동안 이 높이만큼에 걸쳐 STALKER_WALL_OFF 로 붙는다 (한 프레임에 안 튀게) |
| 283 | `STALKER_WALL_OFF` | `0.05` | m, 벽면에서 몸 중심까지. 옛 값 0.7 은 충돌 상자(\|x\| 3.2~3.5) 기준이라 보이는 벽(3.16) 밖 허공이었다 — 사보타주로 되돌려 본다 |
| 284 | `STALKER_RETREAT_CEIL_CELLS` | `3` | 칸, 철수할 때 벽을 타고 올라간 뒤 천장으로 기어 멀어지는 거리 (#50. 3칸 = 21 m, 천장 2.5 m/s 로 8.4초) |
| 285 | `STALKER_FLOOR_MIN_Y` | `-0.1` | m, 괴물이 이 밑으로 내려가면 갇힌 것 — 칸 가운데 바닥으로 되돌린다 (#49 수정 그물) |
| 286 | `STALKER_SURF_TURN_S` | `0.4` | s, 붙은 면이 바뀔 때 몸이 새 법선으로 도는 시간 |

#### 벽을 탈 수 있는 조각 (#51). 이 셋만 옆벽이 칸 가운데에서 TUNNEL_WALL_X 인 곧은 면이다 — 갱목 기둥이 벽… (Tuning.gd:287)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 290 | `STALKER_WALL_PIECES` | `["straight", "t", "cap"]` |  |
| 291 | `TUNNEL_WALL_X` | `3.16` | m, 보이는 벽(갱목 기둥 안쪽면)까지. 조립기 단면(MineAssembler._collar_mesh)과 같은 값 |
| 292 | `TUNNEL_ARCH_Y` | `4.4` | m, 벽이 끝나고 아치가 시작하는 높이 (h_wall) |
| 293 | `TUNNEL_TOP_Y` | `5.6` | m, 아치 꼭대기 (h_top). 실제 조각 천장은 CEIL_H 가 더 낮다 — 아치는 그 값으로 눌러 쓴다 |
| 294 | `STALKER_FALL_TURN_S` | `0.25` | s, 천장에서 놓고 몸이 뒤집히는 시간 |
| 295 | `STALKER_FALL_TRIGGER_M` | `7.5` | m, 천장에서 플레이어가 이 안에 들면 떨어진다 (낙하+착지 1.4초 동안 플레이어가 도망갈 거리를 감안) |
| 296 | `STALKER_LAND_FROM` | `0.63` | s, land_hard 에서 발이 바닥에 닿는 시각 — 여기서부터 튼다 |
| 297 | `STALKER_LAND_S` | `0.67` | s, 착지 자세를 유지하는 시간. 끝나면 서서 달리기로 섞는다 |

#### 낙하 = 매달림 → 머리부터 (#57). 레퍼런스 = 조사 #56(리커·에일리언·베르두고): 팔을 옆으로 벌리는 작품은 없다… (Tuning.gd:298)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 299 | `STALKER_HANG_S` | `0.8` | s, 떨어지기로 한 뒤 천장에 멈춰 노려보는 시간(예고, #59). 0 = 옛 동작(바로 놓는다). #60 플레이어 멈춤을 넣으면 1.2 |
| 300 | `STALKER_HANG_SWING_S` | `0.25` | s, 그중 천장 기기 클립(crawl)으로 섞는 시간 — 다 섞이면 그 자리에 멈춘다 |

#### 노려보기 (#59). F5(#58 뒤): 선 클립을 뒤집은 매달림은 곡예사처럼 읽힌다 → 리커처럼 엎드린 채 허리를 접어 상체… (Tuning.gd:301)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 302 | `STALKER_GLARE_ON` | `true` | 끄면 굽히지 않는다 (재기만 한다 — 사보타주용) |
| 303 | `STALKER_GLARE_RISE_S` | `0.35` | s, 상체를 드는 시간 (팔 뻗기도 같이 오른다). 나머지가 노려보는 시간 |
| 304 | `STALKER_GLARE_SPINE_DEG` | `45.0` | °, 척추 세 마디 합계 굽힘 (마디마다 1/3) |
| 305 | `STALKER_GLARE_HIP_DEG` | `10.0` | °, 엉덩이 뼈가 나눠 가지는 굽힘 (다리는 그만큼 되돌려 발을 천장에 둔다) |
| 306 | `STALKER_GLARE_BONE_MAX` | `20.0` | °, 마디 하나가 굽는 최대 — 넘기면 허리 표면이 접혀 찌그러진다 |
| 307 | `STALKER_GLARE_HEAD_DEG` | `50.0` | °, 목·머리가 플레이어 쪽으로 더 돌 수 있는 최대 (반씩). 제안 40 → 6 m 앞 플레이어를 못 봤다(실측 일치 0.88, 상체가 62~66° 들려서) |
| 308 | `STALKER_GLARE_BREATH_DEG` | `3.0` | °, 숨쉬기 — 척추 굽힘이 ± 이만큼 흔들린다 |
| 309 | `STALKER_GLARE_BREATH_HZ` | `0.8` | 초당 숨 횟수 |
| 310 | `STALKER_GLARE_TILT_DEG` | `15.0` | °, 고개 갸웃 (얼굴 축으로 천천히 기울여 그대로 둔다) |
| 311 | `STALKER_GLARE_TILT_AT` | `0.2` | s, 노려보기 시작부터 갸웃 시작까지 (상체를 드는 중에 시작한다) |
| 312 | `STALKER_GLARE_TILT_S` | `0.45` | s, 다 기울이는 시간 — 깜빡임(끝나기 STALKER_DROP_BLINK_AT 전) 무렵 끝난다. F5: 옛 0.25초에 꺾었다 돌아오기는 너무 빨랐다 |
| 313 | `STALKER_GLARE_CRAWL_T` | `0.0` | s, 멈춰 둘 crawl 시각 |
| 314 | `STALKER_GLARE_FADE_S` | `0.15` | s, 놓은 뒤 굽힘을 푸는 시간 — 한 프레임에 풀면 머리가 튄다 |
| 315 | `STALKER_REACH_ON` | `true` | 팔 뻗기 켬/끔. false = 클립 팔 그대로 (봇 사보타주용) |
| 316 | `STALKER_REACH_FRAC` | `0.9` | 팔 길이의 이 비율까지 뻗는다 — 다 펴면 막대처럼 보인다 |
| 317 | `STALKER_REACH_AIM_Y` | `1.2` | m, 뻗는 목표 = 플레이어 발 위 이 높이(가슴) |
| 318 | `STALKER_REACH_SIDE_M` | `0.5` | m, 두 팔 목표를 가슴에서 좌우로 벌리는 거리 (#59). 0 이면 두 손이 노려보는 얼굴 바로 앞을 가린다(플레이어 시점 캡처 92n) |
| 319 | `STALKER_FALL_CLIP` | `"land_hard"` | 낙하 클립. land_hard 의 공중 구간(0 ~ STALKER_LAND_FROM)을 낙하 시간에 맞춰 늘여 튼다. "fall_air" = 옛 동작(Falling Idle, 팔을 벌린다) |
| 320 | `STALKER_FALL_UPRIGHT_AT` | `0.9` | 낙하 시간의 이 비율에서 몸이 똑바로 선다 — 착지 전에 다 서 있게 |

#### 낙하 가리기 (#58). F5(09-13 16-39-18 영상 7.1~7.3초): 공중에서 몸이 옆으로 누운 채 한 덩어리로… (Tuning.gd:321)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 323 | `STALKER_DROP_BLACK` | `true` | 끄면 #57 그대로 (되돌리기·사보타주용) |
| 324 | `STALKER_DROP_BLINK_AT` | `0.15` | s, 매달림이 끝나기 이만큼 전에 한 번 깜빡 — "곧 온다" |
| 325 | `STALKER_DROP_BLINK_S` | `0.05` | s, 예고 깜빡임이 꺼져 있는 시간 (3프레임) |
| 326 | `STALKER_DROP_DARK_AFTER` | `0.12` | s, 착지한 뒤에도 더 꺼져 있는 시간 — 켜질 때 이미 웅크려 있게 |
| 327 | `STALKER_DROP_LIGHT_S` | `0.08` | s, 다시 켜지는 데 걸리는 시간 (툭 켜진다) |
| 328 | `STALKER_DROP_DUST` | `80` | 알, 손을 놓은 천장에서 쏟아지는 흙먼지 (파괴 먼지 DEATH_DUST 와 같은 양) |
| 329 | `STALKER_CLIP_RUN_STAND` | `4.05` | m/s, run_stand(zombie run) 실측 자연 속도. 추격 6.5 → 1.6배속 |
| 330 | `MINER_CLIP_Y_OFFSET` | `{"climb_down": -2.61}` | m, 클립이 원점에서 떠 있는 만큼 몸을 내린다 (실측: 내려가는 클립은 첫 프레임이 3 m 위) |
| 331 | `STALKER_CLIP_WALK` | `1.0` | m/s, walk_crouch 가 "제속도"로 보이는 이동 속도. 재생 배율 = 속도 ÷ 이 값 (최소 MINER_ANIM_SPEED). #45 세트 B Creeping Zombie Walk 의 실측 자연 속도는 0.45 — 그대로면 배회 2.5 에서 5.5배라 1.0 으로(2.5배, 미끄러짐 감수). 세트 A Crouched Walking 실측 1.24 |
| 332 | `STALKER_CLIP_RUN` | `3.0` | m/s, run 클립의 실측 자연 속도 (#45 세트 B running crawl 3.01. Mutant Run 3.11, zombie run 4.05). 추격 6.5 → 2.2배 |
| 333 | `PRESSURE_UP` | `2.0` | /s, 괴물이 숨어 있거나 PRESSURE_FAR_M 밖이면 오름 |
| 334 | `PRESSURE_DOWN` | `5.0` | /s, PRESSURE_NEAR_M 안이면 내림 |
| 335 | `PRESSURE_FAR_M` | `40.0` |  |
| 336 | `PRESSURE_NEAR_M` | `15.0` |  |
| 337 | `PRESSURE_SEND` | `80.0` | 여기 닿으면 시야 밖 곡선 칸에 내려놓음 |
| 338 | `PRESSURE_RECALL` | `20.0` | 여기 밑이면 철수 |
| 339 | `PRESSURE_FLOOR_MUL` | `0.25` | 층마다 오르는 속도 +25 % (층 수 = 난이도) |
| 340 | `SPAWN_CELLS_MIN` | `3` | 등장 자리: 플레이어에서 격자 거리 (곡선 칸, 시야 밖) |
| 341 | `SPAWN_CELLS_MAX` | `6` |  |
| 342 | `SPAWN_BEHIND_DOT` | `0.3` | 플레이어 앞 방향과 자리 방향의 내적이 이 밑이면 "시야 밖" |
| 343 | `CARD_LAMP_N` | `3` | 카드 어둠 수색: 조사·수색·추격 중 20 m 안에서 램프를 끈 횟수 |
| 344 | `CARD_CART_N` | `2` | 카드 광차 들여다보기: 20 m 안에서 광차에 숙여 탄 횟수 |
| 345 | `CARD_HABIT_M` | `20.0` |  |
| 346 | `CARD_EAR_MUL` | `1.5` | 어둠 수색: 귀 반경 배율 |
| 347 | `CARD_DWELL_MUL` | `2.0` | 어둠 수색: 수색 머무는 시간 배율 |
| 348 | `CARD_DARK_SPEED_MUL` | `0.7` | 어둠 수색 텔: 조사·수색이 느려지고 머리를 좌우로 훑는다 |
| 349 | `CARD_DARK_SWAY_DEG` | `25.0` |  |
| 350 | `CAUGHT_TEXT` | `"잡혔습니다."` |  |
| 351 | `CAUGHT_TURN_S` | `0.4` | s, 잡히면 시점이 괴물 쪽으로 돌아가는 시간. 램프도 같은 시간에 꺼진다 |

#### 정비 1 (#30) — 고장난 지지목. scripts/Fault.gd · RepairPart.gd · RepairHud.gd.… (Tuning.gd:352)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 353 | `FAULT_SET` | `1` | 직선 조각의 세트 번호 (0~3). 그 세트의 post_L 을 숨기고 cap 을 기울인다 |
| 354 | `FAULT_CAP_TILT_DEG` | `12.0` | 기운 갓보 |

#### 자재함 (#31) — 정거장 앞 첫 직선 오른쪽 벽. E 로 부품 하나. scripts/PartsBin.gd (Tuning.gd:355)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 356 | `ORE_PER_PART` | `5` | 좋은 부품 하나에 광석 (사용자 09-10: 3 → 5). 모자라면 삐걱 부품(무한) |
| 357 | `SKILL_ZONE_GOOD_DEG` | `90.0` | 좋은 부품 성공 구간 (삐걱 SKILL_ZONE_DEG 50) |
| 358 | `SKILL_INTERVAL_GOOD_MIN` | `6.0` | 좋은 부품 체크 간격 (삐걱 3~5) |
| 359 | `SKILL_INTERVAL_GOOD_MAX` | `9.0` |  |
| 360 | `PART_GOOD_TINT` | `Color(1.0, 0.92, 0.75)` | 새 통나무 색 (삐걱은 TIMBER_TINT) |
| 361 | `BIN_SIZE` | `Vector3(1.2, 0.9, 0.9)` |  |
| 362 | `BIN_DROP` | `1.2` | m, 부품이 놓이는 거리 (자재함 앞, 통로 쪽) |
| 363 | `PART_SIZE` | `Vector3(0.3, 0.3, 2.6)` |  |
| 364 | `CARRY_SPEED_MUL` | `0.6` | 들고 있을 때 걷기 배율 (끌기와 같은 규칙). 점프 불가 |
| 365 | `CARRY_REACH` | `2.5` | m, E 가 먹는 거리 (줍기·세우기) |
| 366 | `REPAIR_HOLD_S` | `12.0` | s, 자리당 E 를 누르고 있는 시간 |
| 367 | `SKILL_INTERVAL_MIN` | `3.0` | s, 스킬체크 간격 |
| 368 | `SKILL_INTERVAL_MAX` | `5.0` |  |
| 369 | `SKILL_NEEDLE_RPS` | `0.8` | 바늘 회전/초 |
| 370 | `SKILL_ZONE_DEG` | `50.0` | 성공 구간 ("삐걱 부품". 좋은 부품은 #31 에서 넓게) |
| 371 | `REPAIR_FAIL_BACK` | `0.25` | 실패 시 진행 후퇴 |
| 372 | `DANGER_REPAIR_FAIL` | `15.0` | 게이지 (#24: 실패 +M > 성공 −N) |
| 373 | `DANGER_REPAIR_DONE` | `5.0` |  |
| 374 | `FAIL_SHAKE_AMOUNT` | `0.06` | 실패 흔들림 = 붕괴 흔들림 폭. 소음은 ⑥ |
| 375 | `FAIL_SHAKE_TIME` | `0.3` |  |
| 376 | `SVC_ON` | `1` | 0 = 안 놓음 (비교·사보타주) |
| 377 | `SVC_CABLE_H` | `3.2` | m, 케이블 걸이 높이 (광산안전기술기준 80조 "안전높이" = 머리 위) |
| 378 | `SVC_CABLE_SAG` | `0.12` | m, 기둥 사이 처짐 (칸 경계에서도 처진다 — 세트 간격 1.75 가 칸을 넘어 이어져서) |
| 379 | `SVC_CABLE_R` | `0.024` | m, 동력 케이블 반지름 (개장케이블 지름 48) |
| 380 | `SVC_DUCT_R` | `0.30` | m, 풍관 반지름 (지름 600 = 24 in 표준) |
| 381 | `SVC_DUCT_H` | `3.9` | m, 풍관 중심 높이 (어깨) |
| 382 | `SVC_DUCT_X` | `2.05` | m, 풍관 중심이 갱도 가운데서 왼쪽으로 |
| 383 | `SVC_DRAIN_R` | `0.075` | m, 배수관 반지름 (지름 150) |
| 384 | `SVC_DRAIN_H` | `0.32` | m, 배수관 중심 높이 |
| 385 | `SVC_DRAIN_X` | `3.05` | m, 배수관 x (오른쪽 벽, 기둥 안쪽 면 3.16 안) |
| 386 | `SVC_DITCH_W` | `0.36` | m, 배수로 폭 (왼쪽 벽 옆 x −2.75) |
| 387 | `SVC_LAG_P` | `0.45` | 기둥 사이 구간에 라깅(널판)이 있을 확률. 위쪽 2.4~4.4 m 만 |
| 388 | `SVC_LAMP_EVERY` | `2` | 참고값: 갓등은 세트 0·2 = 3.5 m 마다 (코드는 세트 번호로 박혀 있다) |
| 389 | `SVC_VALVE_EVERY` | `8` | 직선 몇 칸마다 밸브+호스 변형 |
| 390 | `SVC_JBOX_EVERY` | `10` | 직선 몇 칸마다 접속함 변형 |
| 391 | `SVC_SIGN_EVERY` | `6` | 직선 몇 칸마다 전화기+표지 변형 |
| 392 | `SVC_WATER_ROUGH` | `0.3` | 배수로 물 거칠기. 0.05 는 거울 = 램프 흰 점 |
| 393 | `SVC_TRI_MAX` | `4000` | 칸당(L+R) 삼각형 상한 |
| 394 | `DRIP_STRETCH` | `4.0` | 수직면에서 얼룩을 세로로 늘리는 배율 — 흘러내린 자국 |
| 395 | `WET_BAND` | `1.2` | m, 바닥에서 이 높이까지는 더 젖는다 — 물은 아래에 고인다 |
| 396 | `WET_BAND_ADD` | `0.25` | 그 띠에서 노이즈에 더하는 값 (0.18 이면 WET_LOW 를 넘어 확실히 젖음) |
| 397 | `TIMBER_TINT` | `Color(0.6, 0.52, 0.45)` | 갱목(MAT_Timber) 텍스처에 곱하는 색. 1,1,1 = 텍스처 그대로. Blender 의 나무 틴트는 내보내기에서 빠진다 — 여기서 곱한다. medieval_wood + (0.42, 0.30, 0.20) 은 "어둡지만 오래된 느낌이 없다"(#19 2차 판정) → 텍스처를 dark_wooden_planks 로 바꾸고(export.sh) 틴트는 약하게 |
| 401 | `AMBIENT_ENERGY` | `0.03` | 램프 밖의 잔광. 0.05 → 0.03. 0 이면 그림자 속이 완전 검정이라 형태가 안 읽힌다 |
| 402 | `FOG_DENSITY` | `0.03` | 거리 안개. 0.06 은 10m 너머 바닥 무늬까지 뿌옇게 지웠다. 0 이면 끔 |
| 403 | `FOG_COLOR` | `Color(0.006, 0.008, 0.008)` | 잠기는 색. 검정에 가까운 청록. 밝게 두면 램프를 꺼도 화면이 이 색으로 남아 "램프 끔 = 어두움" 검사가 깨진다 |
| 405 | `VOLFOG_DENSITY` | `0.012` | 부피 안개. 램프 원뿔이 공기 중에 빛줄기로 보이는 정도. 0 이면 끔. 0.03 은 머리에 단 등이라 화면 전체가 뿌연 덩어리가 됐다(대비 죽음). 램프를 이마에 달면 늘 빛줄기 안에서 본다 — 옅어야 한다 |
| 408 | `VOLFOG_ALBEDO` | `Color(0.6, 0.6, 0.55)` | 공기 중 먼지 색. 약간 누런 회색 |
| 409 | `VOLFOG_ANISOTROPY` | `0.6` | 빛을 앞으로 뿌리는 정도. 클수록 빛줄기가 또렷 |
| 410 | `ADJ_CONTRAST` | `1.0` | 대비. 1.0 = 그대로. 올리지 마라 — Godot 은 0.5 를 축으로 늘리는데 이 게임은 화면 대부분이 0.01~0.1 이라 1.15 만으로 전부 0 에 깔렸다 (실측: 화면 평균 0.0111 → 0.0026) |
| 413 | `ADJ_SATURATION` | `0.75` | 채도. 1.0 = 그대로. 낮출수록 회색 광산 |
| 414 | `VIGNETTE` | `0.35` | 가장자리 어두워지는 세기. 0 = 없음 |
| 415 | `GRAIN` | `0.0` | 필름 그레인. 밝기에 곱한다. 0.025 는 "있는지 모르겠다", 0.08 은 "거슬린다" (사용자 09-08 두 판정) — 끈다. 켜려면 이 둘만 올린다 |
| 417 | `GRAIN_FLOOR` | `0.0` | 어둠에서도 남는 알갱이의 바닥값 (0.015 였다). 검은 화면 검사(0.008) 실측 0.0037 안에서. 잡음은 평균 0 이지만 검정에서 0 으로 잘려 램프 끔 밝기를 0.006 올렸다 |

#### 평타 파편 (Tuning.gd:420)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 421 | `CHIP_PER_HIT` | `2` | 평타 한 번에 튀는 자갈 수. 많으면 벽이 부서질 때와 구분이 안 된다 |
| 423 | `CHIP_POP` | `2.4` | m/s, 벽에서 튕겨나가는 속도. 조각(1.8)보다 빠르게 |
| 424 | `CHIP_LIFE` | `1.2` | 초, 파괴 조각(3.0)보다 짧게. 안 쌓이게 |

#### 위험 게이지 (Tuning.gd:426)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 430 | `DANGER_MAX` | `100.0` | 바가 꽉 차는 값 |
| 431 | `DANGER_PER_HIT` | `0.0` | 곡괭이가 포켓에 닿을 때마다. #24 로 0 (1.5 였다) |
| 432 | `DANGER_PER_DROP` | `0.0` | 리프트로 한 층 내려가는 동안 거리에 비례해. #24 로 0 (20 이었다) |
| 433 | `DANGER_TREMOR_FROM` | `60.0` | 이 값부터 갱도가 주기적으로 떨린다 |
| 434 | `DANGER_TREMOR_INTERVAL` | `2.0` | 초 |
| 435 | `DANGER_TREMOR_AMOUNT` | `0.02` | m, 파괴 흔들림(0.06)의 1/3 폭 |
| 436 | `DANGER_TREMOR_TIME` | `0.4` | 초, 파괴 흔들림(0.15)보다 길게. 폭은 작고 오래 |
| 437 | `DANGER_COLOR_LOW` | `Color(0.30, 0.80, 0.35)` | 0% |
| 438 | `DANGER_COLOR_MID` | `Color(0.95, 0.80, 0.20)` | 50% |
| 439 | `DANGER_COLOR_HIGH` | `Color(0.90, 0.20, 0.15)` | 100% |

#### 붕괴 (위험 100) (Tuning.gd:441)

| 줄 | 이름 | 값 | 주석 |
|---|---|---|---|
| 443 | `DEATH_SHAKE_AMOUNT` | `0.15` | m, 파괴 흔들림(0.06)의 2.5배 |
| 444 | `DEATH_SHAKE_TIME` | `1.2` | 초 |
| 445 | `DEATH_ROCKS` | `24` | 개, 평타 자갈 메시를 머리 위에서 떨어뜨린다 |
| 446 | `DEATH_ROCK_HEIGHT` | `3.0` | m, 머리 위 |
| 447 | `DEATH_ROCK_RADIUS` | `2.5` | m |
| 448 | `DEATH_DUST` | `80` | 알, 파괴 먼지(60)보다 많이 |
| 449 | `DEATH_LAMP_FADE` | `0.9` | 초, 램프 에너지 -> 0 |
| 450 | `DEATH_BLACK_TIME` | `1.2` | 초, 이때부터 검은 화면 |
| 451 | `DEATH_BLACK_FADE` | `0.3` | 초 |
| 452 | `DEATH_RESTART_TIME` | `3.0` | 초, 방을 다시 띄운다 |
| 453 | `DEATH_TEXT` | `"광산이 무너졌습니다."` |  |

