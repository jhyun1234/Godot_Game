extends CharacterBody3D

## 1인칭 이동 · 마우스 시점 · 점프.
## 수치는 전부 scripts/Tuning.gd 에 있다.

## 캔 광석 수가 바뀌면 알린다. Hud 가 받는다.
signal ore_changed(count: int)
## 위험 값이 바뀌면 알린다. DangerHud 가 받는다.
signal danger_changed(value: float)
## 위험이 100 에 닿아 무너졌다. DeathScreen 이 받는다.
signal died

@onready var _head: Node3D = $Head

var ore_count := 0
## 위험 게이지. 곡괭이질(Miner)과 리프트 하강(Lift)이 올린다. 내려가는 것은 정산 때 일이다.
var danger := 0.0
var dead := false
var _tremor_wait := 0.0
var _pitch := 0.0
var _head_rest := Vector3.ZERO
var _shake_left := 0.0
var _shake_amount := 0.0
var _shake_span := 0.0
var _lamp_bob_phase := 0.0
var ride: Node3D = null          # 타고 있는 광차 (#29). 잠기면 물리를 안 돌리고 자리만 따라간다
var carry: Node3D = null         # 든 부품 (#30). 걷기 ×CARRY_SPEED_MUL, 점프 불가
var repair_target: Node = null   # 지금 E 를 누르고 있는 고장 (Fault). HUD 가 읽는다. 있으면 점프 안 함
var _claim_frame := -1
var ride_offset := Vector3.ZERO
var _ride_yaw := 0.0
var lamp_on := true              # 헤드램프 (#32). F 로 토글. 끄면 Atmosphere 가 눈 적응(환경광)을 올린다
var _step_left := 0.0
var stance := "walk"             # 자세 (#34): crouch / walk / run. 속도·발소리는 Tuning.STANCE
var stamina := Tuning.STAMINA_MAX
var exhausted := false           # 0 에서 Shift 를 계속 눌렀다 — 100 찰 때까지 못 움직인다 (시점·숙이기는 됨)
var has_pick := true             # 곡괭이를 들고 있나. 던지면 false, 주우면 true. Miner 가 본다
var death_text := Tuning.DEATH_TEXT   # 검은 화면 글자 (#35): 붕괴 / 잡힘. DeathScreen 이 died 때 읽는다
var _thrown: RigidBody3D = null
var _blackout_tw: Tween          # #58 괴물 낙하 정전. F·잡힘·붕괴가 끊는다


func _ready() -> void:
	_head_rest = _head.position
	$Magnet.body_entered.connect(_on_magnet_body_entered)
	_setup_headlamp()
	_capture_mouse()


## 헤드램프. Head 밑에 있지만 top_level 이라 부모를 안 따라간다 — _update_lamp 가
## 카메라를 반 박자 늦게 쫓아가게 옮긴다(#17 수정, 사용자 판정 "빛이 따라오는지 모르겠다").
## 수치는 씬이 아니라 Tuning 에서 온다 (CLAUDE.md §7).
func _setup_headlamp() -> void:
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	if lamp == null:
		push_warning("Headlamp 노드가 없다 — 갱도가 안 어두워진다")
		return
	lamp.top_level = true
	_update_lamp(1.0e9)         # 첫 프레임은 카메라에 딱 붙여 시작한다
	lamp.spot_angle = Tuning.LAMP_ANGLE_DEG
	lamp.spot_angle_attenuation = Tuning.LAMP_ATTEN
	lamp.spot_range = Tuning.LAMP_RANGE
	lamp.spot_attenuation = Tuning.LAMP_DIST_ATTEN
	lamp.light_energy = Tuning.LAMP_ENERGY
	lamp.light_color = Tuning.LAMP_COLOR
	lamp.shadow_enabled = Tuning.LAMP_SHADOW

	# 곡괭이는 등과 같은 자리(눈앞)에 있다. 그림자를 만들게 두면 그 그림자가
	# 벽 전체를 덮어 화면이 통째로 어두워진다. 뷰모델이라 그림자가 필요도 없다.
	var pick := _head.get_node_or_null("Camera3D/Pickaxe")
	if pick != null:
		for n in pick.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func add_ore(count: int) -> void:
	ore_count += count
	ore_changed.emit(ore_count)


func add_danger(amount: float) -> void:
	danger = clampf(danger + amount, 0.0, Tuning.DANGER_MAX)
	danger_changed.emit(danger)
	if danger >= Tuning.DANGER_MAX and not dead:
		_collapse()


func is_dead() -> bool:
	return dead


## 무너진다. 조작이 끊기고, 흔들리고, 돌이 쏟아지고, 등이 꺼진다.
## 검은 화면은 DeathScreen 이 died 를 받아 띄운다. 3초 뒤 방을 다시 띄운다 —
## 게이지·광석은 씬이 새로 뜨면서 0 이 된다. 되돌릴 상태를 따로 안 둔다.
func _collapse() -> void:
	dead = true
	death_text = Tuning.DEATH_TEXT
	died.emit()
	shake(Tuning.DEATH_SHAKE_AMOUNT, Tuning.DEATH_SHAKE_TIME)
	var room := get_parent()
	var top := global_position + Vector3.UP * Tuning.DEATH_ROCK_HEIGHT
	Dust.burst(room, top, Vector3.DOWN, Tuning.DEATH_DUST)
	_rain_rocks(room, top)
	_stop_blackout()
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	if lamp != null:
		create_tween().tween_property(lamp, "light_energy", 0.0, Tuning.DEATH_LAMP_FADE)
	# 사람이 지나는 화면 전환이라 템플릿의 SceneLoader 를 쓴다 (CLAUDE.md §5).
	get_tree().create_timer(Tuning.DEATH_RESTART_TIME).timeout.connect(
		SceneLoader.reload_current_scene)


## 괴물에게 잡혔다 (#35). 조작이 끊기고, 시점이 괴물 쪽으로 돌아가고, 램프가 꺼진다. 돌은 안 떨어진다.
## 검은 화면·재시작은 붕괴와 같은 길 (died → DeathScreen, DEATH_RESTART_TIME 뒤 reload).
func caught(by: Node3D) -> void:
	if dead:
		return
	dead = true
	death_text = Tuning.CAUGHT_TEXT
	died.emit()
	var to: Vector3 = by.global_position + Vector3(0.0, Tuning.STALKER_EYE_H, 0.0) - _head.global_position
	var yaw: float = atan2(-to.x, -to.z)                          # -Z 가 앞
	var pitch: float = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -deg_to_rad(Tuning.PITCH_LIMIT_DEG), deg_to_rad(Tuning.PITCH_LIMIT_DEG))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "rotation:y", yaw, Tuning.CAUGHT_TURN_S)
	tw.tween_property(_head, "rotation:x", pitch, Tuning.CAUGHT_TURN_S)
	_pitch = pitch
	_stop_blackout()
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	if lamp != null:
		tw.tween_property(lamp, "light_energy", 0.0, Tuning.CAUGHT_TURN_S)
	get_tree().create_timer(Tuning.DEATH_RESTART_TIME).timeout.connect(
		SceneLoader.reload_current_scene)


## #58 헤드램프 빛만 off_s 동안 끈다(괴물이 천장에서 떨어질 때). 툭 꺼지고 STALKER_DROP_LIGHT_S 에 걸쳐 켜진다.
## lamp_on · 눈 적응은 그대로 — 괴물 눈과 감독 버릇 세기는 lamp_on 을 본다. 플레이어가 꺼 둔 램프는 건드리지 않는다
func lamp_blackout(off_s: float) -> void:
	if not lamp_on or dead:
		return
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	if lamp == null:
		return
	_stop_blackout()
	lamp.light_energy = 0.0
	_blackout_tw = create_tween()
	_blackout_tw.tween_interval(off_s)
	_blackout_tw.tween_property(lamp, "light_energy", Tuning.LAMP_ENERGY, Tuning.STALKER_DROP_LIGHT_S)


func _stop_blackout() -> void:
	if _blackout_tw != null:
		_blackout_tw.kill()
		_blackout_tw = null


## 괴물 눈에 안 띄는 자리인가 (#35): 광차에 숙여 타고 있다(눈 1.0 < 테두리 1.72) 또는 대피소 칸 안. 숙이기(조용함)와는 다르다
func is_hidden() -> bool:
	if ride != null and stance == "crouch":
		return true
	var asm := get_parent().get_node_or_null("Layers")
	if asm == null or not "floors" in asm:
		return false
	var c: Vector2i = MineAssembler.cell_of(global_position)
	for fd in asm.floors:
		if absf(global_position.y - fd.y) < Tuning.LIFT_DROP * 0.5 and fd.kind.get(c, "") == "refuge":
			return true
	return false


## 평타 자갈 메시를 머리 위에 흩뿌린다. 중력이 떨어뜨린다. 새 모델은 없다.
func _rain_rocks(parent: Node, top: Vector3) -> void:
	var packed := load(OrePocket.CHIPS_PATH) as PackedScene
	if packed == null:
		return
	var set_root := packed.instantiate()
	var meshes: Array[Mesh] = []
	for child in set_root.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			meshes.append(mi.mesh)
	set_root.queue_free()
	if meshes.is_empty():
		return
	for i in Tuning.DEATH_ROCKS:
		var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) 			* Tuning.DEATH_ROCK_RADIUS + Vector3(0.0, randf_range(0.0, 1.5), 0.0)
		var basis := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * Tuning.CHUNK_SPIN
		WallChunk.spawn(parent, meshes[randi() % meshes.size()],
			Transform3D(basis, top + off), Vector3.ZERO, spin)


## 자석 범위에 들어온 광석은 몸으로 날아온다. 발밑을 조준해 누르는 것보다
## 채굴 흐름이 안 끊긴다.
func _on_magnet_body_entered(body: Node3D) -> void:
	var ore := body as Ore
	if ore != null:
		ore.attract(self)


## 화면을 짧게 흔든다. 벽이 부서질 때 Miner 가 부른다.
## 카메라가 아니라 Head 를 흔든다 — 시점 회전이 Head 에 걸려 있어서,
## 카메라를 옮기면 조준선이 틀어진다. 위치만 흔들면 조준은 그대로다.
func shake(amount: float, span: float) -> void:
	_shake_amount = amount
	_shake_span = span
	_shake_left = span


func _unhandled_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * Tuning.MOUSE_SENSITIVITY)
		var limit := deg_to_rad(Tuning.PITCH_LIMIT_DEG)
		_pitch = clampf(_pitch - motion.relative.y * Tuning.MOUSE_SENSITIVITY, -limit, limit)
		_head.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_capture_mouse()


## E 는 부품·고장·광차·플레이어가 각자 폴링한다 — 한 프레임에 하나만 먹게 먼저 부른 쪽이 가져간다
func interact_claim() -> bool:
	var f: int = Engine.get_physics_frames()
	if _claim_frame == f:
		return false
	_claim_frame = f
	return true


func pick_up(part: Node3D) -> void:
	carry = part
	part.carried = true
	part.get_parent().remove_child(part)
	$Head/Camera3D/Carry.add_child(part)
	part.position = Vector3.ZERO
	part.rotation = Vector3(0.0, PI * 0.5, 0.12)    # 가로로 든다


func drop_carry() -> void:
	if carry == null:
		return
	var part := carry
	carry = null
	var world: Node = get_parent()
	part.get_parent().remove_child(part)
	world.add_child(part)
	part.global_position = global_position + (-transform.basis.z) * 1.2 + Vector3(0.0, Tuning.PART_SIZE.y * 0.5, 0.0)
	part.global_rotation = Vector3(0.0, rotation.y, 0.0)
	part.carried = false


## 고장에 세웠다 — 부품 소모
func consume_carry() -> void:
	if carry == null:
		return
	carry.queue_free()
	carry = null


func board(cart: Node3D, seat: Vector3) -> void:
	ride = cart
	ride_offset = seat
	_ride_yaw = cart.global_rotation.y
	velocity = Vector3.ZERO


func unboard() -> void:
	ride = null


func _physics_process(delta: float) -> void:
	_update_tremor(delta)
	_update_shake(delta)
	if not dead and Input.is_action_just_pressed("lamp"):
		set_lamp(not lamp_on)
	if ride != null:                                   # 광차 위: 광차가 돈 만큼 시점도 돌고, 자리는 짐칸에 고정
		var yaw: float = ride.global_rotation.y
		rotate_y(angle_difference(_ride_yaw, yaw))
		_ride_yaw = yaw
		global_position = ride.global_position + ride.global_transform.basis * ride_offset
		velocity = Vector3.ZERO
		stance = "crouch" if Input.is_action_pressed("crouch") and not dead else "walk"   # 타고 숙이면 숨는다 (#35 is_hidden)
		_update_crouch(delta)
		return
	var grounded := is_on_floor()
	if carry != null and Input.is_action_just_pressed("interact") and interact_claim():
		drop_carry()
	if Input.is_action_just_pressed("throw") and has_pick and not dead and carry == null and repair_target == null:
		_throw_pick()

	# 죽으면 입력이 안 먹는다. 중력·감속은 그대로 돈다
	var input := Vector2.ZERO if dead 		else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# 자세 (#34): Ctrl 숙이기 > Shift 달리기(스태미나 > 0, 부품 없음, 움직일 때만) > 걷기
	var want_crouch := Input.is_action_pressed("crouch") and not dead
	var want_run := Input.is_action_pressed("run") and not dead and not want_crouch and carry == null and input != Vector2.ZERO
	if want_run and stamina <= 0.0 and not exhausted:
		exhausted = true                               # 0 인데 계속 눌렀다 — 탈진
		shake(Tuning.SHAKE_AMOUNT, Tuning.SHAKE_TIME)
	if exhausted:
		want_run = false
		input = Vector2.ZERO
		if stamina >= Tuning.STAMINA_MAX:
			exhausted = false
	stance = "crouch" if want_crouch else ("run" if want_run else "walk")
	if stance == "run":
		stamina -= Tuning.STAMINA_RUN * delta
	elif input != Vector2.ZERO:
		stamina += Tuning.STAMINA_WALK * delta
	else:
		stamina += Tuning.STAMINA_IDLE * delta
	stamina = clampf(stamina, 0.0, Tuning.STAMINA_MAX)
	_update_crouch(delta)

	if grounded:
		if Input.is_action_just_pressed("jump") and not dead and carry == null and repair_target == null and stance != "crouch" and not exhausted:   # 걷기·달리기 중 점프 (사용자 09-11: 달리며 점프 안 되던 것 고침). 숙이면 못 뛴다
			velocity.y = Tuning.jump_velocity()
	else:
		velocity.y -= Tuning.GRAVITY * delta

	var speed: float = Tuning.STANCE[stance]["speed"]
	var wish := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized() * speed * (Tuning.CARRY_SPEED_MUL if carry != null else 1.0)

	var rate := Tuning.accel() if input != Vector2.ZERO else Tuning.decel()
	if not grounded:
		rate *= Tuning.AIR_CONTROL

	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish, rate * delta)
	velocity.x = flat.x
	velocity.z = flat.z

	move_and_slide()

	var pick := _head.get_node_or_null("Camera3D/Pickaxe")
	if pick != null:
		pick.bob(Vector2(velocity.x, velocity.z).length(), delta)
	# 발걸음 소음 (#32): 바닥에서 움직이는 동안 자세의 간격마다 (#34). 멈추면 다음 걸음이 바로 난다
	if grounded and Vector2(velocity.x, velocity.z).length() > 0.5:
		_step_left -= delta
		if _step_left <= 0.0:
			_step_left = Tuning.STANCE[stance]["step"]
			NoiseBus.make(global_position, Tuning.STANCE[stance]["radius"], "step", self)
	else:
		_step_left = 0.0


## 숙이기 (#34): 눈(Head 쉼자리)이 CROUCH_EYE 로 내려가고 충돌 캡슐이 줄어든다. _update_shake 가 _head_rest 를 기준으로 그린다
func _update_crouch(delta: float) -> void:
	var eye: float = Tuning.CROUCH_EYE if stance == "crouch" else Tuning.EYE_HEIGHT
	if is_equal_approx(_head_rest.y, eye):
		return
	_head_rest.y = move_toward(_head_rest.y, eye, (Tuning.EYE_HEIGHT - Tuning.CROUCH_EYE) / Tuning.CROUCH_TIME * delta)
	var col := $Collider as CollisionShape3D
	var cap := col.shape as CapsuleShape3D
	var h: float = Tuning.BODY_HEIGHT - (Tuning.EYE_HEIGHT - _head_rest.y)
	cap.height = h
	col.position.y = h * 0.5


## 곡괭이 던지기 (#34): 뷰모델을 숨기고 ThrownPick 을 카메라 앞에서 던진다. 착지 소음·줍기는 ThrownPick
func _throw_pick() -> void:
	var pick := _head.get_node_or_null("Camera3D/Pickaxe") as Node3D
	var cam := _head.get_node_or_null("Camera3D") as Camera3D
	if pick == null or cam == null:
		return
	has_pick = false
	pick.visible = false
	var body := ThrownPick.new()
	body.setup(self, load("res://assets/generated/tunnel/pick.gltf"))
	get_parent().add_child(body)
	var fwd: Vector3 = -cam.global_transform.basis.z
	var dir: Vector3 = fwd.rotated(cam.global_transform.basis.x, deg_to_rad(Tuning.THROW_UP_DEG)).normalized()
	body.global_position = cam.global_position + fwd * 0.6
	body.linear_velocity = dir * Tuning.THROW_SPEED
	body.angular_velocity = cam.global_transform.basis.x * 8.0
	_thrown = body


## ThrownPick 이 E 로 주워졌다
func pick_returned() -> void:
	has_pick = true
	_thrown = null
	var pick := _head.get_node_or_null("Camera3D/Pickaxe") as Node3D
	if pick != null:
		pick.visible = true


## 헤드램프 끄기/켜기 (#32). 끄면 눈이 어둠에 적응한다 (Atmosphere 환경광). 켜면 즉시 평소로
func set_lamp(on: bool) -> void:
	_stop_blackout()                 # #58 괴물 낙하 정전 중에 F 를 누르면 F 가 이긴다
	lamp_on = on
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	if lamp != null:
		create_tween().tween_property(lamp, "light_energy", Tuning.LAMP_ENERGY if on else 0.0, Tuning.LAMP_TOGGLE_TIME)
	Atmosphere.set_adapt(not on)


## 위험이 높으면 갱도가 주기적으로 떨린다. 파괴 흔들림과 같은 shake() 를 작게 부른다.
## 부서지는 흔들림이 도는 중이면 건너뛴다 — 덮어쓰면 그쪽이 짧아진다.
func _process(delta: float) -> void:
	_update_lamp(delta)


## 램프가 카메라를 늦게 쫓아간다. 등이 카메라와 같은 축에 붙어 있으면 빛에 방향이
## 없다 — 돌려도 화면 가운데 원반뿐이라 "내 등"으로 안 읽힌다(사용자 판정 09-08).
## 회전은 LAMP_FOLLOW_TIME 으로 따라잡고, 원점은 눈 위 LAMP_OFFSET(이마), 걸으면 LAMP_BOB 만큼 끄덕인다.
func _update_lamp(delta: float) -> void:
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	var cam := _head.get_node_or_null("Camera3D") as Camera3D
	if lamp == null or cam == null:
		return
	var target: Transform3D = cam.global_transform
	var origin: Vector3 = target.origin + target.basis * Tuning.LAMP_OFFSET
	var want := target.basis.get_rotation_quaternion()
	var have := lamp.global_transform.basis.get_rotation_quaternion()
	var k := 1.0 if Tuning.LAMP_FOLLOW_TIME <= 0.0 else 1.0 - exp(-delta / Tuning.LAMP_FOLLOW_TIME)
	var q := have.slerp(want, clampf(k, 0.0, 1.0))
	# 걷기 끄덕임. 곡괭이 bob 과 같은 속도로, 속도에 비례해.
	var speed := Vector2(velocity.x, velocity.z).length()
	_lamp_bob_phase += Tuning.PICK_BOB_SPEED * delta * (speed / Tuning.WALK_SPEED)
	var nod := Basis.from_euler(Vector3(
		sin(_lamp_bob_phase) * deg_to_rad(Tuning.LAMP_BOB) * (speed / Tuning.WALK_SPEED), 0.0, 0.0))
	lamp.global_transform = Transform3D(Basis(q) * nod, origin)


## 검사용. 램프 시선과 카메라 시선의 각도 차(도).
func lamp_lag_deg() -> float:
	var lamp := _head.get_node_or_null("Headlamp") as SpotLight3D
	var cam := _head.get_node_or_null("Camera3D") as Camera3D
	if lamp == null or cam == null:
		return 0.0
	return rad_to_deg((-lamp.global_transform.basis.z).angle_to(-cam.global_transform.basis.z))


func _update_tremor(delta: float) -> void:
	if danger < Tuning.DANGER_TREMOR_FROM:
		_tremor_wait = 0.0          # 넘는 순간 바로 한 번 떨린다
		return
	_tremor_wait -= delta
	if _tremor_wait <= 0.0 and _shake_left <= 0.0:
		_tremor_wait = Tuning.DANGER_TREMOR_INTERVAL
		shake(Tuning.DANGER_TREMOR_AMOUNT, Tuning.DANGER_TREMOR_TIME)


func _update_shake(delta: float) -> void:
	if _shake_left <= 0.0:
		if _head.position != _head_rest:
			_head.position = _head_rest
		return
	_shake_left -= delta
	var strength: float = _shake_amount * maxf(_shake_left, 0.0) / _shake_span
	_head.position = _head_rest + Vector3(
		randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * strength


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
