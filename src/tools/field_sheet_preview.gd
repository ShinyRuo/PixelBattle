@tool
class_name PBFieldSheetPreview
extends Control

var texture: Texture2D
var cells: Array[Rect2i] = []


func show_sheet(source: Image, regions: Array[Rect2i]) -> void:
	texture = ImageTexture.create_from_image(source) if source != null else null
	cells = regions.duplicate()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.16, 0.20))
	if texture == null:
		return
	var fit := minf(size.x / texture.get_width(), size.y / texture.get_height())
	var box := Rect2((size - texture.get_size() * fit) * 0.5, texture.get_size() * fit)
	draw_texture_rect(texture, box, false)
	for i: int in cells.size():
		var cell := Rect2(
			box.position + Vector2(cells[i].position) * fit, Vector2(cells[i].size) * fit
		)
		draw_rect(cell, Color(0.1, 0.7, 1), false, 1)
		draw_string(
			ThemeDB.fallback_font,
			cell.position + Vector2(5, 18),
			str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(0.1, 0.6, 1)
		)
