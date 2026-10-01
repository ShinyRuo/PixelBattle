class_name PBMapBackground
extends TextureRect
## 八张战场图按局轮换；下一张的编号保存在 user://，网页刷新后也能接着轮换。

const SAVE_PATH := "user://map_rotation.cfg"
const MAPS := [
	preload("res://assets/maps/leaf_training.jpg"),
	preload("res://assets/maps/death_forest.jpg"),
	preload("res://assets/maps/sand_village.jpg"),
	preload("res://assets/maps/rain_city.jpg"),
	preload("res://assets/maps/mist_shore.jpg"),
	preload("res://assets/maps/snow_bridge.jpg"),
	preload("res://assets/maps/stone_canyon.jpg"),
	preload("res://assets/maps/ancient_valley.jpg"),
]

static var _next_index: int = -1


func advance() -> void:
	if _next_index < 0:
		var saved := ConfigFile.new()
		_next_index = 0
		if saved.load(SAVE_PATH) == OK:
			_next_index = posmod(int(saved.get_value("map", "next", 0)), MAPS.size())
	show_map(_next_index)
	_next_index = following(_next_index)
	var updated := ConfigFile.new()
	updated.set_value("map", "next", _next_index)
	if updated.save(SAVE_PATH) != OK:
		push_warning("Map rotation could not be saved for the next session")


func show_map(index: int) -> void:
	texture = MAPS[posmod(index, MAPS.size())]
	position = PBLayout.B_FIELD.position - PBLayout.B_LANE_INSET
	size = PBLayout.B_FIELD.size + PBLayout.B_LANE_INSET * 2.0


static func following(index: int) -> int:
	return posmod(index + 1, MAPS.size())
