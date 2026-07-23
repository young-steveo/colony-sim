extends SceneTree
## Sim-core stress test (no rendering): measures ms/tick at rising actor
## counts. Run with:
##   godot --path . --headless --script res://tests/benchmark.gd
## GDD context: "Performance Is a Goal, Fun Wins" — ambition is ~500 actors
## at full speed; this harness tells us the truth as systems get heavier.

const COUNTS := [100, 300, 500, 1000, 2000, 5000]
const WARMUP_TICKS := 60
const MEASURED_TICKS := 600


func _init() -> void:
	print("actors | ms/tick | %% of 30tps frame budget (33.3 ms)")
	for n: int in COUNTS:
		var sim := Simulation.new(42)
		sim.actors.spawn(sim.world, n)
		for t: int in WARMUP_TICKS:
			sim.tick()
		var t0 := Time.get_ticks_usec()
		for t: int in MEASURED_TICKS:
			sim.tick()
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / MEASURED_TICKS
		print("%6d | %7.3f | %5.1f%%" % [n, ms, ms / 33.333 * 100.0])
	quit(0)
