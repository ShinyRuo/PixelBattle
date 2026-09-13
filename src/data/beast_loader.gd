class_name PBBeastLoader
extends RefCounted
## 把 `data/beasts/*.tres` 装成一张 [PBBeastTable]。与 [PBCharacterLoader] 同构。
## 排序影响的是显示顺序（尾兽不参与随机流）：文件名带序号，排出来正好是一尾到九尾。

const DIR := "res://data/beasts"

## §11 明写的尾兽只数。**九只缺一只都不行**：§11 点名七尾（纯聚拢）和
## 六尾（重置全体大招 CD）是机制型，「不能被数值型挤掉」——
## 而少了任何一只，那条横向比较就少了一个对照点。
const SPEC_BEASTS: int = 9

static var _cached: PBBeastTable = null


## 全部尾兽。第一次调用读盘，之后走缓存。
static func table() -> PBBeastTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把真尾兽表装进一份配置。返回同一个 [param cfg]，方便串写。
##
## 忘了调的后果和前三张表不同：不是「静默退回一条替身曲线」，
## 而是**表里一只都没有，于是 `--beast` 指定哪只都当作没带**
## （见 [method PBStrategy.choose_beast]）。跑出来是对照组的数字，
## 明显偏低，一眼看得出不对 —— 这是刻意选的失败形态。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.beasts = table()
	return cfg


## 从指定目录装一张表。目录读不到或有坏数据时会报错并跳过那一份。
static func load_from(dir_path: String) -> PBBeastTable:
	var table_out := PBBeastTable.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("尾兽目录打不开：%s" % dir_path)
		return table_out

	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var beast := load(path) as PBBeast
		if beast == null:
			push_error("这份尾兽数据装不进来（不是 PBBeast？）：%s" % path)
			continue
		var bad := _unknown_aura_keys(beast)
		if not bad.is_empty():
			# **不认识的光环键直接拒收，不静默跳过**：静默的表现是表装得进来、玩家照样花钱升级，
			# 只有光环什么都不发生。认不认得只问 [method PBModRules.is_known]。
			push_error("这只尾兽的光环里有认不得的键 %s：%s" % [bad, path])
			continue
		if not table_out.add(beast):
			push_error("这份尾兽数据被拒收（id 空/重复，或减速倍率越界）：%s" % path)
	return table_out


## 这只尾兽的 [member PBBeast.aura_passives] 里有哪些键是词汇表不认得的。
##
## **认不认得只有一处**（[method PBPassiveRules.is_known]）——
## 在这里另抄一份名单的话，「这个键认不认」迟早和规则层分叉，
## 而分叉的那一侧静默生效。
static func _unknown_aura_keys(beast: PBBeast) -> Array[StringName]:
	var bad: Array[StringName] = []
	for key: StringName in beast.aura_passives:
		if not PBModRules.is_known(key):
			bad.append(key)
	return bad
