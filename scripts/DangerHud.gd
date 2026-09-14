extends CanvasLayer

## 위험 게이지 바. 오른쪽 아래. Player.tscn 안에 들어 있어서 부모가 곧 플레이어다 —
## OreHud 와 같은 구조. 값·색은 전부 Tuning 에서 온다.

@onready var _bar: ProgressBar = $Bar
var _fill := StyleBoxFlat.new()


func _ready() -> void:
	_bar.max_value = Tuning.DANGER_MAX
	_bar.add_theme_stylebox_override("fill", _fill)
	var player := get_parent()
	if player.has_signal("danger_changed"):
		player.danger_changed.connect(_on_danger_changed)
		_on_danger_changed(player.danger)


func _on_danger_changed(value: float) -> void:
	_bar.value = value
	# 0% 녹 -> 50% 노랑 -> 100% 빨강
	var t := value / Tuning.DANGER_MAX
	if t < 0.5:
		_fill.bg_color = Tuning.DANGER_COLOR_LOW.lerp(Tuning.DANGER_COLOR_MID, t * 2.0)
	else:
		_fill.bg_color = Tuning.DANGER_COLOR_MID.lerp(Tuning.DANGER_COLOR_HIGH, (t - 0.5) * 2.0)
