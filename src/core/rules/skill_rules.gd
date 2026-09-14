class_name PBSkillRules
extends RefCounted
## 一发技能落地时结算什么。全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules] / [PBMoveRules] 对称：这一层答「这一发落在谁身上、
## 他们身上发生了什么」。[PBBattleSim] 只管什么时候放、冷却与蓝够不够。


## 一个单位的第 [param index] 个技能。**0 是大招，1.. 是他自己表里的。**
## 越界或者压根没有就返回 null。
##
## 指令卡、瞄准状态机、施放入口三处只认这一个下标 —— 各自判「这一格是大招还是
## 技能表里的」的话，漏改一处的表现是「第二个技能的按钮放出第一个」。
static func cast_at(unit: PBAttacker, index: int) -> PBSkillCast:
	if unit == null or index < 0:
		return null
	if index == 0:
		return unit.ultimate
	var i: int = index - 1
	return unit.skills[i] if i < unit.skills.size() else null


## 这个人一共有几格技能（含大招那一格）。指令卡拿它决定画几个格子。
static func cast_count(unit: PBAttacker) -> int:
	return 0 if unit == null else 1 + unit.skills.size()


## 他这一刻放不放得出第 [param index] 个技能：活着 / 冷却转好 / 蓝够（§3.5）。
##
## **指令卡那一格的亮灰、和真正下达时的第一道门，读的是同一份。**
## 各写一份的话「按钮亮着但点了没反应」迟早出现，而它不报错 ——
## 玩家只会觉得这一格时灵时不灵。
static func can_cast(unit: PBAttacker, index: int, at_tick: int) -> bool:
	if unit == null or not unit.alive:
		return false
	var cast := cast_at(unit, index)
	if cast == null:
		return false
	return cast.is_ready(at_tick) and unit.can_pay(cast.skill.mp_cost)


## 这份技能的数据合不合法。返回空串表示没问题，否则是给人看的原因。
##
## 拦的都是**静默生效**的错：
##
## - **`ALLY` 却打敌人 / `ENEMY` 却打自己人** —— 表现是「点了一个队友然后他掉血」
## - **非 `GROUND` 却配了施法延迟** —— 延迟存在的全部理由是 §02 的预判窗口，
##   锁定单体的技能目标跟着走，没有预判可言
static func validate(skill: PBSkill) -> String:
	if skill == null:
		return "技能是空的"
	if skill.target == PBSkill.Target.ALLY and skill.affects != PBSkill.Party.ALLIES:
		return "target=ALLY 的技能必须 affects=ALLIES —— 点队友却打敌人说不通"
	if skill.target == PBSkill.Target.ENEMY and skill.affects != PBSkill.Party.ENEMIES:
		return "target=ENEMY 的技能必须 affects=ENEMIES —— 点敌人却打自己人说不通"
	if skill.target != PBSkill.Target.GROUND and skill.delay_ticks != 0:
		return "只有 GROUND 档能配施法延迟 —— 锁定目标的技能没有预判窗口"
	return _check_shot(skill)


## 子弹那几条。见 [member PBSkill.shot_cross_seconds]。静默生效的错：
##
## - **地面档配了飞行速度**：那一档的飞行时间是 [member PBSkill.delay_ticks]，两把尺子
## - **不挑目标的那一档配了飞行速度**：没有目标可飞
## - **子弹技能配了位置操纵与全场效果**（[member PBSkill.gather] 那一批）：
##   子弹只结算打中的那一个（[method PBShotRules._hit_enemy]），配了不会生效
static func _check_shot(skill: PBSkill) -> String:
	if skill.shot_cross_seconds <= 0.0:
		return ""
	if skill.target != PBSkill.Target.ALLY and skill.target != PBSkill.Target.ENEMY:
		return "只有锁定档（ALLY / ENEMY）能配飞行速度 —— 别的档没有目标可追"
	if skill.gather or skill.knockback > 0.0 or skill.reset_cooldowns:
		return "子弹技能不结算位置操纵与重置冷却 —— 那几项是地面档大招的词汇"
	if skill.slow_ticks > 0 or skill.buff_ticks > 0:
		return "子弹技能不结算全场效果（减速 / 全队增伤）—— 同上"
	return ""


## 一发**子弹**打在敌人身上。返回它有没有被这一下打死。
## 伤害由 [method PBShotRules._hit_enemy] 先结算，这里只挂 [member PBSkill.on_hit] ——
## 「打死了几个」只有一个来源。
static func apply_hit(
	enemy: PBEnemy, skill: PBSkill, level: int, cfg: PBSimConfig, tick: int
) -> bool:
	return apply_all_enemy(enemy, skill.on_hit, level, cfg, tick)


## 一发**子弹**落在己方单位身上（治疗那一类）。
static func apply_hit_ally(
	unit: PBAttacker, skill: PBSkill, level: int, cfg: PBSimConfig, tick: int
) -> void:
	_apply_all(unit, skill.on_hit, level, cfg, tick, skill.heal_scale)


## 一发落地：范围内每个敌人各吃一份完整伤害，聚拢/击退的还会被挪位置。
## 返回这一下打死了几个 —— 调用方要把它加进 [PBCombatOutcome]。
##
## 和 [method PBStrikeRules._strike_area] 一样**不结算溢出** —— 技能的价值
## 写在命中数上（§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一发范围技能在密集波里等于无限伤害。
static func land(
	cast: PBSkillCast, enemies: Array[PBEnemy], front: int, cfg: PBSimConfig, tick: int
) -> int:
	var skill := cast.skill
	var kills: int = 0
	var hits: int = 0
	for i: int in range(front, enemies.size()):
		if skill.max_targets > 0 and hits >= skill.max_targets:
			break
		var enemy: PBEnemy = enemies[i]
		if not enemy.has_spawned(tick):
			break
		if not enemy.alive:
			continue
		# 真圆（[member PBSkill.radius]），圆心是落点。
		if enemy.pos().distance_to(cast.spot) > skill.radius:
			continue
		hits += 1
		if enemy.take_damage(skill.damage, tick):
			kills += 1
			continue
		# 命中之后才挂 [member PBSkill.on_hit]：给尸体挂减速会让「定住了几个」虚高。
		if apply_all_enemy(enemy, skill.on_hit, cast.caster_level, cfg, tick):
			kills += 1
			continue
		# 活下来的才挪 —— 挪一个尸体没有意义，而且会让「聚拢值多少」虚高。
		if skill.gather:
			# 聚拢是**两轴一起**拖到落点上：只拖 x 的话一圈人会被拉成
			# 一条横线，而「聚成一堆」正是这个机制唯一的产出。
			enemy.distance = cast.spot.x
			enemy.lane = cast.spot.y
		elif skill.knockback > 0.0:
			# 击退只作用在推进轴上 —— 它买的是「敌人晚到基地多久」。
			# 上限是**他自己的出生点**，不是战场长度：方阵后面几列出生在
			# 战场之外，拿战场长度封顶会把他们往前拽（见 [member PBEnemy.start_x]）。
			enemy.distance = minf(enemy.distance + skill.knockback, enemy.start_x)
	return kills


## 落在一个**锁定的己方单位**身上（[constant PBSkill.Target.ALLY]）。
##
## **目标没了就空放，不改打别人**：下达和落地之间隔着一个 tick，目标可能已经死了。
## 改打别人的话，玩家点的人和实际受益的人不是同一个，而他不会知道。
## 同 [PBProjectile] 那条「目标死了子弹就消失」。
static func land_on_ally(
	cast: PBSkillCast, attackers: Array[PBAttacker], cfg: PBSimConfig, tick: int
) -> void:
	if cast.target_slot < 0 or cast.target_slot >= attackers.size():
		return
	var target: PBAttacker = attackers[cast.target_slot]
	if not target.is_targetable():
		return
	_apply_all(target, cast.skill.on_hit, cast.caster_level, cfg, tick, cast.skill.heal_scale)


## 落在**一圈己方单位**身上：圆心 [param center]、半径 [member PBSkill.radius] 内每个还站着的人各挂一份
## [member PBSkill.on_hit]（含施法者自己）。半径 0 = 只有站在圆心上的那一个。
##
## 「不用点」的光环（圆心是施法者）、「点地面」的治疗圈、阵亡时放的回血（圆心是尸体）都走这里。
## **缺了它的表现是按了扣蓝进冷却、谁身上都没有效果**，而它不报错。
static func land_around_allies(
	cast: PBSkillCast, center: Vector2, attackers: Array[PBAttacker], cfg: PBSimConfig, tick: int
) -> void:
	for unit: PBAttacker in attackers:
		if unit.is_targetable() and unit.pos.distance_to(center) <= cast.skill.radius:
			_apply_all(unit, cast.skill.on_hit, cast.caster_level, cfg, tick, cast.skill.heal_scale)


## 落在一个**锁定的敌人**身上（[constant PBSkill.Target.ENEMY]）。返回打死了几个（0 或 1）。
## 和 [method land_on_ally] 对称，目标没了就空放。
static func land_on_enemy(
	cast: PBSkillCast, enemies: Array[PBEnemy], cfg: PBSimConfig, tick: int
) -> int:
	if cast.target_slot < 0 or cast.target_slot >= enemies.size():
		return 0
	var enemy: PBEnemy = enemies[cast.target_slot]
	if not enemy.alive or not enemy.has_spawned(tick):
		return 0
	if enemy.take_damage(cast.skill.damage, tick):
		return 1
	return 1 if apply_all_enemy(enemy, cast.skill.on_hit, cast.caster_level, cfg, tick) else 0


## 打全场：伤害发给**每一个已出场且还活着的敌人**，不看位置
## （[constant PBSkill.Target.NONE] + [constant PBSkill.Party.ENEMIES]）。返回打死了几个。
## 和 [method land] 只差「不按半径圈人」，[member PBSkill.max_targets] 仍然管用（0 = 不限）。
static func land_on_field(
	cast: PBSkillCast, enemies: Array[PBEnemy], front: int, cfg: PBSimConfig, tick: int
) -> int:
	var skill := cast.skill
	var kills: int = 0
	var hits: int = 0
	for i: int in range(front, enemies.size()):
		if skill.max_targets > 0 and hits >= skill.max_targets:
			break
		var enemy: PBEnemy = enemies[i]
		if not enemy.has_spawned(tick):
			break
		if not enemy.alive:
			continue
		hits += 1
		if enemy.take_damage(skill.damage, tick):
			kills += 1
			continue
		if apply_all_enemy(enemy, skill.on_hit, cast.caster_level, cfg, tick):
			kills += 1
	return kills


## 下达那一刻挂给施法者自己的效果（[member PBSkill.on_self]）。
static func apply_on_self(
	attacker: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int
) -> void:
	_apply_all(attacker, cast.skill.on_self, cast.caster_level, cfg, tick, cast.skill.heal_scale)


## 把一串效果挂到一个己方单位身上，数值按 [param level] 现算（决策 7），
## 回血量再乘施法者的治疗倍率（[member PBSkill.heal_scale]）。
static func _apply_all(
	unit: PBAttacker,
	buffs: Array[PBBuff],
	level: int,
	cfg: PBSimConfig,
	tick: int,
	heal_scale: float = 1.0
) -> void:
	for buff: PBBuff in buffs:
		var mods := PBBuffRules.scale_heal(PBBuffRules.resolve(buff, level), heal_scale)
		apply_one(unit, buff, mods, cfg, tick)


## 把**一份**效果挂到一个己方单位身上。
##
## ## 瞬间的那一档不进效果袋
##
## §2.3 那条分界线：**瞬间效果改的是「量」（血、蓝），写进字段；
## 持续效果改的是「率」，只在用的那一刻问一次。** 所以瞬间档在这里当场
## 结算完就没了，而 [method PBBuffBag.add] 那条路是给有窗口的那两档走的
## —— 顺带它自己也拦着（`ticks <= 0` 直接返回），瞬间档的窗口正好是 0。
static func apply_one(
	unit: PBAttacker, buff: PBBuff, mods: Dictionary, cfg: PBSimConfig, tick: int
) -> void:
	if buff == null:
		return
	if buff.kind == PBBuff.Kind.INSTANT:
		unit.heal(float(mods.get(PBBuffRules.HEAL, 0.0)))
		unit.heal(unit.max_hp * float(mods.get(PBBuffRules.HEAL_MAX, 0.0)))
		unit.restore_mana(float(mods.get(PBBuffRules.MANA, 0.0)))
		return
	unit.buffs.add(buff, mods, tick, buff.duration_ticks(cfg), buff.period_ticks(cfg))


## 把一串效果挂到一个**敌人**身上。返回它有没有被这一串里的瞬间伤害打死。
##
## 技能与角色被动（[method PBStrikeRules.land]）共用这一处 —— 各写一份的话，
## 两者迟早在叠加方式或「死了还挂不挂」上分叉。
static func apply_all_enemy(
	enemy: PBEnemy, buffs: Array[PBBuff], level: int, cfg: PBSimConfig, tick: int
) -> bool:
	for buff: PBBuff in buffs:
		if apply_one_enemy(enemy, buff, PBBuffRules.resolve(buff, level), cfg, tick):
			return true
	return false


## 把**一份**效果挂到一个敌人身上。返回这一下有没有把它打死。
##
## 瞬间分支和己方（[method apply_one]）不能共用：己方是回血回蓝，敌方是掉血，
## 而掉血必须走 [method PBEnemy.take_damage]（杀敌数和易伤都在它里面）。
static func apply_one_enemy(
	enemy: PBEnemy, buff: PBBuff, mods: Dictionary, cfg: PBSimConfig, tick: int
) -> bool:
	if buff == null:
		return false
	if buff.kind == PBBuff.Kind.INSTANT:
		var harm: float = float(mods.get(PBBuffRules.HARM, 0.0))
		return harm > 0.0 and enemy.take_damage(harm, tick)
	enemy.buffs.add(buff, mods, tick, buff.duration_ticks(cfg), buff.period_ticks(cfg))
	return false


## 落地时给全队挂一份短时增伤（给每个人各挂一份 [PBBuff]）。
## 没配这一项（`buff_ticks <= 0` 或倍率不大于 1）什么都不做。
static func apply_team_buff(skill: PBSkill, attackers: Array[PBAttacker], tick: int) -> void:
	if skill.buff_ticks <= 0 or skill.team_damage_scale <= 1.0:
		return
	# **一份 Dictionary 发给全队**，不是一人造一个：谁都不改
	# [member PBBuffState.mods]，共用是安全的，而 §14 那条
	# 「热路径不 `.new()`」在这里省的是十一次分配。
	var boost: Dictionary = {PBBuffRules.DAMAGE_SCALE: skill.team_damage_scale}
	for attacker: PBAttacker in attackers:
		attacker.buffs.add(PBBuffRules.team_damage(), boost, tick, skill.buff_ticks, 0)


## 落地时把**其他**技能的冷却清零（§11 六尾）。没配这一项什么都不做。
##
## 清的是别人不是自己 —— 自己也清的话它会在同一 tick 反复自我重置。
## 这一条的强度与队伍里技能的总量成正比，而不是和它自己的数值成正比，
## 所以它在数据上伤害为 0 却可能是最强的一只。
static func reset_other_cooldowns(
	skill: PBSkill, caster: PBSkillCast, attackers: Array[PBAttacker], tick: int
) -> void:
	if not skill.reset_cooldowns:
		return
	for attacker: PBAttacker in attackers:
		# **每一格都清，不只是大招那一格**：这一条的价值与队伍里技能的总量成正比。
		for i: int in cast_count(attacker):
			var other := cast_at(attacker, i)
			if other != null and other != caster and not other.is_pending():
				other.ready_at = tick
