class_name PBCharacterLoader
extends RefCounted
## 把 `data/characters/*.tres` 装成一张 [PBCharacterTable]。
##
## 不在 `src/core/`：`ResourceLoader` 被纯度检查挡住。core 只认表的类型，批量模拟喂合成表、测试现造、
## 真游戏喂 `.tres`，共用同一套规则。报错只能在这一层做（只有这里手上有文件路径）。
##
## **排序是确定性**：[method ResourceLoader.list_directory] 的顺序跨平台不保证一致，而抽卡是
## 「掷稀有度 → 在该稀有度的角色里掷下标」—— 顺序一变，同一个种子在另一台机器上抽到别的角色。

const DIR := "res://data/characters"

## 装好的表缓存一份。角色表是只读内容，重复读盘没有意义。
static var _cached: PBCharacterTable = null


## 全部角色。第一次调用读盘，之后走缓存。
static func table() -> PBCharacterTable:
	if _cached == null:
		_cached = load_from(DIR)
	return _cached


## 把真角色表装进一份配置。返回同一个 [param cfg]，方便串写。
##
## **每个游戏入口都要调它一次。** 忘了调就会静默退回合成表 ——
## 那张表是给对拍用的假卡池，跑出来的数值和真游戏对不上且不报错。
## `test_battle_view.gd` 里有一条断言守着主场景确实调了。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	cfg.characters = table()
	return cfg


## 新建一份装好真角色表的配置。游戏入口用这个，别直接 `PBSimConfig.new()`。
static func config() -> PBSimConfig:
	return install(PBSimConfig.new())


## 从指定目录装一张表。目录读不到或有坏数据时会报错并跳过那一份。
static func load_from(dir_path: String) -> PBCharacterTable:
	var table_out := PBCharacterTable.new()
	var names := ResourceLoader.list_directory(dir_path)
	if names.is_empty():
		push_error("角色目录打不开：%s" % dir_path)
		return table_out
	names.sort()  # 确定性，见类顶部说明
	for file_name: String in names:
		# 导入后引擎会在旁边生成 .import / .remap 之类的边车文件，只认 .tres。
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [dir_path, file_name]
		var character := load(path) as PBCharacter
		if character == null:
			push_error("这份角色数据装不进来（不是 PBCharacter？）：%s" % path)
			continue
		if not table_out.add(character):
			push_error("这份角色数据被拒收（id 空或重复）：%s" % path)
	return table_out
