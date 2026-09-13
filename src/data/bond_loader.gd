class_name PBBondLoader
extends RefCounted
## 把 `data/bonds/*.tres` 装成一张 [PBBondTable]。与 [PBCharacterLoader] 同构：
## `ResourceLoader` 被 core 纯度检查挡住；报错只能在这一层做（只有这里手上有 `.tres` 路径）。
## 按文件名排序只为让报错与调试输出稳定（羁绊各组相加，与次序无关）。

const DIR := "res://data/bonds"

static var _cached: PBBondTable = null


## 全部羁绊。第一次调用读盘，之后走缓存。
static func table() -> PBBondTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把真羁绊表装进一份配置。返回同一个 [param cfg]，方便串写。
## 忘了调会静默退回合成表，数值和真游戏对不上且不报错。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.bonds = table()
	return cfg


## 从指定目录装一张表。目录读不到或有坏数据时会报错并跳过那一份。
static func load_from(dir_path: String) -> PBBondTable:
	var table_out := PBBondTable.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("羁绊目录打不开：%s" % dir_path)
		return table_out

	var names := dir.get_files()
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var bond := load(path) as PBBond
		if bond == null:
			push_error("这份羁绊数据装不进来（不是 PBBond？）：%s" % path)
			continue
		if not table_out.add(bond):
			push_error("这份羁绊数据被拒收（id 空/重复，或档位表不合法）：%s" % path)
	return table_out
