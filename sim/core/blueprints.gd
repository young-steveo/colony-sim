class_name Blueprints
extends RefCounted
## Construction designations: the player paints blueprints, pawns build
## them. A blueprint is a world entity with a lifecycle — placed, worked on
## (possibly by several pawns across many ticks), completed into a
## structure. The hauling seam: when materials exist, an "awaiting
## materials" state slots in before "buildable" without touching anything
## else.

## Build effort in seconds of pawn work, by structure type.
const WORK_SECONDS: Dictionary = {
	SimWorld.STRUCT_WALL: 3.0,
	SimWorld.STRUCT_DOOR: 4.0,
	SimWorld.STRUCT_BED: 5.0,
}

# One builder per job: keeps future skill rolls, build failures, and XP
# attribution unambiguous (a "helper" mechanic can lift this someday).
const MAX_WORKERS_PER_CELL := 1

var cells := PackedInt32Array()
var types := PackedByteArray()
var work_done := PackedFloat32Array()
var workers := PackedByteArray()  # workers this tick; reset by the sim
var cell_lookup := {}
var version := 1  # bumps on place/cancel/complete — goal set changed


func has_at(cell: int) -> bool:
	return cell_lookup.has(cell)


func place(world: SimWorld, x: int, y: int, type: int) -> bool:
	if not world.is_walkable(x, y):
		return false
	var cell := y * world.width + x
	if world.structure_at_cell(cell) != SimWorld.STRUCT_NONE or cell_lookup.has(cell):
		return false
	cell_lookup[cell] = cells.size()
	var _e1: bool = cells.push_back(cell)
	var _e2: bool = types.push_back(type)
	var _e3: bool = work_done.push_back(0.0)
	var _e4: bool = workers.push_back(0)
	version += 1
	return true


func cancel(cell: int) -> bool:
	var idx: int = cell_lookup.get(cell, -1)
	if idx < 0:
		return false
	_remove(idx)
	version += 1
	return true


## Contribute work at this cell. Returns the completed structure type when
## the blueprint finishes (and removes it), or STRUCT_NONE otherwise.
func add_work(cell: int, seconds: float) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	if idx < 0:
		return SimWorld.STRUCT_NONE
	work_done[idx] += seconds
	var type := int(types[idx])
	var required: float = WORK_SECONDS[type]
	if work_done[idx] < required:
		return SimWorld.STRUCT_NONE
	_remove(idx)
	version += 1
	return type


func goal_cells() -> PackedInt32Array:
	return cells.duplicate()


## The build frontier: for each connected cluster of blueprints, its
## deepest cells (BFS depth from open walkable ground). Routing builders
## deepest-first makes solid fills complete inside-out — the Smarter
## Construction ordering — instead of sealing their own interiors off.
## Unreachable blueprints (no path from open ground) are excluded.
func frontier_goals(world: SimWorld) -> PackedInt32Array:
	var goals := PackedInt32Array()
	if cells.is_empty():
		return goals
	var w := world.width
	# Layered BFS inward: seed with blueprints touching open (non-blueprint,
	# walkable) ground at depth 1, then flood through blueprint adjacency.
	var depth := {}
	var frontier := PackedInt32Array()
	for b: int in cells.size():
		var cell := cells[b]
		var cx := cell % w
		@warning_ignore("integer_division")
		var cy := cell / w
		for d: int in 4:
			var nx := cx + FlowField.DX[d]
			var ny := cy + FlowField.DY[d]
			if world.is_walkable(nx, ny) and not cell_lookup.has(ny * w + nx):
				depth[cell] = 1
				var _e: bool = frontier.push_back(cell)
				break
	var current_depth := 1
	while not frontier.is_empty():
		var next_frontier := PackedInt32Array()
		current_depth += 1
		for cell: int in frontier:
			var cx := cell % w
			@warning_ignore("integer_division")
			var cy := cell / w
			for d: int in 4:
				var ncell := (cy + FlowField.DY[d]) * w + cx + FlowField.DX[d]
				if cell_lookup.has(ncell) and not depth.has(ncell):
					depth[ncell] = current_depth
					var _e2: bool = next_frontier.push_back(ncell)
		frontier = next_frontier
	# Per-cluster maxima: a cell is a goal if no deeper neighbor exists in
	# its cluster — i.e. its depth is not exceeded by any adjacent
	# blueprint's depth.
	for b: int in cells.size():
		var cell := cells[b]
		if not depth.has(cell):
			continue  # unreachable from open ground
		var my_depth: int = depth[cell]
		var cx := cell % w
		@warning_ignore("integer_division")
		var cy := cell / w
		var deepest := true
		for d: int in 4:
			var ncell := (cy + FlowField.DY[d]) * w + cx + FlowField.DX[d]
			if depth.get(ncell, 0) > my_depth:
				deepest = false
				break
		if deepest:
			var _e3: bool = goals.push_back(cell)
	return goals


func type_at(cell: int) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	return int(types[idx]) if idx >= 0 else SimWorld.STRUCT_NONE


func reset_workers() -> void:
	workers.fill(0)


## Register one worker on this cell for the current tick. Returns false if
## the cell is already at capacity.
func add_worker(cell: int) -> bool:
	var idx: int = cell_lookup.get(cell, -1)
	if idx < 0 or workers[idx] >= MAX_WORKERS_PER_CELL:
		return false
	workers[idx] += 1
	return true


## Swap-remove keeping the lookup consistent.
func _remove(idx: int) -> void:
	var _erased: bool = cell_lookup.erase(cells[idx])
	var last := cells.size() - 1
	if idx != last:
		cells[idx] = cells[last]
		types[idx] = types[last]
		work_done[idx] = work_done[last]
		workers[idx] = workers[last]
		cell_lookup[cells[idx]] = idx
	var _e1: int = cells.resize(last)
	var _e2: int = types.resize(last)
	var _e3: int = work_done.resize(last)
	var _e4: int = workers.resize(last)
