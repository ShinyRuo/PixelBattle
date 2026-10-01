extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(bonded: bool = true, level: int = 1) -> PBAttacker:
	var patches: Dictionary = {}
	if bonded:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"tsuchikage_guard":
				patches = bond.member_skill_patches
	var unit := PBUnit.new(_cfg.characters.by_id(&"onoki"))
	unit.level = level
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
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
			patches
		)[0]
	)
	one.ultimate = null
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	one.ninjutsu_crit_chance = 0.0
	return one


func _sim(one: PBAttacker) -> PBBattleSim:
	var wave := PBWave.new()
	wave.count = 5
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var distances := [0.5, 0.67, 0.6701, 0.755, 0.7551]
	for i: int in sim.enemies().size():
		var enemy: PBEnemy = sim.enemies()[i]
		enemy.distance = distances[i]
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func test_real_bond_has_full_inner_and_sixty_percent_outer_without_double_hit() -> void:
	var one := _caster()
	var sim := _sim(one)
	var mp_before: float = one.mp
	assert_true(sim.cast_skill(one, Vector2(0.5, 0.0), 1))
	for i: int in 18:
		sim.step()
	var enemies := sim.enemies()
	var damage: float = enemies[0].max_hp - enemies[0].hp
	assert_gt(damage, 0.0)
	assert_almost_eq(enemies[1].max_hp - enemies[1].hp, damage, 0.001)
	for i: int in [2, 3]:
		assert_almost_eq(enemies[i].max_hp - enemies[i].hp, damage * 0.6, 0.001)
	assert_eq(enemies[4].hp, enemies[4].max_hp)
	assert_almost_eq(one.mp, mp_before - one.skills[0].skill.mp_cost, 0.001)
	var cooldown: int = one.skills[0].ready_at
	for i: int in 20:
		sim.step()
	assert_eq(one.skills[0].ready_at, cooldown)
	assert_almost_eq(enemies[0].max_hp - enemies[0].hp, damage, 0.001)


func test_unbonded_radius_and_shared_resource_are_unchanged() -> void:
	var one := _caster(false)
	var sim := _sim(one)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	for i: int in 18:
		sim.step()
	assert_lt(sim.enemies()[1].hp, sim.enemies()[1].max_hp)
	assert_eq(sim.enemies()[2].hp, sim.enemies()[2].max_hp)
	var bonded := _caster()
	assert_almost_eq(bonded.skills[0].skill.radius, 0.255, 0.000001)
	var original := _cfg.skills.by_id(&"dust_release")
	assert_eq(original.radius, 0.17)
	assert_eq(original.full_damage_radius, 0.0)
	assert_eq(original.outer_damage_scale, 1.0)


func test_ten_levels_keep_formula_and_outer_ratio_after_ninjutsu_resistance() -> void:
	for level: int in range(1, 11):
		var one := _caster(true, level)
		var sim := _sim(one)
		var skill: PBSkill = one.skills[0].skill
		assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
		assert_eq(skill.element, PBElement.Type.EARTH)
		for enemy: PBEnemy in sim.enemies():
			enemy.armor = 1000.0
			enemy.ninjutsu_resist = 0.25
		sim.cast_skill(one, Vector2(0.5, 0.0), 1)
		for i: int in 18:
			sim.step()
		var expected: float = skill.damage * 0.75
		assert_almost_eq(100000.0 - sim.enemies()[0].hp, expected, 0.001)
		assert_almost_eq(100000.0 - sim.enemies()[3].hp, expected * 0.6, 0.001)


func test_ring_validation_rejects_non_circle_and_silent_partial_configuration() -> void:
	var skill: PBSkill = _caster().skills[0].skill
	assert_eq(PBSkillDamage.validate(skill), "")
	for value: float in [-0.1, INF, NAN, 0.3]:
		var copy := skill.clone()
		copy.full_damage_radius = value
		assert_ne(PBSkillDamage.validate(copy), "")
	for value: float in [-1.0, INF, NAN, 1.1]:
		var copy := skill.clone()
		copy.outer_damage_scale = value
		assert_ne(PBSkillDamage.validate(copy), "")
	var copy := skill.clone()
	copy.full_damage_radius = 0.0
	assert_ne(PBSkillDamage.validate(copy), "")
	copy = skill.clone()
	copy.line_length = 1.0
	assert_ne(PBSkillDamage.validate(copy), "")
	copy = skill.clone()
	copy.target = PBSkill.Target.ENEMY
	assert_ne(PBSkillDamage.validate(copy), "")
	copy = skill.clone()
	copy.pulse_radius_step = 0.1
	assert_ne(PBSkillDamage.validate(copy), "")


func test_preview_uses_two_real_radii_and_resets_for_next_ordinary_cast() -> void:
	var one := _caster()
	var sim := _sim(one)
	sim.cast_skill(one, Vector2(0.5, 0.0), 1)
	sim.step()
	var pool := PBTelegraphPool.new()
	add_child_autofree(pool)
	var field := Vector2(1.0, 0.3)
	pool.sync_pending([one], 0, field)
	assert_eq(pool.shown(), 1)
	var scale: float = PBLayout.px_per_unit(field)
	assert_almost_eq(pool.radius_of(0), 0.255 * scale, 0.001)
	assert_almost_eq(pool.inner_radius_of(0), 0.17 * scale, 0.001)
	var words: String = PBEffectWords.skill_body(one.skills[0].skill, _cfg)
	assert_string_contains(words, "340")
	assert_string_contains(words, "60%")
	one.skills[0].skill.full_damage_radius = 0.0
	one.skills[0].skill.outer_damage_scale = 1.0
	pool.sync_pending([one], 0, field)
	assert_eq(pool.inner_radius_of(0), 0.0)
