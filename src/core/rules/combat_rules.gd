class_name PBCombatRules
extends RefCounted
## 单波战斗的建人与结算（§03 的伤害系数 + §04 的波次参数）。
##
## ## [method resolve] 是解析式排队模型，不是真战斗
##
## 敌人按出场顺序排队，队伍以固定 DPS 推进，每个敌人要么被清掉、要么漏过去扣基地血。
## 真游戏走 [PBBattleSim]；这个模型留着当**对拍锚点**（[method PBAttacker.whole_field]
## 那条退化路径必须与它逐位相同）。它的前提：AOE 与单体无区别、没有波内动态、
## 敌人不还手 —— 用它的结论时要记得。


## 结算一波。
##
## [param dps] 是己方对本波的**有效**每秒伤害，属性克制已经算进去了
## （见 [method team_dps]）。[param def_reduction] 是防御科技的减伤比例，0–1。
static func resolve(
	wave: PBWave, dps: float, def_reduction: float, cfg: PBSimConfig
) -> PBCombatOutcome:
	var out := PBCombatOutcome.new()
	var leak_mult: float = cfg.boss_leak_mult if wave.is_boss() else 1.0
	var leak_damage: float = wave.atk_each * leak_mult * (1.0 - clampf(def_reduction, 0.0, 0.95))

	# DPS 为零是合法状态（全员派去做任务、或阵容全被克到近乎无伤）。
	# 不当成除零错误处理 —— 它就是「这波全漏」，是玩家真会遇到的局面。
	if dps <= 0.0:
		out.cleared = false
		out.leaked = wave.count
		out.base_damage = leak_damage * float(wave.count)
		out.battle_seconds = _spawn_time(wave.count - 1, wave.count, cfg) + cfg.march_seconds
		out.ticks = _to_ticks(out.battle_seconds, cfg)
		return out

	var seconds_per_kill: float = wave.hp_each / dps
	var clock: float = 0.0

	for i: int in wave.count:
		var spawned_at: float = _spawn_time(i, wave.count, cfg)
		var arrives_at: float = spawned_at + cfg.march_seconds
		# 打不了还没出场的敌人。
		clock = maxf(clock, spawned_at)
		var would_die_at: float = clock + seconds_per_kill

		if would_die_at <= arrives_at:
			out.kills += 1
			clock = would_die_at
		else:
			# 它跑掉了。已经砸在它身上的伤害是沉没成本，
			# 而且我们要等到它离场才能接着打下一个。
			out.leaked += 1
			out.base_damage += leak_damage
			clock = arrives_at

	out.cleared = out.leaked == 0
	out.battle_seconds = clock
	out.ticks = _to_ticks(clock, cfg)
	# 时长对齐到 tick 之后再报出去，与真 tick 模拟可比。
	out.battle_seconds = float(out.ticks) / float(cfg.tick_rate)
	return out


## 一队单位对某一波的有效 DPS，属性克制、羁绊、尾兽光环与词条（装备、训练）全部计入。
##
## §03 成立与否的支点：只有 [param deployed] 里真的换上了克制系单位，倍率才吃得到。
## [param equip_mults] 是逐人倍率（[method unit_multipliers]），[param equip_mods]
## 是逐人词条（[method unit_mods]），都与 [param deployed] 同序，空数组 = 没有。
static func team_dps(
	deployed: Array[PBUnit],
	wave_element: PBElement.Type,
	bond_mult: float,
	equip_mults: PackedFloat64Array,
	cfg: PBSimConfig,
	equip_mods: Array[Dictionary] = []
) -> float:
	var mult: float = bond_mult
	var total: float = 0.0
	for i: int in deployed.size():
		var equip: float = equip_mults[i] if i < equip_mults.size() else 1.0
		var mods: Dictionary = equip_mods[i] if i < equip_mods.size() else {}
		total += deployed[i].effective_power(wave_element, cfg, mods) * equip
	return total * mult


## 逐人的乘算加成（今天只有尾兽光环那一份，[member PBBeast.aura_power]）。与 [param units] 同序。
##
## 折叠只在这里做一次：调用点有四处（战斗、估值两处、任务卡预览），各写一份的话
## 漏改一处的表现是那条路径上战力略低，从现象反推几乎不可能。
## 它和 [method unit_mods] 是两条腿，四处都要拿 —— `tests/test_equip_manual.gd`
## 有一条扫描式断言钉着两者的出现次数相等。
static func unit_multipliers(
	units: Array[PBUnit], state: PBRunState, cfg: PBSimConfig
) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(units.size())
	out.fill(1.0)
	var beast := PBBeastRules.beast_of(state, cfg)
	if beast == null:
		return out
	var aura := PBBeastRules.unit_multipliers(units, beast, state.beast_level, cfg)
	for i: int in units.size():
		out[i] = aura[i] if i < aura.size() else 1.0
	return out


## 把上场名单摊成一组 [PBAttacker]，交给 [PBBattleSim] 逐 tick 推。
##
## 每个攻击者的 `dps` 就是 [method team_dps] 那个求和的一项 ——
## 界面上报的战力和这批对象必须同源，`test_attacker.gd` 锁着这个恒等式。
##
## 站哪一列来自射程档（[method PBCharacter.reach_tier]），打多远来自角色自己的原版射程
## （[method PBSimConfig.reach_of]，换算比例在配置里）。
##
## **尾兽**：带了就在末尾多挂一个 `dps = 0` 的攻击者，只有大招。它的伤害以
## 「全队几秒输出」计量，分母只有全部角色摊开之后才知道。
##
## **羁绊功能档**：[param bond_functions] 是 [method PBBondRules.active_functions] 的结果，
## 装在已经建好的大招上（[method PBBondFunctionRules.apply_to_skill]）。
##
## > 参数已经很多。**再加一种加成时别接新参数**，该把「队伍这一波的全部加成」折成一个对象了。
static func build_attackers(
	deployed: Array[PBUnit],
	wave_element: PBElement.Type,
	bond_mult: float,
	equip_mults: PackedFloat64Array,
	cfg: PBSimConfig,
	beast: PBBeast = null,
	beast_level: int = 1,
	beast_cooldown_ticks: int = 0,
	bond_functions: Dictionary = {},
	bond_passives: Dictionary = {},
	bond_skill_patches: Dictionary = {},
	equip_mods: Array[Dictionary] = []
) -> Array[PBAttacker]:
	var team_mult: float = bond_mult
	var out: Array[PBAttacker] = []
	# 召唤物的位子开波就留好（理由见 [PBSummonRules] 顶部）。没有召唤技能就一个不留。
	var spare: int = PBSummonRules.reserve(deployed, cfg, bond_skill_patches)
	out.resize(deployed.size() + spare)
	# 带聚拢大招的名额按出战席顺序发前 n 个。**按比例而不是按角色表**，
	# 理由见 [member PBSimConfig.ultimate_gather_share]。
	var gather_count: int = int(
		round(clampf(cfg.ultimate_gather_share, 0.0, 1.0) * float(deployed.size()))
	)
	var cd_scale: float = PBBeastRules.ultimate_cd_scale(beast)
	# 尾兽光环按等级折算一次就够了 —— 放进循环里等于每个人重算一遍同一个数。
	var beast_aura: Dictionary = PBBeastRules.aura_passives(beast, beast_level, cfg)
	for i: int in deployed.size():
		var unit: PBUnit = deployed[i]
		var tier := unit.character.reach_tier()
		# 装备是逐人的：这个人吃到几件、吃不吃得下，由 [PBEquipRules] 分配。
		var mult: float = team_mult * (equip_mults[i] if i < equip_mults.size() else 1.0)
		var attacker := PBAttacker.new()
		attacker.slot = i
		# **属性词条先收齐**：三围、攻击力、防御、生命、攻速必须在 [method PBStatRules.of]
		# 里面注入（二级属性从一级派生，攻击力要吃克制）。行为那一档走下面的
		# [method PBPassiveRules.equip]。装备和训练科技的词条在 `worn` 里。
		var worn: Dictionary = equip_mods[i] if i < equip_mods.size() else {}
		var stat_mods: Dictionary = (
			PBStatRules
			. collect(
				[
					unit.character.passives,
					bond_passives.get(unit.character.id, {}) as Dictionary,
					beast_aura,
					worn,
				]
			)
		)
		# **一发多重**：战斗真正用的是这个数，见 [member PBAttacker.attack]。
		attacker.attack = unit.effective_attack(wave_element, cfg, stat_mods) * mult
		# 每秒多少：从此只是统计量与退化路径的输入。**这一行一个字没动** ——
		# 面板、估值、解析模型读到的仍是它一直以来的那个数。
		attacker.dps = unit.effective_power(wave_element, cfg) * mult
		# 挨打这一半。**血与防不吃 `mult`**：队伍倍率是进攻向的，防守加成走词条。
		var stats := unit.stats(cfg, stat_mods)
		attacker.attribute_profile = PBAttributeProfile.make(
			unit, stat_mods, stats, wave_element, mult
		)
		attacker.base_attack = stats.base_atk
		attacker.ranged_attack = tier != PBCharacter.Reach.MELEE
		attacker.max_hp = stats.hp
		attacker.damage_attributes = {
			&"strength": stats.strength,
			&"agility": stats.agility,
			&"intellect": stats.intellect,
			&"attack": stats.atk,
			&"max_hp": stats.hp
		}
		attacker.ninjutsu_attack = (
			stats.intellect
			* cfg.damage_multiplier(PBElement.relation(unit.element, wave_element))
			* mult
		)
		attacker.defence = stats.def
		attacker.def_element = unit.def_element
		attacker.attack_element = unit.element
		# 蓝：智力抬池子，回速按池子的比例走。
		attacker.max_mp = stats.mp
		attacker.mp_regen = stats.mp * cfg.mp_regen_rate / float(cfg.tick_rate)
		attacker.reach = cfg.reach_of(unit.character)
		# 站位：x 由射程档派生（§02），y 是泳道，玩家拖动过的由 [PBFormationRules] 覆盖。
		attacker.pos = Vector2(cfg.reach_column(tier), cfg.ally_lane(i, deployed.size()))
		# 跑动：站位是「从哪一列出发」，皮带绳默认不拴（见 [member PBSimConfig.unit_leash]）。
		attacker.home = attacker.pos
		attacker.leash = cfg.leash_distance()
		attacker.move_speed = (
			cfg.field_length / maxf(cfg.unit_move_seconds * float(cfg.tick_rate), 1.0)
		)
		attacker.shape = unit.character.attack_shape
		attacker.max_targets = cfg.aoe_max_targets
		# 出手节奏：间隔由攻速决定，见 [method PBAttacker.prime]。
		attacker.attack_speed = stats.attack_speed
		# 近战不发子弹（接触即伤），五系远程才有弹道。
		attacker.shot_speed = (
			0.0
			if tier == PBCharacter.Reach.MELEE
			else cfg.field_length / maxf(cfg.projectile_cross_seconds * float(cfg.tick_rate), 1.0)
		)
		var skill := _build_skill(unit, wave_element, mult, i < gather_count, cfg, stats)
		# 羁绊功能档里装在大招上的那一半（一组只出一个载体）。
		# 装在本人身上的那一半必须在这个循环里 —— 只有这里知道这个攻击者是哪个角色。
		for key: StringName in bond_functions.get(unit.character.id, []) as Array:
			PBBondFunctionRules.apply_to_skill(skill, key, cfg)
		# 行为词条：角色自带 / 羁绊成员效果 / 尾兽光环 / 装备，**走同一个入口**、在字段上 `+=` 汇合。
		# 走 `equip` 不走几行 `grant_all`：率型键装完还要折算，见 [method PBPassiveRules.equip]。
		(
			PBPassiveRules
			. equip(
				attacker,
				[
					unit.character.passives,
					bond_passives.get(unit.character.id, {}) as Dictionary,
					beast_aura,
					worn,
				]
			)
		)
		# 名册「被动」列里 `on_hit=<效果键>` 那一半。这份是定义，直接共用引用。
		PBAttackRangeRules.apply(attacker, cfg)
		attacker.on_hit_buffs = unit.character.on_hit_buffs
		# `on_low_hp=<效果键>` 那一半，同上。阈值（`low_hp`）已经跟着被动表装上了。
		attacker.low_hp_buffs = unit.character.low_hp_buffs
		attacker.lethal_buffs = unit.character.lethal_buffs
		attacker.struck_buffs = unit.character.struck_buffs
		attacker.attack_buffs = unit.character.attack_buffs
		# 尾兽的「团队回蓝 +25%」在没有蓝条的模型里只剩一个可观测后果：
		# 大招放得更勤。所以它落在这里，而不是另开一条资源。
		skill.cooldown_ticks = maxi(int(round(float(skill.cooldown_ticks) * cd_scale)), 1)
		# 等级跟着进来（决策 7）：技能挂出去的效果按施法者等级缩放，
		# 而 [PBAttacker] 身上没有也不该有 `level` —— 见
		# [member PBSkillCast.caster_level]。
		attacker.ultimate = PBSkillCast.new(skill, unit.level)
		_equip_skills(
			attacker,
			unit,
			wave_element,
			mult,
			cfg,
			bond_skill_patches.get(unit.character.id, {}),
			stats
		)
		out[i] = attacker

	# 预留那几个先空着 —— 它们要等本体放技能才站上来。
	for i: int in spare:
		var spot := PBAttacker.new()
		spot.slot = deployed.size() + i
		spot.summoned = true
		PBSummonRules.dismiss(spot)
		out[deployed.size() + i] = spot

	# 全队光环**排在循环外面**：它是这一组羁绊给的，放进循环的话载体之前建好的人拿不到。
	PBBondFunctionRules.apply_to_team(out, bond_functions)

	var beast_attacker := PBBeastRules.build_ultimate_attacker(
		beast, beast_level, total_dps(out), wave_element, cfg, beast_cooldown_ticks
	)
	if beast_attacker != null:
		out.append(beast_attacker)
	return out


## 把角色表里那几个技能挂到攻击者身上，**每人一份自己的拷贝**。
##
## 共享 `data/` 那一份的话，两个人的冷却是同一个，悬崖二分就地改伤害也会污染正在打的那一份。
## 拷贝之后当场用 [method skill_damage] 算出 [member PBSkill.damage] —— 同一个技能
## 在不同的人、不同的波次下是不同的数。
##
## **查不到就跳过，而且要报错**：拼错 id 的表现是指令卡少一格，看起来和「他本来就只有一个」一样。
## 超过两个只取前两个：指令卡只画得下两格（[constant PBCommandCard.SKILL_COMMANDS]）。
static func _equip_skills(
	attacker: PBAttacker,
	unit: PBUnit,
	wave_element: PBElement.Type,
	mult: float,
	cfg: PBSimConfig,
	patches: Dictionary = {},
	stats: PBStats = null
) -> void:
	if cfg.skills == null:
		return
	for id: StringName in unit.character.skill_ids:
		if attacker.skills.size() >= PBCharacter.MAX_SKILLS:
			push_error("这个角色配了超过 %d 个技能，多出来的放不出去" % PBCharacter.MAX_SKILLS)
			return
		var skill: PBSkill = cfg.skills.by_id(id)
		if skill == null:
			push_error("角色表里点了一个不存在的技能：%s" % id)
			continue
		# **补丁打在复制品上**，而且**排在伤害换算之前**：`power_scale` 改的就是换算要用的倍率。
		var mine := PBSkillVariantRules.prepare(skill, patches.get(id, {}), cfg, unit.level)
		mine.kind = PBDamageKind.skill_kind(unit.element)
		mine.damage = skill_damage(unit, mine, wave_element, mult, cfg, stats)
		if mine.recast != null:
			mine.recast.kind = mine.kind
			mine.recast.damage = skill_damage(unit, mine.recast, wave_element, mult, cfg, stats)
		if mine.followup_enabled:
			mine.followup = cfg.skills.by_id(mine.followup_id).clone()
			mine.followup.kind = mine.kind
			mine.followup.damage = skill_damage(unit, mine.followup, wave_element, mult, cfg, stats)
		if PBSkillDamage.stat_of(mine) == &"attack":
			mine.attack_formula_scale = (
				mine.power_mult
				* mult
				* cfg.damage_multiplier(PBElement.relation(mine.element, wave_element))
			)
		# 被动已经在这之前装好了（[method PBPassiveRules.equip]），治疗倍率跟着写到这一份上。
		var values: PBStats = unit.stats(cfg) if stats == null else stats
		mine.first_cast_damage = (
			values.atk
			* mine.first_cast_attack
			* mult
			* cfg.damage_multiplier(PBElement.relation(mine.element, wave_element))
		)
		mine.heal_scale = 1.0 + attacker.heal_power
		attacker.skills.append(PBSkillCast.new(mine, unit.level))
	_equip_death_casts(attacker, unit, wave_element, mult, cfg, patches, stats)
	PBOnAttackRules.equip(attacker, unit, wave_element, mult, cfg, patches, stats)


## 羁绊补丁 `on_death` 点到的技能装进 [member PBAttacker.death_casts]。**不进指令卡**，所以不占
## [constant PBCharacter.MAX_SKILLS]，也不要求在他的技能表里。伤害换算和普通技能同一句。
static func _equip_death_casts(
	attacker: PBAttacker,
	unit: PBUnit,
	wave_element: PBElement.Type,
	mult: float,
	cfg: PBSimConfig,
	patches: Dictionary,
	stats: PBStats = null
) -> void:
	attacker.death_casts.clear()
	for id: StringName in patches:
		if not (patches[id] as Dictionary).has(PBSkillPatchRules.ON_DEATH):
			continue
		var skill: PBSkill = cfg.skills.by_id(id)
		if skill == null:
			push_error("羁绊补丁点了一个不存在的阵亡技能：%s" % id)
			continue
		var mine := skill.clone()
		mine.kind = PBDamageKind.skill_kind(unit.element)
		PBSkillPatchRules.apply(mine, patches[id], cfg.tick_rate)
		mine.damage = skill_damage(unit, mine, wave_element, mult, cfg, stats)
		mine.heal_scale = 1.0 + attacker.heal_power
		attacker.death_casts.append(PBSkillCast.new(mine, unit.level))


## 造一个单位这一波的大招（§02）。
## **克制按大招自己的属性算，不按单位的**（铁律 4：element 挂在伤害事件上）。
static func _build_skill(
	unit: PBUnit,
	wave_element: PBElement.Type,
	mult: float,
	gather: bool,
	cfg: PBSimConfig,
	stats: PBStats = null
) -> PBSkill:
	var skill := PBSkill.new()
	skill.element = unit.character.ultimate_element()
	skill.kind = PBDamageKind.skill_kind(unit.element)
	skill.power_mult = cfg.ultimate_power_mult
	skill.damage = skill_damage(unit, skill, wave_element, mult, cfg, stats)
	skill.radius = cfg.ultimate_radius
	skill.cooldown_ticks = int(round(cfg.ultimate_cooldown_seconds * float(cfg.tick_rate)))
	skill.delay_ticks = int(round(cfg.ultimate_delay_seconds * float(cfg.tick_rate)))
	skill.mp_cost = cfg.ultimate_mp_cost
	skill.gather = gather
	return skill


## 每个上场单位**从局面上**吃到的词条：装备 + 训练科技。与 [param units] 同序。
##
## 和 [method unit_multipliers] 是两条腿，四个调用点两条都要拿。
## 这是唯一一个手上有 [PBRunState] 又已经接到全部折叠点的地方，局面给的词条都并在这里。
static func unit_mods(
	units: Array[PBUnit], state: PBRunState, cfg: PBSimConfig, preview: bool = false
) -> Array[Dictionary]:
	var out := PBEquipRules.unit_mods(units, state.equip_parts, cfg, state.equipped)
	if state.training.is_empty():
		return out
	var passives := PBBondRules.active_passives(state.bonded_units(cfg, preview), units, cfg.bonds)
	for i: int in units.size():
		var own: Dictionary = passives.get(units[i].character.id, {})
		var ranged: bool = (
			float(own.get(PBPassiveRules.RANGED_RANGE, 0.0)) > 0.0
			or float(out[i].get(PBPassiveRules.RANGED_RANGE, 0.0)) > 0.0
			or float(units[i].character.passives.get(PBPassiveRules.RANGED_RANGE, 0.0)) > 0.0
		)
		var trained := PBTechRules.unit_mods(units[i], state.training, ranged)
		for key: StringName in trained:
			out[i][key] = float(out[i].get(key, 0.0)) + float(trained[key])
	return out


## 一发技能打多少。**大招和角色技能共用这一句**：
## `（等级基数 + 属性 × 系数）× 技能属性克制 × 队伍倍率`。
##
## 只能有一处：技能伤害写成 `.tres` 里的字面量的话，克制、羁绊对技能一律不生效，
## 而且它不随波次涨（见 [member PBSkill.power_mult]）。
## **克制按技能自己的属性算**（铁律 4）。[param mult] 是队伍倍率（羁绊 × 尾兽光环）。
static func skill_damage(
	unit: PBUnit,
	skill: PBSkill,
	wave_element: PBElement.Type,
	mult: float,
	cfg: PBSimConfig,
	stats: PBStats = null
) -> float:
	var rel := PBElement.relation(skill.element, wave_element)
	var values: PBStats = unit.stats(cfg) if stats == null else stats
	return PBSkillDamage.raw(skill, values, unit.level) * cfg.damage_multiplier(rel) * mult


## 一组攻击者的 DPS 之和 —— 也就是对外报的「队伍战力」。
##
## 报数走这里而不是再调一次 [method team_dps]，是为了让两者**不可能**分叉：
## 界面上的数就是战场上真会打出来的伤害，因为它是同一批对象加出来的。
static func total_dps(attackers: Array[PBAttacker]) -> float:
	var total: float = 0.0
	for attacker: PBAttacker in attackers:
		total += attacker.dps
	return total


## 第 [param index] 个敌人的出场时刻（秒）。整波在 `spawn_window` 内均匀出完。
static func _spawn_time(index: int, count: int, cfg: PBSimConfig) -> float:
	if count <= 1:
		return 0.0
	return cfg.spawn_window * float(index) / float(count - 1)


static func _to_ticks(seconds: float, cfg: PBSimConfig) -> int:
	return int(ceil(seconds * float(cfg.tick_rate)))
