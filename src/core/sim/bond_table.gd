class_name PBBondTable
extends RefCounted
## 全部羁绊的查表。M2-b。与 [PBCharacterTable] 同构，理由也一样。
##
## ## 两种表
##
## - [method synthetic] 造的**合成表**：一组「所有人都算成员」的羁绊，
##   数值上精确复现 M-1 那条「每人 +6%、封顶 12 人」的替身曲线。
##   **它存在的唯一理由是让结构层的引入可以对拍。**
## - `data/bonds/*.tres` 装载出来的**真羁绊表**（M2-b2）。加载发生在 core 外面。
##
## ## 表是只读的
##
## 造完就不该再改 —— [method PBSimConfig.clone] 只复制引用而不深拷贝。

## 合成表那组羁绊的 id。前缀 `syn_` 和合成角色表一致，一眼看得出不是内容。
const SYNTHETIC_ID: StringName = &"syn_headcount"

var _all: Array[PBBond] = []
var _by_id: Dictionary = {}


## 造一张合成表：一组匹配所有人的羁绊，第 k 档要 k 个人、给 `per_unit × k` 加成，
## 一共 [param cap] 档。
##
## 这样 N 个人到场时激活第 `min(N, cap)` 档，加成 `per_unit × min(N, cap)` ——
## **和 M-1 的 `bond_power_per_unit × min(在场 − 派遣, bond_unit_cap)` 逐位相同。**
static func synthetic(per_unit: float, cap: int) -> PBBondTable:
	var bond := PBBond.new()
	bond.id = SYNTHETIC_ID
	bond.name_key = String(SYNTHETIC_ID)
	bond.match_mode = PBBond.Match.EVERYONE
	for k: int in range(1, maxi(cap, 0) + 1):
		bond.tier_counts.append(k)
		bond.tier_power.append(per_unit * float(k))
		bond.tier_function_keys.append(&"")
	var table := PBBondTable.new()
	table.add(bond)
	return table


## 收一组羁绊进表。**收下了返回 true，被拒返回 false。**
##
## 和 [method PBCharacterTable.add] 一样只返回状态、不打日志：
## 报错留给装载器，它手上有 `.tres` 的路径，能指出是哪份数据写错了。
##
## 拒收的情况：缺 id、id 重复、档位两条数组不等长、档位人数不是升序。
## **后两条尤其要拦** —— 档位表写歪了不会崩，只会让某一档静默失效，
## 而那种偏差只表现为「这组羁绊好像没什么用」。
func add(bond: PBBond) -> bool:
	if bond == null or bond.id == &"":
		return false
	if _by_id.has(bond.id):
		return false
	if bond.tier_counts.size() != bond.tier_power.size():
		return false
	for i: int in bond.tier_counts.size():
		if bond.tier_counts[i] <= 0:
			return false
		if i > 0 and bond.tier_counts[i] <= bond.tier_counts[i - 1]:
			return false
	_all.append(bond)
	_by_id[bond.id] = bond
	return true


func size() -> int:
	return _all.size()


func all() -> Array[PBBond]:
	return _all


func by_id(bond_id: StringName) -> PBBond:
	return _by_id.get(bond_id, null) as PBBond
