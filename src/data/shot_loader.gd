class_name PBShotLibrary
extends RefCounted
## 把 `data/shots/*.tres` 装成一张「键 → [PBShotSkin]」的表。M8-a。
##
## 和 [PBActorLibrary] 逐条同构，理由也一样：`ResourceLoader` 被 core 纯度检查
## 明令挡住（§14），所以「读盘」这件事只能发生在 core 外面。
##
## ## 目录不存在不是错
##
## `assets/` 里一张子弹图都没有，所以 `data/shots/` 长期是空的。
## 打不开时正确的行为是退回 [method PBWhiteModel.shot]，不是每帧刷一条错 ——
## 同 [PBActorLibrary] 顶上那条「**空 = 白模**」。

const DIR := "res://data/shots"

static var _cached: Dictionary = {}
static var _loaded: bool = false


## 全部子弹。第一次调用读盘，之后走缓存。
static func skins() -> Dictionary:
	if not _loaded:
		_cached = load_from(DIR)
		_loaded = true
	return _cached


## 查一份，没有就 `null`（调用方退回白模）。
static func skin_for(shot_key: StringName) -> PBShotSkin:
	if shot_key == &"":
		return null
	return skins().get(shot_key, null) as PBShotSkin


## 重新读盘。改完 `.tres` 想立刻看效果时用，测试里也用它换一张假表。
static func reload() -> void:
	_loaded = false
	_cached = {}


## 从指定目录装一张表。**键取 [member PBShotSkin.key]，空的就用文件名** ——
## 忘了填那一格的表现该是「按文件名也查得到」，不是这份素材静默失踪。
static func load_from(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var skin := load(path) as PBShotSkin
		if skin == null:
			push_error("这份子弹数据装不进来（不是 PBShotSkin？）：%s" % path)
			continue
		var key: StringName = skin.key
		if key == &"":
			key = StringName(file_name.get_basename())
		out[key] = skin
	return out
