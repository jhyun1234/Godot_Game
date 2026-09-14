extends Node3D
## 부품 = 새 갱목 통나무 (제안서 #30). 자재함(PartsBin, #31)이 만든다. Reach 안에서 E → Player.pick_up.
## quality: "creaky"(광석 없이. 스킬체크 구간 좁고 잦음) / "good"(광석 ORE_PER_PART. 넓고 드묾). 고장이 세울 때 읽는다.

var carried := false
var quality := "creaky"
@onready var _reach: Area3D = $Reach


func _physics_process(_delta: float) -> void:
	if carried or not Input.is_action_just_pressed("interact"):
		return
	for b in _reach.get_overlapping_bodies():
		if b is CharacterBody3D and b.has_method("pick_up") and b.carry == null and b.ride == null and b.interact_claim():
			b.pick_up(self)
			break
