extends SceneTree
## Headless test suite for the sim core. Run with:
##   godot --path . --headless --script res://tests/run_tests.gd
## Exits nonzero on any failure.

var _failures := 0
var _passes := 0


func _init() -> void:
	_test_rng()
	_test_map_gen()
	_test_flow_field()
	_test_simulation()
	print("")
	print("%d passed, %d failed" % [_passes, _failures])
	quit(0 if _failures == 0 else 1)


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s" % name)


func _test_rng() -> void:
	print("SimRng:")
	# Canonical SplitMix64 vector: seed 0 -> 0xE220A8397B1DCDAF.
	_check(SimRng.mix(0) == -2152535657050944081, "splitmix64 known vector (seed 0)")
	_check(SimRng.mix(1) == -7995527694508729151, "splitmix64 known vector (seed 1)")

	_check(
		SimRng.key([42, "wander", 7]) == SimRng.key([42, "wander", 7]),
		"identical context -> identical key"
	)
	_check(SimRng.key([1, 2]) != SimRng.key([2, 1]), "context order matters")
	_check(SimRng.key([42, "spawn"]) != SimRng.key([42, "wander"]), "string context differs")

	var total := 0.0
	var lo := 1.0
	var hi := 0.0
	for i: int in 1000:
		var f := SimRng.randf(SimRng.key([99, "dist", i]))
		total += f
		lo = minf(lo, f)
		hi = maxf(hi, f)
	var mean := total / 1000.0
	_check(mean > 0.45 and mean < 0.55, "randf mean ~0.5 (got %.3f)" % mean)
	_check(lo >= 0.0 and hi < 1.0, "randf within [0, 1)")

	var seen := {}
	var in_bounds := true
	for i: int in 1000:
		var v := SimRng.randi_range(SimRng.key([99, "range", i]), 3, 7)
		if v < 3 or v > 7:
			in_bounds = false
		seen[v] = true
	_check(in_bounds, "randi_range stays in bounds")
	_check(seen.size() == 5, "randi_range hits all values in [3, 7]")

	var s1 := SimRng.stream(SimRng.key([5, "s"]))
	var s2 := SimRng.stream(SimRng.key([5, "s"]))
	var s3 := SimRng.stream(SimRng.key([5, "s"]), 1)
	var same := true
	var independent := false
	for i: int in 10:
		var a := s1.next()
		if a != s2.next():
			same = false
		if a != s3.next():
			independent = true
	_check(same, "same-key streams reproduce")
	_check(independent, "different stream_id diverges")


func _test_map_gen() -> void:
	print("MapGen:")
	var a := MapGen.generate(42, 64, 64)
	var b := MapGen.generate(42, 64, 64)
	var c := MapGen.generate(43, 64, 64)
	_check(a == b, "same seed -> identical map")
	_check(a != c, "different seed -> different map")

	var valid := true
	var walkable := 0
	for t: int in a:
		if t < SimWorld.TILE_WATER or t > SimWorld.TILE_ROCK:
			valid = false
		if t == SimWorld.TILE_SAND or t == SimWorld.TILE_GRASS:
			walkable += 1
	_check(valid, "all tiles are valid types")
	_check(walkable > 64 * 64 / 4, "map is at least 25%% walkable (got %d/4096)" % walkable)


@warning_ignore("integer_division")
func _test_flow_field() -> void:
	print("FlowField:")
	var w := SimWorld.new(42, 96, 96)
	var goal := -1
	for c: int in w.width * w.height:
		if w.is_walkable(c % w.width, c / w.width):
			goal = c
			break
	var f := FlowField.build(w, PackedInt32Array([goal]))
	var f2 := FlowField.build(w, PackedInt32Array([goal]))
	_check(f.distances == f2.distances and f.flow_dir == f2.flow_dir, "build is deterministic")
	_check(f.distances[goal] == 0, "goal distance is zero")

	var descends := true
	var corners_ok := true
	var unwalkable_ok := true
	var farthest := goal
	for c: int in w.width * w.height:
		var x := c % w.width
		var y := c / w.width
		if not w.is_walkable(x, y):
			if f.distances[c] != FlowField.UNREACHABLE:
				unwalkable_ok = false
			continue
		var dist := f.distances[c]
		if dist == FlowField.UNREACHABLE or dist == 0:
			continue
		if dist > f.distances[farthest] and f.distances[farthest] != FlowField.UNREACHABLE:
			farthest = c
		var d := f.flow_dir[c]
		if d == FlowField.NO_DIR:
			descends = false
			continue
		var nx := x + FlowField.DX[d]
		var ny := y + FlowField.DY[d]
		if f.distances[ny * w.width + nx] >= dist:
			descends = false
		if d >= 4 and (not w.is_walkable(nx, y) or not w.is_walkable(x, ny)):
			corners_ok = false
	_check(unwalkable_ok, "unwalkable cells are unreachable")
	_check(descends, "every reachable cell strictly descends")
	_check(corners_ok, "no diagonal corner cutting")

	var c := farthest
	var steps := 0
	while f.distances[c] > 0 and steps < w.width * w.height:
		var d := f.flow_dir[c]
		c += FlowField.DY[d] * w.width + FlowField.DX[d]
		steps += 1
	_check(f.distances[c] == 0, "downhill walk from farthest cell reaches the goal")


func _test_simulation() -> void:
	print("Simulation:")
	var sim_a := Simulation.new(7, 96, 96)
	var sim_b := Simulation.new(7, 96, 96)
	sim_a.actors.spawn(sim_a.world, 20)
	sim_b.actors.spawn(sim_b.world, 20)

	var spawn_positions := sim_a.actors.positions.duplicate()
	var all_walkable := true
	for i: int in sim_a.actors.count:
		var p := sim_a.actors.positions[i]
		if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
			all_walkable = false
	_check(all_walkable, "actors spawn on walkable tiles")

	var stayed_walkable := true
	for t: int in 300:
		sim_a.tick()
		sim_b.tick()
		if t % 50 == 0:
			for i: int in sim_a.actors.count:
				var p := sim_a.actors.positions[i]
				if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
					stayed_walkable = false

	_check(sim_a.actors.positions == sim_b.actors.positions, "300 ticks fully deterministic")
	_check(sim_a.actors.positions != spawn_positions, "actors actually move")
	_check(stayed_walkable, "actors never leave walkable ground")
	_check(sim_a.sites.size() > 0, "sites were placed")
	_check(sim_a.tick_count == 300, "tick count advances")

	var travelling := 0
	for i: int in sim_a.actors.count:
		if sim_a.actors.site_index[i] != ActorPool.NO_SITE:
			travelling += 1
	_check(travelling > sim_a.actors.count / 2, "most actors are travelling to sites")
