extends GutTest

const MEMBERS: Array[StringName] = [&"gaara", &"mei", &"tsunade", &"raikage", &"onoki"]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0  # 固定边界位置，不让分离算法在起手期间挪动目标。


func _caster(level: int = 10, mods: Dictionary = {}) -> PBAttacker:
	var units: Array[PBUnit] = []
	for id: StringName in MEMBERS:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		unit.level = level
		units.append(unit)
	var patches := PBBondRules.active_skill_patches(units, [units[0]], _cfg.bonds)
	var passives := PBBondRules.active_passives(units, [units[0]], _cfg.bonds)
	var one := (
		PBCombatRules
		. build_attackers(
			[units[0]],
			PBElement.Type.PHYSICAL,
			1.0,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			passives,
			patches,
			[mods]
		)[0]
	)
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker, rng: RandomNumberGenerator = null) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 1000000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one], rng)
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_first_pulse_series_uses_post_hit_current_life_and_excludes_heroes() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var sim := _sim(one)
		var normal: PBEnemy = sim.enemies()[0]
		var hero: PBEnemy = sim.enemies()[1]
		hero.is_hero = true
		normal.rank = PBEnemy.Rank.BOSS
		var before: float = one.mp
		sim.cast_skill(one, Vector2(0.5, 0.0), 1)
		PBCastTestClock.release(sim, one)
		assert_eq(one.skills[0].skill.target_current_hp, 0.0, "下一次施放已恢复普通招式")
		assert_eq(normal.hp, normal.max_hp)
		var expected: float = normal.max_hp
		var first: float = (
			100.0
			* level
			* _cfg.damage_multiplier(
				PBElement.relation(PBElement.Type.WIND, PBElement.Type.PHYSICAL)
			)
		)
		var scale: float = first / (100.0 * level)
		for pulse: int in range(1, 11):
			for tick: int in 10:
				sim.step()
			expected -= first
			expected -= expected * 0.012 * scale
			assert_almost_eq(normal.hp, expected, 0.001, "BOSS 档位不能代替英雄身份")
			assert_almost_eq(hero.hp, hero.max_hp - first * pulse, 0.001)
		assert_eq(one.mp, before - (6.0 + 4.0 * level))
		assert_eq(one.skills[0].ready_at, 366)


func test_both_damage_events_use_ninjutsu_crit_bonus_penetration_and_shield_order() -> void:
	var one := _caster(1)
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	one.ninjutsu_crit_chance = 1.0
	one.ninjutsu_crit_bonus = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 204
	var sim := _sim(one, rng)
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.armor = 99999.0
	enemy.ninjutsu_resist = 0.4
	var shield := PBBuff.new()
	shield.id = &"sand_shield"
	shield.kind = PBBuff.Kind.DURATION
	enemy.buffs.add(shield, {PBBuffRules.SHIELD: 50.0}, 0, 100, 0)
	var crit := PBCritRules.hit(
		one, one.skills[0].skill.damage, PBDamageKind.Type.NINJUTSU, 0, RandomNumberGenerator.new()
	)
	var rolled: float = crit[PBCritRules.DAMAGE]
	var multiplier: float = rolled / 100.0 * 0.8
	var after_first: float = enemy.max_hp - maxf(100.0 * multiplier - 50.0, 0.0)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for tick: int in 16:
		sim.step()
	assert_almost_eq(enemy.hp, after_first * (1.0 - 0.012 * multiplier), 0.001)
	assert_eq(enemy.buffs.shield_left(16), 0.0)
	assert_true(crit[PBCritRules.CRIT])


func test_next_cast_is_normal_while_first_zone_continues_and_reset_restores_variant() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	PBCastTestClock.release(sim, one)
	assert_eq(one.skills[0].skill.hit_count, 7)
	assert_eq(one.skills[0].skill.on_start_area.size(), 1)
	PBCastTestClock.recover(sim, one)
	one.skills[0].ready_at = 0
	sim.cast_skill(one, Vector2(0.8, 0.0), 1)
	PBCastTestClock.release(sim, one)
	assert_eq(sim.barrages().size(), 2)
	assert_eq(sim.barrages()[0].cast.skill.hit_count, 10)
	assert_eq(sim.barrages()[0].cast.skill.target_current_hp, 0.012)
	assert_eq(sim.barrages()[1].cast.skill.hit_count, 7)
	assert_eq(sim.barrages()[1].cast.skill.target_current_hp, 0.0)
	var clone := one.clone()
	assert_eq(clone.skills[0].skill.hit_count, 10)
	assert_eq(clone.skills[0].skill.target_current_hp, 0.012)
	_sim(one)
	assert_eq(one.skills[0].skill.hit_count, 10)
	assert_false(one.skills[0].first_cast_spent)
	assert_eq(_cfg.skills.by_id(&"sand_burial").hit_count, 3)


func test_empty_first_cast_is_spent_but_unissued_order_is_not() -> void:
	var one := _caster()
	var sim := _sim(one)
	var before: float = one.mp
	sim.cast_skill(one, Vector2(0.99, 0.0), 1)
	assert_eq(one.mp, before)
	assert_eq(one.skills[0].skill.hit_count, 10)
	PBCastTestClock.release(sim, one)
	assert_eq(one.skills[0].skill.hit_count, 7)
	assert_true(one.skills[0].first_cast_spent)
	for tick: int in 100:
		sim.step()
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp)


func test_slow_aura_has_550_range_but_damage_reaches_555_and_does_not_disarm() -> void:
	var one := _caster(1)
	var sim := _sim(one)
	sim.enemies()[0].distance = 0.776
	sim.enemies()[1].distance = 0.774
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for tick: int in 16:
		sim.step()
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	assert_eq(sim.enemies()[0].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 16), 1.0)
	assert_eq(sim.enemies()[1].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 16), 0.0)
	assert_eq(sim.enemies()[1].buffs.amount(PBBuffRules.DISARM, 16), 0.0)
	assert_eq(sim.enemies()[1].buffs.amount(PBBuffRules.STUN, 16), 0.0)


func test_total_stat_bonus_includes_gear_and_preserves_direct_stat_items() -> void:
	var character := _cfg.characters.by_id(&"gaara")
	var mods: Dictionary = {
		PBStatRules.STRENGTH: 7.0,
		PBStatRules.AGILITY: 11.0,
		PBStatRules.INTELLECT: 13.0,
		PBStatRules.ATTACK: 101.0,
		PBStatRules.MAX_HP: 999.0
	}
	for level: int in range(1, 11):
		var base := PBStatRules.of(character, level, 1, _cfg, mods)
		var one := _caster(level, mods)
		var strength: float = base.strength + floorf(base.strength * 0.2)
		var agility: float = base.agility + floorf(base.agility * 0.2)
		var intellect: float = base.intellect + floorf(base.intellect * 0.2)
		assert_eq(one.damage_attributes[&"strength"], strength)
		assert_eq(one.damage_attributes[&"agility"], agility)
		assert_eq(one.damage_attributes[&"intellect"], intellect)
		assert_eq(one.max_hp, 100.0 + strength * 80.0 + 999.0)
		assert_almost_eq(one.max_mp, 100.0 + intellect * 0.7, 0.0001)
		assert_almost_eq(one.base_attack, 1.0 + intellect * 3.5, 0.0001)


func test_primary_kill_does_not_add_an_extra_kill_or_current_health_hit() -> void:
	var one := _caster()
	var sim := _sim(one)
	for enemy: PBEnemy in sim.enemies():
		enemy.hp = 1.0
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for tick: int in 110:
		sim.step()
	assert_eq(sim.result().kills, 2)
