class_name PBBeastTable
extends RefCounted
## 全部尾兽的查表。与 [PBBondTable] / [PBEquipTable] 同构。
##
## **没有合成表**：它的退化情形是真实局面 —— [member PBRunState.beast_id] 为空 = 不带尾兽，
## 那是扫描时「选了尾兽比不选强多少」的分母。
##
## 表是只读的：[method PBSimConfig.clone] 只复制引用而不深拷贝。

var _all: Array[PBBeast] = []
var _by_id: Dictionary = {}


## 用一组尾兽造一张表。测试直接造，游戏走 [PBBeastLoader]。
static func of(beasts: Array[PBBeast]) -> PBBeastTable:
	var table := PBBeastTable.new()
	for beast: PBBeast in beasts:
		table.add(beast)
	return table


## 收一只尾兽进表。**收下了返回 true，被拒返回 false。**
##
## 和 [method PBBondTable.add] 一样只返回状态、不打日志：报错留给装载器，
## 它手上有 `.tres` 的路径，能指出是哪份数据写错了。
##
## 拒收的情况：缺 id、id 重复、减速倍率不在 0–1 之间。
## **最后一条要拦** —— 填成 1.5 是「加速敌人」，那不会崩，
## 只会让那只尾兽的大招悄悄变成负收益。
func add(beast: PBBeast) -> bool:
	if beast == null or beast.id == &"":
		return false
	if _by_id.has(beast.id):
		return false
	if beast.ultimate_slow_scale < 0.0 or beast.ultimate_slow_scale > 1.0:
		return false
	if beast.aura_ultimate_cd_scale <= 0.0:
		return false
	_all.append(beast)
	_by_id[beast.id] = beast
	return true


func size() -> int:
	return _all.size()


func all() -> Array[PBBeast]:
	return _all


## 按 id 取。没有这只（含 id 为空，也就是「这局不带尾兽」）返回 null。
func by_id(beast_id: StringName) -> PBBeast:
	return _by_id.get(beast_id, null) as PBBeast


## 全部 id，按表里的顺序。扫描要逐只跑一遍时用得上。
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for beast: PBBeast in _all:
		out.append(beast.id)
	return out
