class_name ThrownPick
extends RigidBody3D
## 던져진 곡괭이 (제안서 #34, 규칙 개정 4). Player._throw_pick 이 방(Room)에 넣는다.
## 첫 지형 충돌에서 큰 소음(NOISE_PICK_LAND) 한 번 — 유인. 그 뒤 굴러 멈추고 THROW_STUCK_S 지나면 얼린다(틈에 끼지 않게).
## CARRY_REACH 안에서 E → Player.pick_returned() 로 돌아간다. 괴물(층 5)에 닿으면 Stalker.stun() 하고 그 자리에 떨어진다 (#35).
## 층: 4(광석) — 플레이어(마스크 5)와 안 부딪힌다. 마스크: 1(지형) + 16(괴물).

var landed := false
var land_pos := Vector3.ZERO
var _player: CharacterBody3D
var _age := 0.0
var _land_age := 0.0


func setup(player: CharacterBody3D, mesh_scene: PackedScene) -> void:
	_player = player
	name = "ThrownPick"
	process_physics_priority = -10                     # E 를 자재함·광차보다 먼저 가져간다 (interact_claim 은 먼저 부른 쪽이 이긴다)
	collision_layer = 8
	collision_mask = 1 | 16
	mass = 2.0
	linear_damp = 1.0
	angular_damp = 4.0
	contact_monitor = true
	max_contacts_reported = 2
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = Tuning.THROW_BODY_R
	cs.shape = sph
	add_child(cs)
	var model := mesh_scene.instantiate() as Node3D
	model.name = "Mesh"
	model.scale = Vector3.ONE * Tuning.PICK_SCALE
	add_child(model)
	# 메시 원점이 자루 끝이라 AABB 가운데를 몸체 중심으로 맞춘다
	var box := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as MeshInstance3D).transform * b
		box = b if first else box.merge(b)
		first = false
	if not first:
		model.position = -box.get_center() * Tuning.PICK_SCALE
	var reach := Area3D.new()
	reach.name = "Reach"
	reach.collision_layer = 0
	reach.collision_mask = 2
	var rc := CollisionShape3D.new()
	var rs := SphereShape3D.new()
	rs.radius = Tuning.CARRY_REACH
	rc.shape = rs
	reach.add_child(rc)
	add_child(reach)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Stalker:                                    # 괴물 맞힘 (#35): 스턴, 튀지 않고 그 자리에 떨어진다
		(body as Stalker).stun()
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	if landed:
		return
	landed = true
	land_pos = global_position
	NoiseBus.make(global_position, Tuning.NOISE_PICK_LAND, "pick_land", _player)


func _physics_process(delta: float) -> void:
	_age += delta
	if landed:
		_land_age += delta
		if _land_age >= Tuning.THROW_STUCK_S and not freeze:
			freeze = true                                  # 더 안 구른다
		if global_position.y < land_pos.y - 2.0:           # 바닥 아래로 빠졌다 — 착지점으로
			freeze = true
			global_position = land_pos
	elif _age > Tuning.THROW_STUCK_S * 2.0:                # 아무 데도 안 닿았다(허공) — 그 자리에 세운다
		landed = true
		land_pos = global_position
		freeze = true
	if _player == null or not Input.is_action_just_pressed("interact"):
		return
	for body in $Reach.get_overlapping_bodies():
		if body == _player and _player.interact_claim():
			_player.pick_returned()
			queue_free()
			return
