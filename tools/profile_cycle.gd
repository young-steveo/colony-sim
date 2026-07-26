extends SceneTree
## Material-cycle tick profiler. NOTE: headless ticks run back-to-back
## with zero wall time, so every field install blocks on its full 132 ms
## Dijkstra — this is the WORST case by construction. Live at 30 tps the
## 45-tick async latency gives workers 1.5 s per build; the numbers here
## are for relative comparison, not absolute budgets.


func _init() -> void:
	var simf := Simulation.new(41, 256, 256)
	var tf := Time.get_ticks_usec()
	var _f1 := FlowField.build(simf.world, simf.bushes.goal_cells())
	print("one 256x256 FlowField.build: %.1f ms" % (float(Time.get_ticks_usec() - tf) / 1000.0))

	var sim0 := Simulation.new(41, 256, 256)
	var w0 := sim0.world.width
	for cell: int in sim0.trees.cells.duplicate():
		@warning_ignore("integer_division")
		if maxi(absi(cell % w0 - 128), absi(cell / w0 - 128)) <= 30:
			var _d0: bool = sim0.designate_chop(cell % w0, cell / w0)
	var t_zero := Time.get_ticks_usec()
	for t: int in 600:
		sim0.tick()
	print("plans, ZERO actors: %.3f ms/tick" % (float(Time.get_ticks_usec() - t_zero) / 600000.0))

	var sim := Simulation.new(41, 256, 256)
	sim.spawn_actors(4)
	var t_base := Time.get_ticks_usec()
	for t: int in 600:
		sim.tick()
	print("baseline (trees exist, no plans): %.3f ms/tick"
			% (float(Time.get_ticks_usec() - t_base) / 600000.0))
	var w := sim.world.width
	@warning_ignore("integer_division")
	var cx := w / 2
	@warning_ignore("integer_division")
	var cy := sim.world.height / 2
	for cell: int in sim.trees.cells.duplicate():
		var tx := cell % w
		@warning_ignore("integer_division")
		var ty := cell / w
		if maxi(absi(tx - cx), absi(ty - cy)) <= 30:
			var _d: bool = sim.designate_chop(tx, ty)
	var placed := 0
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			if placed >= 6:
				break
			if sim.place_blueprint(cx + dx, cy + dy, SimWorld.STRUCT_WALL):
				placed += 1
	for chunk: int in 6:
		var t0 := Time.get_ticks_usec()
		for t: int in 300:
			sim.tick()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / 300.0
		print("ticks %d-%d: %.3f ms/tick (items v%d, bp v%d, trees v%d)" % [
			chunk * 300, chunk * 300 + 300, ms, sim.items.version,
			sim.blueprints.version, sim.trees.version,
		])
	quit()
