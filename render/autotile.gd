class_name Autotile
extends RefCounted
## The project's shared 47-blob autotile template: 12×4 blob cells plus a
## bottom variant row (12×5 sheets of 16px cells — content/README.md).
## Walls and terrain both ride this. Cell→mask table was machine-extracted
## from the reference template image; wall_wood.png is the reference sheet.
## Neighbor bits: N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128.

const COLS := 12
const ROWS := 5
const MASKS: Array[int] = [
	16, 20, 84, 80, 213, 92, 116, 87, 28, 125, 124, 112,
	17, 21, 85, 81, 29, 127, 253, 113, 31, 119, -1, 245,
	1, 5, 69, 65, 23, 223, 247, 209, 95, 255, 221, 241,
	0, 4, 68, 64, 117, 71, 197, 93, 7, 199, 215, 193,
]

static var _cell_by_mask: Dictionary = {}


static func cell_for(mask: int) -> int:
	if _cell_by_mask.is_empty():
		for i: int in MASKS.size():
			if MASKS[i] >= 0:
				_cell_by_mask[MASKS[i]] = i
	return _cell_by_mask.get(mask, _cell_by_mask[0])


## Canonical blob mask: diagonal bits only count when both adjacent
## cardinals connect.
static func mask_from(
	n: bool, e: bool, s: bool, w: bool,
	ne: bool, se: bool, sw: bool, nw: bool
) -> int:
	var m := 0
	if n: m |= 1
	if e: m |= 4
	if s: m |= 16
	if w: m |= 64
	if n and e and ne: m |= 2
	if s and e and se: m |= 8
	if s and w and sw: m |= 32
	if n and w and nw: m |= 128
	return m


## UV origin of a cell for the blob shader's INSTANCE_CUSTOM.xy.
static func cell_uv(cell: int) -> Vector2:
	@warning_ignore("integer_division")
	return Vector2(float(cell % COLS) / COLS, float(cell / COLS) / ROWS)
