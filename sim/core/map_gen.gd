class_name MapGen
extends RefCounted
## Deterministic terrain generation: fractal value noise built entirely on
## SimRng, so the same seed always produces the same map. Walking-skeleton
## generator — regions, rivers, ruins, WFC detail passes replace this later.
##
## Worldgen fields (GDD: Soft ground & mud — fields plan): few PHYSICAL
## primaries, derive everything else. Primaries: ELEVATION (coastline,
## stone line), RAINFALL (climate-scale wet/dry regions), SOIL DEPTH (how
## far down bedrock is, thinning with altitude). Derived: WETNESS =
## f(rainfall, distance-to-water) — ground truth, not climate. Materials
## are then classification, never decree: fertile = deep + wet, rocky =
## thin soil, mud = soaked short of open water, sand = dry shoreline,
## stone = no soil at all. Believability comes from the correlations the
## continuous fields carry for free.
##
## Each octave's lattice values are precomputed once (thousands of hashes)
## instead of hashed per tile corner (millions) — ~20x faster, still a pure
## function of the seed.

const OCTAVES := 4
const BASE_FREQUENCY := 1.0 / 48.0
const RAIN_FREQUENCY := 1.0 / 96.0  # climate varies slower than terrain
const SOIL_FREQUENCY := 1.0 / 32.0

const THRESHOLD_WATER := 0.34
const THRESHOLD_PEAK := 0.72  # above this, bedrock breaks the surface
const SOIL_BARE := 0.16  # thinner than this = exposed stone
const SOIL_ROCKY := 0.34
const SOIL_FERTILE := 0.58
const WET_MUD := 0.70
const WET_FERTILE := 0.50
const WET_GRASS := 0.32
const WET_SAND_MAX := 0.52  # sand only on DRY shores
const SAND_SHORE_DIST := 2
const WATER_REACH := 12.0  # tiles over which proximity wetness fades


## Returns { "substrate": PackedByteArray, "surface": PackedByteArray }.
static func generate(world_seed: int, width: int, height: int) -> Dictionary:
	var cell_count := width * height
	var elevation := _fractal(SimRng.key([world_seed, "terrain"]), width, height, OCTAVES, BASE_FREQUENCY)
	var rainfall := _fractal(SimRng.key([world_seed, "rainfall"]), width, height, 2, RAIN_FREQUENCY)
	var soil_noise := _fractal(SimRng.key([world_seed, "soil"]), width, height, 3, SOIL_FREQUENCY)

	# Distance to open water (4-way BFS) — wetness is ground truth, and
	# ground near water is wet regardless of climate.
	var dist := PackedInt32Array()
	var _e1: int = dist.resize(cell_count)
	dist.fill(0x3FFFFFFF)
	var queue := PackedInt32Array()
	for c: int in cell_count:
		if elevation[c] < THRESHOLD_WATER:
			dist[c] = 0
			var _e2: bool = queue.push_back(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % width
		var d := dist[c] + 1
		for n: int in [c - width, c + width, c - 1, c + 1]:
			if n < 0 or n >= cell_count:
				continue
			if (n == c - 1 and cx == 0) or (n == c + 1 and cx == width - 1):
				continue
			if d < dist[n]:
				dist[n] = d
				var _e3: bool = queue.push_back(n)

	var substrate := PackedByteArray()
	var surface := PackedByteArray()
	var wetness := PackedFloat32Array()
	var _e4: int = substrate.resize(cell_count)
	var _e5: int = surface.resize(cell_count)
	var _e6: int = wetness.resize(cell_count)
	var jitter_key := SimRng.key([world_seed, "wetness_jitter"])
	for c: int in cell_count:
		var e := elevation[c]
		# Per-cell jitter breaks threshold isolines: without it, mud forms
		# a mathematically uniform one-cell crust along every wet shore —
		# an outline stroke, not a material. With it, banks come in
		# organic patches (the gentle pass below sweeps the crumbs).
		var jitter := (SimRng.randf(SimRng.combine(jitter_key, c)) - 0.5) * 0.12
		var proximity := clampf(1.0 - float(dist[c]) / WATER_REACH, 0.0, 1.0)
		wetness[c] = 0.6 * rainfall[c] + 0.4 * proximity + jitter
		if e < THRESHOLD_WATER:
			substrate[c] = SimWorld.TILE_WATER
			continue
		var soil := soil_noise[c] * (1.0 - 0.6 * e)  # thin up high
		if e >= THRESHOLD_PEAK or soil < SOIL_BARE:
			substrate[c] = SimWorld.TILE_STONE
		elif dist[c] <= SAND_SHORE_DIST and wetness[c] < WET_SAND_MAX:
			substrate[c] = SimWorld.TILE_SAND
		elif wetness[c] >= WET_MUD:
			substrate[c] = SimWorld.TILE_MUD
		elif soil >= SOIL_FERTILE and wetness[c] >= WET_FERTILE:
			substrate[c] = SimWorld.TILE_DIRT_FERTILE
		elif soil < SOIL_ROCKY:
			substrate[c] = SimWorld.TILE_DIRT_ROCKY
		else:
			substrate[c] = SimWorld.TILE_DIRT

	_defizz(substrate, width, height)

	for c: int in cell_count:
		# Grass grows on soil that holds some water — including fertile
		# ground (its fringe then exposes fertile dirt: the seam rule).
		var s := substrate[c]
		if (s == SimWorld.TILE_DIRT or s == SimWorld.TILE_DIRT_FERTILE) and wetness[c] >= WET_GRASS:
			surface[c] = SimWorld.SURF_GRASS
	return {"substrate": substrate, "surface": surface}


## The gentle pass: a LAND cell with zero orthogonal same-substrate
## neighbors takes the most common land substrate around it. Kills the
## threshold-isoline dithering (diagonal staircases of island blobs)
## while keeping every region, band, and deliberate-feeling lone tuft
## that has even one friend. Water never changes — the coastline is
## elevation truth. Deterministic: reads the pre-pass state only.
static func _defizz(substrate: PackedByteArray, width: int, height: int) -> void:
	var before := substrate.duplicate()
	for y: int in range(1, height - 1):
		for x: int in range(1, width - 1):
			var c := y * width + x
			var mine := before[c]
			if mine == SimWorld.TILE_WATER:
				continue
			var lonely := true
			for n: int in [c - width, c + width, c - 1, c + 1]:
				if before[n] == mine:
					lonely = false
					break
			if not lonely:
				continue
			var counts := {}
			var best := mine
			var best_n := 0
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nv := before[c + dy * width + dx]
					if nv == SimWorld.TILE_WATER:
						continue
					counts[nv] = int(counts.get(nv, 0)) + 1
					if counts[nv] > best_n:
						best_n = counts[nv]
						best = nv
			substrate[c] = best


## Normalized [0,1] fractal value noise, lattice precomputed per octave.
static func _fractal(
	field_key: int, width: int, height: int, octaves: int, base_frequency: float
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var _err: int = out.resize(width * height)
	out.fill(0.0)
	var norm := 0.0
	var amplitude := 1.0
	var frequency := base_frequency

	for octave: int in octaves:
		var lattice_w := floori((width - 1) * frequency) + 2
		var lattice_h := floori((height - 1) * frequency) + 2
		var lattice := PackedFloat32Array()
		var _err2: int = lattice.resize(lattice_w * lattice_h)
		var octave_key := SimRng.combine(field_key, octave)
		for cy: int in lattice_h:
			var row_key := SimRng.combine(octave_key, cy)
			var row := cy * lattice_w
			for cx: int in lattice_w:
				lattice[row + cx] = SimRng.randf(SimRng.combine(row_key, cx))

		for y: int in height:
			var fy := y * frequency
			var y0 := floori(fy)
			var ty := fy - y0
			ty = ty * ty * (3.0 - 2.0 * ty)
			var row0 := y0 * lattice_w
			var row1 := row0 + lattice_w
			var out_row := y * width
			for x: int in width:
				var fx := x * frequency
				var x0 := floori(fx)
				var tx := fx - x0
				tx = tx * tx * (3.0 - 2.0 * tx)
				var top := lerpf(lattice[row0 + x0], lattice[row0 + x0 + 1], tx)
				var bottom := lerpf(lattice[row1 + x0], lattice[row1 + x0 + 1], tx)
				out[out_row + x] += amplitude * lerpf(top, bottom, ty)

		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.0

	var inv := 1.0 / norm
	for i: int in out.size():
		out[i] *= inv
	return out
