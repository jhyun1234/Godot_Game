class_name Director
extends Node

## 감독 (제안서 #35, Alien: Isolation 식). 층마다 하나. 화면 밖에서 압박 0~100 을 세어
## 괴물(Stalker)을 시야 밖 곡선 칸에 내려놓고(PRESSURE_SEND) 불러들인다(PRESSURE_RECALL).
## 플레이어 버릇을 세어 배움 카드 2 를 켠다: 어둠 수색(램프 끄기 CARD_LAMP_N) · 광차 들여다보기(광차 숨기 CARD_CART_N). 카드는 판 안에서만.

var fd: MineAssembler.FloorData
var stalker: Stalker
var player: CharacterBody3D
var pressure := 0.0
var lamp_habit := 0
var cart_habit := 0
var card_dark := false
var card_cart := false
var last_spawn_cell := Vector2i(-1, -1)
var last_spawn_behind := false        # 고른 자리가 시야 밖 후보에서 나왔나 (봇)
var last_behind_cands := 0            # 시야 밖 후보 수 (0 이면 거리 조건만으로 골랐다)
var paused := false                   # 봇: 압박·철수·버릇 세기를 멈춘다 (괴물을 손으로 놓고 재는 동안)
var _lamp_was := true
var _hid_in_cart := false
var _rng := RandomNumberGenerator.new()


func setup(floor_data: MineAssembler.FloorData, s: Stalker) -> void:
	fd = floor_data
	stalker = s
	name = "Director"
	_rng.seed = fd.seed + 400


func _find_player() -> void:
	if player != null:
		return
	var room := fd.root.get_parent().get_parent()
	if room != null:
		player = room.get_node_or_null("Player") as CharacterBody3D
	if player != null:
		_lamp_was = player.lamp_on


var _surf_left := Tuning.STALKER_FLOOR_DWELL_S   # #49 지금 붙은 면에 더 있을 시간. 배회할 때만 줄어든다


func rate_mul() -> float:
	return 1.0 + Tuning.PRESSURE_FLOOR_MUL * fd.index


func _physics_process(delta: float) -> void:
	_find_player()
	if player == null or player.dead or paused:
		return
	if absf(player.global_position.y - fd.y) > Tuning.LIFT_DROP * 0.5:            # 다른 층에 있다 — 이 층 감독은 쉰다
		return
	var d: float = stalker.global_position.distance_to(player.global_position)
	if stalker.state == "hidden":
		pressure += Tuning.PRESSURE_UP * rate_mul() * delta
	elif d <= Tuning.PRESSURE_NEAR_M:
		pressure -= Tuning.PRESSURE_DOWN * delta
	elif d > Tuning.PRESSURE_FAR_M or stalker.state == "retreat":
		pressure += Tuning.PRESSURE_UP * rate_mul() * delta
	pressure = clampf(pressure, 0.0, 100.0)
	if stalker.state == "hidden" and pressure >= Tuning.PRESSURE_SEND:
		send()
	elif stalker.state in Stalker.MOVING and stalker.state != "retreat" and pressure <= Tuning.PRESSURE_RECALL:
		stalker.retreat()
	elif stalker.state == "wander" and pressure > Tuning.PRESSURE_RECALL + 10.0:  # #49 배회는 천장 ↔ 바닥을 시계로 번갈아 쓴다 (올라가지 못하는 칸이면 다음 프레임에 다시)
		_surf_left -= delta
		if _surf_left <= 0.0:
			if stalker.on_ceiling:
				if stalker.climb_down_to_floor():
					_surf_left = Tuning.STALKER_FLOOR_DWELL_S
			elif stalker.climb_to_ceiling():
				_surf_left = Tuning.STALKER_CEIL_DWELL_S
	elif stalker.state != "climb":                                               # 조사·수색·추격 동안에는 시계를 지금 면 기준으로 되돌린다
		_surf_left = Tuning.STALKER_CEIL_DWELL_S if stalker.on_ceiling else Tuning.STALKER_FLOOR_DWELL_S
	_count_habits(d)


## 시야 밖 칸(격자 거리 SPAWN_CELLS_MIN~MAX)에 내려놓는다. 후보가 없으면 거리 조건만.
## #49: 절반은 천장에 붙여 내려놓는다 — 그때는 천장이 높은 직선 칸(곡선은 2.71 m 라 못 붙는다)
func send() -> bool:
	_find_player()
	if player == null:
		return false
	var want_ceil: bool = Tuning.STALKER_CEIL_ON and _rng.randf() < Tuning.STALKER_CEIL_P
	var want_piece := "straight" if want_ceil else "curve"
	var pc := MineAssembler.cell_of(player.global_position)
	var dist: Dictionary = MineAssembler.grid_dist(fd, pc, Tuning.SPAWN_CELLS_MAX)
	var cands: Array[Vector2i] = []
	var loose: Array[Vector2i] = []
	for c in dist.keys():
		if dist[c] < Tuning.SPAWN_CELLS_MIN or not fd.pieces.has(c) or fd.pieces[c]["name"] != want_piece:
			continue
		loose.append(c)
		if MineAssembler.behind_player(player, MineAssembler.cell_world(c, fd.y)):
			cands.append(c)
	last_behind_cands = cands.size()
	last_spawn_behind = not cands.is_empty()
	if cands.is_empty():
		cands = loose
	if cands.is_empty():
		return false
	cands.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return dist[a] < dist[b] or (dist[a] == dist[b] and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	last_spawn_cell = cands[0]
	stalker.appear(last_spawn_cell, pc)
	if want_ceil:
		stalker.set_ceiling(true)
	_surf_left = Tuning.STALKER_CEIL_DWELL_S if want_ceil else Tuning.STALKER_FLOOR_DWELL_S
	pressure = minf(pressure, Tuning.PRESSURE_SEND)
	return true


## 버릇: 조사·수색·추격 중 CARD_HABIT_M 안에서 램프를 껐다 / CARD_HABIT_M 안에서 광차에 숙여 탔다
## ponytail: 램프 버릇은 "그 뒤 놓쳤다"까지 안 본다 — 끈 순간에 센다. 카드가 너무 일찍 켜지면 여기서 조건을 더한다
func _count_habits(d: float) -> void:
	if _lamp_was and not player.lamp_on and d <= Tuning.CARD_HABIT_M and stalker.state in ["investigate", "search", "chase"]:
		lamp_habit += 1
	_lamp_was = player.lamp_on
	var in_cart: bool = player.ride != null and player.stance == "crouch"
	if in_cart and not _hid_in_cart and d <= Tuning.CARD_HABIT_M and stalker.state != "hidden":
		cart_habit += 1
	_hid_in_cart = in_cart
	apply_cards()


func apply_cards() -> void:
	if lamp_habit >= Tuning.CARD_LAMP_N and not card_dark:
		card_dark = true
	if cart_habit >= Tuning.CARD_CART_N and not card_cart:
		card_cart = true
	stalker.ear_mul = Tuning.CARD_EAR_MUL if card_dark else Tuning.STALKER_EAR_MUL
	stalker.dwell_mul = Tuning.CARD_DWELL_MUL if card_dark else 1.0
	stalker.dark_card = card_dark
	stalker.peek_carts = card_cart
