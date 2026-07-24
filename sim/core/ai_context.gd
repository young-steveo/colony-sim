class_name AiContext
extends RefCounted
## Everything a pawn's decision and execution can read, bundled once per
## tick by Simulation. Keeps ActorPool free of a Simulation reference and
## makes the brain's entire world-facing surface explicit — the sim-core
## equivalent of "AI acts only on its memory."

var defs: AiDefs
var world: SimWorld
var bushes: Bushes
var blueprints: Blueprints
var food_field: FlowField
var bed_field: FlowField
var blueprint_field: FlowField
var command_field: FlowField
var tick := 0
var build_capacity := 0  # workable frontier jobs right now (live)
# Sorted field distances of every pawn currently on the build action —
# lets the crowding input rank "how many builders are closer than me".
var builder_distances := PackedInt32Array()
var occupied: Dictionary = {}  # cell -> true for every pawn position at tick start
