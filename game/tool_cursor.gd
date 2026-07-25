class_name ToolCursor
extends Node2D
## The tool in your hand IS the cursor (design spec sheet 03). Lives on
## the HUD layer: 32px glyph from icons.png drawn at 2x, snapped to whole
## screen pixels, hotspot at the mouse point. The loaded material chip
## docks at the glyph's lower-right — one glance answers "what tool" and
## "what paint". Over UI the OS pointer returns (main toggles visibility).

const SCALE := 2
const INK := Color("2e222f")
const ICONS_SHEET := preload("res://content/ui/icons.png")
# Per-tool hotspots in native 32px glyph coords (spec: blade tip,
# bristles, dropper tip, center).
const HOTSPOTS: Array[Vector2i] = [
	Vector2i(27, 5), Vector2i(26, 6), Vector2i(3, 28), Vector2i(16, 16),
]
const ICON_ROW := [0, 2, 1, 3]  # PAINT, PATTERN, EYEDROPPER, CANCEL

var _tool := 0
var _chip: Texture2D


func update_tool(tool: int, chip: Texture2D) -> void:
	_tool = tool
	_chip = chip
	queue_redraw()


func _process(_delta: float) -> void:
	position = get_viewport().get_mouse_position().floor()


func _draw() -> void:
	if _tool > 3:
		return
	var offset := -Vector2(HOTSPOTS[_tool]) * SCALE
	var glyph := Rect2(offset, Vector2(32, 32) * SCALE)
	draw_texture_rect_region(ICONS_SHEET, glyph, Rect2(0, ICON_ROW[_tool] * 32, 32, 32))
	# Loaded chip, lower-right of the glyph; eyedropper and cancel carry
	# no paint.
	if _chip and (_tool == 0 or _tool == 1):
		var chip_pos := offset + Vector2(26, 26) * SCALE
		draw_rect(Rect2(chip_pos - Vector2.ONE * SCALE, Vector2(18, 18) * SCALE), INK)
		draw_texture_rect(_chip, Rect2(chip_pos, Vector2(16, 16) * SCALE), false)
