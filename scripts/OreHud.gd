extends CanvasLayer

## 지금까지 캔 광석 수. Player.tscn 안에 들어 있어서 부모가 곧 플레이어다 —
## 전역 싱글턴도, 노드 찾기도 필요 없다.

@onready var _label: Label = $Label


func _ready() -> void:
	var player := get_parent()
	if player.has_signal("ore_changed"):
		player.ore_changed.connect(_on_ore_changed)
		_on_ore_changed(player.ore_count)


func _on_ore_changed(count: int) -> void:
	_label.text = "철 %d" % count
