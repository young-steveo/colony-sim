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

const ARRIVE_DISTANCE := 0.05
const WANDER_RADIUS := 8.0
const JITTER := 0.35
const DECIDE_INTERVAL := 15
const COMMITMENT_BONUS := 1.1
# A higher-bucket action must clear this to preempt lower buckets. Tuned so
# an eating pawn keeps its meal until roughly three-quarters fed instead of
# wandering off after two bites.
const BUCKET_CUTOFF := 0.15
const NO_ACTION := -1

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
var action_timer := PackedInt32Array()
var build_claims := PackedInt32Array()  # blueprint cell being worked, or -1
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
	var _e10: int = action_timer.resize(new_count)
	var _e11: int = last_scores.resize(new_count * _n_actions)
	var _e13: int = build_claims.resize(new_count)
	for nd: int in _n_needs:
		var _e12: int = needs[nd].resize(new_count)
	for i: int in range(count, new_count):
		var id := _spawned_total
		_spawned_total += 1
		var s := SimRng.stream(SimRng.key([world.world_seed, "spawn", id]))
		var pos := Vector2(world.width * 0.5, world.height * 0.5)
		for attempt: int in 64:
			var x := s.next_range(0, world.width - 1)
			var y := s.next_range(0, world.height - 1)
			if world.is_walkable(x, y):
				pos = Vector2(x + 0.5, y + 0.5)
				break
		ids[i] = id
		positions[i] = pos
		prev_positions[i] = pos
		targets[i] = pos
		speeds[i] = 2.0 + 2.0 * s.nextf()
		responding[i] = 0
		decision_counts[i] = 0
		jitter[i] = Vector2((s.nextf() - 0.5) * JITTER, (s.nextf() - 0.5) * JITTER)
		current_action[i] = NO_ACTION
		action_timer[i] = 0
		build_claims[i] = -1
		for nd: int in _n_needs:
			# Staggered starting levels so the colony doesn't eat and sleep
			# in lockstep.
			needs[nd][i] = clampf(defs.needs[nd].start * (0.7 + 0.3 * s.nextf()), 0.05, 1.0)
	count = new_count


## A rally command exists: everyone answers the call.
func rally() -> void:
	for i: int in count:
		responding[i] = 1
		targets[i] = positions[i]


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
		if responding[i] == 1 and ctx.command_field != null:
			_tick_rally(ctx, i, dt)
			continue
		if current_action[i] == NO_ACTION or (ctx.tick + ids[i]) % DECIDE_INTERVAL == 0:
			_decide(ctx, i)
		var action := ctx.defs.actions[current_action[i]]
		match action.execution:
			&"eat":
				_tick_eat(ctx, i, action, dt)
			&"sleep":
				_tick_sleep(ctx, i, action, dt)
			&"sleep_bed":
				_tick_sleep_bed(ctx, i, action, dt)
			&"build":
				_tick_build(ctx, i, dt)
			&"wander":
				_tick_wander(ctx, i, dt)


# --- decision -------------------------------------------------------------


func _decide(ctx: AiContext, i: int) -> void:
	var row := i * _n_actions
	for a: int in _n_actions:
		var action := ctx.defs.actions[a]
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
		&"build_crowding":
			# Builders assigned vs. total work capacity: 1.0 = saturated.
			# Exclude the evaluating pawn — otherwise a full crew vetoes
			# its own jobs at the next re-decide and construction stalls.
			var bp_count := ctx.blueprints.cells.size()
			if bp_count == 0:
				return 1.0
			var others := ctx.build_workers
			if current_action[i] >= 0 and ctx.defs.actions[current_action[i]].execution == &"build":
				others -= 1
			var capacity := float(bp_count * Blueprints.MAX_WORKERS_PER_CELL)
			return clampf(float(others) / capacity, 0.0, 1.0)
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


func _start_action(ctx: AiContext, i: int, action_idx: int) -> void:
	current_action[i] = action_idx
	action_timer[i] = 0
	match ctx.defs.actions[action_idx].execution:
		&"wander":
			decision_counts[i] += 1
			var s := SimRng.stream(
				SimRng.key([ctx.world.world_seed, "decide", ids[i], decision_counts[i]])
			)
			targets[i] = _local_wander(ctx.world, positions[i], s)
		_:
			targets[i] = positions[i]


func _complete(i: int) -> void:
	current_action[i] = NO_ACTION  # re-decide next tick
	targets[i] = positions[i]
	build_claims[i] = -1


# --- execution ------------------------------------------------------------


func _tick_rally(ctx: AiContext, i: int, dt: float) -> void:
	if not _follow_field(ctx, i, ctx.command_field, dt):
		responding[i] = 0
		_complete(i)


func _tick_eat(ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> void:
	var cell := _cell_of(ctx.world, positions[i])
	if ctx.bushes.has_berries_at(cell):
		action_timer[i] += 1
		if action_timer[i] >= action.ticks_per_bite:
			action_timer[i] = 0
			var _ate: bool = ctx.bushes.consume_at(cell)
			var hunger_idx := action.considerations[0].need_idx
			needs[hunger_idx][i] = minf(needs[hunger_idx][i] + action.restore_per_bite, 1.0)
			if needs[hunger_idx][i] >= 0.98:
				_complete(i)
		return
	if ctx.food_field == null or not _follow_field(ctx, i, ctx.food_field, dt):
		# Unreachable, or the bush emptied under us: give up and re-decide.
		_complete(i)


func _tick_sleep(_ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> void:
	var rest_idx := action.considerations[0].need_idx
	needs[rest_idx][i] = minf(needs[rest_idx][i] + action.restore_per_second * dt, 1.0)
	if needs[rest_idx][i] >= action.wake_threshold:
		_complete(i)


func _tick_sleep_bed(ctx: AiContext, i: int, action: AiDefs.ActionDef, dt: float) -> void:
	var cell := _cell_of(ctx.world, positions[i])
	if ctx.world.structure_at_cell(cell) == SimWorld.STRUCT_BED:
		var rest_idx := action.considerations[0].need_idx
		needs[rest_idx][i] = minf(needs[rest_idx][i] + action.restore_per_second * dt, 1.0)
		if needs[rest_idx][i] >= action.wake_threshold:
			_complete(i)
		return
	if ctx.bed_field == null or not _follow_field(ctx, i, ctx.bed_field, dt):
		_complete(i)


## Builders work standing exactly one tile beside the blueprint — never on
## it — and refuse walls that would seal them into a pocket (the Smarter
## Construction rule).
func _tick_build(ctx: AiContext, i: int, dt: float) -> void:
	var cell := _cell_of(ctx.world, positions[i])
	# Politeness: never loiter on someone's construction site.
	if ctx.blueprints.has_at(cell):
		if not _step_off_blueprints(ctx, i, cell, dt):
			_complete(i)
		return
	var claim := build_claims[i]
	if claim >= 0 and (not ctx.blueprints.has_at(claim) or not _cells_adjacent(ctx.world, cell, claim)):
		claim = -1
	if claim < 0:
		claim = _pick_adjacent_blueprint(ctx, cell)
		build_claims[i] = claim
	if claim >= 0:
		targets[i] = positions[i]
		if not ctx.blueprints.add_worker(claim):
			_complete(i)  # crowded this tick; re-decide
			return
		var built := ctx.blueprints.add_work(claim, dt)
		if built != SimWorld.STRUCT_NONE:
			ctx.world.set_structure(claim, built)
			if built == SimWorld.STRUCT_WALL:
				_displace_from(ctx.world, claim)
			_complete(i)
		return
	# No workable job here: travel toward the blueprints (never stepping
	# onto one), or give up and re-decide.
	if ctx.blueprint_field == null or not _follow_field(ctx, i, ctx.blueprint_field, dt, true):
		_complete(i)


## Adjacent blueprint with worker capacity that is safe to build. Walls are
## checked against the pocket rule: pretend it's built — can I still reach
## open ground from where I stand?
func _pick_adjacent_blueprint(ctx: AiContext, cell: int) -> int:
	var w := ctx.world.width
	@warning_ignore("integer_division")
	var cy := cell / w
	var cx := cell % w
	for d: int in 8:
		var nx := cx + FlowField.DX[d]
		var ny := cy + FlowField.DY[d]
		var ncell := ny * w + nx
		var idx: int = ctx.blueprints.cell_lookup.get(ncell, -1)
		if idx < 0 or ctx.blueprints.workers[idx] >= Blueprints.MAX_WORKERS_PER_CELL:
			continue
		if int(ctx.blueprints.types[idx]) == SimWorld.STRUCT_WALL:
			if Reachability.pocket_size(ctx.world, cell, ncell, 48) < 48:
				continue
		return ncell
	return -1


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


## A blocking structure just appeared at this cell: move any pawns standing
## in it to the nearest walkable neighbor (deterministic scan order).
func _displace_from(world: SimWorld, cell: int) -> void:
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
				_complete(i)
				break


func _tick_wander(ctx: AiContext, i: int, dt: float) -> void:
	if not ctx.world.is_walkable(floori(targets[i].x), floori(targets[i].y)):
		_complete(i)
		return
	if _move_toward_target(i, speeds[i] * dt):
		_complete(i)


# --- movement -------------------------------------------------------------


## Step along a flow field, advancing through cell-sized targets within
## this tick's movement budget. Returns false when there is nowhere further
## to go (goal reached, unreachable, or blocked by fresh construction).
## With avoid_blueprints, stops rather than stepping onto a blueprint cell.
func _follow_field(
	ctx: AiContext, i: int, field: FlowField, dt: float, avoid_blueprints := false
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
			if avoid_blueprints and ctx.blueprints.has_at(ny * ctx.world.width + nx):
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


func _local_wander(world: SimWorld, pos: Vector2, s: SimRng.Stream) -> Vector2:
	for attempt: int in 16:
		var angle := s.nextf() * TAU
		var radius := 1.0 + s.nextf() * WANDER_RADIUS
		var t := pos + Vector2.from_angle(angle) * radius
		if _line_walkable(world, pos, t):
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
