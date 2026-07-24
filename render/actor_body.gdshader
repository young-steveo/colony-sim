shader_type canvas_item;
// Per-instance frame selection for the actor MultiMesh: INSTANCE_CUSTOM.xy
// carries the frame's origin in UV space. Frame size is 1/8 x 1/4 of the
// body sheet (8 columns, 4 rows of 16x16 cells).

void vertex() {
	// QuadMesh UVs are 3D-native (V up); flip V so frames read upright in 2D.
	UV = vec2(UV.x, 1.0 - UV.y) * vec2(0.125, 0.25) + INSTANCE_CUSTOM.xy;
}
