class_name PaletteBar
extends Control
## The painter's palette (docs/palette-ui-brief.md + design spec sheets
## 01-02, docs/design/palette/). One board, bottom-center: tools on the
## left, a groove, then one shelf of material swatches. Everything is a
## 36px slot; selection grows the slot to 40px with the gold frame — the
## loaded brush physically lifts off the board.
##
## All chrome is drawn programmatically from the foundations spec (color
## roles, slot anatomy, board anatomy) — pixel art via rects, so state
## changes never wait on art. Swatch chips are the real material art,
## cropped from the wall sheets: matter, not hex codes.
##
## The bar owns palette STATE (tool in hand, loaded swatch, visible
## shelf); main.gd reads it to decide what a click on the world does.

signal changed  # any tool/swatch/shelf change; main syncs cursor + HUD

const SCALE := 2  # HUD renders at 2x native pixels
# Foundations: color roles (design spec sheet 01).
const INK := Color("2e222f")
const BOARD_FACE := Color("ab947a")
const BOARD_SHADE := Color("966c6c")
const DEEP_GRAIN := Color("694f62")
const RECESS := Color("625565")
const SHEEN := Color("c7dcd0")
const SELECTED := Color("f9c22b")
const SELECTED_INNER := Color("fbb954")

# Native-unit geometry (multiplied by SCALE at draw time).
const SLOT := 36
const PITCH := 38  # slot + 2px gap; the 40px selected slot eats the gap
const PAD := 4
const GROOVE_W := 6
const TAB_W := 52
const TAB_H := 14
const TOOL_COUNT := 4
const SWATCH_SLOTS := 8

enum Tool { PAINT, PATTERN, EYEDROPPER, CANCEL, POINTER }
const TOOL_KEYS: Array[String] = ["B", "P", "I", "X"]
const TOOL_ICON_ROW := [0, 2, 1, 3]  # icons.png rows: trowel, brush, dropper, cancel

const ICONS_SHEET := preload("res://content/ui/icons.png")

var tool: int = Tool.PAINT
var shelf := 0  # visible shelf
var loaded_shelf := 0  # shelf holding the loaded swatch
var loaded_idx := 0
var shelves: Array[Dictionary] = []  # {name, swatches: [{label, type, mat, chip}]}
var _alt_saved_tool := -1
var _hover_slot := -1  # flat hover id: 0..3 tools, 10+i swatches, 20+i tabs


func setup(structure_defs: StructureDefs) -> void:
	shelves = []
	var walls: Array[Dictionary] = []
	for m: int in structure_defs.wall_material_count():
		walls.append({
			"label": structure_defs.wall_material_ids[m].to_upper() + " WALL",
			"type": SimWorld.STRUCT_WALL,
			"mat": m,
			"chip": _wall_chip(structure_defs.wall_material_sheets[m]),
		})
	shelves.append({"name": "WALLS", "swatches": walls})
	var furniture: Array[Dictionary] = [
		{"label": "DOOR", "type": SimWorld.STRUCT_DOOR, "mat": 0, "chip": _flat_chip(Palette.COLORS[21])},
		{"label": "BED", "type": SimWorld.STRUCT_BED, "mat": 0, "chip": _flat_chip(Palette.COLORS[47])},
	]
	shelves.append({"name": "FURN", "swatches": furniture})

	custom_minimum_size = Vector2(_board_w(), 44 + TAB_H) * SCALE
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)
	queue_redraw()


## The swatch currently loaded on the brush.
func loaded_swatch() -> Dictionary:
	return shelves[loaded_shelf]["swatches"][loaded_idx]


func select_tool(t: int) -> void:
	tool = t
	# Picking up paint means you intend to paint (spec: cancel auto-swaps).
	changed.emit()
	queue_redraw()


func select_swatch(idx: int) -> void:
	var swatches: Array = shelves[shelf]["swatches"]
	if idx < 0 or idx >= swatches.size():
		return
	loaded_shelf = shelf
	loaded_idx = idx
	if tool == Tool.CANCEL or tool == Tool.POINTER:
		tool = Tool.PAINT  # loading a brush means painting
	changed.emit()
	queue_redraw()


func cycle_shelf() -> void:
	shelf = (shelf + 1) % shelves.size()
	changed.emit()
	queue_redraw()


## Hold-Alt temporary eyedropper (the art-app power move).
func alt_down() -> void:
	if tool != Tool.EYEDROPPER:
		_alt_saved_tool = tool
		tool = Tool.EYEDROPPER
		changed.emit()
		queue_redraw()


func alt_up() -> void:
	if _alt_saved_tool >= 0:
		tool = _alt_saved_tool
		_alt_saved_tool = -1
		changed.emit()
		queue_redraw()


## Eyedropper hit: find and load the swatch matching a picked structure.
## Returns true when a swatch was found.
func pick(struct_type: int, material_idx: int) -> bool:
	for s: int in shelves.size():
		var swatches: Array = shelves[s]["swatches"]
		for i: int in swatches.size():
			if swatches[i]["type"] == struct_type and swatches[i]["mat"] == material_idx:
				shelf = s
				loaded_shelf = s
				loaded_idx = i
				if _alt_saved_tool >= 0:
					# Temporary pick: return to the saved tool, now loaded.
					tool = _alt_saved_tool
					_alt_saved_tool = -1
				changed.emit()
				queue_redraw()
				return true
	return false


# --- geometry ---------------------------------------------------------------


func _board_w() -> int:
	return PAD + TOOL_COUNT * PITCH - 2 + GROOVE_W + SWATCH_SLOTS * PITCH - 2 + PAD


func _board_rect() -> Rect2:
	return Rect2(0, TAB_H * SCALE, _board_w() * SCALE, 44 * SCALE)


func _tool_slot_pos(i: int) -> Vector2:
	return Vector2(PAD + i * PITCH, TAB_H + 4) * SCALE


func _swatch_slot_pos(i: int) -> Vector2:
	return Vector2(PAD + TOOL_COUNT * PITCH - 2 + GROOVE_W + i * PITCH, TAB_H + 4) * SCALE


func _tab_rect(i: int) -> Rect2:
	var x := PAD + (TAB_W + 4) * i
	var y := 0 if i == shelf else 2
	return Rect2(Vector2(x, y) * SCALE, Vector2(TAB_W, TAB_H + (2 if i == shelf else 0)) * SCALE)


# --- drawing ----------------------------------------------------------------


func _draw() -> void:
	var s := float(SCALE)
	var board := _board_rect()
	# Board anatomy (sheet 01): ink outline -> sheen top edge -> face,
	# #966c6c shade line along bottom/right, nails 3px into corners.
	draw_rect(board, INK)
	var face := Rect2(board.position + Vector2(s, s), board.size - Vector2(2 * s, 2 * s))
	draw_rect(face, BOARD_FACE)
	draw_rect(Rect2(face.position, Vector2(face.size.x, s)), SHEEN)
	draw_rect(Rect2(face.position + Vector2(0, face.size.y - s), Vector2(face.size.x, s)), BOARD_SHADE)
	draw_rect(Rect2(face.position + Vector2(face.size.x - s, 0), Vector2(s, face.size.y)), BOARD_SHADE)
	for corner: Vector2 in [
		face.position + Vector2(3, 3) * s,
		face.position + Vector2(face.size.x - 5 * s, 3 * s),
		face.position + Vector2(3 * s, face.size.y - 5 * s),
		face.position + face.size - Vector2(5, 5) * s,
	]:
		draw_rect(Rect2(corner, Vector2(2, 2) * s), DEEP_GRAIN)
		draw_rect(Rect2(corner, Vector2(s, s)), SHEEN)
	# Groove between tools and paint.
	var groove_x := (PAD + TOOL_COUNT * PITCH - 2 + 2) * SCALE
	draw_rect(Rect2(Vector2(groove_x, board.position.y + 4 * s), Vector2(s, board.size.y - 8 * s)), BOARD_SHADE)
	draw_rect(Rect2(Vector2(groove_x + s, board.position.y + 4 * s), Vector2(s, board.size.y - 8 * s)), SHEEN)

	# Tabs (paint-tin labels on the top edge).
	for t: int in shelves.size():
		var r := _tab_rect(t)
		draw_rect(r, INK)
		var tface := Rect2(r.position + Vector2(s, s), r.size - Vector2(2 * s, s))
		draw_rect(tface, BOARD_FACE if t == shelf else RECESS)
		_draw_tiny_text(str(shelves[t]["name"]), r.position + Vector2(6 * s, 3 * s),
			INK if t == shelf else SHEEN)

	# Tool slots.
	for i: int in TOOL_COUNT:
		var icon := AtlasTexture.new()
		icon.atlas = ICONS_SHEET
		icon.region = Rect2(0, TOOL_ICON_ROW[i] * 32, 32, 32)
		_draw_slot(_tool_slot_pos(i), icon, null, _tool_of_slot(i) == tool, _hover_slot == i, false)
	# Swatch slots.
	var swatches: Array = shelves[shelf]["swatches"]
	for i: int in SWATCH_SLOTS:
		if i < swatches.size():
			var sel := shelf == loaded_shelf and i == loaded_idx
			_draw_slot(_swatch_slot_pos(i), swatches[i]["chip"], null, sel, _hover_slot == 10 + i, false)
		else:
			_draw_slot(_swatch_slot_pos(i), null, null, false, false, true)

	# Keybind hints hang below the board edge, outlined — readable over
	# any terrain, never crowding the art.
	for i: int in TOOL_COUNT:
		_draw_hint(TOOL_KEYS[i], _tool_slot_pos(i), _tool_of_slot(i) == tool)
	for i: int in mini(SWATCH_SLOTS, swatches.size()):
		_draw_hint(str(i + 1), _swatch_slot_pos(i), shelf == loaded_shelf and i == loaded_idx)


## One slot, per the anatomy spec: 36 native (1px ink + 1px state frame +
## 32px content); selected grows to 40 with gold frame + inner ring.
func _draw_slot(pos: Vector2, content: Texture2D, _unused: Variant, sel: bool, hovered: bool, empty: bool) -> void:
	var s := float(SCALE)
	var content_rect := Rect2(pos + Vector2(2, 2) * s, Vector2(32, 32) * s)
	if sel:
		var r := Rect2(pos - Vector2(2, 2) * s, Vector2(40, 40) * s)
		draw_rect(r, INK)
		draw_rect(Rect2(r.position + Vector2(s, s), r.size - Vector2(2, 2) * s), SELECTED)
		draw_rect(Rect2(r.position + Vector2(3, 3) * s, r.size - Vector2(6, 6) * s), SELECTED_INNER)
		draw_rect(content_rect, BOARD_FACE)
		if content:
			draw_texture_rect(content, content_rect, false)
		return
	var r := Rect2(pos, Vector2(SLOT, SLOT) * s)
	draw_rect(r, INK)
	var frame := SHEEN if hovered else (RECESS if empty else BOARD_FACE)
	draw_rect(Rect2(r.position + Vector2(s, s), r.size - Vector2(2, 2) * s), frame)
	if empty:
		draw_rect(Rect2(r.position + Vector2(2, 2) * s, r.size - Vector2(4, 4) * s), RECESS.darkened(0.15))
	else:
		draw_rect(content_rect, BOARD_FACE)
		if content:
			draw_texture_rect(content, content_rect, false)


## Stand-in for the pixel font: default font, small, no outline (on-board
## text per spec). Swapped when m6x11 lands.
func _draw_tiny_text(text: String, pos: Vector2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, pos + Vector2(0, 9 * SCALE), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8 * SCALE, color)


## Over-the-world text gets the ink outline (foundations type rule).
func _draw_hint(text: String, slot_pos: Vector2, active: bool) -> void:
	var font := ThemeDB.fallback_font
	var sz := 8 * SCALE
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var p := slot_pos + Vector2((SLOT * SCALE - w) * 0.5, (SLOT + 7) * SCALE)
	for off: Vector2 in [
		Vector2(SCALE, 0), Vector2(-SCALE, 0), Vector2(0, SCALE), Vector2(0, -SCALE),
	]:
		draw_string(font, p + off, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, INK)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
		Color("f9c22b") if active else Color.WHITE)


# --- input ------------------------------------------------------------------


func _tool_of_slot(i: int) -> int:
	return [Tool.PAINT, Tool.PATTERN, Tool.EYEDROPPER, Tool.CANCEL][i]


func _slot_at(p: Vector2) -> int:
	for i: int in TOOL_COUNT:
		if Rect2(_tool_slot_pos(i), Vector2(SLOT, SLOT) * SCALE).has_point(p):
			return i
	for i: int in SWATCH_SLOTS:
		if Rect2(_swatch_slot_pos(i), Vector2(SLOT, SLOT) * SCALE).has_point(p):
			return 10 + i
	for t: int in shelves.size():
		if _tab_rect(t).has_point(p):
			return 20 + t
	return -1


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		var h := _slot_at(motion.position)
		if h != _hover_slot:
			_hover_slot = h
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var hit := _slot_at(mb.position)
		if hit < 0:
			return
		accept_event()
		if hit < 10:
			select_tool(_tool_of_slot(hit))
		elif hit < 20:
			select_swatch(hit - 10)
		else:
			shelf = hit - 20
			changed.emit()
			queue_redraw()


func _on_mouse_exited() -> void:
	_hover_slot = -1
	queue_redraw()


# --- chips ------------------------------------------------------------------


## A 16px chip of real material art: the island cell of the blob sheet
## (col 0, row 3 of the 12x5 template), drawn at 2x = 32px content.
static func _wall_chip(sheet_path: String) -> Texture2D:
	var tex := AtlasTexture.new()
	tex.atlas = load(sheet_path)
	tex.region = Rect2(0, 48, 16, 16)
	return tex


static func _flat_chip(color: Color) -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(color)
	for x: int in 16:
		img.set_pixel(x, 0, INK)
		img.set_pixel(x, 15, INK)
	for y: int in 16:
		img.set_pixel(0, y, INK)
		img.set_pixel(15, y, INK)
	return ImageTexture.create_from_image(img)
