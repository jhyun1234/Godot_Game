class_name ArmGround
extends SkeletonModifier3D

## #46 손 접지. 기는 클립은 팔이 바닥을 뚫는다 (실측 crawl −0.524 m · run −0.476 m, 발은 +0.03 이라 몸을 올리면 발이 뜬다).
## 원인은 Mixamo 재타깃이 손발 접지를 안 맞춰 주는 것 — 이 괴물은 팔이 클립이 전제한 것보다 길다.
## 하는 일: 클립이 뼈를 놓은 뒤, 엎드린 클립일 때만 좌·우 팔(Arm → ForeArm → Hand)을 2뼈 역기구학으로 다시 푼다.
## 손끝 뼈가 바닥 위 STALKER_HAND_CLEAR 에 오도록 손 자리를 올리고, 팔꿈치가 접히는 쪽은 클립이 잡아 놓은 쪽 그대로.
## 다리는 안 건드린다 (발은 이미 바닥 위, 무릎 −0.035 는 눈에 띄면 그때).

const CHAINS := [["mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand"],
	["mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand"]]

var clip := ""              # 지금 트는 클립 (MinerBody 가 넣는다). 엎드린 클립일 때만 판다
var body: MinerBody         # 붙어 있는 면(점 + 법선)을 여기서 읽는다 — 바닥·천장·벽이 같은 코드다 (#49)
var lifted := 0.0           # 마지막 프레임에 올린 양 중 큰 쪽 (m, 월드) — 봇이 읽는다
var low_before := INF       # 보정 전 손끝과 면 사이 거리 (m, + 면 밖). 고도는 보정 뒤 뼈를 원래대로 되돌려 놓기 때문에
var low_after := INF        # 보정 뒤 손끝-면 거리 (m). 밖에서는 이 순간을 못 본다 — 여기서 재서 넘긴다
var force := false          # #57 클립이 목록에 없어도 판다 (착지 동안 — Stalker 가 켠다)
var reach_target := Vector3.INF   # #57 팔을 뻗는 목표 (월드). INF 면 안 뻗는다 — 매달림·낙하에서 플레이어 가슴
var reach_w := 0.0                # #57 0~1, 클립이 놓은 손 자리에서 뻗은 자리까지 섞는 비율
var spread := INF                 # #57 그려진 두 손 사이 ÷ 어깨 너비 (봇이 읽는다 — 팔 벌림)
var aim_dot := INF                # #57 그려진 팔이 목표를 가리키는 정도, 두 팔 평균 (1 = 정확히)

var _chains: Array = []     # [[위팔, 아래팔, 손, [손 아래 뼈 전부]], ...]


func _ready() -> void:
	set_process_priority(0)


func _resolve(skel: Skeleton3D) -> void:
	_chains.clear()
	for names in CHAINS:
		var up := skel.find_bone(names[0])
		var lo := skel.find_bone(names[1])
		var hand := skel.find_bone(names[2])
		if up < 0 or lo < 0 or hand < 0:
			push_error("ArmGround: 뼈를 못 찾았다 %s" % [names])
			continue
		var tips: Array[int] = []
		_collect(skel, hand, tips)
		_chains.append([up, lo, hand, tips])


func _collect(skel: Skeleton3D, b: int, out: Array[int]) -> void:
	out.append(b)
	for c in skel.get_bone_children(b):
		_collect(skel, c, out)


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body == null:
		return
	if _chains.is_empty():
		_resolve(skel)
	lifted = 0.0
	low_before = INF
	low_after = INF
	var inv := skel.global_transform.affine_inverse()
	if Tuning.STALKER_REACH_ON and reach_w > 0.0 and is_finite(reach_target.x):   # #57 매달림·낙하: 팔을 목표 쪽으로 뻗는다
		var g := skel.global_transform
		var side: Vector3 = ((g * skel.get_bone_global_pose(_chains[0][0])).origin - (g * skel.get_bone_global_pose(_chains[-1][0])).origin).normalized()   # 오른어깨 → 왼어깨 (월드)
		for i in _chains.size():                                                   # #59 팔마다 가슴에서 제 쪽으로 벌린 곳 — 가운데로 모이면 두 손이 얼굴을 가린다
			_reach_arm(skel, _chains[i], inv * (reach_target + side * (1.0 if i == 0 else -1.0) * Tuning.STALKER_REACH_SIDE_M))
	if force or Tuning.STALKER_GROUND_CLIPS.has(clip):
		var up_dir: Vector3 = (inv.basis * body.surface_normal).normalized() # 면에서 몸 쪽으로 나가는 방향 (스켈레톤 공간)
		var sp: Vector3 = body.surface_point
		if not (is_finite(sp.x) and is_finite(sp.y) and is_finite(sp.z)):
			sp = body.global_position                                        # 안 정해졌으면 발밑 = 바닥
		var ground: Vector3 = inv * sp
		var floor_h: float = ground.dot(up_dir) + Tuning.STALKER_HAND_CLEAR / maxf(skel.global_transform.basis.get_scale().y, 0.001)
		for ch in _chains:
			low_before = minf(low_before, _clear_world(skel, ch[3]))
		if Tuning.STALKER_HAND_GROUND:                                       # 끄면 재기만 한다 — 사보타주가 무엇이 깨지는지 숫자로 보이게
			for _pass in 2:                                                  # 손목을 올려도 손이 돌아서 손끝은 조금 덜 올라간다 — 두 번 푼다
				for ch in _chains:
					_ground_arm(skel, ch, up_dir, floor_h)
		for ch in _chains:
			low_after = minf(low_after, _clear_world(skel, ch[3]))
	_measure(skel)


## 손 아래 뼈 가운데 면에 가장 깊이 들어간 것의 면까지 거리 (m, 월드. + 면 밖 · − 면 속)
func _clear_world(skel: Skeleton3D, bones: Array) -> float:
	var sp: Vector3 = body.surface_point
	if not (is_finite(sp.x) and is_finite(sp.y) and is_finite(sp.z)):
		sp = body.global_position
	var lo := INF
	for b in bones:
		lo = minf(lo, ((skel.global_transform * skel.get_bone_global_pose(b)).origin - sp).dot(body.surface_normal))
	return lo


func _ground_arm(skel: Skeleton3D, ch: Array, up_dir: Vector3, floor_h: float) -> void:
	var low := INF
	for b in ch[3]:
		low = minf(low, skel.get_bone_global_pose(b).origin.dot(up_dir))
	if low >= floor_h:
		return
	var lift: float = minf(floor_h - low, Tuning.STALKER_HAND_LIFT_MAX / maxf(skel.global_transform.basis.get_scale().y, 0.001))
	var p0: Vector3 = skel.get_bone_global_pose(ch[0]).origin
	var target: Vector3 = skel.get_bone_global_pose(ch[2]).origin + up_dir * lift
	if _solve_arm(skel, ch, target, (target - p0).normalized().cross(up_dir)):
		lifted = maxf(lifted, lift * skel.global_transform.basis.get_scale().y)


## #57 팔을 목표(스켈레톤 공간) 쪽으로 팔 길이 × STALKER_REACH_FRAC 만큼 뻗는다. reach_w 만큼 클립 손 자리에서 섞는다
func _reach_arm(skel: Skeleton3D, ch: Array, tgt: Vector3) -> void:
	var p0: Vector3 = skel.get_bone_global_pose(ch[0]).origin
	var p1: Vector3 = skel.get_bone_global_pose(ch[1]).origin
	var p2: Vector3 = skel.get_bone_global_pose(ch[2]).origin
	var to: Vector3 = tgt - p0
	if to.length() < 0.001:
		return
	var dir: Vector3 = to.normalized()
	var want: Vector3 = p0 + dir * (p0.distance_to(p1) + p1.distance_to(p2)) * Tuning.STALKER_REACH_FRAC
	var side: Vector3 = dir.cross(Vector3.UP)                              # 클립 팔이 곧게 늘어져 팔꿈치 면이 없을 때 쓸 면
	if side.length() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	_solve_arm(skel, ch, p2.lerp(want, clampf(reach_w, 0.0, 1.0)), side)


## #57 그려진 자세를 잰다 — 고도가 그린 뒤 뼈를 되돌려 밖에서는 이 값을 못 본다
func _measure(skel: Skeleton3D) -> void:
	spread = INF
	aim_dot = INF
	if _chains.size() < 2:
		return
	var g := skel.global_transform
	var s0: Vector3 = (g * skel.get_bone_global_pose(_chains[0][0])).origin
	var s1: Vector3 = (g * skel.get_bone_global_pose(_chains[1][0])).origin
	var h0: Vector3 = (g * skel.get_bone_global_pose(_chains[0][2])).origin
	var h1: Vector3 = (g * skel.get_bone_global_pose(_chains[1][2])).origin
	var w: float = s0.distance_to(s1)
	if w > 0.001:
		spread = h0.distance_to(h1) / w
	if is_finite(reach_target.x):
		aim_dot = ((h0 - s0).normalized().dot((reach_target - s0).normalized()) + (h1 - s1).normalized().dot((reach_target - s1).normalized())) * 0.5


## 2뼈 역기구학: 위팔·아래팔을 돌려 손목을 target(스켈레톤 공간)에 보낸다. 팔꿈치는 클립이 잡아 놓은 쪽(없으면 fallback 면). 못 풀면 false
func _solve_arm(skel: Skeleton3D, ch: Array, target: Vector3, fallback: Vector3) -> bool:
	var up: int = ch[0]
	var lo: int = ch[1]
	var hand: int = ch[2]
	var p0: Vector3 = skel.get_bone_global_pose(up).origin
	var p1: Vector3 = skel.get_bone_global_pose(lo).origin
	var p2: Vector3 = skel.get_bone_global_pose(hand).origin
	var l1: float = p0.distance_to(p1)
	var l2: float = p1.distance_to(p2)
	var d: float = clampf(p0.distance_to(target), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	if l1 < 0.001 or l2 < 0.001:
		return false
	var dir: Vector3 = (target - p0).normalized()
	var axis: Vector3 = (p1 - p0).cross(p2 - p0)                          # 클립이 잡아 놓은 팔꿈치 방향 (굽은 면의 법선)
	if axis.length() < 0.0001:
		axis = fallback
	if axis.length() < 0.0001:
		return false
	axis = axis.normalized()
	var a: float = acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	var elbow_a: Vector3 = p0 + dir.rotated(axis, a) * l1
	var elbow_b: Vector3 = p0 + dir.rotated(axis, -a) * l1
	var elbow: Vector3 = elbow_a if elbow_a.distance_to(p1) <= elbow_b.distance_to(p1) else elbow_b   # 옛 팔꿈치에 가까운 쪽
	var t_up: Transform3D = skel.get_bone_global_pose(up)
	var q1 := Quaternion((p1 - p0).normalized(), (elbow - p0).normalized())
	skel.set_bone_global_pose(up, Transform3D(Basis(q1) * t_up.basis, t_up.origin))
	skel.force_update_bone_child_transform(up)
	var t_lo: Transform3D = skel.get_bone_global_pose(lo)
	var p2b: Vector3 = skel.get_bone_global_pose(hand).origin
	var q2 := Quaternion((p2b - t_lo.origin).normalized(), (target - t_lo.origin).normalized())
	skel.set_bone_global_pose(lo, Transform3D(Basis(q2) * t_lo.basis, t_lo.origin))
	skel.force_update_bone_child_transform(lo)
	return true

