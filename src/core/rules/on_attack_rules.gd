class_name PBOnAttackRules
extends RefCounted
## 只从普攻起手进入，不从命中、暴击、飞行子弹或技能递归触发。
## 一次触发共用一次忍术 / 体术暴击结果；相交的各圆仍逐个结算护甲或抗性。


static func equip(
	attacker: PBAttacker,
	unit: PBUnit,
	element: PBElement.Type,
	mult: float,
	cfg: PBSimConfig,
	patches: Dictionary,
	stats: PBStats
) -> void:
	attacker.attack_casts.clear()
	for id: StringName in patches:
		var patch: Dictionary = patches[id]
		if not patch.has(PBSkillPatchRules.ON_ATTACK_CHANCE) or unit.character.skill_ids.has(id):
			continue
		var source: PBSkill = cfg.skills.by_id(id)
		if source == null:
			push_error("攻击起手技能不存在：%s" % id)
			continue
		var mine := source.clone()
		PBSkillPatchRules.apply(mine, patch, cfg.tick_rate)
		var error := validate(mine)
		if error != "":
			push_error("攻击起手技能 %s：%s" % [id, error])
			continue
		mine.kind = PBDamageKind.skill_kind(unit.element)
		mine.damage = PBCombatRules.skill_damage(unit, mine, element, mult, cfg, stats)
		if PBSkillDamage.stat_of(mine) == &"attack":
			mine.attack_formula_scale = (
				mine.power_mult
				* mult
				* cfg.damage_multiplier(PBElement.relation(mine.element, element))
			)
		attacker.attack_casts.append(PBSkillCast.new(mine, unit.level))


static func self_bonus(unit: PBAttacker) -> float:
	if not unit.is_targetable():
		return 0.0
	var amount: float = 0.0
	for cast: PBSkillCast in unit.attack_casts:
		amount += _self_rate(cast)
	for cast: PBSkillCast in unit.skills:
		amount += _self_rate(cast)
	return amount


static func _self_rate(cast: PBSkillCast) -> float:
	return (
		cast.skill.self_attack_bonus
		+ cast.skill.self_attack_bonus_growth * maxi(cast.caster_level - 1, 0)
	)


static func fire(
	unit: PBAttacker,
	target: PBEnemy,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	if rng == null or not unit.alive or not target.is_hostile(tick):
		return
	for cast: PBSkillCast in unit.attack_casts:
		_attempt(cast, unit, target, enemies, cfg, tick, rng, book, out)
	for cast: PBSkillCast in unit.skills:
		_attempt(cast, unit, target, enemies, cfg, tick, rng, book, out)


static func _attempt(
	cast: PBSkillCast,
	unit: PBAttacker,
	target: PBEnemy,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	var skill := cast.skill
	if skill.attack_trigger_chance <= 0.0 or not target.is_hostile(tick):
		return
	if rng.randf() >= skill.attack_trigger_chance:
		return
	var center: Vector2 = target.pos()
	var direction: Vector2 = unit.pos.direction_to(center)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	cast.trigger_tick = tick
	cast.trigger_center = center
	cast.trigger_direction = direction
	if skill.attack_repeat_count > 0:
		_repeat(skill.attack_repeat_count, unit, target, enemies, cfg, tick, rng, book, out)
		return
	var raw := PBAllyAuraRules.skill_damage(unit, skill, 0.0, tick)
	var rolled := PBCritRules.hit(unit, raw, skill.kind, tick, rng)
	cast.origin = unit.pos
	if skill.target == PBSkill.Target.ENEMY:
		if _hit_primary(cast, unit, target, cfg, tick, rolled, book):
			out.kills += 1
	else:
		for index: int in skill.attack_chain_count:
			cast.spot = center + direction * skill.attack_chain_step * float(index + 1)
			out.kills += PBSkillRules.land(
				cast,
				enemies,
				0,
				cfg,
				tick,
				unit,
				rolled[PBCritRules.DAMAGE],
				book,
				rolled[PBCritRules.CRIT]
			)
	if target.is_hostile(tick):
		if PBSkillRules.apply_all_enemy(
			target,
			skill.on_primary,
			cast.caster_level,
			cfg,
			tick,
			PBHarmContext.from_caster(unit, skill, tick)
		):
			out.kills += 1


static func _repeat(
	count: int,
	unit: PBAttacker,
	enemy: PBEnemy,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	for index: int in count:
		if not enemy.is_hostile(tick):
			break
		var rolled := PBCritRules.strike(unit, tick, rng)
		PBStrikeRules.land(
			unit,
			enemy,
			rolled[PBCritRules.DAMAGE],
			rolled[PBCritRules.CRIT],
			enemies,
			cfg,
			tick,
			book,
			out,
			rng
		)


static func _hit_primary(
	cast: PBSkillCast,
	unit: PBAttacker,
	enemy: PBEnemy,
	cfg: PBSimConfig,
	tick: int,
	rolled: Dictionary,
	book: PBBattleLog
) -> bool:
	var skill := cast.skill
	var dealt := PBStrikeRules.mitigated(
		unit, enemy, rolled[PBCritRules.DAMAGE], skill.kind, cfg, tick
	)
	if book != null:
		book.hit(tick, unit.slot, enemy.slot, dealt, false, rolled[PBCritRules.CRIT])
	return enemy.take_damage(dealt, tick, null, false, skill.element)


static func validate(skill: PBSkill) -> String:
	for value: float in [
		skill.attack_trigger_chance,
		skill.attack_chain_step,
		skill.self_attack_bonus,
		skill.self_attack_bonus_growth
	]:
		if not is_finite(value) or value < 0.0:
			return "攻击触发概率、间距与自身攻击加成必须是有限非负数"
	if skill.attack_trigger_chance > 1.0 or skill.attack_chain_count < 0:
		return "攻击触发概率不能超过 1，连续圆数量不能为负"
	if skill.attack_repeat_count < 0 or skill.attack_repeat_count > 8:
		return "额外普攻次数必须在 0–8 之间"
	if (
		skill.attack_repeat_count > 0
		and (
			skill.attack_trigger_chance <= 0.0
			or skill.target != PBSkill.Target.ENEMY
			or skill.power_mult != 0.0
			or skill.damage_base != 0.0
			or skill.damage_growth != 0.0
			or not skill.on_primary.is_empty()
		)
	):
		return "额外普攻需要单体起手触发，不可同时配置技能伤害或主目标效果"
	if skill.attack_chain_count == 0 and skill.attack_trigger_chance == 0.0:
		if (
			skill.attack_chain_step > 0.0
			or skill.self_attack_bonus > 0.0
			or skill.self_attack_bonus_growth > 0.0
			or not skill.on_primary.is_empty()
		):
			return "攻击触发参数需要连续圆数量"
		return ""
	return _check_shape(skill)


static func _check_shape(skill: PBSkill) -> String:
	var single: bool = skill.target == PBSkill.Target.ENEMY
	if single:
		if skill.radius != 0.0 or skill.attack_chain_count != 0 or skill.attack_chain_step != 0.0:
			return "锁定攻击触发只打主目标，不能同时配置连续圆"
	elif skill.attack_chain_count < 1 or skill.attack_chain_step <= 0.0 or skill.radius <= 0.0:
		return "地面攻击触发需要正圈数、间距和半径"
	if (
		skill.attack_chain_count > 32
		or skill.target not in [PBSkill.Target.GROUND, PBSkill.Target.ENEMY]
		or skill.affects != PBSkill.Party.ENEMIES
		or skill.cooldown_ticks != 0
		or skill.mp_cost != 0.0
		or not skill.mp_cost_levels.is_empty()
		or skill.hit_count != 1
		or skill.delay_ticks != 0
		or not skill.on_self.is_empty()
		or not skill.on_hit.is_empty()
		or not skill.on_target.is_empty()
		or not skill.on_start_target.is_empty()
		or not skill.on_start_area.is_empty()
		or skill.line_length > 0.0
		or skill.travel_step > 0.0
		or skill.zone_seconds > 0.0
		or skill.followup_id != &""
		or skill.summon_count > 0
		or skill.shot_cross_seconds > 0.0
		or skill.target_current_hp > 0.0
	):
		return "攻击触发需要无耗蓝冷却、即时单段的敌方地面圆，1–32 圈，主目标效果单独配置"
	return _check_primary(skill)


static func _check_primary(skill: PBSkill) -> String:
	for buff: PBBuff in skill.on_primary:
		if buff == null or buff.friendly or buff.kind != PBBuff.Kind.DURATION:
			return "攻击主目标效果必须是持续减益"
	return ""
