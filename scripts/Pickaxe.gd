extends Node3D

## 화면에 들리는 곡괭이. Player/Head/Camera3D 밑에 붙는다.
##
## 충돌 판정이 없는 그림이다(뷰모델). 벽을 뚫고 보일 수 있고, 그건 그대로 둔다.
##
## 휘두르는 것은 코드로 한다 — 위치·회전을 숫자로 흔드는 것이라 리깅
## 애니메이션이 아니다 (CLAUDE.md §15).
##
## 곡괭이 머리가 벽에 닿는 순간 struck 을 emit 한다. Miner 가 그때 데미지를 넣는다.

signal struck

var _rest_pos := Vector3.ZERO
var _swinging := false
var _bob := 0.0


func _ready() -> void:
	position = Tuning.PICK_POS
	_rest_pos = position
	# 크기·각도는 전부 Tuning 에서 온다. 씬에 박아두면 두 곳이 갈라진다.
	#
	# "드는 자세"는 Mesh 에, "휘두르기"는 이 노드에 둔다. 한 노드에 섞으면
	# 자세를 만질 때마다 스윙 축이 같이 틀어진다.
	$Mesh.scale = Vector3.ONE * Tuning.PICK_SCALE
	$Mesh.rotation = Vector3(0.0, deg_to_rad(Tuning.PICK_YAW_DEG),
		deg_to_rad(Tuning.PICK_ROLL_DEG))
	rotation = Vector3(deg_to_rad(Tuning.PICK_TILT_DEG), 0.0, 0.0)


func is_swinging() -> bool:
	return _swinging


## 내려쳤다가 되돌아온다. 내려치기가 끝나는 순간이 타격 시점이다.
func swing() -> void:
	if _swinging:
		return
	_swinging = true
	# 앞으로(-X) 찍는다. +X 로 돌리면 머리가 +Z 로 넘어가는데 카메라는 -Z 를
	# 보고 있어서, 플레이어 자기 얼굴 쪽으로 찍는 꼴이 된다.
	var down := deg_to_rad(Tuning.PICK_TILT_DEG - Tuning.PICK_SWING_DEG)
	var up := deg_to_rad(Tuning.PICK_TILT_DEG)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", down, Tuning.PICK_DOWN_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: struck.emit())
	tween.tween_property(self, "rotation:x", up, Tuning.PICK_UP_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: _swinging = false)


## 걸을 때만 흔들린다. 서 있으면 멎는다.
func bob(speed: float, delta: float) -> void:
	if _swinging:
		return
	if speed < 0.2:
		_bob = 0.0
		position = position.lerp(_rest_pos, minf(delta * 8.0, 1.0))
		return
	_bob += delta * Tuning.PICK_BOB_SPEED
	position = _rest_pos + Vector3(
		cos(_bob) * Tuning.PICK_BOB_AMOUNT,
		absf(sin(_bob)) * Tuning.PICK_BOB_AMOUNT, 0.0)
