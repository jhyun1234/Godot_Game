# NewGame — 1인칭 광산 호러 (Godot 프로토타입)

> **저장소 상태: Unity 이전을 검토 중인 아카이브 저장소**
> 이 저장소의 GDScript는 Unity로 옮기지 않는다. 갱도 구조·조명 값·이동 수치·에셋 파이프라인을 참고하는 용도로 보관한다.
> 작업 기간: 2026-09-05 ~ 2026-09-13. 마지막 상태는 [`docs/HANDOFF.md`](docs/HANDOFF.md)에 있다.

1인칭 광산 하강 호러. 헤드램프 하나에 의지해 갱도로 내려가, 돌아오지 않은 광부들의 시신을 회수한다.
(기획 문서의 장르명은 "1인칭 회수 공포" — [`CLAUDE.md`](CLAUDE.md) §15)

---

## 어디부터 읽나

이 README는 입구다. 내용은 아래 문서에 있다.

| 순서 | 문서 | 내용 |
|---|---|---|
| 1 | [`docs/HANDOFF.md`](docs/HANDOFF.md) | **현재 상태.** 맨 위 "다음 세션은 여기서 시작한다" → "지금까지 만든 것"(제안서별 기록) → "다음에 할 일 — 순서표" → "실행 방법" |
| 2 | [`MIGRATION_NOTES.md`](MIGRATION_NOTES.md) | Unity 이전용 정리 — 기능별 완성도, 스크립트 역할, 씬 구조, 에셋, Godot 전용 기능 의존 부분 |
| 3 | [`LOOK_REFERENCE.md`](LOOK_REFERENCE.md) | 목표 룩 — 스크린샷, 레퍼런스 게임, 최소 사양, 현재 렌더링·조명 설정 값 |
| 4 | [`CLAUDE.md`](CLAUDE.md) | 작업 규칙 + §15 기획 맥락(핵심 루프, 괴물, 수리, 게이지, 맵 규칙) |
| 5 | [`docs/DESIGN_REVIEW.md`](docs/DESIGN_REVIEW.md) | 기획 점검과 결정의 흐름 |
| 6 | [`docs/MAP_STRUCTURE.md`](docs/MAP_STRUCTURE.md) | 맵·층·미로·조각 구조 |

---

## 버전

| 항목 | 값 | 출처 |
|---|---|---|
| Godot | **4.7.2-stable** (win64) | `tools/build.sh` 10번째 줄의 에디터 실행 파일 경로 `Godot_v4.7.2-stable_win64` |
| Godot (프로젝트 파일) | 4.7 | `project.godot` `config/features` — 마이너 버전까지만 기록됨 |
| 렌더러 | Forward Plus | `project.godot` `config/features` |
| 템플릿 | [Maaack's Godot Game Template](https://github.com/Maaack/Godot-Game-Template) **1.6.0** | `addons/maaacks_game_template/plugin.cfg` |
| 플러그인 업데이터 | plugin_updater 0.5.1 | `addons/plugin_updater/plugin.cfg` |

Godot은 마이너 버전 사이에도 임포트 동작이 바뀔 수 있다. 이 프로젝트를 다시 열 때는 4.7.2를 쓴다.

---

## 실행

- **게임**: Godot 4.7.2에서 프로젝트를 열고 F5.
  시작 씬은 템플릿 오프닝(`addons/scenes/opening/opening.tscn`)이고, 메인 메뉴의 새 게임이 `scenes/level/Tunnel.tscn`을 연다
  (`project.godot` `[maaacks_game_template] game_scene_path`).
- **빌드 + 검사**: `bash tools/build.sh` (임포트 → 소스 검사 → exe 익스포트 → 배포물 검사 → 플레이 봇).
  구간만 돌릴 때는 `bash tools/quick.sh <구간>`.
  스크립트 안의 Godot 실행 파일 경로가 원래 PC 기준으로 적혀 있다 — 다른 PC에서는 `GODOT=` 줄을 고쳐야 한다.
- 자세한 명령은 [`docs/HANDOFF.md`](docs/HANDOFF.md) "실행 방법".

---

## 폴더 구조

```
new-game/
├── addons/
│   ├── maaacks_game_template/   템플릿 본체 (메뉴·옵션·로딩·씬 전환)
│   ├── scenes/, scripts/,       템플릿 설치 시 복사된 예제·게임 셸 (메뉴, 일시정지, 크레딧 등)
│   │   resources/, assets/
│   └── plugin_updater/          템플릿 업데이트 플러그인
├── assets/
│   ├── generated/               Blender 스크립트가 뽑은 파생 모델
│   │   ├── tunnel/              갱도 조각 13종, 레일, 정거장, 리프트 케이지, 광차, 곡괭이, 광석, 소품 (.gltf)
│   │   ├── monster/             괴물 모델 miner_rigged.glb + 텍스처
│   │   └── palette/             색 팔레트 아틀라스
│   └── kaykit/                  KayKit 원본 팩 (dungeon, resourcebits, rpgtools) — 갱도 안에서는 쓰지 않음
├── scenes/
│   ├── level/                   Tunnel.tscn(본 게임), TestRoom.tscn(옛 시험 방), Lift, Miner, Ore, OrePocket
│   ├── player/                  Player.tscn, Pickaxe.tscn
│   ├── ui/                      DangerHud, DeathScreen, OreHud
│   └── fx/                      Dust
├── scripts/                     게임 코드 GDScript 31개. 모든 수치는 Tuning.gd
├── shaders/                     post.gdshader(후처리), wet_rock.gdshader
├── tools/
│   ├── build.sh, quick.sh       빌드·검사
│   ├── qc.py                    봇 캡처 화면 검수
│   ├── time.sh                  누적 개발 시간
│   ├── minetunnel/              갱도·소품 Blender 스크립트 + Godot 내보내기
│   └── miner/                   괴물 모델 생성·리깅·재질 파이프라인 (stage4~11)
├── docs/                        HANDOFF, DESIGN_REVIEW, MAP_STRUCTURE
├── CLAUDE.md                    작업 규칙 + 기획 맥락
└── project.godot
```

**이 저장소에 없는 것** (`.gitignore` 또는 저장소 밖):

| 대상 | 이유 |
|---|---|
| `.godot/` | 임포트 캐시, 열면 재생성 |
| `build/` | exe·캡처·촬영물 등 빌드 산출물 |
| `addons/ziva_agent/` | 외부 도구 (실행 파일 125MB) |
| `tools/qc_golden/` | 화면 검수 기준 PNG — 옛 히스토리 1.98GB의 원인이라 제외, 로컬 백업. **없으면 `qc.py` 기준 대조를 못 돈다** |
| `export_presets.cfg` | 로컬 경로가 들어갈 수 있음. 없으면 exe 익스포트 전에 Windows Desktop 프리셋(산출물 `build/NewGame.exe`)을 다시 만들어야 한다 |
| Blender 원본 `.blend` | 저장소 밖 `Documents/MineTunnel/` (갱도 모듈 원본). 스크립트 사본만 `tools/minetunnel/`에 있다 |
| 옛 git 히스토리 (커밋 130개) | 이 저장소는 새로 시작했다. 옛 히스토리는 저장소 밖 로컬 백업 |

---

## 구현된 것

`docs/HANDOFF.md` 기준 (제안서 #1~#59). 완성도 판정(완성 / 부분 / 껍데기)은 `MIGRATION_NOTES.md`에서 한다.

- **1인칭 이동** — 숙이기 / 걷기 / 달리기 + 점프, 스태미나(화면 표시 없음)·탈진
- **헤드램프** — 스포트라이트, F로 끄기, 끈 뒤 눈 적응
- **채굴** — 곡괭이 뷰모델, 벽의 광맥 포켓을 두 번 쳐서 광석 획득, 곡괭이 던지기(착지 소음·괴물 스턴·줍기)
- **리프트** — 정거장에서 E로 층 사이 하강·상승
- **갱도 조립기** — 시드로 층 하나를 245m 미로로 조립 (`MineAssembler.gd`). 조각 카탈로그 13종, 층 2개(시드 7·8), 소품·설비 배치
- **광차** — 순환선 위를 돌고 정거장에서 정차, 타고 내리기
- **정비** — 지지목 고장, 자재함에서 부품(품질 2단계), 나르기·세우기, 누르고 있기 + 스킬체크
- **공유 게이지 · 붕괴 · 사망 화면**
- **소음** — 곡괭이·정비 실패·발걸음·광차가 반경을 가진 소음을 냄 (`NoiseBus`), 소음 HUD
- **갱도 괴물 한 마리 + 감독** — 귀·눈·빛 감각, 배회·조사·수색·추격·잡기·철수·스턴, 감독 압박, 격자 길찾기, 배움 카드 2종, 벽·천장 기어가기, 천장 낙하 연출 (`Stalker.gd`, `Director.gd`)
- **괴물 모델** — 이미지→3D 생성 + Mixamo 리깅 + 생성 텍스처 (`tools/miner/`)
- **개발 도구** — 플레이 봇·숫자 검사·캡처 (`DevBot.gd`), 빌드 스크립트, 화면 검수 (`qc.py`)

마지막 작업(#59 천장 노려보기 자세)은 커밋됐고 사용자 플레이 판정 전에 멈췄다.

## 안 된 것

`docs/HANDOFF.md` "다음에 할 일 — 순서표" 기준.

- **소리** — 오디오 파일이 하나도 없다 (게임 쪽 소리 0개)
- 맨 위 층 · 검수대 · 게시판 · 계약 · 자재고
- 시신 인형 (끌기·적재)
- 검수(0원) · 파쇄장 · 시신 괴물 규칙
- 배움 카드 나머지 3종
- 동물
- 상점 (괴물 쫓아내기 도구)
- 낙서 · 이벤트 · 결말
- 협동 네트워크 (최대 4인 계획)
- 괴물 수치 판정(⑦b) · 철수 이유를 보이게 하기(⑦b′)
- 알려진 문제: 괴물이 천장에 설계값(12초)보다 짧게 머묾 — 원인 미확인 (HANDOFF #61)
