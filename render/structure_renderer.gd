class_name StructureRenderer
extends Node2D
## Draws built structures and blueprint ghosts. Walls render from the wood
## blob sheet with 47-blob autotiling — blueprint walls autotile together
## with built walls, so a planned extension connects to the standing wall
## it grows from. Doors and beds stay palette boxes until their art lands.
## Rebuilt only when the sim's structure or blueprint versions change.

# Named drift (content/README.md): every wall material renders with the wood
# sheet until structures go data-driven.
const WALL_SHEET := preload("res://content/structures/wall_wood.png")
const BLOB_SHADER := preload("res://render/autotile_blob.gdshader")
const GHOST_TINT := Color(0.75, 0.87, 1.0, 0.45)
const GHOST_ALPHA := 0.35  # box ghosts (door/bed)

static var _COLORS: Dictionary = {
	SimWorld.STRUCT_DOOR: Palette.COLORS[21],
	SimWorld.STRUCT_BED: Palette.COLORS[47],
}

var _walls: MultiMeshInstance2D
var _boxes: MultiMeshInstance2D
var _structures_seen := -1
var _blueprints_seen := -1


func setup() -> void:
	_walls = MultiMeshInstance2D.new()
	_walls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_walls.texture = WALL_SHEET
	var mat := ShaderMaterial.new()
	mat.shader = BLOB_SHADER
	_walls.material = mat
	_walls.multimesh = _make_multimesh(true)
	add_child(_walls)

	_boxes = MultiMeshInstance2D.new()
	_boxes.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_boxes.multimesh = _make_multimesh(false)
	add_child(_boxes)

	_structures_seen = -1
	_blueprints_seen = -1


func _make_multimesh(custom_data: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = custom_data
	var quad := QuadMesh.new()
	quad.size = Vector2(TerrainRenderer.TILE_PX, TerrainRenderer.TILE_PX)
	mm.mesh = quad
	return mm


func sync(world: SimWorld, blueprints: Blueprints) -> void:
	if world.structures_version == _structures_seen and blueprints.version == _blueprints_seen:
		return
	_structures_seen = world.structures_version
	_blueprints_seen = blueprints.version

	# Wall presence map (built or blueprint) drives connectivity: 0 none,
	# 1 built, 2 blueprint. Doors are deliberately absent — walls cap at a
	# doorframe.
	var walls := PackedByteArray()
	var _r: int = walls.resize(world.width * world.height)
	var box_cells := PackedInt32Array()
	var box_colors := PackedColorArray()
	for cell: int in world.width * world.height:
		var type := int(world.structures[cell])
		if type == SimWorld.STRUCT_WALL:
			walls[cell] = 1
		elif type != SimWorld.STRUCT_NONE:
			var _e1: bool = box_cells.push_back(cell)
			var _e2: bool = box_colors.push_back(_COLORS[type])
	for b: int in blueprints.cells.size():
		var type := int(blueprints.types[b])
		if type == SimWorld.STRUCT_WALL:
			walls[blueprints.cells[b]] = 2
		else:
			var ghost: Color = _COLORS[type]
			ghost.a = GHOST_ALPHA
			var _e3: bool = box_cells.push_back(blueprints.cells[b])
			var _e4: bool = box_colors.push_back(ghost)

	_sync_walls(world, walls)
	_sync_boxes(world, box_cells, box_colors)


func _sync_walls(world: SimWorld, walls: PackedByteArray) -> void:
	var w := world.width
	var h := world.height
	var px := float(TerrainRenderer.TILE_PX)
	var count := 0
	for cell: int in walls.size():
		if walls[cell] != 0:
			count += 1
	_walls.multimesh.instance_count = count
	_walls.multimesh.visible_instance_count = count
	var i := 0
	for cell: int in walls.size():
		if walls[cell] == 0:
			continue
		var x := cell % w
		@warning_ignore("integer_division")
		var y := cell / w
		var mask := Autotile.mask_from(
			_has(walls, w, h, x, y - 1), _has(walls, w, h, x + 1, y),
			_has(walls, w, h, x, y + 1), _has(walls, w, h, x - 1, y),
			_has(walls, w, h, x + 1, y - 1), _has(walls, w, h, x + 1, y + 1),
			_has(walls, w, h, x - 1, y + 1), _has(walls, w, h, x - 1, y - 1))
		var uv := Autotile.cell_uv(Autotile.cell_for(mask))
		var pos := Vector2(x + 0.5, y + 0.5) * px
		_walls.multimesh.set_instance_transform_2d(i, Transform2D(0.0, pos))
		_walls.multimesh.set_instance_custom_data(i, Color(uv.x, uv.y, 0.0, 0.0))
		_walls.multimesh.set_instance_color(i, Color.WHITE if walls[cell] == 1 else GHOST_TINT)
		i += 1


static func _has(walls: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return walls[y * w + x] != 0


func _sync_boxes(world: SimWorld, cells: PackedInt32Array, colors: PackedColorArray) -> void:
	_boxes.multimesh.instance_count = cells.size()
	_boxes.multimesh.visible_instance_count = cells.size()
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in cells.size():
		var cell := cells[i]
		@warning_ignore("integer_division")
		var pos := Vector2(cell % world.width + 0.5, cell / world.width + 0.5) * px
		_boxes.multimesh.set_instance_transform_2d(i, Transform2D(0.0, pos))
		_boxes.multimesh.set_instance_color(i, colors[i])
