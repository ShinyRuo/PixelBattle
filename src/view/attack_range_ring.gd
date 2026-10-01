class_name PBAttackRangeRing
extends Node2D
## 射程仍由模拟层换算；这里只画屏幕圆，父 Control 将其裁切在战场内。

const FILL := Color(0.55, 0.78, 0.95, 0.06)
const EDGE := Color(0.62, 0.84, 0.98, 0.55)
const SEGMENTS: int = 32

var center: Vector2 = Vector2.ZERO
var radius_px: float = 0.0


func _ready() -> void:
	var clip := get_parent() as Control
	if clip != null and clip.clip_contents:
		clip.position = PBLayout.B_FIELD.position
		clip.size = PBLayout.B_FIELD.size
		position = -clip.position


func sync(at: Vector2, radius: float) -> void:
	if center == at and is_equal_approx(radius_px, radius):
		return
	center = at
	radius_px = maxf(radius, 0.0)
	queue_redraw()


func _draw() -> void:
	if radius_px <= 0.0:
		return
	var ring := PBLayout.ground_disc(center, radius_px, SEGMENTS)
	draw_colored_polygon(ring, FILL)
	draw_polyline(ring, EDGE, 1.0)
