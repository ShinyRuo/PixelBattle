extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0


func _caster(level: int = 10) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"kisame"))
	unit.level = level
	var one := (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	one.ultimate = null
	one.move_speed = 0.0
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	one.pos = Vector2(0.4, 0.0)
	return one


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return rng


func _enemy(x: float, slot: int = 0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, x, 0)
	enemy.slot = slot
	return enemy


func test_passive_is_level_damage_not_normal_attack_crit_and_cannot_be_cast_manually() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var passive: PBSkill = one.skills[1].skill
		assert_eq(passive.id, &"shark_cut")
		assert_eq(passive.damage, 50.0 * level)
		assert_eq(passive.attack_trigger_chance, 0.2)
		assert_eq(passive.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(passive.element, PBElement.Type.WATER)
		assert_eq(one.crit_chance, 0.0)
		assert_eq(PBCritRules.attack_kind(one), PBDamageKind.Type.TAIJUTSU)
		assert_false(PBSkillRules.can_cast(one, 2, 1))
		assert_true(PBSkillRules.can_cast(one, 1, 1))
		var main := _enemy(0.45)
		var beside := _enemy(0.45, 1)
		passive.attack_trigger_chance = 1.0
		var mana: float = one.mp
		PBOnAttackRules.fire(
			one, main, [main, beside], _cfg, 1, _rng(), null, PBCombatOutcome.new()
		)
		assert_eq(main.hp, main.max_hp - 50.0 * level)
		assert_eq(beside.hp, beside.max_hp)
		assert_eq(one.mp, mana)
		assert_eq(one.skills[1].ready_at, 0)


func test_shark_passive_uses_ninjutsu_channels_and_does_not_trigger_attack_effects() -> void:
	var one := _caster()
	one.skills[1].skill.attack_trigger_chance = 1.0
	one.crit_chance = 1.0
	one.crit_bonus = 99.0
	one.damage_bonus = 99.0
	one.ninjutsu_crit_chance = 1.0
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	var enemy := _enemy(0.45)
	enemy.armor = 99999.0
	enemy.ninjutsu_resist = 0.4
	var effect := PBBuff.new()
	effect.id = &"no_recursive_attack"
	effect.kind = PBBuff.Kind.DURATION
	effect.duration_seconds = 1.0
	effect.mods = {PBBuffRules.ENEMY_DEFENCE: -100.0}
	one.attack_buffs = [effect]
	PBOnAttackRules.fire(one, enemy, [enemy], _cfg, 1, _rng(), null, PBCombatOutcome.new())
	var expected: float = (
		500.0 * 1.5 * 0.8 * PBCritRules.multiplier_of(one, 1, PBDamageKind.Type.NINJUTSU)
	)
	assert_almost_eq(enemy.hp, enemy.max_hp - expected, 0.001)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 1), 0.0)


func test_infinite_sharks_all_levels_are_ten_fixed_pulses_using_integer_agility() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		one.attack = 0.0
		one.dps = 0.0
		one.mp_regen = 0.0
		var wave := PBWave.new()
		wave.count = 1
		wave.hp_each = 1000000.0
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
		var enemy: PBEnemy = sim.enemies()[0]
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
		var mana: float = one.mp
		assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
		var per_hit: float = 24.0 * level + floorf(one.damage_attributes[&"agility"]) * 0.25
		for tick: int in range(1, 58):
			sim.step()
			var hits: int = clampi(floori(float(tick - 16) / 4.0), 0, 10)
			assert_almost_eq(
				enemy.hp, enemy.max_hp - per_hit * hits, 0.001, "等级 %d tick %d" % [level, tick]
			)
		assert_eq(one.mp, mana - (6.0 + level * 4.0))
		assert_eq(one.skills[0].ready_at, 416)


func test_ground_damage_and_control_have_separate_radii_and_late_entry() -> void:
	var one := _caster()
	var cast: PBSkillCast = one.skills[0]
	cast.spot = Vector2(0.5, 0.0)
	var zone := PBHazardZone.new()
	zone.begin(one, cast, 10)
	var inside := _enemy(0.5)
	var edge := _enemy(0.68, 1)
	var late := _enemy(0.8, 2)
	var enemies: Array[PBEnemy] = [inside, edge, late]
	zone.advance(enemies, 0, _cfg, 10, null, null)
	assert_eq(inside.buffs.amount(PBBuffRules.STUN, 10), 1.0)
	assert_eq(edge.buffs.amount(PBBuffRules.STUN, 10), 0.0)
	zone.advance(enemies, 0, _cfg, 14, null, null)
	assert_lt(edge.hp, edge.max_hp)
	assert_eq(late.hp, late.max_hp)
	late.distance = 0.5
	inside.distance = 0.8
	one.alive = false
	zone.advance(enemies, 0, _cfg, 18, null, null)
	assert_lt(late.hp, late.max_hp)
	assert_eq(late.buffs.amount(PBBuffRules.STUN, 18), 1.0)
	assert_almost_eq(inside.hp, inside.max_hp - cast.skill.damage, 0.001)
	assert_eq(_cfg.skills.by_id(&"infinite_sharks").on_hit.size(), 0)


func test_passive_tooltip_is_explicit_and_does_not_show_a_manual_target_order() -> void:
	var one := _caster()
	var text := PBEffectWords.skill_body(one.skills[1].skill, _cfg, 10)
	assert_string_contains(text, "20%")
	assert_string_contains(text, "仅作用于当前攻击目标")
	assert_string_contains(text, "忍术伤害（水属性）")
	assert_string_contains(text, "不耗蓝，无需施放")
