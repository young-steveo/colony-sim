class_name Simulation
extends RefCounted
## The sim root: owns all sim state and advances it one fixed tick at a time.
## The game layer decides when to call tick() (speed, pause); the sim itself
## has no concept of wall-clock time, rendering, or input.
##
## Player intent enters the sim as data through methods like
## set_command_target() — a first taste of director mode: actors respond to
## the command but remain autonomous (they revert to their own decisions on
## arrival).

const TICKS_PER_SECOND := 30
const TICK_DT := 1.0 / TICKS_PER_SECOND
const AI_DEFS_PATH := "res://data/ai.json"

var world: SimWorld
var actors: ActorPool
var defs: AiDefs
var bushes: Bushes
var food_field: FlowField
var command_field: FlowField
var command_cell := -1
var tick_count := 0

var _ctx := AiContext.new()
var _bush_version_seen := 0


func _init(world_seed: int, map_width := 256, map_height := 256) -> void:
	world = SimWorld.new(world_seed, map_width, map_height)
	defs = AiDefs.load_file(AI_DEFS_PATH)
	bushes = Bushes.generate(world)
	actors = ActorPool.new()
	_ctx.defs = defs
	_ctx.world = world
	_ctx.bushes = bushes
	_refresh_food_field()


func spawn_actors(n: int) -> void:
	actors.spawn(world, defs, n)


func tick() -> void:
	if bushes.version != _bush_version_seen:
		_refresh_food_field()
	_ctx.command_field = command_field
	_ctx.tick = tick_count
	actors.tick(_ctx, TICK_DT)
	tick_count += 1


## Rally every actor to a tile. Returns false (no-op) if it isn't walkable.
## Builds one shared flow field; ~125 ms on a 256x256 map, so a click costs
## a few frames — fine for a debug verb, async build when it's a real one.
func set_command_target(x: int, y: int) -> bool:
	if not world.is_walkable(x, y):
		return false
	command_cell = y * world.width + x
	command_field = FlowField.build(world, PackedInt32Array([command_cell]))
	actors.rally()
	return true


func _refresh_food_field() -> void:
	_bush_version_seen = bushes.version
	var goals := bushes.goal_cells()
	if goals.is_empty():
		food_field = null
	else:
		food_field = FlowField.build(world, goals)
	_ctx.food_field = food_field
