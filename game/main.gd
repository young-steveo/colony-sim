extends Node2D
## Game layer: owns the fixed-timestep loop, time controls, camera, input,
## and telemetry. This is the only place wall-clock time exists; the sim
## just gets tick() called on it. All inputs are named InputMap actions
## (see project.godot) — no hardcoded keycodes.

const SPEEDS: Array[float] = [1.0, 3.0, 6.0]
const MAX_TICKS_PER_FRAME := 12
const PAN_SPEED := 900.0

# Camera zoom locked to steps where a 16px tile lands on whole screen pixels
# (4, 8, 16, 32, 48, 64 px/tile) — crisp pixel art at every stop.
const ZOOM_STEPS: Array[float] = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0]
# Chunky-first: default to 48 screen px per tile (GDD Presentation).
const DEFAULT_ZOOM_IDX := 4

var sim: Simulation
var world_seed := 0
var sim_paused := false
var speed_idx := 0
var default_zoom_idx := DEFAULT_ZOOM_IDX
# Slice default: a readable handful at the map's heart, not a stress crowd
# (F still piles on +100 for the stress test).
var start_actors := 4
var zoom_idx := DEFAULT_ZOOM_IDX
var _cam_pos := Vector2.ZERO  # continuous pan position; cam snaps to pixels
var accumulator := 0.0
var avg_tick_ms := 0.0

const TOOL_NAMES: Array[String] = ["paint", "pattern", "eyedropper", "cancel", "pointer"]

var terrain: TerrainRenderer
var actor_renderer: ActorRenderer
var bush_renderer: BushRenderer
var structure_renderer: StructureRenderer
var field_overlay: FieldDebugRenderer
var tree_renderer: TreeRenderer
var item_renderer: ItemRenderer
var carry_renderer: CarryRenderer
var chop_plan_mode := false  # placeholder input until the plan-tool design round
var palette: PaletteBar
var tool_cursor: ToolCursor
var build_overlay: BuildOverlay
var _line_anchor := Vector2i(-9999, -9999)  # last painted cell; shift-line start
var _stroke_len := 0  # cells attempted this stroke; drives pattern parity
var _last_stroke_cell := -1
var show_field := false
var rally_marker: Sprite2D
var selection_ring: Sprite2D
var panel: Label
var selected_id := -1
var cam: Camera2D
var hud: Label

var _screenshot_mode := false
var _warmup_ticks := 0
var _rally_arg := ""
var _cam_arg := ""
var _shot_frame := 90
var _frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_screenshot_mode = "--screenshot" in args
	var start_seed := int(Time.get_unix_time_from_system()) if not _screenshot_mode else 12345
	for a: String in args:
		if a.begins_with("--seed="):
			start_seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--zoom="):
			var idx := ZOOM_STEPS.find(a.trim_prefix("--zoom=").to_float())
			if idx >= 0:
				default_zoom_idx = idx
		elif a.begins_with("--actors="):
			start_actors = maxi(1, int(a.trim_prefix("--actors=")))
		elif a.begins_with("--rally="):
			_rally_arg = a.trim_prefix("--rally=")
		elif a.begins_with("--warmup="):
			_warmup_ticks = maxi(0, int(a.trim_prefix("--warmup=")))
		elif a.begins_with("--cam="):
			_cam_arg = a.trim_prefix("--cam=")
		elif a.begins_with("--shot-frame="):
			_shot_frame = maxi(1, int(a.trim_prefix("--shot-frame=")))

	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Label.new()
	hud.position = Vector2(10, 8)
	hud.add_theme_color_override("font_color", Color.WHITE)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	hud.add_theme_constant_override("outline_size", 6)
	ui.add_child(hud)
	panel = Label.new()
	panel.position = Vector2(10, 64)
	panel.add_theme_color_override("font_color", Color.WHITE)
	panel.add_theme_color_override("font_outline_color", Color.BLACK)
	panel.add_theme_constant_override("outline_size", 6)
	panel.visible = false
	ui.add_child(panel)
	palette = PaletteBar.new()
	ui.add_child(palette)
	tool_cursor = ToolCursor.new()
	ui.add_child(tool_cursor)

	_start(start_seed)
	if _rally_arg.contains(","):
		var parts := _rally_arg.split(",")
		_rally(int(parts[0]), int(parts[1]))
	if "--house" in args:
		_place_demo_house()
	if "--cycle" in args:
		_demo_material_cycle()
	for t: int in _warmup_ticks:
		sim.tick()
	if "--inspect" in args and sim.actors.count > 0:
		selected_id = sim.actors.ids[0]
		_place_camera(sim.actors.positions[0] * TerrainRenderer.TILE_PX)
	if _cam_arg.contains(","):
		var cam_parts := _cam_arg.split(",")
		_place_camera(Vector2(int(cam_parts[0]), int(cam_parts[1])) * TerrainRenderer.TILE_PX)


func _start(seed_value: int) -> void:
	world_seed = seed_value
	sim = Simulation.new(world_seed)
	sim.spawn_actors(start_actors)
	accumulator = 0.0
	avg_tick_ms = 0.0

	if terrain:
		terrain.queue_free()
	if actor_renderer:
		actor_renderer.queue_free()
	if field_overlay:
		field_overlay.queue_free()
	if rally_marker:
		rally_marker.queue_free()
	if bush_renderer:
		bush_renderer.queue_free()
	if structure_renderer:
		structure_renderer.queue_free()
	if tree_renderer:
		tree_renderer.queue_free()
	if item_renderer:
		item_renderer.queue_free()
	if carry_renderer:
		carry_renderer.queue_free()
	if selection_ring:
		selection_ring.queue_free()
	if build_overlay:
		build_overlay.queue_free()
	selected_id = -1
	_line_anchor = Vector2i(-9999, -9999)
	_last_stroke_cell = -1
	palette.setup(sim.structure_defs)
	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.build(sim.world, sim.terrain_defs)
	bush_renderer = BushRenderer.new()
	add_child(bush_renderer)
	bush_renderer.setup(sim.world, sim.bushes)
	structure_renderer = StructureRenderer.new()
	add_child(structure_renderer)
	structure_renderer.setup(sim.structure_defs)
	item_renderer = ItemRenderer.new()
	add_child(item_renderer)
	item_renderer.setup(sim.world, sim.item_defs)
	tree_renderer = TreeRenderer.new()
	add_child(tree_renderer)
	tree_renderer.setup(sim.world)
	field_overlay = FieldDebugRenderer.new()
	add_child(field_overlay)
	selection_ring = Sprite2D.new()
	var ring_img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	ring_img.set_pixel(0, 0, Color.WHITE)
	selection_ring.texture = ImageTexture.create_from_image(ring_img)
	selection_ring.centered = false
	selection_ring.scale = Vector2.ONE * (TerrainRenderer.TILE_PX + 4)
	selection_ring.modulate = Color(1.0, 1.0, 1.0, 0.3)
	selection_ring.visible = false
	add_child(selection_ring)
	rally_marker = Sprite2D.new()
	var marker_img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	marker_img.set_pixel(0, 0, Color.WHITE)
	rally_marker.texture = ImageTexture.create_from_image(marker_img)
	rally_marker.centered = false
	rally_marker.scale = Vector2(TerrainRenderer.TILE_PX, TerrainRenderer.TILE_PX)
	rally_marker.modulate = Palette.COLORS[18]
	rally_marker.visible = false
	add_child(rally_marker)
	actor_renderer = ActorRenderer.new()
	add_child(actor_renderer)
	actor_renderer.setup(world_seed)
	carry_renderer = CarryRenderer.new()
	add_child(carry_renderer)
	carry_renderer.setup(sim.item_defs)
	build_overlay = BuildOverlay.new()
	add_child(build_overlay)
	_apply_field_overlay()

	var map_px := Vector2(sim.world.width, sim.world.height) * TerrainRenderer.TILE_PX
	_place_camera(map_px * 0.5)
	zoom_idx = default_zoom_idx
	cam.zoom = Vector2.ONE * ZOOM_STEPS[zoom_idx]


func _process(delta: float) -> void:
	if not sim_paused:
		accumulator += delta * SPEEDS[speed_idx]
		var ticks := 0
		var t0 := Time.get_ticks_usec()
		while accumulator >= Simulation.TICK_DT and ticks < MAX_TICKS_PER_FRAME:
			sim.tick()
			accumulator -= Simulation.TICK_DT
			ticks += 1
		if accumulator >= Simulation.TICK_DT:
			accumulator = fmod(accumulator, Simulation.TICK_DT)
		if ticks > 0:
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / ticks
			avg_tick_ms = ms if avg_tick_ms == 0.0 else lerpf(avg_tick_ms, ms, 0.05)

	var alpha := clampf(accumulator / Simulation.TICK_DT, 0.0, 1.0)
	actor_renderer.sync(sim.actors, alpha, cam.zoom.x)
	carry_renderer.sync(sim.actors, alpha, cam.zoom.x)
	bush_renderer.sync(sim.bushes)
	tree_renderer.sync(sim.trees)
	item_renderer.sync(sim.items)
	structure_renderer.sync(sim.world, sim.blueprints)
	_pan_camera(delta)
	_update_hud()
	_update_selection()
	_update_paint_ui()

	if _screenshot_mode:
		_frame += 1
		if _frame == _shot_frame:
			var _err: int = get_viewport().get_texture().get_image().save_png("res://tmp_screenshot.png")
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("sim_pause"):
		sim_paused = not sim_paused
	elif event.is_action_pressed("sim_speed_1"):
		speed_idx = 0
	elif event.is_action_pressed("sim_speed_2"):
		speed_idx = 1
	elif event.is_action_pressed("sim_speed_3"):
		speed_idx = 2
	elif event.is_action_pressed("debug_spawn"):
		sim.spawn_actors(100)
	elif event.is_action_pressed("debug_new_seed"):
		_start(randi())
	elif event.is_action_pressed("debug_regen"):
		_start(world_seed)
	elif event.is_action_pressed("tool_paint"):
		palette.select_tool(PaletteBar.Tool.PAINT)
	elif event.is_action_pressed("tool_pattern"):
		palette.select_tool(PaletteBar.Tool.PATTERN)
	elif event.is_action_pressed("tool_eyedropper"):
		palette.select_tool(PaletteBar.Tool.EYEDROPPER)
	elif event.is_action_pressed("tool_cancel"):
		palette.select_tool(PaletteBar.Tool.CANCEL)
	elif event.is_action_pressed("shelf_next"):
		palette.cycle_shelf()
	elif event.is_action_pressed("ui_cancel"):
		# Esc: put the brush down; pointer mode selects settlers.
		chop_plan_mode = false
		if palette.tool == PaletteBar.Tool.POINTER:
			selected_id = -1
		palette.select_tool(PaletteBar.Tool.POINTER)
	elif event.is_action_pressed("debug_field"):
		show_field = not show_field
		_apply_field_overlay()
	elif event.is_action_pressed("zoom_in"):
		_zoom(1)
	elif event.is_action_pressed("zoom_out"):
		_zoom(-1)
	else:
		var i := 0
		while i < 8:
			if event.is_action_pressed("swatch_%d" % (i + 1)):
				palette.select_swatch(i)
				return
			i += 1
		var key := event as InputEventKey
		if key and key.pressed and not key.echo and key.physical_keycode == KEY_C:
			# Placeholder chop-plan input pending the plan-tool design round:
			# C toggles the mode; LMB plans a tree, RMB cancels the plan.
			chop_plan_mode = not chop_plan_mode
			if chop_plan_mode:
				palette.select_tool(PaletteBar.Tool.POINTER)
			return
		if key and key.physical_keycode == KEY_ALT:
			# Hold-Alt = temporary eyedropper while any tool is in hand.
			if key.pressed and not key.echo:
				palette.alt_down()
			elif not key.pressed:
				palette.alt_up()
			return
		_handle_mouse(event)


func _handle_mouse(event: InputEvent) -> void:
	var tile_pos := get_global_mouse_position() / TerrainRenderer.TILE_PX
	var cell := Vector2i(floori(tile_pos.x), floori(tile_pos.y))
	if chop_plan_mode:
		_handle_chop_input(event, cell)
		return
	var tool: int = palette.tool
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_RIGHT and tool != PaletteBar.Tool.POINTER:
			# Quick-erase stays on RMB regardless of tool: muscle memory.
			var _c: bool = sim.cancel_blueprint(cell.x, cell.y)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		match tool:
			PaletteBar.Tool.PAINT, PaletteBar.Tool.PATTERN:
				_stroke_len = 0
				_last_stroke_cell = -1
				if mb.shift_pressed and _line_anchor.x != -9999:
					_commit_line(_line_anchor, cell, tool)
				else:
					_paint_cell(cell, tool)
				_line_anchor = cell
			PaletteBar.Tool.CANCEL:
				_last_stroke_cell = cell.y * sim.world.width + cell.x
				var _c2: bool = sim.cancel_blueprint(cell.x, cell.y)
			PaletteBar.Tool.EYEDROPPER:
				_eyedrop(cell)
			PaletteBar.Tool.POINTER:
				var picked := _pick_settler(tile_pos)
				if picked >= 0:
					selected_id = sim.actors.ids[picked]
				elif mb.shift_pressed:
					# Debug verb: rally everyone to the clicked tile.
					_rally(cell.x, cell.y)
				else:
					selected_id = -1
		return
	# Drag: freehand stroke (paint/pattern) or sweep-erase (cancel).
	var motion := event as InputEventMouseMotion
	if motion and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		match tool:
			PaletteBar.Tool.PAINT, PaletteBar.Tool.PATTERN:
				_paint_cell(cell, tool)
				_line_anchor = cell
			PaletteBar.Tool.CANCEL:
				var flat := cell.y * sim.world.width + cell.x
				if flat != _last_stroke_cell:
					_last_stroke_cell = flat
					var _c3: bool = sim.cancel_blueprint(cell.x, cell.y)


func _paint_cell(cell: Vector2i, tool: int) -> void:
	var flat := cell.y * sim.world.width + cell.x
	if flat == _last_stroke_cell:
		return
	_last_stroke_cell = flat
	# Pattern brush v1: one pattern, 1-on / 1-off (fence posts).
	var on := tool != PaletteBar.Tool.PATTERN or _stroke_len % 2 == 0
	_stroke_len += 1
	if not on:
		return
	var sw := palette.loaded_swatch()
	var _placed: bool = sim.place_blueprint(cell.x, cell.y, sw["type"], sw["mat"])


## Shift-click: fill the chalk line into ghosts in one stroke.
func _commit_line(a: Vector2i, b: Vector2i, tool: int) -> void:
	var cells := BuildOverlay.cells_between(a, b)
	var sw := palette.loaded_swatch()
	for i: int in cells.size():
		if tool == PaletteBar.Tool.PATTERN and i % 2 == 1:
			continue
		var _placed: bool = sim.place_blueprint(cells[i].x, cells[i].y, sw["type"], sw["mat"])


## Eyedropper: built structures first, then ghosts — pick up whatever the
## world has at this cell and load its swatch.
## Chop-plan strokes: press or drag with LMB plans trees, RMB cancels.
func _handle_chop_input(event: InputEvent, cell: Vector2i) -> void:
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var buttons := 0
	if mb and mb.pressed:
		buttons = 1 if mb.button_index == MOUSE_BUTTON_LEFT \
				else (2 if mb.button_index == MOUSE_BUTTON_RIGHT else 0)
	elif mm:
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			buttons = 1
		elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			buttons = 2
	if buttons == 1:
		var _d: bool = sim.designate_chop(cell.x, cell.y)
	elif buttons == 2:
		var _c: bool = sim.cancel_chop(cell.x, cell.y)


func _eyedrop(cell: Vector2i) -> void:
	var w := sim.world
	if cell.x < 0 or cell.y < 0 or cell.x >= w.width or cell.y >= w.height:
		return
	var flat := cell.y * w.width + cell.x
	if w.structures[flat] != SimWorld.STRUCT_NONE:
		var _f: bool = palette.pick(int(w.structures[flat]), int(w.structure_materials[flat]))
		return
	var bidx: int = sim.blueprints.cell_lookup.get(flat, -1)
	if bidx >= 0:
		var _f2: bool = palette.pick(
			int(sim.blueprints.types[bidx]), int(sim.blueprints.materials[bidx]))


## Per-frame paint feedback: bar placement, cursor glyph, hover outline,
## shift-line preview. The OS pointer returns over UI and in pointer mode.
func _update_paint_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	palette.position = Vector2(
		floorf((vp.x - palette.size.x) * 0.25) * 2.0, floorf(vp.y - palette.size.y - 20.0))
	var tool: int = palette.tool
	var over_ui := palette.get_global_rect().has_point(get_viewport().get_mouse_position())
	var painting := tool != PaletteBar.Tool.POINTER and not over_ui and not _screenshot_mode
	tool_cursor.visible = painting
	tool_cursor.update_tool(tool, palette.loaded_swatch()["chip"])
	var tile := get_global_mouse_position() / TerrainRenderer.TILE_PX
	var cell := Vector2i(floori(tile.x), floori(tile.y))
	var line: Array[Vector2i] = []
	if painting and (tool == PaletteBar.Tool.PAINT or tool == PaletteBar.Tool.PATTERN) \
			and Input.is_key_pressed(KEY_SHIFT) and _line_anchor.x != -9999:
		line = BuildOverlay.cells_between(_line_anchor, cell)
	var hover := cell if painting else Vector2i(-9999, -9999)
	var hover_color := BuildOverlay.GHOST_LIGHT
	if tool == PaletteBar.Tool.CANCEL:
		hover_color = BuildOverlay.WARNING
	elif tool == PaletteBar.Tool.EYEDROPPER:
		hover_color = BuildOverlay.SHEEN
	build_overlay.update_state(hover, line, hover_color, cam.zoom.x)


## Nearest settler within ~a tile of the click, or -1.
func _pick_settler(tile_pos: Vector2) -> int:
	var best := -1
	var best_dist := 0.8
	for i: int in sim.actors.count:
		var d := sim.actors.positions[i].distance_to(tile_pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## Debug: paint an 8x6 house (walls, door, two beds) at the first fully
## walkable rect scanning out from the map center, and aim the camera at it.
## Dev demo: chop plans on every tree near spawn + a wall row, so a
## --warmup run screenshots the material cycle mid-flight.
func _demo_material_cycle() -> void:
	var w := sim.world.width
	@warning_ignore("integer_division")
	var cx := w / 2
	@warning_ignore("integer_division")
	var cy := sim.world.height / 2
	for cell: int in sim.trees.cells.duplicate():
		var tx := cell % w
		@warning_ignore("integer_division")
		var ty := cell / w
		if maxi(absi(tx - cx), absi(ty - cy)) <= 30:
			var _d: bool = sim.designate_chop(tx, ty)
	var placed := 0
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			if placed >= 6:
				break
			if sim.place_blueprint(cx + dx, cy + dy, SimWorld.STRUCT_WALL):
				placed += 1


func _place_demo_house() -> void:
	var w := sim.world
	@warning_ignore("integer_division")
	var start_y := w.height / 2 - 3
	@warning_ignore("integer_division")
	var start_x := w.width / 2 - 4
	for y: int in range(start_y, w.height - 8):
		for x: int in range(start_x, w.width - 10):
			var clear := true
			for dy: int in 6:
				for dx: int in 8:
					if not w.is_walkable(x + dx, y + dy):
						clear = false
			if not clear:
				continue
			for dx: int in 8:
				for dy: int in 6:
					var edge := dx == 0 or dy == 0 or dx == 7 or dy == 5
					if not edge:
						continue
					if dx == 3 and dy == 5:
						var _d: bool = sim.place_blueprint(x + dx, y + dy, SimWorld.STRUCT_DOOR)
					else:
						var _w: bool = sim.place_blueprint(x + dx, y + dy, SimWorld.STRUCT_WALL)
			var _b1: bool = sim.place_blueprint(x + 2, y + 2, SimWorld.STRUCT_BED)
			var _b2: bool = sim.place_blueprint(x + 5, y + 2, SimWorld.STRUCT_BED)
			# Marble wing off the NE corner: proves cross-material wall
			# connectivity and per-material sheets in one glance.
			for dx: int in 3:
				var _m: bool = sim.place_blueprint(x + 8 + dx, y, SimWorld.STRUCT_WALL, 1)
			_place_camera(Vector2(x + 4, y + 3) * TerrainRenderer.TILE_PX)
			return


func _rally(x: int, y: int) -> void:
	if not sim.set_command_target(x, y):
		return
	rally_marker.position = Vector2(x, y) * TerrainRenderer.TILE_PX
	rally_marker.visible = true
	_apply_field_overlay()


func _apply_field_overlay() -> void:
	field_overlay.visible = show_field and sim.command_field != null
	if field_overlay.visible:
		field_overlay.build(sim.world, sim.command_field)


func _zoom(direction: int) -> void:
	zoom_idx = clampi(zoom_idx + direction, 0, ZOOM_STEPS.size() - 1)
	cam.zoom = Vector2.ONE * ZOOM_STEPS[zoom_idx]
	cam.position = _snap_screen_px(_cam_pos)


## All camera placement goes through here so the continuous pan position
## stays in sync — the camera rides the screen-pixel grid so texels never
## straddle screen pixels (mixels), while panning stays visually smooth.
func _place_camera(pos: Vector2) -> void:
	_cam_pos = pos
	cam.position = _snap_screen_px(pos)


func _snap_screen_px(pos: Vector2) -> Vector2:
	var z := cam.zoom.x
	return (pos * z).round() / z


func _pan_camera(delta: float) -> void:
	var dir := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	if dir == Vector2.ZERO:
		return
	_cam_pos += dir * PAN_SPEED * delta / cam.zoom.x
	cam.position = _snap_screen_px(_cam_pos)


func _update_hud() -> void:
	var speed_text := "paused" if sim_paused else "%dx" % int(SPEEDS[speed_idx])
	var responding := 0
	for i: int in sim.actors.count:
		if sim.actors.responding[i] == 1:
			responding += 1
	var sw := palette.loaded_swatch()
	var build_text: String = TOOL_NAMES[palette.tool] + " / " + str(sw["label"]).to_lower()
	if chop_plan_mode:
		build_text = "chop plans (LMB plan / RMB cancel)"
	hud.text = (
		"seed %d | actors %d (%d rallying) | brush: %s | bp %d | speed %s | zoom %s | fps %d | sim tick %.2f ms | tick %d\n" % [
			world_seed, sim.actors.count, responding, build_text, sim.blueprints.cells.size(),
			speed_text, str(ZOOM_STEPS[zoom_idx]),
			Engine.get_frames_per_second(), avg_tick_ms, sim.tick_count,
		]
		+ "[B/P/I/X] tools  [C] chop plans  [1-8] swatches  [Tab] shelf  [shift+click] line  [hold Alt] pick  [RMB] erase  [Esc] pointer (inspect / shift+click rally)  [Space] pause  [F1-F3] speed  [F] +100  [G] field  [N] seed  [R] regen  [WASD] pan  [wheel] zoom"
	)


func _update_selection() -> void:
	var idx := sim.actors.ids.find(selected_id) if selected_id >= 0 else -1
	if idx < 0:
		selection_ring.visible = false
		panel.visible = false
		return
	var pool := sim.actors
	var pos := pool.prev_positions[idx].lerp(pool.positions[idx], clampf(accumulator / Simulation.TICK_DT, 0.0, 1.0))
	var half := (TerrainRenderer.TILE_PX + 4) * 0.5
	selection_ring.position = pos * TerrainRenderer.TILE_PX - Vector2(half, half)
	selection_ring.visible = true

	var lines: Array[String] = []
	lines.append("settler #%d | speed %.1f" % [pool.ids[idx], pool.speeds[idx]])
	for nd: int in sim.defs.needs.size():
		var v := pool.needs[nd][idx]
		lines.append("%-8s %s %3d%%" % [sim.defs.needs[nd].id, _bar(v), int(v * 100.0)])
	if pool.responding[idx] == 1:
		lines.append("action: rallying (player command)")
	else:
		var a := pool.current_action[idx]
		var scores: Array[String] = []
		for k: int in sim.defs.actions.size():
			if k != a:
				scores.append("%s %.2f" % [sim.defs.actions[k].id, pool.last_scores[idx * sim.defs.actions.size() + k]])
		if a >= 0:
			var phase_text := pool.phase_label(sim.defs, idx)
			lines.append("action: %s%s (%.2f)" % [
				sim.defs.actions[a].id,
				":" + phase_text if not phase_text.is_empty() else "",
				pool.last_scores[idx * sim.defs.actions.size() + a],
			])
		lines.append("also considered: %s" % ", ".join(scores))
	panel.text = "\n".join(lines)
	panel.visible = true


static func _bar(v: float) -> String:
	var filled := roundi(clampf(v, 0.0, 1.0) * 10.0)
	return "[%s%s]" % ["|".repeat(filled), ".".repeat(10 - filled)]
