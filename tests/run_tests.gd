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
	_test_ai()
	_test_building()
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


func _test_flow_field() -> void:
	print("FlowField:")
	var w := SimWorld.new(42, 96, 96)
	var goal := -1
	for c: int in w.width * w.height:
		@warning_ignore("integer_division")
		var cy := c / w.width
		if w.is_walkable(c % w.width, cy):
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
		@warning_ignore("integer_division")
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


func _test_ai() -> void:
	print("AI:")
	var defs := AiDefs.load_file(Simulation.AI_DEFS_PATH)
	_check(defs.needs.size() == 3, "three needs load (hunger, rest, safety)")
	_check(defs.actions.size() == 5, "five actions load (eat, sleeps, build, wander)")
	_check(defs.need_index(&"hunger") >= 0, "need_index resolves hunger")
	var expected_buckets: Array[int] = [2, 1, 0]
	_check(defs.bucket_order == expected_buckets, "buckets ordered high to low")

	# Pinned compensation values (ported from The Final Archive's tests).
	_check(
		is_equal_approx(AiDefs.compensate(0.5, 2), 0.625),
		"compensation pinned: compensate(0.5, 2) == 0.625"
	)
	_check(AiDefs.compensate(1.0, 0) == 1.0, "zero considerations score their weight")

	var eat := defs.actions[defs.action_index(&"eat")]
	var hunger_con := eat.considerations[0]
	_check(is_equal_approx(hunger_con.score(1.0), 0.0), "sated hunger scores eat at 0")
	_check(is_equal_approx(hunger_con.score(0.0), 1.0), "starving hunger scores eat at 1")
	var mid := hunger_con.score(0.5)
	_check(mid > 0.2 and mid < 0.3, "half hunger scores quadratically (~0.25)")

	# Behavior: a hungry pawn near food decides to eat and its hunger rises.
	var sim := Simulation.new(7, 96, 96)
	_check(sim.bushes.cells.size() > 5, "bushes scattered on grass (%d)" % sim.bushes.cells.size())
	_check(sim.food_field != null, "food flow field built")
	sim.spawn_actors(8)
	var hunger_idx := sim.defs.need_index(&"hunger")
	var rest_idx := sim.defs.need_index(&"rest")
	for i: int in sim.actors.count:
		sim.actors.needs[hunger_idx][i] = 0.2
	var berries_before := sim.bushes.consumed_total
	var ate := false
	var slept := false
	var prev_rest := sim.actors.needs[rest_idx].duplicate()
	for t: int in 3600:
		sim.tick()
		if t % 20 == 0:
			for i: int in sim.actors.count:
				if sim.bushes.consumed_total > berries_before:
					ate = true
				if sim.actors.needs[rest_idx][i] > prev_rest[i]:
					slept = true
			prev_rest = sim.actors.needs[rest_idx].duplicate()
	_check(ate, "hungry pawns found food and ate (%d berries)" % sim.bushes.consumed_total)
	_check(slept, "tired pawns slept (rest rose)")
	var in_range := true
	for nd: int in sim.defs.needs.size():
		for i: int in sim.actors.count:
			var v := sim.actors.needs[nd][i]
			if v < 0.0 or v > 1.0:
				in_range = false
	_check(in_range, "need values stay in [0, 1]")
	var scored := false
	for v: float in sim.actors.last_scores:
		if v > 0.0:
			scored = true
	_check(scored, "last_scores populated for inspection")


func _test_building() -> void:
	print("Building:")
	var sim_a := Simulation.new(11, 96, 96)
	var sim_b := Simulation.new(11, 96, 96)

	# Find a fully walkable 6x5 rect for a tiny house.
	var ox := -1
	var oy := -1
	for y: int in range(2, 90):
		for x: int in range(2, 90):
			var clear := true
			for dy: int in 5:
				for dx: int in 6:
					if not sim_a.world.is_walkable(x + dx, y + dy):
						clear = false
			if clear:
				ox = x
				oy = y
				break
		if oy >= 0:
			break
	_check(ox >= 0, "found a walkable house site")

	# Perimeter walls with one door, a bed inside — placed on both sims.
	var sims: Array[Simulation] = [sim_a, sim_b]
	var wall_count := 0
	for s: Simulation in sims:
		wall_count = 0
		for dx: int in 6:
			for dy: int in 5:
				var edge := dx == 0 or dy == 0 or dx == 5 or dy == 4
				if not edge:
					continue
				if dx == 2 and dy == 4:
					var _d: bool = s.place_blueprint(ox + dx, oy + dy, SimWorld.STRUCT_DOOR)
				else:
					var placed: bool = s.place_blueprint(ox + dx, oy + dy, SimWorld.STRUCT_WALL)
					if placed:
						wall_count += 1
		var _b: bool = s.place_blueprint(ox + 2, oy + 2, SimWorld.STRUCT_BED)
		s.spawn_actors(10)
	_check(wall_count > 10, "perimeter wall blueprints placed (%d)" % wall_count)
	_check(sim_a.blueprints.cells.size() == wall_count + 2, "blueprint ledger matches")

	var slept_on_bed := false
	for t: int in 5400:
		sim_a.tick()
		sim_b.tick()
		if t % 25 == 0:
			for i: int in sim_a.actors.count:
				var cell := floori(sim_a.actors.positions[i].y) * sim_a.world.width \
					+ floori(sim_a.actors.positions[i].x)
				if sim_a.world.structure_at_cell(cell) == SimWorld.STRUCT_BED:
					slept_on_bed = true

	_check(sim_a.blueprints.cells.size() == 0, "all blueprints completed")
	var built_walls := 0
	var built_door := false
	var built_bed := false
	for cell: int in sim_a.world.width * sim_a.world.height:
		match sim_a.world.structure_at_cell(cell):
			SimWorld.STRUCT_WALL:
				built_walls += 1
			SimWorld.STRUCT_DOOR:
				built_door = true
			SimWorld.STRUCT_BED:
				built_bed = true
	_check(built_walls == wall_count, "all walls built (%d)" % built_walls)
	_check(built_door, "door built")
	_check(built_bed, "bed built")
	_check(not sim_a.world.is_walkable(ox, oy), "built wall blocks movement")
	_check(sim_a.world.is_walkable(ox + 2, oy + 4), "built door stays walkable")
	_check(slept_on_bed, "a tired pawn slept on the bed")

	var on_walkable := true
	for i: int in sim_a.actors.count:
		var p := sim_a.actors.positions[i]
		if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
			on_walkable = false
	_check(on_walkable, "no pawn ended up inside a wall")
	_check(
		sim_a.actors.positions == sim_b.actors.positions
			and sim_a.world.structures == sim_b.world.structures,
		"building run fully deterministic"
	)


func _test_simulation() -> void:
	print("Simulation:")
	var sim_a := Simulation.new(7, 96, 96)
	var sim_b := Simulation.new(7, 96, 96)
	sim_a.spawn_actors(20)
	sim_b.spawn_actors(20)

	var spawn_positions := sim_a.actors.positions.duplicate()
	var all_walkable := true
	for i: int in sim_a.actors.count:
		var p := sim_a.actors.positions[i]
		if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
			all_walkable = false
	_check(all_walkable, "actors spawn on walkable tiles")

	var stayed_walkable := true
	var check_walkable := func() -> void:
		for i: int in sim_a.actors.count:
			var p := sim_a.actors.positions[i]
			if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
				stayed_walkable = false

	for t: int in 150:
		sim_a.tick()
		sim_b.tick()
		if t % 50 == 0:
			check_walkable.call()
	_check(sim_a.actors.positions == sim_b.actors.positions, "150 wander ticks deterministic")
	_check(sim_a.actors.positions != spawn_positions, "actors actually move")

	# Rally everyone to a walkable cell near the map center.
	var rx := -1
	var ry := -1
	for r: int in 40:
		if sim_a.world.is_walkable(48 + r, 48):
			rx = 48 + r
			ry = 48
			break
	_check(rx >= 0, "found a walkable rally cell")
	_check(sim_a.set_command_target(rx, ry), "set_command_target accepts walkable cell")
	_check(not sim_a.set_command_target(0, 0), "set_command_target rejects border/unwalkable")
	var _ok: bool = sim_b.set_command_target(rx, ry)

	var rally_pos := Vector2(rx + 0.5, ry + 0.5)
	var someone_arrived := false
	for t: int in 900:
		sim_a.tick()
		sim_b.tick()
		if t % 25 == 0:
			check_walkable.call()
			for i: int in sim_a.actors.count:
				if sim_a.actors.positions[i].distance_to(rally_pos) < 2.0:
					someone_arrived = true
	_check(sim_a.actors.positions == sim_b.actors.positions, "rally + 900 ticks deterministic")
	_check(stayed_walkable, "actors never leave walkable ground")
	_check(someone_arrived, "actors reach the rally point")

	var still_responding := 0
	for i: int in sim_a.actors.count:
		if sim_a.actors.responding[i] == 1:
			still_responding += 1
	_check(
		still_responding < sim_a.actors.count,
		"arrivals revert to wandering (%d/%d still responding)" % [
			still_responding, sim_a.actors.count,
		]
	)
	_check(sim_a.tick_count == 1050, "tick count advances")
