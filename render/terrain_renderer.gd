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
## Tile stack: a cell's VISIBLE identity is its surface when it has one
## (grass fully covers its dirt while surfaces are flat placeholders),
## else its substrate. Autotiling and neighbor-reveal both run on visible
## identity, so bare dirt scallops against grass fields. When the first
## surface SHEET lands (grass art), surfaces become a second overlay pass
## and substrate connectivity switches to substrate-only — the grass
## fringe will reveal dirt art through its own transitions instead.

const TILE_PX := 16
const BLOB_SHADER := preload("res://render/autotile_blob.gdshader")
# Visible-id space: substrates use their byte; surfaced cells map above
# this base so the two can never collide.
const SURFACE_ID_BASE := 256

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
		if defs.sheets[mat] != "":
			_build_overlay(world, defs, mat)


func _build_base(world: SimWorld, defs: TerrainDefs) -> void:
	var base := Sprite2D.new()
	base.centered = false
	base.scale = Vector2(TILE_PX, TILE_PX)
	base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade_key := SimRng.key([world.world_seed, "tile_shade"])
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	for y: int in world.height:
		for x: int in world.width:
			var vid := _visible_id(world, x, y)
			var sheeted := vid < SURFACE_ID_BASE and defs.sheets[vid] != ""
			if sheeted:
				vid = _reveal_id(world, x, y, vid)
			var c := _visible_color(defs, vid)
			var k := SimRng.combine(SimRng.combine(shade_key, x), y)
			var shade := 0.92 + 0.16 * SimRng.randf(k)
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	base.texture = ImageTexture.create_from_image(img)
	add_child(base)


static func _visible_id(world: SimWorld, x: int, y: int) -> int:
	var cell := clampi(y, 0, world.height - 1) * world.width + clampi(x, 0, world.width - 1)
	var s := world.surfaces[cell]
	return SURFACE_ID_BASE + s if s != SimWorld.SURF_NONE else world.tiles[cell]


static func _visible_color(defs: TerrainDefs, vid: int) -> Color:
	if vid >= SURFACE_ID_BASE:
		return defs.surface_colors[vid - SURFACE_ID_BASE]
	return defs.colors[vid]


## What shows through a sheeted cell's transition notches: the first
## visibly different neighbor in scan order, or the cell's own identity
## when fully interior (covered by the overlay anyway).
func _reveal_id(world: SimWorld, x: int, y: int, vid: int) -> int:
	for offset: Vector2i in NEIGHBOR_ORDER:
		var n := _visible_id(world, x + offset.x, y + offset.y)
		if n != vid:
			return n
	return vid


func _build_overlay(world: SimWorld, defs: TerrainDefs, mat: int) -> void:
	var tex: Texture2D = load(defs.sheets[mat])
	var variants := _interior_variants(tex)
	var variant_key := SimRng.key([world.world_seed, "terrain_variant", defs.ids[mat]])

	var cells := PackedInt32Array()
	for cell: int in world.width * world.height:
		if world.tiles[cell] == mat and world.surfaces[cell] == SimWorld.SURF_NONE:
			var _e: bool = cells.push_back(cell)

	var layer := MultiMeshInstance2D.new()
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.texture = tex
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = BLOB_SHADER
	layer.material = shader_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(TILE_PX, TILE_PX)
	mm.mesh = quad
	mm.instance_count = cells.size()
	layer.multimesh = mm
	add_child(layer)
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
			_same(world, x, y - 1, mat), _same(world, x + 1, y, mat),
			_same(world, x, y + 1, mat), _same(world, x - 1, y, mat),
			_same(world, x + 1, y - 1, mat), _same(world, x + 1, y + 1, mat),
			_same(world, x - 1, y + 1, mat), _same(world, x - 1, y - 1, mat))
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


## Same-visible-identity check with clamp-to-edge semantics: the map
## border acts as a continuation, so edge-of-map terrain never draws a
## transition against the void.
static func _same(world: SimWorld, x: int, y: int, mat: int) -> bool:
	return _visible_id(world, x, y) == mat


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
