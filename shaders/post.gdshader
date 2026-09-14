// 후처리 한 장 (제안서 #17, 질감 D). 화면 전체를 덮는 ColorRect 에 붙는다.
// 비네트: 가장자리를 어둡게. 그레인: 밝기에 비례한 알갱이 — 검은 화면은 검은 채로 둔다
// (사망 검사의 "밝기 0.008 이하"가 안 흔들린다). 수치는 Atmosphere.gd 가 Tuning 에서 넣는다.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float vignette : hint_range(0.0, 1.0) = 0.35;
uniform float grain : hint_range(0.0, 0.2) = 0.04;
uniform float grain_floor : hint_range(0.0, 0.1) = 0.0;   // 어둠에서도 남는 알갱이
uniform float time_seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	// 비네트. 중앙 0, 모서리 1 인 거리를 제곱해 부드럽게.
	vec2 d = SCREEN_UV - vec2(0.5);
	float v = dot(d, d) * 2.0;
	col *= 1.0 - vignette * v * v;
	// 그레인. 프레임마다 다른 잡음을 밝기에 곱한다.
	float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float n = hash(SCREEN_UV * 1000.0 + vec2(time_seed)) - 0.5;
	col += n * (grain * luma * 4.0 + grain_floor);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
