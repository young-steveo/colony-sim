class_name CarryRenderer
extends MultiMeshInstance2D
## Placeholder carried-cargo overlay: a small quad riding above any pawn
## with something in hand — "she's bringing wood home" readable from
## across the map. First use of the tile-stack hands mount; becomes real
## sprite work with the carry-animation pass.

const CARGO_SIZE := Vector2(8.0, 4.0)
const HEAD_OFFSET := Vector2(0.0, -14.0)
var _defs: ItemDefs
var _capacity := 0


func setup(defs: ItemDefs) -> void:
	_defs = defs
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = CARGO_SIZE
	multimesh.mesh = quad


func sync(actors: ActorPool, alpha: float, zoom: float) -> void:
	if actors.count > _capacity:
		_capacity = maxi(actors.count, maxi(_capacity * 2, 256))
		multimesh.instance_count = _capacity
	var px := float(TerrainRenderer.TILE_PX)
	var shown := 0
	for i: int in actors.count:
		if actors.carry_count[i] <= 0:
			continue
		var p := actors.prev_positions[i].lerp(actors.positions[i], alpha) * px
		var snapped := ((p + HEAD_OFFSET) * zoom).round() / zoom
		multimesh.set_instance_transform_2d(shown, Transform2D(0.0, snapped))
		multimesh.set_instance_color(shown, _defs.colors[actors.carry_type[i]])
		shown += 1
	multimesh.visible_instance_count = shown
