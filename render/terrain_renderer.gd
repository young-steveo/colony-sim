class_name TerrainRenderer
extends Node2D
## Data-driven terrain rendering (defs from content/terrain/terrain.json).
##
## Two passes. Base: one image, one pixel per tile, scaled up — each cell
## painted its material's flat color with hashed shade variation. Overlay:
## every material with a blob sheet autotiles through the shared 47-blob
## template (same Autotile + shader the walls use), one MultiMesh per
## material.
##
## The trick that makes transition art work over any neighbor: under a
## sheeted cell that borders another material, the base pixel paints the
## NEIGHBOR's color, so the overlay's scalloped edges reveal the material
## being transitioned onto — never the sheeted material's own flat color.
## Interior (mask 255) cells hash-pick among the sheet's bottom-row variant
## cells, which is what keeps big fields from reading as a stamp grid.
## Terrain is immutable in v1, so build() runs once per map.
##
## Tile stack: substrates autotile against substrates (dirt runs
## CONTINUOUSLY under grass fields), and sheeted surfaces are a second
## overlay pass on top — the grass fringe reveals real dirt art through
## its own transitions. A surface without art yet still flat-covers its
## cell in the base pass, so future sheetless surfaces degrade gracefully.

const TILE_PX := 16
const BLOB_SHADER := preload("res://render/autotile_blob.gdshader")

# Neighbor scan order for the reveal color: cardinals first — an edge cell
# shows the material it directly abuts, diagonals only decide corners.
const NEIGHBOR_ORDER: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
]


func build(world: SimWorld, defs: TerrainDefs) -> void:
	for child: Node in get_children():
		child.queue_free()
	_build_base(world, defs)
	for mat: int in defs.count():
		if defs.sheets[mat] == "":
			continue
		# Blend priority (content contract): at a seam only the HIGHER
		# blend material scallops; the lower extends flat to the edge.
		# Connected = same material, or any higher-blend neighbor.
		var lut := PackedByteArray()
		var _e: int = lut.resize(defs.count())
		for n: int in defs.count():
			lut[n] = 1 if (n == mat or defs.blend[n] > defs.blend[mat]) else 0
		_build_overlay(world, defs.sheets[mat], world.tiles, mat, defs.ids[mat], lut)
	for s: int in range(1, defs.surface_ids.size()):
		if defs.surface_sheets[s] == "":
			continue
		var slut := PackedByteArray()
		var _e2: int = slut.resize(defs.surface_ids.size())
		slut[s] = 1
		_build_overlay(world, defs.surface_sheets[s], world.surfaces, s, defs.surface_ids[s], slut)


func _build_base(world: SimWorld, defs: TerrainDefs) -> void:
	var base := Sprite2D.new()
	base.centered = false
	base.scale = Vector2(TILE_PX, TILE_PX)
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade_key := SimRng.key([world.world_seed, "tile_shade"])
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	for y: int in world.height:
		for x: int in world.width:
			var cell := y * world.width + x
			var mat := world.tiles[cell]
			var surf := world.surfaces[cell]
			var c: Color
			if surf != SimWorld.SURF_NONE and defs.surface_sheets[surf] == "":
				c = defs.surface_colors[surf]  # sheetless surface flat-covers
			elif surf != SimWorld.SURF_NONE:
				# Sheeted surface: its fringe exposes the ground it grows ON,
				# not the neighbor — grass thins to soil before soil meets
				# anything else (Stephen's rule, July 2026).
				c = defs.colors[mat]
			elif defs.sheets[mat] != "":
				c = defs.colors[_reveal_substrate(world, defs, x, y, mat)]
			else:
				c = defs.colors[mat]
			var k := SimRng.combine(SimRng.combine(shade_key, x), y)
			var shade := 0.92 + 0.16 * SimRng.randf(k)
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	base.texture = ImageTexture.create_from_image(img)
	add_child(base)


## What shows through a bare substrate's transition notches. Substrates
## always yield to substrates — at a grass-field boundary the grass has
## already thinned to soil (see above), so stone meeting grassland
## correctly reveals the soil line. The base image is ONE pixel per tile,
## so a cell gets a single reveal color under all its notches even when
## it borders different materials on different sides: take the MAJORITY
## differing neighbor (sides outvote corners 2:1), so one mud corner
## can't speak for three dirt sides.
func _reveal_substrate(world: SimWorld, defs: TerrainDefs, x: int, y: int, mat: int) -> int:
	var votes := {}
	var best := mat
	var best_v := 0
	for i: int in NEIGHBOR_ORDER.size():
		var offset := NEIGHBOR_ORDER[i]
		var n := world.tile_at(
			clampi(x + offset.x, 0, world.width - 1), clampi(y + offset.y, 0, world.height - 1))
		if n == mat or defs.blend[n] > defs.blend[mat]:
			continue  # we only scallop toward LOWER-blend ground
		votes[n] = int(votes.get(n, 0)) + (2 if i < 4 else 1)  # cardinals first in order
		if votes[n] > best_v:
			best_v = votes[n]
			best = n
	return best


## One blob layer: `layer` is the byte array it reads (substrates or
## surfaces), `value` the id it matches, `connected` a LUT over layer
## values — 1 means "treat as myself" (self, and higher-blend neighbors
## for substrates) — same autotiler either way.
func _build_overlay(
	world: SimWorld,
	sheet: String,
	layer: PackedByteArray,
	value: int,
	id_str: String,
	connected: PackedByteArray,
) -> void:
	var tex: Texture2D = load(sheet)
	var variants := _interior_variants(tex)
	var variant_key := SimRng.key([world.world_seed, "terrain_variant", id_str])

	var cells := PackedInt32Array()
	for cell: int in world.width * world.height:
		if layer[cell] == value:
			var _e: bool = cells.push_back(cell)

	var layer_node := MultiMeshInstance2D.new()
	layer_node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer_node.texture = tex
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = BLOB_SHADER
	layer_node.material = shader_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(TILE_PX, TILE_PX)
	mm.mesh = quad
	mm.instance_count = cells.size()
	layer_node.multimesh = mm
	add_child(layer_node)
	# Same hashed per-tile shade the base pass uses — without it, sheeted
	# terrain renders uniformly bright and reads flatter than the flat
	# colors around it.
	var shade_key := SimRng.key([world.world_seed, "tile_shade"])

	var w := world.width
	var px := float(TILE_PX)
	var interior_cell := Autotile.cell_for(255)
	for i: int in cells.size():
		var cell := cells[i]
		var x := cell % w
		@warning_ignore("integer_division")
		var y := cell / w
		var mask := Autotile.mask_from(
			_same(layer, world, x, y - 1, connected), _same(layer, world, x + 1, y, connected),
			_same(layer, world, x, y + 1, connected), _same(layer, world, x - 1, y, connected),
			_same(layer, world, x + 1, y - 1, connected), _same(layer, world, x + 1, y + 1, connected),
			_same(layer, world, x - 1, y + 1, connected), _same(layer, world, x - 1, y - 1, connected))
		var sheet_cell := Autotile.cell_for(mask)
		if sheet_cell == interior_cell and variants.size() > 1:
			var roll := SimRng.randf(SimRng.combine(variant_key, cell))
			sheet_cell = variants[int(roll * variants.size()) % variants.size()]
		var uv := Autotile.cell_uv(sheet_cell)
		mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2(x + 0.5, y + 0.5) * px))
		mm.set_instance_custom_data(i, Color(uv.x, uv.y, 0.0, 0.0))
		var k := SimRng.combine(SimRng.combine(shade_key, x), y)
		var shade := 0.92 + 0.16 * SimRng.randf(k)
		mm.set_instance_color(i, Color(shade, shade, shade))


## Connectivity check on a terrain layer with clamp-to-edge semantics:
## the map border acts as a continuation, so edge-of-map terrain never
## draws a transition against the void.
static func _same(
	layer: PackedByteArray, world: SimWorld, x: int, y: int, connected: PackedByteArray
) -> bool:
	var cx := clampi(x, 0, world.width - 1)
	var cy := clampi(y, 0, world.height - 1)
	return connected[layer[cy * world.width + cx]] == 1


## Interior pool: the canonical fully-surrounded cell plus every non-empty
## bottom-row variant the artist has drawn (contract: bottom row of the
## 12×5 sheet holds fully-surrounded alternates).
static func _interior_variants(tex: Texture2D) -> PackedInt32Array:
	var variants := PackedInt32Array([Autotile.cell_for(255)])
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var row := Autotile.ROWS - 1
	for col: int in Autotile.COLS:
		var used := false
		for y: int in 16:
			for x: int in 16:
				if img.get_pixel(col * 16 + x, row * 16 + y).a > 0.0:
					used = true
					break
			if used:
				break
		if used:
			var _e: bool = variants.push_back(row * Autotile.COLS + col)
	return variants
