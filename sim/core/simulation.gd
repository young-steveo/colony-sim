class_name Simulation
extends RefCounted
## The sim root: owns all sim state and advances it one fixed tick at a time.
## The game layer decides when to call tick() (speed, pause); the sim itself
## has no concept of wall-clock time, rendering, or input.
##
## Player intent enters the sim as data through methods (set_command_target,
## place_blueprint, cancel_blueprint) — never by mutating state directly.

const TICKS_PER_SECOND := 30
const TICK_DT := 1.0 / TICKS_PER_SECOND
const AI_DEFS_PATH := "res://data/ai.json"

## Shared flow fields rebuild at most this often (in ticks) after their
## inputs go stale. Synchronous rebuilds cost ~125 ms each on a 256x256
## map, so they're batched; async builds are the known upgrade when
## construction becomes a core verb.
const FIELD_REBUILD_INTERVAL := 45

var world: SimWorld
var actors: ActorPool
var defs: AiDefs
var bushes: Bushes
var blueprints: Blueprints
var food_field: FlowField
var bed_field: FlowField
var blueprint_field: FlowField
var command_field: FlowField
var command_cell := -1
var tick_count := 0

var _ctx := AiContext.new()
var _bush_version_seen := 0
var _blueprint_version_seen := 0
var _structures_version_seen := 0
var _walkability_dirty := false


func _init(world_seed: int, map_width := 256, map_height := 256) -> void:
	world = SimWorld.new(world_seed, map_width, map_height)
	defs = AiDefs.load_file(AI_DEFS_PATH)
	bushes = Bushes.generate(world)
	blueprints = Blueprints.new()
	actors = ActorPool.new()
	_ctx.defs = defs
	_ctx.world = world
	_ctx.bushes = bushes
	_ctx.blueprints = blueprints
	_refresh_food_field()
	_bush_version_seen = bushes.version
	_blueprint_version_seen = blueprints.version


func spawn_actors(n: int) -> void:
	actors.spawn(world, defs, n)


func tick() -> void:
	if tick_count % FIELD_REBUILD_INTERVAL == 0:
		_refresh_stale_fields()
	_ctx.command_field = command_field
	_ctx.tick = tick_count
	actors.tick(_ctx, TICK_DT)
	# Structure completions change walkability (and bed goals); note them
	# for the next batched rebuild. Blueprints track their own version.
	if world.structures_version != _structures_version_seen:
		_structures_version_seen = world.structures_version
		_walkability_dirty = true
	tick_count += 1


## Rally every actor to a tile. Returns false (no-op) if it isn't walkable.
func set_command_target(x: int, y: int) -> bool:
	if not world.is_walkable(x, y):
		return false
	command_cell = y * world.width + x
	command_field = FlowField.build(world, PackedInt32Array([command_cell]))
	actors.rally()
	return true


## Paint a construction blueprint. Returns false if the cell can't take it.
func place_blueprint(x: int, y: int, type: int) -> bool:
	return blueprints.place(world, x, y, type)


func cancel_blueprint(x: int, y: int) -> bool:
	return blueprints.cancel(y * world.width + x)


func _refresh_stale_fields() -> void:
	if _walkability_dirty:
		# Walkability changed: every field's costs are stale.
		_walkability_dirty = false
		_refresh_food_field()
		_refresh_bed_field()
		_refresh_blueprint_field()
		if command_cell >= 0 and command_field != null:
			command_field = FlowField.build(world, PackedInt32Array([command_cell]))
		_bush_version_seen = bushes.version
		_blueprint_version_seen = blueprints.version
		return
	if bushes.version != _bush_version_seen:
		_bush_version_seen = bushes.version
		_refresh_food_field()
	if blueprints.version != _blueprint_version_seen:
		_blueprint_version_seen = blueprints.version
		_refresh_blueprint_field()


func _refresh_food_field() -> void:
	var goals := bushes.goal_cells()
	if goals.is_empty():
		food_field = null
	else:
		food_field = FlowField.build(world, goals)
	_ctx.food_field = food_field


func _refresh_bed_field() -> void:
	var goals := PackedInt32Array()
	for cell: int in world.width * world.height:
		if world.structures[cell] == SimWorld.STRUCT_BED:
			var _e: bool = goals.push_back(cell)
	if goals.is_empty():
		bed_field = null
	else:
		bed_field = FlowField.build(world, goals)
	_ctx.bed_field = bed_field


func _refresh_blueprint_field() -> void:
	var goals := blueprints.goal_cells()
	if goals.is_empty():
		blueprint_field = null
	else:
		blueprint_field = FlowField.build(world, goals)
	_ctx.blueprint_field = blueprint_field