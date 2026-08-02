class_name Simulation
extends RefCounted
## The sim root: owns all sim state and advances it one fixed tick at a time.
## The game layer decides when to call tick() (speed, pause); the sim itself
## has no concept of wall-clock time, rendering, or input.
##
## Player intent enters the sim as data through methods (set_move_order,
## place_blueprint, cancel_blueprint) — never by mutating state directly.

const TICKS_PER_SECOND := 30
const TICK_DT := 1.0 / TICKS_PER_SECOND
const AI_DEFS_PATH := "res://content/actors/ai.json"

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
var structure_defs: StructureDefs
var terrain_defs: TerrainDefs
var item_defs: ItemDefs
var bushes: Bushes
var trees: Trees
var items: Items
var blueprints: Blueprints
var food_field: FlowField
var bed_field: FlowField
var blueprint_field: FlowField
var chop_field: FlowField
var wood_field: FlowField
var haul_field: FlowField
var tick_count := 0

var _ctx := AiContext.new()
var _bush_version_seen := 0
var _tree_version_seen := 0
var _item_version_seen := 0
var _blueprint_version_seen := 0
var _structures_version_seen := 0
var _walkability_dirty := false
var _build_action_idx := -1
var _jobs: Dictionary = {}  # StringName -> _FieldJob in flight
# Superseded jobs whose results will be dropped. Their tasks must STILL
# be waited on — WorkerThreadPool only frees a task's record and its
# captured data at wait_for_task_completion (documented requirement) —
# so they queue here and are reaped once their threads finish.
var _zombie_jobs: Array[_FieldJob] = []


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
	terrain_defs = TerrainDefs.load_defs()
	world = SimWorld.new(world_seed, map_width, map_height, terrain_defs)
	defs = AiDefs.load_file(AI_DEFS_PATH)
	structure_defs = StructureDefs.load_defs()
	item_defs = ItemDefs.load_defs()
	bushes = Bushes.generate(world)
	trees = Trees.generate(world)
	items = Items.new(item_defs)
	blueprints = Blueprints.new(structure_defs)
	actors = ActorPool.new()
	_ctx.defs = defs
	_ctx.world = world
	_ctx.bushes = bushes
	_ctx.trees = trees
	_ctx.items = items
	_ctx.blueprints = blueprints
	_build_action_idx = defs.action_index(&"build")
	# World load is the one synchronous field build — nothing is running yet.
	food_field = FlowField.build(world, bushes.goal_cells())
	_ctx.food_field = food_field
	_bush_version_seen = bushes.version
	_tree_version_seen = trees.version
	_item_version_seen = items.goals_version
	_blueprint_version_seen = blueprints.goals_version


func spawn_actors(n: int) -> void:
	actors.spawn(world, defs, n)


func tick() -> void:
	_install_due_fields()
	if tick_count % FIELD_REBUILD_INTERVAL == 0:
		_dispatch_stale_fields()
	blueprints.reset_workers()
	trees.reset_workers()
	_ctx.build_capacity = blueprints.frontier_count(world)
	_ctx.builder_distances = _collect_builder_distances()
	_ctx.occupied.clear()
	for i: int in actors.count:
		var p := actors.positions[i]
		_ctx.occupied[floori(p.y) * world.width + floori(p.x)] = true
		# A claimed work stance is reserved ground: nobody else plants
		# there, and nothing is built on it while its worker walks in.
		if actors.work_spots[i] >= 0:
			_ctx.occupied[actors.work_spots[i]] = true
	_ctx.tick = tick_count
	actors.tick(_ctx, TICK_DT)
	# Structure completions change walkability (and bed goals); note them
	# for the next batched rebuild. Blueprints track their own version.
	if world.structures_version != _structures_version_seen:
		_structures_version_seen = world.structures_version
		_walkability_dirty = true
	tick_count += 1


## Order one settler to a tile (plans-vs-orders: THIS is the first true
## order). It is a heavy consideration in the settler's own scoring pass,
## not a command bypass — a dire need can still outbid it, legibly. A new
## order replaces the old one. Returns false for unknown settlers and
## unwalkable or out-of-bounds targets: the sim's intent surface is
## defensive no matter which caller holds the mouse.
func set_move_order(settler_id: int, x: int, y: int) -> bool:
	var i := actors.ids.find(settler_id)
	if i < 0:
		return false
	if x < 0 or y < 0 or x >= world.width or y >= world.height:
		return false
	if not world.is_walkable(x, y):
		return false
	actors.set_order(i, y * world.width + x)
	return true


func cancel_move_order(settler_id: int) -> bool:
	var i := actors.ids.find(settler_id)
	if i < 0 or actors.order_cells[i] < 0:
		return false
	actors.clear_order(i)
	return true


## Paint a construction blueprint. Returns false if the cell can't take
## it. Trees block construction: you clear the forest before you build
## in it (the material cycle asserting itself).
func place_blueprint(x: int, y: int, type: int, material: int = 0) -> bool:
	if trees.has_tree_at(y * world.width + x):
		return false
	return blueprints.place(world, x, y, type, material)


## Cancelling refunds any delivered materials as ground items where the
## ghost stood — hauled wood never vanishes into an undo.
func cancel_blueprint(x: int, y: int) -> bool:
	var cell := y * world.width + x
	var refund := blueprints.delivered_at(cell)
	if not blueprints.cancel(cell):
		return false
	if refund > 0:
		items.scatter(world, cell, Items.WOOD, refund)
	return true


## Plan the tree at this cell for chopping (plans-vs-orders: this is a
## plan — standing intent any settler may act on).
func designate_chop(x: int, y: int) -> bool:
	return trees.designate(y * world.width + x)


func cancel_chop(x: int, y: int) -> bool:
	return trees.cancel_designation(y * world.width + x)


func _collect_builder_distances() -> PackedInt32Array:
	var out := PackedInt32Array()
	if blueprint_field == null:
		return out
	for i: int in actors.count:
		if actors.current_action[i] != _build_action_idx:
			continue
		var p := actors.positions[i]
		var d := blueprint_field.distances[floori(p.y) * world.width + floori(p.x)]
		if d != FlowField.UNREACHABLE:
			var _e: bool = out.push_back(d)
	out.sort()
	return out


func _dispatch_stale_fields() -> void:
	if _walkability_dirty:
		# Walkability changed: every field's costs are stale.
		_walkability_dirty = false
		_bush_version_seen = bushes.version
		_tree_version_seen = trees.version
		_item_version_seen = items.goals_version
		_blueprint_version_seen = blueprints.goals_version
		_dispatch_field(&"food", bushes.goal_cells())
		_dispatch_field(&"bed", _bed_goals())
		_dispatch_blueprint_field()
		_dispatch_field(&"chop", trees.plan_goals())
		_dispatch_field(&"wood", items.goal_cells())
		return
	if bushes.version != _bush_version_seen:
		_bush_version_seen = bushes.version
		_dispatch_field(&"food", bushes.goal_cells())
	if trees.version != _tree_version_seen:
		_tree_version_seen = trees.version
		_dispatch_field(&"chop", trees.plan_goals())
	if items.goals_version != _item_version_seen:
		_item_version_seen = items.goals_version
		_dispatch_field(&"wood", items.goal_cells())
	if blueprints.goals_version != _blueprint_version_seen:
		_blueprint_version_seen = blueprints.goals_version
		_dispatch_blueprint_field()


## Blueprint changes drive two fields: builders travel to the buildable
## frontier; haulers travel to anything still owed materials.
func _dispatch_blueprint_field() -> void:
	_dispatch_field(&"blueprint", blueprints.frontier_goals(world))
	_dispatch_field(&"haul", blueprints.delivery_goals())


func _bed_goals() -> PackedInt32Array:
	var goals := PackedInt32Array()
	for cell: int in world.width * world.height:
		if world.structures[cell] == SimWorld.STRUCT_BED:
			var _e: bool = goals.push_back(cell)
	return goals


## Snapshot inputs and start a worker-thread build; the result installs at
## a fixed future tick. A re-dispatch for a kind already in flight retires
## the pending job to the zombie queue (its task still runs; the result is
## dropped, but the task is always waited on eventually).
func _dispatch_field(kind: StringName, goals: PackedInt32Array) -> void:
	_retire_job(kind)
	if goals.is_empty():
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
	# Reap superseded jobs whose threads have finished. Non-blocking (a
	# still-running orphan just waits for a later pass) and touches no
	# sim state, so thread timing stays unobservable — the fixed-latency
	# determinism contract is untouched.
	var z := _zombie_jobs.size() - 1
	while z >= 0:
		if WorkerThreadPool.is_task_completed(_zombie_jobs[z].task_id):
			var _zerr: int = WorkerThreadPool.wait_for_task_completion(_zombie_jobs[z].task_id)
			_zombie_jobs.remove_at(z)
		z -= 1
	for kind: StringName in _jobs.keys():
		var job: _FieldJob = _jobs[kind]
		if tick_count < job.install_tick:
			continue
		var _err: int = WorkerThreadPool.wait_for_task_completion(job.task_id)
		var _e: bool = _jobs.erase(kind)
		_install_field(kind, job.result)


## Pull a kind's in-flight job (if any) off the active map into the
## zombie queue. The worker thread keeps running; only its result is
## abandoned.
func _retire_job(kind: StringName) -> void:
	var old: _FieldJob = _jobs.get(kind)
	if old != null:
		_zombie_jobs.push_back(old)
		var _e: bool = _jobs.erase(kind)


## Every outstanding worker task, active or zombie, blocking-waited and
## dropped. Call before discarding a Simulation (world regen, quit) —
## the pool cannot free a task that was never waited on.
func shutdown() -> void:
	for kind: StringName in _jobs:
		var _e1: int = WorkerThreadPool.wait_for_task_completion(_jobs[kind].task_id)
	_jobs.clear()
	for zj: _FieldJob in _zombie_jobs:
		var _e2: int = WorkerThreadPool.wait_for_task_completion(zj.task_id)
	_zombie_jobs.clear()


## Worker tasks not yet waited on (in flight + superseded). Debug/test
## surface: bounded in steady state; shutdown() drives it to zero.
func pending_task_count() -> int:
	return _jobs.size() + _zombie_jobs.size()


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
		&"chop":
			chop_field = field
			_ctx.chop_field = field
		&"wood":
			wood_field = field
			_ctx.wood_field = field
		&"haul":
			haul_field = field
			_ctx.haul_field = field