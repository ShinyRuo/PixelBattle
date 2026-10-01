extends GutTest
## 两种伤害类型 × 七种属性；属性基数、增伤隔离、效果来源与敌我减伤契约。

const TAI := PBDamageKind.Type.TAIJUTSU
const NIN := PBDamageKind.Type.NINJUTSU
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _ninja() -> PBAttacker:
	var one := PBAttacker.new()
	one.attack = 100.0
	one.ninjutsu_attack = 40.0
	one.attack_speed = 1.0
	one.max_hp = 10000.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


func _stats() -> PBStats:
	var values := PBStats.new()
	values.atk = 100.0
	values.intellect = 40.0
	values.agility = 30.0
	values.strength = 60.0
	values.hp = 1000.0
	return values


func test_base_uses_attack_or_intellect_and_never_attack_speed() -> void:
	var values := _stats()
	var skill := PBSkill.new()
	skill.power_mult = 2.0
	skill.damage_base = 10.0
	skill.damage_growth = 5.0
	for kind: PBDamageKind.Type in [TAI, NIN]:
		skill.kind = kind
		var expected: float = 220.0 if kind == TAI else 100.0
		assert_eq(PBSkillDamage.raw(skill, values, 3), expected)
		values.attack_speed = 100.0
		assert_eq(PBSkillDamage.raw(skill, values, 3), expected, "攻速不能改变单次伤害")


func test_explicit_attribute_formula_and_health_term_are_independent_of_kind() -> void:
	var skill := PBSkill.new()
	skill.damage_stat = &"strength"
	skill.power_mult = 2.0
	skill.damage_hp = 0.1
	for kind: PBDamageKind.Type in [TAI, NIN]:
		skill.kind = kind
		assert_eq(PBSkillDamage.raw(skill, _stats(), 1), 220.0)
	var copy := skill.clone()
	PBSkillPatchRules.apply(copy, {PBSkillPatchRules.POWER_SCALE: 2.0})
	assert_eq(PBSkillDamage.raw(copy, _stats(), 1), 440.0)
	assert_eq(PBSkillDamage.raw(skill, _stats(), 1), 220.0, "不能污染共享定义")


func test_every_roster_attack_and_skill_follows_owner_rule() -> void:
	for character: PBCharacter in _cfg.characters.all():
		var unit := PBUnit.new(character)
		var squad := PBCombatRules.build_attackers(
			[unit], PBElement.Type.FIRE, 1.0, PackedFloat64Array(), _cfg
		)
		var one: PBAttacker = squad[0]
		var expected: PBDamageKind.Type = (
			TAI if character.element == PBElement.Type.PHYSICAL else NIN
		)
		assert_eq(one.ultimate.skill.kind, expected, str(character.id))
		for cast: PBSkillCast in one.skills:
			assert_eq(cast.skill.kind, expected, str(character.id))
			assert_eq(cast.skill.element, _cfg.skills.by_id(cast.skill.id).element, "分型不能改写技能克制属性")
		var attack_kind: PBDamageKind.Type = NIN if one.attack_ninjutsu > 0.0 else TAI
		assert_eq(PBCritRules.attack_kind(one), attack_kind)
		assert_eq(one.clone().ninjutsu_attack, one.ninjutsu_attack)


func test_seven_elements_still_multiply_both_damage_kinds() -> void:
	var unit := PBUnit.new(PBCharacter.new())
	for attack: int in PBElement.Type.values():
		for defence: int in PBElement.Type.values():
			for kind: PBDamageKind.Type in [TAI, NIN]:
				var skill := PBSkill.new()
				skill.kind = kind
				skill.element = attack as PBElement.Type
				skill.damage_base = 100.0
				var expected: float = (
					100.0
					* _cfg.damage_multiplier(
						PBElement.relation(attack as PBElement.Type, defence as PBElement.Type)
					)
				)
				assert_almost_eq(
					PBCombatRules.skill_damage(unit, skill, defence as PBElement.Type, 1.0, _cfg),
					expected,
					0.0001
				)


func test_stat_modifiers_reach_built_skill_formula() -> void:
	var character := PBCharacter.new()
	character.element = PBElement.Type.FIRE
	character.skill_ids = [&"formula_probe"]
	var skill := PBSkill.new()
	skill.id = &"formula_probe"
	skill.power_mult = 3.0
	skill.element = PBElement.Type.WATER
	_cfg.skills = PBSkillTable.new()
	_cfg.skills.add(skill)
	var unit := PBUnit.new(character)
	var plain := PBCombatRules.build_attackers(
		[unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg
	)
	var boosted := PBCombatRules.build_attackers(
		[unit],
		PBElement.Type.PHYSICAL,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		{},
		{},
		[{PBStatRules.INTELLECT: 20.0}]
	)
	var relation: float = _cfg.damage_multiplier(
		PBElement.relation(skill.element, PBElement.Type.PHYSICAL)
	)
	assert_almost_eq(
		boosted[0].skills[0].skill.damage - plain[0].skills[0].skill.damage,
		60.0 * relation,
		0.0001,
		"装备智力必须进入技能"
	)
	assert_eq(skill.damage, 0.0, "不能改写盘上定义")


func test_damage_bonuses_are_isolated_and_general_bonus_applies_to_both() -> void:
	var one := _ninja()
	one.taijutsu_bonus = 0.5
	one.ninjutsu_bonus = 0.25
	one.all_damage_bonus = 0.2
	one.damage_bonus = 0.1
	assert_almost_eq(PBCritRules.strike(one, 0)[PBCritRules.DAMAGE], 198.0, 0.0001)
	assert_almost_eq(PBCritRules.hit(one, 100.0, TAI, 0)[PBCritRules.DAMAGE], 180.0, 0.0001)
	one.attack_ninjutsu = 1.0
	assert_almost_eq(PBCritRules.strike(one, 0)[PBCritRules.DAMAGE], 66.0, 0.0001)
	assert_almost_eq(PBCritRules.hit(one, 100.0, NIN, 0)[PBCritRules.DAMAGE], 150.0, 0.0001)


func test_enemy_damage_types_use_independent_crit_and_bonuses() -> void:
	var enemy := PBEnemy.new()
	enemy.damage_per_shot = 100.0
	enemy.intellect = 50.0
	enemy.ninjutsu_coefficient = 2.0
	enemy.crit_chance = 1.0
	enemy.ninjutsu_crit_chance = 0.0
	enemy.taijutsu_bonus = 0.5
	enemy.ninjutsu_bonus = 0.25
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	assert_eq(PBCritRules.enemy_strike(enemy, 0, rng)[PBCritRules.DAMAGE], 300.0)
	enemy.damage_kind = NIN
	var state: int = rng.state
	assert_eq(PBCritRules.enemy_strike(enemy, 0, rng)[PBCritRules.DAMAGE], 125.0)
	assert_eq(rng.state, state, "忍术暴击为零不掷体术暴击")


func test_enemy_hits_keep_element_matchups_and_select_only_one_defence() -> void:
	for attack: int in PBElement.Type.values():
		for defence: int in PBElement.Type.values():
			for kind: PBDamageKind.Type in [TAI, NIN]:
				var one := _ninja()
				one.defence = 20.0
				one.ninjutsu_resist = 0.4
				one.def_element = defence as PBElement.Type
				var context := PBEnemyHitContext.new([], false, kind, 0.5, 0.5)
				var reduction: float = (
					0.8 if kind == NIN else 1.0 - PBStatRules.damage_reduction(10.0, _cfg)
				)
				var expected: float = (
					100.0
					* reduction
					* _cfg.damage_multiplier(
						PBElement.relation(attack as PBElement.Type, defence as PBElement.Type)
					)
				)
				PBStrikeRules.hurt_ally(
					one,
					null,
					100.0,
					attack as PBElement.Type,
					_cfg,
					0,
					null,
					null,
					PBCombatOutcome.new(),
					context
				)
				assert_almost_eq(one.max_hp - one.hp, expected, 0.001)


func test_enemy_melee_and_projectile_keep_kind_and_penetration() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	for ranged: bool in [false, true]:
		var wave := PBWave.new()
		wave.hp_each = 100000.0
		wave.atk_each = 100.0
		wave.count = 1
		wave.element = PBElement.Type.PHYSICAL
		wave.damage_kind = NIN
		wave.intellect_each = 50.0
		wave.ninjutsu_coefficient = 2.0
		wave.ninjutsu_pen = 0.5
		wave.ninjutsu_crit_chance = 1.0
		var one := _ninja()
		one.attack = 0.0
		one.defence = 10000.0
		one.ninjutsu_resist = 0.4
		var rng := RandomNumberGenerator.new()
		rng.seed = 37
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one], rng)
		var enemy: PBEnemy = sim.enemies()[0]
		enemy.arm(2.0, 100, 100.0, 0.05 if ranged else 0.0, ranged)
		sim.step()
		enemy.damage_kind = TAI
		enemy.ninjutsu_pen = 0.0
		for tick: int in 30:
			sim.step()
		assert_almost_eq(one.max_hp - one.hp, 160.0, 0.001, "出手后的类型变化不能让忍术弹改吃护甲或丢失穿透")
		enemy.spawn(PBWave.new(), 0.0, 1.0, 0)
		assert_eq(enemy.damage_kind, TAI)
		assert_eq(enemy.ninjutsu_pen, 0.0)


func test_instant_effect_and_temporary_ninjutsu_resistance_use_the_same_rules() -> void:
	var one := _ninja()
	one.taijutsu_bonus = 0.5
	one.armor_pen = 0.5
	var enemy := PBEnemy.new()
	enemy.alive = true
	enemy.hp = 1000.0
	enemy.armor = 20.0
	enemy.element = PBElement.Type.WIND
	var skill := PBSkill.new()
	skill.kind = TAI
	skill.element = PBElement.Type.FIRE
	var buff := PBBuff.new()
	buff.kind = PBBuff.Kind.INSTANT
	var amount: float = (
		150.0 * _cfg.damage_multiplier(PBElement.relation(skill.element, enemy.element))
	)
	amount *= 1.0 - PBStatRules.damage_reduction(10.0, _cfg)
	PBSkillRules.apply_one_enemy(
		enemy, buff, {PBBuffRules.HARM: 100.0}, _cfg, 0, PBHarmContext.from_caster(one, skill)
	)
	assert_almost_eq(1000.0 - enemy.hp, amount, 0.001)
	var resist := PBBuff.new()
	resist.id = &"temporary_resist"
	resist.kind = PBBuff.Kind.DURATION
	one.buffs.add(resist, {PBBuffRules.NINJUTSU_RESIST: 0.5}, 0, 1, 0)
	var context := PBEnemyHitContext.new([], false, NIN)
	for tick: int in [1, 2]:
		var before: float = one.hp
		PBStrikeRules.hurt_ally(
			one,
			null,
			100.0,
			PBElement.Type.PHYSICAL,
			_cfg,
			tick,
			null,
			null,
			PBCombatOutcome.new(),
			context
		)
		var match_scale: float = _cfg.damage_multiplier(
			PBElement.relation(PBElement.Type.PHYSICAL, one.def_element)
		)
		assert_almost_eq(before - one.hp, (50.0 if tick == 1 else 100.0) * match_scale, 0.001)


func test_periodic_damage_preserves_source_kind_element_bonus_and_penetration() -> void:
	var one := _ninja()
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	one.ninjutsu_crit_chance = 1.0
	var skill := PBSkill.new()
	skill.element = PBElement.Type.FIRE
	skill.kind = NIN
	var enemy := PBEnemy.new()
	enemy.alive = true
	enemy.hp = 10000.0
	enemy.element = PBElement.Type.WIND
	enemy.ninjutsu_resist = 0.4
	var buff := PBBuff.new()
	buff.id = &"formula_dot"
	buff.kind = PBBuff.Kind.PERIODIC
	buff.duration_seconds = 2.0
	buff.period_seconds = 1.0
	buff.mods = {PBBuffRules.HARM: 100.0}
	var source := PBHarmContext.from_caster(one, skill)
	PBSkillRules.apply_all_enemy(enemy, [buff], 1, _cfg, 0, source)
	one.ninjutsu_bonus = 20.0
	one.alive = false
	var expected: float = (
		100.0 * 1.5 * 0.8 * _cfg.damage_multiplier(PBElement.relation(skill.element, enemy.element))
	)
	assert_almost_eq(
		PBBuffRules.advance_enemy(enemy, _cfg.tick_rate, _cfg),
		expected,
		0.001,
		"持续伤害保留施加时来源，不暴击，也不受施法者死亡影响"
	)
	assert_eq(float(buff.mods[PBBuffRules.HARM]), 100.0)
	enemy.buffs.clear()
	PBSkillRules.apply_all_enemy(enemy, [buff], 1, _cfg, 0)
	assert_almost_eq(
		PBBuffRules.advance_enemy(enemy, _cfg.tick_rate, _cfg), 60.0, 0.001, "槽位复用不能保留旧来源"
	)
