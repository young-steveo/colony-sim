class_name ActorPool
extends RefCounted
## All actors, structure-of-arrays style: parallel packed arrays indexed by
## actor slot, ticked in one tight loop by the sim. No per-actor objects, no
## per-actor _process.
##
## Walking-skeleton behavior: each actor picks a reachable site and follows
## its shared flow field cell-by-cell ("rolls downhill"); on arrival it picks
## another site. Per-actor cost is one array lookup per cell — no individual
## pathfinding. A fixed per-actor jitter offsets targets inside each cell so
## crowds don't walk single-file. Real utility AI replaces site-picking
## later; the field-following locomotion stays.

const ARRIVE_DISTANCE := 0.05
const WANDER_RADIUS := 8.0
const JITTER := 0.35
const NO_SITE := -1

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var prev_positions := PackedVector2Array()
var targets := PackedVector2Array()
var speeds := PackedFloat32Array()
var site_index := PackedInt32Array()
var decision_counts := PackedInt32Array()
var jitter := PackedVector2Array()

var _spawned_total := 0


func spawn(world: SimWorld, n: int) -> void:
	for j: int in n:
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
		ids.push_back(id)
		positions.push_back(pos)
		prev_positions.push_back(pos)
		targets.push_back(pos)
		speeds.push_back(2.0 + 2.0 * s.nextf())
		site_index.push_back(NO_SITE)
		decision_counts.push_back(0)
		jitter.push_back(Vector2((s.nextf() - 0.5) * JITTER, (s.nextf() - 0.5) * JITTER))
		count += 1


func tick(world: SimWorld, fields: Array[FlowField], dt: float) -> void:
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
				_advance(world, fields, i)
				decisions += 1
				continue
			var step := minf(remaining, dist)
			positions[i] = pos + to_target * (step / dist)
			remaining -= step


## Arrived at the current target: set the next one — the next cell along the
## current site's flow field, or pick a new site (or local wander fallback).
func _advance(world: SimWorld, fields: Array[FlowField], i: int) -> void:
	var pos := positions[i]
	var cell := floori(pos.y) * world.width + floori(pos.x)
	if site_index[i] != NO_SITE:
		var dir := fields[site_index[i]].direction_at_cell(cell)
		if dir != Vector2i.ZERO:
			var next := Vector2(floori(pos.x) + dir.x, floori(pos.y) + dir.y)
			targets[i] = next + Vector2(0.5, 0.5) + jitter[i]
			return
	# At a goal, unreachable, or siteless: choose again.
	decision_counts[i] += 1
	var s := SimRng.stream(
		SimRng.key([world.world_seed, "decide", ids[i], decision_counts[i]])
	)
	var candidates := PackedInt32Array()
	for k: int in fields.size():
		if k != site_index[i] and fields[k].is_reachable_cell(cell):
			candidates.push_back(k)
	if candidates.is_empty():
		site_index[i] = NO_SITE
		targets[i] = _local_wander(world, pos, s)
		return
	site_index[i] = candidates[s.next_range(0, candidates.size() - 1)]
	var dir := fields[site_index[i]].direction_at_cell(cell)
	if dir != Vector2i.ZERO:
		var next := Vector2(floori(pos.x) + dir.x, floori(pos.y) + dir.y)
		targets[i] = next + Vector2(0.5, 0.5) + jitter[i]


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
