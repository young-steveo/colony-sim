class_name Trees
extends RefCounted
## Trees: the first raw-material source. Scattered at worldgen in groves
## (coarse noise clumps the spawn chance) on grassy ground, so forests
## hug the wet lowlands the way bushes do. Chopping is the material
## cycle's first verb: a designated tree is a PLAN (standing intent any
## settler may act on — orders come later with director mode); felling
## yields wood items scattered where it stood.
##
## Trees are walkable in v1 — a deliberate simplification recorded in the
## GDD: blocking trees need either connectivity guarantees at worldgen or
## the weighted-cost flow fields already queued for difficult terrain.
## They DO block construction (Blueprints checks) — you clear the forest
## before you build in it, which is the material cycle asserting itself.

const CHOP_WORK_SECONDS := 4.0
const YIELD_MIN := 4
const YIELD_MAX := 8
const GROVE_FREQUENCY := 24.0  # tiles per grove-noise feature
const GROVE_THRESHOLD := 0.58  # noise above this is grove interior
const CHANCE_GROVE := 0.22
const CHANCE_SPARSE := 0.008
const MAX_WORKERS_PER_TREE := 1

var cells := PackedInt32Array()
var chop_done := PackedFloat32Array()  # work seconds accumulated
var workers := PackedByteArray()  # choppers this tick; reset by the sim
var cell_to_tree := {}
var designated := {}  # cell -> true: standing chop plans
var version := 1  # bumps when trees fall or plans change (field + renderer)
var felled_total := 0


static func generate(world: SimWorld) -> Trees:
	var trees := Trees.new()
	var grove_key := SimRng.key([world.world_seed, "groves"])
	var scatter_key := SimRng.key([world.world_seed, "trees"])
	for y: int in world.height:
		for x: int in world.width:
			if world.surface_at(x, y) != SimWorld.SURF_GRASS or not world.is_walkable(x, y):
				continue
			var cell := y * world.width + x
			var grove := _grove_noise(grove_key, x, y)
			var chance := CHANCE_GROVE if grove > GROVE_THRESHOLD else CHANCE_SPARSE
			if SimRng.randf(SimRng.combine(scatter_key, cell)) < chance:
				trees.cell_to_tree[cell] = trees.cells.size()
				var _e1: bool = trees.cells.push_back(cell)
				var _e2: bool = trees.chop_done.push_back(0.0)
				var _e3: bool = trees.workers.push_back(0)
	return trees


func has_tree_at(cell: int) -> bool:
	return cell_to_tree.has(cell)


func is_designated(cell: int) -> bool:
	return designated.has(cell)


## Designate the tree at this cell for chopping (a plan). Returns false
## if there's no tree here or it's already planned.
func designate(cell: int) -> bool:
	if not cell_to_tree.has(cell) or designated.has(cell):
		return false
	designated[cell] = true
	version += 1
	return true


func cancel_designation(cell: int) -> bool:
	if not designated.has(cell):
		return false
	var _e: bool = designated.erase(cell)
	version += 1
	return true


## Register one chopper on this tree for the current tick (the
## Blueprints add_worker pattern — capacity, not persistent claims).
func add_worker(cell: int) -> bool:
	var idx: int = cell_to_tree.get(cell, -1)
	if idx < 0 or workers[idx] >= MAX_WORKERS_PER_TREE:
		return false
	workers[idx] += 1
	return true


func reset_workers() -> void:
	workers.fill(0)


## Contribute chop work. When the tree falls it is removed, its plan is
## cleared, and the caller receives the wood yield to scatter (the sim
## owns the items pool; Trees never touches it).
func add_work(world: SimWorld, cell: int, seconds: float) -> int:
	var idx: int = cell_to_tree.get(cell, -1)
	if idx < 0:
		return 0
	chop_done[idx] += seconds
	if chop_done[idx] < CHOP_WORK_SECONDS:
		return 0
	var yield_key := SimRng.key([world.world_seed, "tree_yield", cell])
	var wood := SimRng.randi_range(yield_key, YIELD_MIN, YIELD_MAX)
	_remove(idx)
	var _e: bool = designated.erase(cell)
	felled_total += 1
	version += 1
	return wood


## Cells with a standing chop plan — the chop field's goals.
func plan_goals() -> PackedInt32Array:
	var goals := PackedInt32Array()
	for cell: int in designated:
		var _e: bool = goals.push_back(cell)
	goals.sort()  # dictionary order isn't contractual; determinism is
	return goals


## Swap-remove keeping the lookup consistent.
func _remove(idx: int) -> void:
	var _erased: bool = cell_to_tree.erase(cells[idx])
	var last := cells.size() - 1
	if idx != last:
		cells[idx] = cells[last]
		chop_done[idx] = chop_done[last]
		workers[idx] = workers[last]
		cell_to_tree[cells[idx]] = idx
	var _e1: int = cells.resize(last)
	var _e2: int = chop_done.resize(last)
	var _e3: int = workers.resize(last)


## Coarse value-noise for grove clumping: bilinear blend of hashed
## lattice corners. Deterministic, cheap, and only sampled at worldgen.
static func _grove_noise(key: int, x: int, y: int) -> float:
	var fx := float(x) / GROVE_FREQUENCY
	var fy := float(y) / GROVE_FREQUENCY
	var x0 := floori(fx)
	var y0 := floori(fy)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var v00 := SimRng.randf(SimRng.combine(SimRng.combine(key, x0), y0))
	var v10 := SimRng.randf(SimRng.combine(SimRng.combine(key, x0 + 1), y0))
	var v01 := SimRng.randf(SimRng.combine(SimRng.combine(key, x0), y0 + 1))
	var v11 := SimRng.randf(SimRng.combine(SimRng.combine(key, x0 + 1), y0 + 1))
	var sx := tx * tx * (3.0 - 2.0 * tx)
	var sy := ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(v00, v10, sx), lerpf(v01, v11, sx), sy)
