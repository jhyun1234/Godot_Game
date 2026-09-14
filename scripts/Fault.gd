extends Node3D
## 고장난 지지목 하나 (제안서 #30). timber 칸 직선 조각의 세트 FAULT_SET: 오른쪽 기둥(post_R)을 숨기고 갓보(cap)를 기울인다.
## 오른쪽인 이유: 왼쪽 어깨엔 풍관(#28)이 걸려 있어 기운 갓보가 가린다.
##   broken    — 부품을 든 플레이어가 Socket 안에서 E → 기둥이 서고 socketed
##   socketed  — Socket 안에서 E 를 누르고 있으면 progress 가 찬다. 3~5초마다 스킬체크(바늘·구간). 스페이스가 구간 안이면 계속, 밖·한 바퀴면 실패
##   done      — 갓보 원위치. repaired 시그널 → 게이지 −DANGER_REPAIR_DONE
## 실패: 진행 −REPAIR_FAIL_BACK, 게이지 +DANGER_REPAIR_FAIL, 큰 흔들림 (소음은 ⑥). 시간값은 ⑦b 판정 전 참고값.

signal repaired(fault: Node3D)
signal failed(fault: Node3D)

var state := "broken"
var progress := 0.0
var repairing := false
var skill_active := false
var needle := 0.0            # 도, 0~360
var zone_start := 0.0        # 도. 성공 구간 [zone_start, zone_start + SKILL_ZONE_DEG]
var fails := 0
var zone_deg: float = Tuning.SKILL_ZONE_DEG          # 세운 부품 품질이 정한다 (#31)
var int_min: float = Tuning.SKILL_INTERVAL_MIN
var int_max: float = Tuning.SKILL_INTERVAL_MAX
var part_quality := ""
var _next_check := 0.0
var _post: Node3D
var _cap: Node3D
var _cap_rot := Vector3.ZERO
var _cap_pos := Vector3.ZERO
var _repairer: CharacterBody3D = null
var _rng := RandomNumberGenerator.new()
@onready var _socket: Area3D = $Socket


## 조립기가 트리에 넣은 뒤 부른다. piece = timber 칸의 직선 조각
func setup(piece: Node3D, set_idx: int, seed: int) -> void:
	_rng.seed = seed
	_post = piece.get_node_or_null("TMB_straight_%d_post_R" % set_idx)
	_cap = piece.get_node_or_null("TMB_straight_%d_cap" % set_idx)
	if _post == null or _cap == null:
		push_error("Fault: 조각에 TMB_straight_%d_post_R / cap 이 없다" % set_idx)
		return
	_post.visible = false
	_cap_rot = _cap.rotation
	_cap_pos = _cap.position
	var t: float = deg_to_rad(Tuning.FAULT_CAP_TILT_DEG)
	_cap.rotation.z = _cap_rot.z - t                              # 오른쪽(+x, 숨긴 기둥 쪽) 끝이 내려앉는다
	_cap.position.y = _cap_pos.y - sin(t) * Tuning.GRID_CELL * 0.25
	_socket.position = Vector3(_post.position.x - 0.6, 1.2, _post.position.z)   # 기둥 자리(기둥 원점은 높이 2.35 — y 는 사람 키로), 통로 쪽으로 조금
	_next_check = _rng.randf_range(int_min, int_max)


func post_visible() -> bool:
	return _post != null and _post.visible


func cap_tilt_deg() -> float:
	return absf(rad_to_deg(_cap.rotation.z - _cap_rot.z)) if _cap != null else 0.0


func in_zone() -> bool:
	return skill_active and needle >= zone_start and needle <= zone_start + zone_deg


func _player_in_socket() -> CharacterBody3D:
	for b in _socket.get_overlapping_bodies():
		if b is CharacterBody3D and b.has_method("interact_claim"):
			return b
	return null


func _physics_process(delta: float) -> void:
	if state == "done" or _post == null:
		return
	var p := _player_in_socket()
	if state == "broken":
		if p != null and p.carry != null and Input.is_action_just_pressed("interact") and p.interact_claim():
			part_quality = p.carry.get("quality") if p.carry.get("quality") != null else "creaky"
			if part_quality == "good":                             # 좋은 부품: 구간 넓고 체크 드묾 (#31)
				zone_deg = Tuning.SKILL_ZONE_GOOD_DEG
				int_min = Tuning.SKILL_INTERVAL_GOOD_MIN
				int_max = Tuning.SKILL_INTERVAL_GOOD_MAX
			_next_check = _rng.randf_range(int_min, int_max)
			p.consume_carry()
			_post.visible = true
			state = "socketed"
		return
	# socketed: E 를 누르고 있는 동안만 진행
	var holding: bool = p != null and p.ride == null and Input.is_action_pressed("interact")
	if not holding:
		if repairing:
			_stop(p)
		return
	if not repairing:
		repairing = true
		_repairer = p
		p.repair_target = self
	progress = minf(progress + delta / Tuning.REPAIR_HOLD_S, 1.0)
	if skill_active:
		needle += Tuning.SKILL_NEEDLE_RPS * 360.0 * delta
		if Input.is_action_just_pressed("jump"):
			if in_zone():
				_end_check()
			else:
				_fail()
		elif needle >= 360.0:
			_fail()
	else:
		_next_check -= delta
		if _next_check <= 0.0 and progress < 0.97:
			skill_active = true
			needle = 0.0
			zone_start = _rng.randf_range(70.0, 300.0 - zone_deg)
	if progress >= 1.0:
		_done()


func _end_check() -> void:
	skill_active = false
	_next_check = _rng.randf_range(int_min, int_max)


func _fail() -> void:
	fails += 1
	progress = maxf(progress - Tuning.REPAIR_FAIL_BACK, 0.0)
	_end_check()
	if _repairer != null:
		_repairer.add_danger(Tuning.DANGER_REPAIR_FAIL)
		_repairer.shake(Tuning.FAIL_SHAKE_AMOUNT, Tuning.FAIL_SHAKE_TIME)
	NoiseBus.make(global_position, Tuning.NOISE_REPAIR_FAIL, "repair_fail", _repairer)   # 큰 소음 (#32)
	failed.emit(self)


func _stop(p: CharacterBody3D) -> void:
	repairing = false
	skill_active = false
	if _repairer != null and _repairer.repair_target == self:
		_repairer.repair_target = null
	_repairer = null


func _done() -> void:
	state = "done"
	_cap.rotation = _cap_rot
	_cap.position = _cap_pos
	if _repairer != null:
		_repairer.add_danger(-Tuning.DANGER_REPAIR_DONE)
	_stop(_repairer)
	repaired.emit(self)
