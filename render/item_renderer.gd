class_name ItemRenderer
extends MultiMeshInstance2D
## Placeholder ground items: one small quad per stack, sitting at the
## tile's foot, wider as the stack grows — quantity you read by looking,
## not by counter (the anti-spreadsheet stance starts here). Real item
## sprites are queued art.

const STACK_HEIGHT := 4.0
var _defs: ItemDefs
var _width := 0
var _version_seen := 0


func setup(world: SimWorld, defs: ItemDefs) -> void:
	_defs = defs
	_width = world.width
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)  # unit quad; per-instance scale sizes it
	multimesh.mesh = quad


func sync(items: Items) -> void:
	if items.version == _version_seen:
		return
	_version_seen = items.version
	var n := items.cells.size()
	multimesh.instance_count = n
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in n:
		var cell := items.cells[i]
		var cx := float(cell % _width) * px + px * 0.5
		@warning_ignore("integer_division")
		var cy := float(cell / _width) * px + px - STACK_HEIGHT * 0.5 - 1.0
		var t := Transform2D(0.0, Vector2(2.0 + float(items.counts[i]), STACK_HEIGHT), 0.0, Vector2(cx, cy))
		multimesh.set_instance_transform_2d(i, t)
		multimesh.set_instance_color(i, _defs.colors[items.types[i]])
