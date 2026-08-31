class_name PBBeastTable
extends RefCounted
## 全部尾兽的查表。M3-d。与 [PBBondTable] / [PBEquipTable] 同构。
##
## ## 这张表没有「合成表」，和前三张不一样
##
## [PBCharacterTable] / [PBBondTable] / [PBEquipTable] 各有一条
## `synthetic()` 替身曲线，用来让「结构层的引入」可以与「换真数据」分开对拍。
##
## 尾兽不需要那一步，因为**它的退化情形是一个真实存在的局面**：
## [member PBRunState.beast_id] 为空 = 这一局没有尾兽。
## 那不是一条假曲线，是扫描时的**对照组** —— 「选了尾兽比不选强多少」
## 这个问题必须有一个分母，而这个分母只能是「一只都不带」。
##
## （§11 的正式规则是开局必选一只，所以「不带」不是一个可玩的选项，
## 只是一把尺子。真正上架时默认值要翻成某一只，见路线图的待决策表。）
##
## ## 表是只读的
##
## 造完就不该再改 —— [method PBSimConfig.clone] 只复制引用而不深拷贝。

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
