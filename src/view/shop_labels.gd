class_name PBShopLabels
extends RefCounted
## 准备阶段每个购买项的**价格与文案**。
##
## 指令卡的格子写不下整句，所以拆两截：格子上写短的，悬停时提示条上写长的。**两截必须来自同一处**，
## 否则按钮上的价格和提示里的价格迟早对不上。
## 「买下去战力涨多少」是这一层存在的理由，数字来自 [PBValuation] —— 与模拟玩家比价同一份计算。

## 大本营首页那几项。顺序即指令卡里的排列顺序。
const BASE_KINDS: Array[StringName] = [
	&"gacha",
	&"equip",
	&"economy_slot",
	&"tech_gold",
	&"tech_pop",
	&"tech_def",
]

## 「科技 ▸」二级页那四项。**键 = `tech_` + [constant PBTechRules.BRANCHES]**，
## 于是 [PBBattleView] 那条「去掉前缀交给 `buy_tech`」的兜底一行不用改。
const TRAINING_KINDS: Array[StringName] = [
	&"tech_train_attack",
	&"tech_train_defence",
	&"tech_train_hp",
	&"tech_train_aim",
]

## 全部可购买项（两页合起来）。悬停提示与测试按它走。
const KINDS: Array[StringName] = [
	&"gacha",
	&"equip",
	&"economy_slot",
	&"tech_gold",
	&"tech_pop",
	&"tech_def",
	&"tech_train_attack",
	&"tech_train_defence",
	&"tech_train_hp",
	&"tech_train_aim",
]

## §10 的三档装备分类。**名字写在这里而不是数据表里** ——
## 分类是规则（挂不挂得上），显示名是文案，两者改动频率差很远。
const CATEGORY_NAMES := {
	PBEquipItem.Category.PHYSICAL: "物理装",
	PBEquipItem.Category.MAGIC: "法术装",
	PBEquipItem.Category.TANK: "坦克装",
}

## 每一档挂给谁才生效。**这是 §10 最容易踩的坑**：挂上去没反应
## 十有八九是分类不匹配，而那件事在格子上一个字都看不出来。
const CATEGORY_HINTS := {
	PBEquipItem.Category.PHYSICAL: "只对物理属性的忍者生效",
	PBEquipItem.Category.MAGIC: "只对五系忍者生效",
	PBEquipItem.Category.TANK: "当前角色表里没有能吃它的人",
}

## 科技分支的显示名。
const TECH_NAMES := {
	&"gold": "金币科技",
	&"pop": "人口科技",
	&"def": "防御科技",
	&"train_attack": "训练攻击",
	&"train_defence": "训练防御",
	&"train_hp": "训练生命",
	&"train_aim": "训练精准",
}

## 格子上写的短名。
const SHORT_NAMES := {
	&"gacha": "抽卡",
	&"equip": "忍具箱",
	&"economy_slot": "经济位",
	&"tech_gold": "金币科技",
	&"tech_pop": "人口科技",
	&"tech_def": "防御科技",
	&"tech_train_attack": "训练攻击",
	&"tech_train_defence": "训练防御",
	&"tech_train_hp": "训练生命",
	&"tech_train_aim": "训练精准",
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
			return "抽卡 %d　摆三张挑一张　期望战力 %s" % [cost, _percent(PBValuation.gacha_gain(state, cfg))]
		&"equip":
			return _detail_equip(state, cfg, base, cost)
		&"economy_slot":
			return _detail_economy_slot(state, cfg, base, cost)
	return _detail_tech(kind, state, cfg, base, cost)


## 一份词条表写成人看得懂的几个词。**两块面板共用这一处** —— 各写一份的话
## 「攻速 +30%」和「攻速 +0%」会同时出现（成数忘了乘 100，见 [method PBModRules.display_value]）。
##
## **不是整数就写一位小数**：句式是 `%.0f`，尾兽光环 1 级的吸血 1.5% 会被四舍五入成「2%」。
static func mod_words(mods: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in mods:
		var shown: float = PBModRules.display_value(key, float(mods[key]))
		var pattern: String = PBLocale.text("mod.%s" % key)
		if not pattern.contains("%"):
			# 「开波即触发」那种不带数的句式：直接 `%` 一个没有占位符的串会报错。
			out.append(pattern)
			continue
		if not is_equal_approx(shown, roundf(shown)):
			pattern = pattern.replace("%.0f", "%.1f")
		out.append(pattern % shown)
	return out


## 一件**成品**的说明卡正文（§10）。标题由调用方给。
## 按玩家会问的顺序排：**能不能挂给他**、**挂上去给什么**、**要哪几个配件**。
static func item_body(item: PBEquipItem, table: PBEquipTable) -> String:
	var lines := PackedStringArray()
	lines.append(CATEGORY_NAMES.get(item.category, "?"))
	# **写词条，不写「+N% 战力」**：`power` 只是估值分，玩家要对的是属性栏上那几个数。
	var words := mod_words(item.mods)
	if words.is_empty():
		lines.append(PBSkin.tint("当前战斗模型下什么都不给", PBSkin.DIM))
	else:
		lines.append("　".join(words))
	var parts := PackedStringArray()
	for part_id: StringName in item.recipe:
		parts.append(PBLocale.text("equip_part.%s" % part_id))
	lines.append(PBSkin.tint("配方　" + "　".join(parts), PBSkin.DIM))
	if not table.is_synthetic():
		lines.append(PBSkin.tint(CATEGORY_HINTS.get(item.category, ""), PBSkin.DIM))
	return "\n".join(lines)


## 一个**配件**的说明卡正文。配件本身没有效果，说清它是干什么的就够。
static func part_body() -> String:
	return PBSkin.tint("配件。按配方凑齐几种才合得出成品（§10）——\n忍具箱随机出货，所以一定会囤下用不上的。", PBSkin.DIM)


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
	var gain: float = PBValuation.tech_gain(state, cfg, branch, base) if base > 0.0 else 0.0
	if gain > 0.0:
		return "%s Lv%d　%d　战力 %s" % [label, level, cost, _percent(gain)]
	if branch == &"pop":
		return "%s Lv%d　%d　出战位 +1" % [label, level, cost]
	# 训练科技写**词条**：训练防御与训练生命在战力那把尺子上恒为 0，写「战力 +0.0%」会让人以为它没用。
	return "%s Lv%d　%d　%s" % [label, level, cost, _training_words(branch)]


## 「近战 攻击力 +50 攻速 +5%」—— 每一级给什么、给谁。
static func _training_words(branch: StringName) -> String:
	if not PBTechRules.is_branch(branch):
		return ""
	var who: String = "近战" if bool(PBTechRules.FOR_MELEE[branch]) else "远程"
	return "%s %s" % [who, " ".join(mod_words(PBTechRules.PER_LEVEL[branch]))]


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
	var branch := _branch_of(kind)
	match branch:
		&"gold":
			return state.tech_gold
		&"pop":
			return state.tech_pop
		&"def":
			return state.tech_def
		_:
			return state.training_level(branch)


## 带符号的百分比。**正号要写出来** —— 一列没有符号的数字读起来像开销。
static func _percent(value: float) -> String:
	return "%+.1f%%" % (value * 100.0)
