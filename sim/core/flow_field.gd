class_name FlowField
extends RefCounted
## Dijkstra map / flow field (see GDD toolbox: "The Incredible Power of
## Dijkstra Maps"). Built once from a set of goal cells, then any number of
## actors path toward the goals by "rolling downhill" — one array lookup per
## step, no per-actor search. Integer costs (10 orthogonal, 14 diagonal) via
## Dial's bucket queue: exact, deterministic, float-free.

const COST_ORTH := 10
const COST_DIAG := 14
const UNREACHABLE := 2147483647
const NO_DIR := 255
const _RING := COST_DIAG + 1  # Dial's algorithm bucket ring size

# Neighbor order (also direction ids): 4 orthogonal, then 4 diagonal.
# Tie-breaks resolve to the lowest id, so orthogonal moves win ties.
const DX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const DY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]

var width: int
var height: int
var distances := PackedInt32Array()
var flow_dir := PackedByteArray()


static func build(world: SimWorld, goal_cells: PackedInt32Array) -> FlowField:
	return build_from_walk(world.width, world.height, world.walkability_snapshot(), goal_cells)


## Pure-data build: walkability comes in as a snapshot, so this is safe to
## run on a worker thread while the live world keeps mutating.
static func build_from_walk(
	map_width: int, map_height: int, walk: PackedByteArray, goal_cells: PackedInt32Array
) -> FlowField:
	var f := FlowField.new()
	f._build(map_width, map_height, walk, goal_cells)
	return f


func is_reachable_cell(cell: int) -> bool:
	return distances[cell] != UNREACHABLE


## Direction to step from this cell toward the goals, as a tile-space vector.
func direction_at_cell(cell: int) -> Vector2i:
	var d := flow_dir[cell]
	if d == NO_DIR:
		return Vector2i.ZERO
	return Vector2i(DX[d], DY[d])


func _build(
	map_width: int, map_height: int, walk: PackedByteArray, goal_cells: PackedInt32Array
) -> void:
	width = map_width
	height = map_height
	var cell_count := width * height

	# The snapshot's border ring is 0 (SimWorld.walkability_snapshot), so
	# neighbor arithmetic below never needs bounds checks: no interior
	# cell's neighbor offset can escape the array.

	# Neighbor cell-index offsets in DX/DY order, plus the two orthogonal
	# offsets that gate each diagonal (corner-cutting rule).
	var noff := PackedInt32Array([
		1, -1, width, -width, width + 1, -width + 1, width - 1, -width - 1,
	])
	var orth_a := PackedInt32Array([0, 0, 0, 0, 1, 1, -1, -1])
	var orth_b := PackedInt32Array([0, 0, 0, 0, width, -width, width, -width])

	var _err2: int = distances.resize(cell_count)
	distances.fill(UNREACHABLE)
	var _err3: int = flow_dir.resize(cell_count)
	flow_dir.fill(NO_DIR)

	# Dial's algorithm: ring of (max edge cost + 1) buckets keyed by cost.
	var ring: Array[PackedInt32Array] = []
	for r: int in _RING:
		ring.append(PackedInt32Array())
	var pending := 0
	for g: int in goal_cells:
		if walk[g] == 1 and distances[g] != 0:
			distances[g] = 0
			@warning_ignore("return_value_discarded")
			ring[0].push_back(g)
			pending += 1

	var cost := 0
	while pending > 0:
		var bucket := ring[cost % _RING]
		if bucket.is_empty():
			cost += 1
			continue
		ring[cost % _RING] = PackedInt32Array()
		for cell: int in bucket:
			pending -= 1
			if distances[cell] != cost:
				continue  # stale entry, superseded by a shorter route
			for d: int in 8:
				var ncell := cell + noff[d]
				if walk[ncell] == 0:
					continue
				var edge := COST_ORTH
				if d >= 4:
					# Diagonal: forbid cutting corners past a blocked tile.
					if walk[cell + orth_a[d]] == 0 or walk[cell + orth_b[d]] == 0:
						continue
					edge = COST_DIAG
				var nd := cost + edge
				if nd < distances[ncell]:
					distances[ncell] = nd
					@warning_ignore("return_value_discarded")
					ring[nd % _RING].push_back(ncell)
					pending += 1
		cost += 1

	# Downhill direction per cell: the legal neighbor with the smallest
	# distance (strictly smaller than our own is guaranteed for any finite
	# non-goal cell, since its Dijkstra predecessor qualifies).
	for cell: int in cell_count:
		var dist := distances[cell]
		if dist == UNREACHABLE or dist == 0:
			continue
		var best_d := NO_DIR
		var best_dist := dist
		for d: int in 8:
			var ncell := cell + noff[d]
			if walk[ncell] == 0:
				continue
			if d >= 4 and (walk[cell + orth_a[d]] == 0 or walk[cell + orth_b[d]] == 0):
				continue
			if distances[ncell] < best_dist:
				best_dist = distances[ncell]
				best_d = d
		flow_dir[cell] = best_d
