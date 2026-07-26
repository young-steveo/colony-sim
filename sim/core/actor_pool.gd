class_name ActorPool
extends RefCounted
## All actors, structure-of-arrays style: parallel packed arrays indexed by
## actor slot, ticked in one tight loop by the sim. No per-actor objects, no
## per-actor _process.
##
## Behavior = utility AI (see AiDefs for the scoring model). Decisions are
## staggered — each pawn re-decides every DECIDE_INTERVAL ticks, offset by
## its id, plus immediately when its current action completes — and are
## recorded per pawn in last_scores so the inspection panel can always
## answer "what is this pawn doing and why" (the legibility contract).
##
## A player rally command (responding == 1) overrides the brain until
## arrival — director-mode-lite; later, orders become heavy considerations
## inside the same scoring pass instead of a bypass.
##
## ACTIVITY MACHINES (GDD Architecture Commitments): the brain owns
## transitions BETWEEN activities; an activity owns transitions WITHIN
## itself. Each execution is a small phase machine — enter via
## _start_action, tick returns ACT_RUNNING/ACT_DONE/ACT_FAILED, and every
## way out (completion, failure, preemption, rally, rescue) releases pawn
## state through the single exit hook (_exit_action). An activity may
## finish itself (its success criterion can read the need it restores) but
## it never weighs alternatives — "should this pawn be doing something
## else" is solely the brain's question. The moment a phase transition
## starts reading needs, the brain has leaked into the body: stop.

const ARRIVE_DISTANCE := 0.05
# Wandering is a stroll, not a random walk: legs keep roughly the current
# heading (bounded steering turns, never a snap reversal unless walls force
# one), pawns pause between legs, and they amble below task speed.
const WANDER_LEG_MIN := 2.0
const WANDER_LEG_MAX := 6.0
const WANDER_TURN := PI * 0.45  # typical steering range per leg (~±81°)
const WANDER_PAUSE_CHANCE := 0.55
const WANDER_PAUSE_MIN_TICKS := 30  # 1 s at 30 tps
const WANDER_PAUSE_MAX_TICKS := 150
const WANDER_SPEED_SCALE := 0.6
const JITTER := 0.35
const DECIDE_INTERVAL := 15
const COMMITMENT_BONUS := 1.1
# A higher-bucket action must clear this to preempt lower buckets. Tuned so
# an eating pawn keeps its meal until roughly three-quarters fed instead of
# wandering off after two bites.
const BUCKET_CUTOFF := 0.15
const NO_ACTION := -1

# Activity outcomes: every activity tick returns one of these. RUNNING
# keeps the pawn; anything else ends the activity through the exit hook
# (FAILED is DONE that couldn't finish — same cleanup, different story).
const ACT_RUNNING := 0
const ACT_DONE := 1
const ACT_FAILED := 2

# Activity phases. The enter hook picks the starting phase; phase names
# surface in the inspection panel via phase_label (legibility contract).
const WANDER_WAIT := 0
const WANDER_STROLL := 1
const EAT_GOTO := 0
const EAT_CONSUME := 1
const BEDREST_GOTO := 0
const BEDREST_SLEEP := 1
const BUILD_TRAVEL := 0
const BUILD_WORK := 1
const CHOP_TRAVEL := 0
const CHOP_WORK := 1
const HAUL_FETCH := 0
const HAUL_DELIVER := 1
const PHASE_NAMES := {
	&"eat": ["goto", "consume"],
	&"sleep": ["sleep"],
	&"sleep_bed": ["goto", "sleep"],
	&"build": ["travel", "work"],
	&"wander": ["wait", "stroll"],
	&"chop": ["travel", "chop"],
	&"haul": ["fetch", "deliver"],
}

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var prev_positions := PackedVector2Array()
var targets := PackedVector2Array()
var speeds := PackedFloat32Array()
var responding := PackedByteArray()
var decision_counts := PackedInt32Array()
var jitter := PackedVector2Array()
var current_action := PackedInt32Array()
var phase := PackedInt32Array()  # phase within the current activity
var phase_timer := PackedInt32Array()  # scratch timer; resets on phase change
var build_claims := PackedInt32Array()  # blueprint cell being worked, or -1
var work_cooldowns := PackedInt32Array()  # no work re-pick until this tick (build/chop/haul)
var carry_type := PackedInt32Array()  # item type in hands, or -1
var carry_count := PackedInt32Array()  # how many of it
var headings := PackedFloat32Array()  # stroll direction, persists across legs
var needs: Array[PackedFloat32Array] = []
var last_scores := PackedFloat32Array()  # count * n_actions, row per pawn

var _spawned_total := 0
var _n_actions := 0
var _n_needs := 0


func spawn(world: SimWorld, defs: AiDefs, n: int) -> void:
	if needs.is_empty():
		_n_actions = defs.actions.size()
		_n_needs = defs.needs.size()
		for nd: int in _n_needs:
			needs.append(PackedFloat32Array())
	var new_count := count + n
	var _e1: int = ids.resize(new_count)
	var _e2: int = positions.resize(new_count)
	var _e3: int = prev_positions.resize(new_count)
	var _e4: int = targets.resize(new_count)
	var _e5: int = speeds.resize(new_count)
	var _e6: int = responding.resize(new_count)
	var _e7: int = decision_counts.resize(new_count)
	var _e8: int = jitter.resize(new_count)
	var _e9: int = current_action.resize(new_count)
	var _e10: int = phase.resize(new_count)
	var _e11: int = last_scores.resize(new_count * _n_actions)
	var _e13: int = build_claims.resize(new_count)
	var _e14: int = work_cooldowns.resize(new_count)
	var _e17: int = carry_type.resize(new_count)
	var _e18: int = carry_count.resize(new_count)
	var _e15: int = headings.resize(new_count)
	var _e16: int = phase_timer.resize(new_count)
	for nd: int in _n_needs:
		var _e12: int = needs[nd].resize(new_count)
	for i: int in range(count, new_count):
		var id := _spawned_total
		_spawned_total += 1
		var s := SimRng.stream(SimRng.key([world.world_seed, "spawn", id]))
		# The colony starts as a knot at the map's heart: pawn id takes the
		# id-th walkable cell scanning outward from the center, so spawns
		# cluster on screen (the camera opens there) without stacking.
		var cell := _center_spawn_cell(world, id)
		var pos := Vector2(cell) + Vector2(0.5, 0.5)
		ids[i] = id
		positions[i] = pos
		prev_positions[i] = pos
		targets[i] = pos
		speeds[i] = 2.0 + 2.0 * s.nextf()
		responding[i] = 0
		decision_counts[i] = 0
		jitter[i] = Vector2((s.nextf() - 0.5) * JITTER, (s.nextf() - 0.5) * JITTER)
		current_action[i] = NO_ACTION
		phase[i] = 0
		phase_timer[i] = 0
		build_claims[i] = -1
		work_cooldowns[i] = 0
		carry_type[i] = -1
		carry_count[i] = 0
		headings[i] = s.nextf() * TAU
		for nd: int in _n_needs:
			# Staggered starting levels so the colony doesn't eat and sleep
			# in lockstep.
			needs[nd][i] = clampf(defs.needs[nd].start * (0.7 + 0.3 * s.nextf()), 0.05, 1.0)
	count = new_count


## A rally command exists: everyone answers the call. Rallying is an
## interruption like any other — the current activity exits cleanly (a
## carrying hauler drops the log where they stand and runs; the pile is
## the story of the interruption).
func rally(ctx: AiContext) -> void:
	for i: int in count:
		responding[i] = 1
		_stop_action(ctx, i)


func need_value(need_idx: int, i: int) -> float:
	return needs[need_idx][i]


func tick(ctx: AiContext, dt: float) -> void:
	for nd: int in _n_needs:
		var drain := ctx.defs.needs[nd].drain_per_second * dt
		if drain > 0.0:
			var arr := needs[nd]
			for i: int in count:
				arr[i] = maxf(arr[i] - drain, 0.0)

	for i: int in count:
		prev_positions[i] = positions[i]
		_rescue_if_stuck(ctx, i)
		if responding[i] == 1 and ctx.command_field != null:
			_tick_rally(ctx, i, dt)
			continue
		if current_action[i] == NO_ACTION or (ctx.tick + ids[i]) % DECIDE_INTERVAL == 0:
			_decide(ctx, i)
		var action := ctx.defs.actions[current_action[i]]
		var outcome := ACT_RUNNING
		match action.execution:
			&"eat":
				outcome = _eat_tick(ctx, i, action, dt)
			&"sleep":
				outcome = _sleep_tick(ctx, i, action, dt)
			&"sleep_bed":
				outcome = _sleep_bed_tick(ctx, i, action, dt)
			&"build":
				outcome = _build_tick(ctx, i, dt)
			&"wander":
				outcome = _wander_tick(ctx, i, dt)
			&"chop":
				outcome = _chop_tick(ctx, i, dt)
			&"haul":
				outcome = _haul_tick(ctx, i, dt)
		if outcome != ACT_RUNNING:
			_stop_action(ctx, i)  # re-decide next tick


# --- decision -------------------------------------------------------------


func _decide(ctx: AiContext, i: int) -> void:
	var row := i * _n_actions
	for a: int in _n_actions:
		var action := ctx.defs.actions[a]
		var is_work := action.execution == &"build" or action.execution == &"chop" \
				or action.execution == &"haul"
		if is_work and ctx.tick < work_cooldowns[i]:
			# Recently blocked or crowded out: sit this one out briefly so
			# stale-field churn doesn't freeze pawns mid-route.
			last_scores[row + a] = 0.0
			continue
		var product := 1.0
		for con: AiDefs.ConsiderationDef in action.considerations:
			product *= con.score(_input_value(ctx, i, con))
			if product == 0.0:
				break
		var score := action.weight * AiDefs.compensate(product, action.considerations.size())
		if a == current_action[i]:
			score *= COMMITMENT_BONUS
		last_scores[row + a] = score

	# Highest bucket whose best score clears the cutoff wins; the lowest
	# bucket (with its constant-utility idle) always resolves.
	var chosen := NO_ACTION
	var lowest: int = ctx.defs.bucket_order[ctx.defs.bucket_order.size() - 1]
	for bucket: int in ctx.defs.bucket_order:
		var best := NO_ACTION
		var best_score := 0.0
		for a: int in _n_actions:
			if ctx.defs.actions[a].bucket != bucket:
				continue
			if last_scores[row + a] > best_score:
				best_score = last_scores[row + a]
				best = a
		if best != NO_ACTION and (best_score >= BUCKET_CUTOFF or bucket == lowest):
			chosen = best
			break
	if chosen != current_action[i]:
		# Preemption is the brain's right, but the losing activity always
		# gets its exit — claims and phase state never leak across.
		if current_action[i] != NO_ACTION:
			_exit_action(ctx, i)
		_start_action(ctx, i, chosen)


func _input_value(ctx: AiContext, i: int, con: AiDefs.ConsiderationDef) -> float:
	if con.need_idx >= 0:
		return needs[con.need_idx][i]
	match con.input:
		&"food_distance":
			return _field_distance(ctx, i, ctx.food_field)
		&"bed_distance":
			return _field_distance(ctx, i, ctx.bed_field)
		&"blueprint_distance":
			return _field_distance(ctx, i, ctx.blueprint_field)
		&"chop_distance":
			return _field_distance(ctx, i, ctx.chop_field)
		&"wood_distance":
			# Wood already in hand is wood at distance zero — otherwise a
			# mid-carry re-decide with no ground stacks left would veto
			# haul and drop the last load en route.
			if carry_count[i] > 0:
				return 0.0
			return _field_distance(ctx, i, ctx.wood_field)
		&"haul_target_distance":
			return _field_distance(ctx, i, ctx.haul_field)
		&"build_crowding":
			# Proximity-ranked crowding: of the builders currently
			# assigned, how many are CLOSER to the work than me, against
			# the number of workable frontier jobs? The nearest pawns
			# always rank 0 and take the job; a distant traveler sees
			# closer pawns saturating capacity and drops out. (Assignment
			# order alone let far pawns grab slots while the pawn beside
			# the site wandered.) Strict less-than self-excludes: my own
			# recorded distance equals mine.
			if ctx.build_capacity == 0 or ctx.blueprint_field == null:
				return 1.0
			var my_dist := ctx.blueprint_field.distances[_cell_of(ctx.world, positions[i])]
			if my_dist == FlowField.UNREACHABLE:
				return 1.0
			var closer := 0
			for bd: int in ctx.builder_distances:
				if bd >= my_dist:
					break  # sorted
				closer += 1
			return clampf(float(closer) / float(ctx.build_capacity), 0.0, 1.0)
	assert(false, "ActorPool: unhandled input '%s'" % con.input)
	return 0.0


## Path distance (in tiles) to the nearest goal of a shared field; INF when
## no field exists or the goals are unreachable from here — the
## normalization window maps INF to 1.0, where a b+m=0 curve vetoes.
func _field_distance(ctx: AiContext, i: int, field: FlowField) -> float:
	if field == null:
		return INF
	var dist := field.distances[_cell_of(ctx.world, positions[i])]
	if dist == FlowField.UNREACHABLE:
		return INF
	return float(dist) / float(FlowField.COST_ORTH)


## Enter hook: the only way into an activity.
func _start_action(ctx: AiContext, i: int, action_idx: int) -> void:
	current_action[i] = action_idx
	phase[i] = 0
	phase_timer[i] = 0
	targets[i] = positions[i]
	match ctx.defs.actions[action_idx].execution:
		&"wander":
			_wander_enter(ctx, i)


## Exit hook: the ONLY place pawn-local activity state is released. Every
## way out of an activity — DONE, FAILED, preemption, rally, rescue,
## displacement — funnels through here so nothing leaks into the next
## one. Anything still in the pawn's hands goes to the ground where they
## stand (wood never vanishes; a dropped log is a visible story beat).
func _exit_action(ctx: AiContext, i: int) -> void:
	phase[i] = 0
	phase_timer[i] = 0
	targets[i] = positions[i]
	build_claims[i] = -1
	if carry_count[i] > 0:
		ctx.items.scatter(ctx.world, _cell_of(ctx.world, positions[i]), carry_type[i], carry_count[i])
	carry_type[i] = -1
	carry_count[i] = 0


func _stop_action(ctx: AiContext, i: int) -> void:
	_exit_action(ctx, i)
	current_action[i] = NO_ACTION  # re-decide next tick


## Phase transition inside an activity. The timer always resets: a phase
## may not smuggle state across the boundary.
func _set_phase(i: int, p: int) -> void:
	phase[i] = p
	phase_timer[i] = 0


## Inspection-panel label for the pawn's current phase (legibility
## contract: the player can always see what a pawn is doing and why).
func phase_label(defs: AiDefs, i: int) -> String:
	if current_action[i] == NO_ACTION:
		return ""
	var names: Array = PHASE_NAMES.get(defs.actions[current_action[i]].execution, [])
	if phase[i] >= names.size():
		return ""
	return names[phase[i]]


# --- activities -----------------------------------------------------------
# Each activity is a phase machine: transitions between phases first, then
# tick the current phase. Return values end the activity; only the brain
# starts a different one.


## Rally is not an activity — it's the player's hand overriding the brain
## entirely (see header). It gets the same clean exit on arrival.
func _tick_rally(ctx: AiContext, i: int, dt: float) -> void:
	if not _follow_field(ctx, i, ctx.command_field, dt):
		responding[i] = 0
		_stop_action(ctx, i)


func _eat_tick(ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> int:
	var cell := _cell_of(ctx.world, positions[i])
	# Standing on berries is the whole transition condition, both ways
	# (the bush can empty under us mid-meal).
	if ctx.bushes.has_berries_at(cell):
		if phase[i] != EAT_CONSUME:
			_set_phase(i, EAT_CONSUME)
	elif phase[i] != EAT_GOTO:
		_set_phase(i, EAT_GOTO)

	if phase[i] == EAT_CONSUME:
		phase_timer[i] += 1
		if phase_timer[i] >= action.ticks_per_bite:
			phase_timer[i] = 0
			var _ate: bool = ctx.bushes.consume_at(cell)
			var hunger_idx := action.considerations[0].need_idx
			needs[hunger_idx][i] = minf(needs[hunger_idx][i] + action.restore_per_bite, 1.0)
			if needs[hunger_idx][i] >= 0.98:
				return ACT_DONE
		return ACT_RUNNING
	if ctx.food_field == null or not _follow_field(ctx, i, ctx.food_field, dt):
		return ACT_FAILED  # unreachable: give up and re-decide
	return ACT_RUNNING


func _sleep_tick(ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> int:
	# Prefer not to bed down on someone's construction site — but if
	# there's no open ground one step away (deep in a painted field),
	# sleep on the ghost anyway: the occupancy rule defers that cell's
	# construction, and an unsleepable pawn is a starving deadlock.
	var cell := _cell_of(ctx.world, positions[i])
	if ctx.blueprints.has_at(cell) and _step_off_blueprints(ctx, i, cell, dt):
		return ACT_RUNNING
	var rest_idx := action.considerations[0].need_idx
	needs[rest_idx][i] = minf(needs[rest_idx][i] + action.restore_per_second * dt, 1.0)
	return ACT_DONE if needs[rest_idx][i] >= action.wake_threshold else ACT_RUNNING


func _sleep_bed_tick(ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> int:
	var cell := _cell_of(ctx.world, positions[i])
	if ctx.world.structure_at_cell(cell) == SimWorld.STRUCT_BED:
		if phase[i] != BEDREST_SLEEP:
			_set_phase(i, BEDREST_SLEEP)
	elif phase[i] != BEDREST_GOTO:
		_set_phase(i, BEDREST_GOTO)

	if phase[i] == BEDREST_SLEEP:
		var rest_idx := action.considerations[0].need_idx
		needs[rest_idx][i] = minf(needs[rest_idx][i] + action.restore_per_second * dt, 1.0)
		return ACT_DONE if needs[rest_idx][i] >= action.wake_threshold else ACT_RUNNING
	if ctx.bed_field == null or not _follow_field(ctx, i, ctx.bed_field, dt):
		return ACT_FAILED
	return ACT_RUNNING


## Builders work standing exactly one tile beside the blueprint — never on
## it — and refuse walls that would seal them into a pocket. Blueprint
## ghosts are scaffolding: pawns stand on them freely (solid fills need it),
## but a cell is never built while anyone occupies it.
func _build_tick(ctx: AiContext, i: int, dt: float) -> int:
	var cell := _cell_of(ctx.world, positions[i])
	# A live claim is the WORK-phase condition; it revalidates every tick
	# because the world moves under builders (cancelled ghosts, walls
	# built by others, our own arrival at a new frontier).
	var claim := build_claims[i]
	if claim >= 0 and (not ctx.blueprints.has_at(claim) or not _cells_adjacent(ctx.world, cell, claim)):
		claim = -1
	if claim < 0:
		claim = _pick_adjacent_blueprint(ctx, cell)
		build_claims[i] = claim
	if phase[i] != (BUILD_WORK if claim >= 0 else BUILD_TRAVEL):
		_set_phase(i, BUILD_WORK if claim >= 0 else BUILD_TRAVEL)

	if phase[i] == BUILD_WORK:
		targets[i] = positions[i]
		if not ctx.blueprints.add_worker(claim):
			work_cooldowns[i] = ctx.tick + 45
			return ACT_FAILED  # crowded this tick; re-decide
		var mat := ctx.blueprints.material_at(claim)
		var built := ctx.blueprints.add_work(claim, dt)
		if built != SimWorld.STRUCT_NONE:
			ctx.world.set_structure(claim, built, mat)
			if built == SimWorld.STRUCT_WALL:
				_displace_from(ctx, claim)
				ctx.items.displace_from(ctx.world, claim)
			# Stay on the job: clear the claim and pick the next adjacent
			# frontier cell next tick. (Needs still preempt at the regular
			# decide cadence.) Re-rolling life plans after every wall is
			# how construction turns into a colony-wide relay race.
			build_claims[i] = -1
		return ACT_RUNNING
	# No workable job here: travel toward the build frontier, stopping one
	# cell short of the goal (you can't build what you stand on). Blocked or
	# out of road: cool down so we don't statue in place on a stale field.
	if ctx.blueprint_field == null or not _follow_field(ctx, i, ctx.blueprint_field, dt, true):
		work_cooldowns[i] = ctx.tick + 45
		return ACT_FAILED
	return ACT_RUNNING


## Adjacent blueprint with worker capacity that is safe to build: never one
## someone is standing on; walls are checked against the pocket rule
## (pretend it's built — can I still reach open ground from where I
## stand?); the deepest candidate wins, so clusters complete inside-out.
func _pick_adjacent_blueprint(ctx: AiContext, cell: int) -> int:
	var w := ctx.world.width
	@warning_ignore("integer_division")
	var cy := cell / w
	var cx := cell % w
	var best := -1
	var best_depth := -1
	for d: int in 8:
		var nx := cx + FlowField.DX[d]
		var ny := cy + FlowField.DY[d]
		var ncell := ny * w + nx
		var idx: int = ctx.blueprints.cell_lookup.get(ncell, -1)
		if idx < 0 or ctx.blueprints.workers[idx] >= Blueprints.MAX_WORKERS_PER_CELL:
			continue
		# Workface discipline: only cells on the current build frontier may
		# be worked. An adjacent blueprint that isn't a frontier cell is
		# someone's future scaffold — building it early is how you seal a
		# solid fill's interior off (the outer-shell bug). The frontier is
		# LIVE (cached per blueprint change), never the stale async field:
		# a builder finishing the center must find the ring workable now.
		if not ctx.blueprints.is_frontier(ctx.world, ncell):
			continue
		# Awaiting materials: a hauler's job, not a builder's.
		if not ctx.blueprints.is_buildable(ncell):
			continue
		if ctx.occupied.has(ncell):
			continue
		if int(ctx.blueprints.types[idx]) == SimWorld.STRUCT_WALL:
			if Reachability.pocket_size(ctx.world, cell, ncell, 48) < 48:
				continue
		var cand_depth := _local_depth(ctx, ncell)
		if cand_depth > best_depth:
			best_depth = cand_depth
			best = ncell
	return best


## How buried a blueprint cell is: count of 4-dir neighbors that are
## blueprints or walls. Deeper cells must be built first.
func _local_depth(ctx: AiContext, cell: int) -> int:
	var w := ctx.world.width
	@warning_ignore("integer_division")
	var cy := cell / w
	var cx := cell % w
	var depth := 0
	for d: int in 4:
		var ncell := (cy + FlowField.DY[d]) * w + cx + FlowField.DX[d]
		if ctx.blueprints.has_at(ncell):
			depth += 1
		elif ctx.world.structure_at_cell(ncell) == SimWorld.STRUCT_WALL:
			depth += 1
	return depth


## Move one tile off any blueprint cell. Returns false when boxed in.
func _step_off_blueprints(ctx: AiContext, i: int, cell: int, dt: float) -> bool:
	var w := ctx.world.width
	@warning_ignore("integer_division")
	var cy := cell / w
	var cx := cell % w
	for d: int in 8:
		var nx := cx + FlowField.DX[d]
		var ny := cy + FlowField.DY[d]
		if not ctx.world.is_walkable(nx, ny) or ctx.blueprints.has_at(ny * w + nx):
			continue
		targets[i] = Vector2(nx + 0.5, ny + 0.5) + jitter[i]
		var _arrived := _move_toward_target(i, speeds[i] * dt)
		return true
	return false


static func _cells_adjacent(world: SimWorld, a: int, b: int) -> bool:
	var w := world.width
	@warning_ignore("integer_division")
	var dy := absi(a / w - b / w)
	var dx := absi(a % w - b % w)
	return maxi(dx, dy) == 1


## Safety net: a pawn can transiently end up inside fresh construction
## (walked through a cell the tick it completed). Teleport to the nearest
## walkable cell, scanning outward deterministically.
func _rescue_if_stuck(ctx: AiContext, i: int) -> void:
	var world := ctx.world
	var x := floori(positions[i].x)
	var y := floori(positions[i].y)
	if world.is_walkable(x, y):
		return
	for radius: int in range(1, 6):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if world.is_walkable(x + dx, y + dy):
					positions[i] = Vector2(x + dx + 0.5, y + dy + 0.5) + jitter[i]
					prev_positions[i] = positions[i]
					_stop_action(ctx, i)
					return


## A blocking structure just appeared at this cell: move any pawns standing
## in it to the nearest walkable neighbor (deterministic scan order).
func _displace_from(ctx: AiContext, cell: int) -> void:
	var world := ctx.world
	@warning_ignore("integer_division")
	var cy := cell / world.width
	var cx := cell % world.width
	for i: int in count:
		if _cell_of(world, positions[i]) != cell:
			continue
		for d: int in 8:
			var nx := cx + FlowField.DX[d]
			var ny := cy + FlowField.DY[d]
			if world.is_walkable(nx, ny):
				positions[i] = Vector2(nx + 0.5, ny + 0.5) + jitter[i]
				prev_positions[i] = positions[i]
				_stop_action(ctx, i)
				break


## Chopping: walk the chop field to a planned tree, then work it down.
## Trees are walkable, so the chopper stands on the tree's cell (good
## enough until chop animations land). Felling scatters the yield where
## the tree stood — the sim's first item spawn.
func _chop_tick(ctx: AiContext, i: int, dt: float) -> int:
	var cell := _cell_of(ctx.world, positions[i])
	var on_planned_tree := ctx.trees.is_designated(cell)
	if phase[i] != (CHOP_WORK if on_planned_tree else CHOP_TRAVEL):
		_set_phase(i, CHOP_WORK if on_planned_tree else CHOP_TRAVEL)

	if phase[i] == CHOP_WORK:
		targets[i] = positions[i]
		if not ctx.trees.add_worker(cell):
			work_cooldowns[i] = ctx.tick + 45
			return ACT_FAILED  # someone else is on this tree; re-decide
		var wood := ctx.trees.add_work(ctx.world, cell, dt)
		if wood > 0:
			ctx.items.scatter(ctx.world, cell, Items.WOOD, wood)
			return ACT_DONE  # tree's down; re-decide (often: the next tree)
		return ACT_RUNNING
	if ctx.chop_field == null or not _follow_field(ctx, i, ctx.chop_field, dt):
		work_cooldowns[i] = ctx.tick + 45
		return ACT_FAILED
	return ACT_RUNNING


## Hauling: fetch wood from the nearest ground stack, carry it to the
## nearest blueprint still owed materials, deposit into it (and any
## needing neighbors) — repeat until the hands are empty. No stack
## claims in v1: two haulers racing to one stack self-heal through
## re-decide, and the loser's shrug is visible, honest behavior. Cargo
## never needs explicit dropping here — every exit path goes through
## the exit hook, which grounds whatever is still in hand.
func _haul_tick(ctx: AiContext, i: int, dt: float) -> int:
	var cell := _cell_of(ctx.world, positions[i])
	var carrying := carry_count[i] > 0
	if phase[i] != (HAUL_DELIVER if carrying else HAUL_FETCH):
		_set_phase(i, HAUL_DELIVER if carrying else HAUL_FETCH)

	if phase[i] == HAUL_FETCH:
		if ctx.items.has_at(cell) and ctx.items.type_at(cell) == Items.WOOD:
			var capacity := ctx.items.defs.stack_sizes[Items.WOOD]
			var taken := ctx.items.take(cell, capacity)
			if taken > 0:
				carry_type[i] = Items.WOOD
				carry_count[i] = taken
				return ACT_RUNNING  # deliver phase picks up next tick
		if ctx.wood_field == null or not _follow_field(ctx, i, ctx.wood_field, dt):
			work_cooldowns[i] = ctx.tick + 45
			return ACT_FAILED  # raced to an empty stack, or no wood at all
		return ACT_RUNNING

	# Deliver: feed any owed blueprint we're standing on or beside.
	var fed := false
	var w := ctx.world.width
	@warning_ignore("integer_division")
	var cy := cell / w
	var cx := cell % w
	for d: int in 9:
		var ncell := cell if d == 8 else (cy + FlowField.DY[d]) * w + cx + FlowField.DX[d]
		var accepted := ctx.blueprints.deliver(ncell, carry_count[i])
		if accepted > 0:
			carry_count[i] -= accepted
			fed = true
			if carry_count[i] <= 0:
				carry_type[i] = -1
				return ACT_DONE
	if fed:
		return ACT_RUNNING  # partial deposit; keep feeding neighbors next tick
	if ctx.haul_field == null or not _follow_field(ctx, i, ctx.haul_field, dt):
		work_cooldowns[i] = ctx.tick + 45
		return ACT_FAILED  # demand vanished mid-carry; exit hook grounds the load
	return ACT_RUNNING


## A stroll alternates walking legs with standing pauses; each DONE comes
## back through the brain, and re-entry rolls the next leg or pause.
func _wander_enter(ctx: AiContext, i: int) -> void:
	decision_counts[i] += 1
	var s := SimRng.stream(
		SimRng.key([ctx.world.world_seed, "decide", ids[i], decision_counts[i]])
	)
	if s.nextf() < WANDER_PAUSE_CHANCE:
		_set_phase(i, WANDER_WAIT)
		phase_timer[i] = WANDER_PAUSE_MIN_TICKS + s.next_range(
			0, WANDER_PAUSE_MAX_TICKS - WANDER_PAUSE_MIN_TICKS
		)
	else:
		_set_phase(i, WANDER_STROLL)
		targets[i] = _pick_stroll_leg(ctx.world, i, s)


func _wander_tick(ctx: AiContext, i: int, dt: float) -> int:
	if phase[i] == WANDER_WAIT:
		phase_timer[i] -= 1
		return ACT_DONE if phase_timer[i] <= 0 else ACT_RUNNING
	if not ctx.world.is_walkable(floori(targets[i].x), floori(targets[i].y)):
		return ACT_FAILED  # a wall landed on the destination mid-leg
	if _move_toward_target(i, speeds[i] * WANDER_SPEED_SCALE * dt):
		return ACT_DONE
	return ACT_RUNNING


# --- movement -------------------------------------------------------------


## Step along a flow field, advancing through cell-sized targets within
## this tick's movement budget. Returns false when there is nowhere further
## to go (goal reached, unreachable, or blocked by fresh construction).
## With stop_before_goal, halts one cell short instead of entering the goal.
func _follow_field(
	ctx: AiContext, i: int, field: FlowField, dt: float, stop_before_goal := false
) -> bool:
	var remaining := speeds[i] * dt
	var advances := 0
	while advances < 3:
		var pos := positions[i]
		# The target cell may have been walled since it was chosen (fields
		# rebuild on a delay) — never keep walking into it.
		if not ctx.world.is_walkable(floori(targets[i].x), floori(targets[i].y)):
			targets[i] = pos
			return false
		var to_target := targets[i] - pos
		var dist := to_target.length()
		if dist <= ARRIVE_DISTANCE:
			var cx := floori(pos.x)
			var cy := floori(pos.y)
			var dir := field.direction_at_cell(cy * ctx.world.width + cx)
			if dir == Vector2i.ZERO:
				return false
			var nx := cx + dir.x
			var ny := cy + dir.y
			# Fields rebuild on a delay; walls may have appeared since —
			# check the step (and, for diagonals, the corner rule) against
			# the live world. Repath rather than walk through.
			if not ctx.world.is_walkable(nx, ny):
				return false
			if dir.x != 0 and dir.y != 0:
				if not ctx.world.is_walkable(nx, cy) or not ctx.world.is_walkable(cx, ny):
					return false
			if stop_before_goal and field.distances[ny * ctx.world.width + nx] == 0:
				return false
			targets[i] = Vector2(nx, ny) + Vector2(0.5, 0.5) + jitter[i]
			advances += 1
			continue
		if remaining <= 0.0:
			return true
		var step := minf(remaining, dist)
		positions[i] = pos + to_target * (step / dist)
		remaining -= step
	return true


## Move up to max_step toward targets[i]. Returns true on arrival.
func _move_toward_target(i: int, max_step: float) -> bool:
	var pos := positions[i]
	var to_target := targets[i] - pos
	var dist := to_target.length()
	if dist <= ARRIVE_DISTANCE:
		return true
	var step := minf(max_step, dist)
	positions[i] = pos + to_target * (step / dist)
	return dist - step <= ARRIVE_DISTANCE


static func _cell_of(world: SimWorld, pos: Vector2) -> int:
	return floori(pos.y) * world.width + floori(pos.x)


## The order-th walkable cell scanning outward from the map center in
## deterministic ring order (Chebyshev rings, row-major within each ring).
static func _center_spawn_cell(world: SimWorld, order: int) -> Vector2i:
	@warning_ignore("integer_division")
	var cx := world.width / 2
	@warning_ignore("integer_division")
	var cy := world.height / 2
	var seen := 0
	for r: int in maxi(world.width, world.height):
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if world.is_walkable(cx + dx, cy + dy):
					if seen == order:
						return Vector2i(cx + dx, cy + dy)
					seen += 1
	return Vector2i(cx, cy)


## One stroll leg: steer from the pawn's current heading by a bounded,
## center-weighted turn. The cone widens toward a full U-turn only as
## attempts fail, so reversals happen when geometry demands them, not by
## coin flip.
func _pick_stroll_leg(world: SimWorld, i: int, s: SimRng.Stream) -> Vector2:
	var pos := positions[i]
	for attempt: int in 16:
		var spread := WANDER_TURN + (PI - WANDER_TURN) * float(attempt) / 15.0
		var turn := (s.nextf() + s.nextf() - 1.0) * spread
		var angle := headings[i] + turn
		var radius := WANDER_LEG_MIN + s.nextf() * (WANDER_LEG_MAX - WANDER_LEG_MIN)
		var t := pos + Vector2.from_angle(angle) * radius
		if _line_walkable(world, pos, t):
			headings[i] = wrapf(angle, -PI, PI)
			return t
	return pos


## Movement is a straight segment, so the whole segment must stay on
## walkable tiles (sampled at half-tile steps), not just the endpoint.
static func _line_walkable(world: SimWorld, from: Vector2, to: Vector2) -> bool:
	var length := from.distance_to(to)
	var steps := maxi(1, ceili(length * 2.0))
	for k: int in steps + 1:
		var p := from.lerp(to, float(k) / steps)
		if not world.is_walkable(floori(p.x), floori(p.y)):
			return false
	return true
