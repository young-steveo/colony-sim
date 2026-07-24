class_name FieldDebugRenderer
extends Sprite2D
## Debug heatmap for a flow field: near-goal cells cool teal, far cells warm
## pink, goal cell white, unreachable/unwalkable transparent. Toggled from
## main; never shown in normal play.

const RANGE_TILES := 120.0

static var _NEAR := Palette.COLORS[42]
static var _FAR := Palette.COLORS[60]


func build(world: SimWorld, field: FlowField) -> void:
	centered = false
	scale = Vector2(TerrainRenderer.TILE_PX, TerrainRenderer.TILE_PX)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var img := Image.create(world.width, world.height, false, Image.FORMAT_RGBA8)
	for y: int in world.height:
		for x: int in world.width:
			var dist := field.distances[y * world.width + x]
			if dist == FlowField.UNREACHABLE:
				continue
			if dist == 0:
				img.set_pixel(x, y, Color.WHITE)
				continue
			var t := clampf(float(dist) / (FlowField.COST_ORTH * RANGE_TILES), 0.0, 1.0)
			var c := _NEAR.lerp(_FAR, t)
			c.a = 0.5
			img.set_pixel(x, y, c)
	texture = ImageTexture.create_from_image(img)
