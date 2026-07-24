class_name WallTestRenderer
extends Node2D
## THROWAWAY debug: paints a hardcoded arrangement of wood walls with 47-blob
## autotiling so we can see the sheet in action. No sim, no collision — pure
## decal. Delete when the real structure autotiler lands.

const SHEET := preload("res://content/structures/wall_wood.png")
# Cell -> neighbor bitmask, extracted from Stephen's blob template
# (bits: N=1, NE=2, E=4, SE=8, S=16, SW=32, W=64, NW=128; -1 = unused cell).
const MASKS: Array[int] = [
	16, 20, 84, 80, 213, 92, 116, 87, 28, 125, 124, 112,
	17, 21, 85, 81, 29, 127, 253, 113, 31, 119, -1, 245,
	1, 5, 69, 65, 23, 223, 247, 209, 95, 255, 221, 241,
	0, 4, 68, 64, 117, 71, 197, 93, 7, 199, 215, 193,
]

var _cell_by_mask := {}
var _tiles := {}  # Vector2i -> true


func setup(origin: Vector2i) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in MASKS.size():
		if MASKS[i] >= 0:
			_cell_by_mask[MASKS[i]] = i
	# The sacred solid fill: 7x7 block.
	_fill(origin, origin + Vector2i(6, 6))
	# A 5x5 room ring with a door-sized gap in the south wall.
	_ring(origin + Vector2i(9, 0), origin + Vector2i(13, 4))
	_tiles.erase(origin + Vector2i(11, 4))
	# Lone wall, lines, an L, and a plus.
	_tiles[origin + Vector2i(16, 0)] = true
	_fill(origin + Vector2i(16, 2), origin + Vector2i(16, 6))
	_fill(origin + Vector2i(18, 0), origin + Vector2i(22, 0))
	_fill(origin + Vector2i(18, 2), origin + Vector2i(18, 5))
	_fill(origin + Vector2i(18, 5), origin + Vector2i(21, 5))
	_fill(origin + Vector2i(20, 2), origin + Vector2i(22, 2))
	_tiles[origin + Vector2i(21, 3)] = true
	queue_redraw()


func _fill(a: Vector2i, b: Vector2i) -> void:
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			_tiles[Vector2i(x, y)] = true


func _ring(a: Vector2i, b: Vector2i) -> void:
	for x in range(a.x, b.x + 1):
		_tiles[Vector2i(x, a.y)] = true
		_tiles[Vector2i(x, b.y)] = true
	for y in range(a.y, b.y + 1):
		_tiles[Vector2i(a.x, y)] = true
		_tiles[Vector2i(b.x, y)] = true


func _draw() -> void:
	var px := float(TerrainRenderer.TILE_PX)
	for t: Vector2i in _tiles:
		var m := _mask_at(t)
		var cell: int = _cell_by_mask.get(m, _cell_by_mask.get(0, 0))
		var src := Rect2(float(cell % 12) * 16.0, float(cell / 12) * 16.0, 16.0, 16.0)
		draw_texture_rect_region(SHEET, Rect2(Vector2(t) * px, Vector2(px, px)), src)


func _mask_at(t: Vector2i) -> int:
	var n := _tiles.has(t + Vector2i(0, -1))
	var e := _tiles.has(t + Vector2i(1, 0))
	var s := _tiles.has(t + Vector2i(0, 1))
	var w := _tiles.has(t + Vector2i(-1, 0))
	var m := 0
	if n: m |= 1
	if e: m |= 4
	if s: m |= 16
	if w: m |= 64
	# Diagonals only matter when both adjacent cardinals connect (blob rule).
	if n and e and _tiles.has(t + Vector2i(1, -1)): m |= 2
	if s and e and _tiles.has(t + Vector2i(1, 1)): m |= 8
	if s and w and _tiles.has(t + Vector2i(-1, 1)): m |= 32
	if n and w and _tiles.has(t + Vector2i(-1, -1)): m |= 128
	return m
