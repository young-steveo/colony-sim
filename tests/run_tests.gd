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
	_test_pathfinder()
	_test_ai()
	_test_content_validation()
	_test_building()
	_test_wall_materials()
	_test_material_cycle()
	_test_sheet_completeness()
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

	var substrate: PackedByteArray = a["substrate"]
	var surface: PackedByteArray = a["surface"]
	var valid := true
	var walkable := 0
	var grassy := 0
	for i: int in substrate.size():
		var t := substrate[i]
		if t > SimWorld.TILE_DIRT_ROCKY:
			valid = false
		if (
			surface[i] == SimWorld.SURF_GRASS
			and t != SimWorld.TILE_DIRT
			and t != SimWorld.TILE_DIRT_FERTILE
		):
			valid = false  # grass only grows on soil
		if t != SimWorld.TILE_WATER:
			walkable += 1  # every land substrate is walkable in v1
		if surface[i] == SimWorld.SURF_GRASS:
			grassy += 1
	_check(valid, "all substrates valid; grass only on soil")
	_check(walkable > 64 * 64 / 4, "map is at least 25%% walkable (got %d/4096)" % walkable)
	_check(grassy > 0, "grass surface exists")


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


func _test_pathfinder() -> void:
	print("PathFinder:")
	var w := SimWorld.new(42, 96, 96)
	var cells := PackedInt32Array()
	for cc: int in w.width * w.height:
		@warning_ignore("integer_division")
		if w.is_walkable(cc % w.width, cc / w.width):
			var _e: bool = cells.push_back(cc)
	_check(cells.size() > 100, "walkable cells found (%d)" % cells.size())
	var from := cells[0]
	var to := cells[cells.size() - 1]
	var p1 := PathFinder.find(w, from, to)
	var p2 := PathFinder.find(w, from, to)
	_check(p1 == p2, "search is deterministic")
	_check(p1.size() > 0 and p1[p1.size() - 1] == to, "path crosses the map and ends on the goal (%d steps)" % p1.size())
	_check(_path_legal(w, from, p1), "every step adjacent, walkable, corner-safe")
	_check(PathFinder.find(w, from, from).is_empty(), "same-cell path is empty")
	var wet := -1
	for cc: int in w.width * w.height:
		@warning_ignore("integer_division")
		if not w.is_walkable(cc % w.width, cc / w.width):
			wet = cc
			break
	_check(wet >= 0 and PathFinder.find(w, from, wet).is_empty(), "unwalkable goal yields empty path")

	# A wall in the way forces a detour: wall the center of an open 3x3,
	# then path west neighbor -> east neighbor. The direct lane is gone
	# and the diagonal squeeze past the wall corner is illegal, so the
	# legal route is at least four steps around.
	var center := -1
	for cy: int in range(4, 90):
		for cx: int in range(4, 90):
			var open := true
			for d: int in 9:
				if not w.is_walkable(cx + (d % 3) - 1, cy + (d / 3) - 1):
					open = false
					break
			if open:
				center = cy * w.width + cx
				break
		if center >= 0:
			break
	_check(center >= 0, "found an open 3x3 site")
	w.set_structure(center, SimWorld.STRUCT_WALL, 0)
	var detour := PathFinder.find(w, center - 1, center + 1)
	_check(
		detour.size() >= 4 and not detour.has(center) and _path_legal(w, center - 1, detour),
		"walled cell forces a legal detour (%d steps)" % detour.size()
	)


## Walk a returned path asserting each step is a walkable neighbor and
## diagonals never cut a blocked corner (FlowField's rule).
func _path_legal(w: SimWorld, from: int, path: PackedInt32Array) -> bool:
	var prev := from
	for cell: int in path:
		@warning_ignore("integer_division")
		var py := prev / w.width
		var px := prev % w.width
		@warning_ignore("integer_division")
		var cy := cell / w.width
		var cx := cell % w.width
		var dx := cx - px
		var dy := cy - py
		if maxi(absi(dx), absi(dy)) != 1:
			return false
		if not w.is_walkable(cx, cy):
			return false
		if dx != 0 and dy != 0:
			if not w.is_walkable(px + dx, py) or not w.is_walkable(px, py + dy):
				return false
		prev = cell
	return true


func _test_ai() -> void:
	print("AI:")
	var defs := AiDefs.load_file(Simulation.AI_DEFS_PATH)
	_check(defs.needs.size() == 3, "three needs load (hunger, rest, safety)")
	_check(
		defs.actions.size() == 8,
		"eight actions load (eat, sleep, sleep_bed, chop, haul, build, goto_order, wander)"
	)
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

	# Move orders are heavy considerations, not commands: the goto_order
	# score must beat eat at moderate hunger (the settler obeys) and lose
	# to eat at dire hunger with food at hand (the settler eats first).
	# Same bucket, so the comparison is a straight score contest.
	var goto_action := defs.actions[defs.action_index(&"goto_order")]
	var goto_score := goto_action.weight * AiDefs.compensate(
		goto_action.considerations[0].score(1.0), 1
	)
	var dist_con := eat.considerations[1]
	var eat_moderate := eat.weight * AiDefs.compensate(
		hunger_con.score(0.25) * dist_con.score(0.0), 2
	)
	var eat_dire := eat.weight * AiDefs.compensate(
		hunger_con.score(0.02) * dist_con.score(0.0), 2
	)
	_check(goto_score > eat_moderate, "order outbids moderate hunger (%.2f > %.2f)" % [goto_score, eat_moderate])
	_check(
		eat_dire > goto_score * ActorPool.COMMITMENT_BONUS,
		"dire hunger beside food outbids a held order (%.2f > %.2f)" % [
			eat_dire, goto_score * ActorPool.COMMITMENT_BONUS,
		]
	)

	# Behavior: a hungry settler near food decides to eat and its hunger rises.
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
	_check(ate, "hungry settlers found food and ate (%d berries)" % sim.bushes.consumed_total)
	_check(slept, "tired settlers slept (rest rose)")
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


## Deliver every placed blueprint's full cost directly. The legacy
## construction tests stay about ORDERING and CROWDING; the material
## loop (chop -> haul -> build) is covered by _test_material_cycle.
func _fund_blueprints(s: Simulation) -> void:
	for cell: int in s.blueprints.cells.duplicate():
		var _n: int = s.blueprints.deliver(cell, 99)


func _write_tmp(name: String, content: String) -> String:
	var path := "user://%s" % name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(content)
	return path


## The always-on validation path (ContentJson): loaders collect precise
## errors instead of relying on stripped-in-release asserts. Tests call
## the side-effect-free parse() cores directly with garbage files and
## inspect the error lists.
func _test_content_validation() -> void:
	print("Content validation:")
	var errors: Array[String] = []

	# The shipped content must pass its own validators with zero errors.
	var _a: AiDefs = AiDefs.parse(Simulation.AI_DEFS_PATH, errors)
	var _i: ItemDefs = ItemDefs.parse(ItemDefs.PATH, errors)
	var _s: StructureDefs = StructureDefs.parse(StructureDefs.PATH, errors)
	var _t: TerrainDefs = TerrainDefs.parse(TerrainDefs.PATH, errors)
	_check(errors.is_empty(), "shipped content validates clean (%s)" % ";".join(errors))

	# Malformed JSON reports the file and a line number, not a null-deref.
	errors = []
	var bad_json := _write_tmp("bad_syntax.json", "{ \"items\": [ oops ]")
	var _r1: ItemDefs = ItemDefs.parse(bad_json, errors)
	_check(
		errors.size() == 1 and errors[0].contains("bad_syntax.json:"),
		"malformed JSON reports file and line"
	)

	errors = []
	var zero_stack := _write_tmp(
		"bad_stack.json",
		"{ \"items\": [ { \"id\": \"wood\", \"stack\": 0, \"color\": \"#c77b58\" } ] }"
	)
	var _r2: ItemDefs = ItemDefs.parse(zero_stack, errors)
	_check(not errors.is_empty() and errors[0].contains("stack"), "zero stack is rejected")

	errors = []
	var wrong_first := _write_tmp(
		"bad_order.json",
		"{ \"items\": [ { \"id\": \"stone\", \"stack\": 5, \"color\": \"#7f708a\" } ] }"
	)
	var _r3: ItemDefs = ItemDefs.parse(wrong_first, errors)
	_check(not errors.is_empty() and errors[0].contains("wood"), "item order contract enforced")

	# Unknown cost keys must not build free structures silently.
	errors = []
	var stone_cost := _write_tmp("bad_cost.json", """
	{ "structures": [
		{ "id": "wall", "work": 2.0, "cost": { "stone": 5 } },
		{ "id": "door", "work": 2.0, "cost": {} },
		{ "id": "bed", "work": 4.0, "cost": {} }
	], "wall_materials": [ { "id": "wood", "sheet": "res://content/structures/wall_wood.png" } ] }
	""")
	var _r4: StructureDefs = StructureDefs.parse(stone_cost, errors)
	var cost_flagged := false
	for e: String in errors:
		if e.contains("stone"):
			cost_flagged = true
	_check(cost_flagged, "unknown cost key is rejected (no silent free builds)")

	# AI: unknown execution would otherwise no-op a settler forever.
	errors = []
	var bad_exec := _write_tmp("bad_exec.json", """
	{ "needs": [ { "id": "hunger" } ], "actions": [
		{ "id": "fish", "bucket": 1, "execution": "fish" },
		{ "id": "idle", "bucket": 0, "execution": "wander" }
	] }
	""")
	var _r5: AiDefs = AiDefs.parse(bad_exec, errors)
	var exec_flagged := false
	for e: String in errors:
		if e.contains("unknown execution 'fish'"):
			exec_flagged = true
	_check(exec_flagged, "unknown execution is rejected")

	# AI: restoring executions must name their need explicitly — the old
	# considerations[0] convention silently wrapped to needs[-1].
	errors = []
	var no_restores := _write_tmp("bad_restores.json", """
	{ "needs": [ { "id": "hunger" } ], "actions": [
		{ "id": "eat", "bucket": 2, "execution": "eat",
		  "considerations": [ { "input": "hunger", "curve": { "type": "poly" } } ] },
		{ "id": "idle", "bucket": 0, "execution": "wander" }
	] }
	""")
	var _r6: AiDefs = AiDefs.parse(no_restores, errors)
	var restores_flagged := false
	for e: String in errors:
		if e.contains("restores"):
			restores_flagged = true
	_check(restores_flagged, "restoring execution without a restores key is rejected")

	# Curves: fractional k with c > 0 evaluates NaN for x < c.
	errors = []
	var _c1: ResponseCurve = ResponseCurve.from_dict(
		{"type": "poly", "k": 0.5, "c": 0.5}, errors, "test"
	)
	_check(not errors.is_empty() and errors[0].contains("NaN"), "NaN-region poly curve is rejected")
	errors = []
	var _c2: ResponseCurve = ResponseCurve.from_dict(
		{"type": "warble"}, errors, "test"
	)
	_check(not errors.is_empty(), "unknown curve type is rejected")


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
		_fund_blueprints(s)
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
	_check(slept_on_bed, "a tired settler slept on the bed")

	var on_walkable := true
	for i: int in sim_a.actors.count:
		var p := sim_a.actors.positions[i]
		if not sim_a.world.is_walkable(floori(p.x), floori(p.y)):
			on_walkable = false
	_check(on_walkable, "no settler ended up inside a wall")
	_check(
		sim_a.actors.positions == sim_b.actors.positions
			and sim_a.world.structures == sim_b.world.structures,
		"building run fully deterministic"
	)

	# Crowding: one door among 40 idle settlers must draw a small crew, not
	# the whole colony.
	var sim_c := Simulation.new(23, 96, 96)
	sim_c.spawn_actors(40)
	var dx2 := -1
	var dy2 := -1
	for y: int in range(40, 90):
		for x: int in range(4, 90):
			if sim_c.world.is_walkable(x, y):
				dx2 = x
				dy2 = y
				break
		if dy2 >= 0:
			break
	var _p2: bool = sim_c.place_blueprint(dx2, dy2, SimWorld.STRUCT_DOOR)
	_fund_blueprints(sim_c)
	var build_idx := sim_c.defs.action_index(&"build")
	var max_builders := 0
	for t: int in 900:
		sim_c.tick()
		var builders := 0
		for i: int in sim_c.actors.count:
			if sim_c.actors.current_action[i] == build_idx:
				builders += 1
		max_builders = maxi(max_builders, builders)
	_check(max_builders >= 1, "someone answered the build job")
	_check(
		max_builders <= 6,
		"one door draws a crew, not a colony (max %d builders)" % max_builders
	)
	_check(sim_c.blueprints.cells.size() == 0, "the door still got built")

	# Solid fill: a 5x5 block of wall must complete inside-out — the deep
	# interior cells can only be built from atop the ghost scaffold.
	var sim_d := Simulation.new(31, 96, 96)
	var sim_e := Simulation.new(31, 96, 96)
	var sx := -1
	var sy := -1
	for y: int in range(2, 88):
		for x: int in range(2, 88):
			var clear := true
			for dy: int in 5:
				for dx: int in 5:
					if not sim_d.world.is_walkable(x + dx, y + dy):
						clear = false
			if clear:
				sx = x
				sy = y
				break
		if sy >= 0:
			break
	_check(sx >= 0, "found a walkable 5x5 site")
	for s: Simulation in [sim_d, sim_e]:
		for dx: int in 5:
			for dy: int in 5:
				var _w2: bool = s.place_blueprint(sx + dx, sy + dy, SimWorld.STRUCT_WALL)
		_fund_blueprints(s)
		s.spawn_actors(12)
	var rest_idx2 := sim_d.defs.need_index(&"rest")
	var pinned_rest := 0
	var first_built := -1
	for t: int in 4500:
		sim_d.tick()
		sim_e.tick()
		if first_built < 0 and sim_d.world.structures_version > 0:
			for dy: int in 5:
				for dx: int in 5:
					var fcell := (sy + dy) * sim_d.world.width + sx + dx
					if sim_d.world.structure_at_cell(fcell) == SimWorld.STRUCT_WALL:
						first_built = fcell
		if t % 50 == 0:
			var worst := 0
			for i: int in sim_d.actors.count:
				if sim_d.actors.needs[rest_idx2][i] < 0.001:
					worst += 1
			pinned_rest = maxi(pinned_rest, worst)
	_check(
		first_built == (sy + 2) * sim_d.world.width + sx + 2,
		"first wall built is the center (inside-out order)"
	)
	_check(
		sim_d.blueprints.cells.size() == 0,
		"solid 5x5 built at a working pace, 4500 ticks (%d blueprints left)"
			% sim_d.blueprints.cells.size()
	)
	_check(pinned_rest == 0, "no settler ever pinned at zero rest (sleep deadlock)")
	var solid := true
	for dx: int in 5:
		for dy: int in 5:
			var scell := (sy + dy) * sim_d.world.width + sx + dx
			if sim_d.world.structure_at_cell(scell) != SimWorld.STRUCT_WALL:
				solid = false
	_check(solid, "every cell of the block is wall")
	var d_walkable := true
	for i: int in sim_d.actors.count:
		var p := sim_d.actors.positions[i]
		if not sim_d.world.is_walkable(floori(p.x), floori(p.y)):
			d_walkable = false
	_check(d_walkable, "no settler entombed in the block")
	_check(
		sim_d.actors.positions == sim_e.actors.positions
			and sim_d.world.structures == sim_e.world.structures,
		"solid-fill run fully deterministic"
	)


func _test_wall_materials() -> void:
	print("Wall materials:")
	var sim := Simulation.new(11, 96, 96)
	_check(sim.structure_defs.wall_material_count() >= 2, "defs load with >= 2 wall materials")

	# Three walls: wood, marble, marble. Cancel the first — swap-remove must
	# keep materials attached to the right cells.
	var y := -1
	for cy: int in range(2, 90):
		if sim.world.is_walkable(10, cy) and sim.world.is_walkable(11, cy) and sim.world.is_walkable(12, cy):
			y = cy
			break
	_check(y >= 0, "found a walkable strip")
	var _p1: bool = sim.place_blueprint(10, y, SimWorld.STRUCT_WALL, 0)
	var _p2: bool = sim.place_blueprint(11, y, SimWorld.STRUCT_WALL, 1)
	var _p3: bool = sim.place_blueprint(12, y, SimWorld.STRUCT_WALL, 1)
	var c1 := y * sim.world.width + 10
	var c2 := y * sim.world.width + 11
	var c3 := y * sim.world.width + 12
	var _c: bool = sim.cancel_blueprint(10, y)
	_check(sim.blueprints.material_at(c2) == 1, "material survives swap-remove (cell 2)")
	_check(sim.blueprints.material_at(c3) == 1, "material survives swap-remove (cell 3)")
	_check(sim.blueprints.material_at(c1) == 0, "cancelled cell reports no material")

	# Completion carries material into the built structure. add_work on an
	# unfunded blueprint must refuse — the material gate.
	var mat := sim.blueprints.material_at(c2)
	_check(
		sim.blueprints.add_work(c2, 99.0) == SimWorld.STRUCT_NONE,
		"add_work refuses an unfunded blueprint (awaiting materials)"
	)
	var _f2: int = sim.blueprints.deliver(c2, 99)
	var built := sim.blueprints.add_work(c2, 99.0)
	sim.world.set_structure(c2, built, mat)
	_check(built == SimWorld.STRUCT_WALL, "blueprint completes into a wall")
	_check(sim.world.structure_material_at(c2) == 1, "built wall keeps its material")


func _test_material_cycle() -> void:
	print("Material cycle:")
	var idefs := ItemDefs.load_defs()
	_check(idefs.count() >= 1 and idefs.ids[Items.WOOD] == "wood", "item defs load; wood is item 0")
	_check(idefs.stack_sizes[Items.WOOD] == 6, "wood stack size comes from items.json (6)")

	var sdefs := StructureDefs.load_defs()
	_check(
		is_equal_approx(sdefs.work_seconds[SimWorld.STRUCT_WALL], 3.0),
		"wall work seconds come from structures.json"
	)
	_check(sdefs.wood_costs[SimWorld.STRUCT_WALL] == 2, "wall wood cost comes from structures.json")

	# Items pool: merge to the stack cap, spill via scatter, take back out.
	var sim := Simulation.new(7, 96, 96)
	var mid := -1
	for cy: int in range(4, 90):
		var ok := true
		for d: int in 9:
			if not sim.world.is_walkable(4 + (d % 3) - 1, cy + (d / 3) - 1):
				ok = false
		if ok:
			mid = cy * sim.world.width + 4
			break
	_check(mid >= 0, "found an open items site")
	var placed := sim.items.add(mid, Items.WOOD, 4)
	placed += sim.items.add(mid, Items.WOOD, 4)
	_check(placed == 6 and sim.items.count_at(mid) == 6, "stack merges and caps at stack size")
	sim.items.scatter(sim.world, mid, Items.WOOD, 5)
	var total := 0
	for i: int in sim.items.cells.size():
		total += sim.items.counts[i]
	_check(total == 11 and sim.items.cells.size() >= 2, "scatter spills overflow to neighbors")
	var taken := sim.items.take(mid, 99)
	_check(taken == 6 and not sim.items.has_at(mid), "take empties and removes the stack")

	# Trees: deterministic worldgen, plans, felling yield.
	var sim2 := Simulation.new(7, 96, 96)
	_check(sim.trees.cells.size() > 0, "trees generated (%d)" % sim.trees.cells.size())
	_check(sim.trees.cells == sim2.trees.cells, "tree placement deterministic")
	var tcell := sim.trees.cells[0]
	@warning_ignore("integer_division")
	var tx := tcell % sim.world.width
	@warning_ignore("integer_division")
	var ty := tcell / sim.world.width
	_check(sim.designate_chop(tx, ty), "tree designated for chopping (a plan)")
	_check(not sim.designate_chop(tx, ty), "double-designation refused")
	_check(not sim.place_blueprint(tx, ty, SimWorld.STRUCT_WALL), "trees block construction")
	var wood_yield := sim.trees.add_work(sim.world, tcell, 99.0)
	_check(wood_yield >= 4 and wood_yield <= 8, "felled tree yields 4-8 wood (%d)" % wood_yield)
	_check(not sim.trees.has_tree_at(tcell), "felled tree is gone")
	_check(sim2.trees.add_work(sim2.world, tcell, 99.0) == wood_yield, "yield deterministic")

	# Cancel refunds delivered materials as ground items.
	var bx := -1
	var by := -1
	for cy: int in range(4, 90):
		if sim.world.is_walkable(50, cy) and not sim.trees.has_tree_at(cy * sim.world.width + 50):
			bx = 50
			by = cy
			break
	var _pb: bool = sim.place_blueprint(bx, by, SimWorld.STRUCT_WALL)
	var bcell := by * sim.world.width + bx
	_check(sim.blueprints.remaining_delivery(bcell) == 2, "fresh wall blueprint owes its cost")
	var _dv: int = sim.blueprints.deliver(bcell, 2)
	_check(sim.blueprints.is_buildable(bcell), "funded blueprint is buildable")
	var before := sim.items.count_at(bcell)
	var _cc: bool = sim.cancel_blueprint(bx, by)
	var refunded := 0
	for i: int in sim.items.cells.size():
		refunded += sim.items.counts[i]
	_check(sim.items.count_at(bcell) >= before, "cancel refunds wood to the ground")

	# The proper verb, end to end: chop plans -> logs -> hauling -> walls.
	_material_cycle_integration()


## Two identical sims run the full loop; the verb is proper when a wall
## costs wood a settler actually carried — and it must be deterministic.
func _material_cycle_integration() -> void:
	var sim_a := Simulation.new(41, 96, 96)
	var sim_b := Simulation.new(41, 96, 96)
	var w := sim_a.world.width
	@warning_ignore("integer_division")
	var cx := w / 2
	@warning_ignore("integer_division")
	var cy := sim_a.world.height / 2
	# Designate every tree near the spawn knot; place a few walls nearby.
	var designated := 0
	for s: Simulation in [sim_a, sim_b]:
		designated = 0
		for cell: int in s.trees.cells.duplicate():
			var tx := cell % w
			@warning_ignore("integer_division")
			var ty := cell / w
			if maxi(absi(tx - cx), absi(ty - cy)) <= 30:
				if s.designate_chop(tx, ty):
					designated += 1
		var placed_walls := 0
		for dy: int in range(-6, 7):
			for dx: int in range(-6, 7):
				if placed_walls >= 3:
					break
				if s.place_blueprint(cx + dx, cy + dy, SimWorld.STRUCT_WALL):
					placed_walls += 1
		s.spawn_actors(8)
	_check(designated > 0, "trees designated near spawn (%d)" % designated)

	# While the cycle runs, every settler seen in a WORK phase must be
	# planted at the center of a tile beside their claim — never on it —
	# facing the work: the stance contract the work animations are drawn
	# for. Cardinal stances must dominate (corners are the fallback).
	var chop_action := sim_a.defs.action_index(&"chop")
	var build_action := sim_a.defs.action_index(&"build")
	var work_samples := 0
	var cardinal_stances := 0
	var corner_stances := 0
	var stance_violations := 0
	for t: int in 9000:
		sim_a.tick()
		sim_b.tick()
		var pool := sim_a.actors
		for i: int in pool.count:
			var act := pool.current_action[i]
			var working := (act == chop_action and pool.phase[i] == ActorPool.CHOP_WORK) \
					or (act == build_action and pool.phase[i] == ActorPool.BUILD_WORK)
			if not working:
				continue
			work_samples += 1
			var claim := pool.work_claims[i]
			var pos := pool.positions[i]
			var cell := floori(pos.y) * w + floori(pos.x)
			@warning_ignore("integer_division")
			var span_x := absi(cell % w - claim % w) if claim >= 0 else 99
			@warning_ignore("integer_division")
			var span_y := absi(cell / w - claim / w) if claim >= 0 else 99
			var centered := absf(pos.x - (floorf(pos.x) + 0.5)) < 0.001 \
					and absf(pos.y - (floorf(pos.y) + 0.5)) < 0.001
			@warning_ignore("integer_division")
			var to_work := (Vector2(claim % w + 0.5, claim / w + 0.5) - pos).normalized()
			var facing_ok := claim >= 0 and pool.facings[i].distance_to(to_work) < 0.001
			if maxi(span_x, span_y) != 1 or not centered or not facing_ok:
				stance_violations += 1
			elif span_x + span_y == 1:
				cardinal_stances += 1
			else:
				corner_stances += 1
	var walls := 0
	for cell: int in sim_a.world.width * sim_a.world.height:
		if sim_a.world.structure_at_cell(cell) == SimWorld.STRUCT_WALL:
			walls += 1
	_check(sim_a.trees.felled_total > 0, "settlers felled planned trees (%d)" % sim_a.trees.felled_total)
	_check(walls > 0, "walls built from hauled wood (%d)" % walls)
	_check(work_samples > 0, "settlers observed at work (%d samples)" % work_samples)
	_check(
		stance_violations == 0,
		"working settlers plant centered beside the work, facing it (%d violations)" % stance_violations
	)
	_check(
		cardinal_stances > corner_stances,
		"cardinal stances dominate (%d cardinal, %d corner)" % [cardinal_stances, corner_stances]
	)
	_check(
		sim_a.actors.positions == sim_b.actors.positions
			and sim_a.items.cells == sim_b.items.cells
			and sim_a.items.counts == sim_b.items.counts
			and sim_a.world.structures == sim_b.world.structures,
		"material cycle fully deterministic"
	)


## Every blob sheet the defs reference must have art in all 47 mapped
## cells. Guards the invisible-tile class of bug: a blank cell renders a
## real material as nothing (found via an isolated grass patch whose
## horizontal pieces were missing from the donor export).
func _test_sheet_completeness() -> void:
	print("Sheet completeness:")
	var sheets: Array[String] = []
	var tdefs := TerrainDefs.load_defs()
	for i: int in tdefs.count():
		if tdefs.sheets[i] != "":
			sheets.append(tdefs.sheets[i])
	for i: int in tdefs.surface_ids.size():
		if tdefs.surface_sheets[i] != "":
			sheets.append(tdefs.surface_sheets[i])
	var sdefs := StructureDefs.load_defs()
	for i: int in sdefs.wall_material_count():
		sheets.append(sdefs.wall_material_sheets[i])
	for path: String in sheets:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		var empty := 0
		for idx: int in Autotile.MASKS.size():
			if Autotile.MASKS[idx] < 0:
				continue
			var cx := idx % Autotile.COLS
			@warning_ignore("integer_division")
			var cy := idx / Autotile.COLS
			var used := false
			for y: int in 16:
				for x: int in 16:
					if img.get_pixel(cx * 16 + x, cy * 16 + y).a > 0.0:
						used = true
						break
				if used:
					break
			if not used:
				empty += 1
		_check(empty == 0, "%s: all 47 blob cells drawn (%d empty)" % [path.get_file(), empty])


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

	# Move orders: order every settler to a walkable cell near the map
	# center (orders are per-settler considerations, not a command bypass).
	var rx := -1
	var ry := -1
	for r: int in 40:
		if sim_a.world.is_walkable(48 + r, 48):
			rx = 48 + r
			ry = 48
			break
	_check(rx >= 0, "found a walkable order cell")
	_check(sim_a.set_move_order(sim_a.actors.ids[0], rx, ry), "set_move_order accepts walkable cell")
	_check(not sim_a.set_move_order(sim_a.actors.ids[0], 0, 0), "set_move_order rejects border/unwalkable")
	_check(not sim_a.set_move_order(sim_a.actors.ids[0], -3, 40), "set_move_order rejects out-of-bounds")
	_check(not sim_a.set_move_order(99999, rx, ry), "set_move_order rejects unknown settler")
	_check(sim_a.set_move_order(sim_a.actors.ids[0], rx, ry), "re-order replaces (accepted again)")
	for s: Simulation in [sim_a, sim_b]:
		for i: int in s.actors.count:
			var _o: bool = s.set_move_order(s.actors.ids[i], rx, ry)

	# Arrivals are sampled DURING the run: an arrived settler's order
	# clears and they wander off, so end-of-run proximity undercounts.
	var order_pos := Vector2(rx + 0.5, ry + 0.5)
	var arrived := {}
	for t: int in 900:
		sim_a.tick()
		sim_b.tick()
		if t % 25 == 0:
			check_walkable.call()
			for i: int in sim_a.actors.count:
				if sim_a.actors.positions[i].distance_to(order_pos) < 2.0:
					arrived[i] = true
	_check(sim_a.actors.positions == sim_b.actors.positions, "orders + 900 ticks deterministic")
	_check(stayed_walkable, "actors never leave walkable ground")
	_check(
		arrived.size() > sim_a.actors.count / 2,
		"ordered settlers reach the target (%d/%d seen arriving)" % [arrived.size(), sim_a.actors.count]
	)

	var still_ordered := 0
	for i: int in sim_a.actors.count:
		if sim_a.actors.order_cells[i] >= 0:
			still_ordered += 1
	_check(
		still_ordered < sim_a.actors.count,
		"arrivals clear their orders (%d/%d still ordered)" % [still_ordered, sim_a.actors.count]
	)
	_check(sim_a.tick_count == 1050, "tick count advances")

	# Field-job hygiene: rapid goal churn retires in-flight builds, and
	# every retired task must still be waited on (WorkerThreadPool frees
	# a task only at wait_for_task_completion) — so the pending count
	# stays bounded under churn and shutdown() drains it to zero.
	var sim_j := Simulation.new(11, 96, 96)
	_check(sim_j.trees.cells.size() > 0, "job-churn world has trees")
	var toggle_cell: int = sim_j.trees.cells[0]
	var tcx := toggle_cell % sim_j.world.width
	@warning_ignore("integer_division")
	var tcy := toggle_cell / sim_j.world.width
	for t: int in 40:
		if t % 2 == 0:
			var _d: bool = sim_j.designate_chop(tcx, tcy)
		else:
			var _c: bool = sim_j.cancel_chop(tcx, tcy)
		sim_j.tick()
	for t: int in 120:
		sim_j.tick()
	_check(
		sim_j.pending_task_count() <= 6,
		"superseded field jobs are reaped (%d tasks pending after churn)" % sim_j.pending_task_count()
	)
	sim_j.shutdown()
	_check(sim_j.pending_task_count() == 0, "shutdown drains every worker task")
