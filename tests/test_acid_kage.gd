extends GutTest

const MEMBERS: Array[StringName] = [&"mei", &"tsunade", &"gaara", &"raikage", &"onoki"]
const ARMOR: Array[float] = [-4.0, -8.0, -12.0, -16.0, -20.0, -24.0, -28.0, -32.0, -36.0, -40.5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0


func _units(level: int = 10) -> Array[PBUnit]:
	var units: Array[PBUnit] = []
	for id: StringName in MEMBERS:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		unit.level = level
		units.append(unit)
	return units


func _caster(level: int = 10, bonded: bool = true) -> PBAttacker:
	var units := _units(level)
	if not bonded:
		units.resize(1)
	var patches := PBBondRules.active_skill_patches(units, [units[0]], _cfg.bonds)
	var team := PBCombatRules.build_attackers(
		[units[0]],
		PBElement.Type.PHYSICAL,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		{},
		patches
	)
	var one: PBAttacker = team[0]
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 1000000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_every_level_uses_sixteen_pulses_without_doubling_per_hit_or_cost() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var plain := _caster(level, false)
		var skill: PBSkill = one.skills[0].skill
		assert_eq(skill.id, &"boil_acid")
		assert_eq(skill.damage, plain.skills[0].skill.damage)
		assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(skill.element, PBElement.Type.WATER)
		var sim := _sim(one)
		var before: float = one.mp
		assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
		for tick: int in range(1, 168):
			sim.step()
			assert_almost_eq(
				sim.enemies()[0].max_hp - sim.enemies()[0].hp,
				skill.damage * clampi((tick - 6) / 10, 0, 16),
				0.001
			)
		assert_eq(one.mp, before - PBSkillCostRules.mana(plain.skills[0].skill, level))
		assert_eq(one.skills[0].ready_at, 406)


func test_outer_ring_debuffs_cover_beyond_damage_and_expire_after_carrier() -> void:
	var one := _caster()
	var sim := _sim(one)
	var inside: PBEnemy = sim.enemies()[0]
	var outside: PBEnemy = sim.enemies()[1]
	inside.distance = 0.884
	outside.distance = 0.885
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for tick: int in 146:
		sim.step()
	assert_eq(inside.hp, inside.max_hp, "光环外围不能误吃伤害圆")
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 225), -40.5)
	assert_almost_eq(inside.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 225), 0.3, 0.0001)
	assert_eq(outside.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 141), 0.0)
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 226), 0.0)
	assert_eq(inside.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 226), 1.0)


func test_armor_table_and_overlapping_carriers_do_not_stack() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var sim := _sim(one)
		sim.cast_skill(one, Vector2(0.5, 0.0), 1)
		PBCastTestClock.release(sim, one)
		var enemy: PBEnemy = sim.enemies()[0]
		assert_almost_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 6), ARMOR[level - 1], 0.0001)
		assert_almost_eq(enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 6), 0.3, 0.0001)
		enemy.attack_interval = 30
		enemy.windup_ticks = 0
		enemy.on_fired(1)
		assert_eq(enemy.next_shot_at, 101, "降攻速必须改变真实下次攻击时间")


func test_unbonded_and_shared_definitions_keep_the_base_zone() -> void:
	var enhanced := _caster()
	assert_eq(enhanced.skills[0].skill.hit_count, 16)
	var normal := _caster(10, false)
	var source := _cfg.skills.by_id(&"boil_acid")
	for skill: PBSkill in [source, normal.skills[0].skill]:
		assert_eq(skill.hit_count, 8)
		assert_eq(skill.zone_outer_count, 0)
		assert_true(skill.zone_ring_effects.is_empty())
		assert_eq(PBBuffRules.resolve(skill.zone_effects[0], 10)[PBBuffRules.ENEMY_DEFENCE], -30.0)
	var clone := enhanced.skills[0].skill.clone()
	clone.zone_ring_effects.clear()
	assert_eq(enhanced.skills[0].skill.zone_ring_effects.size(), 1)


func test_preparation_card_uses_same_variant_as_battle_and_keeps_mana() -> void:
	var units := _units()
	var state := PBRunState.new()
	state.tech_pop = 1
	for unit: PBUnit in units:
		state.add_unit(unit)
	var card := PBCommandCard.new()
	add_child_autofree(card)
	card.refresh(PBSelection.of_unit(units[0].key()), state, _cfg, PBWavePlan.new(), units)
	var found: PBSkill = null
	for skill: PBSkill in card.skill_definitions():
		if skill != null and skill.id == &"boil_acid":
			found = skill
	assert_not_null(found)
	assert_eq(found.hit_count, 16)
	assert_eq(found.zone_outer_count, 8)
	assert_eq(PBSkillCostRules.mana(found, 10), 46.0)
	assert_eq(found.cooldown_ticks, 400)


func test_invalid_variant_links_and_zone_layouts_are_rejected() -> void:
	var source := _cfg.skills.by_id(&"boil_acid").clone()
	source.variant_id = &"missing"
	assert_ne(PBSkillVariantRules.check_link(source, _cfg.skills), "")
	source.variant_id = source.id
	assert_ne(PBSkillVariantRules.check_link(source, _cfg.skills), "")
	var zone := _cfg.skills.by_id(&"boil_acid_kage").clone()
	zone.zone_outer_count = 0
	assert_ne(PBHazardZone.validate_zone(zone), "")
	zone.zone_outer_count = 33
	assert_ne(PBHazardZone.validate_zone(zone), "")
	zone.zone_outer_count = 8
	assert_eq(PBHazardZone.validate_zone(zone), "")
	var buff := zone.zone_effects[0].duplicate(true) as PBBuff
	buff.mods_levels[PBBuffRules.ENEMY_DEFENCE] = PackedFloat32Array([NAN])
	assert_ne(PBBuffRules.validate(buff), "")
	buff.mods_levels[PBBuffRules.ENEMY_DEFENCE] = PackedFloat32Array([-4.0, -8.0])
	assert_eq(PBBuffRules.validate(buff), "")
	assert_eq(PBBuffRules.resolve(buff, 99)[PBBuffRules.ENEMY_DEFENCE], -8.0)
