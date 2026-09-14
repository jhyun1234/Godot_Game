class_name Stalker
extends CharacterBody3D

## 갱도 괴물 몸통 (제안서 #35). 한 마리. 몸은 Miner.tscn(#36) — 앞면 +Z 라 움직이는 방향으로 노드를 돌린다.
## 길은 조립기 격자(MineAssembler.grid_path): 칸 사이 뚫린 면 한가운데 → 칸 가운데. 내비메시 없음.
## 감각 셋: 귀(NoiseBus.made, 반경 안) · 눈(앞 원뿔 STALKER_EYE_DEG·STALKER_EYE_M, 램프 켜진 몸, 시선 안 가림) ·
## 빛(STALKER_LIGHT_M 안 켜진 램프가 시선에 들면 그 자리로 천천히).
## 상태: hidden · wander · investigate · search · alert(들킴 포효) · climb(벽 #49) · hang(노려보기 #57·#59)·fall·land(낙하 #48) · chase · retreat · stun · catch. 등장·철수는 Director 가 정한다.
## 붙는 면은 (점 + 법선) 하나로 둔다 (#49) — 바닥 UP · 천장 DOWN · 벽 옆. 몸의 위를 법선에 맞추면 셋이 같은 코드다.
## 봇 손잡이: hold(안 움직임, 감각은 돈다) · force_state · appear · found_count. 충돌 층 5(괴물), 마스크 1(지형).

signal state_changed(state: String)
signal caught_player

const MOVING := ["wander", "investigate", "search", "chase", "retreat"]
const FLIP_AXIS := Vector3(0.0, 0.70710678, -0.70710678)   # #57 _fall_pose 앞 구간의 회전축 (몸 기준) — 거꾸로 매달린 몸을 머리가 플레이어 쪽인 엎드림으로
const FLIP_SPLIT := 2.0 / 3.0                              # #57 앞 구간(비틀기 180°) : 뒤 구간(세우기 90°) 시간 비 = 각도 비 — 두 구간을 같은 빠르기로 돈다 (반반이면 앞 구간이 두 배 빠르다)

var fd: MineAssembler.FloorData
var player: CharacterBody3D
var body: MinerBody
var eye: RayCast3D
var state := "hidden"
var hold := false                     # 봇: 제자리 (감각·상태 전이는 그대로)
var frozen := false                   # 개발용 정지(숫자 8): 감각·이동·클립 전부 그 자리에 멈춘다. F5 에서 모델을 들여다볼 때
var ear_mul := Tuning.STALKER_EAR_MUL # 카드 어둠 수색이 올린다
var dwell_mul := 1.0
var peek_carts := false               # 카드 광차 들여다보기
var dark_card := false                # 텔: 느리게 + 머리 훑기
var found_count := 0                  # 수색에서 숨은 플레이어를 들킨 횟수 (봇)
var last_seen := Vector3.ZERO         # 마지막으로 본 플레이어 자리 (월드)
var wander_center := Vector2i.ZERO

var _path: Array[Vector3] = []        # 길목 (Floor 로컬)
var _wp := 0
var _lose_left := 0.0
var _dwell_left := 0.0
var _stun_left := 0.0
var _alert_left := 0.0
var _drop_left := 0.0                 # 엎드리는 중 남은 시간 (#47)
var _hang_left := 0.0                 # #57 매달림 남은 시간
var _fall_el := 0.0                   # #57 놓은 뒤 지난 시간
var _fall_t := 0.0                    # #57 떨어지는 데 걸릴 시간 (놓을 때 높이로 계산)
var _fall_speed := 1.0                # #57 낙하 클립 재생 배율
var _hip_d := 0.0                     # #57 발 ↔ 엉덩이 거리 — 낙하 중 몸이 도는 축 높이
var _blinked := false                 # #58 이번 매달림에서 예고 깜빡임을 했다
var on_ceiling := false               # 천장에 거꾸로 붙어 있다 (#48)
var _ceil_y := 0.0                    # 지금 붙어 있는 천장 높이 (Floor 로컬)
var _climb_dir := 1                   # 벽타기 방향 (+1 오름 · −1 내림)
var _cl := {}                         # 지금 타는 벽 (#49): {sign, axis, center, along, ceil}
var _climb_s := 0.0                   # 벽·아치를 따라 바닥에서 잴 길이 (m)
var _pending_inv := Vector3.INF       # 내려온 뒤 조사하러 갈 자리 (없으면 INF)
var _retreat_up := false              # 철수하려고 벽을 오르는 중 (#50) — 천장에 닿으면 기어서 사라진다
var _retreat_on := false              # 철수를 시작했고 아직 안 끝났다 (#54). 천장 길이 끊겨 벽에서 내려와도 이 표시가 있으면 걸어서 마저 물러난다 —
                                      # 없으면 배회로 돌아가고, 압박이 낮으면 감독이 같은 자리에서 다시 벽을 태워 무한히 오르내린다(F5 Bug2.mp4)
var _pause_left := 0.0
var _spots: Array[Vector3] = []
var _searched: Array[Vector2i] = []
var _curious := false                 # 빛 때문에 가는 중 (배회 속도)
var _target_cell := Vector2i(-1, -1)
var _rng := RandomNumberGenerator.new()
var _sway_t := 0.0


func setup(floor_data: MineAssembler.FloorData) -> void:
	fd = floor_data
	_rng.seed = fd.seed + 300
	name = "Stalker"
	collision_layer = 16
	collision_mask = 1
	var col := CollisionShape3D.new()
	col.name = "Collider"
	var cap := CapsuleShape3D.new()
	cap.radius = Tuning.STALKER_R
	cap.height = Tuning.STALKER_H
	col.shape = cap
	col.position.y = Tuning.STALKER_H * 0.5
	add_child(col)
	body = (load("res://scenes/level/Miner.tscn") as PackedScene).instantiate() as MinerBody
	body.name = "Body"
	add_child(body)
	eye = RayCast3D.new()
	eye.name = "Eye"
	eye.enabled = false
	eye.collision_mask = 1
	eye.position.y = Tuning.STALKER_EYE_H
	add_child(eye)
	NoiseBus.made.connect(_on_noise)
	state = ""                                                 # _set_state 가 같은 상태면 건너뛴다 — 처음 숨김도 거쳐 가게
	_set_state("hidden")


func _find_player() -> void:
	if player != null:
		return
	var room := fd.root.get_parent().get_parent()
	if room != null:
		player = room.get_node_or_null("Player") as CharacterBody3D


# ---------------- 상태 ----------------

func _set_state(s: String) -> void:
	if state == s:
		return
	var was_climb: bool = state == "climb"
	state = s
	visible = s != "hidden"
	col_enabled(s != "hidden")
	if was_climb and s != "climb":                             # 벽타기가 끝났다/끊겼다 — 벽에 누워 있던 몸을 지금 면에 맞춰 세운다 (#49 수정 2)
		_body_to_surface()
	if body != null:
		if not s in ["hang", "fall", "land"]:                  # #57 팔 뻗기는 매달림 ~ 착지에서만
			body.set_reach(Vector3.INF, 0.0)
		if not s in ["hang", "fall"]:                          # #59 노려보기는 매달림에서, 놓은 뒤 STALKER_GLARE_FADE_S 에 걸쳐 푼다
			body.set_glare(Vector3.INF, 0.0, 0.0)
		body.set_ground_force(s == "land")                     # #57 착지 클립은 손이 바닥을 뚫는다 — 착지 동안만 손 접지
		if s == "drop":                                        # 엎드리기는 일어서는 클립을 뒤로 튼다 (#47)
			body.drop()
		elif s == "hang":                                      # #59 천장 기기 클립으로 섞는다 — 다 섞이면 _physics_process 가 그 자리에 멈춘다
			body.play(_clip_for(s), 1.0, false, Tuning.STALKER_GLARE_CRAWL_T, Tuning.STALKER_HANG_SWING_S)
		elif s == "fall":                                      # #57 처음부터, begin_fall 이 잰 배율로 (land_hard 면 공중 구간이 낙하 시간에 맞는다)
			body.play(_clip_for(s), _fall_speed)
		elif s == "land":                                      # 착지는 발이 닿는 시각부터 (#48)
			body.play("land_hard", 1.0, false, Tuning.STALKER_LAND_FROM)
		elif _clip_for(s) != "":
			body.play(_clip_for(s), _clip_speed(s))
	state_changed.emit(s)


## #48 천장에 붙는다/뗀다. 몸을 앞뒤 축으로 180° 굴려 거꾸로 매달고, 충돌 캡슐과 눈을 원점 아래로 내린다.
func set_ceiling(on: bool) -> void:
	if on_ceiling == on or (on and not Tuning.STALKER_CEIL_ON):
		return
	on_ceiling = on
	var col := get_node_or_null("Collider") as CollisionShape3D
	if col != null:
		col.position.y = -Tuning.STALKER_H * 0.5 if on else Tuning.STALKER_H * 0.5
	if eye != null:
		eye.position.y = Tuning.STALKER_CEIL_EYE_H if on else Tuning.STALKER_EYE_H
	if on:
		var c := ceiling_y(position)
		_ceil_y = c if c > 0.0 else position.y + Tuning.STALKER_CEIL_MIN_H
		position.y = _ceil_y - Tuning.STALKER_CEIL_CLEAR
	_body_to_surface()
	velocity = Vector3.ZERO


## #49 몸을 지금 붙어 있는 면에 맞춘다 — 바닥이면 똑바로, 천장이면 앞뒤 축으로 180° 굴려 거꾸로.
## 벽타기(_surface_face)는 몸을 통째로 눕혀 놓으므로, 벽에서 벗어나면 반드시 이걸 불러야 한다 (안 부르면 머리를 바닥에 박은 채 걸어다닌다).
func _body_to_surface() -> void:
	if body == null:
		return
	body.rotation = Vector3(0.0, 0.0, PI if on_ceiling else 0.0)
	body.surface_normal = Vector3.DOWN if on_ceiling else Vector3.UP
	body.surface_point = fd.root.to_global(Vector3(position.x, _ceil_y, position.z)) if on_ceiling else Vector3.INF


## #51 이 자리에서 탈 수 있는 벽. 직선·T·끝막이(STALKER_WALL_PIECES) — 세 조각만 벽이 |x| 3.16 의 곧은 면이다.
## 판정: 닫힌 면 f 중 **수직 면(f±1) 하나가 뚫려 있는** 것 = 복도 옆벽. 끝막이의 막장 벽은 수직 면이 둘 다 닫혀 자동으로 빠지고,
## 교차는 닫힌 면이 없어 빠진다. 여럿이면 지금 자리에서 가까운 쪽(옆으로 덜 옮겨 붙는 쪽).
## 단면 값은 조립기와 같다(TUNNEL_WALL_X = 갱목 기둥 안쪽면 · TUNNEL_ARCH_Y). 충돌 상자(|x| 3.2~3.5)는 안 쓴다 — 보이는 벽보다 밖이라 #48 이 허공을 짚었다.
func _wall_of(at: Vector3) -> Dictionary:
	var cell := MineAssembler.cell_of(at)
	if fd == null or not fd.pieces.has(cell):
		return {}
	var nm: String = fd.pieces[cell]["name"]
	var ceil_h: float = float(Tuning.CEIL_H.get(nm, -1.0))
	if not nm in Tuning.STALKER_WALL_PIECES or ceil_h < Tuning.STALKER_CEIL_MIN_H:
		return {}
	var mask: int = int(fd.open.get(cell, 0))
	var center := MineAssembler.cell_world(cell)
	var best := {}
	var best_d := INF
	for f in 4:
		if mask & (1 << f):                                                       # 뚫린 면은 벽이 아니다
			continue
		if not (mask & (1 << ((f + 1) % 4))) and not (mask & (1 << ((f + 3) % 4))):
			continue                                                              # 수직 면이 둘 다 닫힘 = 막장 끝벽 (칸 가운데에서 3.05, 단면이 다르다)
		var axis: int = 0 if f == MineAssembler.E_IDX or f == MineAssembler.W_IDX else 1
		var sgn: float = 1.0 if f == MineAssembler.E_IDX or f == MineAssembler.S_IDX else -1.0
		var off: float = (at.x - center.x) if axis == 0 else (at.z - center.z)
		var d: float = absf(Tuning.TUNNEL_WALL_X * sgn - off)
		if d < best_d:
			best_d = d
			best = {"sign": sgn, "axis": axis, "center": center,
				"along": at.z if axis == 0 else at.x,
				"ceil": maxf(ceil_h, Tuning.TUNNEL_ARCH_Y + 0.2)}
	return best


## #49 아치(사분 타원) 길이 근사
func _arch_len() -> float:
	var b: float = maxf(float(_cl["ceil"]) - Tuning.TUNNEL_ARCH_Y, 0.05)
	return PI * 0.5 * sqrt((Tuning.TUNNEL_WALL_X * Tuning.TUNNEL_WALL_X + b * b) * 0.5)


## #49 벽·아치 위의 자리. s = 바닥에서 면을 따라 잰 길이. {"surf": 면 위 점, "n": 법선(통로 쪽), "pos": 몸 중심} (Floor 로컬)
func _wall_at(s: float) -> Dictionary:
	var sd: float = _cl["sign"]
	var a: float = Tuning.TUNNEL_WALL_X
	var b: float = maxf(float(_cl["ceil"]) - Tuning.TUNNEL_ARCH_Y, 0.05)
	var p := Vector2(a, clampf(s, 0.0, Tuning.TUNNEL_ARCH_Y))
	var n := Vector2(-1.0, 0.0)
	var t := 0.0
	if s > Tuning.TUNNEL_ARCH_Y:
		t = clampf((s - Tuning.TUNNEL_ARCH_Y) / _arch_len(), 0.0, 1.0)
		var th: float = t * PI * 0.5
		p = Vector2(a * cos(th), Tuning.TUNNEL_ARCH_Y + b * sin(th))
		n = -Vector2(cos(th) / a, sin(th) / b).normalized()
	var off: float = lerpf(Tuning.STALKER_WALL_OFF, Tuning.STALKER_CEIL_CLEAR, t)
	if s < Tuning.STALKER_WALL_LAND_OFF:                                   # 밑동은 바닥에 선 자리에서 벽으로 누워든다 — 바로 붙으면 몸이 벽 충돌체에 박힌다 (#49 수정)
		off = lerpf(Tuning.STALKER_WALL_LAND_OFF, Tuning.STALKER_WALL_OFF, maxf(s, 0.0) / Tuning.STALKER_WALL_LAND_OFF)
	var surf := _wall_vec(p.x * sd, p.y)
	var nor := _wall_vec(n.x * sd, n.y, true)
	return {"surf": surf, "n": nor, "pos": surf + nor * off}


## #49 단면 좌표(벽 쪽 cross · 높이 y)를 칸 좌표로. dir 이면 방향 벡터(칸 자리를 안 더한다)
func _wall_vec(cross: float, y: float, dir: bool = false) -> Vector3:
	var center: Vector3 = _cl["center"]
	var along: float = _cl["along"]
	if int(_cl["axis"]) == 0:
		return Vector3(cross, y, 0.0) if dir else Vector3(center.x + cross, y, along)
	return Vector3(0.0, y, cross) if dir else Vector3(along, y, center.z + cross)


## #49 지금 s 에서 가는 방향(면을 따라). 머리가 늘 진행 방향을 본다 — 내려올 때는 아래로
func _climb_tangent() -> Vector3:
	var t: Vector3 = ((_wall_at(_climb_s + 0.05)["surf"] as Vector3) - (_wall_at(_climb_s - 0.05)["surf"] as Vector3)) * float(_climb_dir)
	return t.normalized() if t.length() > 0.0001 else Vector3.UP


## #49 몸을 면에 붙인다 — 몸의 위 = 면 법선, 앞 = 가는 방향. w 만큼(0~1) 지금 자세에서 돌린다.
func _surface_face(n: Vector3, fwd: Vector3, w: float, surf: Vector3) -> void:
	if body == null:
		return
	var f: Vector3 = fwd - n * fwd.dot(n)
	if f.length() < 0.001:
		f = n.cross(Vector3.RIGHT if absf(n.x) < 0.9 else Vector3.FORWARD)
	f = f.normalized()
	var want := Basis(n.cross(f).normalized(), n, f)
	var cur := body.transform.basis.orthonormalized()
	var q: Quaternion = cur.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), clampf(w, 0.0, 1.0))
	body.transform.basis = Basis(q).scaled(Vector3.ONE * Tuning.MINER_SCALE)
	body.surface_normal = n
	body.surface_point = fd.root.to_global(surf)


## #49 벽을 타고 천장으로. 직선 칸이 아니면 false — 감독이 다음 프레임에 다시 부른다.
func climb_to_ceiling() -> bool:
	if not Tuning.STALKER_CEIL_ON or on_ceiling or state == "climb":
		return false
	var w := _wall_of(position)
	if w.is_empty():
		return false
	_cl = w
	_climb_s = 0.0
	_climb_dir = 1
	_begin_climb()
	return true


## #49 벽을 타고 내려온다. 오르는 중이면 방향만 되돌린다.
## 지금 칸에 탈 벽이 없으면 false — 천장을 기어 가다가 직선 칸에서 다시 부른다 (허공에서 떨어뜨리지 않는다)
func climb_down_to_floor() -> bool:
	if state == "climb":
		_climb_dir = -1
		set_ceiling(false)                                     # 벽에 붙어 있는 동안은 천장이 아니다 — 천장 표시가 남으면 뒤집힌 채로 내려온다
		return true
	if not on_ceiling:
		return false
	var w := _wall_of(position)
	if w.is_empty():
		return false
	_cl = w
	_climb_s = Tuning.TUNNEL_ARCH_Y + _arch_len()
	_climb_dir = -1
	set_ceiling(false)
	_begin_climb()
	return true


func _begin_climb() -> void:
	_path.clear()
	velocity = Vector3.ZERO
	rotation.y = 0.0                                           # 벽에서는 몸 노드가 통째로 돈다 (_surface_face)
	var at := _wall_at(_climb_s)
	position = at["pos"]
	_set_state("climb")
	_surface_face(at["n"], _climb_tangent(), 1.0, at["surf"])   # 첫 프레임은 바로 붙인다


## #49 벽·아치 한 걸음. 꼭대기에 닿으면 천장, 바닥에 닿으면 바닥.
func _climb_step(delta: float) -> void:
	var top: float = Tuning.TUNNEL_ARCH_Y + _arch_len()
	_climb_s = clampf(_climb_s + Tuning.STALKER_WALL_SPEED * delta * float(_climb_dir), 0.0, top)
	var at := _wall_at(_climb_s)
	position = at["pos"]
	_surface_face(at["n"], _climb_tangent(), delta / maxf(Tuning.STALKER_SURF_TURN_S, 0.01), at["surf"])
	if body != null:
		body.play(_clip_for("climb"), _clip_speed("climb"))
	if _climb_dir > 0 and _climb_s >= top - 0.001:
		set_ceiling(true)
		_resume_after_climb()
	elif _climb_dir < 0 and _climb_s <= 0.001:
		position = Vector3(at["pos"].x, 0.0, at["pos"].z)                  # _wall_at(0) 이 이미 벽에서 STALKER_WALL_LAND_OFF 떨어진 자리다
		_resume_after_climb()


## #49 벽에서 내려오거나 올라간 뒤 하던 일로. 내려오는 길이었으면 그 자리를 조사한다.
func _resume_after_climb() -> void:
	wander_center = MineAssembler.cell_of(position)
	var up_retreat: bool = _retreat_up and on_ceiling           # #50 철수하려고 올라온 것이면 이어서 기어 사라진다
	_retreat_up = false
	_set_state("wander")                                       # 벽타기에서 **먼저** 빠져나온다 — 상태가 climb 인 채로 조사를 부르면
	if is_finite(_pending_inv.x):                              # investigate 가 "먼저 내려와라"로 되돌려 보내 제자리에 갇힌다 (#49 수정 3, F5 영상 t=58~67 climb 고정)
		var p: Vector3 = _pending_inv
		_pending_inv = Vector3.INF
		investigate(p)
		return
	if up_retreat:
		_retreat_ceiling()
		return
	if _retreat_on and not on_ceiling:                          # #54 천장 철수가 끊겨 내려왔다 — 배회로 돌아가지 않고 걸어서 마저 물러난다
		_retreat_walk()
		return
	_pick_wander()


## #57 → #59 천장에서 떨어지기 전에 멈춰 노려본다 — 엎드린 채(엉덩이·발은 천장) 허리를 접어 상체를 들고, 머리는 플레이어 눈, 팔은 가슴 쪽 (조사 #56 리커).
## STALKER_HANG_S 뒤 _physics_process 가 begin_fall 을 부른다. 0 이면 바로 놓는다(옛 동작)
func begin_hang() -> void:
	if Tuning.STALKER_HANG_S <= 0.0:
		begin_fall()
		return
	_path.clear()
	velocity = Vector3.ZERO
	_hang_left = Tuning.STALKER_HANG_S
	_blinked = false
	if player != null:
		face_toward(player.global_position)
	_set_state("hang")


## #48 천장에서 손을 놓는다. #57: 원점을 "몸이 섰을 때 발 자리"로 내리고, 몸은 엉덩이를 축으로 머리부터 돌아 착지 전에 선다
## (옛 동작 STALKER_FALL_CLIP "fall_air" 는 발을 축으로 앞뒤 축 굴림 — 몸이 잠깐 바닥 속으로 휘둘렸다)
func begin_fall() -> void:
	var feet_y: float = global_position.y
	var hip_y: float = body.hip_y() if body != null else feet_y
	var ceil_at: Vector3 = fd.root.to_global(Vector3(position.x, _ceil_y, position.z))   # #58 흙먼지가 쏟아질 자리 (on_ceiling 을 끄기 전에)
	on_ceiling = false
	var col := get_node_or_null("Collider") as CollisionShape3D
	if col != null:
		col.position.y = Tuning.STALKER_H * 0.5
	if eye != null:
		eye.position.y = Tuning.STALKER_EYE_H
	if body != null:
		body.surface_normal = Vector3.UP
		body.surface_point = Vector3.INF
	_path.clear()
	velocity = Vector3.ZERO
	_fall_speed = 1.0
	_hip_d = 0.0
	_fall_el = 0.0
	if body != null:
		body.set_paused(false)                                         # #59 멈춘 crawl 에서 바로 낙하 클립을 틀면 섞지 않고 튄다(머리 1.27 m) — 다시 틀어 놓고 섞는다	if Tuning.STALKER_FALL_CLIP == "land_hard" and body != null:
		_hip_d = absf(feet_y - hip_y)                                  # 발 ↔ 엉덩이 (매달렸으면 발이 위)
		position.y += (hip_y - _hip_d) - feet_y                        # 엉덩이는 그 자리 — 원점만 내린다
		_fall_t = sqrt(2.0 * maxf(position.y, 0.05) / Tuning.GRAVITY)
		_fall_el = 0.0
		_fall_speed = Tuning.STALKER_LAND_FROM / maxf(_fall_t, 0.05)    # 공중 구간(0 ~ 발 닿는 시각)이 낙하 시간에 맞게
	if Tuning.STALKER_DROP_BLACK:                                      # #58 떨어지는 동안 헤드램프가 꺼진다 — 공중에서 도는 몸을 어둠이 가린다
		if player != null:
			player.lamp_blackout(sqrt(2.0 * maxf(position.y, 0.05) / Tuning.GRAVITY) + Tuning.STALKER_DROP_DARK_AFTER)
		Dust.burst(fd.root, ceil_at, Vector3.DOWN, Tuning.STALKER_DROP_DUST)
	_set_state("fall")
	if Tuning.STALKER_FALL_CLIP == "land_hard" and body != null:
		_fall_pose(0.0)                                                # _set_state 뒤에 — play() 가 몸 높이를 클립 기본값(0)으로 되돌려, 앞에 두면 한 프레임 동안 몸이 2.8 m 내려앉았다


## #57 낙하 자세. u 0 = 거꾸로 매달림(앞뒤 축 180°) → FLIP_SPLIT = 머리를 플레이어 쪽으로 엎드린 수평 → 1 = 똑바로. 엉덩이(원점 위 _hip_d)를 축으로 돈다.
## 매달린 몸은 배가 플레이어를 보고 있어서 머리부터 엎드리려면 반 바퀴 비틀어야 한다 — 비틀기를 앞 구간에 몰았다
func _fall_pose(u: float) -> void:
	if body == null:
		return
	var q: Quaternion
	if u < FLIP_SPLIT:
		q = Quaternion(FLIP_AXIS, PI * u / FLIP_SPLIT) * Quaternion(Vector3(0.0, 0.0, 1.0), PI)
	else:
		q = Quaternion(Vector3.RIGHT, PI * 0.5 * (1.0 - u) / (1.0 - FLIP_SPLIT))
	body.quaternion = q
	var off := Vector3(0.0, _hip_d, 0.0)
	body.position = off - q * off


## #57 팔을 뻗는 목표 — 플레이어 가슴
func _reach_point() -> Vector3:
	return player.global_position + Vector3(0.0, Tuning.STALKER_REACH_AIM_Y, 0.0)


## #59 노려보는 목표 — 플레이어 눈
func _glare_point() -> Vector3:
	return player.global_position + Vector3(0.0, Tuning.EYE_HEIGHT, 0.0)


## 이 자리의 천장 높이 (Floor 로컬 y). 천장에는 충돌 상자가 없어서(벽 상자만 있다) 조각별 실측 표를 쓴다. 모르면 −1.
func ceiling_y(at: Vector3) -> float:
	if fd == null:
		return -1.0
	var cell := MineAssembler.cell_of(at)
	if not fd.pieces.has(cell):
		return -1.0
	return Tuning.CEIL_H.get(fd.pieces[cell]["name"], -1.0)


func col_enabled(on: bool) -> void:
	var col := get_node_or_null("Collider") as CollisionShape3D
	if col != null:
		col.disabled = not on


## 이 상태에 쓸 클립. 천장이면 기는 클립 (#48). 벽도 crawl (#49) — 사람 사다리 클립은 팔을 벌려 웃긴다
func _clip_for(s: String) -> String:
	if s == "fall":
		return Tuning.STALKER_FALL_CLIP                          # #57
	if on_ceiling and Tuning.STALKER_CEIL_CLIPS.has(s):
		return Tuning.STALKER_CEIL_CLIPS[s]
	return Tuning.STALKER_CLIPS[s] if Tuning.STALKER_CLIPS.has(s) else ""


func _clip_speed(s: String) -> float:
	if s == "climb":
		return maxf(Tuning.MINER_ANIM_SPEED, Tuning.STALKER_WALL_SPEED / Tuning.STALKER_CLIP_WALK)
	if s == "fall" or s == "land":
		return 1.0
	if s == "chase":
		var nat: float = Tuning.STALKER_CLIP_RUN if on_ceiling else Tuning.STALKER_CLIP_RUN_STAND
		return maxf(Tuning.MINER_ANIM_SPEED, Tuning.STALKER_SPEED["chase"] / nat)
	if Tuning.STALKER_SPEED.has(s):
		return maxf(Tuning.MINER_ANIM_SPEED, Tuning.STALKER_SPEED[s] / Tuning.STALKER_CLIP_WALK)
	return Tuning.MINER_ANIM_SPEED


## Director: 시야 밖 곡선 칸에 내려놓는다. 배회 구역은 플레이어 칸
func appear(cell: Vector2i, center: Vector2i) -> void:
	_retreat_on = false
	position = MineAssembler.cell_world(cell)
	velocity = Vector3.ZERO
	wander_center = center
	_searched.clear()
	_set_state("wander")
	_pick_wander()


## Director: 철수 (#50) — 벽을 타고 천장으로 올라가 시야 밖에서 사라진다.
## 탈 벽이 없는 칸이면 옆 방식(걸어서 시야 밖 곡선 칸으로) 으로 물러난다.
func retreat() -> void:
	if state in ["hidden", "catch", "hang", "fall", "land", "climb"]:                 # 벽에 붙어 있는 동안은 그대로 — 올라가서 이어서 물러난다
		return
	_find_player()
	if on_ceiling:                                                            # 이미 천장 — 그대로 기어서 시야 밖으로
		_retreat_ceiling()
		return
	_retreat_on = true
	_pending_inv = Vector3.INF                                                # #55 철수가 이긴다 — 미뤄 둔 소리 조사가 벽에서 내려선 뒤 철수보다 먼저 처리되면 또 벽을 탄다
	if climb_to_ceiling():                                                    # 벽을 타고 올라간다 — 도망친 플레이어가 뒤돌아보면 이 모습이 보인다
		_retreat_up = true
		return
	_retreat_walk()


## #54 걸어서 물러난다 — 시야 밖 곡선 칸으로. 갈 곳이 없으면 그 자리에서 사라진다.
## 천장으로 물러나다 길이 끊겨 내려온 경우에도 이걸로 마저 물러난다 (안 그러면 벽만 오르내린다)
func _retreat_walk() -> void:
	_retreat_on = true
	var target := _hide_cell()
	_set_state("retreat")
	if target.x < 0 or not _go(target):
		hide_away()


## #50 천장에 붙은 채 시야 밖으로 기어가 사라진다
func _retreat_ceiling() -> void:
	_pending_inv = Vector3.INF                                                # 물러나는 중에는 조사할 일이 없다
	_set_state("retreat")
	var target := _ceil_hide_cell()
	if target.x < 0 or not _go(target):
		hide_away()


## #50 천장으로 물러날 자리: 천장이 높은 칸 가운데 STALKER_RETREAT_CEIL_CELLS 이상 떨어지고 플레이어 시야 밖인 곳
func _ceil_hide_cell() -> Vector2i:
	var from := MineAssembler.cell_of(position)
	var dist: Dictionary = MineAssembler.grid_dist(fd, from, Tuning.STALKER_RETREAT_CEIL_CELLS + 3)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for c in dist.keys():
		if dist[c] < Tuning.STALKER_RETREAT_CEIL_CELLS or not fd.pieces.has(c):
			continue
		if float(Tuning.CEIL_H.get(fd.pieces[c]["name"], -1.0)) < Tuning.STALKER_CEIL_MIN_H:
			continue
		if player != null and not MineAssembler.behind_player(player, MineAssembler.cell_world(c, fd.y)):
			continue
		if dist[c] < best_d:
			best_d = dist[c]
			best = c
	return best


func hide_away() -> void:
	_retreat_on = false
	_path.clear()
	set_ceiling(false)                                                        # 사라질 때 천장에서 뗀다 — 안 그러면 다음 등장이 천장에 붙은 채로 뜬다 (#50)
	_set_state("hidden")


## 곡괭이가 맞았다 (ThrownPick)
func stun() -> void:
	if state in ["hidden", "catch"]:
		return
	_stun_left = Tuning.STALKER_STUN_S
	_retreat_on = false
	_path.clear()
	velocity = Vector3.ZERO
	_set_state("stun")


## 봇: 상태를 억지로. investigate/search 는 지금 자리 기준
func force_state(s: String) -> void:
	_path.clear()
	_curious = false
	_set_state(s)
	if s == "wander":
		wander_center = MineAssembler.cell_of(position)
		_pick_wander()
	elif s == "search":
		_start_search(position)
	elif s == "drop":
		_drop_left = Tuning.STALKER_DROP_S


## 봇·시험: 이 자리를 조사하러 간다 (소음과 같은 길)
func investigate(pos: Vector3, curious: bool = false) -> void:
	_curious = curious
	# 소음 조사는 바닥에서 한다 (#49) — 떨어진 곡괭이는 바닥에서 확인할 일이라 먼저 내려온다.
	# 빛으로 알아챈 것(curious)이면 안 내려온다 (#53) — 천장을 그대로 기어서 다가간다. 다음 칸 천장이 낮으면 _move 가 그때 벽으로 내려보낸다.
	if (on_ceiling or state == "climb") and not curious:
		_pending_inv = pos
		climb_down_to_floor()
		return
	var cell := MineAssembler.cell_of(pos)
	if state == "investigate" and cell == _target_cell:
		return
	_set_state("investigate")
	if not _go(cell):
		_start_search(position)
	else:
		_path[_path.size() - 1] = Vector3(pos.x, 0.0, pos.z)          # 마지막 길목은 소음 자리 자체 (칸 가운데가 아니라)


## 봇: 자리를 옮기고 그쪽을 본다 (Floor 로컬)
func place(local: Vector3, look_at: Vector3) -> void:
	position = local
	velocity = Vector3.ZERO
	_path.clear()
	face_toward(fd.root.to_global(look_at))


func face_toward(p: Vector3) -> void:
	var d := p - global_position
	if not Vector2(d.x, d.z).is_zero_approx():
		rotation.y = atan2(d.x, d.z)


func _on_noise(pos: Vector3, radius: float, kind: String, who: Node) -> void:
	if state in ["hidden", "chase", "stun", "catch", "retreat", "hang", "fall", "land"] or _retreat_on or who == self or kind == "cart":   # ponytail: 광차 소음은 안 듣는다 — 매초 20 m 라 괴물이 늘 광차만 쫓는다
		# #55 _retreat_on: 철수하려고 벽을 오르는(climb) 동안도 안 듣는다 — 들으면 오르던 방향이 뒤집혀 내려왔다 다시 오른다(F5 영상 1:03~1:13, 봇 10.7초)
		return
	if absf(pos.y - global_position.y) > Tuning.LIFT_DROP * 0.5:
		return
	if global_position.distance_to(pos) <= radius * ear_mul:
		investigate(pos)


# ---------------- 매 프레임 ----------------

## 개발용 정지 (#43 F5): 몸도 클립도 그 자리에. 감독은 DebugHud 가 같이 멈춘다.
func set_frozen(f: bool) -> void:
	frozen = f
	velocity = Vector3.ZERO
	if body != null:
		body.set_paused(f)


func _physics_process(delta: float) -> void:
	if state == "hidden" or frozen:
		return
	if not on_ceiling and state != "climb" and position.y < Tuning.STALKER_FLOOR_MIN_Y:   # 바닥 아래로 빠졌다 — 거기서는 길도 중력도 못 돌아온다 (#49 수정 그물)
		push_warning("Stalker: 바닥 아래 %.2f m — 칸 가운데로 되돌린다" % position.y)
		position = MineAssembler.cell_world(MineAssembler.cell_of(position))
		velocity = Vector3.ZERO
	_find_player()
	if state == "stun":
		_stun_left -= delta
		if _stun_left <= 0.0:
			_start_search(position)
		return
	if state == "catch":
		return
	if state == "alert":                                       # 들킴 포효 — 끝나면 추격
		_alert_left -= delta
		if player != null:
			face_toward(player.global_position)
		if _alert_left <= 0.0:
			_begin_chase()
		return
	if state == "climb":                                       # 벽·아치를 기어 오르내린다 (#49)
		_climb_step(delta)
		return
	if state == "hang":                                        # #59 천장 기기 자세로 멈춰 상체를 들고 노려본다 → STALKER_HANG_S 뒤 놓는다
		_hang_left -= delta
		var el: float = Tuning.STALKER_HANG_S - _hang_left
		var w: float = clampf(el / maxf(Tuning.STALKER_GLARE_RISE_S, 0.01), 0.0, 1.0)
		if player != null and body != null:
			if el >= Tuning.STALKER_HANG_SWING_S and body.is_playing():
				body.set_paused(true)                                      # crawl 로 다 섞였다 — 그 자리에 멈춘다 (움직이는 건 척추·목·팔만)
			face_toward(player.global_position)
			body.set_reach(_reach_point(), w)
			body.set_glare(_glare_point(), w, el)
		if Tuning.STALKER_DROP_BLACK and not _blinked and _hang_left <= Tuning.STALKER_DROP_BLINK_AT and player != null:
			_blinked = true
			player.lamp_blackout(Tuning.STALKER_DROP_BLINK_S)             # #58 곧 떨어진다는 예고
		if _hang_left <= 0.0:
			begin_fall()
		return
	if state == "fall":                                        # 떨어진다 — 몸이 뒤집히며 (#48)
		_fall_el += delta
		if player != null and body != null:                        # #59 노려보던 굽힘을 한 프레임에 풀면 머리가 튄다
			body.set_glare(_glare_point(), 1.0 - clampf(_fall_el / maxf(Tuning.STALKER_GLARE_FADE_S, 0.01), 0.0, 1.0), Tuning.STALKER_HANG_S + _fall_el)
		if Tuning.STALKER_FALL_CLIP == "land_hard":                # #57 머리부터, 엉덩이를 축으로 돌아 착지 전에 선다
			_fall_pose(clampf(_fall_el / maxf(_fall_t * Tuning.STALKER_FALL_UPRIGHT_AT, 0.01), 0.0, 1.0))
			if player != null and body != null:
				body.set_reach(_reach_point(), 1.0)
		elif body != null and body.rotation.z > 0.001:              # 옛 동작 (#48): 발을 축으로 앞뒤 축 굴림
			body.rotation.z = maxf(0.0, body.rotation.z - PI * delta / maxf(Tuning.STALKER_FALL_TURN_S, 0.01))
		velocity.y -= Tuning.GRAVITY * delta
		move_and_slide()
		if is_on_floor():
			if body != null:
				body.quaternion = Quaternion.IDENTITY
				body.position = Vector3.ZERO
			if Tuning.STALKER_DROP_BLACK and player != null:
				player.shake(Tuning.SHAKE_AMOUNT, Tuning.SHAKE_TIME)          # #58 어둠 속에서 쿵
			_drop_left = Tuning.STALKER_LAND_S
			_set_state("land")
		return
	if state == "land":                                        # 한 손 짚고 착지 → 일어서서 달린다 (#48)
		_drop_left -= delta
		if player != null:
			face_toward(player.global_position)
			if body != null:
				body.set_reach(_reach_point(), clampf(_drop_left / maxf(Tuning.STALKER_LAND_S, 0.01), 0.0, 1.0))   # #57 착지하며 팔을 거둔다
		if _drop_left <= 0.0:
			_lose_left = Tuning.STALKER_LOSE_S
			_set_state("chase")
		return
	if state == "drop":                                        # 엎드리는 중 — 제자리에서 몸만 낮춘다 (#47)
		_drop_left -= delta
		if player != null:
			face_toward(player.global_position)
		if _drop_left <= 0.0:
			_set_state("chase")
		return
	if on_ceiling and is_finite(_pending_inv.x):                # 내려가야 하는데 아직 벽을 못 찾았다 — 기어가면서 다시 찾는다 (#49)
		climb_down_to_floor()
	_sense(delta)
	if state == "search" and _dwell_left > 0.0:
		_dwell_left -= delta
		_check_found()
		if _dwell_left <= 0.0:
			_next_spot()
		return
	if state == "wander" and _pause_left > 0.0:
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_wander()
		return
	if state == "chase":
		_chase_step()
	_move(delta)


## 추격 시작 (#47): 바로 기어가지 않고 STALKER_DROP_S 동안 제자리에서 엎드린 뒤 chase 로.
func _begin_chase() -> void:
	_retreat_on = false                                        # #54 물러나던 중에 들켰다 — 철수는 없던 일이 된다
	_lose_left = Tuning.STALKER_LOSE_S
	_path.clear()
	velocity.x = 0.0
	velocity.z = 0.0
	_drop_left = Tuning.STALKER_DROP_S
	if on_ceiling:                                             # 천장에서는 엎드릴 일이 없다 — 기어서 다가가다 가까워지면 떨어진다 (#48)
		_set_state("chase")
		return
	_set_state("drop" if Tuning.STALKER_DROP_S > 0.0 else "chase")   # 천장에서는 엎드릴 일이 없다 — 떨어지는 연출은 #48 2단계


func _speed() -> float:
	if on_ceiling:
		if state == "chase":
			return Tuning.STALKER_CEIL_CHASE_SPEED                    # #52 천장 추격은 바닥 추격과 같은 속도
		if state == "investigate":
			return Tuning.STALKER_CEIL_INV_SPEED                      # #53 천장에서 빛을 보고 다가가는 속도
		return Tuning.STALKER_CEIL_SPEED
	var s: float = Tuning.STALKER_SPEED.get(state, Tuning.STALKER_SPEED["wander"])
	if state == "investigate" and _curious:
		s = Tuning.STALKER_SPEED["wander"]
	if dark_card and state in ["investigate", "search"]:
		s *= Tuning.CARD_DARK_SPEED_MUL
	return s


func _move(delta: float) -> void:
	if hold or _wp >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if on_ceiling else velocity.y - (Tuning.GRAVITY * delta if not is_on_floor() else 0.0)
		move_and_slide()
		if _wp >= _path.size() and not hold and state in MOVING:
			_arrived()
		return
	var target: Vector3 = _path[_wp]
	var d := target - position
	d.y = 0.0
	if d.length() < 0.35:
		_wp += 1
		return
	var dir := d.normalized()
	var sp := _speed()
	velocity.x = dir.x * sp
	velocity.z = dir.z * sp
	if on_ceiling:                                                            # #48: 중력 대신 그 칸 천장에 붙어 간다
		if ceiling_y(target) < Tuning.STALKER_CEIL_MIN_H:                     # 다음 길목이 낮은 칸(곡선·목)이면 벽을 타고 내려온다
			if not climb_down_to_floor():                                     # 여기 벽이 없으면 그 칸으로 가지 않고 다른 길을 고른다
				_path.clear()
				_pick_wander()
			return
		var c := ceiling_y(position)
		if c > Tuning.STALKER_CEIL_MIN_H:
			_ceil_y = c
		var want: float = _ceil_y - Tuning.STALKER_CEIL_CLEAR
		position.y = move_toward(position.y, want, Tuning.STALKER_CEIL_RISE * delta)
		if body != null:
			body.surface_point = fd.root.to_global(Vector3(position.x, _ceil_y, position.z))   # 손은 천장면을 짚는다 (#46 을 천장으로 넓힌 것)
		velocity.y = 0.0
	else:
		velocity.y = velocity.y - Tuning.GRAVITY * delta if not is_on_floor() else 0.0
	rotation.y = atan2(dir.x, dir.z)
	if dark_card and state in ["investigate", "search"]:                       # 텔: 머리를 좌우로 훑는다
		_sway_t += delta
		rotation.y += sin(_sway_t * 2.0) * deg_to_rad(Tuning.CARD_DARK_SWAY_DEG)
	move_and_slide()
	if body != null and _clip_for(state) != "":
		body.play(_clip_for(state), _clip_speed(state))


func _arrived() -> void:
	match state:
		"wander":
			_pause_left = Tuning.STALKER_WANDER_PAUSE_S
		"investigate":
			_start_search(position)
		"search":
			_dwell_left = Tuning.STALKER_DWELL_S * dwell_mul
			if player != null:
				face_toward(player.global_position)
		"retreat":
			hide_away()
		"chase":
			pass


# ---------------- 길 ----------------

## cell 까지 격자 길을 잡는다. 없으면 false
func _go(cell: Vector2i) -> bool:
	var from := MineAssembler.cell_of(position)
	var cells: Array[Vector2i] = MineAssembler.grid_path(fd, from, cell)
	if cells.is_empty():
		return false
	_path.clear()
	var g: float = Tuning.GRID_CELL
	for i in range(1, cells.size()):
		var a: Vector2i = cells[i - 1]
		var b: Vector2i = cells[i]
		_path.append(MineAssembler.cell_world(a) + Vector3(b.x - a.x, 0.0, b.y - a.y) * g * 0.5)   # 뚫린 면 한가운데
	_path.append(MineAssembler.cell_world(cells[cells.size() - 1]))
	_wp = 0
	_target_cell = cell
	return true


func _pick_wander() -> void:
	var near: Dictionary = MineAssembler.grid_dist(fd, wander_center, Tuning.STALKER_WANDER_CELLS)
	var keys: Array = near.keys()
	if keys.is_empty():
		return
	for k in 6:
		var c: Vector2i = keys[_rng.randi() % keys.size()]
		if c != MineAssembler.cell_of(position) and _go(c):
			return


## 조사 끝·스턴 뒤: 근처 숨는 곳 2~3곳을 차례로 뒤진다
func _start_search(at: Vector3) -> void:
	if on_ceiling or state == "climb":                                # 수색도 바닥에서 (#49) — 광차·대피소를 뒤져야 한다
		_pending_inv = at
		climb_down_to_floor()
		return
	_set_state("search")
	_spots.clear()
	var here := MineAssembler.cell_of(at)
	var near: Dictionary = MineAssembler.grid_dist(fd, here, Tuning.STALKER_SEARCH_CELLS)
	var cands: Array[Vector3] = []
	for c in near.keys():
		if c in _searched:
			continue
		if fd.kind.get(c, "") == "refuge":
			cands.append(MineAssembler.cell_world(c))
	if peek_carts:
		for cart in fd.carts:
			var cn := cart as Node3D
			var cc := MineAssembler.cell_of(cn.global_position)
			if near.has(cc):
				cands.append(Vector3(cn.global_position.x, 0.0, cn.global_position.z) + cn.global_transform.basis.x * (Tuning.CART_OFF_SIDE + 0.4))
	var want: int = Tuning.STALKER_SPOTS_MIN + (_rng.randi() % (Tuning.STALKER_SPOTS_MAX - Tuning.STALKER_SPOTS_MIN + 1))
	var open_cells: Array = near.keys()
	var guard := 0
	while cands.size() < want and guard < 20 and not open_cells.is_empty():
		guard += 1
		var c: Vector2i = open_cells[_rng.randi() % open_cells.size()]
		if c != here and not c in _searched:
			cands.append(MineAssembler.cell_world(c))
	_spots = cands.slice(0, want)
	_next_spot()


func _next_spot() -> void:
	_searched.append(MineAssembler.cell_of(position))
	while not _spots.is_empty():
		var p: Vector3 = _spots.pop_front()
		if _go(MineAssembler.cell_of(p)):
			_path[_path.size() - 1] = p                                 # 마지막 길목은 곳 자체 (광차 옆 등)
			return
	_searched.clear()
	wander_center = MineAssembler.cell_of(position)
	_set_state("wander")
	_pick_wander()


## 수색 자리에서 머무는 동안: 숨은 플레이어가 STALKER_FOUND_M 안이면 들킨다
func _check_found() -> void:
	if player == null or not player.is_hidden():
		return
	if global_position.distance_to(player.global_position) <= Tuning.STALKER_FOUND_M:
		found_count += 1
		last_seen = player.global_position
		_path.clear()
		velocity = Vector3.ZERO
		_alert_left = Tuning.STALKER_ALERT_S
		_set_state("alert")


## 철수·등장 자리: 플레이어 시야 밖 곡선 칸. 등장은 Director 가 고르고, 철수는 여기(지금 자리에서 가까운 것)
func _hide_cell() -> Vector2i:
	var from := MineAssembler.cell_of(position)
	var dist: Dictionary = MineAssembler.grid_dist(fd, from, 12)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for c in dist.keys():
		if not fd.pieces.has(c) or fd.pieces[c]["name"] != "curve" or dist[c] < 2:
			continue
		if player != null and not MineAssembler.behind_player(player, MineAssembler.cell_world(c, fd.y)):
			continue
		if dist[c] < best_d:
			best_d = dist[c]
			best = c
	return best


# ---------------- 감각 ----------------

func _sense(_delta: float) -> void:
	if player == null or player.dead or state == "retreat":
		return
	var eye_h: float = Tuning.STALKER_CEIL_EYE_H if on_ceiling else Tuning.STALKER_EYE_H
	var to: Vector3 = player.global_position + Vector3(0.0, Tuning.EYE_HEIGHT, 0.0) - (global_position + Vector3(0.0, eye_h, 0.0))
	var dist := to.length()
	if state == "chase":
		if dist <= Tuning.STALKER_CATCH_M:
			_catch()
		return
	if not player.lamp_on or player.is_hidden():
		return
	var fwd: Vector3 = global_transform.basis.z
	var ang := rad_to_deg(fwd.angle_to(Vector3(to.x, 0.0, to.z).normalized()))
	if dist <= Tuning.STALKER_EYE_M and ang <= Tuning.STALKER_EYE_DEG and _clear_line(to):
		last_seen = player.global_position
		_begin_chase()
		return
	if state in ["wander", "search"] and dist <= Tuning.STALKER_LIGHT_M and _clear_line(to):
		investigate(player.global_position, true)


func _clear_line(to: Vector3) -> bool:
	eye.target_position = eye.global_transform.basis.inverse() * to
	eye.force_raycast_update()
	return not eye.is_colliding()


## 추격: 보이면 플레이어 자리로, 안 보이면 마지막 자리로. STALKER_LOSE_S 못 보면 조사
func _chase_step() -> void:
	if on_ceiling and Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() <= Tuning.STALKER_FALL_TRIGGER_M:
		begin_hang()                                                          # #48 천장 추격 → 이 거리에서 떨어진다 (#57: 먼저 매달린다)
		return
	var eye_h: float = Tuning.STALKER_CEIL_EYE_H if on_ceiling else Tuning.STALKER_EYE_H
	var to: Vector3 = player.global_position + Vector3(0.0, Tuning.EYE_HEIGHT, 0.0) - (global_position + Vector3(0.0, eye_h, 0.0))
	var seen: bool = player.lamp_on and not player.is_hidden() and to.length() <= Tuning.STALKER_EYE_M and _clear_line(to)
	if seen:
		last_seen = player.global_position
		_lose_left = Tuning.STALKER_LOSE_S
	else:
		_lose_left -= get_physics_process_delta_time()
		if _lose_left <= 0.0:
			_curious = false
			_set_state("investigate")
			if not _go(MineAssembler.cell_of(last_seen)):
				_start_search(position)
			return
	var cell := MineAssembler.cell_of(last_seen)
	if cell != _target_cell or _wp >= _path.size():
		if not _go(cell):
			_path = [Vector3(last_seen.x, 0.0, last_seen.z)]
			_wp = 0
	if MineAssembler.cell_of(position) == cell:                                # 같은 칸: 마지막 자리로 곧장
		_path = [Vector3(last_seen.x, 0.0, last_seen.z)]
		_wp = 0


func _catch() -> void:
	_path.clear()
	velocity = Vector3.ZERO
	face_toward(player.global_position)
	_set_state("catch")
	caught_player.emit()
	if player.has_method("caught"):
		player.caught(self)
