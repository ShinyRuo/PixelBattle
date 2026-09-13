class_name PBCharacterTable
extends RefCounted
## 全部角色的查表。抽卡、估值、羁绊共用一份索引 ——
## 各处各写遍历的话，「抽卡的分布」和「估值假设的分布」会慢慢对不上，且不报错。
##
## - [method synthetic] 造的**合成表**：`稀有度 × 属性 × per_bucket` 个无名角色，慢档整局扫描用的那副牌。
## - `data/characters/*.tres` 装载出来的**真角色表**（加载在 core 外面）。
##
## 表是只读的：[method PBSimConfig.clone] 只复制引用，改了会让批量扫描的格子互相串味。

var _all: Array[PBCharacter] = []
var _by_id: Dictionary = {}

## 键是 [method _cell_key]，值是 `Array[PBCharacter]`。
var _by_cell: Dictionary = {}

## 键是稀有度序号，值是 `Array[PBCharacter]`。
var _by_rarity: Dictionary = {}


## 造一张合成表：每个（稀有度, 属性）格子 [param per_bucket] 个无名角色。
## id 前缀 `syn_` 让人一眼看出它不是真角色。
static func synthetic(per_bucket: int) -> PBCharacterTable:
	var table := PBCharacterTable.new()
	for rarity: int in PBUnit.Rarity.size():
		# 铺 [constant PBElement.PICKABLE]，**不是 `Type.size()`** —— 否则合成卡池会多出一批
		# 克制一切的仙系角色，配平结论一起失真。
		for element: int in PBElement.PICKABLE:
			for variant: int in maxi(per_bucket, 1):
				table.add(
					PBCharacter.make(
						StringName("syn_e%d_r%d_v%d" % [element, rarity, variant]),
						element as PBElement.Type,
						rarity as PBUnit.Rarity
					)
				)
	return table


## 收一个角色进表。**收下了返回 true，被拒返回 false**（缺 id 或 id 重复）。
##
## **这里只返回状态，不打日志**：装载器手上有 `.tres` 的文件路径，报错要留给它。
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


func cell(element: PBElement.Type, rarity: PBUnit.Rarity) -> Array[PBCharacter]:
	return _by_cell.get(_cell_key(element, rarity), [] as Array[PBCharacter]) as Array[PBCharacter]


## 取（属性, 稀有度）这一格的第 [param index] 个角色，下标绕回。
##
## 合成表里这一格必然非空，取到的就是第 index 号变体。
## **真角色表里这一格可能是空的**（比如没有水系 SSR），
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
