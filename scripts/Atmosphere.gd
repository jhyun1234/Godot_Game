extends Node

## 갱도의 색과 공기 (제안서 #17, 질감 A·D). 자동 실행.
##
## 세 가지를 한다. 전부 실행 중에 걸고, 씬 파일·KayKit 원본은 안 고친다.
##  1. 재질 — 화면에 놓이는 MeshInstance3D 를 지켜본다.
##     a) MineTunnel 갱도 재질(이름이 WET_MATERIALS 로 시작, #19)이면 젖은 바위 셰이더(wet_rock.gdshader)로
##        갈아 끼운다 — glTF 텍스처(색·노멀·거칠기)는 그대로 넘기고, 세계 좌표 노이즈로 젖은 얼룩만 더한다.
##        (#17~#20 균일한 광택막은 세 번 "반사가 센 돌"로 판정됐다.)
##     b) 던전 팔레트(`dungeon_texture.png`, 원본이든 generated/ 사본이든)를 쓰는 재질이면
##        `assets/generated/palette/` 의 사본 팔레트로 갈아 끼운다. 무광(#17 의 광택은 평면에서 원반이 돼 뺐다).
##        리프트·채굴 벽·파쇄 조각이 아직 이 길이다.
##     재질은 메시에 묶여 인스턴스끼리 공유되므로 한 번 바꾸면 같은 모델 전부에 먹는다.
##     나중에 시드로 조립하는 갱도 조각도 같은 길로 들어와 자동으로 같은 톤을 받는다.
##  2. 공기 — WorldEnvironment 가 놓이면 Tuning 의 안개·부피 안개·색 보정을 넣는다.
##  3. 후처리 — 방(현재 씬) 위에 비네트·그레인 ColorRect 한 장을 띄운다.
##
## 수치는 전부 Tuning.gd (CLAUDE.md §7).

const PALETTE_FILE := "dungeon_texture.png"
# Blender 재질 이름 앞부분 (내보내기가 _EXPORT 를 붙인다). 암벽·바닥만 — 갱목·철·소품은 마른 채 둔다.
const WET_MATERIALS := ["MAT_RockWall", "MAT_Floor"]
const TIMBER_MATERIAL := "MAT_Timber"   # 갱목·침목·부러진 기둥. 텍스처에 Tuning.TIMBER_TINT 를 곱한다
const POST_SHADER := "res://shaders/post.gdshader"
const WET_SHADER := "res://shaders/wet_rock.gdshader"
const POST_LAYER_NAME := "PostFx"

var _palette: Texture2D
var _wet_shader: Shader
var _wet_noise: NoiseTexture2D
var _swapped := {}      # 재질 RID -> true. 같은 재질을 두 번 만지지 않는다
var _wet_mats := {}     # 재질 이름 앞부분 -> Array[ShaderMaterial]. 봇의 텍스처 후보 비교(--texcmp)가 바꿔 끼운다
var _post_mat: ShaderMaterial


func _ready() -> void:
	_palette = load(Tuning.PALETTE_PATH)
	if _palette == null:
		push_warning("팔레트 사본이 없다: %s — python tools/palette.py" % Tuning.PALETTE_PATH)
	var tree := get_tree()
	tree.node_added.connect(_on_node_added)
	# 이미 떠 있는 것(자동 실행 순서상 거의 없지만)도 한 번 훑는다.
	_walk(tree.root)


func _process(_delta: float) -> void:
	if _post_mat != null:
		_post_mat.set_shader_parameter("time_seed", fmod(Time.get_ticks_msec() * 0.001, 100.0))


func _walk(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_walk(c)


func _on_node_added(n: Node) -> void:
	if n is MeshInstance3D:
		_swap_materials(n as MeshInstance3D)
	elif n is WorldEnvironment:
		_apply_environment(n as WorldEnvironment)
		_ensure_post(n)


# ---------------- 1. 재질 ----------------

func _swap_materials(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if mat == null or _swapped.has(mat.get_rid()):
			continue
		if mat.resource_name.begins_with(TIMBER_MATERIAL):
			mat.albedo_color = Tuning.TIMBER_TINT
			_swapped[mat.get_rid()] = true
			continue
		if _is_wet_name(mat.resource_name):
			var wet := _wet_material(mat)
			mi.mesh.surface_set_material(i, wet)      # 메시에 묶이므로 같은 모델의 모든 인스턴스에 먹는다
			for p in WET_MATERIALS:
				if mat.resource_name.begins_with(p):
					if not _wet_mats.has(p):
						_wet_mats[p] = []
					_wet_mats[p].append(wet)
			_swapped[mat.get_rid()] = true
			_swapped[wet.get_rid()] = true
			continue
		if _palette == null:
			continue
		var tex := mat.albedo_texture
		if tex == null or tex.resource_path.get_file() != PALETTE_FILE:
			continue
		if tex == _palette:
			continue
		mat.albedo_texture = _palette
		mat.roughness = Tuning.PALETTE_ROUGHNESS   # 무광. 평평한 면이라 광택막을 주면 램프가 원반으로 맺힌다
		mat.clearcoat_enabled = false
		_swapped[mat.get_rid()] = true


## StandardMaterial3D(glTF) 의 텍스처를 그대로 물려받는 젖은 바위 ShaderMaterial. 이름도 물려받는다 — 검사가 이름으로 찾는다.
func _wet_material(src: StandardMaterial3D) -> ShaderMaterial:
	if _wet_shader == null:
		_wet_shader = load(WET_SHADER)
	if _wet_noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.seed = 7
		fn.frequency = 0.012            # 256px 한 장에 얼룩 서너 개
		fn.fractal_octaves = 4
		_wet_noise = NoiseTexture2D.new()
		_wet_noise.width = 256
		_wet_noise.height = 256
		_wet_noise.seamless = true
		_wet_noise.noise = fn
	var m := ShaderMaterial.new()
	m.shader = _wet_shader
	m.resource_name = src.resource_name
	m.set_shader_parameter("albedo_tex", src.albedo_texture)
	m.set_shader_parameter("normal_tex", src.normal_texture)
	m.set_shader_parameter("rough_tex", src.roughness_texture)
	m.set_shader_parameter("rough_channel", int(src.roughness_texture_channel))
	m.set_shader_parameter("albedo_tint", src.albedo_color)
	m.set_shader_parameter("normal_scale", Tuning.ROCK_NORMAL_SCALE if src.normal_enabled else 0.0)
	m.set_shader_parameter("specular_value", Tuning.ROCK_SPECULAR)
	m.set_shader_parameter("detail_tiles", Tuning.DETAIL_NORMAL_TILES)
	m.set_shader_parameter("detail_strength", Tuning.DETAIL_NORMAL_STRENGTH)
	m.set_shader_parameter("use_triplanar", Tuning.TRIPLANAR)
	m.set_shader_parameter("tri_scale", Tuning.TRI_SCALE_FLOOR if src.resource_name.begins_with("MAT_Floor") else Tuning.TRI_SCALE_WALL)
	m.set_shader_parameter("tri_blend", Tuning.TRI_BLEND)
	m.set_shader_parameter("wet_noise", _wet_noise)
	m.set_shader_parameter("wet_scale", Tuning.WET_SCALE)
	m.set_shader_parameter("wet_low", Tuning.WET_LOW)
	m.set_shader_parameter("wet_high", Tuning.WET_HIGH)
	m.set_shader_parameter("wet_darken", Tuning.WET_DARKEN)
	m.set_shader_parameter("wet_roughness", Tuning.WET_ROUGHNESS)
	m.set_shader_parameter("wet_clearcoat", Tuning.STONE_CLEARCOAT)
	m.set_shader_parameter("drip_stretch", Tuning.DRIP_STRETCH)
	m.set_shader_parameter("wet_band", Tuning.WET_BAND)
	m.set_shader_parameter("wet_band_add", Tuning.WET_BAND_ADD)
	m.set_shader_parameter("level_pitch", Tuning.LIFT_DROP)
	return m


func _is_wet_name(name: String) -> bool:
	for p in WET_MATERIALS:
		if name.begins_with(p):
			return true
	return false


## 검사용. 이 메시의 재질이 사본 팔레트를 쓰고 있나.
func uses_palette(mi: MeshInstance3D) -> bool:
	if mi == null or mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(i) as StandardMaterial3D
		if mat != null and mat.albedo_texture == _palette and _palette != null:
			return true
	return false


# ---------------- 2. 공기 ----------------

var _env: Environment
var _adapt_tween: Tween


## 눈의 어둠 적응 (#32). 램프를 끄면 환경광이 DARK_ADAPT_TIME 에 걸쳐 DARK_ADAPT_AMBIENT 로 오르고 거리 안개가 DARK_ADAPT_FOG 로 짙어진다(가까운 것만 보인다). 켜면 즉시 평소(눈부심)
func set_adapt(on: bool) -> void:
	if _env == null:
		return
	if _adapt_tween != null:
		_adapt_tween.kill()
		_adapt_tween = null
	if on:
		_adapt_tween = create_tween()
		_adapt_tween.set_parallel(true)
		_adapt_tween.tween_property(_env, "ambient_light_energy", Tuning.DARK_ADAPT_AMBIENT, Tuning.DARK_ADAPT_TIME)
		_adapt_tween.tween_property(_env, "fog_density", Tuning.DARK_ADAPT_FOG, Tuning.DARK_ADAPT_TIME)   # 환경광은 거리가 없다 — 먼 곳은 안개로 잠근다 (#32 수정)
	else:
		_env.ambient_light_energy = Tuning.AMBIENT_ENERGY
		_env.fog_density = Tuning.FOG_DENSITY


## 검사용
func ambient() -> float:
	return _env.ambient_light_energy if _env != null else -1.0


func fog() -> float:
	return _env.fog_density if _env != null else -1.0


func _apply_environment(we: WorldEnvironment) -> void:
	var env := we.environment
	if env == null:
		return
	_env = env
	if _adapt_tween != null:
		_adapt_tween.kill()
		_adapt_tween = null
	env.ambient_light_energy = Tuning.AMBIENT_ENERGY
	env.fog_enabled = Tuning.FOG_DENSITY > 0.0
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Tuning.FOG_COLOR
	env.fog_density = Tuning.FOG_DENSITY
	env.fog_sun_scatter = 0.0
	env.fog_aerial_perspective = 0.0
	env.volumetric_fog_enabled = Tuning.VOLFOG_DENSITY > 0.0
	env.volumetric_fog_density = Tuning.VOLFOG_DENSITY
	env.volumetric_fog_albedo = Tuning.VOLFOG_ALBEDO
	env.volumetric_fog_anisotropy = Tuning.VOLFOG_ANISOTROPY
	env.volumetric_fog_ambient_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = Tuning.ADJ_CONTRAST
	env.adjustment_saturation = Tuning.ADJ_SATURATION


# ---------------- 3. 후처리 ----------------

## 방 루트 밑에 CanvasLayer 0 으로 붙인다. HUD(레이어 1 이상)와 사망 검은 화면은 이 위에 그려진다 —
## 글자에는 그레인이 안 앉고, 검은 화면은 검은 채로 남는다.
func _ensure_post(anchor: Node) -> void:
	var root := anchor.get_parent()
	if root == null or root.get_node_or_null(POST_LAYER_NAME) != null:
		return
	var layer := CanvasLayer.new()
	layer.name = POST_LAYER_NAME
	layer.layer = 0
	var rect := ColorRect.new()
	rect.name = "Rect"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load(POST_SHADER)
	_post_mat.set_shader_parameter("vignette", Tuning.VIGNETTE)
	_post_mat.set_shader_parameter("grain", Tuning.GRAIN)
	_post_mat.set_shader_parameter("grain_floor", Tuning.GRAIN_FLOOR)
	rect.material = _post_mat
	layer.add_child(rect)
	root.add_child.call_deferred(layer)


## 검사용. 후처리 재질(없으면 null).
func post_material() -> ShaderMaterial:
	return _post_mat


## 텍스처 후보 비교 (#27 수정 A, DevBot --texcmp). prefix 재질 전부에 다른 텍스처 3장과 보기 값을 끼운다. 원본은 안 건드린다.
## textures = {albedo, normal, rough}(Texture2D, 없으면 그대로), look = {셰이더 파라미터: 값}.
func texcmp_apply(prefix: String, textures: Dictionary, look: Dictionary) -> int:
	var n := 0
	for m in _wet_mats.get(prefix, []):
		var sm := m as ShaderMaterial
		if textures.has("albedo"):
			sm.set_shader_parameter("albedo_tex", textures["albedo"])
		if textures.has("normal"):
			sm.set_shader_parameter("normal_tex", textures["normal"])
		if textures.has("rough"):
			sm.set_shader_parameter("rough_tex", textures["rough"])
			sm.set_shader_parameter("rough_channel", 0)     # Poly Haven Rough.jpg 는 회색 한 장 (glTF 는 G)
		for k in look:
			sm.set_shader_parameter(k, look[k])
		n += 1
	return n
