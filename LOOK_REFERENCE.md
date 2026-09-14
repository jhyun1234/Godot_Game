# LOOK_REFERENCE — 목표 룩과 현재 렌더링 값

Unity로 옮길 때 첫날 정해야 하는 HDRP / URP 판단용 자료 모음.
4~6절은 파일에서 읽은 **실제 값**만 적었다. 파일·코드 어디에도 설정이 없는 항목은 기본값을 추정하지 않고 "설정 없음" 또는 "확인 불가"로 적었다.

조사 기준: 2026-09-14, `C:\Users\anjyo\Tunnel\new-game` 작업 폴더.

---

## 1. 스크린샷

위치: [`docs/screenshots/`](docs/screenshots/). 출처는 플레이 봇 화면 검수 캡처 `tools/qc_golden/`(저장소 밖 백업)이며, 해상도는 전부 1140×641(봇 창 크기)이다.
화면의 원형 밝은 영역 밖이 검은 것은 헤드램프 원뿔 조명이다. 오른쪽의 곡괭이, 왼쪽 아래 "철 N", 오른쪽 아래 막대는 HUD다.

| 파일 | 보여주는 것 |
|---|---|
| [`play_09_lamp.png`](docs/screenshots/play_09_lamp.png) | 직선 갱도. 갱목 틀이 소실점까지 반복되고 끝이 어둠에 잠긴다 — 헤드램프가 비추는 거리와 깊이감 |
| [`play_01_walk.png`](docs/screenshots/play_01_walk.png) | 기본 걷기 시점. 레일 두 줄, 양옆 갱목, 램프 원 안만 보이는 화면 구성 |
| [`play_25_station_far.png`](docs/screenshots/play_25_station_far.png) | 레일 끝에 수갱 정거장 입구 틀이 보이는 먼 거리 컷 — 안개와 거리 감쇠 |
| [`play_11_lift_far.png`](docs/screenshots/play_11_lift_far.png) | 리프트 케이지 안쪽. 금속 창살과 나무 바닥이 램프에 따뜻한 색으로 비친다 — 금속·목재 재질 반응 |
| [`play_93_lamp_pass.png`](docs/screenshots/play_93_lamp_pass.png) | 거의 검은 화면에 레일과 곡괭이 윤곽만 희미하게 남은 컷 — 이 게임의 어둠의 하한 |

## 2. 레퍼런스 게임

사용자 지정 (2026-09-14). 특정 장면이나 스크린샷은 지정하지 않았다.

- **Alien: Isolation**
- **Amnesia: The Bunker**
- **SOMA**

## 3. 최소 사양 목표

**잠정 목표: GTX 1650 / 1080p / 60fps**

근거: 레퍼런스로 삼은 Alien: Isolation, SOMA, Amnesia: The Bunker의 플레이어층을 기준으로 잡음. 확정 아님 — 세로 슬라이스가 나온 뒤 재검토.

(2026-09-14 결정. 처음 답은 "모르겠음"이었다.)

## 3-1. Unity 렌더 파이프라인: URP

**결정: URP** (사용자 결정, 2026-09-14)

근거:
- 3절의 최소 사양 목표(GTX 1650 / 1080p / 60fps)
- 현재 게임의 실시간 라이트는 **헤드램프 SpotLight3D 1개**뿐이다 (5절)
- 전역 조명(SDFGI·VoxelGI·LightmapGI)과 화면 공간 효과(SSAO·SSIL·SSR·Glow)는 **0개**다 (4-2절)

Unity 첫날 필요한 것:
- 현재 룩은 **볼류메트릭 안개**(밀도 0.012, 4-3절)에 기댄다. URP에는 볼류메트릭 안개가 기본 제공되지 않아 별도 패키지가 필요하다

---

## 4. 현재 Godot 렌더링 설정

값이 세 곳에서 온다: `project.godot`, 씬의 `Environment` 리소스(`scenes/level/Tunnel.tscn`), 실행 중 덮어쓰는 코드(`scripts/Atmosphere.gd` 자동 실행, 수치는 `scripts/Tuning.gd`). **실행 중 값은 코드가 이긴다.**

### 4-1. 렌더러

| 항목 | 값 | 출처 |
|---|---|---|
| 렌더 방식 | Forward Plus | `project.godot` `config/features=PackedStringArray("4.7", "Forward Plus")` |
| `rendering/renderer/rendering_method` | 명시 없음 | `project.godot` `[rendering]` 절에 없음 |
| 그래픽 드라이버 (Windows) | d3d12 | `project.godot` `rendering_device/driver.windows="d3d12"` |

### 4-2. 전역 조명 · 화면 공간 효과

| 항목 | 값 | 출처 |
|---|---|---|
| SDFGI | **설정 없음** | `Tunnel.tscn` Environment · `Atmosphere.gd` · `project.godot` 어디에도 없음 |
| SSAO | **설정 없음** | 위와 같음 |
| SSIL | **설정 없음** | 위와 같음 |
| SSR | **설정 없음** | 위와 같음 |
| Glow | **설정 없음** | 위와 같음 |
| VoxelGI / LightmapGI / ReflectionProbe 노드 | 0개 | `scenes/` 모든 `.tscn` 검색 |

### 4-3. 안개

| 항목 | 값 | 출처 |
|---|---|---|
| 거리 안개 | 켜짐 | `Atmosphere.gd:205` (`FOG_DENSITY > 0`) |
| 거리 안개 방식 | Exponential | `Atmosphere.gd:206` |
| 거리 안개 밀도 | **0.03** | `Tuning.gd:402` `FOG_DENSITY` |
| 거리 안개 색 | (0.006, 0.008, 0.008) | `Tuning.gd:403` `FOG_COLOR` |
| sun_scatter / aerial_perspective | 0.0 / 0.0 | `Atmosphere.gd:209-210` |
| **볼류메트릭 안개** | **켜짐** | `Atmosphere.gd:211` (`VOLFOG_DENSITY > 0`) |
| 볼류메트릭 안개 밀도 | **0.012** | `Tuning.gd:405` `VOLFOG_DENSITY` |
| 볼류메트릭 안개 albedo | (0.6, 0.6, 0.55) | `Tuning.gd:408` |
| 볼류메트릭 안개 anisotropy | 0.6 | `Tuning.gd:409` |
| 볼류메트릭 안개 ambient_inject | 0.0 | `Atmosphere.gd:215` |
| 볼류메트릭 안개 length / detail | 설정 없음 | 파일·코드에 없음 |
| 램프를 끄고 눈이 적응한 뒤 거리 안개 밀도 | 0.45 (4.0초에 걸쳐) | `Tuning.gd:156-157`, `Atmosphere.gd:181` |

### 4-4. 배경 · 환경광 · 톤 · 후처리

| 항목 | 값 | 출처 |
|---|---|---|
| 배경 | `background_mode = 1` (Color), 색 (0.02, 0.02, 0.03) | `Tunnel.tscn` `Environment_tunnel` |
| 환경광 소스 | `ambient_light_source = 2` (Color), 색 (0.1, 0.12, 0.2) | `Tunnel.tscn` |
| 환경광 세기 | 씬 파일 0.05 → **실행 중 0.03** | `Tunnel.tscn` / `Tuning.gd:401` `AMBIENT_ENERGY`, `Atmosphere.gd:204` |
| 램프를 끄고 눈이 적응한 뒤 환경광 | 3.0 (4.0초에 걸쳐) | `Tuning.gd:155-156` |
| 톤매핑 | `tonemap_mode = 2` (Godot `Environment` 열거값 2 = Filmic) | `Tunnel.tscn` |
| 노출 / CameraAttributes | 설정 없음 | 씬·코드에 없음 |
| 색 보정 | 켜짐 — brightness 1.0, contrast 1.0, saturation **0.75** | `Atmosphere.gd:216-219`, `Tuning.gd:410,413` |
| 후처리 셰이더 | `shaders/post.gdshader`를 CanvasLayer 0의 전체 화면 ColorRect에 적용 | `Atmosphere.gd:228-242` |
| 비네트 | 0.35 | `Tuning.gd:414` `VIGNETTE` |
| 필름 그레인 / 바닥값 | 0.0 / 0.0 (꺼짐) | `Tuning.gd:415,417` |
| 카메라 FOV | 80 | `scenes/player/Player.tscn` `Camera3D` |

`scenes/level/TestRoom.tscn`(옛 시험 방)의 Environment 값은 `Tunnel.tscn`과 같다.

### 4-5. 그림자 · 안티앨리어싱

| 항목 | 값 | 출처 |
|---|---|---|
| 헤드램프 그림자 | 켜짐 | `Tuning.gd:153` `LAMP_SHADOW := true`, `Player.gd:66` |
| 그림자 품질 (atlas 크기, 필터, 소프트 섀도) | **확인 불가** — `project.godot`·씬·코드에 설정 없음 | |
| 그림자 bias / blur 등 라이트별 값 | **확인 불가** — `Headlamp` 노드와 `Player.gd`에 설정 없음 | |
| 곡괭이 뷰모델 그림자 | 끔 (등과 같은 자리라 화면을 덮음) | `Player.gd:68-` |
| 안티앨리어싱 (MSAA / FXAA·SMAA / TAA) | **확인 불가** — `project.godot`·`override.cfg`·씬·코드에 설정 없음 | |
| 3D 해상도 스케일 (FSR 등) | **확인 불가** — 설정 없음 | |

---

## 5. 씬의 조명 구성

**실시간 라이트는 헤드램프 하나뿐이다.** 태양·방 조명·갱도 전등 라이트가 없다.

| 위치 | 라이트 | 개수 | 출처 |
|---|---|---|---|
| `scenes/level/Tunnel.tscn` (본 게임) | 없음 | 0 | 노드 검색 |
| `scenes/level/TestRoom.tscn` | 없음 | 0 | 노드 검색 |
| `scenes/player/Player.tscn` → `Head/Headlamp` | SpotLight3D | **1** | `Player.tscn:46` |
| `assets/generated/**/*.gltf` | 없음 (`KHR_lights_punctual` 0건) | 0 | glTF 검색 |
| 코드로 생성 (`*Light3D.new()`) | 없음 | 0 | `scripts/` 검색 |

### 헤드램프 파라미터

노드에는 속성이 없고, `Player.gd:54-66` `_setup_headlamp()`가 `Tuning.gd` 값을 넣는다.

| 파라미터 | 값 | `Tuning.gd` |
|---|---|---|
| spot_angle (원뿔 반각) | 40.0° | `LAMP_ANGLE_DEG` :133 |
| spot_angle_attenuation | 0.45 | `LAMP_ATTEN` :135 |
| spot_range | 14.0 m | `LAMP_RANGE` :143 |
| spot_attenuation (거리 감쇠) | 0.6 | `LAMP_DIST_ATTEN` :149 |
| light_energy | 5.0 | `LAMP_ENERGY` :145 |
| light_color | (1.00, 0.96, 0.88) | `LAMP_COLOR` :151 |
| shadow_enabled | true | `LAMP_SHADOW` :153 |
| 위치 | 카메라 기준 (0, 0.12, 0) — 이마 자리 | `LAMP_OFFSET` :140 |
| 시점 따라가기 지연 | 0.10초 (`top_level`로 카메라와 분리) | `LAMP_FOLLOW_TIME` :138 |
| 걸을 때 끄덕임 | 0.01° | `LAMP_BOB` :141 |
| F로 끄고 켜기 | 0.15초 트윈 | `LAMP_TOGGLE_TIME` :154 |

헤드램프가 꺼지는 다른 경우: 사망(서서히 꺼짐, `Player.gd:107`), 괴물에게 잡힘(`Player.gd:131`), 괴물 천장 낙하 순간 정전(`Player.gd:141-148`).

### 빛처럼 보이지만 라이트가 아닌 것

- **갓등**: 갱도 설비의 전등은 메시만 있는 "죽은 등"이다 (`MineAssembler.gd:1042` 주석). 전구 재질 `MAT_Bulb`에는 텍스처와 발광 값이 없다.
- **오일 램프 불꽃**: `mine_props.gltf`, `mine_tunnel_module.gltf`의 `vintage_oil_lamp_flame` 재질이 발광(emissive) 텍스처와 emissiveFactor (1, 1, 1)를 가진다. 라이트는 아니다.

---

## 6. 머티리얼이 쓰는 텍스처 채널

### 6-1. 요약

| 채널 | 쓰는 곳 |
|---|---|
| 베이스 컬러 | 텍스처가 있는 재질 전부 |
| 노멀 | 갱도 조각·소품 glTF 재질 전부, 괴물의 갱목·주철 부분 |
| 러프니스 | 갱도 조각·소품 glTF (metallicRoughness 텍스처) |
| 메탈릭 | glTF의 metallicRoughness 텍스처에 포함. **단, 젖은 바위 셰이더로 바뀌는 벽·바닥은 메탈릭 텍스처를 넘기지 않는다** |
| AO (occlusion) | **없음** — 어떤 glTF/glb 재질에도 occlusionTexture 없음 |
| 이미시브 | 오일 램프 불꽃 재질 하나뿐 |

### 6-2. 갱도·소품 glTF (`assets/generated/tunnel/*.gltf`)

| 재질 | base | metalRough | normal | occlusion | emissive | 비고 |
|---|---|---|---|---|---|---|
| `MAT_RockWall_EXPORT`, `MAT_Floor_EXPORT` | O | O | O | – | – | metallicFactor 0. **실행 중 젖은 바위 셰이더로 교체** (6-3) |
| `MAT_Rock_EXPORT` | O | O | O | – | – | metallicFactor 0 |
| `MAT_Timber_EXPORT` | O | O | O | – | – | 실행 중 albedo_color에 (0.6, 0.52, 0.45) 곱함 (`Tuning.gd:397`, `Atmosphere.gd:74-75`) |
| `MAT_RustyMetal_EXPORT` | O | O | O | – | – | metallicFactor 0 |
| Poly Haven 소품 (barrel, bucket, crate, oil_lamp, lamp_glass, sledgehammer, spade) | O | O | O | – | – | |
| `vintage_oil_lamp_flame` | O | – | – | – | **O** | emissiveFactor (1, 1, 1), metal 0, rough 0 |
| `MAT_Cable` | – | – | – | – | – | 값만: metal 0, rough 0.55 |
| `MAT_Bulb` | – | – | – | – | – | 텍스처·값 없음 |
| `MAT_Ore` (`ore.gltf`) | – | – | – | – | – | 값만: metal 0.55, rough 0.3 |

벽·바닥 텍스처 원본은 Poly Haven `rock_face_04` 2K(벽)와 `brown_mud_rocks_01` 2K(바닥)다 (`CLAUDE.md` §15).

### 6-3. 젖은 바위 셰이더 (`shaders/wet_rock.gdshader`)

`Atmosphere.gd:117-142`가 `MAT_RockWall`, `MAT_Floor`로 시작하는 재질을 이 ShaderMaterial로 바꾼다.

| 넘기는 것 | 값 |
|---|---|
| albedo 텍스처 | glTF 원본 그대로 |
| normal 텍스처 | glTF 원본 그대로, normal_scale **1.6** (`ROCK_NORMAL_SCALE`) |
| roughness 텍스처 | glTF 원본 그대로, 채널은 원본 재질 설정 (glTF는 G) |
| 메탈릭 텍스처 | **넘기지 않음** (셰이더에 uniform 없음) |
| AO 텍스처 | 없음 |
| 미세 결 노멀 | 같은 노멀맵을 6.0배 잘게, 세기 0.6 (`DETAIL_NORMAL_TILES`, `DETAIL_NORMAL_STRENGTH`) |
| 트라이플래너 (세계 좌표 3면 샘플링) | 켜짐 — 벽 0.42 (2.4 m 한 장), 바닥 0.70 (1.4 m 한 장), blend 4.0 |
| 마른 바위 반사율 | 0.25 (`ROCK_SPECULAR`) |
| 젖은 얼룩 | 노이즈 256px 심플렉스, 주기 0.3, low 0.42 / high 0.60, 색 배율 0.5, 거칠기 0.45, 물막 0.0, 수직 흘러내림 4.0배, 바닥 위 1.2 m 띠에 +0.25 |

### 6-4. 코드로 만든 설비 재질 (`MineAssembler.gd:961-981`)

StandardMaterial3D이며 텍스처 없이 색·거칠기·메탈릭 값만 쓴다. 양면 렌더링.

| 재질 | 색 | roughness | metallic |
|---|---|---|---|
| SVC_Water (배수로 물) | (0.06, 0.07, 0.07) | 0.3 | 0.0 |
| SVC_Steel | (0.12, 0.11, 0.10) | 0.6 | 0.6 |
| SVC_Ceramic (애자) | (0.75, 0.74, 0.68) | 0.5 | 0.0 |
| SVC_Concrete | (0.28, 0.27, 0.24) | 1.0 | 0.0 |
| SVC_Sign | (0.70, 0.60, 0.12) | 0.6 | 0.0 |
| SVC_CableRed | (0.45, 0.04, 0.03) | 0.6 | 0.0 |
| SVC_Duct / SVC_DuctDark | (0.26, 0.24, 0.12) / (0.12, 0.11, 0.07) | 1.0 | 0.0 |

갱목·녹슨 철·케이블·전구는 조각 glTF의 재질을 찾아 재사용한다. 못 찾으면 회색 (0.3, 0.3, 0.3), roughness 0.8 재질을 쓴다.

### 6-5. 괴물 (`assets/generated/monster/miner_rigged.glb`)

| 재질 | base | metalRough | normal | occlusion | emissive | 비고 |
|---|---|---|---|---|---|---|
| `살` (몸) | O (webp) | – | – | – | – | metallicFactor 0 |
| `살_머리` | O (webp) | – | – | – | – | metallicFactor 0 |
| `뒤틀린_갱목` | O | – | O | – | – | KHR_materials_specular 0.4, 양면, UV 2배 |
| `녹슨_주철` | O | – | O | – | – | KHR_materials_specular 0.4, 양면, UV 3배 |
| `가죽끈` | – | – | – | – | – | 색 (0.05, 0.035, 0.03)만, specular 0.4 |

- 괴물 몸(`살`, `살_머리`)에는 **노멀·러프니스 텍스처가 연결되어 있지 않다.**
- 같은 폴더에 `miner_rigged_miner_skin_albedo.jpg`, `miner_rigged_miner_skin_normal.png` 파일이 있다. 그러나 glb 재질에서도, `scripts/`·`scenes/`에서도 참조를 찾지 못했다. 어디서 쓰이는지는 **확인 불가**.
- 씬·코드에서 괴물 재질을 덮어쓰는 곳은 없다 (`material_override`·StandardMaterial3D 검색 0건).

### 6-6. KayKit 팔레트 재질

리프트, 옛 시험 방의 채굴 벽, 파쇄 조각이 쓰는 KayKit `dungeon_texture.png` 재질이다. 실행 중 사본 팔레트(`assets/generated/palette/`)로 바뀌고, roughness 0.7(`PALETTE_ROUGHNESS`), clearcoat 끔이 적용된다 (`Atmosphere.gd:89-98`). 쓰는 채널은 베이스 컬러 하나다.
