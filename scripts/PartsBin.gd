extends Node3D
## 자재함 (제안서 #31). 층마다 하나, 정거장 앞 첫 직선 오른쪽 벽. Reach 안에서 E →
##   광석 ≥ ORE_PER_PART 면 광석을 빼고 좋은 부품(밝은 통나무, 스킬체크 구간 넓고 드묾), 아니면 삐걱 부품.
## 부품은 자재함 앞 BIN_DROP 바닥에 놓인다. 앞의 부품을 아직 안 들었으면 새로 안 만든다. 부품은 무한 — 품질만 갈린다 (#24).

var parts: Array = []            # 만든 부품 (봇용)
var mat_creaky: Material
var mat_good: Material
var _last: Node3D = null
@onready var _reach: Area3D = $Reach


func _physics_process(_delta: float) -> void:
	if not Input.is_action_just_pressed("interact"):
		return
	for b in _reach.get_overlapping_bodies():
		if b is CharacterBody3D and b.has_method("add_ore") and b.carry == null and b.ride == null and b.interact_claim():
			make_part(b)
			break


func can_make() -> bool:
	return _last == null or not is_instance_valid(_last) or _last.carried or _last.global_position.distance_to(_drop_pos()) > 1.0


func _drop_pos() -> Vector3:
	return global_position + (-global_transform.basis.x) * Tuning.BIN_DROP


func make_part(player: CharacterBody3D) -> Node3D:
	if not can_make():
		return null
	var good: bool = player.ore_count >= Tuning.ORE_PER_PART
	if good:
		player.add_ore(-Tuning.ORE_PER_PART)
	var part := Node3D.new()
	part.name = "Part_%d" % parts.size()
	var mi := MeshInstance3D.new()
	mi.name = "Log"
	var mesh := BoxMesh.new()
	mesh.size = Tuning.PART_SIZE
	mesh.material = mat_good if good else mat_creaky
	mi.mesh = mesh
	mi.visibility_range_end = Tuning.PIECE_VIEW_RANGE
	part.add_child(mi)
	var reach := Area3D.new()
	reach.name = "Reach"
	reach.collision_layer = 0
	reach.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = Tuning.CARRY_REACH
	cs.shape = sph
	reach.add_child(cs)
	part.add_child(reach)
	part.set_script(load("res://scripts/RepairPart.gd"))
	get_parent().get_node("Parts").add_child(part)
	part.quality = "good" if good else "creaky"
	part.global_position = _drop_pos() + Vector3(0.0, Tuning.PART_SIZE.y * 0.5, 0.0)
	part.global_rotation = Vector3(0.0, global_rotation.y, 0.0)
	parts.append(part)
	_last = part
	return part
