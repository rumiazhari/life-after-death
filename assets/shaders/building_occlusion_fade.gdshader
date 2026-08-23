shader_type canvas_item;
// Local soft transparency hole around the player for projected Prague
// facades and displaced roofs. World-space distance falloff so ONE shared
// material instance can drive every canvas layer of a building regardless
// of each layer's local origin. Gameplay geometry is never touched -- this
// only modulates drawn alpha.

uniform vec2 player_world = vec2(1e9, 1e9);
uniform float strength = 0.0; // 0 = fully opaque, 1 = full fade applied
uniform float fade_outer = 112.0;
uniform float fade_inner = 72.0;
uniform float center_alpha = 0.28;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float d = distance(world_pos, player_world);
	float openness = smoothstep(fade_inner, fade_outer, d); // 0 at player -> 1 at rim
	float alpha_mul = mix(center_alpha, 1.0, openness);
	COLOR.a *= mix(1.0, alpha_mul, clamp(strength, 0.0, 1.0));
}
