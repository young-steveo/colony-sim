shader_type canvas_item;
// Per-instance cell selection for 12×5 blob sheets (192×80, 16px cells):
// INSTANCE_CUSTOM.xy = cell UV origin. Instance COLOR carries tint
// (white = built, translucent blue = blueprint ghost).
//
// Sampling is exactly 1:1; bleed protection is a clamp, never an inset
// remap. COLOR is assigned, never multiplied by texture() — it already
// arrives pre-multiplied (see CLAUDE.md, learned the hard way).

const vec2 CELL = vec2(1.0 / 12.0, 1.0 / 5.0);
const vec2 HALF_TEXEL = vec2(0.5 / 192.0, 0.5 / 80.0);

varying vec2 v_origin;
varying vec4 v_tint;

void vertex() {
	v_origin = INSTANCE_CUSTOM.xy;
	v_tint = COLOR;
	// QuadMesh UVs are 3D-native (V up); flip V so cells read upright in 2D.
	UV = vec2(UV.x, 1.0 - UV.y) * CELL + v_origin;
}

void fragment() {
	vec2 uv = clamp(UV, v_origin + HALF_TEXEL, v_origin + CELL - HALF_TEXEL);
	COLOR = texture(TEXTURE, uv) * v_tint;
}
