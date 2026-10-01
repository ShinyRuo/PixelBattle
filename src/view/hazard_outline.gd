class_name PBHazardOutline
extends RefCounted
## 只画光环并集的外边，不叠画内部交叉圈。几何只在区域复用或布局变化时重算。

const SEGMENTS: int = 96
var strokes := PackedVector2Array()
var _source: PBHazardZone
var _generation: int = -1
var _field := Vector2.ZERO


func sync(zone: PBHazardZone, field: Vector2) -> void:
	if zone == null:
		_source = null
		_generation = -1
		strokes.clear()
		return
	if _source == zone and _generation == zone.generation and _field == field:
		return
	_source = zone
	_generation = zone.generation
	_field = field
	strokes.clear()
	var radius: float = zone.cast.skill.zone_radius
	for index: int in zone.points.size():
		var origin: Vector2 = zone.points[index]
		for part: int in SEGMENTS:
			var angle: float = TAU * (part + 0.5) / SEGMENTS
			var middle := origin + Vector2(cos(angle), sin(angle)) * radius
			if _inside_other(middle, zone.points, index, radius):
				continue
			for edge: int in 2:
				var edge_angle: float = TAU * (part + edge) / SEGMENTS
				var point := origin + Vector2(cos(edge_angle), sin(edge_angle)) * radius
				strokes.append(PBLayout.to_screen(point, field))


static func _inside_other(
	point: Vector2, origins: PackedVector2Array, own: int, radius: float
) -> bool:
	for index: int in origins.size():
		if index != own and point.distance_to(origins[index]) < radius - 0.0000001:
			return true
	return false
