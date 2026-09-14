extends PathFollow3D
## 광차 하나 (제안서 #29). 순환선 Path3D 위를 CART_SPEED 로 돌고, 진행 0(정거장 앞 직선 끝)에서 CART_STOP_S 정차한다.
## E: Board 안의 플레이어를 짐칸에 잠근다(Player.board) / 타고 있으면 오른쪽 CART_OFF_SIDE 바닥에 내린다.
## 충돌 없음. 광차끼리 안 피한다 (ponytail: 간격 40초 > 정차 6초. 값이 바뀌어 겹치면 앞차 거리로 감속).

var rider: CharacterBody3D = null
var _stop_left := 0.0
var _length := 0.0
var _curve: Curve3D
var _noise_left := 0.0
@onready var _board: Area3D = $Board


func _ready() -> void:
	loop = true
	rotation_mode = PathFollow3D.ROTATION_NONE      # 회전은 _face 가 (#29-c)
	_curve = (get_parent() as Path3D).curve
	_length = _curve.get_baked_length()


## 조립기가 트리에 넣은 뒤 부른다. 시작점(0)에 놓인 광차는 정차 상태로 시작한다
func start(p: float) -> void:
	progress = p
	_stop_left = Tuning.CART_STOP_S if is_zero_approx(p) else 0.0
	_face()


## CART_LOOK m 앞 점을 본다. 접선(rotation_mode XYZ)은 호 폴리라인 꼭짓점마다 한 프레임에 14° 튀었다 —
## 두 점 다 진행에 연속이라 현 방향은 안 튄다 (프레임당 최대 2.4° = 반지름 3.5 를 8 m/s 로 도는 값)
func _face() -> void:
	var ahead: Vector3 = _curve.sample_baked(fposmod(progress + Tuning.CART_LOOK, _length))
	var dir: Vector3 = ahead - position
	dir.y = 0.0
	if not dir.is_zero_approx():
		basis = Basis.looking_at(dir)                     # -Z 가 앞 (ROTATION_XYZ 때와 같은 방향 규약)


func is_stopped() -> bool:
	return _stop_left > 0.0


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		if rider != null:
			_unboard()
		else:
			for body in _board.get_overlapping_bodies():
				if body is CharacterBody3D and body.has_method("board") and body.ride == null:
					rider = body
					body.board(self, Tuning.CART_SEAT)
					break
	if _stop_left > 0.0:
		_stop_left -= delta
		return
	_noise_left -= delta                          # 달리는 동안 1초마다 소음 (#32). 정차 중은 위에서 돌아간다
	if _noise_left <= 0.0:
		_noise_left = 1.0
		NoiseBus.make(global_position, Tuning.NOISE_CART, "cart", self)
	var before := progress
	progress += Tuning.CART_SPEED * delta
	if progress < before or (before < _length and progress >= _length):   # 한 바퀴 — 시작점에서 선다
		progress = 0.0
		_stop_left = Tuning.CART_STOP_S
	_face()


func _unboard() -> void:
	var r := rider
	rider = null
	r.unboard()
	r.global_position = global_position + global_transform.basis.x * Tuning.CART_OFF_SIDE + Vector3(0.0, 0.2, 0.0)
	r.velocity = Vector3.ZERO
