class_name PBBeastRules
extends RefCounted
## 尾兽的结算规则（§11）。全部 static、无状态、零引擎依赖。
##
## 一只尾兽分成三份：**光环**（[method aura_passives]，走被动词汇表）、
## **对角色大招的加速**（冷却倍率）、**大招**（一个 `dps = 0` 的 [PBAttacker]，
## 见 [method build_ultimate_attacker]）。
##
## ## 等级只放大三样东西
##
## 光环、大招伤害、大招频率按同一个 [method level_scale] 放大；半径、聚拢、
## 减速倍率、重置 CD 一概不变。放大机制会让机制型尾兽随金币无限膨胀
## （Lv10 的全屏定身等于游戏结束）；放大频率则让六尾、七尾这种零伤害的尾兽
## 也有升级曲线。`beast_level_gain` 是占位值，归数值回归。

## [member PBAttacker.slot] 上给尾兽留的号。
##
## 出战席的下标从 0 起，所以负数不会和任何一个真单位撞上。
## 渲染层靠它把「这一发是尾兽放的」和「这一发是第 3 号位放的」分开 ——
## §11 的尾兽大招在 §02 的屏幕分区里有自己的位置（底部中央那个大按钮）。
const BEAST_SLOT: int = -1


## 这一局带的是哪只尾兽。没带（或者表里没有这个 id）返回 null。
##
## 「没带」是一个**合法且有用**的局面：它是扫描时的对照组，
## 「选了尾兽比不选强多少」这个问题的分母。见 [PBBeastTable] 顶部。
static func beast_of(state: PBRunState, cfg: PBSimConfig) -> PBBeast:
	if cfg.beasts == null or state.beast_id == &"":
		return null
	return cfg.beasts.by_id(state.beast_id)


## 等级对效果的放大倍数。Lv1 = 1.0，也就是 `.tres` 里写的就是 1 级的值。
static func level_scale(level: int, cfg: PBSimConfig) -> float:
	var lv: int = clampi(level, 1, maxi(cfg.beast_level_max, 1))
	return 1.0 + cfg.beast_level_gain * float(lv - 1)


## 从 [param level] 升一级要多少钱。**已满级返回 −1**，与
## [method PBEconomyRules.tech_cost] 同一个约定（调用方只认负数）。
##
## §11 的公式是 `400 × 1.6^Lv`。指数底 1.6 比攻击科技的 1.4 更陡，
## 是有道理的：科技加的是一条 +6% 的线性梯子，尾兽升级同时买到
## 光环、大招伤害和大招频率三样，本来就该更贵。
static func upgrade_cost(level: int, cfg: PBSimConfig) -> int:
	if level >= cfg.beast_level_max:
		return -1
	return int(floor(cfg.beast_level_cost * pow(cfg.beast_level_mult, float(maxi(level, 1)))))


## 常驻光环按等级折算出来的那一份：`{被动键: 量}`。
## 表里写「每级多少」，这里乘上 [method level_scale]。
static func aura_passives(beast: PBBeast, level: int, cfg: PBSimConfig) -> Dictionary:
	var out: Dictionary = {}
	if beast == null:
		return out
	var scale: float = level_scale(level, cfg)
	for key: StringName in beast.aura_passives:
		out[key] = float(beast.aura_passives[key]) * scale
	return out


## 光环给每个上场单位的伤害倍率，与 [param deployed] 同序。
##
## 形状刻意和 [method PBEquipRules.unit_multipliers] 一模一样 ——
## 两者在 [method PBCombatRules.unit_multipliers] 里相乘，
## 调用方不需要知道有几种逐人加成，加第三种时也只改那一处。
##
## 为什么是逐人而不是一条全队倍率：§11 有三只尾兽的光环带筛选
## （三尾只加水系、五尾只加土系、九尾只加点名的角色）。
## 折成全队平均数的话，「为了吃满尾兽光环去凑同系阵容」这个决策就没了 ——
## 而那正是尾兽和 §03 属性系统的接口。
static func unit_multipliers(
	deployed: Array[PBUnit], beast: PBBeast, level: int, cfg: PBSimConfig
) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(deployed.size())
	out.fill(1.0)
	if beast == null or beast.aura_power == 0.0:
		return out
	var bonus: float = beast.aura_power * level_scale(level, cfg)
	for i: int in deployed.size():
		if beast.aura_applies_to(deployed[i].character):
			out[i] = 1.0 + bonus
	return out


## 光环给**角色大招**的冷却倍率（0.8 = 冷却缩短两成）。没带尾兽是 1.0。
##
## **不随等级放大。** 它已经是个乘算折扣，再乘上 Lv10 的放大倍数会变成负冷却；
## 而六尾在升级上真正该买到的是**它自己那发重置**放得更勤，
## 那一份走 [method build_ultimate_attacker] 里的冷却缩短。
static func ultimate_cd_scale(beast: PBBeast) -> float:
	if beast == null:
		return 1.0
	return maxf(beast.aura_ultimate_cd_scale, 0.05)


## 光环给基地的额外减伤。**当前全表为 0**，理由见 [member PBBeast.aura_def_reduction]。
static func def_reduction_bonus(beast: PBBeast, level: int, cfg: PBSimConfig) -> float:
	if beast == null:
		return 0.0
	return beast.aura_def_reduction * level_scale(level, cfg)


## 把尾兽的大招做成一个**攻击者**。没带尾兽、或者这只尾兽的大招毫无后果时返回 null。
##
## ## 为什么是「一个 dps 为 0 的攻击者」而不是一个新类型
##
## 尾兽大招和角色大招的结算规则逐条相同：有冷却、有落点、有施法延迟、
## 按半径圈人、按 [PBAimRules] 挑地方。**唯一的区别是它没有普攻。**
##
## 而「没有普攻」在 [PBAttacker] 里已经是可表达的 —— `dps = 0`，
## 每 tick 打 0 点伤害，[method PBStrikeRules._strike_single] 直接空转返回。
## 单开一个类型的话，落点选择、施法延迟、冷却结算都要抄第二份，
## 而 §09 的功能档落地时还要抄第三份 —— 三份的落点判定迟早对不上，
## 且对不上的表现是「大招偶尔打空」，从现象反推极难。
##
## 这个选择还顺带买到一件事：[method PBValuation.leak_threshold_dps] 的
## 悬崖二分**自动把尾兽算进去**。它按 `dps / 总输出` 缩放每个攻击者，
## 尾兽那一项的比例是 0（普攻没有），而大招按 `ultimate_damage / 总输出`
## 单独缩 —— 正好是想要的语义：队伍越强，尾兽那一发也越重。
##
## [param team_dps] 是这一波全队的普攻总输出，尾兽大招的伤害以它计量
## （见 [member PBBeast.ultimate_damage_seconds]）。
##
## [param pending_cooldown_ticks] 是**上一波打完时还欠的冷却**。尾兽的 75 秒
## 冷却比单波（约 16 秒）长四五倍，不跨波带的话它每波都放得出来，
## §11 那句「必须选择在哪一波交底牌」就没有对象了 ——
## 见 [member PBSkill.carry_over_ticks]。
static func build_ultimate_attacker(
	beast: PBBeast,
	level: int,
	team_dps: float,
	wave_element: PBElement.Type,
	cfg: PBSimConfig,
	pending_cooldown_ticks: int = 0
) -> PBAttacker:
	if beast == null or not beast.has_ultimate():
		return null
	var scale: float = level_scale(level, cfg)
	var seconds: float = beast.ultimate_cooldown_seconds
	if seconds <= 0.0:
		seconds = cfg.beast_ultimate_cooldown_seconds

	var skill := PBSkill.new()
	skill.element = _ultimate_element(beast)
	skill.damage = (
		team_dps * beast.ultimate_damage_seconds * scale * _element_mult(beast, wave_element, cfg)
	)
	# 半径为 0 = 「打全场」，所以要的是**对角**而不是长度 ——
	# 二维之后用长度的话罩不到角落（见 [method PBSimConfig.field_diagonal]）。
	skill.radius = beast.ultimate_radius if beast.ultimate_radius > 0.0 else cfg.field_diagonal()
	# 频率也吃等级：零伤害的机制型尾兽靠这一条才有升级曲线，见本类顶部。
	skill.cooldown_ticks = maxi(int(round(seconds / scale * float(cfg.tick_rate))), 1)
	skill.delay_ticks = int(round(cfg.ultimate_delay_seconds * float(cfg.tick_rate)))
	skill.max_targets = beast.ultimate_max_targets
	skill.gather = beast.ultimate_gather
	skill.knockback = beast.ultimate_knockback
	skill.slow_scale = beast.ultimate_slow_scale
	skill.slow_ticks = int(round(beast.ultimate_slow_seconds * float(cfg.tick_rate)))
	skill.team_damage_scale = beast.ultimate_team_damage_scale
	skill.buff_ticks = int(round(beast.ultimate_buff_seconds * float(cfg.tick_rate)))
	skill.reset_cooldowns = beast.ultimate_reset_cooldowns
	skill.carry_over_ticks = maxi(pending_cooldown_ticks, 0)

	var attacker := PBAttacker.new()
	attacker.slot = BEAST_SLOT
	attacker.dps = 0.0
	# 尾兽没有本体：站在基地上、够得着全场、不挨打（`max_hp` 恒为 0）。
	attacker.pos = Vector2.ZERO
	attacker.reach = cfg.field_diagonal()
	attacker.ultimate = PBSkillCast.new(skill)
	return attacker


## 一批攻击者里尾兽的那个。没带尾兽返回 null。
##
## 靠 [constant BEAST_SLOT] 认人而不是靠「最后一个」——
## §09 的功能档进来之后攻击者列表还会加东西，位置约定迟早会被打破，
## 而打破的表现是「尾兽的冷却记到了某个角色头上」，不报任何错。
static func attacker_in(attackers: Array[PBAttacker]) -> PBAttacker:
	for attacker: PBAttacker in attackers:
		if attacker.slot == BEAST_SLOT:
			return attacker
	return null


## 大招打什么属性。不限属性的按物理算 —— 那只是给渲染层一个显示用的值，
## 真正的克制倍率已经由 [method _element_mult] 乘进 [member PBSkill.damage] 了。
static func _ultimate_element(beast: PBBeast) -> PBElement.Type:
	if beast.ultimate_element == PBBeast.ANY_ELEMENT:
		return PBElement.Type.PHYSICAL
	return beast.ultimate_element as PBElement.Type


## 大招吃到的属性倍率。不限属性的恒为 1.0（**中性，不是物理的 1.05**）——
## 尾兽不在 §03 的克制环里，给它 1.05 等于让它凭空强 5%。
static func _element_mult(beast: PBBeast, wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	if beast.ultimate_element == PBBeast.ANY_ELEMENT:
		return 1.0
	var rel := PBElement.relation(beast.ultimate_element as PBElement.Type, wave_element)
	return cfg.damage_multiplier(rel)
