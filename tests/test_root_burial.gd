extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _patch() -> Dictionary:
	for bond: PBBond in _cfg.bonds.all():
		if bond.id == &"leaf_and_root":
			return bond.member_skill_patches[&"danzo"][&"root_burial"]
	return {}


func _cast(level: int = 1, boosted: bool = false) -> PBSkillCast:
	var skill := _cfg.skills.by_id(&"root_burial").clone()
	if boosted:
		PBSkillPatchRules.apply(skill, _patch())
	var cast := PBSkillCast.new(skill, level)
	cast.cast_on(0, 0)
	return cast


func _enemies() -> Array[PBEnemy]:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemies: Array[PBEnemy] = []
	for i: int in 3:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, 0.5, 0, float(i) * 0.1)
		enemies.append(enemy)
	return enemies


func test_initial_hold_is_single_target_at_all_original_levels() -> void:
	var seconds := [1, 1, 2, 2, 2, 3, 3, 3, 3, 4]
	for level: int in range(1, 11):
		var enemies := _enemies()
		var cast := _cast(level)
		PBSkillRules.prepare_target(cast, enemies, _cfg, 1)
		var end: int = seconds[level - 1] * _cfg.tick_rate
		assert_false(enemies[0].ready_to_fire(end))
		assert_true(enemies[0].ready_to_fire(end + 1))
		assert_true(enemies[1].ready_to_fire(1))
		assert_eq(enemies[0].hp, enemies[0].max_hp)


func test_explosion_deals_local_damage_and_only_bond_adds_local_stun() -> void:
	for boosted: bool in [false, true]:
		var cast := _cast(1, boosted)
		var enemies := _enemies()
		PBSkillRules.prepare_target(cast, enemies, _cfg, 1)
		PBSkillRules.land_on_enemy(cast, enemies, _cfg, 40, null, 100.0)
		for i: int in 2:
			assert_eq(enemies[i].hp, 99900.0)
			assert_eq(enemies[i].ready_to_fire(80), not boosted)
			assert_true(enemies[i].ready_to_fire(81))
		assert_eq(enemies[2].hp, enemies[2].max_hp)
		assert_true(enemies[2].ready_to_fire(40))
		assert_eq(cast.skill.slow_ticks, 0)


func test_patch_does_not_modify_shared_resource_or_duplicate_on_reapply() -> void:
	var original := _cfg.skills.by_id(&"root_burial")
	var copy := original.clone()
	var count_before: int = original.on_hit.size()
	PBSkillPatchRules.apply(copy, _patch())
	PBSkillPatchRules.apply(copy, _patch())
	assert_eq(copy.on_hit.size(), count_before + 1)
	assert_eq(original.on_hit.size(), count_before)
	assert_string_contains(PBEffectWords.skill_body(copy, _cfg), "命中眩晕")
	assert_false(PBEffectWords.skill_body(copy, _cfg).contains("全场减速"))
	assert_string_contains("、".join(PBEffectWords.patch_words(_patch())), "2.0 秒")


func test_real_sim_waits_two_seconds_before_explosion() -> void:
	var unit := PBUnit.new(_cfg.characters.by_id(&"danzo"))
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	var cast := _cast(1, true)
	cast.skill.damage = 100.0
	one.skills = [cast]
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	sim.cast_skill_at(one, sim.enemies()[0], 1)
	for i: int in 45:
		sim.step()
	assert_eq(sim.enemies()[1].hp, 100000.0)
	sim.step()
	assert_lt(sim.enemies()[1].hp, 100000.0)
	assert_false(sim.enemies()[1].ready_to_fire(46))
	assert_eq(sim._slow_until, -1)
