class_name ActorPool
extends RefCounted
## All actors, structure-of-arrays style: parallel packed arrays indexed by
## actor slot, ticked in one tight loop by the sim. No per-actor objects, no
## per-actor _process. Walking-skeleton behavior is dumb wandering — real
## utility AI replaces _pick_target later.
##
## Known limitation (by design, for now): movement is straight-line toward
## the target, so actors can cut across water. Pathfinding is the next
## foundation phase.

const WANDER_RADIUS := 8.0
const ARRIVE_DISTANCE := 0.05

var count := 0
var ids := PackedInt32Array()
var positions := PackedVector2Array()
var prev_positions := PackedVector2Array()
var targets := PackedVector2Array()
var speeds := PackedFloat32Array()
var wander_counts := PackedInt32Array()

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
		wander_counts.push_back(0)
		count += 1


func tick(world: SimWorld, dt: float) -> void:
	for i: int in count:
		var pos := positions[i]
		prev_positions[i] = pos
		var to_target := targets[i] - pos
		var dist := to_target.length()
		if dist < ARRIVE_DISTANCE:
			targets[i] = _pick_target(world, i, pos)
			continue
		var step := minf(speeds[i] * dt, dist)
		positions[i] = pos + to_target * (step / dist)


func _pick_target(world: SimWorld, i: int, pos: Vector2) -> Vector2:
	wander_counts[i] += 1
	var s := SimRng.stream(
		SimRng.key([world.world_seed, "wander", ids[i], wander_counts[i]])
	)
	for attempt: int in 16:
		var angle := s.nextf() * TAU
		var radius := 1.0 + s.nextf() * WANDER_RADIUS
		var t := pos + Vector2.from_angle(angle) * radius
		if world.is_walkable(floori(t.x), floori(t.y)):
			return t
	return pos
