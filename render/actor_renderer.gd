class_name ActorRenderer
extends MultiMeshInstance2D
## Renders the whole actor pool through one MultiMesh — one draw call, no
## per-actor nodes. Positions interpolate between the last two sim ticks so
## movement stays smooth regardless of sim tick rate.

const ACTOR_PX := 10.0

var _capacity := 0
var _world_seed := 0


func setup(world_seed: int) -> void:
	_world_seed = world_seed
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(ACTOR_PX, ACTOR_PX)
	multimesh.mesh = quad
	_capacity = 0


func sync(actors: ActorPool, alpha: float) -> void:
	if actors.count > _capacity:
		_grow(actors)
	multimesh.visible_instance_count = actors.count
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in actors.count:
		var p := actors.prev_positions[i].lerp(actors.positions[i], alpha) * px
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, p))


func _grow(actors: ActorPool) -> void:
	# Resizing instance_count clears instance data, so recolor everything.
	_capacity = maxi(actors.count, maxi(_capacity * 2, 256))
	multimesh.instance_count = _capacity
	for i: int in actors.count:
		multimesh.set_instance_color(i, _actor_color(actors.ids[i]))


func _actor_color(id: int) -> Color:
	var s := SimRng.stream(SimRng.key([_world_seed, "actor_color", id]))
	return Color.from_hsv(s.nextf(), 0.35 + 0.3 * s.nextf(), 0.75 + 0.2 * s.nextf())
