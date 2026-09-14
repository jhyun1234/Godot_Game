extends CanvasLayer
## 개발용 괴물 표시 (제안서 #38). Player.tscn 안 — 부모가 플레이어. 왼쪽 위 한 줄:
##   압박 63 · 괴물 수색 · 18 m · 왼쪽 뒤 [어둠 수색]
## 숫자 9 = 이 층 감독 압박을 PRESSURE_SEND 로 (괴물 즉시 등장) · 숫자 8 = 괴물 정지/재개 (#43 F5: 모델을 들여다보게. 감독도 같이 멈춘다) · 숫자 0 = 표시 켜고 끔.
## 배포물(release)에는 없다 — _ready 에서 자기를 지운다. 봇 --check 가 이를 잰다. 판정(무서운가)을 볼 땐 0 으로 끄고 본다.

const POS := Vector2(12.0, 12.0)
const FONT_PX := 18
var _label: Label
var _player: Node
var _on := true


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)                                     # 지워지기 전 같은 프레임에 _process 가 돌면 _label 이 없다 (배포물 --check 가 여기서 죽었다)
		queue_free()
		return
	layer = 5
	_player = get_parent()
	_label = Label.new()
	_label.position = POS
	_label.add_theme_font_size_override("font_size", FONT_PX)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func _floor_of(asm: Node) -> MineAssembler.FloorData:
	for fd in asm.floors:
		if absf((_player as Node3D).global_position.y - fd.y) < Tuning.LIFT_DROP * 0.5:
			return fd
	return null


func _process(_delta: float) -> void:
	if _label == null:
		return
	if Input.is_action_just_pressed("debug_hud"):
		_on = not _on
		_label.visible = _on
	var asm := _player.get_parent().get_node_or_null("Layers")
	if asm == null or not "floors" in asm:
		_label.text = ""
		return
	var fd := _floor_of(asm)
	if fd == null or fd.director == null or fd.stalker == null:
		_label.text = ""
		return
	if Input.is_action_just_pressed("debug_spawn"):
		fd.director.pressure = Tuning.PRESSURE_SEND
	var st: Stalker = fd.stalker
	if Input.is_action_just_pressed("debug_freeze"):
		st.set_frozen(not st.frozen)
		fd.director.paused = st.frozen
	if not _on:
		return
	var text := "압박 %.0f · 괴물 %s%s" % [fd.director.pressure, st.state, " [정지]" if st.frozen else ""]
	if st.state != "hidden":
		var to: Vector3 = st.global_position - (_player as Node3D).global_position
		to.y = 0.0
		var fwd: Vector3 = -(_player as Node3D).global_transform.basis.z
		var ang: float = rad_to_deg(fwd.signed_angle_to(to.normalized(), Vector3.UP))   # + 왼쪽
		var side := ""
		if absf(ang) < 30.0:
			side = "앞"
		elif absf(ang) > 150.0:
			side = "뒤"
		else:
			side = ("왼쪽" if ang > 0.0 else "오른쪽") + (" 앞" if absf(ang) < 90.0 else " 뒤")
		text += " · %.0f m · %s (%.0f°)" % [to.length(), side, ang]
	var cards := []
	if fd.director.card_dark:
		cards.append("어둠 수색")
	if fd.director.card_cart:
		cards.append("광차 들여다보기")
	if not cards.is_empty():
		text += " [" + " · ".join(cards) + "]"
	_label.text = text
