class_name PBCharacterTable
extends RefCounted
## 全部角色的查表。M2-a。
##
## 抽卡、估值、羁绊都要问同一批问题（这个稀有度有哪些角色？这一格有几个？），
## 索引建一次、各处共用 —— 每处各写一遍遍历，慢是其次，
## **真正的风险是「抽卡的分布」和「估值假设的分布」慢慢对不上，且不报错**。
##
## ## 两种表
##
## - [method synthetic] 造的**合成表**：`4 稀有度 × 6 属性 × per_bucket` 个无名角色，
##   完全复现 M-1/M0/M1 的卡池。**它存在的唯一理由是让身份层的引入可以对拍**——
##   接真角色表是下一步，那一步的数值变化必须能和这一步的重构分开看。
## - `data/characters/*.tres` 装载出来的**真角色表**（M2-a2）。加载发生在 core 外面。
##
## ## 表是只读的
##
## 造完就不该再改。[PBSimConfig.clone] 只复制引用而不深拷贝，
## 靠的就是这条 —— 破坏它会让批量扫描的各个格子互相串味。

var _all: Array[PBCharacter] = []
var _by_id: Dictionary = {}

## 键是 [method _cell_key]，值是 `Array[PBCharacter]`。
var _by_cell: Dictionary = {}

## 键是稀有度序号，值是 `Array[PBCharacter]`。
var _by_rarity: Dictionary = {}


## 造一张合成表：每个（稀有度, 属性）格子 [param per_bucket] 个无名角色。
##
## **这是 M-1 至 M1 一直在用的那个卡池**，只是现在每张卡有了 id。
## id 前缀 `syn_` 是有意的 —— 一眼看得出它不是真角色，
## 免得将来有人拿它当内容用。
static func synthetic(per_bucket: int) -> PBCharacterTable:
	var table := PBCharacterTable.new()
	for rarity: int in PBUnit.Rarity.size():
		for element: int in PBElement.Type.size():
			for variant: int in maxi(per_bucket, 1):
				table.add(
					PBCharacter.make(
						StringName("syn_e%d_r%d_v%d" % [element, rarity, variant]),
						element as PBElement.Type,
						rarity as PBUnit.Rarity
					)
				)
	return table


## 收一个角色进表。**收下了返回 true，被拒返回 false。**
##
## 拒收的两种情况：缺 id，或 id 重复。重复 id 会让仓库把两个角色
## 当成同一张卡去升星，而那种错误在结果里完全看不出来。
##
## **这里只返回状态，不打日志。** 报错要留给装载器（M2-a2，在 core 外面）——
## 它手上有 `.tres` 的文件路径，能指出是哪份数据写错了；
## core 里只能打出一个没有出处的 id，对排查毫无帮助。
func add(character: PBCharacter) -> bool:
	if character == null or character.id == &"":
		return false
	if _by_id.has(character.id):
		return false
	_all.append(character)
	_by_id[character.id] = character
	var cell: int = _cell_key(character.element, character.rarity)
	if not _by_cell.has(cell):
		_by_cell[cell] = [] as Array[PBCharacter]
	(_by_cell[cell] as Array[PBCharacter]).append(character)
	var rarity: int = int(character.rarity)
	if not _by_rarity.has(rarity):
		_by_rarity[rarity] = [] as Array[PBCharacter]
	(_by_rarity[rarity] as Array[PBCharacter]).append(character)
	return true


func size() -> int:
	return _all.size()


func all() -> Array[PBCharacter]:
	return _all


func by_id(character_id: StringName) -> PBCharacter:
	return _by_id.get(character_id, null) as PBCharacter


## 某个稀有度下的全部角色。**抽卡与估值都按这个口径算概率**，
## 见 [method PBValuation.expected_surplus]。
func of_rarity(rarity: PBUnit.Rarity) -> Array[PBCharacter]:
	return _by_rarity.get(int(rarity), [] as Array[PBCharacter]) as Array[PBCharacter]


## 这一格（属性 × 稀有度）里有几个角色。
func count_in_cell(element: PBElement.Type, rarity: PBUnit.Rarity) -> int:
	return cell(element, rarity).size()


func cell(element: PBElement.Type, rarity: PBUnit.Rarity) -> Array[PBCharacter]:
	return _by_cell.get(_cell_key(element, rarity), [] as Array[PBCharacter]) as Array[PBCharacter]


## 取（属性, 稀有度）这一格的第 [param index] 个角色，下标绕回。
##
## 合成表里这一格必然非空，取到的就是第 index 号变体。
## **真角色表里这一格可能是空的**（比如没有水系 USR），
## 那时候退回到同稀有度的任意一个 —— 抽卡不能因为格子空了就掉空。
## 这条退化路径在合成表上永远走不到，所以它不影响对拍。
func pick(element: PBElement.Type, rarity: PBUnit.Rarity, index: int) -> PBCharacter:
	var bucket := cell(element, rarity)
	if not bucket.is_empty():
		return bucket[posmod(index, bucket.size())]
	var fallback := of_rarity(rarity)
	if fallback.is_empty():
		return null
	return fallback[posmod(index, fallback.size())]


static func _cell_key(element: PBElement.Type, rarity: PBUnit.Rarity) -> int:
	return int(rarity) * 8 + int(element)
