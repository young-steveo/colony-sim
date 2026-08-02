class_name PathFinder
extends RefCounted
## Deterministic A* for a single walker to a single destination — the
## per-settler complement to the shared FlowField (one field serves many
## walkers toward a goal SET; a move order is one walker, one cell, and
## building a whole field for it would be the wrong tool). Same integer
## cost model as FlowField (10 orthogonal / 14 diagonal), same
## corner-cutting rule, octile heuristic (admissible and consistent for
## these costs), and a fixed tie-break — lowest f, then lowest cell
## index, baked into one comparable key — so results are bit-stable.
##
## Orders are player-rate (a handful alive at once), so a synchronous
## search on the live world is fine; no async contract needed. Callers
## must still re-check live walkability while following the path — the
## world moves after the search, same rule as the shared fields.

const _UNVISITED := 2147483647
# Heap keys pack (f << CELL_BITS) | cell. 2^18 cells covers 512x512 maps;
# f stays far below 2^45, so the packed key orders exactly by (f, cell).
const _CELL_BITS := 18
const _CELL_MASK := (1 << _CELL_BITS) - 1

var _heap := PackedInt64Array()


## Cells from start (exclusive) to goal (inclusive), or empty when the
## goal is unreachable, unwalkable, or equals the start.
static func find(world: SimWorld, from_cell: int, to_cell: int) -> PackedInt32Array:
	return PathFinder.new()._find(world, from_cell, to_cell)


func _find(world: SimWorld, from_cell: int, to_cell: int) -> PackedInt32Array:
	var w := world.width
	assert(w * world.height <= 1 << _CELL_BITS, "PathFinder: map exceeds key packing")
	# The snapshot's border ring is 0 (SimWorld.walkability_snapshot), so
	# neighbor arithmetic below never needs bounds checks — the FlowField
	# border-sentinel guarantee, reused.
	var walk := world.walkability_snapshot()
	if from_cell == to_cell or walk[to_cell] == 0 or walk[from_cell] == 0:
		return PackedInt32Array()

	var g := PackedInt32Array()
	var _r1: int = g.resize(walk.size())
	g.fill(_UNVISITED)
	var came := PackedInt32Array()
	var _r2: int = came.resize(walk.size())  # only read for reached cells

	# Neighbor cell-index offsets in FlowField.DX/DY order, plus the two
	# orthogonal offsets that gate each diagonal (corner-cutting rule).
	var noff := PackedInt32Array([1, -1, w, -w, w + 1, -w + 1, w - 1, -w - 1])
	var orth_a := PackedInt32Array([1, -1, 0, 0, 1, 1, -1, -1])
	var orth_b := PackedInt32Array([0, 0, w, -w, w, -w, w, -w])

	var _c: int = _heap.resize(0)
	g[from_cell] = 0
	_push((_octile(w, from_cell, to_cell) << _CELL_BITS) | from_cell)
	while _heap.size() > 0:
		var key := _pop()
		var cell := int(key & _CELL_MASK)
		var gc := g[cell]
		if int(key >> _CELL_BITS) > gc + _octile(w, cell, to_cell):
			continue  # stale entry: this cell was improved after the push
		if cell == to_cell:
			break
		for d: int in 8:
			var ncell := cell + noff[d]
			if walk[ncell] == 0:
				continue
			if d >= 4 and (walk[cell + orth_a[d]] == 0 or walk[cell + orth_b[d]] == 0):
				continue
			var ng := gc + (FlowField.COST_ORTH if d < 4 else FlowField.COST_DIAG)
			if ng < g[ncell]:
				g[ncell] = ng
				came[ncell] = cell
				_push(((ng + _octile(w, ncell, to_cell)) << _CELL_BITS) | ncell)

	if g[to_cell] == _UNVISITED:
		return PackedInt32Array()
	var path := PackedInt32Array()
	var c := to_cell
	while c != from_cell:
		var _p: bool = path.push_back(c)
		c = came[c]
	path.reverse()
	return path


static func _octile(w: int, a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var dy := absi(a / w - b / w)
	var dx := absi(a % w - b % w)
	var lo := mini(dx, dy)
	return FlowField.COST_DIAG * lo + FlowField.COST_ORTH * (maxi(dx, dy) - lo)


# Binary min-heap over packed keys; member array because Packed*Arrays
# are copy-on-write value types — a static helper couldn't mutate one.
func _push(key: int) -> void:
	var _a: bool = _heap.push_back(key)
	var i := _heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _heap[parent] <= _heap[i]:
			break
		var tmp := _heap[parent]
		_heap[parent] = _heap[i]
		_heap[i] = tmp
		i = parent


func _pop() -> int:
	var top := _heap[0]
	var last := _heap.size() - 1
	_heap[0] = _heap[last]
	var _r: int = _heap.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= last:
			break
		var small := l
		if l + 1 < last and _heap[l + 1] < _heap[l]:
			small = l + 1
		if _heap[i] <= _heap[small]:
			break
		var tmp := _heap[i]
		_heap[i] = _heap[small]
		_heap[small] = tmp
		i = small
	return top
