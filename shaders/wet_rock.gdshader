// 젖은 바위 (제안서 #20 F5 판정 "젖은 게 아니라 반사가 센 것으로 보인다" — 세 번째 같은 판정).
// 젖음의 단서는 얼룩이다: 젖은 자리만 어둡고, 그 자리만 번들거리고, 수직면에서는 세로로 흘러내린 자국.
// 균일한 광택막(clearcoat 0.7)은 "반사가 센 돌"일 뿐이었다. Blender 재질의 젖음 노이즈가 내보내기에서 빠져
// 그 얼룩이 사라졌던 것을 Godot 쪽에서 세계 좌표 노이즈로 되살린다.
// 갱도 모듈·정거장의 MAT_RockWall·MAT_Floor 에 Atmosphere.gd 가 실행 중에 붙인다. 텍스처는 glTF 것 그대로.
// 수치는 Tuning.gd (WET_*).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_noise : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform float normal_scale = 1.0;
uniform int rough_channel = 1;          // glTF 가 거칠기를 G 채널에 싣는다 (StandardMaterial3D.roughness_texture_channel)
uniform float wet_scale = 0.3;          // 노이즈 한 주기 = 1/wet_scale m
uniform float wet_low = 0.42;           // 노이즈가 이 밑이면 마른 돌
uniform float wet_high = 0.60;          // 이 위면 완전히 젖음. 사이는 번짐
uniform float wet_darken = 0.5;         // 젖은 자리 색 배율 (물이 스미면 어두워진다)
uniform float wet_roughness = 0.1;      // 젖은 자리 거칠기
uniform float wet_clearcoat = 1.0;      // 젖은 자리 물막. 마른 자리는 0
uniform float drip_stretch = 4.0;       // 수직면에서 노이즈를 세로로 이만큼 늘린다 — 흘러내린 자국
uniform float wet_band = 1.2;           // 바닥에서 이 높이(m)까지는 더 젖어 있다 — 물은 아래에 고인다
uniform float wet_band_add = 0.25;      // 그 띠에서 노이즈에 더하는 값
uniform float level_pitch = 8.0;        // 층 간격. 바닥이 y 0, -8, ... 에 있다 (Tuning.LIFT_DROP)
uniform float specular_value = 0.5;     // 마른 바위 반사율 (#27 수정: 0.5 는 램프가 흰 점으로 맺혔다)
uniform float detail_tiles = 6.0;       // 미세 결: 같은 노멀맵을 이만큼 잘게 한 번 더 겹친다 (#27 수정)
uniform float detail_strength = 0.0;    // 그 세기. 0 = 없음
uniform bool use_triplanar = false;     // 세계 좌표 세 면 샘플링 (#27 수정 2) — 조각 경계에서 무늬가 안 끊긴다. UV 는 안 쓴다
uniform float tri_scale = 0.42;         // 1/한 장 크기 (m)
uniform float tri_blend = 4.0;          // 세 면 섞는 날카로움

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

// 세계 좌표 삼면 노이즈. 수직면(법선이 x·z)은 y 를 눌러 세로 줄무늬, 바닥(법선 y)은 그냥 얼룩.
float wet_mask(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float nx = texture(wet_noise, vec2(p.z, p.y / drip_stretch) * wet_scale).r;
	float nz = texture(wet_noise, vec2(p.x, p.y / drip_stretch) * wet_scale).r;
	float ny = texture(wet_noise, p.xz * wet_scale).r;
	return nx * w.x + ny * w.y + nz * w.z;
}

float pick_rough(vec4 rt) {
	return rough_channel == 0 ? rt.r : (rough_channel == 1 ? rt.g : (rough_channel == 2 ? rt.b : (rough_channel == 3 ? rt.a : rt.r)));
}

// 한 면의 탄젠트 노멀(큰 결 + 미세 결), xy 만 쓴다
vec2 tangent_xy(vec2 uv) {
	vec2 n1 = texture(normal_tex, uv).xy * 2.0 - 1.0;
	vec2 n2 = texture(normal_tex, uv * detail_tiles).xy * 2.0 - 1.0;
	return (n1 + n2 * detail_strength) * normal_scale;
}

void fragment() {
	vec4 a;
	float r;
	float h = mod(wpos.y, level_pitch);                         // 가장 가까운 아래층 바닥에서의 높이
	float band = wet_band_add * (1.0 - smoothstep(0.0, wet_band, h));
	float wet = smoothstep(wet_low, wet_high, wet_mask(wpos, wnrm) + band);
	if (use_triplanar) {
		// 세계 좌표 세 면. 법선이 향한 면의 텍스처가 이긴다 (젖은 얼룩과 같은 섞기). 조각 경계와 무관하다
		vec3 w = pow(abs(wnrm), vec3(tri_blend));
		w /= (w.x + w.y + w.z);
		vec2 ux = wpos.zy * tri_scale;
		vec2 uy = wpos.xz * tri_scale;
		vec2 uz = wpos.xy * tri_scale;
		a = (texture(albedo_tex, ux) * w.x + texture(albedo_tex, uy) * w.y + texture(albedo_tex, uz) * w.z) * albedo_tint;
		r = pick_rough(texture(rough_tex, ux)) * w.x + pick_rough(texture(rough_tex, uy)) * w.y + pick_rough(texture(rough_tex, uz)) * w.z;
		// 노멀: 면마다 탄젠트 xy 를 세계 법선에 더해(UDN) 세계 공간에서 섞고 카메라 공간으로
		vec2 tx = tangent_xy(ux);
		vec2 ty = tangent_xy(uy);
		vec2 tz = tangent_xy(uz);
		vec3 nX = vec3(wnrm.x, tx.y + wnrm.y, tx.x + wnrm.z);
		vec3 nY = vec3(ty.x + wnrm.x, wnrm.y, ty.y + wnrm.z);
		vec3 nZ = vec3(tz.x + wnrm.x, tz.y + wnrm.y, wnrm.z);
		vec3 nw = normalize(nX * w.x + nY * w.y + nZ * w.z);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	} else {
		a = texture(albedo_tex, UV) * albedo_tint;
		r = pick_rough(texture(rough_tex, UV));
		// 큰 결 + 미세 결 (같은 노멀맵을 detail_tiles 배 잘게). xy 를 더하고 z 는 큰 결 것 — 1 m 앞에서 "사진 한 장"이 안 되게
		vec3 n1 = texture(normal_tex, UV).rgb * 2.0 - 1.0;
		vec3 n2 = texture(normal_tex, UV * detail_tiles).rgb * 2.0 - 1.0;
		vec3 nb = normalize(vec3(n1.xy + n2.xy * detail_strength, n1.z));
		NORMAL_MAP = nb * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ALBEDO = a.rgb * mix(1.0, wet_darken, wet);
	ROUGHNESS = mix(r, wet_roughness, wet);
	CLEARCOAT = wet * wet_clearcoat;
	CLEARCOAT_ROUGHNESS = 0.1;
	SPECULAR = specular_value;
}
