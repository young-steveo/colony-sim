shader_type canvas_item;
// Per-instance frame selection for the actor MultiMesh: INSTANCE_CUSTOM.xy
// carries the frame's origin in UV space. Frame size is 1/8 x 1/4 of the
// body sheet (8 columns, 4 rows of 16x16 cells).
//
// Sampling stays exactly 1:1 texel-to-quad (no inset remap — that resamples
// the sprite and doubles pixels). Bleed protection is a clamp instead:
// edge samples can never leave their own cell.

const vec2 CELL = vec2(0.125, 0.25);
const vec2 HALF_TEXEL = vec2(0.5 / 128.0, 0.5 / 64.0);

varying vec2 v_origin;

void vertex() {
	v_origin = INSTANCE_CUSTOM.xy;
	// QuadMesh UVs are 3D-native (V up); flip V so frames read upright in 2D.
	UV = vec2(UV.x, 1.0 - UV.y) * CELL + v_origin;
}

void fragment() {
	vec2 uv = clamp(UV, v_origin + HALF_TEXEL, v_origin + CELL - HALF_TEXEL);
	// Plain assignment: COLOR already arrives with the texture sample baked
	// in, so multiplying texture() in again squares the values (darkened,
	// oversaturated sprites — found the hard way).
	COLOR = texture(TEXTURE, uv);
}
