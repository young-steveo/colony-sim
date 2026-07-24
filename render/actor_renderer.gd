class_name ActorRenderer
extends MultiMeshInstance2D
## Renders the whole actor pool through one MultiMesh — one draw call, no
## per-actor nodes. Positions interpolate between the last two sim ticks so
## movement stays smooth regardless of sim tick rate.

# Character proportion: 1 tile wide, 1.5 tall (16x24 on the 16px grid),
# anchored at the feet — the sim position is ground contact. 16x32 towered
# over 16px walls; 24 keeps heads above the parapet without stilts.
const ACTOR_SIZE := Vector2(16.0, 24.0)

var _capacity := 0
var _world_seed := 0


func setup(world_seed: int) -> void:
	_world_seed = world_seed
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = ACTOR_SIZE
	multimesh.mesh = quad
	_capacity = 0


func sync(actors: ActorPool, alpha: float) -> void:
	if actors.count > _capacity:
		_grow(actors)
	multimesh.visible_instance_count = actors.count
	var px := float(TerrainRenderer.TILE_PX)
	var feet_offset := Vector2(0.0, -ACTOR_SIZE.y * 0.5)
	for i: int in actors.count:
		var p := actors.prev_positions[i].lerp(actors.positions[i], alpha) * px
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, p + feet_offset))


func _grow(actors: ActorPool) -> void:
	# Resizing instance_count clears instance data, so recolor everything.
	_capacity = maxi(actors.count, maxi(_capacity * 2, 256))
	multimesh.instance_count = _capacity
	for i: int in actors.count:
		multimesh.set_instance_color(i, _actor_color(actors.ids[i]))


# Vivid Palette entries that pop against terrain.
static var ACTOR_TINTS := PackedInt32Array([
	12, 13, 16, 17, 18, 22, 23, 26, 27, 31,
	32, 41, 42, 47, 48, 51, 52, 56, 57, 60, 61, 62,
])


func _actor_color(id: int) -> Color:
	var s := SimRng.stream(SimRng.key([_world_seed, "actor_color", id]))
	return Palette.COLORS[ACTOR_TINTS[s.next_range(0, ACTOR_TINTS.size() - 1)]]
