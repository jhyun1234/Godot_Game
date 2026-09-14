class_name Dust
extends GPUParticles3D

## 한 번 터지고 스스로 사라지는 먼지. OrePocket 과 Player 가 코드로 놓는다.
## 알 개수와 방향은 놓는 쪽이 정한다 — 평타 먼지와 파괴 먼지가 같은 씬을 쓴다.


static func burst(parent: Node, at: Vector3, facing: Vector3, count: int) -> void:
	var fx: GPUParticles3D = load("res://scenes/fx/Dust.tscn").instantiate()
	fx.amount = count
	parent.add_child(fx)
	fx.global_position = at
	# 먼지는 벽에서 플레이어 쪽으로 뿜어져 나온다.
	if facing.length_squared() > 0.001:
		fx.look_at(at + facing, Vector3.UP)
	fx.emitting = true


func _ready() -> void:
	finished.connect(queue_free)
