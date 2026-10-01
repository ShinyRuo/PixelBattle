@tool
class_name PBSummonArt
extends Resource
## 按召唤技能绑定形象和普攻子弹；独立于数值生成表。

static var _cache: Dictionary = {}

@export var actor_key: StringName = &""
@export var shot_key: StringName = &""
@export var spawn_fx_key: StringName = &""


static func for_skill(id: StringName) -> PBSummonArt:
	if not _cache.has(id):
		var art := PBSummonArt.new()
		var path := "res://data/summon_art/%s.tres" % id
		if id != &"" and ResourceLoader.exists(path):
			var saved := (
				ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBSummonArt
			)
			if saved != null:
				art = saved
		_cache[id] = art
	return _cache[id]


static func clear_cache() -> void:
	_cache.clear()
