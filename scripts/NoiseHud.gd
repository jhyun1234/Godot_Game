extends CanvasLayer
## 소음 표시 (제안서 #32). Player.tscn 안 — 부모가 플레이어. 내가 낸 마지막 소음의 반경만큼 왼쪽 아래 원이 뜨고
## NOISE_HUD_FADE 동안 사라진다. 소리는 화면에 안 찍히므로 쇼츠는 이 원으로 보여준다. _draw 로만 그린다 — 새 UI 씬 없음.

const CENTER := Vector2(110.0, -110.0)     # 왼쪽 아래 기준 (DangerHud 는 오른쪽 아래)
var _ctl: Control
var _player: Node
var _radius := 0.0
var _left := 0.0


func _ready() -> void:
	_player = get_parent()
	_ctl = Control.new()
	_ctl.name = "Draw"
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctl.draw.connect(_on_draw)
	add_child(_ctl)
	NoiseBus.made.connect(_on_noise)


func _on_noise(_pos: Vector3, radius: float, _kind: String, who: Node) -> void:
	if who != _player:
		return
	_radius = radius
	_left = Tuning.NOISE_HUD_FADE


func _process(delta: float) -> void:
	if _left > 0.0:
		_left = maxf(_left - delta, 0.0)
		_ctl.queue_redraw()


func _on_draw() -> void:
	if _left <= 0.0:
		return
	var a: float = _left / Tuning.NOISE_HUD_FADE
	var c := Vector2(CENTER.x, _ctl.size.y + CENTER.y)
	var r: float = _radius * Tuning.NOISE_HUD_PX_PER_M * 0.5
	_ctl.draw_circle(c, r, Color(0.95, 0.85, 0.5, 0.18 * a))
	_ctl.draw_arc(c, r, 0.0, TAU, 48, Color(0.95, 0.85, 0.5, 0.9 * a), 2.0)
	_ctl.draw_circle(c, 3.0, Color(0.95, 0.85, 0.5, a))
