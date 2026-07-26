class_name TreeRenderer
extends Node2D
## Placeholder trees: trunk + canopy quads per tree, one MultiMesh each.
## Real 16x32 tree sprites (with Y-sorting/canopy occlusion) are queued
## art; this is debug-grade so the material cycle is playable now.
## A designated tree's canopy warms toward the marked-for-felling color
## so chop plans read at a glance.

const TRUNK_SIZE := Vector2(4.0, 7.0)
const CANOPY_SIZE := Vector2(13.0, 13.0)
static var _TRUNK := Palette.COLORS[19]  # 7a3045
static var _CANOPY := Palette.COLORS[30]  # 239063
static var _MARKED := Palette.COLORS[18]  # f9c22b

var _trunks := MultiMeshInstance2D.new()
var _canopies := MultiMeshInstance2D.new()
var _width := 0
var _version_seen := 0


func setup(world: SimWorld) -> void:
	_width = world.width
	_add_layer(_trunks, TRUNK_SIZE)
	_add_layer(_canopies, CANOPY_SIZE)


func sync(trees: Trees) -> void:
	if trees.version == _version_seen:
		return
	_version_seen = trees.version
	var n := trees.cells.size()
	_trunks.multimesh.instance_count = n
	_canopies.multimesh.instance_count = n
	var px := float(TerrainRenderer.TILE_PX)
	for i: int in n:
		var cell := trees.cells[i]
		var cx := float(cell % _width) * px + px * 0.5
		@warning_ignore("integer_division")
		var cy := float(cell / _width) * px
		# Feet on the tile, canopy overhanging the tile above: trees must
		# read TALLER than bushes or the forest is just dark confetti.
		_trunks.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2(cx, cy + 12.0)))
		_canopies.multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2(cx, cy - 2.0)))
		_trunks.multimesh.set_instance_color(i, _TRUNK)
		var marked := trees.is_designated(cell)
		_canopies.multimesh.set_instance_color(i, _CANOPY.lerp(_MARKED, 0.55) if marked else _CANOPY)


func _add_layer(layer: MultiMeshInstance2D, size: Vector2) -> void:
	layer.multimesh = MultiMesh.new()
	layer.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	layer.multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = size
	layer.multimesh.mesh = quad
	add_child(layer)
