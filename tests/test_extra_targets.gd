extends GutTest

const CASES: Array = [
	[&"kurenai", &"haze_illusion", &"team_eight", 4],
	[&"ino", &"mind_transfer", &"ino_shika_cho", 2],
	[&"itachi", &"tsukuyomi", &"vermilion_pair", 2],
	[&"kurenai", &"mirror_ward", &"crimson_dusk", 5],
	[&"rin_nohara", &"inspire", &"three_of_them", 5],
	[&"chiyo", &"reincarnation", &"puppet_masters", 2],
]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(entry: Array, enabled: bool = true) -> PBAttacker:
	var owner := PBUnit.new(_cfg.characters.by_id(entry[0]))
	var members: Array[PBUnit] = [owner]
	if enabled:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == entry[2]:
				for id: StringName in bond.member_ids:
					if id != entry[0]:
						members.append(PBUnit.new(_cfg.characters.by_id(id)))
	var patches := PBBondRules.active_skill_patches(members, [owner], _cfg.bonds)
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
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
		)[0]
	)
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == entry[1]:
			one.skills = [cast]
			break
	one.pos = Vector2(0.2, 0.0)
	one.ultimate = null
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.mp_regen = 0.0
	return one


func _sim(one: PBAttacker, allies: bool = false) -> PBBattleSim:
	var team: Array[PBAttacker] = [one]
	if allies:
		for i: int in 5:
			var friend := PBUnit.new(_cfg.characters.by_id(&"rock_lee"))
			var actor: PBAttacker = (
				PBCombatRules
				. build_attackers(
					[friend], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg
				)[0]
			)
			actor.ultimate = null
			actor.skills.clear()
			actor.attack = 0.0
			actor.dps = 0.0
			actor.slot = i + 1
			actor.max_hp = 100000.0
			actor.hp = actor.max_hp
			actor.pos = Vector2(0.5, 0.0)
			actor.move_speed = 0.0
			team.append(actor)
	var wave := PBWave.new()
	wave.count = 6
	wave.hp_each = 100000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	return sim


func _cast(sim: PBBattleSim, one: PBAttacker) -> void:
	if one.skills[0].skill.target == PBSkill.Target.ALLY:
		assert_true(sim.cast_skill_on(one, sim.attackers()[5], 1))
	else:
		assert_true(sim.cast_skill_at(one, sim.enemies()[5], 1))


func _affected(sim: PBBattleSim, allies: bool = false) -> int:
	var count: int = 0
	if allies:
		for actor: PBAttacker in sim.attackers():
			if (
				actor.buffs.count(sim.current_tick()) > 0
				or (
					actor.attribute_profile != null
					and not actor.attribute_profile.temporary.is_empty()
				)
			):
				count += 1
	else:
		for enemy: PBEnemy in sim.enemies():
			if enemy.buffs.count(sim.current_tick()) > 0:
				count += 1
	return count


func test_six_real_bond_skills_gain_the_promised_targets_and_pay_only_once() -> void:
	for entry: Array in CASES:
		for enabled: bool in [false, true]:
			var one := _caster(entry, enabled)
			var allied: bool = one.skills[0].skill.target == PBSkill.Target.ALLY
			var sim := _sim(one, allied)
			var mana: float = one.mp
			_cast(sim, one)
			assert_eq(one.mp, mana, "排队时还没有扣蓝")
			for i: int in 15:
				sim.step()
			assert_eq(_affected(sim, allied), int(entry[3]) if enabled else 1, String(entry[1]))
			assert_almost_eq(one.mp, mana - one.skills[0].skill.mp_cost, 0.0001)
			assert_eq(one.skills[0].ready_at, 6 + one.skills[0].skill.cooldown_ticks)
			assert_eq(PBSkillTargets.validate(one.skills[0].skill), "")
			assert_eq(_cfg.skills.by_id(entry[1]).max_targets, 0, "共享资源仍是基础单体")


func test_selection_prioritizes_primary_then_distance_and_slot_including_boundary() -> void:
	var one := _caster(CASES[0])
	one.skills[0].skill.extra_target_radius = 0.25
	one.skills[0].skill.extra_target_from_caster = false
	var sim := _sim(one)
	var cast := one.skills[0]
	cast.target_slot = 5
	cast.skill.extra_target_radius = 0.125
	sim.enemies()[0].distance = 0.625
	sim.enemies()[1].distance = 0.375
	sim.enemies()[2].distance = 0.5001
	sim.enemies()[2].alive = false
	sim.enemies()[3].spawn_tick = 99
	sim.enemies()[4].distance = 0.626
	assert_eq(PBSkillTargets.enemies(cast, sim.enemies(), 0), PackedInt32Array([5, 0, 1]))
	sim.enemies()[5].alive = false
	assert_true(PBSkillTargets.enemies(cast, sim.enemies(), 0).is_empty())


func test_invalid_primary_does_not_redirect_enemy_or_ally_cast() -> void:
	for entry: Array in [CASES[0], CASES[3]]:
		var one := _caster(entry)
		var allied: bool = one.skills[0].skill.target == PBSkill.Target.ALLY
		var sim := _sim(one, allied)
		_cast(sim, one)
		if allied:
			sim.attackers()[5].alive = false
		else:
			sim.enemies()[5].alive = false
		for i: int in 15:
			sim.step()
		assert_eq(_affected(sim, allied), 0)


func test_each_projectile_keeps_its_target_when_one_dies_and_caster_moves() -> void:
	var one := _caster(CASES[0])
	one.skills[0].skill.shot_cross_seconds = 2.0
	var sim := _sim(one)
	_cast(sim, one)
	PBCastTestClock.release(sim, one)
	var selected := PackedInt32Array()
	for shot: PBProjectile in sim.shots():
		if shot.alive:
			selected.append(shot.target)
	assert_eq(selected, PackedInt32Array([5, 0, 1, 2]))
	sim.enemies()[0].alive = false
	one.pos = Vector2(0.9, 0.0)
	one.alive = false
	for i: int in 25:
		sim.step()
	assert_eq(_affected(sim), 3)
	assert_eq(sim.enemies()[3].buffs.count(sim.current_tick()), 0)
	assert_eq(sim.enemies()[4].buffs.count(sim.current_tick()), 0)


func test_full_or_partial_projectile_pool_never_falls_back_to_instant_hit() -> void:
	for available: int in [0, 1]:
		var one := _caster(CASES[0])
		var sim := _sim(one)
		# 在发射读点直接验证满池，避免模拟推进时先回收测试占位弹。
		for i: int in sim.shots().size():
			sim.shots()[i].alive = i >= available
		var cast := one.skills[0]
		cast.target_slot = 5
		sim._launch_skill(one, cast)
		assert_eq(_affected(sim), 0)
		if available > 0:
			assert_eq(sim.shots()[0].target, 5, "有限名额必须先保证主目标")
			assert_eq(sim.shots()[0].skill, cast.skill)


func test_instant_enemy_path_uses_the_same_selection_and_does_not_chain_expand() -> void:
	var one := _caster(CASES[0])
	one.skills[0].skill.extra_target_radius = 0.25
	one.skills[0].skill.extra_target_from_caster = false
	one.skills[0].skill.shot_cross_seconds = 0.0
	var sim := _sim(one)
	sim.enemies()[0].distance = 0.7
	sim.enemies()[1].distance = 0.8
	sim.enemies()[2].distance = 0.9
	sim.enemies()[3].distance = 0.9
	sim.enemies()[4].distance = 0.9
	_cast(sim, one)
	PBCastTestClock.release(sim, one)
	assert_eq(_affected(sim), 2, "不能从追加目标再次扩散搜索")
	assert_gt(sim.enemies()[5].buffs.count(1), 0)
	assert_gt(sim.enemies()[0].buffs.count(1), 0)


func test_cooldown_reset_selects_again_without_retargeting_old_projectiles() -> void:
	var one := _caster(CASES[0])
	one.skills[0].skill.extra_target_radius = 0.25
	one.skills[0].skill.extra_target_from_caster = false
	one.skills[0].skill.shot_cross_seconds = 4.0
	var sim := _sim(one)
	_cast(sim, one)
	PBCastTestClock.release(sim, one)
	PBCastTestClock.recover(sim, one)
	one.skills[0].ready_at = sim.current_tick()
	sim.enemies()[3].distance = 0.9
	sim.enemies()[4].distance = 0.9
	assert_true(sim.cast_skill_at(one, sim.enemies()[4], 1))
	PBCastTestClock.release(sim, one)
	var targets := PackedInt32Array()
	for shot: PBProjectile in sim.shots():
		if shot.alive:
			targets.append(shot.target)
	assert_eq(targets, PackedInt32Array([5, 0, 1, 2, 4, 3]))


func test_increasing_targets_preserves_unlimited_area_and_counts_single_primary() -> void:
	var skill := PBSkill.new()
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.TARGETS_ADD: 4.0})
	assert_eq(skill.max_targets, 0, "范围不限不能因增加目标反而受限")
	skill.target = PBSkill.Target.ENEMY
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.TARGETS_ADD: 4.0})
	assert_eq(skill.max_targets, 5)
	assert_ne(PBSkillTargets.validate(skill), "", "不能默默变成全场搜索")
	skill.extra_target_radius = 0.25
	assert_eq(PBSkillTargets.validate(skill), "")
	skill.extra_target_radius = INF
	assert_ne(PBSkillTargets.validate(skill), "")


func test_real_patches_validate_and_description_shows_total_and_selection_range() -> void:
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_skill_patches:
			for id: StringName in bond.member_skill_patches[who]:
				var skill := _cfg.skills.by_id(id).clone()
				PBSkillPatchRules.apply(skill, bond.member_skill_patches[who][id])
				assert_eq(PBSkillTargets.validate(skill), "", "%s/%s" % [bond.id, id])
	var body := PBEffectWords.skill_body(_caster(CASES[0]).skills[0].skill, _cfg)
	assert_string_contains(body, "最多 4 个目标")
	assert_string_contains(body, "优先主目标")
	assert_string_contains(body, "0.60")


func test_multiple_targets_do_not_repeat_self_effects_and_ally_projectiles_use_same_list() -> void:
	var one := _caster(CASES[3])
	one.skills[0].skill.extra_target_radius = 0.25
	one.skills[0].skill.extra_target_from_caster = false
	var self_mana := PBBuff.new()
	self_mana.id = &"probe_self_mana"
	self_mana.mods = {PBBuffRules.MANA: 3.0}
	one.skills[0].skill.on_self = [self_mana]
	one.skills[0].skill.shot_cross_seconds = 2.0
	var sim := _sim(one, true)
	var before: float = one.mp
	_cast(sim, one)
	PBCastTestClock.release(sim, one)
	assert_eq(_affected(sim, true), 0, "治疗 / 护盾弹道也必须等飞到")
	assert_almost_eq(one.mp, before - one.skills[0].skill.mp_cost + 3.0, 0.0001)
	sim.attackers()[0].alive = false
	sim.attackers()[1].alive = false
	for i: int in 25:
		sim.step()
	assert_eq(_affected(sim, true), 4, "一份弹道的目标死亡不影响其他弹道")
