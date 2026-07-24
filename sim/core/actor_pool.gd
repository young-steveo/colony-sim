class_name ActorPool
extends RefCounted
## All actors, structure-of-arrays style: parallel packed arrays indexed by
## actor slot, ticked in one tight loop by the sim. No per-actor objects, no
## per-actor _process.
##
## Behavior: actors wander locally. When the player sets a rally target
## (see Simulation.set_command_target), every actor follows the shared flow
## field to it — one array lookup per cell, no per-actor pathfinding — then
## reverts to wandering on arrival. A fixed per-actor jitter offsets targets
## inside each cell so crowds don't walk single-file.

const ARRIVE_DISTANCE := 0.05
const WANDER_RADIUS := 8.0
const JITTER := 0.35

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var prev_positions := PackedVector2Array()
var targets := PackedVector2Array()
var speeds := PackedFloat32Array()
var responding := PackedByteArray()
var decision_counts := PackedInt32Array()
var jitter := PackedVector2Array()

var _spawned_total := 0


func spawn(world: SimWorld, n: int) -> void:
	var new_count := count + n
	var _e1: int = ids.resize(new_count)
	var _e2: int = positions.resize(new_count)
	var _e3: int = prev_positions.resize(new_count)
	var _e4: int = targets.resize(new_count)
	var _e5: int = speeds.resize(new_count)
	var _e6: int = responding.resize(new_count)
	var _e7: int = decision_counts.resize(new_count)
	var _e8: int = jitter.resize(new_count)
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
	count = new_count


## A new command target exists: everyone answers the call.
func rally() -> void:
	for i: int in count:
		responding[i] = 1
		# Retarget on the next arrival check by heading to the nearest cell
		# center; keeps the turn toward the rally point prompt.
		targets[i] = positions[i]


func tick(world: SimWorld, command_field: FlowField, dt: float) -> void:
	for i: int in count:
		prev_positions[i] = positions[i]
		var remaining := speeds[i] * dt
		# Advance through cell-sized targets without stalling a tick at each
		# arrival; the guard bounds decision work per actor per tick.
		var decisions := 0
		while remaining > 0.0 and decisions < 3:
			var pos := positions[i]
			var to_target := targets[i] - pos
			var dist := to_target.length()
			if dist <= ARRIVE_DISTANCE:
				_advance(world, command_field, i)
				decisions += 1
				continue
			var step := minf(remaining, dist)
			positions[i] = pos + to_target * (step / dist)
			remaining -= step


## Arrived at the current target: set the next one — the next cell along the
## command field while responding, local wander otherwise.
func _advance(world: SimWorld, command_field: FlowField, i: int) -> void:
	var pos := positions[i]
	if responding[i] == 1 and command_field != null:
		var cell := floori(pos.y) * world.width + floori(pos.x)
		var dir := command_field.direction_at_cell(cell)
		if dir != Vector2i.ZERO:
			var next := Vector2(floori(pos.x) + dir.x, floori(pos.y) + dir.y)
			targets[i] = next + Vector2(0.5, 0.5) + jitter[i]
			return
		# Arrived (or the rally point is unreachable from here): back to
		# your own business.
		responding[i] = 0
	decision_counts[i] += 1
	var s := SimRng.stream(
		SimRng.key([world.world_seed, "decide", ids[i], decision_counts[i]])
	)
	targets[i] = _local_wander(world, pos, s)


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
