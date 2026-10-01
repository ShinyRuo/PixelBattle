class_name PBBaseMotion
extends Node2D
## 基地石像和大楼保持静止；两面布旗摆动，飞鸟沿上缘缓慢掠过。

const FLAG_RED := Color(0.80, 0.33, 0.23, 0.94)
const FLAG_SHADE := Color(0.48, 0.18, 0.18, 0.92)
const BIRD := Color(0.89, 0.88, 0.80, 0.92)

var _time: float = 0.0


func _process(delta: float) -> void:
	_time = fposmod(_time + delta, 20.0)
	queue_redraw()


func _draw() -> void:
	_draw_flag(Vector2(13.0, 30.0), 0.0)
	_draw_flag(Vector2(51.0, 31.0), 1.6)
	for i: int in 2:
		var x: float = fposmod(_time * (6.0 + float(i)) + float(i) * 29.0, 75.0) - 6.0
		var y: float = 3.0 + float(i) * 5.0 + sin(_time * 2.3 + float(i)) * 1.5
		var wing: float = sin(_time * 7.0 + float(i) * 2.0) * 1.3
		draw_polyline(
			PackedVector2Array([Vector2(x - 2.4, y - wing), Vector2(x, y + 0.6),
				Vector2(x + 2.4, y - wing)]), BIRD, 1.0
		)


func _draw_flag(pole: Vector2, phase: float) -> void:
	draw_line(pole + Vector2(0.0, 8.0), pole, Color(0.39, 0.34, 0.30), 1.0)
	var wave: float = sin(_time * 5.0 + phase) * 1.6
	var tip := pole + Vector2(7.0 + wave, 1.5)
	draw_colored_polygon(PackedVector2Array([
		pole, pole + Vector2(4.0, 1.0 + wave * 0.3), tip,
		pole + Vector2(5.0 + wave * 0.5, 4.5), pole + Vector2(0.0, 4.0),
	]), FLAG_RED)
	draw_line(pole + Vector2(4.0, 1.0 + wave * 0.3),
		pole + Vector2(5.0 + wave * 0.5, 4.5), FLAG_SHADE, 0.8)
