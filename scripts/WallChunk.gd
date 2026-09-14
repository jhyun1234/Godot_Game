class_name WallChunk
extends RigidBody3D

## 부서진 벽 조각 하나. MinableBlock 이 코드로 만들어 붙인다.
## 수치는 scripts/Tuning.gd.
##
## 조각은 장식이다 — 레이어 0, 마스크 1. 지형에는 떨어지지만 아무도 조각을
## 감지하지 않는다. 플레이어가 조각에 걸려 넘어지지 않고, 곡괭이도 안 맞는다.

## 살아있는 조각 전부. 상한을 넘으면 오래된 것부터 지운다.
## 벽을 연달아 부수면 조각이 무한히 쌓이는데, 수명(3초)만으로는 그 사이를 못 막는다.
static var _live: Array[WallChunk] = []

var _mesh: MeshInstance3D
var _life := 0.0


## life 를 안 주면 파괴 조각의 수명을 쓴다. 평타 자갈은 더 짧게 넘긴다.
static func spawn(parent: Node, mesh: Mesh, xform: Transform3D,
		impulse: Vector3, spin: Vector3, life: float = -1.0) -> WallChunk:
	var chunk := WallChunk.new()
	chunk.collision_layer = 0
	chunk.collision_mask = 1
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	chunk.add_child(mi)
	chunk._mesh = mi
	var col := CollisionShape3D.new()
	col.shape = _shape_for(mesh)
	chunk.add_child(col)
	parent.add_child(chunk)
	chunk.global_transform = xform
	chunk.linear_velocity = impulse
	chunk.angular_velocity = spin
	chunk._life = life if life > 0.0 else Tuning.CHUNK_LIFE
	chunk._register()
	return chunk


## 볼록 껍질은 메시마다 한 번만 만든다. 벽 하나에 조각이 열몇 개고,
## 같은 구역을 다시 부수면 같은 메시가 또 온다.
static var _shapes: Dictionary = {}

static func _shape_for(mesh: Mesh) -> Shape3D:
	var key := mesh.get_rid()
	if not _shapes.has(key):
		_shapes[key] = mesh.create_convex_shape()
	return _shapes[key]


func _register() -> void:
	_live.append(self)
	while _live.size() > Tuning.CHUNK_LIMIT:
		var old: WallChunk = _live.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	_fade_out()


func _fade_out() -> void:
	var tween := create_tween()
	tween.tween_interval(_life)
	tween.tween_property(_mesh, "scale", Vector3.ZERO, Tuning.CHUNK_FADE)
	tween.tween_callback(queue_free)


func _exit_tree() -> void:
	_live.erase(self)
