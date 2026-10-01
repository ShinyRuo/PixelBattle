class_name PBActorLibrary
extends RefCounted
## 把 `data/actors/*.tres` 装成一张「键 → [PBActorSkin]」的表。
##
## 读盘只能在 core 外面（铁律 1）。角色数值走 [PBCharacterLoader]、形象走这里，两张表用
## [member PBCharacter.actor_key] 对上，谁都不知道对方存在 —— 批量模拟一张图都不加载照样跑。
##
## **目录不存在不是错**：素材大部分不进版本控制，打不开的正确行为是退回白模（[PBWhiteModel]）。
##
## **战斗画面按键一份一份读**（[method skin_for]），不一次读全目录：几十套形象、几十兆贴图一起读，
## 开局第一次点选忍者会卡住好几秒（编辑器里十几秒）。所以**文件名必须和键一致**
## （`data/actors/<键>.tres`），`tests/test_actor_data.gd` 钉着。整目录读只留给预览台和测试（[method skins]）。

const DIR := "res://data/actors"

static var _cached: Dictionary = {}
static var _loaded: bool = false

## 按键单独查过、盘上没有的键。记下来免得每帧去问一次磁盘（白模角色每帧都在查）。
static var _missing: Dictionary = {}


## 全部形象。第一次调用读整个目录，之后走缓存。**战斗画面别用它**，见类注释。
static func skins() -> Dictionary:
	if not _loaded:
		_cached = load_from(DIR)
		_loaded = true
	return _cached


## 查一张皮，没有就 `null`（调用方退回白模）。**只读 `<键>.tres` 这一份**，读过的缓存起来。
static func skin_for(actor_key: StringName) -> PBActorSkin:
	if actor_key == &"":
		return null
	if _cached.has(actor_key):
		return _cached[actor_key] as PBActorSkin
	if _loaded or _missing.has(actor_key):
		return null
	var path: String = "%s/%s.tres" % [DIR, actor_key]
	var skin: PBActorSkin = _load_one(path, PBSimConfig.new().anim_frames)
	if skin != null and skin.key != &"" and skin.key != actor_key:
		push_error("形象的文件名和键对不上（按键找不到它）：%s 里的键是 %s" % [path, skin.key])
		skin = null
	if skin == null:
		_missing[actor_key] = true
		return null
	_cached[actor_key] = skin
	return skin


## 重新读盘。改完 `.tres` 想立刻看效果时用，测试里也用它换一张假表。
static func reload() -> void:
	_loaded = false
	_cached = {}
	_missing = {}


## 从指定目录装一张表。**键取 [member PBActorSkin.key]，空的就用文件名** ——
## 忘了填那一格的表现该是「按文件名也能查到」，不是这份素材静默失踪。
static func load_from(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var names := ResourceLoader.list_directory(dir_path)
	if names.is_empty():
		return out
	names.sort()
	# **攻击段一律补到 6 帧**（见 [method PBActorSkin.hold_last_to]）：「第 4 帧出手」只有在每段帧数相同时
	# 才是同一句话。载入时补，不必重导盘上的素材。
	var want: int = PBSimConfig.new().anim_frames
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var skin := _load_one("%s/%s" % [dir_path, file_name], want)
		if skin == null:
			continue
		var key: StringName = skin.key
		if key == &"":
			key = StringName(file_name.get_basename())
		out[key] = skin
	return out


## 读一份形象并补齐攻击段。盘上没有返回 null（不报错）；有但不是 [PBActorSkin] 才报错。
static func _load_one(path: String, want: int) -> PBActorSkin:
	if not ResourceLoader.exists(path):
		return null
	var skin := load(path) as PBActorSkin
	if skin == null:
		push_error("这份形象数据装不进来（不是 PBActorSkin？）：%s" % path)
		return null
	skin.hold_last_to(skin.anim_attack, want)
	return skin
