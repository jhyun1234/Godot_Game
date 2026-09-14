extends Node
## 소음 이벤트 (제안서 #32, 순서표 ⑥). 결정 함수 한 곳(CLAUDE.md 멀티 준비) — 곡괭이 타격(Miner)·정비 실패(Fault)·
## 발걸음(Player)·달리는 광차(MineCart)가 make() 로 알린다. 아직 듣는 괴물은 없다: NoiseHud 가 made 를 받아
## 원을 그리고, 봇과 ⑦ 괴물 감각은 log 를 본다. 반경 0 은 소음이 아니다 (안 남긴다).

signal made(pos: Vector3, radius: float, kind: String, who: Node)

const LOG_MAX := 512
var log: Array[Dictionary] = []      # {"pos", "radius", "kind", "who", "frame"} 오래된 순
var total := 0                       # 지금까지 낸 수. 봇이 구간을 자를 때 쓴다 (log 는 잘려 나간다)


func make(pos: Vector3, radius: float, kind: String, who: Node = null) -> void:
	if radius <= 0.0:
		return
	total += 1
	log.append({"pos": pos, "radius": radius, "kind": kind, "who": who, "frame": Engine.get_physics_frames()})
	if log.size() > LOG_MAX:
		log.pop_front()
	made.emit(pos, radius, kind, who)


## total 이 t0 이던 때부터 지금까지 낸 소음
func since(t0: int) -> Array[Dictionary]:
	var n: int = mini(total - t0, log.size())
	if n <= 0:
		return []
	return log.slice(log.size() - n)
