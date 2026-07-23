extends Node2D
## Game layer: owns the fixed-timestep loop, time controls, camera, input,
## and telemetry. This is the only place wall-clock time exists; the sim
## just gets tick() called on it.
##
## Controls: [Space] pause  [1/2/3] speed  [F] +100 actors  [N] new seed
##           [R] regen same seed  [WASD/arrows] pan  [wheel] zoom

const SPEEDS := [1.0, 3.0, 6.0]
const MAX_TICKS_PER_FRAME := 12
const PAN_SPEED := 900.0

var sim: Simulation
var world_seed := 0
var sim_paused := false
var speed_idx := 0
var accumulator := 0.0
var avg_tick_ms := 0.0

var terrain: TerrainRenderer
var actor_renderer: ActorRenderer
var cam: Camera2D
var hud: Label

var _screenshot_mode := false
var _frame := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_screenshot_mode = "--screenshot" in args
	var start_seed := int(Time.get_unix_time_from_system()) if not _screenshot_mode else 12345
	for a in args:
		if a.begins_with("--seed="):
			start_seed = int(a.trim_prefix("--seed="))

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

	_start(start_seed)


func _start(seed_value: int) -> void:
	world_seed = seed_value
	sim = Simulation.new(world_seed)
	sim.actors.spawn(sim.world, 100)
	accumulator = 0.0
	avg_tick_ms = 0.0

	if terrain:
		terrain.queue_free()
	if actor_renderer:
		actor_renderer.queue_free()
	terrain = TerrainRenderer.new()
	add_child(terrain)
	terrain.build(sim.world)
	actor_renderer = ActorRenderer.new()
	add_child(actor_renderer)
	actor_renderer.setup(world_seed)

	var map_px := Vector2(sim.world.width, sim.world.height) * TerrainRenderer.TILE_PX
	cam.position = map_px * 0.5
	cam.zoom = Vector2(0.4, 0.4)


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
	_pan_camera(delta)
	_update_hud()

	if _screenshot_mode:
		_frame += 1
		if _frame == 90:
			get_viewport().get_texture().get_image().save_png("res://tmp_screenshot.png")
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				sim_paused = not sim_paused
			KEY_1:
				speed_idx = 0
			KEY_2:
				speed_idx = 1
			KEY_3:
				speed_idx = 2
			KEY_F:
				sim.actors.spawn(sim.world, 100)
			KEY_N:
				_start(randi())
			KEY_R:
				_start(world_seed)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = (cam.zoom * 1.15).clampf(0.1, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = (cam.zoom / 1.15).clampf(0.1, 8.0)


func _pan_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	cam.position += dir * PAN_SPEED * delta / cam.zoom.x


func _update_hud() -> void:
	var speed_text := "paused" if sim_paused else "%dx" % int(SPEEDS[speed_idx])
	hud.text = (
		"seed %d | actors %d | speed %s | fps %d | sim tick %.2f ms | tick %d\n" % [
			world_seed, sim.actors.count, speed_text,
			Engine.get_frames_per_second(), avg_tick_ms, sim.tick_count,
		]
		+ "[Space] pause  [1/2/3] speed  [F] +100 actors  [N] new seed  [R] regen  [WASD] pan  [wheel] zoom"
	)
