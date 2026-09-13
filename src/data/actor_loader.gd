class_name PBActorLibrary
extends RefCounted
## 把 `data/actors/*.tres` 装成一张「键 → [PBActorSkin]」的表。
##
## 读盘只能在 core 外面（铁律 1）。角色数值走 [PBCharacterLoader]、形象走这里，两张表用
## [member PBCharacter.actor_key] 对上，谁都不知道对方存在 —— 批量模拟一张图都不加载照样跑。
##
## **目录不存在不是错**：素材大部分不进版本控制，打不开的正确行为是退回白模（[PBWhiteModel]）。

const DIR := "res://data/actors"

static var _cached: Dictionary = {}
static var _loaded: bool = false


## 全部形象。第一次调用读盘，之后走缓存。
static func skins() -> Dictionary:
	if not _loaded:
		_cached = load_from(DIR)
		_loaded = true
	return _cached


## 查一张皮，没有就 `null`（调用方退回白模）。
static func skin_for(actor_key: StringName) -> PBActorSkin:
	if actor_key == &"":
		return null
	return skins().get(actor_key, null) as PBActorSkin


## 重新读盘。改完 `.tres` 想立刻看效果时用，测试里也用它换一张假表。
static func reload() -> void:
	_loaded = false
	_cached = {}


## 从指定目录装一张表。**键取 [member PBActorSkin.key]，空的就用文件名** ——
## 忘了填那一格的表现该是「按文件名也能查到」，不是这份素材静默失踪。
static func load_from(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	# **攻击段一律补到 6 帧**（见 [method PBActorSkin.hold_last_to]）：「第 4 帧出手」只有在每段帧数相同时
	# 才是同一句话。载入时补，不必重导盘上的素材。
	var want: int = PBSimConfig.new().anim_frames
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var skin := load(path) as PBActorSkin
		if skin == null:
			push_error("这份形象数据装不进来（不是 PBActorSkin？）：%s" % path)
			continue
		var key: StringName = skin.key
		if key == &"":
			key = StringName(file_name.get_basename())
		skin.hold_last_to(skin.anim_attack, want)
		out[key] = skin
	return out
