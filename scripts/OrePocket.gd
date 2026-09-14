class_name OrePocket
extends StaticBody3D

## 갱도 옆벽에 반쯤 박힌 광석 덩이 — 광맥 포켓 (#23 수정판, #24 규칙 "광석은 재화"). 수치는 전부 scripts/Tuning.gd.
##
## 곡괭이로 두 번 친다. 첫 타에 밀렸다 돌아오며 자갈이 튀고, 둘째 타에 덩이가 벽에서
## 빠져나와 통로 쪽으로 구른다(Ore). 채굴 벽(막장 부수기)은 없다 — 막장은 못 캐는 끝막이다.
## 자리는 PocketSpawner 가 시드로 정한다. 이 스크립트는 자기 한 자리만 안다.

signal broken(pocket: OrePocket)

## 평타 자갈 4종. 끝막이 벽에서 잘라낸 것 (tools/minetunnel/build_face.py). 붕괴 돌(Player)도 같은 것을 쓴다.
const CHIPS_PATH := "res://assets/generated/tunnel/mine_chips.gltf"

@onready var _mesh: Node3D = $Mesh

var _health := Tuning.POCKET_HEALTH
var _rest := Vector3.ZERO
var _breaking := false


func _ready() -> void:
	_rest = _mesh.position


func is_breaking() -> bool:
	return _breaking


## hit_dir 은 때린 쪽에서 포켓을 향하는 방향(전역).
## hit_point 는 곡괭이가 닿은 지점(전역).
func take_hit(damage: float, hit_dir: Vector3, hit_point: Vector3) -> void:
	if _breaking:
		return
	_health -= damage
	if _health <= 0.0:
		_pop(hit_dir)
		return
	Dust.burst(get_parent(), hit_point, -hit_dir, Tuning.HIT_DUST)
	_spawn_chips(get_parent(), hit_point, -hit_dir)
	var local_dir := (global_transform.basis.inverse() * hit_dir).normalized()
	var tween := create_tween()
	tween.tween_property(_mesh, "position", _rest + local_dir * Tuning.HIT_RECOIL,
		Tuning.HIT_RECOIL_TIME * 0.4)
	tween.tween_property(_mesh, "position", _rest, Tuning.HIT_RECOIL_TIME * 0.6)


## 평타에 튀는 자갈. 조각 강체(WallChunk)를 짧은 수명으로 쓴다.
func _spawn_chips(parent: Node, hit_point: Vector3, out: Vector3) -> void:
	var packed := load(CHIPS_PATH) as PackedScene
	if packed == null:
		return
	var set_root := packed.instantiate()
	var meshes: Array[Mesh] = []
	for child in set_root.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			meshes.append(mi.mesh)
	if not meshes.is_empty():
		for i in Tuning.CHIP_PER_HIT:
			var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0),
				randf_range(-1.0, 1.0)).normalized()
			var pop := (out + spread * 0.7).normalized() * Tuning.CHIP_POP
			var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * Tuning.CHUNK_SPIN
			WallChunk.spawn(parent, meshes[randi() % meshes.size()],
				Transform3D(Basis.IDENTITY, hit_point + out * 0.1), pop, spin,
				Tuning.CHIP_LIFE)
	set_root.queue_free()


## 덩이가 벽에서 빠져나온다. 통로 쪽(때린 사람 쪽)으로 튀고, 위로 떠서 바닥에 구른다.
func _pop(hit_dir: Vector3) -> void:
	_breaking = true
	# 광석이 생기기 전에 판정부터 뺀다. 안 그러면 레이가 사라지는 포켓을 또 맞춘다.
	collision_layer = 0
	broken.emit(self)
	var parent := get_parent()
	var out := Vector3(-hit_dir.x, 0.0, -hit_dir.z).normalized()
	if out.is_zero_approx():
		out = -global_transform.basis.z
	Dust.burst(parent, global_position, out, Tuning.BREAK_DUST)
	var side := out.cross(Vector3.UP) * randf_range(-1.0, 1.0) * Tuning.ORE_POP_SIDE
	var pop := out * Tuning.POCKET_POP_OUT + side + Vector3.UP * Tuning.ORE_POP_UP
	Ore.spawn(parent, global_position + out * 0.3, pop)
	queue_free()
