@tool
class_name PBBuffGlowLayer
extends Node2D
## 同一前/后层内的一种混合通道，预分配后只更新绘制内容。

var front: bool = false
var _drawings: Array[Dictionary] = []


func _init(additive: bool = false) -> void:
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = (
		CanvasItemMaterial.BLEND_MODE_ADD if additive else CanvasItemMaterial.BLEND_MODE_MIX
	)
	material = blend
	visible = false


func sync_drawings(items: Array[Dictionary], is_front: bool) -> void:
	front = is_front
	_drawings = items
	visible = not items.is_empty()
	# 预览中同一资源可原地修改锚点、缩放或混合方式，不能仅凭引用相等跳过重绘。
	queue_redraw()


func _draw() -> void:
	for item: Dictionary in _drawings:
		var skin: PBBuffSkin = item.skin
		var frames := skin.front_frames if front else skin.back_frames
		if not frames.is_empty():
			var texture: Texture2D = frames[item.frame]
			var at := skin.offset - skin.anchor * skin.pixel_scale
			draw_texture_rect(
				texture, Rect2(at, texture.get_size() * skin.pixel_scale), false, skin.tint
			)
		elif skin.placeholder:
			_draw_placeholder(skin.tint, item.frame)


func _draw_placeholder(color: Color, frame: int) -> void:
	color.a *= 0.55 if front else 0.3
	for i: int in 4:
		var x: float = [-14.0, -10.0, 10.0, 14.0][i]
		var y := -8.0 - float((frame + i * 3) % 12) * 3.0
		draw_line(Vector2(x, y), Vector2(x * 0.9, y - 11.0), color, 2.0)
