class_name ToolCursor
extends Node2D
## Paint-state badge riding beside the OS pointer. The tool icons stay
## button art — they're 32px, angled up-right, and trail the wrong way
## for a cursor (cursor bodies trail down-right of the hotspot). Tool
## identity at the point of action comes from the hover-cell outline
## color (BuildOverlay) plus this loaded-material chip for the painting
## tools. If dedicated cursor art ever lands (cursors.png: 16x16 cells,
## row per tool, drawn pointing up-left), this is where it plugs in.

const SCALE := 2
const INK := Color("2e222f")

var _tool := 0
var _chip: Texture2D


func update_tool(tool: int, chip: Texture2D) -> void:
	_tool = tool
	_chip = chip
	queue_redraw()


func _process(_delta: float) -> void:
	position = get_viewport().get_mouse_position().floor()


func _draw() -> void:
	# Chip badge only for the tools that carry paint.
	if _chip == null or _tool > 1:
		return
	var pos := Vector2(7, 9) * SCALE  # tucked below-right of the pointer
	draw_rect(Rect2(pos - Vector2.ONE * SCALE, Vector2(14, 14) * SCALE), INK)
	draw_texture_rect(_chip, Rect2(pos, Vector2(12, 12) * SCALE), false)
