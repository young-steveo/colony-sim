class_name ActorRenderer
extends MultiMeshInstance2D
## Renders the whole actor pool through one MultiMesh — one draw call, no
## per-actor nodes. Positions interpolate between the last two sim ticks so
## movement stays smooth regardless of sim tick rate. Body frames come from
## the base spritesheet; facing and walk phase are render-side state derived
## from sim movement — the sim knows nothing about animation.

# Chibi verdict (July 2026): the whole body fits one 16x16 tile, anchored at
# the feet — the sim position is ground contact. Customization layers may
# later overhang the square; the base body never does.
const ACTOR_SIZE := Vector2(16.0, 16.0)

# Named drift (content/README.md, data-audit commitment): sheet path and
# frame map are hardcoded until the actor pipeline goes data-driven.
const BODY_SHEET := preload("res://content/actors/body/actor-base.png")
const BODY_SHADER := preload("res://render/actor_body.gdshader")
const SHEET_COLS := 8
const SHEET_ROWS := 4
const WALK_FRAMES := 4
# One full walk cycle per tile of ground covered; retune by eye if it reads
# like skating or scurrying.
const CYCLE_FRAMES_PER_TILE := 4.0

# Sheet convention (GDD art verdict): row 0 = south | north, row 1 = east |
# west, 4 frames each. Indexed by the FACING_* constants below.
const FACING_CELLS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 1), Vector2i(4, 1),
]
const FACING_S := 0
const FACING_N := 1
const FACING_E := 2
const FACING_W := 3

var _capacity := 0
var _facing := PackedInt32Array()
var _cycle := PackedFloat32Array()  # tiles traveled; drives the walk frame
var _last_px := PackedVector2Array()  # previous sync's interpolated position


func setup(_world_seed: int) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = BODY_SHEET
	var mat := ShaderMaterial.new()
	mat.shader = BODY_SHADER
	material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = ACTOR_SIZE
	multimesh.mesh = quad
	_capacity = 0
	_facing = PackedInt32Array()
	_cycle = PackedFloat32Array()
	_last_px = PackedVector2Array()


func sync(actors: ActorPool, alpha: float, zoom: float) -> void:
	if actors.count > _capacity:
		_grow(actors)
	multimesh.visible_instance_count = actors.count
	var px := float(TerrainRenderer.TILE_PX)
	var feet_offset := Vector2(0.0, -ACTOR_SIZE.y * 0.5)
	var cell_uv := Vector2(1.0 / SHEET_COLS, 1.0 / SHEET_ROWS)
	for i: int in actors.count:
		var p := actors.prev_positions[i].lerp(actors.positions[i], alpha) * px
		# Snap to the screen-pixel grid (not whole world pixels): texels stay
		# uniform on screen, while motion steps by one screen pixel — smooth
		# to the eye instead of chunky world-pixel pops.
		var snapped := ((p + feet_offset) * zoom).round() / zoom
		multimesh.set_instance_transform_2d(i, Transform2D(0.0, snapped))
		var vel := actors.positions[i] - actors.prev_positions[i]
		var frame := 0
		if vel.length_squared() > 0.000001:
			if absf(vel.x) >= absf(vel.y):
				_facing[i] = FACING_E if vel.x > 0.0 else FACING_W
			else:
				_facing[i] = FACING_S if vel.y > 0.0 else FACING_N
			_cycle[i] += p.distance_to(_last_px[i]) / px
			frame = int(_cycle[i] * CYCLE_FRAMES_PER_TILE) % WALK_FRAMES
		_last_px[i] = p
		var cell := FACING_CELLS[_facing[i]]
		var uv := Vector2(float(cell.x + frame), float(cell.y)) * cell_uv
		multimesh.set_instance_custom_data(i, Color(uv.x, uv.y, 0.0, 0.0))


func _grow(actors: ActorPool) -> void:
	# Resizing instance_count clears per-instance data; transforms and frames
	# are rewritten every sync, so only our side arrays need care.
	_capacity = maxi(actors.count, maxi(_capacity * 2, 256))
	multimesh.instance_count = _capacity
	var old := _facing.size()
	var _e1: int = _facing.resize(_capacity)
	var _e2: int = _cycle.resize(_capacity)
	var _e3: int = _last_px.resize(_capacity)
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in range(old, actors.count):
		_last_px[i] = actors.positions[i] * px
