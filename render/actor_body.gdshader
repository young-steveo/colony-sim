shader_type canvas_item;
// Per-instance frame selection for the actor MultiMesh: INSTANCE_CUSTOM.xy
// carries the frame's origin in UV space. Frame size is 1/8 x 1/4 of the
// body sheet (8 columns, 4 rows of 16x16 cells).

const vec2 CELL = vec2(0.125, 0.25);
// Half a texel on the 128x64 sheet: keeps edge samples inside their own
// frame so neighboring cells never bleed in (the flash-artifact fix).
const vec2 INSET = vec2(0.5 / 128.0, 0.5 / 64.0);

void vertex() {
	// QuadMesh UVs are 3D-native (V up); flip V so frames read upright in 2D.
	vec2 f = vec2(UV.x, 1.0 - UV.y);
	UV = INSTANCE_CUSTOM.xy + INSET + f * (CELL - 2.0 * INSET);
}
