@tool
class_name PBEnemyShotTable
extends RefCounted
## `data/enemy_shots.tsv`：**哪一种会开枪的敌人打哪一颗子弹**。一行一种，键是敌人的皮键（[method PBEnemyPool.skin_key]）。
##
## 敌人没有 [PBCharacter]，名册那一格（[member PBCharacter.shot_key]）落不下，所以另起一张两列的小表。
## **按皮配，不按属性推**（玩家定的）：同是火系，远程小怪射火箭、BOSS 吐火球，都是逐个配的事。
##
## 表由「战场特效」面板写（[method PBShotForge.assign_enemy]），渲染层读（[method PBShotPool._shot_skin]）。
## 不经过生成器：表里只有两列字符串，生成一份 `.tres` 只是同一件事再抄一遍。
## `@tool` 是给面板的：编辑器里不带它的脚本只是占位。

const PATH := "res://data/enemy_shots.tsv"

## 子弹键那一格写这个 = 没配（白模）。
const NONE := "-"

static var _cached: Dictionary = {}
static var _loaded: bool = false


## 这种敌人打哪一颗子弹。没配、查不到、表不在，一律返回空（调用方退回白模）。
static func shot_for(skin_key: StringName) -> StringName:
	if not _loaded:
		_cached = load_from(PATH)
		_loaded = true
	return _cached.get(skin_key, &"")


## 读一张表：`{皮键: 子弹键}`，只收配了的那几行。表不在就是一张空表 —— 那正是「全是白模」的样子，不该报错。
static func load_from(path: String) -> Dictionary:
	var out: Dictionary = {}
	for cells: PackedStringArray in rows(path):
		if cells.size() >= 2 and cells[1] != NONE and cells[1] != "":
			out[StringName(cells[0])] = StringName(cells[1])
	return out


## 表里每一行（去掉注释和空行），配没配都算。测试拿它核对「表里正好是会开枪的那几种」。
static func rows(path: String = PATH) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	if not FileAccess.file_exists(path):
		return out
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		out.append(cells)
	return out


## 下一次查的时候重新读盘（面板改了表、测试塞了假数据之后）。
static func reload() -> void:
	_cached = {}
	_loaded = false
