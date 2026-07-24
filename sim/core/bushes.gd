class_name Bushes
extends RefCounted
## Berry scrub: the first food resource. Scattered deterministically on
## grass at worldgen; each bush holds a finite berry count. `version` bumps
## whenever a bush empties so the food flow field (and renderer) know to
## refresh.

const SPAWN_CHANCE := 0.006
const BERRIES_PER_BUSH := 24

var cells := PackedInt32Array()
var berries := PackedInt32Array()
var cell_to_bush := {}
var version := 1
var consumed_total := 0


static func generate(world: SimWorld) -> Bushes:
	var bushes := Bushes.new()
	var scatter_key := SimRng.key([world.world_seed, "bushes"])
	for y: int in world.height:
		for x: int in world.width:
			if world.tile_at(x, y) != SimWorld.TILE_GRASS or not world.is_walkable(x, y):
				continue
			var cell := y * world.width + x
			if SimRng.randf(SimRng.combine(scatter_key, cell)) < SPAWN_CHANCE:
				bushes.cell_to_bush[cell] = bushes.cells.size()
				var _e1: bool = bushes.cells.push_back(cell)
				var _e2: bool = bushes.berries.push_back(BERRIES_PER_BUSH)
	return bushes


func goal_cells() -> PackedInt32Array:
	var goals := PackedInt32Array()
	for i: int in cells.size():
		if berries[i] > 0:
			var _e: bool = goals.push_back(cells[i])
	return goals


func has_berries_at(cell: int) -> bool:
	var idx: int = cell_to_bush.get(cell, -1)
	return idx >= 0 and berries[idx] > 0


## Take one berry from the bush at this cell. Returns false if there is no
## stocked bush here.
func consume_at(cell: int) -> bool:
	var idx: int = cell_to_bush.get(cell, -1)
	if idx < 0 or berries[idx] <= 0:
		return false
	berries[idx] -= 1
	consumed_total += 1
	if berries[idx] == 0:
		version += 1
	return true
