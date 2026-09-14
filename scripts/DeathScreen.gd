extends CanvasLayer

## 무너졌을 때 덮이는 검은 화면과 글자. Player.tscn 안에 있어서 부모가 곧 플레이어다.
## 다른 HUD(layer 1)보다 위(layer 10)라 게이지·철 카운터도 같이 덮인다.

@onready var _label: Label = $Black/Label


func _ready() -> void:
	visible = false
	_label.text = Tuning.DEATH_TEXT
	var player := get_parent()
	if player.has_signal("died"):
		player.died.connect(_on_died)


func _on_died() -> void:
	var player := get_parent()
	if "death_text" in player:
		_label.text = player.death_text                    # 붕괴 / 잡힘 (#35)
	await get_tree().create_timer(Tuning.DEATH_BLACK_TIME).timeout
	$Black.modulate.a = 0.0
	visible = true
	create_tween().tween_property($Black, "modulate:a", 1.0, Tuning.DEATH_BLACK_FADE)
