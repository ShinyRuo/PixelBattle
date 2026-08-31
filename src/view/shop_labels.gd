class_name PBShopLabels
extends RefCounted
## 准备阶段每个购买项的**价格与文案**。M3.5-e，从 [PBPreparePanel] 抽出来。
##
## ## 为什么要单独一份
##
## 战场直接操作（§02）之后，这些项从一块常驻面板搬进了**指令卡**——
## 一个 3×3 的小格子网格。格子里写不下「忍具箱 300（配件 14，每箱战力 +0.6%）」，
## 所以拆成两截：格子上写短的，悬停时在提示条上写长的。
##
## **两截必须来自同一处。** 分开写的话，按钮上的价格和提示里的价格
## 迟早对不上 —— 而那正是 CLAUDE.md 那条「四块面板与比价同源」防的病。
##
## ## 「买下去战力涨多少」搬到了悬停，但没有丢
##
## 那句话是这一层存在的理由（原版最大的短板是信息不透明，§03/§10），
## 数字来自 [PBValuation]，也就是模拟玩家比价用的**同一份计算**。
## 指令卡的格子太小，长句只能进提示条 —— 这是记在案的取舍，不是省略。

## 全部可购买项。顺序即指令卡里的排列顺序。
const KINDS: Array[StringName] = [
	&"gacha",
	&"equip",
	&"economy_slot",
	&"tech_gold",
	&"tech_pop",
	&"tech_atk",
	&"tech_def",
]

## 四条科技分支的显示名（§07）。
const TECH_NAMES := {
	&"gold": "金币科技",
	&"pop": "人口科技",
	&"atk": "攻击科技",
	&"def": "防御科技",
}

## 格子上写的短名。
const SHORT_NAMES := {
	&"gacha": "抽卡",
	&"equip": "忍具箱",
	&"economy_slot": "经济位",
	&"tech_gold": "金币科技",
	&"tech_pop": "人口科技",
	&"tech_atk": "攻击科技",
	&"tech_def": "防御科技",
}


## 这一项要多少钱。**-1 表示买不了**（满级 / 装备已装满 / 位置不够）。
static func cost_of(kind: StringName, state: PBRunState, cfg: PBSimConfig) -> int:
	match kind:
		&"gacha":
			return cfg.gacha_cost
		&"equip":
			return -1 if _equipment_full(state, cfg) else cfg.equip_part_cost
		&"economy_slot":
			# 经济位是抽来的角色不是商店货，代价折成一次单抽 —— 与模拟玩家同口径。
			# 留一个出战位，否则整队都是经济卡、DPS 归零。
			return -1 if state.open_slots(cfg) <= 1 else cfg.gacha_cost
		_:
			return PBEconomyRules.tech_cost(_branch_of(kind), _tech_level(kind, state), cfg)


## 格子上写的两行：名字 + 价格。买不了就写为什么。
static func short_of(kind: StringName, state: PBRunState, cfg: PBSimConfig) -> String:
	var name: String = SHORT_NAMES.get(kind, String(kind))
	var cost: int = cost_of(kind, state, cfg)
	if cost < 0:
		return "%s\n—" % name
	if String(kind).begins_with("tech_"):
		return "%s Lv%d\n%d" % [name, _tech_level(kind, state), cost]
	return "%s\n%d" % [name, cost]


## 悬停时提示条上写的那一整句。**「买下去战力涨多少」在这里。**
static func detail_of(kind: StringName, state: PBRunState, cfg: PBSimConfig) -> String:
	var base: float = PBValuation.mean_dps(state, cfg)
	var cost: int = cost_of(kind, state, cfg)
	match kind:
		&"gacha":
			# 一张卡都没有时估值函数返回的是「无穷大」的哨兵值（1.0）。
			# 照着写成「+100%」会让开局这一屏看起来像坏了 —— 直接说人话。
			if state.roster.is_empty():
				return "抽卡 %d　先抽第一张（三选一）" % cost
			return (
				"抽卡 %d　摆三张挑一张　期望战力 %s"
				% [cost, _percent(PBValuation.gacha_gain(state, cfg))]
			)
		&"equip":
			return _detail_equip(state, cfg, base, cost)
		&"economy_slot":
			return _detail_economy_slot(state, cfg, base, cost)
	return _detail_tech(kind, state, cfg, base, cost)


static func _detail_equip(state: PBRunState, cfg: PBSimConfig, base: float, cost: int) -> String:
	if cost < 0:
		return "装备配件　已装满"
	# 写的是**开一箱的期望收益**，不是「多一个配件立刻涨多少」——
	# 忍具箱随机出货、配方点名要哪几种，所以单箱的即时收益十有八九是 0，
	# 照实写 0 会让玩家以为装备没用（见 [method PBValuation.equip_box_gain]）。
	var owned: int = PBEquipRules.part_total(state.equip_parts)
	if base <= 0.0:
		return "忍具箱 %d（配件 %d）" % [cost, owned]
	var per_box: String = _percent(PBValuation.equip_box_gain(state, cfg, base))
	return "忍具箱 %d（配件 %d，每箱战力 %s）" % [cost, owned, per_box]


## 经济位是全场唯一一个**两种货币并列**的项：付出战力，收金币。
## 换算留给玩家 —— §07 的「经济位 = 战力空位」就是这个取舍本身。
static func _detail_economy_slot(
	state: PBRunState, cfg: PBSimConfig, base: float, cost: int
) -> String:
	if cost < 0:
		return "经济位　位置不够"
	if base <= 0.0:
		return "经济位 %d　每波 +%d 金（先凑阵容）" % [cost, _economy_slot_step(state, cfg)]
	return (
		"经济位 %d　战力 −%.1f%%　每波 +%d 金"
		% [
			cost,
			PBValuation.economy_slot_loss(state, cfg, base) * 100.0,
			_economy_slot_step(state, cfg)
		]
	)


static func _detail_tech(
	kind: StringName, state: PBRunState, cfg: PBSimConfig, base: float, cost: int
) -> String:
	var branch := _branch_of(kind)
	var label: String = TECH_NAMES.get(branch, "科技")
	if cost < 0:
		return "%s　满级" % label
	var level: int = _tech_level(kind, state)
	# 金币和防御不直接产出 DPS，写「战力 +0%」会误导 —— 各写各的口径。
	if branch == &"gold":
		return "%s Lv%d　%d　每波 +%d 金" % [label, level, cost, _passive_step(state, cfg)]
	if branch == &"def":
		var reduction: float = cfg.tech_def_per_level * 100.0
		return "%s Lv%d　%d　基地减伤 +%.0f%%" % [label, level, cost, reduction]
	# 队伍是空的时候，「涨百分之几」算出来恒为 0（0 的 6% 还是 0）。
	# 照实显示「战力 —」会让开局这一屏看起来像坏了，改写标称效果 —— 那句同样是真的。
	if base <= 0.0:
		if branch == &"pop":
			return "%s Lv%d　%d　出战位 +1" % [label, level, cost]
		return "%s Lv%d　%d　全体攻击 +%.0f%%" % [label, level, cost, cfg.tech_atk_per_level * 100.0]
	return (
		"%s Lv%d　%d　战力 %s"
		% [label, level, cost, _percent(PBValuation.tech_gain(state, cfg, branch, base))]
	)


## 升一级金币科技，每波多赚多少。用上一波的实际时长估。
static func _passive_step(state: PBRunState, cfg: PBSimConfig) -> int:
	var seconds: float = 10.0
	if state.wave_index > 1 and state.elapsed_seconds > 0.0:
		seconds = state.elapsed_seconds / float(state.wave_index - 1)
	var after := PBEconomyRules.passive_income(seconds, state.tech_gold + 1, cfg)
	return after - PBEconomyRules.passive_income(seconds, state.tech_gold, cfg)


## 多上一个经济位，每波多赚多少。
static func _economy_slot_step(state: PBRunState, cfg: PBSimConfig) -> int:
	var after := PBEconomyRules.economy_slot_income(
		state.economy_slot_count + 1, state.wave_index, cfg
	)
	return (
		after - PBEconomyRules.economy_slot_income(state.economy_slot_count, state.wave_index, cfg)
	)


static func _equipment_full(state: PBRunState, cfg: PBSimConfig) -> bool:
	var deployed := PBValuation.deployed_by_raw_power(state, cfg)
	if deployed.is_empty():
		return false
	var owned := PBEquipRules.craftable(state.equip_parts, cfg.equipment)
	var items: int = 0
	for item_id: StringName in owned:
		items += int(owned[item_id])
	return items >= PBEquipRules.open_item_slots(deployed, cfg)


static func _branch_of(kind: StringName) -> StringName:
	return StringName(String(kind).trim_prefix("tech_"))


static func _tech_level(kind: StringName, state: PBRunState) -> int:
	match _branch_of(kind):
		&"gold":
			return state.tech_gold
		&"pop":
			return state.tech_pop
		&"atk":
			return state.tech_atk
		_:
			return state.tech_def


## 带符号的百分比。**正号要写出来** —— 一列没有符号的数字读起来像开销。
static func _percent(value: float) -> String:
	return "%+.1f%%" % (value * 100.0)
