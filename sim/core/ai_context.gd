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
var build_workers := 0  # pawns currently on the build action (last tick's count)
