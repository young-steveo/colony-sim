extends SceneTree
## ONE-SHOT BOOTSTRAP — re-running OVERWRITES content/terrain/*.png,
## including any hand-edits made in PyxelEdit since. Git history is
## the undo. Derives material sheets from dirt.png (the donor).
## One-shot bootstrap: derive terrain sheets from Stephen's dirt.png
## (the structural donor — silhouette, scallops, seam discipline all his).
## Per material: recolor the mask to its base, then stamp cell-local
## character features per the art-direction session. Features never touch
## transparent pixels (edges stay his) and never cross 16px cell bounds.

const CELL := 16
const COLS := 12
const ROWS := 5

class Rng:
	var state: int
	func _init(seed_v: int) -> void:
		state = seed_v if seed_v != 0 else 1
	func next() -> int:
		state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
		return state >> 16
	func range_i(lo: int, hi: int) -> int:
		return lo + next() % (hi - lo + 1)
	func chance(p: float) -> bool:
		return float(next() % 10000) / 10000.0 < p

func _init() -> void:
	var donor := Image.load_from_file(ProjectSettings.globalize_path("res://content/terrain/dirt.png"))
	_gen(donor, "stone", Color("7f708a"), _stone_features)
	_gen(donor, "grass", Color("676633"), _grass_features)
	_gen(donor, "dirt_fertile", Color("4c3e24"), _fertile_features)
	_gen(donor, "dirt_rocky", Color("966c6c"), _rocky_features)
	_gen(donor, "sand", Color("ab947a"), _sand_features)
	_gen(donor, "mud", Color("9e4539"), _mud_features)
	_gen_water(donor)
	print("done")
	quit()

func _gen(donor: Image, id: String, base: Color, features: Callable) -> void:
	var img := Image.create(donor.get_width(), donor.get_height(), false, Image.FORMAT_RGBA8)
	for y: int in donor.get_height():
		for x: int in donor.get_width():
			if donor.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, base)
	for cy: int in ROWS:
		for cx: int in COLS:
			var rng := Rng.new(hash(id) ^ (cy * COLS + cx + 7777))
			features.call(img, donor, cx * CELL, cy * CELL, rng)
	var _e := img.save_png(ProjectSettings.globalize_path("res://content/terrain/%s.png" % id))
	print(id)

## Every target pixel (plus nothing else) must be opaque in the donor.
func _stamp(img: Image, donor: Image, pts: Array, color: Color) -> bool:
	for p: Vector2i in pts:
		if p.x < 0 or p.y < 0 or p.x >= donor.get_width() or p.y >= donor.get_height():
			return false
		if donor.get_pixel(p.x, p.y).a == 0.0:
			return false
	for p: Vector2i in pts:
		img.set_pixel(p.x, p.y, color)
	return true

## Stone: mostly dead flat; ~1/3 of cells carry one thin crack (a short
## 1px random walk), the rest silence. Cracks read, dots sparkle.
func _stone_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	if not rng.chance(0.35):
		return
	var x := ox + rng.range_i(3, 11)
	var y := oy + rng.range_i(3, 11)
	var pts: Array = []
	var dir_x := 1 if rng.chance(0.5) else -1
	for s: int in rng.range_i(3, 5):
		pts.append(Vector2i(x, y))
		x += dir_x if rng.chance(0.7) else 0
		y += 1 if rng.chance(0.6) else 0
		if x < ox + 1 or x > ox + 14 or y > oy + 14:
			break
	var _ok := _stamp(img, donor, pts, Color("625565"))

## Grass: short vertical blade ticks, one step up-ramp, sparse.
func _grass_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	for i: int in rng.range_i(3, 5):
		var x := ox + rng.range_i(1, 14)
		var y := oy + rng.range_i(1, 12)
		var len_px := rng.range_i(2, 3)
		var pts: Array = []
		for dy: int in len_px:
			pts.append(Vector2i(x, y + dy))
		var _ok := _stamp(img, donor, pts, Color("a2a947"))

## Fertile: darker clumps, slightly denser than dirt ever was — abundance,
## not decoration. Low contrast (one ramp step down).
func _fertile_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	for i: int in rng.range_i(3, 4):
		var x := ox + rng.range_i(1, 13)
		var y := oy + rng.range_i(1, 13)
		var pts: Array = [Vector2i(x, y), Vector2i(x + 1, y)]
		if rng.chance(0.5):
			pts.append(Vector2i(x + rng.range_i(0, 1), y + 1))
		var _ok := _stamp(img, donor, pts, Color("676633"))

## Rocky dirt: the one deliberate cross-ramp — stone-colored pebbles with
## an ink-side shadow pixel; "don't farm here" is information.
func _rocky_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	for i: int in rng.range_i(1, 2):
		var x := ox + rng.range_i(2, 12)
		var y := oy + rng.range_i(2, 12)
		var pts: Array = [
			Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1),
		]
		if _stamp(img, donor, pts, Color("7f708a")):
			# No sheen glint on pebbles: a lone cool bright pixel per pebble
			# aggregates into blue confetti at play zoom (the navy-fleck
			# lesson, round two). The pebble body is enough.
			var _s := _stamp(img, donor, [Vector2i(x + 1, y + 1)], Color("625565"))

## Sand: flattest of all — a rare short horizontal ripple, base-shade.
func _sand_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	if not rng.chance(0.45):
		return
	for i: int in rng.range_i(1, 2):
		var x := ox + rng.range_i(1, 10)
		var y := oy + rng.range_i(2, 13)
		var pts: Array = []
		for dx: int in rng.range_i(3, 4):
			pts.append(Vector2i(x + dx, y))
		var _ok := _stamp(img, donor, pts, Color("966c6c"))

## Water rides the donor differently: the shore grammar is baked in.
## Donor-opaque pixels become deep water; donor-transparent pixels
## inside any used cell become opaque shallow fringe, so the land-side
## reveal band continues across the seam and dies on the donor's
## ragged silhouette instead of the straight cell boundary. Cells with
## no donor art (template hole, unused variant slots) stay empty.
func _gen_water(donor: Image) -> void:
	var deep := Color("0b5e65")
	var shallow := Color("0b8a8f")
	var img := Image.create(donor.get_width(), donor.get_height(), false, Image.FORMAT_RGBA8)
	for cy: int in ROWS:
		for cx: int in COLS:
			var used := false
			for y: int in CELL:
				for x: int in CELL:
					if donor.get_pixel(cx * CELL + x, cy * CELL + y).a > 0.0:
						used = true
						break
				if used:
					break
			if not used:
				continue
			for y: int in CELL:
				for x: int in CELL:
					var px := cx * CELL + x
					var py := cy * CELL + y
					img.set_pixel(px, py, deep if donor.get_pixel(px, py).a > 0.0 else shallow)
			# Ripples only on interior + variant cells: every coast tile of
			# a given mask is the same sheet cell, so a ripple there
			# wallpapers down the whole shoreline. Shore water stays calm.
			if cy == ROWS - 1 or cy * COLS + cx == Autotile.cell_for(255):
				var rng := Rng.new(hash("water") ^ (cy * COLS + cx + 7777))
				_water_features(img, donor, cx * CELL, cy * CELL, rng)
	var _e := img.save_png(ProjectSettings.globalize_path("res://content/terrain/water.png"))
	print("water")


## Water ripples: short horizontal ticks one ramp up (the shallows
## color), ends stepped down a pixel so they read as waves, not
## scratches; rare darker trough beneath. Sparse — lakes are big and
## bright specks aggregate at play zoom (the navy-fleck lesson).
## _stamp requires donor-opaque pixels, so ripples land on deep water
## only — the shallow fringe stays calm.
func _water_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	if not rng.chance(0.75):
		return
	for i: int in rng.range_i(1, 2):
		var x := ox + rng.range_i(2, 9)
		var y := oy + rng.range_i(2, 12)
		var run := rng.range_i(3, 5)
		var pts: Array = []
		for dx: int in run:
			var dy := 1 if (dx == 0 or dx == run - 1) and rng.chance(0.6) else 0
			pts.append(Vector2i(x + dx, y + dy))
		if _stamp(img, donor, pts, Color("0b8a8f")) and rng.chance(0.3):
			var _t := _stamp(img, donor, [Vector2i(x + 1, y + 2), Vector2i(x + 2, y + 2)], Color("084850"))


## Mud: dark pools plus the one licensed sparkle — single-pixel wet
## glints, sparse, so still pools and matte patches both exist.
func _mud_features(img: Image, donor: Image, ox: int, oy: int, rng: Rng) -> void:
	if rng.chance(0.4):
		var x := ox + rng.range_i(2, 11)
		var y := oy + rng.range_i(2, 12)
		var pts: Array = [
			Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y),
			Vector2i(x + rng.range_i(0, 1), y + 1), Vector2i(x + 1 + rng.range_i(0, 1), y + 1),
		]
		var _ok := _stamp(img, donor, pts, Color("7a3045"))
	if rng.chance(0.5):
		for i: int in rng.range_i(1, 2):
			var p := Vector2i(ox + rng.range_i(1, 14), oy + rng.range_i(1, 14))
			var _g := _stamp(img, donor, [p], Color("7f708a"))
