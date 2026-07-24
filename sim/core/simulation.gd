class_name Simulation
extends RefCounted
## The sim root: owns all sim state and advances it one fixed tick at a time.
## The game layer decides when to call tick() (speed, pause); the sim itself
## has no concept of wall-clock time, rendering, or input.

const TICKS_PER_SECOND := 30
const TICK_DT := 1.0 / TICKS_PER_SECOND

# Walking-skeleton points of interest: stand-ins for future real
# destinations (stockpiles, work sites, home). Each gets one shared flow
# field that any number of actors path on.
const SITE_COUNT := 6
const SITE_MIN_SEPARATION := 48.0

var world: SimWorld
var actors: ActorPool
var sites := PackedInt32Array()
var fields: Array[FlowField] = []
var tick_count := 0


func _init(world_seed: int, map_width := 256, map_height := 256) -> void:
	world = SimWorld.new(world_seed, map_width, map_height)
	_place_sites()
	for site: int in sites:
		fields.append(FlowField.build(world, PackedInt32Array([site])))
	actors = ActorPool.new()


func tick() -> void:
	actors.tick(world, fields, TICK_DT)
	tick_count += 1


func _place_sites() -> void:
	var s := SimRng.stream(SimRng.key([world.world_seed, "sites"]))
	var attempts := 0
	while sites.size() < SITE_COUNT and attempts < 400:
		attempts += 1
		var x := s.next_range(0, world.width - 1)
		var y := s.next_range(0, world.height - 1)
		if not world.is_walkable(x, y):
			continue
		# Spread sites out unless the map makes us settle.
		var min_sep := SITE_MIN_SEPARATION if attempts < 200 else 8.0
		var pos := Vector2(x, y)
		var too_close := false
		for site: int in sites:
			@warning_ignore("integer_division")
			var sp := Vector2(site % world.width, site / world.width)
			if pos.distance_to(sp) < min_sep:
				too_close = true
				break
		if not too_close:
			sites.push_back(y * world.width + x)
