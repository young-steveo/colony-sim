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

## Shared flow fields rebuild asynchronously on worker threads under a
## fixed-latency contract: a rebuild dispatched at tick T is installed at
## exactly T + FIELD_ASYNC_TICKS, whatever the thread timing was (the main
## thread blocks at the install tick in the rare case the worker isn't
## done). Fixed latency keeps the sim bit-deterministic — thread speed can
## never influence sim state. Movement legality never comes from fields
## (every step checks live walkability), so stale fields are safe by
## construction.
const FIELD_REBUILD_INTERVAL := 15  # how often dirt is collected into jobs
const FIELD_ASYNC_TICKS := 45  # dispatch-to-install latency

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
var _build_action_idx := -1
var _frontier_count := 0
var _jobs: Dictionary = {}  # StringName -> _FieldJob in flight


class _FieldJob:
	extends RefCounted
	var task_id := -1
	var install_tick := 0
	var width := 0
	var height := 0
	var walk := PackedByteArray()
	var goals := PackedInt32Array()
	var result: FlowField

	func run() -> void:
		result = FlowField.build_from_walk(width, height, walk, goals)


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
	_build_action_idx = defs.action_index(&"build")
	# World load is the one synchronous field build — nothing is running yet.
	food_field = FlowField.build(world, bushes.goal_cells())
	_ctx.food_field = food_field
	_bush_version_seen = bushes.version
	_blueprint_version_seen = blueprints.version


func spawn_actors(n: int) -> void:
	actors.spawn(world, defs, n)


func tick() -> void:
	_install_due_fields()
	if tick_count % FIELD_REBUILD_INTERVAL == 0:
		_dispatch_stale_fields()
	blueprints.reset_workers()
	_ctx.build_workers = _count_build_workers()
	_ctx.build_capacity = _frontier_count
	_ctx.occupied.clear()
	for i: int in actors.count:
		var p := actors.positions[i]
		_ctx.occupied[floori(p.y) * world.width + floori(p.x)] = true
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
## The field builds asynchronously; actors answer once it installs.
func set_command_target(x: int, y: int) -> bool:
	if not world.is_walkable(x, y):
		return false
	command_cell = y * world.width + x
	_dispatch_field(&"command", PackedInt32Array([command_cell]))
	actors.rally()
	return true


## Paint a construction blueprint. Returns false if the cell can't take it.
func place_blueprint(x: int, y: int, type: int) -> bool:
	return blueprints.place(world, x, y, type)


func cancel_blueprint(x: int, y: int) -> bool:
	return blueprints.cancel(y * world.width + x)


func _count_build_workers() -> int:
	var n := 0
	for i: int in actors.count:
		if actors.current_action[i] == _build_action_idx:
			n += 1
	return n


func _dispatch_stale_fields() -> void:
	if _walkability_dirty:
		# Walkability changed: every field's costs are stale.
		_walkability_dirty = false
		_bush_version_seen = bushes.version
		_blueprint_version_seen = blueprints.version
		_dispatch_field(&"food", bushes.goal_cells())
		_dispatch_field(&"bed", _bed_goals())
		_dispatch_blueprint_field()
		if command_cell >= 0:
			_dispatch_field(&"command", PackedInt32Array([command_cell]))
		return
	if bushes.version != _bush_version_seen:
		_bush_version_seen = bushes.version
		_dispatch_field(&"food", bushes.goal_cells())
	if blueprints.version != _blueprint_version_seen:
		_blueprint_version_seen = blueprints.version
		_dispatch_blueprint_field()


func _dispatch_blueprint_field() -> void:
	var frontier := blueprints.frontier_goals(world)
	_frontier_count = frontier.size()
	_dispatch_field(&"blueprint", frontier)


func _bed_goals() -> PackedInt32Array:
	var goals := PackedInt32Array()
	for cell: int in world.width * world.height:
		if world.structures[cell] == SimWorld.STRUCT_BED:
			var _e: bool = goals.push_back(cell)
	return goals


## Snapshot inputs and start a worker-thread build; the result installs at
## a fixed future tick. A re-dispatch for a kind already in flight simply
## replaces the pending job (its task still runs; the result is dropped).
func _dispatch_field(kind: StringName, goals: PackedInt32Array) -> void:
	if goals.is_empty():
		var _e: bool = _jobs.erase(kind)
		_install_field(kind, null)
		return
	var job := _FieldJob.new()
	job.width = world.width
	job.height = world.height
	job.walk = world.walkability_snapshot()
	job.goals = goals
	job.install_tick = tick_count + FIELD_ASYNC_TICKS
	job.task_id = WorkerThreadPool.add_task(job.run, false, "flow field: %s" % kind)
	_jobs[kind] = job


func _install_due_fields() -> void:
	for kind: StringName in _jobs.keys():
		var job: _FieldJob = _jobs[kind]
		if tick_count < job.install_tick:
			continue
		var _err: int = WorkerThreadPool.wait_for_task_completion(job.task_id)
		var _e: bool = _jobs.erase(kind)
		_install_field(kind, job.result)


func _install_field(kind: StringName, field: FlowField) -> void:
	match kind:
		&"food":
			food_field = field
			_ctx.food_field = field
		&"bed":
			bed_field = field
			_ctx.bed_field = field
		&"blueprint":
			blueprint_field = field
			_ctx.blueprint_field = field
		&"command":
			command_field = field
			_ctx.command_field = field