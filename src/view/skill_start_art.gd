@tool
class_name PBSkillStartArt
extends Resource
## 技能独立美术配置：命名起手光与飞行可见性，不改变结算。

static var _hidden: Dictionary = {}

@export var hide_flight: bool = false
@export var start_key: StringName = &""


static func flight_hidden(id: StringName) -> bool:
	if not _hidden.has(id):
		var path := "res://data/skill_art/%s.tres" % id
		var art: PBSkillStartArt = null
		if ResourceLoader.exists(path):
			art = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBSkillStartArt
		_hidden[id] = art != null and art.hide_flight
	return bool(_hidden[id])
