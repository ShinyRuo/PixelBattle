@tool
class_name PBFormArt
extends Resource
## 持续效果 ID → 独立战场形象；只影响渲染，数值仍由效果袋决定。

static var _cache: Dictionary = {}

@export var actor_key: StringName = &""


static func for_buff(id: StringName) -> PBFormArt:
	if not _cache.has(id):
		var art := PBFormArt.new()
		var path := "res://data/form_art/%s.tres" % id
		if id != &"" and ResourceLoader.exists(path):
			var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBFormArt
			if saved != null:
				art = saved
		_cache[id] = art
	return _cache[id]


static func clear_cache() -> void:
	_cache.clear()
