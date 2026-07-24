class_name StructureRenderer
extends MultiMeshInstance2D
## Draws built structures and blueprint ghosts through one MultiMesh:
## walls grey, doors timber, beds blue; blueprints are the same colors at
## ghost alpha. Rebuilt only when the sim's structure or blueprint versions
## change.

static var _COLORS: Dictionary = {
	SimWorld.STRUCT_WALL: Palette.COLORS[6],
	SimWorld.STRUCT_DOOR: Palette.COLORS[21],
	SimWorld.STRUCT_BED: Palette.COLORS[47],
}
const GHOST_ALPHA := 0.35

var _structures_seen := -1
var _blueprints_seen := -1


func setup() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(TerrainRenderer.TILE_PX, TerrainRenderer.TILE_PX)
	multimesh.mesh = quad
	_structures_seen = -1
	_blueprints_seen = -1


func sync(world: SimWorld, blueprints: Blueprints) -> void:
	if world.structures_version == _structures_seen and blueprints.version == _blueprints_seen:
		return
	_structures_seen = world.structures_version
	_blueprints_seen = blueprints.version

	var cells := PackedInt32Array()
	var colors := PackedColorArray()
	for cell: int in world.width * world.height:
		var type := int(world.structures[cell])
		if type != SimWorld.STRUCT_NONE:
			var _e1: bool = cells.push_back(cell)
			var _e2: bool = colors.push_back(_COLORS[type])
	for b: int in blueprints.cells.size():
		var ghost: Color = _COLORS[int(blueprints.types[b])]
		ghost.a = GHOST_ALPHA
		var _e3: bool = cells.push_back(blueprints.cells[b])
		var _e4: bool = colors.push_back(ghost)

	multimesh.instance_count = cells.size()
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in cells.size():
		var cell := cells[i]
		@warning_ignore("integer_division")
		var pos := Vector2(cell % world.width + 0.5, cell / world.width + 0.5) * px
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, pos))
		multimesh.set_instance_color(i, colors[i])
