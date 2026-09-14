extends Node3D

## 광맥 포켓 배치 (#23 수정판 → #27 조립기). Tunnel/Pockets 에 붙는다. 수치는 scripts/Tuning.gd 의 POCKET_* 와 MAP_SEED.
##
## ../Layers(MineAssembler) 가 놓은 조각마다 들어 있는 빈 노드 SLOT_Pocket_* 를 전부 읽어
## POCKET_CHANCE 확률로 OrePocket 을 붙인다. 층에 하나도 안 켜지면 그 층 첫 자리를 강제로 켠다.
## 시드는 방 시드 하나(MAP_SEED + 100)라 두 번 띄워도 같은 자리다 — 봇·골든이 그걸 본다.
## 포켓마다 meta "out"(자리에서 조각 원점 쪽 = 통로 쪽 방향)과 "slot"(자리 노드)을 적는다 — 곡괭이 봇이 회전된 조각에서도 바른 쪽에 선다.
## Layers 가 Pockets 보다 위에 있어야 한다 (_ready 순서: 조각이 먼저 놓여야 자리를 읽는다).

const POCKET_SCENE := "res://scenes/level/OrePocket.tscn"


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Tuning.MAP_SEED + 100
	var packed := load(POCKET_SCENE) as PackedScene
	var layers := get_parent().get_node_or_null("Layers")
	if packed == null or layers == null:
		push_warning("PocketSpawner: OrePocket.tscn 또는 ../Layers 가 없다")
		return
	var floors := {}      # int -> Array[Node3D] (이 층의 자리, 트리 순서)
	var lit := {}         # int -> int (이 층에 켜진 수)
	for s in layers.find_children("SLOT_Pocket_*", "Node3D", true, false):
		var slot := s as Node3D
		var floor_id := roundi(slot.global_position.y / Tuning.LIFT_DROP)
		if not floors.has(floor_id):
			floors[floor_id] = []
			lit[floor_id] = 0
		floors[floor_id].append(slot)
		if rng.randf() < Tuning.POCKET_CHANCE:
			_place(packed, slot, rng)
			lit[floor_id] += 1
	for floor_id in floors:
		var slots: Array = floors[floor_id]
		var k := 0
		while lit[floor_id] < Tuning.POCKET_MIN_PER_FLOOR and k < slots.size():
			_place(packed, slots[k], rng)
			lit[floor_id] += 1
			k += 1


## 자리에서 통로 쪽으로 POCKET_WALL_OUT 만큼 내밀어 놓고 시드로 돌려 놓는다 — 같은 메시라도 같은 각으로 보이면 복제품이다. 통로 쪽 = 자리에서 조각 원점 쪽.
func _place(packed: PackedScene, slot: Node3D, rng: RandomNumberGenerator) -> void:
	var pocket := packed.instantiate() as Node3D
	pocket.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	var piece := slot.get_parent() as Node3D
	var out: Vector3 = piece.global_position - slot.global_position if piece != null else Vector3.ZERO
	out.y = 0.0
	pocket.set_meta("out", out.normalized())
	pocket.set_meta("slot", slot)
	add_child(pocket)
	pocket.global_position = slot.global_position + out.normalized() * Tuning.POCKET_WALL_OUT


## 검사용. 지금 살아 있는 포켓들.
func pockets() -> Array[OrePocket]:
	var out: Array[OrePocket] = []
	for c in get_children():
		if c is OrePocket:
			out.append(c)
	return out
