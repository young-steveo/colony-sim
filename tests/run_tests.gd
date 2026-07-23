extends SceneTree
## Headless test suite for the sim core. Run with:
##   godot --path . --headless --script res://tests/run_tests.gd
## Exits nonzero on any failure.

var _failures := 0
var _passes := 0


func _init() -> void:
	_test_rng()
	_test_map_gen()
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

	for t: int in 200:
		sim_a.tick()
		sim_b.tick()

	_check(sim_a.actors.positions == sim_b.actors.positions, "200 ticks fully deterministic")
	_check(sim_a.actors.positions != spawn_positions, "actors actually move")
	_check(sim_a.tick_count == 200, "tick count advances")
