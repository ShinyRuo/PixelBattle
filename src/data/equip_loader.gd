class_name PBEquipLoader
extends RefCounted
## 把 `data/equipment/*.tres` 装成一张 [PBEquipTable]。与 [PBCharacterLoader] 同构。
##
## **配件表是从配方推出来的，不单独存**：配件本身没有属性，单独建文件的话「哪些配件存在」存了两份，
## 对不上的表现是忍具箱开出一种谁也用不到的配件。配件表 = 全部配方里出现过的配件的并集，显示名走 `equip_part.*`。

const DIR := "res://data/equipment"

## §10 明写的配件种类数。整份数据里应该出现这么多种。
const SPEC_PARTS: int = 7

## 忍具箱**当前**会出几种配件。**等概率出货，所以这个数直接决定出货率**，
## 值得一条断言盯着：它悄悄变大就是有废配件混进了货架，
## 悄悄变小就是某件成品被误标成了 0 收益。
##
## 它比 [constant SPEC_PARTS] 小，差额正是那两件防御向成品的专属配件 ——
## 见 [method _parts_of]。**敌人还手做出来之后这两个数会重新相等。**
const LIVE_PARTS: int = 4

static var _cached: PBEquipTable = null


## 全部装备。第一次调用读盘，之后走缓存。
static func table() -> PBEquipTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把真装备表装进一份配置。返回同一个 [param cfg]，方便串写。
## 忘了调会静默退回合成表（任意 N 个配件换一件、对谁都生效），数值比真树乐观得多。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.equipment = table()
	return cfg


## 从指定目录装一张表。目录读不到或有坏数据时会报错并跳过那一份。
static func load_from(dir_path: String) -> PBEquipTable:
	var items: Array[PBEquipItem] = []
	var names := ResourceLoader.list_directory(dir_path)
	if names.is_empty():
		push_error("装备目录打不开：%s" % dir_path)
		return PBEquipTable.of([], items)
	# 排序纯粹是为了让报错与调试输出稳定。合成与分配都按加成排，与文件顺序无关。
	names.sort()
	var seen: Dictionary = {}
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var item := load(path) as PBEquipItem
		if item == null:
			push_error("这份装备数据装不进来（不是 PBEquipItem？）：%s" % path)
			continue
		if item.id == &"" or seen.has(item.id):
			push_error("这份装备数据被拒收（id 空或重复）：%s" % path)
			continue
		if item.recipe.is_empty():
			push_error("这份装备数据被拒收（配方是空的，永远合不出来）：%s" % path)
			continue
		seen[item.id] = true
		items.append(item)

	return PBEquipTable.of(_parts_of(items), items)


## 忍具箱会出哪些配件：**只数给东西的那些配方**，去重后按名字排序。
##
## **箱子不卖你用不上的东西**：忍具箱等概率出货，一件什么都不给的成品的专属配件是纯废品，会把金币坑压垮。
## 同时喂给有用和没用配方的配件照常出货。排序让出货下标稳定（那一掷走 `gacha` 流）。
static func _parts_of(items: Array[PBEquipItem]) -> Array[StringName]:
	var seen: Dictionary = {}
	for item: PBEquipItem in items:
		# **判据是「它给不给东西」（mods），不是估值分** —— 看估值分的话，一件估值写错的成品会让它的配件静默下架。
		if item.mods.is_empty():
			continue
		for part_id: StringName in item.recipe:
			seen[part_id] = true
	var out: Array[StringName] = []
	for part_id: StringName in seen:
		out.append(part_id)
	out.sort()
	return out
