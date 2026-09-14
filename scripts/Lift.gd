extends AnimatableBody3D

## 갱도 리프트(케이지). 위에 사람이 서 있을 때 E 를 누르면 문이 닫히고, 다 닫힌 뒤 아래층까지 내려간다.
## 도착하면 문이 열린다. 다시 누르면 같은 순서로 올라온다.
##
## AnimatableBody3D + sync_to_physics 라서, 위에 선 CharacterBody3D 는
## `move_and_slide` 가 알아서 실어 나른다. 플레이어 코드를 건드리지 않는다.
##
## 문 두 짝(Mesh/CAGE_GateL·R)은 glTF 노드다. 원점이 경첩이라 rotation.y 만 돌린다 —
## 애니메이션 파일은 없다(CLAUDE.md §15). 닫혀 있는 동안 `Gate` 충돌체가 켜져 못 내린다.
##
## 수치는 전부 scripts/Tuning.gd 에 있다.

## 층에 도착했다. 나중에 층 재생성·정산이 이걸 받는다.
signal arrived(at_bottom: bool)

const GATE_OPEN_DEG := 90.0     # 열린 문짝 각도. 바깥(갱도 쪽)으로 젖혀져 옆 기둥에 붙는다

@onready var _riders: Area3D = $Riders
@onready var _gate_shape: CollisionShape3D = $Gate
@onready var _gate_l: Node3D = get_node_or_null("Mesh/CAGE_GateL")
@onready var _gate_r: Node3D = get_node_or_null("Mesh/CAGE_GateR")

var _top_y := 0.0
var _target_y := 0.0
var _speed := 0.0
var _gate := 1.0            # 0 닫힘 ~ 1 열림
var _gate_target := 1.0
var _go_y := NAN            # 문이 다 닫히면 갈 높이


func _ready() -> void:
	_top_y = global_position.y
	_target_y = _top_y
	_apply_gate()


## 내려가는(또는 올라가는) 중인가. 봇과 나중의 위험 게이지가 본다.
func is_moving() -> bool:
	return not is_equal_approx(global_position.y, _target_y)


## 위에 사람이 있는가.
func has_rider() -> bool:
	return not _riders.get_overlapping_bodies().is_empty()


## 문이 완전히 닫혀 있는가. 봇이 본다.
func is_gate_closed() -> bool:
	return is_zero_approx(_gate) and is_zero_approx(_gate_target)


## 문 열림 비율 0(닫힘)~1(열림). 봇이 본다.
func gate_open_ratio() -> float:
	return _gate


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("interact") and has_rider() and not is_moving() \
			and is_equal_approx(_gate, 1.0) and is_nan(_go_y):
		var at_top := is_equal_approx(_target_y, _top_y)
		_go_y = _top_y - Tuning.LIFT_DROP if at_top else _top_y
		_gate_target = 0.0

	# 문. 닫히는 동안은 안 움직인다 — 다 닫힌 프레임에 목표 높이를 넘긴다.
	if not is_equal_approx(_gate, _gate_target):
		_gate = move_toward(_gate, _gate_target, delta / Tuning.LIFT_GATE_TIME)
		_apply_gate()
	if is_zero_approx(_gate) and not is_nan(_go_y):
		_target_y = _go_y
		_go_y = NAN

	var remain := _target_y - global_position.y
	if absf(remain) < 0.0005 and is_zero_approx(_speed):
		return

	# 도착 거리가 남은 제동거리보다 짧아지면 속도를 0 으로 몬다.
	# v^2 = 2as 를 그대로 쓴다 — 이렇게 해야 목표 지점에서 정확히 선다.
	var accel: float = Tuning.LIFT_SPEED / Tuning.LIFT_ACCEL_TIME
	var brake: float = _speed * _speed / (2.0 * accel)
	var want: float = 0.0 if absf(remain) <= brake else Tuning.LIFT_SPEED
	_speed = move_toward(_speed, want, accel * delta)

	var step: float = signf(remain) * _speed * delta
	var arriving := absf(step) >= absf(remain)
	if arriving:
		step = remain
		_speed = 0.0
	# 내려가는 동안 움직인 거리만큼 탄 사람의 위험이 오른다. 8m 에 20 —
	# 도착 순간에 확 뛰지 않고 바가 미끄러지듯 찬다. 올라올 때는 안 오른다.
	if step < 0.0:
		for body in _riders.get_overlapping_bodies():
			if body.has_method("add_danger"):
				body.add_danger(-step / Tuning.LIFT_DROP * Tuning.DANGER_PER_DROP)
	global_position.y += step
	if arriving:
		global_position.y = _target_y
		_gate_target = 1.0
		arrived.emit(not is_equal_approx(_target_y, _top_y))


func _apply_gate() -> void:
	var a := deg_to_rad(GATE_OPEN_DEG) * _gate
	if _gate_l != null:
		_gate_l.rotation.y = a
	if _gate_r != null:
		_gate_r.rotation.y = -a
	_gate_shape.disabled = is_equal_approx(_gate, 1.0)   # 조금이라도 닫히면 막는다
