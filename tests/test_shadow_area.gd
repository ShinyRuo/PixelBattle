extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _skill(enabled: bool = true) -> PBSkill:
	var skill := _cfg.skills.by_id(&"shadow_bind").clone()
	if enabled:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"strategist_couple":
				PBSkillPatchRules.apply(skill, bond.member_skill_patches[&"shikamaru"][skill.id])
	return skill


func _enemies() -> Array[PBEnemy]:
	var result: Array[PBEnemy] = []
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	for i: int in 6:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.01, 0.5, 0)
		enemy.slot = i
		enemy.lane = 0.0
		result.append(enemy)
	result[1].lane = 0.175
	result[2].lane = 0.176
	result[3].lane = 0.3
	result[4].alive = false
	result[5].spawn_tick = 1000
	return result


func _shot(skill: PBSkill) -> PBProjectile:
	# 本文件单测附加范围；引导的完整生命周期由独立测试及下方真实建队覆盖。
	skill = skill.clone()
	skill.channel_control = false
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 0.0, 1.0, false, skill.element, -1, skill, 10)
	return shot


func _advance(shot: PBProjectile, enemies: Array[PBEnemy], tick: int) -> void:
	PBShotRules.advance([shot], enemies, [], _cfg, tick, null, PBCombatOutcome.new())


func test_real_bond_patch_controls_only_neighbors_at_impact_with_separate_duration() -> void:
	var skill := _skill()
	assert_eq(PBSkillRules.validate(skill), "")
	assert_eq(skill.radius, 0.0)
	var enemies := _enemies()
	var shot := _shot(skill)
	shot.speed = 0.1
	_advance(shot, enemies, 1)
	assert_eq(enemies[1].buffs.count(1), 0)
	shot.speed = 1.0
	_advance(shot, enemies, 10)
	assert_false(shot.alive)
	assert_false(enemies[0].ready_to_fire(61))
	assert_false(enemies[1].ready_to_fire(60))
	assert_true(enemies[1].ready_to_fire(61))
	var old: float = enemies[1].distance
	enemies[1].advance(1.0, 60)
	assert_eq(enemies[1].distance, old)
	enemies[1].advance(1.0, 61)
	assert_lt(enemies[1].distance, old)
	for i: int in range(2, 6):
		assert_eq(enemies[i].buffs.count(10), 0, "范围外、尸体和未出生目标不控制")
	for enemy: PBEnemy in enemies:
		assert_eq(enemy.hp, enemy.max_hp, "无额外伤害")
	assert_eq(enemies[0].buffs.count(10), 1, "不重复给主目标挂周围控制")
	assert_eq(_cfg.skills.by_id(&"shadow_bind").impact_hold_radius, 0.0)


func test_without_bond_stays_single_target_and_dead_primary_does_not_spread() -> void:
	for enabled: bool in [false, true]:
		var enemies := _enemies()
		var shot := _shot(_skill(enabled))
		if enabled:
			enemies[0].alive = false
		_advance(shot, enemies, 1)
		assert_eq(enemies[1].buffs.count(1), 0)
		assert_false(shot.alive)


func test_impact_uses_current_positions_and_repeated_cast_refreshes_without_chaining() -> void:
	var enemies := _enemies()
	var skill := _skill()
	var shot := _shot(skill)
	shot.speed = 0.01
	_advance(shot, enemies, 1)
	enemies[0].distance = 0.8
	enemies[1].distance = 0.8
	enemies[1].lane = 0.1
	enemies[2].distance = 0.8
	enemies[2].lane = 0.2
	shot.speed = 1.0
	_advance(shot, enemies, 10)
	assert_eq(enemies[1].buffs.count(10), 1)
	assert_eq(enemies[2].buffs.count(10), 0)
	_advance(_shot(skill), enemies, 30)
	assert_eq(enemies[1].buffs.count(30), 1)
	assert_false(enemies[1].ready_to_fire(80))
	assert_true(enemies[1].ready_to_fire(81))


func test_invalid_impact_configuration_is_rejected_and_tooltip_explains_both_parts() -> void:
	var skill := _skill()
	var words := PBEffectWords.skill_body(skill, _cfg)
	assert_true(words.contains("0.175"))
	assert_true(words.contains("其他敌人 2.5 秒"))
	for value: float in [-1.0, NAN, INF]:
		skill.impact_hold_radius = value
		assert_ne(PBSkillRules.validate(skill), "")
	skill = _skill()
	skill.impact_hold_seconds = 0.0
	assert_ne(PBSkillRules.validate(skill), "")
	skill = _skill()
	skill.shot_cross_seconds = 0.0
	assert_ne(PBSkillRules.validate(skill), "")


func test_roster_bond_activation_fires_one_projectile_and_pays_once() -> void:
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0
	var owner := PBUnit.new(_cfg.characters.by_id(&"shikamaru"))
	var partner := PBUnit.new(_cfg.characters.by_id(&"temari"))
	var patches := PBBondRules.active_skill_patches([owner, partner], [owner], _cfg.bonds)
	var team := PBCombatRules.build_attackers(
		[owner],
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
	var caster: PBAttacker = team[0]
	for cast: PBSkillCast in caster.skills:
		if cast.skill.id == &"shadow_bind":
			caster.skills = [cast]
			break
	caster.ultimate = null
	caster.pos = Vector2(0.2, 0.0)
	caster.dps = 0.0
	caster.attack = 0.0
	caster.move_speed = 0.0
	caster.mp_regen = 0.0
	var wave := PBWave.new()
	wave.count = 3
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	sim.enemies()[1].lane = 0.1
	sim.enemies()[2].lane = 0.3
	var mana: float = caster.mp
	assert_true(sim.cast_skill_at(caster, sim.enemies()[0], 1))
	PBCastTestClock.release(sim, caster)
	var projectiles: int = 0
	for shot: PBProjectile in sim.shots():
		if shot.alive and shot.skill != null:
			projectiles += 1
	assert_eq(projectiles, 1)
	for i: int in 19:
		sim.step()
	assert_almost_eq(caster.mp, mana - caster.skills[0].skill.mp_cost, 0.001)
	assert_gt(caster.skills[0].ready_at, sim.current_tick())
	assert_eq(sim.enemies()[0].buffs.count(sim.current_tick()), 1)
	assert_eq(sim.enemies()[1].buffs.count(sim.current_tick()), 1)
	assert_eq(sim.enemies()[2].buffs.count(sim.current_tick()), 0)
