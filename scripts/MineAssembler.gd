class_name MineAssembler
extends Node3D

## 층 조립기 (제안서 #27). Tunnel/Layers 에 붙는다. 프로토타입 `Opus5_채굴게임/Claude outputs/조립기_프로토타입_v6.py` 의 문법을 옮긴 것.
##
## 층마다 (시드 = Tuning.MAP_SEED + 층 번호) 35×35 칸 격자에
##   ① 광차 순환선(레일 고리, 모퉁이 5 + 흔들림) ② 지선 2~4·종점 ③ 횡갱(가지의 가지, 뿌리에서 멀수록 갈림 ↓)
##   ④ 다른 갱도에 닿으면 고리 ⑤ 채탄구역(방기둥 격자) ⑥ 막다른 끝의 70% = 목 + 방 ⑦ 대피소(옆 칸 바위 예약)
## 를 짜서 "칸 → 뚫린 면 4비트 + 종류 + 레일" 표를 만들고, 표를 PieceCatalog 의 조각으로 바꿔 놓는다.
## 조각은 gltf 인스턴스를 칸 가운데 바닥에 두고 rotation.y 만 돌린다 — 충돌·포켓 자리(SLOT_Pocket_*)는 조각 안에 있다.
## 프로토타입과 다른 점 7가지는 제안서 #27 표. 수치는 전부 scripts/Tuning.gd (MAP_*, RING_*, BRANCH*, PROP_*).
##
## 좌표: 칸 (cx, cy) 가운데 = ((cx − SX) × 7, 층 y, (cy − (N−3)) × 7 − 3.5). 입구 칸 (SX, N−3) = (0, −3.5). 정거장 = (SX, N−2)·(SX, N−1).
## 면 비트: N(−Z) 1 · E(+X) 2 · S(+Z) 4 · W(−X) 8.  회전 r(0~3) = rotation.y = r × 90°: 조각의 면 f 는 세계의 (f − r) mod 4 로 간다 (+90° 는 E → N).
##
## 봇이 읽는 것: floors[i] (FloorData), pieces_of(i, 이름), cell_world(), cell_of(), layout_hash(i), build_ms.

const N_IDX := 0
const E_IDX := 1
const S_IDX := 2
const W_IDX := 3
const DIR_VEC: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const DIR_NAME: Array[String] = ["N", "E", "S", "W"]
const ALL := 15
const PROPS_PATH := PieceCatalog.DIR + PieceCatalog.PROPS_GLTF
## 여기 종류의 칸에는 가지·고리·채탄구역 문을 안 붙인다 (정거장 앞 직선은 곧아야 하고, 종점·방·끝막이는 막다른 끝이다)
const NO_ATTACH: Array[String] = ["station", "entry", "stub", "term", "room", "neck", "cap"]


class FloorData:
	extends RefCounted
	var index := 0
	var seed := 0
	var y := 0.0
	var open := {}         # Vector2i -> int (뚫린 면 비트)
	var kind := {}         # Vector2i -> String (station·entry·stub·term·block·pillar·room·neck·cap·refuge·rock·pump·timber)
	var rail := {}         # Vector2i -> true
	var station: Array[Vector2i] = []
	var entry := Vector2i.ZERO
	var stub_end := Vector2i.ZERO
	var pieces := {}       # Vector2i -> {name, r, node} (조각을 든 칸. 2×2 방은 문 칸)
	var cover := {}        # Vector2i -> Vector2i (2×2 방의 나머지 칸 → 문 칸)
	var rails := {}        # Vector2i -> Array[{name, r, node}]
	var props: Array[Node3D] = []
	var clusters: Array = []   # {cell, center(Floor 로컬), members: Array[Node3D]} — 소품 무더기 (#27 수정). 봇이 램프 원뿔 안인지 잰다
	var seams: Array = []      # {cell, face, kind: "A"|"D", pos(Floor 로컬), r} — 뚫린 면끼리 맞닿는 이음새 (#27 수정 2). 칼라가 하나씩 선다
	var services: Array = []   # {cell, side: "L"|"R", variant, node} — 직선 칸의 설비 묶음 (#28). 봇이 수·자리·삼각형을 잰다
	var ring: Array[Vector2i] = []   # 순환선 칸 순서 (#29). 첫 = 끝 = stub_end. 광차 길
	var ring_recording := false
	var carts: Array = []      # PathFollow3D (MineCart.gd) (#29)
	var faults: Array = []     # Fault (#30) — timber 칸
	var bin: Node3D            # PartsBin (#31) — 정거장 앞 자재함. 부품은 bin.parts
	var stalker: Node3D        # Stalker (#35) — 층의 괴물 한 마리. 처음엔 숨김, Director 가 내려놓는다
	var director: Node         # Director (#35) — 압박·카드
	var rail_path: Path3D
	var stats := {}
	var root: Node3D


var floors: Array[FloorData] = []
var build_ms := 0
var _scenes := {}          # 경로 -> PackedScene


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	for i in Tuning.MAP_FLOORS:
		var fd := build_layout(Tuning.MAP_SEED + i, i)
		_place(fd)
		floors.append(fd)
	build_ms = Time.get_ticks_msec() - t0
	print("ok 층 %d개 조립 %d ms (칸 %s)" % [floors.size(), build_ms, floors.map(func(f): return f.stats["cells"])])


# ---------------- 좌표 ----------------

static func sx() -> int:
	return Tuning.MAP_N / 2 - 1


static func cell_world(c: Vector2i, y: float = 0.0) -> Vector3:
	var g: float = Tuning.GRID_CELL
	return Vector3((c.x - sx()) * g, y, (c.y - (Tuning.MAP_N - 3)) * g - g * 0.5)


static func cell_of(p: Vector3) -> Vector2i:
	var g: float = Tuning.GRID_CELL
	return Vector2i(int(floor(p.x / g + 0.5)) + sx(), int(floor((p.z + g) / g)) + Tuning.MAP_N - 3)


## 조각의 면 비트(로컬)를 r 만큼 돌린 것. 로컬 면 f 는 세계 (f − r) mod 4.
static func rotate_mask(mask: int, r: int) -> int:
	var out := 0
	for f in 4:
		if mask & (1 << f):
			out |= 1 << ((f - r + 4) % 4)
	return out


## 칸 오프셋을 r 만큼 돌린 것 (E (1,0) → N (0,−1)).
static func rotate_cell(d: Vector2i, r: int) -> Vector2i:
	var v := d
	for k in r:
		v = Vector2i(v.y, -v.x)
	return v


static func faces_mask(faces: Dictionary) -> int:
	var m := 0
	for f in 4:
		if faces[DIR_NAME[f]] != PieceCatalog.CLOSED:
			m |= 1 << f
	return m


static func _bits(mask: int) -> int:
	var n := 0
	for f in 4:
		if mask & (1 << f):
			n += 1
	return n


# ---------------- 문법 (프로토타입 v6) ----------------

func build_layout(seed: int, index: int) -> FloorData:
	var fd := FloorData.new()
	fd.index = index
	fd.seed = seed
	fd.y = -Tuning.LIFT_DROP * index
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n: int = Tuning.MAP_N
	var s := sx()
	fd.station = [Vector2i(s, n - 2), Vector2i(s, n - 1)]
	for c in fd.station:
		fd.kind[c] = "station"
	fd.entry = Vector2i(s, n - 3)
	fd.open[fd.entry] = 1 << S_IDX
	fd.rail[fd.entry] = true
	fd.kind[fd.entry] = "entry"
	# 정거장 앞 직선 (프로토타입과 다른 점 2): 입구 + ENTRY_STRAIGHT 칸. 마지막 칸(stub_end)에서 순환선이 갈라진다 — 입구부터 ENTRY_STRAIGHT 칸이 곧다
	var cur := fd.entry
	for k in Tuning.ENTRY_STRAIGHT:
		var nx := cur + DIR_VEC[N_IDX]
		_carve(fd, cur, nx, N_IDX)
		fd.rail[nx] = true
		fd.kind[nx] = "stub"
		cur = nx
	fd.stub_end = cur
	var loops := [0]
	var blocks_placed := 0

	# 1. 광차 순환선: 모퉁이 5 + 중간점 2개씩 흔들어 구불구불 한 바퀴. 직각 구간을 잇되 방향이 바뀌는 칸은 곡선 조각이 된다.
	var m: int = Tuning.RING_MARGIN
	var ring: Array[Vector2i] = [fd.stub_end,
		Vector2i(n - m + _j(rng, 2), n - 8 + _j(rng, 3)), Vector2i(n - m - 3 + _j(rng, 3), m + _j(rng, 2)),
		Vector2i(s + _j(rng, 4), m - 1 + _j(rng, 1)), Vector2i(m + 3 + _j(rng, 3), m + _j(rng, 2)),
		Vector2i(m + _j(rng, 2), n - 8 + _j(rng, 3)), fd.stub_end]
	for i in range(1, ring.size() - 1):
		ring[i] = Vector2i(clampi(ring[i].x, 0, n - 1), clampi(ring[i].y, 0, n - 4 - Tuning.ENTRY_STRAIGHT))   # 정거장 앞 직선 줄은 안 지난다
	var pts: Array[Vector2i] = [ring[0]]
	for k in range(1, ring.size()):
		var a := ring[k - 1]
		var b := ring[k]
		for t in [0.33, 0.66]:
			var mx: float = a.x + (b.x - a.x) * t
			var my: float = a.y + (b.y - a.y) * t
			if absi(b.x - a.x) >= absi(b.y - a.y):
				my += _j(rng, Tuning.RING_WOBBLE)
			else:
				mx += _j(rng, Tuning.RING_WOBBLE)
			pts.append(Vector2i(clampi(roundi(mx), 1, n - 2), clampi(roundi(my), 1, n - 4 - Tuning.ENTRY_STRAIGHT)))
		pts.append(b)
	cur = fd.stub_end
	fd.ring = [fd.stub_end]
	fd.ring_recording = true
	for k in range(1, pts.size()):
		cur = _carve_path(fd, cur, pts[k], true, rng.randf() < 0.5)
	fd.ring_recording = false
	_strip_spurs(fd.ring)
	var ring_cells: Array = fd.rail.keys()
	# 지선: 순환선에서 구석으로. 끝은 종점 (광차 대기). 종점은 레일 막다른 끝 = 끝막이 + 버퍼 (다른 점 3)
	for _i in rng.randi_range(Tuning.SPURS_MIN, Tuning.SPURS_MAX):
		var c: Vector2i = ring_cells[rng.randi() % ring_cells.size()]
		if fd.kind.get(c, "") in ["entry", "stub"]:
			continue
		var dirs: Array = []
		for f in 4:
			if not (fd.open[c] & (1 << f)):
				dirs.append(f)
		_shuffle(rng, dirs)
		for f in dirs:
			var nx: Vector2i = c + DIR_VEC[f]
			if _free(fd, nx):
				_carve(fd, c, nx, f)
				fd.rail[nx] = true
				var res: Array = _walk(fd, rng, nx, f, rng.randi_range(Tuning.SPUR_LEN_MIN, Tuning.SPUR_LEN_MAX), true, Tuning.SPUR_TURN_P, false, loops)
				var path: Array = res[0]
				fd.kind[path[path.size() - 1]] = "term"
				break

	# 2. 가지 (깊이 BRANCH_DEPTH 까지). 뿌리에서 멀수록 갈림 확률 ↓ (개미집: 가지는 뿌리 가까이)
	var frontier: Array = []
	for c in fd.rail:
		if not (fd.kind.get(c, "") in NO_ATTACH):
			frontier.append([c, 0])
	var made := 0
	var tries := 0
	while made < Tuning.BRANCHES and tries < 1500:
		tries += 1
		var e: Array = frontier[rng.randi() % frontier.size()]
		var c: Vector2i = e[0]
		var depth: int = e[1]
		if depth >= Tuning.BRANCH_DEPTH:
			continue
		var far: int = absi(c.y - (n - 3)) + absi(c.x - s)
		if rng.randf() < far / Tuning.FAR_DIV:
			continue
		var closed: Array = []
		for f in 4:
			if not (fd.open[c] & (1 << f)):
				closed.append(f)
		if closed.is_empty():
			continue
		var d: int = closed[rng.randi() % closed.size()]
		var nx: Vector2i = c + DIR_VEC[d]
		if not _free(fd, nx):
			continue
		_carve(fd, c, nx, d)
		var res: Array = _walk(fd, rng, nx, d, rng.randi_range(Tuning.BRANCH_LEN_MIN, Tuning.BRANCH_LEN_MAX), false, Tuning.TURN_P, true, loops)
		for p in res[0]:
			frontier.append([p, depth + 1])
		made += 1

	# 3. 방기둥 채탄구역: 3×3~5×5 를 빈 자리에 놓고 갱도와 이웃한 칸 하나로 문을 낸다. 안에 고리, 기둥은 바위(조각 없음)
	for _b in Tuning.BLOCKS:
		for _t in 200:
			var w: int = [3, 5][rng.randi() % 2]
			var h: int = [3, 5][rng.randi() % 2]
			var x0 := rng.randi_range(0, n - w)
			var y0 := rng.randi_range(0, n - h)
			var cells: Array[Vector2i] = []
			for i in w:
				for j in h:
					cells.append(Vector2i(x0 + i, y0 + j))
			var ok := true
			for c in cells:
				if not _free(fd, c):
					ok = false
					break
			if not ok:
				continue
			var door: Array = []
			for c in cells:
				if (c.x - x0) % 2 == 1 and (c.y - y0) % 2 == 1:
					continue
				for f in 4:
					var nb: Vector2i = c + DIR_VEC[f]
					if fd.open.has(nb) and not (fd.kind.get(nb, "") in NO_ATTACH):
						door = [c, nb, f]
						break
				if not door.is_empty():
					break
			if door.is_empty():
				continue
			for c in cells:
				if (c.x - x0) % 2 == 1 and (c.y - y0) % 2 == 1:
					fd.kind[c] = "pillar"
					continue
				fd.kind[c] = "block"
				if not fd.open.has(c):
					fd.open[c] = 0
				for f in [E_IDX, S_IDX]:
					var nb: Vector2i = c + DIR_VEC[f]
					if cells.has(nb) and not ((nb.x - x0) % 2 == 1 and (nb.y - y0) % 2 == 1):
						_carve(fd, c, nb, f)
			_carve(fd, door[0], door[1], door[2])
			loops[0] += (w / 2) * (h / 2)
			blocks_placed += 1
			break

	# 4. 막다른 끝: 목 + 방(2×2, 안 되면 1×1) / 끝막이. 레일 막다른 끝은 항상 끝막이(종점).
	for c in fd.open.keys():
		if _bits(fd.open[c]) != 1 or c == fd.entry or fd.kind.get(c, "") in ["block", "station"]:
			continue
		if fd.rail.has(c):
			fd.kind[c] = "term"
			continue
		var d: int = (_first_bit(fd.open[c]) + 2) % 4
		var placed := false
		if rng.randf() < Tuning.ROOM_P:
			var nx: Vector2i = c + DIR_VEC[d]
			var r: int = (4 - d) % 4
			for size in [2, 1]:
				var rc: Array[Vector2i] = _room_cells(nx, r, size)
				var ok := true
				for x in rc:
					if not _free(fd, x):
						ok = false
						break
				if not ok:
					continue
				for x in rc:
					fd.kind[x] = "room"
				fd.kind[c] = "neck"
				fd.open[c] |= 1 << d
				fd.open[nx] = 1 << ((d + 2) % 4)
				fd.cover.erase(nx)
				for x in rc:
					if x != nx:
						fd.cover[x] = nx
				placed = true
				break
		if not placed:
			fd.kind[c] = "cap"

	# 5. 설비: 직선 무레일 칸에 끼운다. 대피소는 옆 칸(조각 로컬 E)이 비어 있어야 하고 그 칸을 바위로 예약한다 (다른 점 5).
	#    펌프장·갱목 구간은 종류만 적는다 — 조각은 ⑧ 정비 때 (다른 점 6).
	var straights: Array = []
	for c in fd.open:
		if not fd.rail.has(c) and not fd.kind.has(c) and (fd.open[c] == 5 or fd.open[c] == 10):
			straights.append(c)
	_shuffle(rng, straights)
	var refuges := 0
	var slots: Array[String] = ["pump", "timber", "timber", "timber", "timber"]
	for c in straights:
		if refuges < Tuning.REFUGES:
			var r0: int = 0 if fd.open[c] == 5 else 1
			for r in [r0, r0 + 2]:
				var side: Vector2i = c + rotate_cell(Vector2i(1, 0), r)
				if _free(fd, side):
					fd.kind[c] = "refuge"
					fd.kind[side] = "rock"
					fd.pieces[c] = {"name": "refuge", "r": r}
					refuges += 1
					break
			if fd.kind.get(c, "") == "refuge":
				continue
		if not slots.is_empty():
			fd.kind[c] = slots.pop_front()
	fd.stats = _stats(fd, loops[0])
	fd.stats["blocks"] = blocks_placed
	fd.stats["refuges"] = refuges
	return fd


func _j(rng: RandomNumberGenerator, k: int) -> int:
	return rng.randi_range(-k, k)


func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _first_bit(mask: int) -> int:
	for f in 4:
		if mask & (1 << f):
			return f
	return -1


func _free(fd: FloorData, c: Vector2i) -> bool:
	return c.x >= 0 and c.x < Tuning.MAP_N and c.y >= 0 and c.y < Tuning.MAP_N and not fd.open.has(c) and not fd.kind.has(c)


func _carve(fd: FloorData, a: Vector2i, b: Vector2i, d: int) -> void:
	fd.open[a] = fd.open.get(a, 0) | (1 << d)
	fd.open[b] = fd.open.get(b, 0) | (1 << ((d + 2) % 4))


## 시작 칸에서 heading 쪽으로 length 칸 걷는다. 꺾일 확률 turn_p. 이미 있는 갱도에 닿으면(allow_loop) 확률로 이어 붙인다 = 고리.
## 돌려주는 것: [지나간 칸들, 고리를 만들었나]
func _walk(fd: FloorData, rng: RandomNumberGenerator, start: Vector2i, heading: int, length: int, is_rail: bool, turn_p: float, allow_loop: bool, loops: Array) -> Array:
	var cur := start
	var h := heading
	var path: Array[Vector2i] = [start]
	for _i in length:
		var cands: Array = [h]
		if rng.randf() < turn_p:
			cands.append((h + 3) % 4)
			cands.append((h + 1) % 4)
		if cands.size() > 1:
			_shuffle(rng, cands)
		if rng.randf() < turn_p:
			cands = [(h + 3) % 4, (h + 1) % 4, h]
			_shuffle(rng, cands)
		var moved := false
		for d in cands:
			var nx: Vector2i = cur + DIR_VEC[d]
			if _free(fd, nx):
				_carve(fd, cur, nx, d)
				cur = nx
				h = d
				path.append(cur)
				moved = true
				if is_rail:
					fd.rail[cur] = true
				break
			if allow_loop and fd.open.has(nx) and not (fd.open[cur] & (1 << d)) and loops[0] < Tuning.LOOPS_MAX \
					and not (fd.kind.get(nx, "") in NO_ATTACH) and rng.randf() < Tuning.LOOP_P:
				_carve(fd, cur, nx, d)
				loops[0] += 1
				return [path, true]
		if not moved:
			break
	return [path, false]


## a 에서 b 까지 직각 두 구간으로 판다 (순환선). 정거장·정거장 앞 직선·격자 밖에 닿으면 거기서 멈춘다.
func _carve_path(fd: FloorData, a: Vector2i, b: Vector2i, is_rail: bool, xy_first: bool) -> Vector2i:
	var cur := a
	var legs: Array = [[0, b.x], [1, b.y]] if xy_first else [[1, b.y], [0, b.x]]
	for leg in legs:
		var axis: int = leg[0]
		var target: int = leg[1]
		while (cur.x if axis == 0 else cur.y) != target:
			var d: int
			if axis == 0:
				d = E_IDX if target > cur.x else W_IDX
			else:
				d = S_IDX if target > cur.y else N_IDX
			var nx: Vector2i = cur + DIR_VEC[d]
			if nx.x < 0 or nx.x >= Tuning.MAP_N or nx.y < 0 or nx.y >= Tuning.MAP_N:
				return cur
			if fd.kind.get(nx, "") in ["station", "entry", "stub"] and nx != b:
				return cur
			_carve(fd, cur, nx, d)
			cur = nx
			if is_rail:
				fd.rail[cur] = true
			if fd.ring_recording:
				fd.ring.append(cur)
	return cur


## 방의 칸들. door = 문 칸(목 바로 앞), r = 방 조각 회전. 2×2 는 문 칸이 로컬 남서 칸: 로컬 E·N·NE 를 r 만큼 돌려 붙인다.
static func _room_cells(door: Vector2i, r: int, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [door]
	if size == 2:
		for off in [Vector2i(1, 0), Vector2i(0, -1), Vector2i(1, -1)]:
			out.append(door + rotate_cell(off, r))
	return out


func _stats(fd: FloorData, loops: int) -> Dictionary:
	var cells: Array = fd.open.keys()
	var e := 0
	var curves := 0
	var junc := 0
	var dead := 0
	var terms := 0
	var necks := 0
	var caps := 0
	var pillars := 0
	var open_holes := 0
	for c in cells:
		var mask: int = fd.open[c]
		var b := _bits(mask)
		e += b
		if b == 2 and mask != 5 and mask != 10:
			curves += 1
		if b >= 3:
			junc += 1
		if b == 1 and c != fd.entry:
			dead += 1
		for f in 4:
			if not (mask & (1 << f)):
				continue
			var nb: Vector2i = c + DIR_VEC[f]
			if fd.station.has(nb):
				continue
			if not fd.open.has(nb) or not (fd.open[nb] & (1 << ((f + 2) % 4))):
				open_holes += 1
	for c in fd.kind:
		match fd.kind[c]:
			"term": terms += 1
			"neck": necks += 1
			"cap": caps += 1
			"pillar": pillars += 1
	e /= 2
	# 정거장에서 닿는 칸 (BFS)
	var dist := {fd.entry: 0}
	var q: Array[Vector2i] = [fd.entry]
	var far := 0
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for f in 4:
			if fd.open[c] & (1 << f):
				var nb: Vector2i = c + DIR_VEC[f]
				if fd.open.has(nb) and not dist.has(nb):
					dist[nb] = dist[c] + 1
					far = maxi(far, dist[nb])
					q.append(nb)
	# 레일 고리: 레일 칸끼리의 변
	var re := 0
	for c in fd.rail:
		for f in 4:
			if (fd.open[c] & (1 << f)) and fd.rail.has(c + DIR_VEC[f]):
				re += 1
	re /= 2
	return {"cells": cells.size(), "edges": e, "loops": e - cells.size() + 1, "block_loops": loops, "dead": dead, "junctions": junc,
		"curves": curves, "rooms": necks, "caps": caps, "terms": terms, "pillars": pillars, "rail": fd.rail.size(),
		"rail_loops": re - fd.rail.size() + 1, "far_m": far * Tuning.GRID_CELL, "reach": dist.size() == cells.size(), "open_holes": open_holes}


# ---------------- 표 → 조각 ----------------

func _packed(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _place(fd: FloorData) -> void:
	var root := Node3D.new()
	root.name = "Floor_%d" % fd.index
	root.position.y = fd.y
	add_child(root)
	fd.root = root
	# 1. 갱도 조각
	for c in fd.open.keys():
		if fd.cover.has(c) or fd.station.has(c):
			continue
		var mask: int = fd.open[c]
		var k: String = fd.kind.get(c, "")
		var name := ""
		var r := -1
		if fd.pieces.has(c):                       # 대피소는 5 단계에서 정해졌다
			name = fd.pieces[c]["name"]
			r = fd.pieces[c]["r"]
		elif k == "neck":
			name = "neck"
			r = (4 - _room_dir(fd, c)) % 4
		elif k == "room":
			var size: int = 2 if _covered_by(fd, c) == 4 else 1
			name = "room_2" if size == 2 else "room_1"
			r = (4 - (_first_bit(mask) + 2) % 4) % 4   # 문 면(로컬 S)이 목 쪽을 본다
		else:
			match _bits(mask):
				1: name = "cap"
				2: name = "straight" if (mask == 5 or mask == 10) else "curve"
				3: name = "t"
				4: name = "cross"
			r = _find_rot(faces_mask(PieceCatalog.PIECES[name]["faces"]), mask)
		if name.is_empty() or r < 0:
			push_error("MineAssembler: 칸 %s 면 %d 종류 %s 에 맞는 조각이 없다" % [c, mask, k])
			continue
		var at := cell_world(c)
		if name == "room_2":
			var g: float = Tuning.GRID_CELL * 0.5
			var off := Vector3(g, 0.0, -g)
			at += Basis(Vector3.UP, r * PI * 0.5) * off
		var node := _spawn(root, PieceCatalog.piece_path(name), "P_%d_%d_%s" % [c.x, c.y, name], at, r)
		fd.pieces[c] = {"name": name, "r": r, "node": node}
	# 2. 레일 덧씌우기: 이웃(또는 정거장)도 레일인 면에만
	for c in fd.rail:
		var rm := 0
		for f in 4:
			if (fd.open[c] & (1 << f)):
				var nb: Vector2i = c + DIR_VEC[f]
				if fd.rail.has(nb) or fd.station.has(nb):
					rm |= 1 << f
		var lay: Array = []       # [이름, r]
		match _bits(rm):
			1: lay.append(["end", (2 - _first_bit(rm) + 4) % 4])
			2: lay.append(["straight" if (rm == 5 or rm == 10) else "curve", -1])
			3: lay.append(["turnout", -1])
			4:
				lay.append(["straight", 0])
				lay.append(["straight", 1])
		fd.rails[c] = []
		for l in lay:
			var name: String = l[0]
			var r: int = l[1]
			if r < 0:
				r = _find_rot(_rail_mask(name), rm)
			if r < 0:
				push_error("MineAssembler: 레일 칸 %s 면 %d 에 맞는 레일이 없다" % [c, rm])
				continue
			var node := _spawn(root, PieceCatalog.rail_path(name), "R_%d_%d_%s%s" % [c.x, c.y, name, "_b" if fd.rails[c].size() > 0 else ""], cell_world(c), r)
			fd.rails[c].append({"name": name, "r": r, "node": node})
	# 3. 소품 뿌리기
	_scatter_props(fd)
	# 4. 이음새 바위 칼라 + 크립 속 채우기 (#27 수정 2)
	_place_collars(fd)
	_fill_cribs(fd)
	# 5. 갱도 설비: 직선 칸마다 케이블·풍관·배관·배수로·갓등·라깅 (#28)
	_place_services(fd)
	# 6. 광차: 순환선 Path3D + CART_COUNT 대 (#29)
	_place_carts(fd)
	# 7. 정비 1: timber 칸의 고장 지지목 + 정거장 앞 부품 (#30)
	_place_faults(fd)
	_place_bin(fd)
	# 8. 괴물 + 감독 (#35). 몸은 #36 모델. 처음엔 숨김
	_place_stalker(fd)


func _room_dir(fd: FloorData, neck: Vector2i) -> int:
	for f in 4:
		if (fd.open[neck] & (1 << f)) and fd.kind.get(neck + DIR_VEC[f], "") == "room":
			return f
	return 0


func _covered_by(fd: FloorData, door: Vector2i) -> int:
	var n := 1
	for c in fd.cover:
		if fd.cover[c] == door:
			n += 1
	return n


static func _rail_mask(name: String) -> int:
	var m := 0
	for f in PieceCatalog.RAILS[name]["faces"]:
		m |= 1 << DIR_NAME.find(f)
	return m


static func _find_rot(local_mask: int, world_mask: int) -> int:
	for r in 4:
		if rotate_mask(local_mask, r) == world_mask:
			return r
	return -1


func _spawn(parent: Node3D, path: String, name: String, at: Vector3, r: int) -> Node3D:
	var node := _packed(path).instantiate() as Node3D
	node.name = name
	node.position = at
	node.rotation.y = r * PI * 0.5
	_set_view_range(node)
	parent.add_child(node)
	return node


## 40 m 밖 조각은 안 그린다 (Godot 내장 visibility range). 램프 14 m + 안개라 그 너머는 어차피 검다.
func _set_view_range(n: Node) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).visibility_range_end = Tuning.PIECE_VIEW_RANGE
	for c in n.get_children():
		_set_view_range(c)


## 소품 무더기 (#27 수정): 직선 칸 PROP_CLUSTER_P · 갈림 칸 PROP_JUNCTION_P · 끝막이 앞 PROP_CAP · 방 구석. 무더기 = 2~3개가 반지름 PROP_CLUSTER_R 안,
## 중심은 벽에서 PROP_WALL_GAP(1.4~2.2 m) — 복도 가운데서 램프 원뿔 안에 든다. 큰 것 위주(PROP_BIG_FRAC), 각도 무작위, 충돌 없음.
const PROP_BIG: Array[String] = ["PROP_crate", "PROP_crate_s", "PROP_barrels", "PROP_rubble", "PROP_post"]

func _scatter_props(fd: FloorData) -> void:
	var packed := _packed(PROPS_PATH)
	if packed == null:
		push_warning("MineAssembler: mine_props.gltf 가 없다")
		return
	var lib := packed.instantiate() as Node3D
	var big: Array[Node3D] = []
	var small: Array[Node3D] = []
	for c in lib.get_children():
		if c is Node3D and c.name.begins_with("PROP_"):
			if c.name in PROP_BIG:
				big.append(c)
			else:
				small.append(c)
	if big.size() + small.size() != PieceCatalog.PROPS.size():
		push_warning("MineAssembler: 소품 %d종 (표는 %d)" % [big.size() + small.size(), PieceCatalog.PROPS.size()])
	var holder := Node3D.new()
	holder.name = "Props"
	fd.root.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = fd.seed + 200
	var hw: float = Tuning.GRID_CELL * 0.5
	for c in fd.pieces:
		var p: Dictionary = fd.pieces[c]
		var node: Node3D = p["node"]
		var centers: Array[Vector3] = []          # 무더기 중심, 조각 로컬 (x, 0, z)
		match p["name"]:
			"straight":
				if rng.randf() < Tuning.PROP_CLUSTER_P:
					var side: float = 1.0 if rng.randf() < 0.5 else -1.0
					centers.append(Vector3(side * (hw - rng.randf_range(Tuning.PROP_WALL_GAP_MIN, Tuning.PROP_WALL_GAP_MAX)), 0.0, rng.randf_range(-2.0, 2.0)))
			"t", "cross":
				if rng.randf() < Tuning.PROP_JUNCTION_P:
					# 막힌 면 쪽 벽(T 는 로컬 W) 또는 모서리 크립 옆. 가운데 통로는 비운다
					var gx: float = -1.0 if p["name"] == "t" else (1.0 if rng.randf() < 0.5 else -1.0)
					centers.append(Vector3(gx * (hw - rng.randf_range(Tuning.PROP_WALL_GAP_MIN, Tuning.PROP_WALL_GAP_MAX)), 0.0, rng.randf_range(-1.0, 1.0)))
			"cap":
				for _i in Tuning.PROP_CAP:
					centers.append(Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.8, -1.0)))
			"room_2":
				var corners: Array[Vector3] = [Vector3(5.0, 0.0, 5.0), Vector3(5.0, 0.0, -5.0), Vector3(-5.0, 0.0, -5.0)]
				for i in mini(Tuning.PROP_ROOM_2, corners.size()):
					centers.append(corners[i] + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5)))
			"room_1":
				for _i in Tuning.PROP_ROOM_1:
					centers.append(Vector3(rng.randf_range(-1.8, 1.8), 0.0, rng.randf_range(-2.0, -1.0)))
		for lc in centers:
			var center: Vector3 = node.position + node.transform.basis * lc
			var members: Array = []
			var n: int = rng.randi_range(Tuning.PROP_CLUSTER_MIN, Tuning.PROP_CLUSTER_MAX)
			for k in n:
				var pool: Array[Node3D] = big if (rng.randf() < Tuning.PROP_BIG_FRAC or small.is_empty()) else small
				var kind: Node3D = pool[rng.randi() % pool.size()]
				var prop := kind.duplicate() as Node3D
				prop.name = "X_%d_%s" % [fd.props.size(), kind.name.substr(5)]
				var ang: float = rng.randf_range(0.0, TAU)
				var rad: float = rng.randf_range(0.0, Tuning.PROP_CLUSTER_R - 0.3) if k > 0 else 0.0
				prop.position = center + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
				prop.rotation.y = rng.randf_range(0.0, TAU)
				_set_view_range(prop)
				holder.add_child(prop)
				fd.props.append(prop)
				members.append(prop)
			fd.clusters.append({"cell": c, "center": center, "members": members})
	lib.free()


# ---------------- 봇이 읽는 것 ----------------

func pieces_of(floor_index: int, name: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var fd := floors[floor_index]
	for c in fd.pieces:
		if fd.pieces[c]["name"] == name and fd.pieces[c].has("node"):
			out.append(fd.pieces[c]["node"])
	return out


## 칸에 놓인 조각의 회전 r 로, 조각의 뚫린 면이 세계에서 어느 쪽인지 (예: 끝막이의 열린 면). 봇이 "3 m 앞"을 잡을 때 쓴다.
static func world_face(name: String, r: int, local_face: String) -> int:
	return (DIR_NAME.find(local_face) - r + 4) % 4


## 배치를 한 줄로 줄인 것. 같은 시드면 같아야 하고, 시드가 다르면 달라야 한다.
func layout_hash(floor_index: int) -> String:
	return hash_of(floors[floor_index])


static func hash_of(fd: FloorData) -> String:
	var keys: Array = fd.open.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var s := ""
	for c in keys:
		s += "%d,%d:%d%s%s;" % [c.x, c.y, fd.open[c], fd.kind.get(c, ""), "r" if fd.rail.has(c) else ""]
	return s.md5_text()


# ---------------- 이음새 칼라 (#27 수정 2) ----------------
## 갈림 조각은 모서리에 벽이 없고 이웃 벽 끝이 모서리를 이룬다. 그 벽 끝(두께 0 껍질)과 크립 사이 슬롯으로 벽 뒤 빈 공간이 검게 보였다.
## 이음새마다 아치 윤곽 바깥쪽 COLLAR_THICK 두께의 고리 안쪽 면을 앞뒤 COLLAR_DEPTH 로 세운다 — 어느 슬롯으로 봐도 바위. 바닥 아래 띠 포함.
## 메시 하나(A)·하나(D)를 만들어 공유, 재질은 직선 조각의 MAT_RockWall(젖은 셰이더로 이미 바뀐 것).

var _collar_mesh := {}      # "A"|"D" -> ArrayMesh


func _collect_seams(fd: FloorData) -> void:
	fd.seams.clear()
	for c in fd.open:
		for f in 4:
			if not (fd.open[c] & (1 << f)):
				continue
			var nb: Vector2i = c + DIR_VEC[f]
			var to_station: bool = fd.station.has(nb)
			if not to_station:
				if not fd.open.has(nb) or not (fd.open[nb] & (1 << ((f + 2) % 4))):
					continue
				if f == S_IDX or f == W_IDX:          # 이음새는 한 번만: N·E 쪽에서 센다 (정거장 쪽은 S 뿐이라 예외)
					continue
			var kind := "A"
			if fd.kind.get(c, "") == "neck" and fd.kind.get(nb, "") == "room":
				kind = "D"
			elif fd.kind.get(c, "") == "room" and fd.kind.get(nb, "") == "neck":
				kind = "D"
			fd.seams.append({"cell": c, "face": f, "kind": kind, "pos": cell_world(c) + Vector3(DIR_VEC[f].x, 0.0, DIR_VEC[f].y) * Tuning.GRID_CELL * 0.5,
				"r": 0 if (f == N_IDX or f == S_IDX) else 1})


func _place_collars(fd: FloorData) -> void:
	_collect_seams(fd)
	if Tuning.COLLAR_THICK <= 0.0:
		return
	var holder := Node3D.new()
	holder.name = "Collars"
	fd.root.add_child(holder)
	var mat: Material = _rock_material(fd)
	for sm in fd.seams:
		var mi := MeshInstance3D.new()
		mi.mesh = _collar(sm["kind"])
		if mat != null:
			mi.material_override = mat
		mi.name = "C_%d_%d_%s" % [sm["cell"].x, sm["cell"].y, DIR_NAME[sm["face"]]]
		mi.position = sm["pos"]
		mi.rotation.y = sm["r"] * PI * 0.5
		mi.visibility_range_end = Tuning.PIECE_VIEW_RANGE
		holder.add_child(mi)


## 직선 조각 껍질(SHL_)의 재질 — Atmosphere 가 젖은 ShaderMaterial 로 바꿔 둔 것. 칼라도 같은 바위로 보인다
func _rock_material(fd: FloorData) -> Material:
	for c in fd.pieces:
		if fd.pieces[c]["name"] != "straight":
			continue
		var node: Node3D = fd.pieces[c]["node"]
		for ch in node.get_children():
			if ch is MeshInstance3D and ch.name.begins_with("SHL_") and (ch as MeshInstance3D).mesh != null:
				return (ch as MeshInstance3D).mesh.surface_get_material(0)
	return null


## 윤곽(로컬 xy, 아치 = build_piece.py 의 arch 와 같은 반타원) 안쪽 면을 z ±depth 로 세운 띠. 법선은 통로 쪽.
func _collar(kind: String) -> ArrayMesh:
	if _collar_mesh.has(kind):
		return _collar_mesh[kind]
	var hw: float = 3.5 if kind == "A" else 1.75
	var h_wall: float = 4.4 if kind == "A" else 2.45
	var h_top: float = 5.6 if kind == "A" else 3.0
	var t: float = Tuning.COLLAR_THICK
	var inset: float = Tuning.COLLAR_INSET
	var d: float = Tuning.COLLAR_DEPTH
	# 윤곽 점 (안쪽 면). 왼벽 아래(바닥 밑 띠 끝) → 왼벽 위 → 아치 → 오른벽 → 오른벽 아래
	var pts := PackedVector2Array()
	pts.append(Vector2(-hw - inset, -t))
	pts.append(Vector2(-hw - inset, h_wall))
	var segs := 16
	for i in range(1, segs):
		var u: float = -1.0 + 2.0 * float(i) / float(segs)
		var y: float = h_wall + (h_top - h_wall) * sqrt(maxf(0.0, 1.0 - u * u))
		pts.append(Vector2(u * (hw + inset), y + inset))
	pts.append(Vector2(hw + inset, h_wall))
	pts.append(Vector2(hw + inset, -t))
	# 바닥 아래는 띠의 안쪽 면 = y −inset 평면 (바닥 판 바로 밑). 오른쪽 → 왼쪽으로 가야 안쪽(위)을 본다
	var floor_pts := PackedVector2Array([Vector2(hw + inset, -inset), Vector2(-hw - inset, -inset)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(st, pts, d)
	_strip(st, floor_pts, d)
	st.generate_normals()
	var mesh := st.commit()
	_collar_mesh[kind] = mesh
	return mesh


## 2D 폴리라인을 z −d..+d 로 뽑은 띠. 진행 방향의 오른쪽(= 윤곽 안쪽, 통로)을 앞면으로 감는다.
func _strip(st: SurfaceTool, pts: PackedVector2Array, d: float) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var p0 := Vector3(a.x, a.y, -d)
		var p1 := Vector3(b.x, b.y, -d)
		var p2 := Vector3(b.x, b.y, d)
		var p3 := Vector3(a.x, a.y, d)
		var n := Vector3(b.y - a.y, -(b.x - a.x), 0.0)          # 진행 방향의 오른쪽
		# Godot 의 앞면은 시계 방향: 법선(반시계 외적)이 안쪽을 향하면 순서를 뒤집어야 앞면이 안쪽을 본다
		var tri_n := (p1 - p0).cross(p3 - p0)
		if tri_n.dot(n) < 0.0:
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
		else:
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
			st.add_vertex(p0); st.add_vertex(p3); st.add_vertex(p2)


## 크립(통나무 기둥) 속 바위 채우기 (#27 수정 2). 사용자 스크린샷의 "벽과 벽 사이 틈"은 크립의 빈 속이 통나무 틈새로 검게 보인 것이었다.
## 갈림(T·+)·방 2×2 의 크립 자리(PieceCatalog.CRIBS)에 바위 기둥을 세운다. 재질은 칼라와 같은 젖은 바위.
func _fill_cribs(fd: FloorData) -> void:
	if Tuning.CRIB_FILL_W <= 0.0:
		return
	var holder := Node3D.new()
	holder.name = "CribFill"
	fd.root.add_child(holder)
	var mat: Material = _rock_material(fd)
	var meshes := {}
	for c in fd.pieces:
		var p: Dictionary = fd.pieces[c]
		if not PieceCatalog.CRIBS.has(p["name"]):
			continue
		var spec: Dictionary = PieceCatalog.CRIBS[p["name"]]
		var node: Node3D = p["node"]
		if not meshes.has(spec["h"]):
			var bm := BoxMesh.new()
			bm.size = Vector3(Tuning.CRIB_FILL_W, spec["h"], Tuning.CRIB_FILL_W)
			meshes[spec["h"]] = bm
		for at in spec["at"]:
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[spec["h"]]
			if mat != null:
				mi.material_override = mat
			mi.name = "K_%d_%d_%d" % [c.x, c.y, holder.get_child_count()]
			mi.position = node.position + node.transform.basis * Vector3(at.x, spec["h"] * 0.5, at.y)
			mi.rotation.y = node.rotation.y
			mi.visibility_range_end = Tuning.PIECE_VIEW_RANGE
			holder.add_child(mi)


# ---------------- 갱도 설비 (#28) ----------------
## 직선 칸마다 왼쪽 묶음 L(케이블 3·애자·풍관·배수로·라깅·갓등)과 오른쪽 묶음 R(배수관·플랜지·받침) 하나씩. 조각 gltf 는 안 건드린다.
## 메시는 변형별로 한 번만 만든다 — 7 m 한 칸분. 갱목 세트가 칸마다 같은 자리(z ±2.625·±0.875)라 처짐·걸이도 칸 경계를 넘어 이어진다.
## 곡선·갈림·방·끝막이에는 없다 — 구간 끝에서 배관은 플랜지로, 풍관은 그냥 끊긴다 (ponytail: 엘보·휨 조각은 거슬리면 다음에).
## 로컬 축은 직선 조각과 같다: x 가로(왼쪽 −) · y 위 · z 길이. 조각과 같은 자리·회전으로 놓는다.
const SVC_SET_Z: Array[float] = [-2.625, -0.875, 0.875, 2.625]   # 갱목 세트 자리 (build_piece.py SET_YS)
const SVC_POST_IN := 3.16        # 기둥 안쪽 면 x (3.5 − 0.34)
const SVC_CAP_BOTTOM := 4.67     # 갓보 아랫면 y (POST_H 4.8 + 0.05 − 0.36/2)
const SVC_LAMP_X := 0.9          # 갓등 x (갓보 밑, 가운데서 오른쪽)
var _svc_mesh := {}              # "L0".."R2" -> ArrayMesh
var _svc_mats := {}


func _place_services(fd: FloorData) -> void:
	fd.services.clear()
	if Tuning.SVC_ON <= 0:
		return
	var holder := Node3D.new()
	holder.name = "Services"
	fd.root.add_child(holder)
	if _svc_mats.is_empty():
		_svc_mats = _piece_materials(fd)
	var rng := RandomNumberGenerator.new()
	rng.seed = fd.seed + 300
	var idx := 0
	for c in fd.pieces:
		var p: Dictionary = fd.pieces[c]
		if p["name"] != "straight":
			continue
		idx += 1
		var vl: int = 1 if idx % Tuning.SVC_JBOX_EVERY == 0 else (2 if rng.randf() < 0.5 else 0)
		var vr: int = 1 if idx % Tuning.SVC_VALVE_EVERY == 0 else (2 if idx % Tuning.SVC_SIGN_EVERY == 0 else 0)
		var node: Node3D = p["node"]
		for sv in [["L", vl], ["R", vr]]:
			var mi := MeshInstance3D.new()
			mi.mesh = _svc_mesh_for("%s%d" % [sv[0], sv[1]])
			mi.name = "S_%d_%d_%s" % [c.x, c.y, sv[0]]
			mi.position = node.position
			mi.rotation.y = node.rotation.y
			mi.visibility_range_end = Tuning.PIECE_VIEW_RANGE
			holder.add_child(mi)
			fd.services.append({"cell": c, "side": sv[0], "variant": sv[1], "node": mi})


## 직선 조각이 쓰는 재질(이름 앞자리로). Atmosphere 가 이미 손본 그 객체라 같은 색·틴트로 보인다. 없으면 새 재질.
func _piece_materials(fd: FloorData) -> Dictionary:
	var found := {}
	for c in fd.pieces:
		if fd.pieces[c]["name"] != "straight":
			continue
		for ch in (fd.pieces[c]["node"] as Node3D).get_children():
			if not (ch is MeshInstance3D) or (ch as MeshInstance3D).mesh == null:
				continue
			var m: Mesh = (ch as MeshInstance3D).mesh
			for i in m.get_surface_count():
				var mat := m.surface_get_material(i)
				if mat == null:
					continue
				for prefix in ["MAT_Timber", "MAT_RustyMetal", "MAT_Cable", "MAT_Bulb"]:   # 이름은 내보내기에서 _EXPORT 가 붙는다 → 앞자리로
					if mat.resource_name.begins_with(prefix) and not found.has(prefix):
						found[prefix] = mat
		break
	var out := {}
	for pair in [["timber", "MAT_Timber"], ["rust", "MAT_RustyMetal"], ["cable", "MAT_Cable"], ["bulb", "MAT_Bulb"]]:
		out[pair[0]] = found.get(pair[1], _svc_new_material(pair[1], Color(0.3, 0.3, 0.3), 0.8, 0.0))
	out["duct"] = _svc_new_material("SVC_Duct", Color(0.26, 0.24, 0.12), 1.0, 0.0)
	out["duct_dark"] = _svc_new_material("SVC_DuctDark", Color(0.12, 0.11, 0.07), 1.0, 0.0)
	out["water"] = _svc_new_material("SVC_Water", Color(0.06, 0.07, 0.07), Tuning.SVC_WATER_ROUGH, 0.0)
	out["steel"] = _svc_new_material("SVC_Steel", Color(0.12, 0.11, 0.10), 0.6, 0.6)
	out["ceramic"] = _svc_new_material("SVC_Ceramic", Color(0.75, 0.74, 0.68), 0.5, 0.0)
	out["conc"] = _svc_new_material("SVC_Concrete", Color(0.28, 0.27, 0.24), 1.0, 0.0)
	out["sign"] = _svc_new_material("SVC_Sign", Color(0.70, 0.60, 0.12), 0.6, 0.0)
	out["red"] = _svc_new_material("SVC_CableRed", Color(0.45, 0.04, 0.03), 0.6, 0.0)
	return out


func _svc_new_material(mat_name: String, col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED     # 코드로 감은 면의 방향을 안 따진다 (칼라는 반대로 감아 한 번 안 보였다)
	return m


func _svc_mesh_for(key: String) -> ArrayMesh:
	if _svc_mesh.has(key):
		return _svc_mesh[key]
	var mesh := ArrayMesh.new()
	var st := {}                                    # 재질 이름 -> SurfaceTool
	var rng := RandomNumberGenerator.new()
	rng.seed = 2800 + absi(key.hash()) % 100000     # 변형마다 고정 — 층·판이 달라도 같은 라깅 (골든이 흔들리지 않게)
	var side: String = key.substr(0, 1)
	var v: int = int(key.substr(1))
	var hw: float = Tuning.GRID_CELL * 0.5
	if side == "L":
		var sx := -1.0
		var cx: float = sx * (SVC_POST_IN - 0.06)          # 케이블 x
		var h: float = Tuning.SVC_CABLE_H
		# 1. 라깅: 기둥 사이 구간 SVC_LAG_P, 위쪽(2.4~4.4)만, 줄마다 30 % 빠짐
		var gaps: Array = [[-hw, SVC_SET_Z[0]], [SVC_SET_Z[0], SVC_SET_Z[1]], [SVC_SET_Z[1], SVC_SET_Z[2]], [SVC_SET_Z[2], SVC_SET_Z[3]], [SVC_SET_Z[3], hw]]
		for g in gaps:
			if rng.randf() >= Tuning.SVC_LAG_P:
				continue
			var z0: float = [2.4, 2.9, 3.4][rng.randi() % 3]
			var a: float = g[0] + (0.17 if g[0] > -hw else -0.06)
			var b: float = g[1] - (0.17 if g[1] < hw else -0.06)
			var y := z0
			while y < 4.4:
				if rng.randf() >= 0.3:
					_st_box(_st(st, "timber"), Vector3(sx * (SVC_POST_IN - 0.03) + rng.randf_range(-0.01, 0.01), y + rng.randf_range(-0.04, 0.04), (a + b) * 0.5), Vector3(0.05, 0.2, b - a))   # 기둥 면에 붙여 — 바위 요철(≤0.3) 속에 묻히면 그림자로 검게 뜬다
				y += 0.42
		# 2. 케이블 3: 세트에서 걸리고 사이(칸 경계 포함)에서 처진다
		var zs: Array = [-hw, SVC_SET_Z[0], -1.75, SVC_SET_Z[1], 0.0, SVC_SET_Z[2], 1.75, SVC_SET_Z[3], hw]
		for spec in [[0.0, 0.0, Tuning.SVC_CABLE_R, "cable"], [-0.07, 0.02, Tuning.SVC_CABLE_R, "cable"], [0.14, 0.0, 0.008, "red"]]:
			var pts: Array = []
			for i in zs.size():
				var sag: float = 0.0 if i % 2 == 1 else Tuning.SVC_CABLE_SAG
				pts.append(Vector3(cx + sx * spec[1] + (0.0 if i % 2 == 1 else sx * -0.03), h + spec[0] - sag, zs[i]))
			_st_tube(_st(st, spec[3]), pts, spec[2], 8, false)
		for z in SVC_SET_Z:                          # 걸이: 기둥에 박힌 철봉 2 + 흰 애자
			_st_tube(_st(st, "steel"), [Vector3(sx * SVC_POST_IN, h + 0.06, z), Vector3(cx + sx * 0.04, h + 0.06, z)], 0.012, 6, true)
			_st_tube(_st(st, "steel"), [Vector3(sx * SVC_POST_IN, h - 0.10, z), Vector3(cx + sx * 0.04, h - 0.10, z)], 0.012, 6, true)
			_st_tube(_st(st, "ceramic"), [Vector3(cx, h - 0.005, z), Vector3(cx, h + 0.065, z)], 0.03, 8, true)
		# 3. 풍관: 어깨, 갓보마다 띠, 사이 처짐. 이음 고리 3.5 m 마다
		var dx: float = sx * Tuning.SVC_DUCT_X
		var dpts: Array = []
		for i in zs.size():
			dpts.append(Vector3(dx, Tuning.SVC_DUCT_H - (0.0 if i % 2 == 1 else 0.10), zs[i]))
		_st_tube(_st(st, "duct"), dpts, Tuning.SVC_DUCT_R, 12, false)
		for z in SVC_SET_Z:
			var top: float = SVC_CAP_BOTTOM
			var bot: float = Tuning.SVC_DUCT_H + Tuning.SVC_DUCT_R - 0.02
			_st_box(_st(st, "steel"), Vector3(dx, (top + bot) * 0.5, z), Vector3(0.04, top - bot, 0.05))
		for z in [-1.75, 1.75]:
			_st_ring(_st(st, "duct_dark"), Vector3(dx, Tuning.SVC_DUCT_H - 0.05, z), Tuning.SVC_DUCT_R + 0.02, 0.025, Vector3.FORWARD)
		# 4. 배수로: 턱 2 + 물 (+ 덮개판)
		var wx: float = sx * 2.75
		for ddx in [-Tuning.SVC_DITCH_W * 0.5, Tuning.SVC_DITCH_W * 0.5]:
			_st_box(_st(st, "conc"), Vector3(wx + ddx, 0.07, 0.0), Vector3(0.08, 0.14, Tuning.GRID_CELL))   # 턱 0.14: 바닥 요철(0.06) 위로 나와야 검게 안 뜬다
		_st_box(_st(st, "water"), Vector3(wx, 0.085, 0.0), Vector3(Tuning.SVC_DITCH_W - 0.08, 0.004, Tuning.GRID_CELL))
		if v != 1:
			_st_box(_st(st, "timber"), Vector3(wx, 0.16, rng.randf_range(-2.5, 2.5)), Vector3(Tuning.SVC_DITCH_W + 0.1, 0.03, 0.5))
		# 5. 갓등(죽은 등): 세트 0·2 (3.5 m 마다), 갓보 밑. 전등선은 갓보 밑을 건너 케이블에 합류
		var lp: Array = [Vector3(cx, h + 0.25, -hw)]
		for k in [0, 2]:
			var z: float = SVC_SET_Z[k]
			var yb: float = SVC_CAP_BOTTOM
			_st_tube(_st(st, "cable"), [Vector3(SVC_LAMP_X, yb, z), Vector3(SVC_LAMP_X, yb - 0.30, z)], 0.006, 5, false)
			_st_tube(_st(st, "cable"), [Vector3(SVC_LAMP_X, yb - 0.29, z), Vector3(SVC_LAMP_X, yb - 0.37, z)], 0.025, 8, true)
			_st_tube_r(_st(st, "steel"), [Vector3(SVC_LAMP_X, yb - 0.355, z), Vector3(SVC_LAMP_X, yb - 0.445, z)], [0.02, 0.16], 12, false)
			_st_sphere(_st(st, "bulb"), Vector3(SVC_LAMP_X, yb - 0.49, z), 0.045)
			_st_ring(_st(st, "steel"), Vector3(SVC_LAMP_X, yb - 0.53, z), 0.075, 0.005, Vector3.UP)
			for j in 5:
				var t: float = j * TAU / 5.0
				_st_tube(_st(st, "steel"), [Vector3(SVC_LAMP_X + cos(t) * 0.055, yb - 0.42, z + sin(t) * 0.055), Vector3(SVC_LAMP_X + cos(t) * 0.075, yb - 0.58, z + sin(t) * 0.075)], 0.004, 4, false)
			lp.append(Vector3(SVC_LAMP_X - 0.4, 4.78, z - 0.6))
			lp.append(Vector3(SVC_LAMP_X, yb - 0.01, z))
			lp.append(Vector3(SVC_LAMP_X - 0.4, 4.78, z + 0.6))
			lp.append(Vector3(cx, h + 0.25, z + 0.9))
		lp.append(Vector3(cx, h + 0.25, hw))
		_st_tube(_st(st, "cable"), lp, 0.007, 5, false)
		# 6. 변형 1: 접속함 + 늘어진 여분 케이블
		if v == 1:
			_st_box(_st(st, "steel"), Vector3(sx * 3.06, h - 0.45, 0.0), Vector3(0.14, 0.22, 0.32))
			_st_tube(_st(st, "cable"), [Vector3(sx * 2.98, h - 0.35, -0.16), Vector3(sx * 2.9, h - 0.9, -0.3), Vector3(sx * 2.9, 0.05, -0.4), Vector3(sx * 2.4, 0.03, -0.2)], 0.014, 6, false)
	else:
		var sx := 1.0
		var ax: float = hw - 0.34 - 0.06               # 조각에 이미 있는 압기관 x 3.1, y 1.25 (build_piece.py pipe_cable_straight)
		var ay := 1.25
		# 1. 배수관: 바닥 가까이, 받침 2, 플랜지 1쌍
		var dxr: float = sx * Tuning.SVC_DRAIN_X
		_st_tube(_st(st, "rust"), [Vector3(dxr, Tuning.SVC_DRAIN_H, -hw - 0.05), Vector3(dxr, Tuning.SVC_DRAIN_H, hw + 0.05)], Tuning.SVC_DRAIN_R, 12, false)
		for z in [-2.9, 0.6]:
			var hs: float = Tuning.SVC_DRAIN_H - Tuning.SVC_DRAIN_R + 0.04
			_st_box(_st(st, "conc"), Vector3(dxr, hs * 0.5, z), Vector3(0.22, hs, 0.10))
		for z in [-1.23, -1.17]:
			_st_tube(_st(st, "rust"), [Vector3(dxr, Tuning.SVC_DRAIN_H, z - 0.01), Vector3(dxr, Tuning.SVC_DRAIN_H, z + 0.01)], Tuning.SVC_DRAIN_R + 0.04, 16, true)
		# 2. 압기관 플랜지 1쌍 (배관 자체는 조각에 있다)
		for z in [1.87, 1.93]:
			_st_tube(_st(st, "rust"), [Vector3(sx * ax, ay, z - 0.01), Vector3(sx * ax, ay, z + 0.01)], 0.085, 16, true)
		if v == 1:                                     # 밸브 + 핸드휠 + 바닥으로 늘어진 호스
			_st_tube(_st(st, "rust"), [Vector3(sx * ax, ay, -1.71), Vector3(sx * ax, ay, -1.49)], 0.075, 12, true)
			_st_tube(_st(st, "steel"), [Vector3(sx * ax, ay, -1.6), Vector3(sx * ax, ay + 0.27, -1.6)], 0.014, 6, true)
			_st_ring(_st(st, "rust"), Vector3(sx * ax, ay + 0.28, -1.6), 0.11, 0.012, Vector3.UP)
			_st_tube(_st(st, "cable"), [Vector3(sx * ax, ay - 0.08, -1.6), Vector3(sx * 2.9, 0.5, -1.3), Vector3(sx * 2.6, 0.04, -0.7), Vector3(sx * 1.9, 0.03, 0.2)], 0.02, 6, false)
		elif v == 2:                                   # 벽 전화기 + 전화선, 노란 표지판 (글자 없음 — ponytail: Label3D 는 노드가 늘어 뺐다)
			_st_box(_st(st, "steel"), Vector3(sx * 3.07, 1.55, -0.875), Vector3(0.16, 0.34, 0.24))
			_st_tube(_st(st, "cable"), [Vector3(sx * 3.07, 1.72, -0.83), Vector3(sx * 3.3, 2.6, -0.575), Vector3(sx * 3.25, 4.4, -0.275), Vector3(sx * 3.3, SVC_CAP_BOTTOM, 0.125)], 0.006, 5, false)
			_st_box(_st(st, "sign"), Vector3(sx * (SVC_POST_IN - 0.02), 1.75, 2.625), Vector3(0.02, 0.24, 0.36))
	for mat_name in st:
		(st[mat_name] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _svc_mats[mat_name])
	_svc_mesh[key] = mesh
	return mesh


func _st(st: Dictionary, mat_name: String) -> SurfaceTool:
	if not st.has(mat_name):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		st[mat_name] = s
	return st[mat_name]


## UV 는 미터 단위 평면 좌표 — 조각 재질(MAT_Timber·MAT_RustyMetal)은 텍스처라 UV 가 없으면 (0,0) 한 점 색으로 검게 나온다
func _st_tri(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv: Array = []) -> void:
	s.set_normal(n)
	if uv.is_empty():
		uv = [Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.5, 0.5)]
	s.set_uv(uv[0])
	s.add_vertex(a)
	s.set_uv(uv[1])
	s.add_vertex(b)
	s.set_uv(uv[2])
	s.add_vertex(c)


func _st_box(s: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	for axis in 3:
		for sgn in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			var w := Vector3.ZERO
			u[(axis + 1) % 3] = h[(axis + 1) % 3]
			w[(axis + 2) % 3] = h[(axis + 2) % 3]
			var o: Vector3 = center + n * h[axis]
			var lu: float = u.length()
			var lw: float = w.length()
			var c0: Vector2 = Vector2(center[(axis + 1) % 3], center[(axis + 2) % 3])
			# Godot 앞면 = 시계 방향. 반대로 감으면 상자가 뒤집혀 안쪽 면만 보이고 법선이 등져 검게 뜬다 (첫 빌드의 검은 널판·배수로)
			_st_tri(s, o - u - w, o + u + w, o + u - w, n, [c0 + Vector2(-lu, -lw), c0 + Vector2(lu, lw), c0 + Vector2(lu, -lw)])
			_st_tri(s, o - u - w, o - u + w, o + u + w, n, [c0 + Vector2(-lu, -lw), c0 + Vector2(-lu, lw), c0 + Vector2(lu, lw)])


## 꺾은선을 따라 관. radii 가 점마다 (깔때기·구). caps = 양 끝을 원판으로 막는다.
func _st_tube_r(s: SurfaceTool, pts: Array, radii: Array, segs: int, caps: bool) -> void:
	var n: int = pts.size()
	var rings: Array = []
	var dirs: Array = []
	for i in n:
		var d: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		if d.length() < 0.5:
			d = Vector3.FORWARD
		var up: Vector3 = Vector3.UP if absf(d.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var n1: Vector3 = d.cross(up).normalized()
		var n2: Vector3 = n1.cross(d).normalized()
		var ring: Array = []
		for k in segs:
			var t: float = k * TAU / segs
			ring.append(n1 * cos(t) + n2 * sin(t))
		rings.append(ring)
		dirs.append(d)
	for i in n - 1:
		for k in segs:
			var k2: int = (k + 1) % segs
			var a: Vector3 = pts[i] + rings[i][k] * radii[i]
			var b: Vector3 = pts[i] + rings[i][k2] * radii[i]
			var c: Vector3 = pts[i + 1] + rings[i + 1][k2] * radii[i + 1]
			var d: Vector3 = pts[i + 1] + rings[i + 1][k] * radii[i + 1]
			var u0: float = float(k) / segs * TAU * radii[i]
			var u1: float = float(k + 1) / segs * TAU * radii[i]
			var v0: float = (pts[i] - pts[0]).length()
			var v1: float = (pts[i + 1] - pts[0]).length()
			s.set_normal(rings[i][k])
			s.set_uv(Vector2(u0, v0))
			s.add_vertex(a)
			s.set_normal(rings[i][k2])
			s.set_uv(Vector2(u1, v0))
			s.add_vertex(b)
			s.set_normal(rings[i + 1][k2])
			s.set_uv(Vector2(u1, v1))
			s.add_vertex(c)
			s.set_normal(rings[i][k])
			s.set_uv(Vector2(u0, v0))
			s.add_vertex(a)
			s.set_normal(rings[i + 1][k2])
			s.set_uv(Vector2(u1, v1))
			s.add_vertex(c)
			s.set_normal(rings[i + 1][k])
			s.set_uv(Vector2(u0, v1))
			s.add_vertex(d)
	if caps:
		for e in [0, n - 1]:
			var nn: Vector3 = -dirs[e] if e == 0 else dirs[e]
			for k in segs:
				_st_tri(s, pts[e], pts[e] + rings[e][k] * radii[e], pts[e] + rings[e][(k + 1) % segs] * radii[e], nn)


func _st_tube(s: SurfaceTool, pts: Array, r: float, segs: int, caps: bool) -> void:
	var radii: Array = []
	for i in pts.size():
		radii.append(r)
	_st_tube_r(s, pts, radii, segs, caps)


## 고리(토러스). axis 에 수직인 원.
func _st_ring(s: SurfaceTool, center: Vector3, big_r: float, tube_r: float, axis: Vector3) -> void:
	var up: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var n1: Vector3 = axis.cross(up).normalized()
	var n2: Vector3 = n1.cross(axis).normalized()
	var pts: Array = []
	for k in 17:
		var t: float = k * TAU / 16.0
		pts.append(center + (n1 * cos(t) + n2 * sin(t)) * big_r)
	_st_tube(s, pts, tube_r, 6, false)


func _st_sphere(s: SurfaceTool, center: Vector3, r: float) -> void:
	var pts: Array = []
	var radii: Array = []
	for k in 7:
		var t: float = k * PI / 6.0
		pts.append(center + Vector3(0.0, r * cos(t), 0.0))
		radii.append(maxf(r * sin(t), 0.001))
	_st_tube_r(s, pts, radii, 10, false)


# ---------------- 광차 (#29) ----------------
## 순환선 칸 순서(fd.ring)로 Path3D 곡선을 만든다. 직선 칸은 칸 가운데, 꺾이는 칸은 안쪽 모서리 중심 반지름 CART_CURVE_R 호 (rail_curve 와 같다).
## 광차는 PathFollow3D(MineCart.gd) — 순환선 길이 ÷ CART_COUNT 간격.
func _place_carts(fd: FloorData) -> void:
	fd.carts.clear()
	if Tuning.CART_COUNT <= 0 or fd.ring.size() < 4:
		return
	var holder := Node3D.new()
	holder.name = "Carts"
	fd.root.add_child(holder)
	var path := Path3D.new()
	path.name = "RailPath"
	path.curve = _ring_curve(fd)
	holder.add_child(path)
	fd.rail_path = path
	var packed := _packed(PieceCatalog.DIR + PieceCatalog.CART_GLTF)
	var script := load("res://scripts/MineCart.gd")
	var length: float = path.curve.get_baked_length()
	for k in Tuning.CART_COUNT:
		var pf := PathFollow3D.new()
		pf.name = "Cart_%d" % k
		pf.loop = true
		var model := packed.instantiate() as Node3D
		model.name = "Model"
		_set_view_range(model)
		pf.add_child(model)
		var board := Area3D.new()
		board.name = "Board"
		board.collision_layer = 0
		board.collision_mask = 2            # 플레이어 몸 (Player.tscn collision_layer 2)
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = Tuning.CART_BOARD_DIST
		cs.shape = sph
		cs.position = Vector3(0.0, 0.8, 0.0)
		board.add_child(cs)
		pf.add_child(board)
		pf.set_script(script)
		path.add_child(pf)
		pf.start(length * k / Tuning.CART_COUNT)
		fd.carts.append(pf)


## 되돌아가는 가지(A→B→A)를 없앨 때까지 지운다 (#29-c). _carve_path 가 제 길을 되짚으면 기록에 남고, 광차가 막다른 곳에서 180° 뒤집혔다.
## 레일은 그대로 파여 있고 광차만 안 들어간다. 첫·끝 칸은 안 건드린다
static func _strip_spurs(ring: Array[Vector2i]) -> void:
	var i := 1
	while i < ring.size() - 1:
		if ring[i - 1] == ring[i + 1]:
			ring.remove_at(i)
			ring.remove_at(i)
			i = maxi(i - 1, 1)
		else:
			i += 1


## 순환선 곡선 (Floor 로컬). ring 은 첫 = 끝.
func _ring_curve(fd: FloorData) -> Curve3D:
	var curve := Curve3D.new()
	var n: int = fd.ring.size() - 1              # 마지막은 첫 칸과 같다
	var r: float = Tuning.CART_CURVE_R
	for i in n:
		var cur: Vector2i = fd.ring[i]
		var prev: Vector2i = fd.ring[(i - 1 + n) % n]
		var next: Vector2i = fd.ring[(i + 1) % n]
		var center: Vector3 = cell_world(cur)
		var din := Vector3(prev.x - cur.x, 0.0, prev.y - cur.y)
		var dout := Vector3(next.x - cur.x, 0.0, next.y - cur.y)
		if din.is_equal_approx(-dout) or din.is_equal_approx(dout) or din.is_zero_approx() or dout.is_zero_approx():
			_curve_add(curve, center)
		else:
			var corner: Vector3 = center + (din + dout) * r
			for k in Tuning.CART_ARC_PTS:
				var t: float = PI * 0.5 * k / (Tuning.CART_ARC_PTS - 1)
				_curve_add(curve, corner - (dout * cos(t) + din * sin(t)) * r)
	_curve_add(curve, curve.get_point_position(0))
	return curve


## 직전 점과 같은 자리는 건너뛴다. 꺾이는 칸이 붙으면 앞 호의 끝 = 뒤 호의 시작 (GRID_CELL 7 = CART_CURVE_R 3.5 × 2) —
## 길이 0 구간이 생겨 PathFollow3D 가 접선을 0 벡터로 잡고 회전이 정면으로 튄다 (곡선에서 시점이 뚝뚝 끊기던 원인)
static func _curve_add(curve: Curve3D, p: Vector3) -> void:
	var n := curve.point_count
	if n > 0 and curve.get_point_position(n - 1).is_equal_approx(p):
		return
	curve.add_point(p)


# ---------------- 정비 1 (#30) ----------------
## timber 칸(조립기가 층마다 4곳 적어 둔 직선)마다 고장 하나: 조각의 세트 FAULT_SET 기둥을 숨기고 갓보를 기울인다. 옆에 부러진 갱목 소품.
func _place_faults(fd: FloorData) -> void:
	fd.faults.clear()
	var holder := Node3D.new()
	holder.name = "Faults"
	fd.root.add_child(holder)
	var script := load("res://scripts/Fault.gd")
	var lib := _packed(PROPS_PATH).instantiate() as Node3D
	var broken: Node3D = lib.get_node_or_null("PROP_post")
	var k := 0
	for c in fd.kind:
		if fd.kind[c] != "timber" or not fd.pieces.has(c) or fd.pieces[c]["name"] != "straight":
			continue
		var piece: Node3D = fd.pieces[c]["node"]
		var f := Node3D.new()
		f.name = "Fault_%d" % k
		var socket := Area3D.new()
		socket.name = "Socket"
		socket.collision_layer = 0
		socket.collision_mask = 2
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = Tuning.CARRY_REACH
		cs.shape = sph
		socket.add_child(cs)
		f.add_child(socket)
		f.set_script(script)
		f.position = piece.position
		f.rotation = piece.rotation
		holder.add_child(f)
		f.setup(piece, Tuning.FAULT_SET, fd.seed + 400 + k)
		if broken != null:
			var b := broken.duplicate() as Node3D
			b.name = "Broken"
			f.add_child(b)
			b.position = Vector3(2.2, 0.0, -0.2)
			b.rotation.y = 0.4
			_set_view_range(b)
		fd.faults.append(f)
		k += 1
	lib.free()


## 자재함 (#31): 정거장 앞 첫 직선 칸(입구 다음) 오른쪽 벽. 부품은 자재함이 E 마다 만든다 (Floor_i/Parts 아래)
func _place_bin(fd: FloorData) -> void:
	var parts_holder := Node3D.new()
	parts_holder.name = "Parts"
	fd.root.add_child(parts_holder)
	var bin := Node3D.new()
	bin.name = "Bin"
	var metal: Material = _svc_mats.get("rust") if not _svc_mats.is_empty() else null
	var timber: Material = _svc_mats.get("timber") if not _svc_mats.is_empty() else null
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = Tuning.BIN_SIZE
	if metal != null:
		bm.material = metal
	body.mesh = bm
	body.position = Vector3(0.0, Tuning.BIN_SIZE.y * 0.5, 0.0)
	bin.add_child(body)
	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	var lm := BoxMesh.new()
	lm.size = Vector3(Tuning.BIN_SIZE.x + 0.06, 0.05, Tuning.BIN_SIZE.z + 0.06)
	if metal != null:
		lm.material = metal
	lid.mesh = lm
	lid.position = Vector3(0.0, Tuning.BIN_SIZE.y + 0.12, 0.0)
	lid.rotation.z = 0.35                            # 열린 채 기운 뚜껑
	bin.add_child(lid)
	var reach := Area3D.new()
	reach.name = "Reach"
	reach.collision_layer = 0
	reach.collision_mask = 2
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = Tuning.CARRY_REACH
	cs.shape = sph
	cs.position = Vector3(-0.6, 0.6, 0.0)
	reach.add_child(cs)
	bin.add_child(reach)
	bin.set_script(load("res://scripts/PartsBin.gd"))
	_set_view_range(bin)
	fd.root.add_child(bin)
	var cell: Vector2i = fd.entry + DIR_VEC[N_IDX]
	bin.position = cell_world(cell) + Vector3(2.45, 0.0, -1.2)
	bin.mat_creaky = timber
	var good: Material = timber.duplicate() if timber is StandardMaterial3D else timber
	if good is StandardMaterial3D:
		(good as StandardMaterial3D).albedo_color = Tuning.PART_GOOD_TINT
		good.resource_name = "SVC_TimberGood"           # MAT_Timber 로 시작하면 Atmosphere 가 TIMBER_TINT 로 되돌린다
	bin.mat_good = good
	fd.bin = bin


# ---------------- 괴물 + 감독 (#35) ----------------
## 층마다 Stalker(CharacterBody3D, 몸 = Miner.tscn) 하나 + Director 하나. 처음엔 숨김 — 감독이 압박 PRESSURE_SEND 에 시야 밖 곡선 칸에 내려놓는다
func _place_stalker(fd: FloorData) -> void:
	var s := Stalker.new()
	s.setup(fd)
	_set_view_range(s)
	fd.root.add_child(s)
	s.position = cell_world(fd.entry)
	var d := Director.new()
	d.setup(fd, s)
	fd.root.add_child(d)
	fd.stalker = s
	fd.director = d


## 격자 길 (BFS): a 에서 b 까지 뚫린 면으로만 이어지는 칸 열. 첫 = a, 끝 = b. 없으면 빈 배열
static func grid_path(fd: FloorData, a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not fd.open.has(a) or not fd.open.has(b):
		return out
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		if c == b:
			break
		for f in 4:
			if not (fd.open[c] & (1 << f)):
				continue
			var nb: Vector2i = c + DIR_VEC[f]
			if prev.has(nb) or not fd.open.has(nb):
				continue
			prev[nb] = c
			q.append(nb)
	if not prev.has(b):
		return out
	var c := b
	while c != a:
		out.push_front(c)
		c = prev[c]
	out.push_front(a)
	return out


## from 에서 격자 거리 max_n 안의 뚫린 칸 → 거리
static func grid_dist(fd: FloorData, from: Vector2i, max_n: int) -> Dictionary:
	var dist := {}
	if not fd.open.has(from):
		return dist
	dist[from] = 0
	var q: Array[Vector2i] = [from]
	var qi := 0
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		if dist[c] >= max_n:
			continue
		for f in 4:
			if not (fd.open[c] & (1 << f)):
				continue
			var nb: Vector2i = c + DIR_VEC[f]
			if dist.has(nb) or not fd.open.has(nb):
				continue
			dist[nb] = dist[c] + 1
			q.append(nb)
	return dist


## 플레이어 시야 밖인가: 앞 방향(-Z)과 자리 방향의 내적이 SPAWN_BEHIND_DOT 밑
static func behind_player(player: Node3D, at: Vector3) -> bool:
	var fwd: Vector3 = -player.global_transform.basis.z
	var to: Vector3 = at - player.global_position
	to.y = 0.0
	if to.is_zero_approx():
		return false
	return fwd.dot(to.normalized()) < Tuning.SPAWN_BEHIND_DOT
