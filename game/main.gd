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
const DEFAULT_ZOOM_IDX := 3

var sim: Simulation
var world_seed := 0
var sim_paused := false
var speed_idx := 0
var default_zoom_idx := DEFAULT_ZOOM_IDX
var start_actors := 100
var zoom_idx := DEFAULT_ZOOM_IDX
var accumulator := 0.0
var avg_tick_ms := 0.0

var terrain: TerrainRenderer
var actor_renderer: ActorRenderer
var bush_renderer: BushRenderer
var field_overlay: FieldDebugRenderer
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

	_start(start_seed)
	if _rally_arg.contains(","):
		var parts := _rally_arg.split(",")
		_rally(int(parts[0]), int(parts[1]))
	for t: int in _warmup_ticks:
		sim.tick()
	if "--inspect" in args and sim.actors.count > 0:
		selected_id = sim.actors.ids[0]
		cam.position = sim.actors.positions[0] * TerrainRenderer.TILE_PX


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
	if selection_ring:
		selection_ring.queue_free()
	selected_id = -1
	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.build(sim.world)
	bush_renderer = BushRenderer.new()
	add_child(bush_renderer)
	bush_renderer.setup(sim.world, sim.bushes)
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
	_apply_field_overlay()

	var map_px := Vector2(sim.world.width, sim.world.height) * TerrainRenderer.TILE_PX
	cam.position = map_px * 0.5
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
	actor_renderer.sync(sim.actors, alpha)
	bush_renderer.sync(sim.bushes)
	_pan_camera(delta)
	_update_hud()
	_update_selection()

	if _screenshot_mode:
		_frame += 1
		if _frame == 90:
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
	elif event.is_action_pressed("debug_field"):
		show_field = not show_field
		_apply_field_overlay()
	elif event.is_action_pressed("zoom_in"):
		_zoom(1)
	elif event.is_action_pressed("zoom_out"):
		_zoom(-1)
	else:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var tile_pos := get_global_mouse_position() / TerrainRenderer.TILE_PX
			var picked := _pick_pawn(tile_pos)
			if picked >= 0:
				selected_id = sim.actors.ids[picked]
			else:
				_rally(floori(tile_pos.x), floori(tile_pos.y))


## Nearest pawn within ~a tile of the click, or -1.
func _pick_pawn(tile_pos: Vector2) -> int:
	var best := -1
	var best_dist := 0.8
	for i: int in sim.actors.count:
		var d := sim.actors.positions[i].distance_to(tile_pos)
		if d < best_dist:
			best_dist = d
			best = i
	return best


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


func _pan_camera(delta: float) -> void:
	var dir := Input.get_vector("pan_left", "pan_right", "pan_up", "pan_down")
	cam.position += dir * PAN_SPEED * delta / cam.zoom.x


func _update_hud() -> void:
	var speed_text := "paused" if sim_paused else "%dx" % int(SPEEDS[speed_idx])
	var responding := 0
	for i: int in sim.actors.count:
		if sim.actors.responding[i] == 1:
			responding += 1
	hud.text = (
		"seed %d | actors %d (%d rallying) | speed %s | zoom %s | fps %d | sim tick %.2f ms | tick %d\n" % [
			world_seed, sim.actors.count, responding, speed_text, str(ZOOM_STEPS[zoom_idx]),
			Engine.get_frames_per_second(), avg_tick_ms, sim.tick_count,
		]
		+ "[click] rally / inspect pawn  [Space] pause  [1/2/3] speed  [F] +100 actors  [G] field overlay  [N] new seed  [R] regen  [WASD] pan  [wheel] zoom"
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
	lines.append("pawn #%d | speed %.1f" % [pool.ids[idx], pool.speeds[idx]])
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
			lines.append("action: %s (%.2f)" % [
				sim.defs.actions[a].id,
				pool.last_scores[idx * sim.defs.actions.size() + a],
			])
		lines.append("also considered: %s" % ", ".join(scores))
	panel.text = "\n".join(lines)
	panel.visible = true


static func _bar(v: float) -> String:
	var filled := roundi(clampf(v, 0.0, 1.0) * 10.0)
	return "[%s%s]" % ["|".repeat(filled), ".".repeat(10 - filled)]
