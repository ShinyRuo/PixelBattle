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

## 已持有的卡。键是 [method PBUnit.key]（即角色 id），值是那张卡；
## 重复抽到只加 `copies`（§08：同卡 3 张升 1 星）。
var roster: Dictionary = {}

## 四条科技分支的等级（§07）。
var tech_gold: int = 0
var tech_pop: int = 0
var tech_atk: int = 0
var tech_def: int = 0

## 上场的经济位数量。纯经济卡，占出战位但不产生任何输出（§07 的改动）。
var economy_slot_count: int = 0

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

## 每条收入流各自赚了多少。键是 [constant PBEconomyRules.GOLD_SOURCES] 里的名字。
var gold_by_source: Dictionary = {}


## 收一张卡进仓库。已有的话累加张数（§08：同卡 3 张升 1 星）。
func add_unit(unit: PBUnit) -> void:
	var k: StringName = unit.key()
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


## 出战席里还剩几个位置能放输出 —— 经济位占着位却不产出任何伤害（§07）。
func open_slots(cfg: PBSimConfig) -> int:
	return maxi(deploy_capacity(cfg) - economy_slot_count, 0)


## 待命台格数。§05：初始 3，人口科技每 2 级 +1，上限 6。
func standby_capacity(cfg: PBSimConfig) -> int:
	return mini(cfg.standby_slots_base + tech_pop / 2, cfg.standby_slots_max)


## 攻击科技的全局倍率。§07：+6%/级。
func atk_mult(cfg: PBSimConfig) -> float:
	return 1.0 + cfg.tech_atk_per_level * float(tech_atk)


## 防御科技的基地减伤比例。§07：+4%/级。
func def_reduction(cfg: PBSimConfig) -> float:
	return cfg.tech_def_per_level * float(tech_def)


## 现在有哪些卡在给羁绊计数（§09）。
##
## §09 的生效规则：**出战席与待命台双场景全额生效、无衰减**，
## 但**派出去做任务的人羁绊暂时失效**（§06 新增）。这两条缺一不可，
## 否则 §06 那句「这一波我要羁绊，还是要钱」在模型里就没有代价，
## 派遣策略的对比（路线图第 4 个问题）会得出「派满永远最优」的假结论。
##
## ## 两处刻意留着的粗糙
##
## 1. **在场的是哪几张卡，这里按仓库顺序取前 N，不排序。**
##    「谁上场」在 M2-c 会变成玩家的真决策（真羁绊让它重新有得选），
##    在那之前排不排都一样 —— 合成羁绊表匹配所有人，取谁都是同一个数。
##    **而且不能排**：本函数在 [method PBValuation.mean_dps] 的热路径上，
##    每买一笔钱要过好几遍，多一次全仓排序会让批量扫描直接慢一倍。
## 2. **派出去的是哪几个，按末尾取。** §06 说派的是待命台上的人，
##    而待命台坐的就是排在后面的那几张。M2-d 会把它变成「派哪 3 人」。
func bonded_units(cfg: PBSimConfig) -> Array[PBUnit]:
	var pool := all_units()
	var on_field: int = mini(pool.size(), deploy_capacity(cfg) + standby_capacity(cfg))
	return pool.slice(0, maxi(on_field - dispatched, 0))


## 羁绊加成倍率（§09）。
func bond_mult(cfg: PBSimConfig) -> float:
	return 1.0 + PBBondRules.power_bonus(bonded_units(cfg), cfg.bonds)


## 假如仓库里有 [param roster_size] 张卡，羁绊倍率会是多少。
##
## 存在的理由是**比价**：会算账的玩家要问「再抽一张值多少」，
## 而新卡的价值有一部分来自羁绊，不只是它自己的输出。
##
## **这条口径 M2-b2 要换掉。** 它按人头算，而真羁绊问的是「多的那张卡是谁」——
## 一张补上凯班第 4 档的卡和一张谁都不搭的卡，价值差一个数量级。
## 换成按角色表求期望（和 [method PBValuation.expected_surplus] 同一套路）是那一步的事。
## 现在留着，是因为合成羁绊表上它和 [method bond_mult] 恒等，
## `test_bond_prediction_matches_the_real_formula` 锁着这条 ——
## **那条测试在 M2-b2 会红，那正是它的用处。**
func bond_mult_for(roster_size: int, cfg: PBSimConfig) -> float:
	return 1.0 + cfg.bond_power_per_unit * float(bonded_count_for(roster_size, dispatched, cfg))


## 有几个人在给羁绊计数 —— 羁绊倍率就是拿这个数乘出来的。
##
## 单独暴露出来是给准备阶段的任务卡用：§06 的验收原话是
## 「派了羁绊掉几档，准备阶段能一眼看出」，**「档」指的就是这个计数**。
## 只显示倍率不显示档数的话，玩家看不出自己离 [member PBSimConfig.bond_unit_cap]
## 还有多远 —— 而卡池够大的时候派遣是**完全免费**的（掉的档被上限吃掉了），
## 那是这个决策里最反直觉、也最值钱的一格信息。
func bonded_count_for(roster_size: int, dispatch: int, cfg: PBSimConfig) -> int:
	var on_field: int = mini(roster_size, deploy_capacity(cfg) + standby_capacity(cfg))
	return mini(maxi(on_field - dispatch, 0), cfg.bond_unit_cap)


## 待命台上现在有几个人可以被派出去做任务。
##
## 实现在这里而不是在 [PBStrategy] —— 界面层要问同一个问题（任务派不派得出），
## 而公式只能有一份。和 [method open_slots] 当初挪过来是同一个理由。
func standby_available(cfg: PBSimConfig) -> int:
	return clampi(roster.size() - open_slots(cfg), 0, standby_capacity(cfg))


## 装备带来的队伍战力倍率（§10 的替身曲线）。
##
## 配件先合成品，成品摊到出战席上，每人最多 [member PBSimConfig.equip_items_per_unit] 件。
## 装备满整队之前，每多一件成品就实打实多一份战力 —— 这就是它能当
## 「无底金币坑」的原因，和抽卡在卡池抽满后归零的边际收益正好相反。
func equip_mult(cfg: PBSimConfig) -> float:
	var slots: int = deploy_capacity(cfg) - economy_slot_count
	if slots <= 0:
		return 1.0
	var items: int = equip_parts / cfg.equip_parts_per_item
	var usable: int = mini(items, slots * cfg.equip_items_per_unit)
	return 1.0 + cfg.equip_power_per_item * float(usable) / float(slots)


## 卡池里有没有能克制 [param wave_element] 的单位。
##
## §02 的第三层视觉编码「可被当前阵容克制的敌人加一圈亮边」算的就是这个 ——
## 那是玩家在战斗中最需要的即时信息。
func can_counter(wave_element: PBElement.Type) -> bool:
	var needed := PBElement.counter_of(wave_element)
	for unit: PBUnit in roster.values():
		if unit.element == needed:
			return true
	return false


## 卡池覆盖不了的输出属性 —— 即「未来一个轮转周期里，哪几波你没有克星」。
##
## §03 要求准备阶段显示「当前阵容对下一波的克制覆盖：2/5，风系空缺」。
## 这是原版最大的短板：克制关系要点开技能说明才看得到，玩家全靠背。
## 自动算出来摆在 HUD 上，是本案投入产出比最高的一处改进。
func missing_counters() -> Array[int]:
	var missing: Array[int] = []
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		if not can_counter(wave_element as PBElement.Type):
			missing.append(int(PBElement.counter_of(wave_element as PBElement.Type)))
	return missing


## 花钱。钱不够返回 false 且不扣款。
func spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_spent += amount
	return true


## 进账。[param source] 是 [constant PBEconomyRules.GOLD_SOURCES] 里的一条流。
##
## 分流记账是为了回答 §07 的那个失败验收：不投经济几乎没有代价，
## 但只看总收入分不出「金币科技没用」和「金币科技有用但被别的流盖过」。
func earn(amount: int, source: StringName = &"other") -> void:
	gold += amount
	if amount > 0:
		gold_earned += amount
	# 击杀掉落会掉负数，照实累计净额 —— 抹掉负值会让它看起来比实际稳。
	gold_by_source[source] = int(gold_by_source.get(source, 0)) + amount
