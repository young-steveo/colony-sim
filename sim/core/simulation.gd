class_name Simulation
extends RefCounted
## The sim root: owns all sim state and advances it one fixed tick at a time.
## The game layer decides when to call tick() (speed, pause); the sim itself
## has no concept of wall-clock time, rendering, or input.

const TICKS_PER_SECOND := 30
const TICK_DT := 1.0 / TICKS_PER_SECOND

var world: SimWorld
var actors: ActorPool
var tick_count := 0


func _init(world_seed: int, map_width := 256, map_height := 256) -> void:
	world = SimWorld.new(world_seed, map_width, map_height)
	actors = ActorPool.new()


func tick() -> void:
	actors.tick(world, TICK_DT)
	tick_count += 1
