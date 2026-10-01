extends GutTest
## 原版追牙：五只独立召唤物、分级攻击继承、只定身、追击与生命周期。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.march_seconds = 1000000.0
	_cfg.unit_min_gap = 0.0


func _team(level: int = 1, patch: Dictionary = {}) -> Array[PBAttacker]:
	var unit := PBUnit.new(_cfg.characters.by_id(&"kakashi"))
	unit.level = level
	return PBCombatRules.build_attackers(
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
		{&"kakashi": {&"pursuing_fangs": patch}}
	)


func _cast(team: Array[PBAttacker]) -> PBSkillCast:
	return team[0].skills[0]


func _sim(team: Array[PBAttacker]) -> PBBattleSim:
	var one := team[0]
	one.ultimate = null
	one.mp_regen = 0.0
	one.reach = 0.05
	one.move_speed = 0.025
	one.leash = 1.0
	one.pos = Vector2(0.1, 0.0)
	one.home = one.pos
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 1000000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	one.next_shot_at = 1000000
	sim.enemies()[0].distance = 0.12
	sim.enemies()[1].distance = 0.7
	return sim


func test_all_ten_levels_summon_five_with_correct_attack_and_element() -> void:
	for level: int in range(1, 11):
		var team := _team(level)
		var cast := _cast(team)
		team[0].revive()
		assert_eq(cast.skill.damage, 0.0)
		assert_eq(cast.skill.shot_cross_seconds, 0.0)
		assert_eq(PBSummonRules.raise_from(team, team[0], cast.skill, 10, _cfg, -1, level, 1), 5)
		for i: int in range(1, 6):
			var dog := team[i]
			var expected: float = team[0].attack * (0.30 + 0.03 * level)
			assert_almost_eq(dog.attack, expected, 0.001)
			assert_almost_eq(dog.damage_per_shot(), expected, 0.001)
			assert_eq(dog.attack_element, PBElement.Type.THUNDER)
			assert_eq(PBCritRules.attack_kind(dog), PBDamageKind.Type.TAIJUTSU)
			assert_eq(dog.expires_at, 110)
			assert_eq(dog.forced_target, 1)
			assert_true(dog.focus_named_target)
			assert_eq(dog.leash, team[0].leash)


func test_existing_rival_bond_scales_base_and_level_growth() -> void:
	var patch: Dictionary = {}
	for bond: PBBond in _cfg.bonds.all():
		if bond.id == &"eternal_rivals":
			patch = bond.member_skill_patches[&"kakashi"][&"pursuing_fangs"]
	assert_false(patch.is_empty())
	for level: int in [1, 5, 10]:
		var team := _team(level, patch)
		var cast := _cast(team)
		PBSummonRules.raise_from(team, team[0], cast.skill, 0, _cfg, -1, level, 0)
		assert_almost_eq(team[1].attack, team[0].attack * (0.30 + level * 0.03) * 1.7, 0.001)
	assert_almost_eq(_cfg.skills.by_id(&"pursuing_fangs").summon_power, 0.33, 0.00001)
	assert_almost_eq(_cfg.skills.by_id(&"pursuing_fangs").summon_power_growth, 0.03, 0.00001)


func test_real_cast_roots_but_does_not_stun_or_deal_an_extra_hit() -> void:
	var team := _team()
	var sim := _sim(team)
	var target := sim.enemies()[1]
	var before: float = team[0].mp
	assert_true(sim.cast_skill_at(team[0], target, 1))
	PBCastTestClock.release(sim, team[0])
	assert_eq(target.hp, target.max_hp)
	assert_true(target.ready_to_fire(1), "束缚不能禁止攻击")
	assert_eq(target.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 106), 0.0)
	assert_eq(target.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 107), 1.0)
	target.speed = 0.1
	var at := target.pos()
	target.march_to(Vector2.ZERO, 1.0, 1)
	assert_eq(target.pos(), at)
	assert_eq(team[0].mp, before - 10.0)
	assert_eq(_cast(team).ready_at, 546)
	for shot: PBProjectile in sim.shots():
		assert_false(shot.alive)


func test_pursuers_walk_past_decoy_and_really_damage_selected_enemy() -> void:
	var team := _team()
	var sim := _sim(team)
	var target := sim.enemies()[1]
	assert_true(sim.cast_skill_at(team[0], target, 1))
	for tick: int in 45:
		sim.step()
	assert_lt(target.hp, target.max_hp)
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	for i: int in range(1, 6):
		assert_gt(team[i].pos.x, 0.5, "预留位不能因 leash=0 被拴在出生点")
		assert_eq(team[i].aim_at, 1)
		assert_eq(team[i].forced_target, 1)


func test_original_target_death_restores_ordinary_target_selection() -> void:
	var team := _team()
	var sim := _sim(team)
	assert_true(sim.cast_skill_at(team[0], sim.enemies()[1], 1))
	PBCastTestClock.release(sim, team[0])
	sim.enemies()[1].alive = false
	var dog := team[1]
	assert_null(PBStrikeRules.named_target(dog, sim.enemies(), 1))
	assert_same(PBStrikeRules.first_reachable(dog, sim.enemies(), 0, 1), sim.enemies()[0])
	for tick: int in 20:
		sim.step()
	assert_lt(sim.enemies()[0].hp, sim.enemies()[0].max_hp)


func test_target_invalid_before_landing_does_not_summon_without_a_target() -> void:
	var team := _team()
	var sim := _sim(team)
	assert_true(sim.cast_skill_at(team[0], sim.enemies()[1], 1))
	sim.enemies()[1].alive = false
	PBCastTestClock.release(sim, team[0])
	for i: int in range(1, 6):
		assert_false(team[i].alive)
	assert_eq(_cast(team).ready_at, 546)
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp)


func test_caster_death_does_not_remove_dogs_and_five_seconds_expires_them() -> void:
	var team := _team()
	var sim := _sim(team)
	assert_true(sim.cast_skill_at(team[0], sim.enemies()[1], 1))
	PBCastTestClock.release(sim, team[0])
	team[0].alive = false
	for tick: int in 99:
		sim.step()
	assert_eq(sim.current_tick(), 105)
	assert_true(team[1].alive)
	sim.step()
	for i: int in range(1, 6):
		assert_false(team[i].alive)
		assert_eq(team[i].forced_target, -1)
		assert_false(team[i].focus_named_target)
	assert_eq(sim.result().allies_lost, 0, "自然消失不记阵亡")


func test_reused_slot_does_not_keep_pursuit_or_old_windup() -> void:
	var team := _team()
	var cast := _cast(team)
	PBSummonRules.raise_from(team, team[0], cast.skill, 0, _cfg, -1, 10, 1)
	team[1].swinging = true
	PBSummonRules.dismiss(team[1])
	var other := cast.skill.clone()
	other.summon_focus = false
	other.summon_count = 1
	other.summon_power = 0.5
	other.summon_power_growth = 0.0
	assert_eq(PBSummonRules.raise_from(team, team[0], other, 12, _cfg), 1)
	assert_false(team[1].swinging)
	assert_false(team[1].focus_named_target)
	assert_eq(team[1].forced_target, -1)
	assert_eq(team[1].next_shot_at, 12)
	assert_almost_eq(team[1].attack, team[0].attack * 0.5, 0.001)


func test_data_validation_and_tooltip_follow_current_level() -> void:
	var skill := _cast(_team()).skill
	var text := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_string_contains(text, "60% 攻击力")
	assert_string_contains(text, "优先追击")
	assert_string_contains(text, "无直接伤害")
	skill.summon_power_growth = NAN
	assert_ne(PBSummonRules.validate(skill), "")
	skill.summon_power_growth = 0.03
	skill.target = PBSkill.Target.NONE
	assert_ne(PBSummonRules.validate(skill), "")
	skill.target = PBSkill.Target.ENEMY
	skill.summon_count = 0
	assert_ne(PBSummonRules.validate(skill), "")
