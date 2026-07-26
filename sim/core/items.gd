class_name Items
extends RefCounted
## Ground item stacks: the anonymity seam applied to stuff. A stack is
## anonymous quantity located on a tile (items in a pawn's hands live on
## the pawn — ActorPool carry arrays; items never become tile-state).
## One stack per tile in v1: same-type spawns merge up to the def's stack
## size and overflow scatters to nearby tiles, so a felled tree's yield
## spreads into a visible pile of piles, not an invisible tall number.
##
## No claims in v1: haulers race to stacks and the loser re-decides on
## arrival (self-healing, and the shrug is visible honest behavior).
## Claims can land later without changing this class's shape.

# Engine-side item type indices; items.json must list them in this exact
# order (ItemDefs asserts) — the SimWorld.TILE_* pattern.

const WOOD := 0

var defs: ItemDefs
var cells := PackedInt32Array()
var types := PackedByteArray()
var counts := PackedInt32Array()
var cell_lookup := {}  # cell -> stack index (one stack per tile)
var version := 1  # bumps on every content change (fields and renderer both key off it)


func _init(item_defs: ItemDefs) -> void:
	defs = item_defs


func has_at(cell: int) -> bool:
	return cell_lookup.has(cell)


func type_at(cell: int) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	return int(types[idx]) if idx >= 0 else -1


func count_at(cell: int) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	return counts[idx] if idx >= 0 else 0


## Add up to n of an item type to this exact tile, merging into an
## existing same-type stack. Returns how many were placed (0 if the tile
## holds a different type or a full stack — no spilling here; that's
## scatter's job).
func add(cell: int, type: int, n: int) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	if idx >= 0:
		if int(types[idx]) != type:
			return 0
		var space := defs.stack_sizes[type] - counts[idx]
		var placed := mini(space, n)
		if placed > 0:
			counts[idx] += placed
			version += 1
		return placed
	var placed := mini(defs.stack_sizes[type], n)
	if placed <= 0:
		return 0
	cell_lookup[cell] = cells.size()
	var _e1: bool = cells.push_back(cell)
	var _e2: bool = types.push_back(type)
	var _e3: bool = counts.push_back(placed)
	version += 1
	return placed


## Scatter n of an item type around a center cell: fill the center
## first, then walkable neighbors in deterministic ring order. If the
## whole neighborhood is packed, the remainder is forced into the center
## stack past its limit — wood never vanishes; an overfull stack is a
## visible oddity, a vanished log is a lie.
func scatter(world: SimWorld, center: int, type: int, n: int) -> void:
	var remaining := n
	remaining -= add(center, type, remaining)
	if remaining <= 0:
		return
	var w := world.width
	var cx := center % w
	@warning_ignore("integer_division")
	var cy := center / w
	for radius: int in range(1, 4):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if not world.is_walkable(cx + dx, cy + dy):
					continue
				remaining -= add((cy + dy) * w + cx + dx, type, remaining)
				if remaining <= 0:
					return
	if remaining > 0:
		_force_add(center, type, remaining)


## Take up to n items from the stack at this cell. Returns how many came
## off (0 if nothing here).
func take(cell: int, n: int) -> int:
	var idx: int = cell_lookup.get(cell, -1)
	if idx < 0:
		return 0
	var taken := mini(counts[idx], n)
	counts[idx] -= taken
	if counts[idx] <= 0:
		_remove(idx)
	if taken > 0:
		version += 1
	return taken


## A blocking structure completed on this cell: push its stack to the
## nearest walkable neighbor (the pawn-displacement rule, applied to
## stuff — items under a wall would be a lie the player can't see).
func displace_from(world: SimWorld, cell: int) -> void:
	var idx: int = cell_lookup.get(cell, -1)
	if idx < 0:
		return
	var type := int(types[idx])
	var n := counts[idx]
	_remove(idx)
	scatter(world, _nearest_walkable(world, cell), type, n)
	version += 1


func goal_cells() -> PackedInt32Array:
	var goals := PackedInt32Array()
	for i: int in cells.size():
		if counts[i] > 0:
			var _e: bool = goals.push_back(cells[i])
	goals.sort()
	return goals


## Force items into a cell ignoring the stack limit (scatter's last
## resort; see scatter).
func _force_add(cell: int, type: int, n: int) -> void:
	var idx: int = cell_lookup.get(cell, -1)
	if idx >= 0 and int(types[idx]) == type:
		counts[idx] += n
		return
	cell_lookup[cell] = cells.size()
	var _e1: bool = cells.push_back(cell)
	var _e2: bool = types.push_back(type)
	var _e3: bool = counts.push_back(n)
	version += 1


func _nearest_walkable(world: SimWorld, cell: int) -> int:
	var w := world.width
	var cx := cell % w
	@warning_ignore("integer_division")
	var cy := cell / w
	for radius: int in range(1, 6):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if world.is_walkable(cx + dx, cy + dy):
					return (cy + dy) * w + cx + dx
	return cell


## Swap-remove keeping the lookup consistent (the Blueprints pattern).
func _remove(idx: int) -> void:
	var _erased: bool = cell_lookup.erase(cells[idx])
	var last := cells.size() - 1
	if idx != last:
		cells[idx] = cells[last]
		types[idx] = types[last]
		counts[idx] = counts[last]
		cell_lookup[cells[idx]] = idx
	var _e1: int = cells.resize(last)
	var _e2: int = types.resize(last)
	var _e3: int = counts.resize(last)
