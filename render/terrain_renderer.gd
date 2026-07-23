class_name TerrainRenderer
extends Sprite2D
## Draws the tile grid as one image scaled up with nearest filtering — one
## pixel per tile, no per-tile nodes. Placeholder colors until real art;
## per-tile shade variation (hashed, deterministic) keeps it from reading as
## flat color fields.

const TILE_PX := 16

# Palette indices by tile id (SimWorld.TILE_*): murky teal water, tan sand,
# olive grass, grey-purple rock.
static var COLORS := PackedColorArray([
	Palette.COLORS[39],
	Palette.COLORS[4],
	Palette.COLORS[25],
	Palette.COLORS[2],
])


func build(world: SimWorld) -> void:
	centered = false
	scale = Vector2(TILE_PX, TILE_PX)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade_key := SimRng.key([world.world_seed, "tile_shade"])
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	for y: int in world.height:
		for x: int in world.width:
			var c := COLORS[world.tile_at(x, y)]
			var k := SimRng.combine(SimRng.combine(shade_key, x), y)
			var shade := 0.92 + 0.16 * SimRng.randf(k)
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	texture = ImageTexture.create_from_image(img)
