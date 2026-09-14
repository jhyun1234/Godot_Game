extends RayCast3D

## 카메라 정면으로 레이를 쏴서 닿아 있는 OrePocket(광맥 포켓)을 친다.
## Player/Head/Camera3D/MineRay 에 붙는다.
##
## 레이 길이는 _ready 에서 Tuning 값으로 맞춘다 —
## 씬 파일과 Tuning.gd 두 곳에 사거리를 적어두면 갈라진다.

var _cooldown := 0.0
var _pick: Node3D = null


func _ready() -> void:
	target_position = Vector3(0.0, 0.0, -Tuning.MINE_RANGE)
	_pick = get_parent().get_node_or_null("Pickaxe")
	if _pick != null:
		_pick.struck.connect(_on_struck)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _cooldown > 0.0 or not Input.is_action_pressed("mine"):
		return
	if owner != null and owner.has_method("is_dead") and owner.is_dead():
		return
	if owner != null and owner.get("has_pick") == false:   # 던져서 손에 없다 (#34)
		return
	# 이 프레임의 최신 위치로 다시 쏜다. 노드 갱신 순서에 안 기댄다.
	force_raycast_update()
	var block := get_collider() as OrePocket
	if block == null or block.is_breaking():
		return
	_cooldown = Tuning.MINE_COOLDOWN
	# 곡괭이가 있으면 휘두르고, 머리가 벽에 닿는 순간에 데미지가 들어간다.
	# 곡괭이가 없으면(검사용 씬 등) 그냥 즉시 친다.
	if _pick != null:
		_pick.swing()
	else:
		_on_struck()


## 곡괭이 머리가 벽에 닿았다. 이 시점에 다시 쏴서 맞은 것을 친다 —
## 휘두르는 0.12초 사이에 시점이 돌아갔을 수 있다.
func _on_struck() -> void:
	force_raycast_update()
	var block := get_collider() as OrePocket
	if block == null or block.is_breaking():
		return
	block.take_hit(Tuning.MINE_DAMAGE, -global_transform.basis.z, get_collision_point())
	var player := owner as CharacterBody3D
	NoiseBus.make(get_collision_point(), Tuning.NOISE_PICK, "pick", player)     # 벽에 닿은 타격만 소음 (#32). 허공은 위에서 걸러진다
	# 닿은 타격마다 DANGER_PER_HIT 만큼 (#24 로 0 — 경로만 남긴다). 허공을 친 것은 안 온다 (위에서 걸러진다).
	if player != null and player.has_method("add_danger"):
		player.add_danger(Tuning.DANGER_PER_HIT)
	# 덩이가 빠질 때만 흔든다. 평타마다 흔들면 빠지는 순간이 안 특별해진다.
	if block.is_breaking():
		if player != null and player.has_method("shake"):
			player.shake(Tuning.SHAKE_AMOUNT, Tuning.SHAKE_TIME)
