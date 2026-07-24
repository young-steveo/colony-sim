class_name Reachability
extends RefCounted
## Small bounded reachability queries against the live world (fields are
## async and stale by design; these answer "right now" questions).


## Flood-fill (4-connected) from a cell, pretending blocked_cell is a wall,
## stopping at `limit` cells. Returns the number of cells reached (capped at
## limit). A small result means from_cell would be sealed into a pocket —
## the Smarter Construction check: don't build yourself in.
static func pocket_size(world: SimWorld, from_cell: int, blocked_cell: int, limit: int) -> int:
	if from_cell == blocked_cell:
		return 0
	var frontier := PackedInt32Array()
	var _e: bool = frontier.push_back(from_cell)
	var visited := {from_cell: true}
	var reached := 0
	var w := world.width
	while not frontier.is_empty() and reached < limit:
		var cell := frontier[frontier.size() - 1]
		var _e2: int = frontier.resize(frontier.size() - 1)
		reached += 1
		var x := cell % w
		@warning_ignore("integer_division")
		var y := cell / w
		for d: int in 4:
			var nx := x + FlowField.DX[d]
			var ny := y + FlowField.DY[d]
			var ncell := ny * w + nx
			if ncell == blocked_cell or visited.has(ncell):
				continue
			if not world.is_walkable(nx, ny):
				continue
			visited[ncell] = true
			var _e3: bool = frontier.push_back(ncell)
	return reached
