class_name PBRunState
extends RefCounted
## 一局游戏的全部可变状态。字段与 §12 的存档结构一一对应。
##
## M-1 不实现存档（那是 M4），但字段名刻意跟存档 JSON 的键对齐 ——
## 到 M4 写序列化时就是一层平铺映射，不用先做一次结构重构。

## 当前波次，从 1 开始。
var wave_index: int = 1

var gold: int = 0

## 基地剩余血量。归零即本局结束，卡在的那一波就是玩家的成绩。
var base_hp: float = 0.0

## 已持有的卡。键是 [method PBUnit.key]，值是那张卡（重复抽到只加 copies）。
var roster: Dictionary = {}

## 四条科技分支的等级（§07）。
var tech_gold: int = 0
var tech_pop: int = 0
var tech_atk: int = 0
var tech_def: int = 0

## 上场的角都数量。纯经济卡，占出战位但不产生任何输出（§07 的改动）。
var kakuzu_count: int = 0

## 本波派出去做任务的人数。派遣期间羁绊不生效（§06），波次结算后归零。
var dispatched: int = 0

## 已买到的装备配件总数（§10 的替身曲线，见 [member PBSimConfig.equip_part_cost]）。
##
## M-1 不区分七种配件、不做合成树，只数总数 —— 保留的是它的经济学身份：
## **一个吃得下任意金币的深坑**。抽卡在卡池抽满后就没有边际价值了，
## 装备没有那个天花板，后期金币的去处主要是它。
var equip_parts: int = 0

## 连续未出 SSR 及以上的抽数，用于 §08 的保底。跨波保留，本局内有效。
var gacha_pity: int = 0

# ── 统计，只写不读，供 CSV 输出 ──────────────────────────────────
var total_kills: int = 0
var total_leaked: int = 0
var gold_earned: int = 0
var gold_spent: int = 0
var gacha_pulls: int = 0
var elapsed_seconds: float = 0.0


## 收一张卡进仓库。已有的话累加张数（§08：同卡 3 张升 1 星）。
func add_unit(unit: PBUnit) -> void:
	var k: int = unit.key()
	if roster.has(k):
		(roster[k] as PBUnit).copies += 1
	else:
		roster[k] = unit


func all_units() -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for unit: PBUnit in roster.values():
		out.append(unit)
	return out


## 全部卡按战力从高到低排序。
func sorted_by_power(cfg: PBSimConfig) -> Array[PBUnit]:
	var out := all_units()
	out.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return out


## 出战席容量。§05：初始 4，人口科技每级 +1，上限 10。
func deploy_capacity(cfg: PBSimConfig) -> int:
	return mini(cfg.deploy_slots_base + tech_pop, cfg.deploy_slots_max)


## 待命台格数。§05：初始 3，人口科技每 2 级 +1，上限 6。
func standby_capacity(cfg: PBSimConfig) -> int:
	return mini(cfg.standby_slots_base + tech_pop / 2, cfg.standby_slots_max)


## 攻击科技的全局倍率。§07：+6%/级。
func atk_mult(cfg: PBSimConfig) -> float:
	return 1.0 + cfg.tech_atk_per_level * float(tech_atk)


## 防御科技的基地减伤比例。§07：+4%/级。
func def_reduction(cfg: PBSimConfig) -> float:
	return cfg.tech_def_per_level * float(tech_def)


## 羁绊加成倍率 —— M-1 的替身曲线，不是真羁绊。
##
## 只有「在场（出战席 + 待命台）且未被派遣」的卡算数。这三个条件缺一不可，
## 否则 §06 那句「这一波我要羁绊，还是要钱」在模型里就没有代价，
## 派遣策略的对比（路线图第 4 个问题）会得出「派满永远最优」的假结论。
func bond_mult(cfg: PBSimConfig) -> float:
	var on_field: int = mini(roster.size(), deploy_capacity(cfg) + standby_capacity(cfg))
	var bonded: int = maxi(on_field - dispatched, 0)
	return 1.0 + cfg.bond_power_per_unit * float(mini(bonded, cfg.bond_unit_cap))


## 装备带来的队伍战力倍率（§10 的替身曲线）。
##
## 配件先合成品，成品摊到出战席上，每人最多 [member PBSimConfig.equip_items_per_unit] 件。
## 装备满整队之前，每多一件成品就实打实多一份战力 —— 这就是它能当
## 「无底金币坑」的原因，和抽卡在卡池抽满后归零的边际收益正好相反。
func equip_mult(cfg: PBSimConfig) -> float:
	var slots: int = deploy_capacity(cfg) - kakuzu_count
	if slots <= 0:
		return 1.0
	var items: int = equip_parts / cfg.equip_parts_per_item
	var usable: int = mini(items, slots * cfg.equip_items_per_unit)
	return 1.0 + cfg.equip_power_per_item * float(usable) / float(slots)


## 花钱。钱不够返回 false 且不扣款。
func spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_spent += amount
	return true


## 进账。
func earn(amount: int) -> void:
	gold += amount
	if amount > 0:
		gold_earned += amount
