extends CanvasLayer
## 수리 HUD (제안서 #30). Player.tscn 안 — 부모가 플레이어. Player.repair_target(Fault) 가 있을 때만 그린다.
## 아래 가운데 진행 바, 그 위 스킬체크 링(성공 구간 + 바늘). _draw 로만 그린다 — 새 UI 씬 없음.

const BAR_W := 320.0
const BAR_H := 14.0
const RING_R := 64.0
var _ctl: Control
var _player: Node


func _ready() -> void:
	_player = get_parent()
	_ctl = Control.new()
	_ctl.name = "Draw"
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctl.draw.connect(_on_draw)
	add_child(_ctl)


func _process(_delta: float) -> void:
	_ctl.queue_redraw()


func _on_draw() -> void:
	var fault: Node = _player.get("repair_target")
	if fault == null:
		return
	var size: Vector2 = _ctl.size
	var bar := Rect2(size.x * 0.5 - BAR_W * 0.5, size.y - 110.0, BAR_W, BAR_H)
	_ctl.draw_rect(bar, Color(0.05, 0.05, 0.05, 0.75))
	_ctl.draw_rect(Rect2(bar.position, Vector2(BAR_W * clampf(fault.progress, 0.0, 1.0), BAR_H)), Color(0.85, 0.75, 0.35))
	_ctl.draw_rect(bar, Color(0.9, 0.85, 0.7, 0.8), false, 1.0)
	if not fault.skill_active:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.5 + 90.0)
	_ctl.draw_arc(c, RING_R, 0.0, TAU, 64, Color(0.1, 0.1, 0.1, 0.8), 10.0)
	var a0: float = deg_to_rad(fault.zone_start) - PI * 0.5
	var a1: float = a0 + deg_to_rad(fault.zone_deg)
	_ctl.draw_arc(c, RING_R, a0, a1, 24, Color(0.95, 0.95, 0.95), 10.0)
	var an: float = deg_to_rad(fault.needle) - PI * 0.5
	_ctl.draw_line(c, c + Vector2(cos(an), sin(an)) * (RING_R + 8.0), Color(0.95, 0.2, 0.15), 3.0)
	_ctl.draw_circle(c, 4.0, Color(0.95, 0.2, 0.15))
