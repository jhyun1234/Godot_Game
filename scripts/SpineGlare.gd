class_name SpineGlare
extends SkeletonModifier3D

## #59 천장 노려보기. 클립(천장 기기 crawl)이 뼈를 놓은 뒤 엉덩이·척추 세 마디를 몸 옆 축으로 굽혀 상체를 붙은 면에서 들고,
## 목·머리를 목표(플레이어 눈) 쪽으로 돌린다. 숨쉬기(굽힘 흔들림)와 고개 갸웃(얼굴 축으로 굴림)을 얹는다.
## MinerBody 가 ArmGround 보다 먼저 붙인다 — 고도는 모디파이어를 자식 순서대로 돌리므로 팔은 굽힌 어깨 자리에서 뻗는다.
## 굽히는 축은 몸 기준(앞 × 위)이라 천장·바닥·낙하 중 어느 자세에서도 같은 코드다. 그려진 자세는 여기서 잰다 (#46).

const SPINE := ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]
const LEGS := ["mixamorig_LeftUpLeg", "mixamorig_RightUpLeg"]     # 엉덩이를 기울인 만큼 되돌린다 — 발은 천장에 둔다
const FEET := ["mixamorig_LeftFoot", "mixamorig_RightFoot", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]

var body: MinerBody
var target := Vector3.INF   # 볼 곳 (월드). INF 거나 w 0 이면 안 굽힌다
var w := 0.0                # 0~1 굽힘 세기
var t := 0.0                # 노려보기 시작부터 지난 시간 (s) — 숨쉬기·갸웃 시계

# 봇이 읽는 그려진 값
var lift_deg := INF         # 엉덩이 → Spine2 가 붙은 면에서 들린 각 (°, + = 면에서 멀어짐)
var head_aim := INF         # 얼굴 앞 방향 · 목표 방향 (1 = 정확히). 목표가 없으면 INF
var tilt_deg := 0.0         # 이번 프레임 고개를 얼굴 축으로 굴린 각 (°)
var head_pos := Vector3.INF # 머리 뼈 자리 (월드)
var hip_gap := INF          # 엉덩이 뼈와 면 사이 (m)
var foot_gap := INF         # 발 뼈 중 면에서 가장 먼 것 (m)

var _hips := -1
var _neck := -1
var _head := -1
var _spine: Array[int] = []
var _legs: Array[int] = []
var _feet: Array[int] = []
var _face := Vector3.ZERO   # 머리 뼈 기준 얼굴 앞 방향 (쉬는 자세의 모델 앞 +Z 에서 구한다)


func _resolve(skel: Skeleton3D) -> void:
	_hips = skel.find_bone("mixamorig_Hips")
	_neck = skel.find_bone("mixamorig_Neck")
	_head = skel.find_bone("mixamorig_Head")
	_spine = _bones(skel, SPINE)
	_legs = _bones(skel, LEGS)
	_feet = _bones(skel, FEET)
	if _hips < 0 or _neck < 0 or _head < 0 or _spine.size() < SPINE.size():
		push_error("SpineGlare: 뼈를 못 찾았다")
		return
	_face = (skel.get_bone_global_rest(_head).basis.inverse() * _to_skel(skel, body.global_transform.basis.z)).normalized()


func _bones(skel: Skeleton3D, names: Array) -> Array[int]:
	var out: Array[int] = []
	for n in names:
		var b := skel.find_bone(n)
		if b >= 0:
			out.append(b)
	return out


## 월드 방향 → 스켈레톤 공간 방향 (길이 1)
func _to_skel(skel: Skeleton3D, v: Vector3) -> Vector3:
	return (skel.global_transform.basis.inverse() * v).normalized()


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or body == null:
		return
	if _face == Vector3.ZERO:
		_resolve(skel)
		if _face == Vector3.ZERO:
			return
	tilt_deg = 0.0
	if Tuning.STALKER_GLARE_ON and w > 0.0 and is_finite(target.x):   # 끄면 재기만 한다 — 사보타주가 무엇이 깨지는지 숫자로 보이게
		_bend(skel)
	_measure(skel)


func _bend(skel: Skeleton3D) -> void:
	var fwd := _to_skel(skel, body.global_transform.basis.z)
	var up := _to_skel(skel, body.global_transform.basis.y)          # 몸 위 = 붙은 면에서 멀어지는 쪽 (천장이면 아래)
	var axis: Vector3 = fwd.cross(up).normalized()                   # 이 축으로 + 돌리면 앞이 위로 = 가슴이 면에서 든다
	var cap: float = deg_to_rad(Tuning.STALKER_GLARE_BONE_MAX)
	var hip: float = minf(deg_to_rad(Tuning.STALKER_GLARE_HIP_DEG), cap) * w
	_turn(skel, _hips, Basis(axis, hip))
	for b in _legs:
		_turn(skel, b, Basis(axis, -hip))
	var spine: float = deg_to_rad(Tuning.STALKER_GLARE_SPINE_DEG + Tuning.STALKER_GLARE_BREATH_DEG * sin(TAU * Tuning.STALKER_GLARE_BREATH_HZ * t))
	for b in _spine:
		_turn(skel, b, Basis(axis, minf(spine / _spine.size(), cap) * w))
	var tgt: Vector3 = skel.global_transform.affine_inverse() * target
	var head_cap: float = deg_to_rad(Tuning.STALKER_GLARE_HEAD_DEG) * 0.5 * w   # 목과 머리가 반씩
	for b in [_neck, _head]:
		var hp: Transform3D = skel.get_bone_global_pose(_head)
		var face: Vector3 = (hp.basis * _face).normalized()
		var to: Vector3 = (tgt - hp.origin).normalized()
		var ax: Vector3 = face.cross(to)
		if ax.length() < 0.0001:
			continue
		_turn(skel, b, Basis(ax.normalized(), minf(face.angle_to(to), head_cap)))
	var u: float = clampf((t - Tuning.STALKER_GLARE_TILT_AT) / maxf(Tuning.STALKER_GLARE_TILT_S, 0.01), 0.0, 1.0)
	if u > 0.0:                                                      # 고개 갸웃: 천천히 기울이고 그대로 둔다 (F5: 꺾었다 돌아오는 0.25초는 너무 빨랐다). 놓으면 w 와 함께 풀린다
		var hb: Basis = skel.get_bone_global_pose(_head).basis
		var y0: Vector3 = hb.y.normalized()
		_turn(skel, _head, Basis((hb * _face).normalized(), deg_to_rad(Tuning.STALKER_GLARE_TILT_DEG) * smoothstep(0.0, 1.0, u) * w))
		tilt_deg = rad_to_deg(y0.angle_to(skel.get_bone_global_pose(_head).basis.y.normalized()))


## 뼈 하나를 스켈레톤 공간 회전 q 만큼 제자리에서 돌린다
func _turn(skel: Skeleton3D, b: int, q: Basis) -> void:
	var p: Transform3D = skel.get_bone_global_pose(b)
	skel.set_bone_global_pose(b, Transform3D(q * p.basis, p.origin))
	skel.force_update_bone_child_transform(b)


func _measure(skel: Skeleton3D) -> void:
	var g := skel.global_transform
	var n: Vector3 = body.surface_normal
	var sp: Vector3 = body.surface_point
	if not (is_finite(sp.x) and is_finite(sp.y) and is_finite(sp.z)):
		sp = body.global_position
	var hip_w: Vector3 = g * skel.get_bone_global_pose(_hips).origin
	var chest_w: Vector3 = g * skel.get_bone_global_pose(_spine[_spine.size() - 1]).origin
	lift_deg = rad_to_deg(asin(clampf((chest_w - hip_w).normalized().dot(n), -1.0, 1.0)))
	var hp: Transform3D = skel.get_bone_global_pose(_head)
	head_pos = g * hp.origin
	head_aim = (g.basis * (hp.basis * _face)).normalized().dot((target - head_pos).normalized()) if is_finite(target.x) else INF
	hip_gap = (hip_w - sp).dot(n)
	foot_gap = -INF
	for b in _feet:
		foot_gap = maxf(foot_gap, (g * skel.get_bone_global_pose(b).origin - sp).dot(n))
