class_name PBEquipLoader
extends RefCounted
## 把 `data/equipment/*.tres` 装成一张 [PBEquipTable]。M3-c2。
##
## 和 [PBCharacterLoader] / [PBBondLoader] 同构，两条理由也一样：
##
## - `ResourceLoader` 被 core 纯度检查明令挡住（§14）。core 只认
##   [PBEquipTable] 这个类型，不知道装备数据从哪来。
## - 报错只能在这一层做 —— 只有这里手上有 `.tres` 的路径，
##   能指出是**哪一份数据**写错了。
##
## ## 配件表是从配方推出来的，不单独存
##
## §10 的 7 种配件本身没有任何属性 —— 它们只是配方里的名字。
## 单独给它们建 7 个 `.tres`，就等于把「哪些配件存在」这件事存了两份：
## 一份在配件文件里，一份在配方里。**两份迟早对不上**，
## 而对不上的表现是「忍具箱开出一种谁也用不到的配件」，不报任何错。
##
## 所以配件表 = 全部配方里出现过的配件的并集。
## 显示名走语言表（`equip_part.*`），和角色、羁绊一样。

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
##
## 忘了调就会静默退回 [method PBEquipTable.synthetic] 那张合成表 ——
## 那是 M-1 的替身曲线（任意 N 个配件换一件、对谁都生效），
## 跑出来的数值比真树乐观得多，而且不报错。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.equipment = table()
	return cfg


## 从指定目录装一张表。目录读不到或有坏数据时会报错并跳过那一份。
static func load_from(dir_path: String) -> PBEquipTable:
	var items: Array[PBEquipItem] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("装备目录打不开：%s" % dir_path)
		return PBEquipTable.of([], items)

	var names := dir.get_files()
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


## 忍具箱会出哪些配件：**只数还有用的那些配方**，去重后按名字排序。
##
## ## 为什么要跳过 0 收益的配方
##
## §10 的六件成品里有两件在当前战斗模型下价值恒为 0（防御向，
## 而敌人不还手、己方单位也不会死，见 [member PBEquipItem.power]）。
## 它们的专属配件因此是纯废品 —— 而忍具箱是**等概率**出货的，
## 于是每开三箱就有一箱直接扔掉。
##
## 实测这条损耗足以把整个金币坑压垮：真树刚接上时，一个会算账的玩家
## 整局买 **0 个**配件，正是 §10 当初否掉原价 1350 时的那个失败形态。
##
## **规则因此是「箱子不卖你用不上的东西」**：一件成品的效果在模型里不存在，
## 它的专属配件也就不在货架上。这条是**自愈的** —— 等 [PBBattleSim]
## 有了「敌人还手」，那两件的 `power` 一变正，配件自动回到池子里，
## 不需要有人记得回来改这里。
##
## 同时喂给活配方和死配方的配件不受影响，照常出货。
##
## 排序让出货下标稳定：那一掷走 `gacha` 流，
## 顺序一变同一个种子就抽出不同的配件，整局结果跟着变。
static func _parts_of(items: Array[PBEquipItem]) -> Array[StringName]:
	var seen: Dictionary = {}
	for item: PBEquipItem in items:
		# **判据是「它给不给东西」，不是估值分**（M12-h2）。
		# 看 `power` 的那一版把吸血与格挡两件的配件下架了九个里程碑 ——
		# 理由是「敌人不还手」，而那句话从 M3.5-b 起就不成立了。
		if item.mods.is_empty():
			continue
		for part_id: StringName in item.recipe:
			seen[part_id] = true
	var out: Array[StringName] = []
	for part_id: StringName in seen:
		out.append(part_id)
	out.sort()
	return out
