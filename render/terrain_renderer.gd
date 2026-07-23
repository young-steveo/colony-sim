class_name TerrainRenderer
extends Sprite2D
## Draws the tile grid as one image scaled up with nearest filtering — one
## pixel per tile, no per-tile nodes. Placeholder colors until real art;
## per-tile shade variation (hashed, deterministic) keeps it from reading as
## flat color fields.

const TILE_PX := 16

const COLORS := {
	SimWorld.TILE_WATER: Color8(52, 84, 110),
	SimWorld.TILE_SAND: Color8(178, 159, 112),
	SimWorld.TILE_GRASS: Color8(106, 122, 74),
	SimWorld.TILE_ROCK: Color8(112, 106, 98),
}


func build(world: SimWorld) -> void:
	centered = false
	scale = Vector2(TILE_PX, TILE_PX)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade_key := SimRng.key([world.world_seed, "tile_shade"])
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	for y in world.height:
		for x in world.width:
			var c: Color = COLORS[world.tile_at(x, y)]
			var k := SimRng.combine(SimRng.combine(shade_key, x), y)
			var shade := 0.92 + 0.16 * SimRng.randf(k)
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	texture = ImageTexture.create_from_image(img)
