class_name Ore
extends RigidBody3D

## 벽에서 튀어나온 광석 한 덩이. MinableBlock 이 만든다.
##
## 조각(WallChunk)과 달리 시간이 지나도 사라지지 않는다 — 주우러 갈지 말지를
## 고르는 것이 이 게임의 긴장이라(CLAUDE.md §15), 시간이 대신 지워주면 안 된다.
##
## 레이어 4(광석) / 마스크 1(지형). 지형에만 떨어지고 플레이어를 막지 않는다.
## 자석은 Player/Magnet 이고 마스크 4만 본다.

const SCENE := "res://scenes/level/Ore.tscn"

var _target: Node3D = null
var _pending: Node3D = null
var _age := 0.0


static func spawn(parent: Node, at: Vector3, impulse: Vector3) -> Ore:
	var ore: Ore = (load(SCENE) as PackedScene).instantiate()
	parent.add_child(ore)
	ore.global_position = at
	ore.linear_velocity = impulse
	ore.angular_damp = Tuning.ORE_ROLL_DAMP
	ore.linear_damp = Tuning.ORE_ROLL_DAMP * 0.25
	ore.angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)) * Tuning.ORE_SPIN
	return ore


## 자석 범위에 들어왔다. 후보로만 기억하고, 날아갈지는 아래에서 거리로 정한다.
func attract(to: Node3D) -> void:
	if _target == null:
		_pending = to


func _physics_process(delta: float) -> void:
	_age += delta
	if _target == null:
		if _pending == null or _age < Tuning.ORE_MAGNET_DELAY:
			return
		# 거리로 직접 판정한다. body_exited 는 플레이어가 순간이동하면 안 오고,
		# 봇이 그렇게 움직인다. 신호는 후보를 알려줄 뿐이고 판단은 여기서 한다.
		if global_position.distance_to(_pending.global_position) > Tuning.ORE_MAGNET_RANGE:
			return
		_target = _pending
		# 물리를 끄고 직접 옮긴다. 안 그러면 빨려오는 내내 중력과 싸운다.
		freeze = true
	# 발밑이 아니라 가슴께로 빨려와야 화면에 보인다.
	var goal: Vector3 = _target.global_position + Vector3(0.0, Tuning.EYE_HEIGHT * 0.5, 0.0)
	global_position = global_position.move_toward(goal, Tuning.ORE_PULL_SPEED * delta)
	if global_position.distance_to(goal) <= Tuning.ORE_COLLECT_DIST:
		if _target.has_method("add_ore"):
			_target.add_ore(1)
		queue_free()
