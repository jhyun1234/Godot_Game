class_name MinerBody
extends Node3D

## 갱목 광부 몸통 (#36). miner_rigged.glb 인스턴스 + GLB 가 만든 AnimationPlayer. 하는 일은 play(클립) 하나.
## 충돌 없음 — #35 가 CharacterBody3D 로 감싸고 감각·상태를 얹는다. 모델은 +Z(정거장 쪽)를 본다.
## 모델 만든 과정: Documents/MineTunnel/MINER_ASSET_PIPELINE.md (스크립트 사본 tools/miner/).

const CLIPS: PackedStringArray = ["idle_crouch", "walk_crouch", "crawl", "run", "attack_swipe", "hit", "death", "roar", "prone_down",
	"run_stand", "climb_up", "climb_down", "fall_air", "land_hard"]   # 뒤 다섯은 #48 (서서 달리기·벽타기·공중·착지)
const LOOPING: PackedStringArray = ["idle_crouch", "walk_crouch", "crawl", "run"]   # 나머지는 한 번
const PRONE: PackedStringArray = ["crawl", "run", "fall_air", "land_hard"]                                   # 엎드린 자세. 나머지는 선 자세 (#47 섞는 시간)
const BRIDGE := "prone_down"                                                        # 엎드림 → 네 발 → 일어섬. 뒤로 틀면 엎드리기 (#47)

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _ground: ArmGround                                                              # #46 손 접지
var glare: SpineGlare                                                               # #59 노려보기 (봇이 그려진 값을 바로 읽는다)
var surface_normal := Vector3.UP                                                    # 짚는 면의 법선 (월드, 면에서 몸 쪽). 바닥 UP · 천장 DOWN · 벽은 옆 (#49)
var surface_point := Vector3.INF                                                    # 짚는 면 위의 한 점 (월드). 안 정해졌으면 이 노드 자리 (= 바닥)


func _ready() -> void:
	scale = Vector3.ONE * Tuning.MINER_SCALE
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skel = _find_skeleton(self)
	if _anim == null:
		push_error("MinerBody: AnimationPlayer 가 없다 (GLB 임포트 animation/import 확인)")
		return
	for n in LOOPING:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_set_blend_times()
	if _skel != null:                                                               # #46: 클립이 뼈를 놓은 뒤 손을 바닥에 붙이는 보정
		glare = SpineGlare.new()                                                    # #59: 손 보정보다 먼저 붙인다 — 굽힌 어깨에서 팔을 뻗게
		glare.name = "SpineGlare"
		glare.body = self
		_skel.add_child(glare)
		_ground = ArmGround.new()
		_ground.name = "ArmGround"
		_ground.body = self
		_skel.add_child(_ground)


## 클립 짝마다 섞는 시간 (#47). 이걸 넣어 두면 play() 를 그냥 불러도 고도가 두 자세를 겹쳐 넘긴다 — 안 넣으면 한 프레임에 튄다.
func _set_blend_times() -> void:
	for a in CLIPS:
		for b in CLIPS:
			if a == b or not (_anim.has_animation(a) and _anim.has_animation(b)):
				continue
			var t: float = Tuning.MINER_BLEND_S
			if PRONE.has(a) != PRONE.has(b):
				t = Tuning.MINER_BLEND_POSE_S
			if a == BRIDGE or b == BRIDGE:
				t = Tuning.MINER_BLEND_BRIDGE_S
			if b == "hit" or b == "attack_swipe":
				t = Tuning.MINER_BLEND_HIT_S
			elif b == "roar":
				t = Tuning.MINER_BLEND_ROAR_S
			_anim.set_blend_time(a, b, t)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


## 클립을 튼다. 모르는 이름이면 false. backwards 면 뒤로, from_time >= 0 이면 그 시각부터 (#47 엎드리기).
## blend >= 0 이면 짝마다 정한 섞는 시간 대신 이 값 (#57 매달림: 섞는 시간이 곧 늘어지는 시간)
func play(clip: String, speed: float = Tuning.MINER_ANIM_SPEED, backwards: bool = false, from_time: float = -1.0, blend: float = -1.0) -> bool:
	if _anim == null or not _anim.has_animation(clip):
		return false
	_anim.speed_scale = speed
	if _ground != null:
		_ground.clip = clip
	if _anim.current_animation == clip and _anim.is_playing() and not backwards and from_time < 0.0:   # 같은 클립이면 처음으로 되감지 않는다 (상태 유지 중 매 프레임 불러도 된다, #35)
		return true
	if _ground != null:
		_ground.clip = clip
	position.y = Tuning.MINER_CLIP_Y_OFFSET.get(clip, 0.0)                  # 클립이 원점에서 떠 있으면 내린다 (#48 climb_down)
	if backwards:
		_anim.play_backwards(clip, blend)
	else:
		_anim.play(clip, blend)
	if from_time >= 0.0:
		_anim.seek(from_time, true)
	return true


## 엎드리기 (#47): 일어서는 클립을 선 자세 시각부터 뒤로 튼다. STALKER_DROP_S 안에 네 발 자세까지 온다.
func drop() -> bool:
	var secs: float = maxf(Tuning.STALKER_DROP_S, 0.05)
	var span: float = Tuning.MINER_PRONE_FROM - Tuning.MINER_PRONE_TO
	return play(BRIDGE, span / secs, true, Tuning.MINER_PRONE_FROM)


## 클립을 그 자리에 멈추거나(true) 이어서 튼다(false). 개발용 정지(숫자 8, #43 F5).
func set_paused(p: bool) -> void:
	if _anim == null:
		return
	if p:
		_anim.pause()
	elif not _anim.is_playing():
		_anim.play()


func is_paused() -> bool:
	return _anim != null and not _anim.is_playing() and _anim.assigned_animation != ""   # pause() 뒤 current_animation 은 "" 가 된다 — 멈춘 클립은 assigned_animation 에


func clip_names() -> PackedStringArray:
	return _anim.get_animation_list() if _anim != null else PackedStringArray()


func clip_length(clip: String) -> float:
	return _anim.get_animation(clip).length if _anim != null and _anim.has_animation(clip) else -1.0


func current_clip() -> String:
	return _anim.current_animation if _anim != null else ""


func clip_position() -> float:
	return _anim.current_animation_position if _anim != null and _anim.assigned_animation != "" else -1.0   # 멈춘 클립도 시각을 준다 (정지 키 검사)


func is_playing() -> bool:
	return _anim != null and _anim.is_playing()


func speed() -> float:
	return _anim.speed_scale if _anim != null else 0.0


## 지금 자세의 키 (m, 월드) — 본 전부의 가장 높은 점 − 가장 낮은 점. 웅크린 클립이면 약 1.9, T 포즈(안 움직임)면 2.5.
func bone_height() -> float:
	if _skel == null:
		return -1.0
	var lo := INF
	var hi := -INF
	for b in _skel.get_bone_count():
		var y: float = (_skel.global_transform * _skel.get_bone_global_pose(b)).origin.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return hi - lo


## 머리 뼈의 지금 높이 (m, 월드). 자세가 얼마나 빨리 바뀌는지를 봇이 이걸로 잰다 (#47).
func head_y() -> float:
	if _skel == null:
		return -1.0
	var b := _skel.find_bone("mixamorig_Head")
	if b < 0:
		return -1.0
	return (_skel.global_transform * _skel.get_bone_global_pose(b)).origin.y


## 엉덩이 뼈의 지금 높이 (m, 월드). 내려올 때 "머리부터"인지를 봇이 머리와 견준다 (#49).
func hip_y() -> float:
	if _skel == null:
		return -1.0
	var b := _skel.find_bone("mixamorig_Hips")
	if b < 0:
		return -1.0
	return (_skel.global_transform * _skel.get_bone_global_pose(b)).origin.y


## 마지막 프레임에 손 접지가 팔을 끌어올린 양 (m). 0 이면 안 건드렸다.
func hand_lift() -> float:
	return _ground.lifted if _ground != null else 0.0


## 손 접지를 **적용한 뒤**의 손끝과 면 사이 거리 (m, + 면 밖 · − 면 속). 고도는 보정으로 그린 뒤 뼈를 원래 자세로
## 되돌려 놓기 때문에(SkeletonModifier3D 규약) 밖에서 뼈를 읽으면 보정 전 값이 나온다 — 화면에 그려진 값은 이것이다.
## #49: 바닥·천장·벽을 한 값으로 재려고 월드 y 가 아니라 면 법선 쪽 거리로 바꿨다.
func hand_clear_drawn() -> float:
	return _ground.low_after if _ground != null else INF


## 같은 프레임의 보정 **전** 손끝-면 거리 (m). 검사가 "고칠 것이 있었다"를 함께 확인한다.
func hand_clear_raw() -> float:
	return _ground.low_before if _ground != null else INF


## #57 팔을 월드 한 점 쪽으로 뻗는다. w 0~1 = 클립 손 자리에서 뻗은 자리까지. target 이 INF 거나 w 0 이면 안 뻗는다
func set_reach(target: Vector3, w: float) -> void:
	if _ground != null:
		_ground.reach_target = target
		_ground.reach_w = w


## #59 상체를 들어 월드 한 점을 노려본다. w 0~1 굽힘 세기, t 노려보기 시작부터 지난 시간(숨쉬기·갸웃). target INF 면 안 굽힌다
func set_glare(target: Vector3, w: float, t: float) -> void:
	if glare != null:
		glare.target = target
		glare.w = w
		glare.t = t


## #57 **그려진** 두 손 사이 ÷ 어깨 너비. 팔을 옆으로 벌리면 커진다 (hand_clear_drawn 과 같은 이유로 보정 안에서 잰 값)
func hand_spread() -> float:
	return _ground.spread if _ground != null else INF


## #57 그려진 팔(어깨 → 손)이 뻗기 목표를 가리키는 정도, 두 팔 평균 (1 = 정확히 · 0 = 직각). 목표가 없으면 INF
func reach_aim() -> float:
	return _ground.aim_dot if _ground != null else INF


## #57 클립과 상관없이 손을 바닥에 붙인다 — 착지(land_hard)는 한 손이 바닥을 0.32 m 뚫는다(#48 부터, 실측 RightHandRing4).
## land_hard 를 STALKER_GROUND_CLIPS 에 넣지 않는 이유: 낙하 중에도 같은 클립을 틀어서, 공중에서 원점 밑 손을 들어 올려 버린다
func set_ground_force(on: bool) -> void:
	if _ground != null:
		_ground.force = on
