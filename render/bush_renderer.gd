class_name BushRenderer
extends MultiMeshInstance2D
## Draws every berry bush through one MultiMesh: stocked bushes dark green,
## picked-clean bushes dead brown. Positions are static; only colors change,
## and only when the sim bumps bushes.version.

const BUSH_PX := 12.0

static var _STOCKED := Palette.COLORS[29]
static var _EMPTY := Palette.COLORS[24]

var _version_seen := 0


func setup(world: SimWorld, bushes: Bushes) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(BUSH_PX, BUSH_PX)
	multimesh.mesh = quad
	multimesh.instance_count = bushes.cells.size()
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in bushes.cells.size():
		var cell := bushes.cells[i]
		@warning_ignore("integer_division")
		var pos := Vector2(cell % world.width + 0.5, cell / world.width + 0.5) * px
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, pos))
	_version_seen = 0
	sync(bushes)


func sync(bushes: Bushes) -> void:
	if bushes.version == _version_seen:
		return
	_version_seen = bushes.version
	for i: int in bushes.cells.size():
		multimesh.set_instance_color(i, _STOCKED if bushes.berries[i] > 0 else _EMPTY)
