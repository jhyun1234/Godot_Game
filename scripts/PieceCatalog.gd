class_name PieceCatalog
extends RefCounted

## 조각 카탈로그 (제안서 #26). 조립기(#27)와 봇이 읽는 표. 모양은 tools/minetunnel/build_piece.py 가 만든다.
##
## 칸 = Tuning.GRID_CELL(7 m). 조각 원점 = 칸 가운데 바닥 (2×2 방은 네 칸의 가운데).
## 면 이름은 Godot 좌표: N = -Z, S = +Z, E = +X, W = -X (Blender +Y 가 export_yup 으로 -Z).
## 면 종류: "A" = 아치 7×5.6 (갱도끼리) · "D" = 문 3.5×3.0 (목 ↔ 방) · "X" = 막힘.
## 모든 A 면의 테두리 정점은 같은 자리(0.35 격자), D 면은 0.175 격자 — 어느 조각을 어디에 붙여도 벽·천장·바닥이 이어진다.
## 봇(--check)이 exe 안에서 정점을 꺼내 잰다 (FACE_TOL).
##
## cols  = 임포터가 -convcolonly 로 만드는 StaticBody3D 수 (충돌 상자). 접미사를 하나 지우면 봇이 잡는다.
## slots = 빈 노드 SLOT_Pocket_<조각>_<n> 수 (광맥 포켓 자리. PocketSpawner 가 #27 에서 읽는다).
## door_x = D 면 가운데의 x 오프셋 (방 2×2 는 남서 칸 남면 가운데 = -3.5). half = 원점에서 면까지 (2×2 방만 7).

const DIR := "res://assets/generated/tunnel/"
const FACE_TOL := 0.002          # m, 면 테두리 정점 오차 허용 (제안서 #26: 2 mm)
const TRI_MAX := 12000           # 조각당 삼각형 예산 (층 588칸 × 12k = 7M)
const OPEN_A := "A"
const OPEN_D := "D"
const CLOSED := "X"

# 갱도 조각 9. faces 순서 N·E·S·W.
const PIECES := {
	"straight": {"gltf": "piece_straight.gltf", "cells": Vector2i(1, 1), "faces": {"N": "A", "E": "X", "S": "A", "W": "X"}, "cols": 3, "slots": 4},
	"curve":    {"gltf": "piece_curve.gltf",    "cells": Vector2i(1, 1), "faces": {"N": "X", "E": "X", "S": "A", "W": "A"}, "cols": 5, "slots": 2},
	"t":        {"gltf": "piece_t.gltf",        "cells": Vector2i(1, 1), "faces": {"N": "A", "E": "A", "S": "A", "W": "X"}, "cols": 4, "slots": 2},
	"cross":    {"gltf": "piece_cross.gltf",    "cells": Vector2i(1, 1), "faces": {"N": "A", "E": "A", "S": "A", "W": "A"}, "cols": 5, "slots": 0},
	"cap":      {"gltf": "piece_cap.gltf",      "cells": Vector2i(1, 1), "faces": {"N": "X", "E": "X", "S": "A", "W": "X"}, "cols": 4, "slots": 2},
	"neck":     {"gltf": "piece_neck.gltf",     "cells": Vector2i(1, 1), "faces": {"N": "D", "E": "X", "S": "A", "W": "X"}, "cols": 4, "slots": 0},
	"room_2":   {"gltf": "piece_room_2.gltf",   "cells": Vector2i(2, 2), "half": 7.0, "faces": {"N": "X", "E": "X", "S": "D", "W": "X"}, "cols": 13, "slots": 6, "door_x": -3.5},
	"room_1":   {"gltf": "piece_room_1.gltf",   "cells": Vector2i(1, 1), "faces": {"N": "X", "E": "X", "S": "D", "W": "X"}, "cols": 11, "slots": 3},
	"refuge":   {"gltf": "piece_refuge.gltf",   "cells": Vector2i(2, 1), "faces": {"N": "A", "E": "X", "S": "A", "W": "X"}, "cols": 9, "slots": 2},   # 동쪽 칸은 벽감(바위로 예약)
}

# 레일 덧씌우기 4. 갱도 조각 위에 얹는다. body = 봇 캡처 때 밑에 까는 조각.
const RAILS := {
	"straight": {"gltf": "rail_straight.gltf", "faces": ["N", "S"], "cols": 0, "body": "straight"},
	"curve":    {"gltf": "rail_curve.gltf",    "faces": ["S", "W"], "cols": 0, "body": "curve"},
	"turnout":  {"gltf": "rail_turnout.gltf",  "faces": ["N", "S", "W"], "cols": 0, "body": "t", "body_rot": 180.0},   # 직진 N-S + 곡선 S-W. T 는 W 가 막혀 있어 180° 돌려 깐다
	"end":      {"gltf": "rail_end.gltf",      "faces": ["S"], "cols": 1, "body": "cap"},                              # 종점 = 끝막이 + 버퍼
}

# 정거장 (shaft_station.gltf, #20~#22). 조립기가 칸 (SX, N−2)·(SX, N−1) 을 비워 두고, 갱도 쪽(N) 면만 뚫려 있다. 씬(Tunnel.tscn)에 놓여 있어 조립기가 안 놓는다.
const STATION := {"gltf": "shaft_station.gltf", "cells": Vector2i(1, 2), "faces": {"N": "A", "E": "X", "S": "X", "W": "X"}}
# 소품 9종 (mine_props.gltf 의 자식 이름, build_props.py). 조립기가 복제해 뿌린다. 충돌 없음.
const PROPS: Array[String] = ["PROP_crate", "PROP_crate_s", "PROP_barrels", "PROP_spade", "PROP_sledge", "PROP_bucket", "PROP_lamp", "PROP_rubble", "PROP_post"]
const PROPS_GLTF := "mine_props.gltf"
const CART_GLTF := "mine_cart.gltf"        # 광차 (#29, build_cart.py). 조립기가 순환선 위에 CART_COUNT 대
# 크립(통나무 엇갈려 쌓은 기둥) 자리 — 조각 로컬 (x, z) 가운데와 높이 (gltf 에서 잰 값, build_piece.py CRIB_W 0.9·CRIB_LOG 0.2).
# 속이 비어 있어 틈새로 검게 보였다(#27 수정 2 F5 "벽과 벽 사이에 틈") → 조립기가 안에 바위를 채운다
const CRIBS := {
	"t": {"h": 4.4, "at": [Vector2(3.03, -3.03), Vector2(3.03, 3.03)]},
	"cross": {"h": 4.4, "at": [Vector2(-3.03, -3.03), Vector2(-3.03, 3.03), Vector2(3.03, -3.03), Vector2(3.03, 3.03)]},
	"room_2": {"h": 6.0, "at": [Vector2(-2.8, -2.4), Vector2(3.2, 1.6)]},
}


static func piece_path(name: String) -> String:
	return DIR + PIECES[name]["gltf"]


static func rail_path(name: String) -> String:
	return DIR + RAILS[name]["gltf"]


## 면의 평면: 축(0 = x, 2 = z)과 그 축의 값. 원점에서 면까지 = half (2×2 방만 7, 나머지 3.5 — 대피소는 원점이 통로 칸이라 벽감 칸은 안 센다).
static func face_plane(name: String, face: String) -> Array:
	var half: float = PIECES[name].get("half", Tuning.GRID_CELL * 0.5)
	match face:
		"N": return [2, -half]
		"S": return [2, half]
		"E": return [0, half]
		_: return [0, -half]
