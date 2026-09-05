class_name PBCombatRules
extends RefCounted
## 单波战斗的结算。施工策划案 §03 的伤害系数 + §04 的波次参数。
##
## ## 这是一个解析式近似，不是真战斗
##
## M-1 要跑上万局来校准 `GROWTH`，逐单位逐 tick 模拟跑不动
## （48 单位 × 800 tick × 120 波 × 上万局 ≈ 千亿次更新）。
## 所以这里用一个**排队模型**代替：敌人按出场顺序排队，队伍以固定 DPS 推进，
## 每个敌人要么在抵达基地前被清掉，要么漏过去扣基地血。
##
## 时长仍然对齐到整 tick（§14 铁律：定帧 20 tick/s），
## 这样 M0 换成真 tick 模拟时两边的数字可以直接对照。
##
## ## 这个近似丢掉了什么（用到结论时要记得）
##
## 1. **AOE 与单体输出没有区别** —— 队列是单目标的。所以 §04 那条验收
##    「纯 AOE 阵容在精英波吃力、纯单体在潮水波吃力」**M-1 回答不了，留给 M0**。
##    路线图列的四个问题都不依赖它，是有意的取舍。
## 2. **没有波内动态** —— 前排先死导致输出下降、聚拢大招把敌人拖成一堆，
##    这些都不在模型里。
## 3. **敌人不还手** —— 只有漏怪才伤基地，己方单位不会被打死。


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
	# 时长对齐到 tick 之后再报出去，保证与 M0 的真 tick 模拟可比。
	out.battle_seconds = float(out.ticks) / float(cfg.tick_rate)
	return out


## 一队单位对某一波的有效 DPS，属性克制、攻击科技、羁绊加成全部计入。
##
## 这个求和是 §03 成立与否的支点：只有当 [param deployed] 里真的换上了
## 克制系单位，2.0 的倍率才吃得到。全员固定上场的五系阵容平均只有 1.10，
## 和物理的 1.05 几乎没差别。
## [param equip_mults] 是**逐人**的装备倍率（与 [param deployed] 同序）。
## 空数组表示没有装备，全员按 1.0 算。
##
## M3-c 之前这里是一个全队标量 —— §10 的分类匹配（法术装挂不上物理角色）
## 在标量里表达不出来，而装备对 §03 属性系统的稀释正来自那个「对谁都一样有用」。
static func team_dps(
	deployed: Array[PBUnit],
	wave_element: PBElement.Type,
	atk_tech_mult: float,
	bond_mult: float,
	equip_mults: PackedFloat64Array,
	cfg: PBSimConfig
) -> float:
	var mult: float = atk_tech_mult * bond_mult
	var total: float = 0.0
	for i: int in deployed.size():
		var equip: float = equip_mults[i] if i < equip_mults.size() else 1.0
		total += deployed[i].effective_power(wave_element, cfg) * equip
	return total * mult


## 逐人的**全部**乘算加成：装备（§10）× 尾兽光环（§11）。与 [param units] 同序。
##
## ## 为什么要有这么一层
##
## [method team_dps] 和 [method build_attackers] 都收一个逐人倍率数组，
## 而调用它们的地方有四处（战斗、估值两处、任务卡预览）。
## M3-c 时那四处各写着同一句 `PBEquipRules.unit_multipliers(...)`；
## M3-d 加了尾兽光环，四处就要各自改成「装备 × 尾兽」。
##
## **漏改一处不会报错**，只会让那条路径上的战力比实际低一点 ——
## 而那四处里有两处是估值，估值偏低的表现是「会算账的玩家做出略差的选择」，
## 从现象反推几乎不可能。所以折叠只做一次，加第三种加成时也只改这里。
static func unit_multipliers(
	units: Array[PBUnit], state: PBRunState, cfg: PBSimConfig
) -> PackedFloat64Array:
	var equip := PBEquipRules.unit_multipliers(units, state.equip_parts, cfg, state.equipped)
	var beast := PBBeastRules.beast_of(state, cfg)
	if beast == null:
		return equip
	var aura := PBBeastRules.unit_multipliers(units, beast, state.beast_level, cfg)
	var out := PackedFloat64Array()
	out.resize(units.size())
	for i: int in units.size():
		var equip_mult: float = equip[i] if i < equip.size() else 1.0
		var aura_mult: float = aura[i] if i < aura.size() else 1.0
		out[i] = equip_mult * aura_mult
	return out


## 把上场名单摊成一组 [PBAttacker]，交给 [PBBattleSim] 逐 tick 推。
##
## **和 [method team_dps] 必须是同一套算法的两种输出**：这里每个攻击者的
## `dps` 就是那个求和的一项，两者只差浮点结合律。分成两份各写一遍的话，
## 「界面上报的战力」和「战场上真打出来的伤害」会慢慢分叉，且不报任何错 ——
## `test_battle_sim.gd` 里有一条断言把这个恒等式锁住。
##
## 射程与站位来自角色（[method PBCharacter.reach_tier]），
## 具体距离来自配置（[method PBSimConfig.reach_distance]）——
## 角色表说「这是个远程」，配置说「远程能打多远」，两件事分开才扫得动。
##
## ## 尾兽（M3-d）
##
## 带了尾兽就在末尾**多挂一个 `dps = 0` 的攻击者**，它只有大招。
## 挂在这里而不是让 [PBBattleSim] 自己去查尾兽表，是因为尾兽大招的伤害
## 以「全队几秒输出」计量（[member PBBeast.ultimate_damage_seconds]），
## 而那个分母只有在全部角色都摊开之后才知道 —— 正是本函数的返回值。
##
## ## 羁绊功能档（M3-f）
##
## [param bond_functions] 是 [method PBBondRules.active_functions] 的结果，
## `{ 载体角色 id: [功能键…] }`。功能装在**已经建好的**大招上，
## 理由见 [method PBBondFunctionRules.apply_to_skill]。
##
## > 本函数已经到了 `.gdlintrc` 的参数上限（10 个）。**再加一种加成时
## > 不要接第 11 个参数**，该把「队伍这一波的全部加成」折成一个对象了 ——
## > 现在还没折，是因为九个参数里有六个是从 M-1 就在的原始量，
## > 硬折会让一次数据结构改动混进一次功能改动里。
static func build_attackers(
	deployed: Array[PBUnit],
	wave_element: PBElement.Type,
	atk_tech_mult: float,
	bond_mult: float,
	equip_mults: PackedFloat64Array,
	cfg: PBSimConfig,
	beast: PBBeast = null,
	beast_level: int = 1,
	beast_cooldown_ticks: int = 0,
	bond_functions: Dictionary = {}
) -> Array[PBAttacker]:
	var team_mult: float = atk_tech_mult * bond_mult
	var out: Array[PBAttacker] = []
	out.resize(deployed.size())
	# 带聚拢大招的名额按出战席顺序发前 n 个。**按比例而不是按角色表**，
	# 理由见 [member PBSimConfig.ultimate_gather_share]。
	var gather_count: int = int(
		round(clampf(cfg.ultimate_gather_share, 0.0, 1.0) * float(deployed.size()))
	)
	var cd_scale: float = PBBeastRules.ultimate_cd_scale(beast)
	for i: int in deployed.size():
		var unit: PBUnit = deployed[i]
		var tier := unit.character.reach_tier()
		# 装备是逐人的：这个人吃到几件、吃不吃得下，由 [PBEquipRules] 分配。
		var mult: float = team_mult * (equip_mults[i] if i < equip_mults.size() else 1.0)
		var attacker := PBAttacker.new()
		attacker.slot = i
		attacker.dps = unit.effective_power(wave_element, cfg) * mult
		# 挨打这一半（§03A，M3.5-b）。**血与防不吃 `mult`** ——
		# 装备、羁绊、尾兽光环目前全是进攻向的，把它们乘到防守上
		# 等于凭空发明一份没人设计过的加成。§10 的两件防御装
		# 和 §11 一尾的减伤光环接上来时，那才是它们的落点。
		var stats := unit.stats(cfg)
		attacker.max_hp = stats.hp
		attacker.defence = stats.def
		attacker.def_element = unit.def_element
		# 蓝（M3.5-d）：智力抬池子，回速按池子的比例走 —— 所以它同时抬两样。
		attacker.max_mp = stats.mp
		attacker.mp_regen = stats.mp * cfg.mp_regen_rate / float(cfg.tick_rate)
		attacker.reach = cfg.reach_distance(tier)
		# 站位：x 由射程档派生（§02），y 是泳道 —— **M4-a 之前没有 y**，
		# 纵向是渲染层自己编的。默认均分，M4-f 之后由玩家拖动决定。
		attacker.pos = Vector2(cfg.reach_column(tier), cfg.ally_lane(i, deployed.size()))
		# 跑动（M3.5-c）：站位从「站在哪一列」变成「从哪一列出发」。
		# 皮带绳把前压拴在自己那一列附近 —— 放开的话所有人挤到最前面接敌，
		# §02 的射程梯度（「场上稳定有人」的唯一来源）就没了。
		attacker.home = attacker.pos
		attacker.leash = cfg.unit_leash
		attacker.move_speed = cfg.field_length / maxf(
			cfg.unit_move_seconds * float(cfg.tick_rate), 1.0
		)
		attacker.shape = unit.character.attack_shape
		attacker.max_targets = cfg.aoe_max_targets
		# 出手节奏与子弹（M4-b）。**攻速第一次被战斗读到** ——
		# 在这之前它只进 `dps = atk × 攻速` 这个乘积，信息栏上写着
		# 「攻速 1.11」而战斗里是一条没有边界的连续伤害流。
		attacker.attack_speed = stats.attack_speed
		# 近战不发子弹（接触即伤），五系远程才有弹道。
		attacker.shot_speed = (
			0.0
			if tier == PBCharacter.Reach.MELEE
			else cfg.field_length / maxf(
				cfg.projectile_cross_seconds * float(cfg.tick_rate), 1.0
			)
		)
		var skill := _build_skill(unit, wave_element, mult, i < gather_count, cfg)
		# 羁绊功能档（§09，M3-f）：这个人是不是某组凑满了的羁绊的载体。
		for key: StringName in bond_functions.get(unit.character.id, []) as Array:
			PBBondFunctionRules.apply_to_skill(skill, key, cfg)
		# 尾兽的「团队回蓝 +25%」在没有蓝条的模型里只剩一个可观测后果：
		# 大招放得更勤。所以它落在这里，而不是另开一条资源。
		skill.cooldown_ticks = maxi(int(round(float(skill.cooldown_ticks) * cd_scale)), 1)
		# 等级跟着进来（决策 7）：技能挂出去的效果按施法者等级缩放，
		# 而 [PBAttacker] 身上没有也不该有 `level` —— 见
		# [member PBSkillCast.caster_level]。
		attacker.ultimate = PBSkillCast.new(skill, unit.level)
		_equip_skills(attacker, unit, cfg)
		out[i] = attacker

	var beast_attacker := PBBeastRules.build_ultimate_attacker(
		beast, beast_level, total_dps(out), wave_element, cfg, beast_cooldown_ticks
	)
	if beast_attacker != null:
		out.append(beast_attacker)
	return out


## 把角色表里那几个技能挂到攻击者身上（决策 6，M7-g）。
##
## ## 每人一份自己的拷贝，不共享 `data/` 里那一份
##
## [PBSkillCast] 会记冷却与落点，共享的话两个人的冷却是同一个 ——
## 而 [method PBSkill.clone] 顶上还有一条更硬的：悬崖二分要能就地改伤害
## （[method PBValuation._leaks_at]），共享会污染正在真正战斗的那一份。
##
## ## 查不到就跳过，而且要报错
##
## 拼错一个 id 的表现是「这个角色少了一个技能」—— 指令卡上少一格，
## 而少的那一格看起来和「他本来就只有一个技能」一模一样。
## 静默跳过的话没有任何地方说得出发生过什么。
##
## 超过两个也只取前两个（决策 6）：指令卡那一行只画得下两格
## （[constant PBCommandCard.SKILL_COMMANDS]），多出来的放不出去 ——
## 而「配了却放不出」比「没配」更难查。
static func _equip_skills(attacker: PBAttacker, unit: PBUnit, cfg: PBSimConfig) -> void:
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
		attacker.skills.append(PBSkillCast.new(skill.clone(), unit.level))


## 造一个单位这一波的大招（§02，M3-b）。
##
## **伤害按大招自己的属性算克制，不按单位的**（§03 铁律 4：element 挂在
## 伤害事件上）。所以「本体土属性、大招火系」的角色，普攻和大招会在
## 同一波里吃到不同的倍率 —— 那正是那条铁律想留出来的空间。
static func _build_skill(
	unit: PBUnit, wave_element: PBElement.Type, mult: float, gather: bool, cfg: PBSimConfig
) -> PBSkill:
	var skill := PBSkill.new()
	skill.element = unit.character.ultimate_element()
	var rel := PBElement.relation(skill.element, wave_element)
	skill.damage = unit.power(cfg) * cfg.damage_multiplier(rel) * mult * cfg.ultimate_power_mult
	skill.radius = cfg.ultimate_radius
	skill.cooldown_ticks = int(round(cfg.ultimate_cooldown_seconds * float(cfg.tick_rate)))
	skill.delay_ticks = int(round(cfg.ultimate_delay_seconds * float(cfg.tick_rate)))
	skill.mp_cost = cfg.ultimate_mp_cost
	skill.gather = gather
	return skill


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
