class_name PBBondLoader
extends RefCounted
## 把 `data/bonds/*.tres` 装成一张 [PBBondTable]。M2-b2。
##
## 和 [PBCharacterLoader] 同构，两条理由也一样：
##
## - `ResourceLoader` 被 core 纯度检查明令挡住（§14）。core 只认
##   [PBBondTable] 这个类型，不知道羁绊数据从哪来。
## - 报错只能在这一层做 —— 只有这里手上有 `.tres` 的路径，
##   能指出是**哪一份数据**写错了。
##
## ## 这里的排序不影响确定性，但还是排
##
## 羁绊表不参与任何随机流，顺序变了加成也一样（各组相加，与次序无关）。
## 排序纯粹是为了让报错信息和调试输出稳定 —— 同一份数据两次运行
## 打出来的顺序不一样，对比日志时会很烦。

const DIR := "res://data/bonds"

static var _cached: PBBondTable = null


## 全部羁绊。第一次调用读盘，之后走缓存。
static func table() -> PBBondTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把真羁绊表装进一份配置。返回同一个 [param cfg]，方便串写。
##
## 忘了调就会静默退回 [method PBBondTable.synthetic] 那张合成表 ——
## 那是 M2-b1 用来对拍的替身曲线，跑出来的数值和真游戏对不上且不报错。
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
