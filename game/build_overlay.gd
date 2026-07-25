class_name BuildOverlay
extends Node2D
## World-space paint feedback (design spec sheet 03): a 1-screen-px
## GHOST LIGHT outline on the hovered cell ("what will happen on click,
## always visible"), and the shift-line chalk preview — outline-only
## Bresenham cells with white corner ticks on both anchors. Nothing here
## commits anything; main.gd owns the actual strokes.

const GHOST_LIGHT := Color("8fd3ff")
const WARNING := Color("e83b3b")
const TICK := Color.WHITE

var hover_cell := Vector2i(-9999, -9999)
var warn := false  # cancel tool in hand: the outline reads destructive
var line_cells: Array[Vector2i] = []
var zoom := 3.0


func update_state(hover: Vector2i, line: Array[Vector2i], warn_tint: bool, cam_zoom: float) -> void:
	hover_cell = hover
	line_cells = line
	warn = warn_tint
	zoom = cam_zoom
	queue_redraw()


func _draw() -> void:
	var px := float(TerrainRenderer.TILE_PX)
	var w := 1.0 / zoom  # one SCREEN pixel regardless of zoom
	for c: Vector2i in line_cells:
		draw_rect(Rect2(Vector2(c) * px, Vector2(px, px)).grow(-w * 0.5), GHOST_LIGHT, false, w)
	if not line_cells.is_empty():
		_draw_ticks(line_cells[0], w)
		_draw_ticks(line_cells[line_cells.size() - 1], w)
	if hover_cell.x != -9999:
		var color := WARNING if warn else GHOST_LIGHT
		draw_rect(Rect2(Vector2(hover_cell) * px, Vector2(px, px)).grow(-w * 0.5), color, false, w)


## White corner ticks marking a line anchor (the chalk line's pins).
func _draw_ticks(cell: Vector2i, w: float) -> void:
	var px := float(TerrainRenderer.TILE_PX)
	var o := Vector2(cell) * px
	var t := 3.0 * w
	for corner: int in 4:
		var cx := o.x + (px if corner % 2 == 1 else 0.0)
		var cy := o.y + (px if corner >= 2 else 0.0)
		var dx := -1.0 if corner % 2 == 1 else 1.0
		var dy := -1.0 if corner >= 2 else 1.0
		draw_rect(Rect2(cx - (0.0 if dx > 0 else t), cy - (0.0 if dy > 0 else w), t, w), TICK)
		draw_rect(Rect2(cx - (0.0 if dx > 0 else w), cy - (0.0 if dy > 0 else t), w, t), TICK)


## Bresenham cells from a to b inclusive — the chalk line's path.
static func cells_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		cells.append(p)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return cells
