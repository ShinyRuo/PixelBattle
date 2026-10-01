extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _owner(bonded: bool = false, level: int = 1, gear: float = 0.0) -> PBAttacker:
	var card := PBUnit.new(_cfg.characters.by_id(&"kurotsuchi"))
	card.level = level
	var roster: Array[PBUnit] = [card]
	if bonded:
		roster.append(PBUnit.new(_cfg.characters.by_id(&"onoki")))
	var patches := PBBondRules.active_skill_patches(roster, [card], _cfg.bonds)
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers(
			[card],
			PBElement.Type.PHYSICAL,
			1.0,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			{},
			patches,
			[{PBStatRules.ATTACK_SPEED: gear}]
		)[0]
	)
	one.ultimate = null
	one.pos = Vector2.ZERO
	one.prime(20, _cfg)
	PBMotionAuraRules.install([one])
	return one


func _target() -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 1000.0
	one.hp = one.max_hp
	one.attack = 100.0
	one.attack_speed = 1.0
	one.move_speed = 0.01
	one.pos = Vector2(0.1, 0.0)
	one.reach = 0.1
	one.leash = 1.0
	one.prime(20)
	return one


func test_ten_levels_self_only_and_bonded_aura_share_same_growth() -> void:
	for level: int in range(1, 11):
		var one := _owner(false, level)
		var other := _target()
		PBMotionAuraRules.install([one, other])
		var expected: float = 0.10 + 0.04 * level
		assert_almost_eq(PBMotionAuraRules.bonus(one), expected, 0.000001)
		assert_almost_eq(PBMotionAuraRules.bonus(one, true), 0.15, 0.000001)
		assert_eq(PBMotionAuraRules.bonus(other), 0.0)
		var bonded := _owner(true, level)
		PBMotionAuraRules.install([bonded, other])
		assert_almost_eq(PBMotionAuraRules.bonus(other), expected, 0.000001)
		assert_almost_eq(PBMotionAuraRules.bonus(bonded), expected, 0.000001)
		assert_eq(bonded.skills[1].skill.radius, 0.3)
	assert_false(_cfg.characters.by_id(&"kurotsuchi").passives.has(PBStatRules.ATTACK_SPEED))
	assert_eq(_cfg.skills.by_id(&"light_rock").radius, 0.0)


func test_boundary_departure_death_and_overlapping_sources_do_not_leave_bonus() -> void:
	var weak := _owner(true, 1)
	var strong := _owner(true, 10)
	var other := _target()
	other.pos = Vector2(0.3, 0.0)
	PBMotionAuraRules.install([weak, strong, other])
	assert_almost_eq(PBMotionAuraRules.bonus(other), 0.5, 0.000001)
	strong.alive = false
	assert_almost_eq(PBMotionAuraRules.bonus(other), 0.14, 0.000001)
	other.pos.x = 0.3001
	assert_eq(PBMotionAuraRules.bonus(other), 0.0)
	other.pos.x = 0.3
	weak.pos.x = -0.01
	assert_eq(PBMotionAuraRules.bonus(other), 0.0)
	weak.pos.x = 0.0
	weak.buffs.add(PBBuff.new(), {PBBuffRules.SILENCE: 1.0}, 0, 100, 0)
	assert_almost_eq(PBMotionAuraRules.bonus(other), 0.14, 0.000001)
	PBMotionAuraRules.install([other])
	assert_eq(PBMotionAuraRules.bonus(other), 0.0)


func test_gear_and_aura_add_without_multiplying_existing_bonus() -> void:
	var clean := _owner(false, 10)
	var geared := _owner(false, 10, 0.5)
	assert_almost_eq(
		geared.attack_speed * PBMotionAuraRules.attack_scale(geared),
		clean.attack_speed * 2.0,
		0.000001
	)
	var other := _target()
	other.move_speed_bonus = 0.2
	other.move_speed = 0.012
	var source := _owner(true)
	PBMotionAuraRules.install([source, other])
	assert_almost_eq(PBMotionAuraRules.move_step(other), 0.0135, 0.000001)
	assert_eq(other.move_speed, 0.012)


func test_attack_cadence_scales_windup_and_respects_cap_and_tick_rate() -> void:
	var source := _owner(true, 10)
	var other := _target()
	other.windup_ticks = 6
	PBMotionAuraRules.install([source, other])
	assert_eq(other.attack_interval(), 13)
	assert_true(other.begin_swing(0))
	assert_eq(other.next_shot_at, 4)
	other.on_fired(4)
	assert_eq(other.next_shot_at, 13)
	other.pos.x = 0.4
	assert_eq(other.attack_interval(), 20)
	other.on_fired(20)
	assert_eq(other.next_shot_at, 34)
	other.pos.x = 0.1
	other.prime(40)
	assert_eq(other.attack_interval(), 27)
	other.attack_speed = 1000.0
	other.prime(20)
	assert_eq(other.attack_interval(), PBAttacker.fastest_ticks(20))
	other.attack_speed = 0.0
	other.prime(20)
	assert_eq(other.attack_interval(), 1)


func test_both_movement_paths_use_current_aura_without_touching_base_speed() -> void:
	var source := _owner(true)
	var other := _target()
	PBMotionAuraRules.install([source, other])
	var enemy := PBEnemy.new()
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	enemy.spawn(wave, 0.0, 0.8, 0)
	PBMoveRules.press_forward(other, enemy, 1.0)
	assert_almost_eq(other.pos.x, 0.1115, 0.000001)
	other.pos = Vector2(0.1, 0.0)
	PBMoveRules.close_in(other, enemy, 1.0)
	assert_almost_eq(other.pos.x, 0.1115, 0.000001)
	other.pos = Vector2(0.4, 0.0)
	PBMoveRules.close_in(other, enemy, 1.0)
	assert_almost_eq(other.pos.x, 0.41, 0.000001)
	assert_eq(other.move_speed, 0.01)


func test_summoned_invulnerable_phantom_receives_aura_but_empty_slot_does_not() -> void:
	var source := _owner(true, 10)
	var ghost := _target()
	ghost.summoned = true
	ghost.phantom = true
	PBMotionAuraRules.install([source, ghost])
	assert_false(ghost.is_targetable())
	assert_almost_eq(PBMotionAuraRules.bonus(ghost), 0.5, 0.000001)
	assert_eq(ghost.attack_interval(), 13)
	PBSummonRules.dismiss(ghost)
	assert_eq(PBMotionAuraRules.bonus(ghost), 0.0)


func test_passive_cannot_be_cast_or_spend_mana_and_clone_reinstalls_sources() -> void:
	var one := _owner(true)
	assert_false(PBSkillRules.can_cast(one, 2, 1000))
	var copy := one.clone()
	assert_true(copy.motion_sources.is_empty())
	PBMotionAuraRules.install([copy])
	assert_almost_eq(PBMotionAuraRules.bonus(copy), 0.14, 0.000001)
	one.skills[1].caster_level = 10
	assert_almost_eq(PBMotionAuraRules.bonus(copy), 0.14, 0.000001)
	assert_string_contains(PBEffectWords.skill_body(copy.skills[1].skill, _cfg, 10), "+50%")
	assert_string_contains(PBEffectWords.skill_body(copy.skills[1].skill, _cfg), "不耗蓝")


func test_validation_refuses_values_and_active_payloads_that_would_be_ignored() -> void:
	var skill := _cfg.skills.by_id(&"light_rock").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	for key: String in ["attack_speed_aura", "attack_speed_aura_growth", "move_speed_aura"]:
		for value: float in [-0.1, INF, NAN]:
			var copy := skill.clone()
			copy.set(key, value)
			assert_ne(PBMotionAuraRules.validate(copy), "")
	var copy := skill.clone()
	copy.mp_cost = 1.0
	assert_ne(PBMotionAuraRules.validate(copy), "")
	copy = skill.clone()
	copy.on_hit = [PBBuff.new()]
	assert_ne(PBMotionAuraRules.validate(copy), "")
	copy = skill.clone()
	copy.target = PBSkill.Target.GROUND
	assert_ne(PBMotionAuraRules.validate(copy), "")


func test_real_battle_aura_increases_normal_hits_without_increasing_each_hit() -> void:
	var damages: Array[float] = []
	for bonded: bool in [false, true]:
		var source := _owner(bonded, 10)
		source.attack = 0.0
		source.dps = 0.0
		source.move_speed = 0.0
		var other := _target()
		other.slot = 1
		other.home = Vector2(0.1, 0.0)
		other.move_speed = 0.0
		other.reach = 1.0
		var wave := PBWave.new()
		wave.count = 1
		wave.hp_each = 100000.0
		wave.element = PBElement.Type.PHYSICAL
		var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [source, other])
		var enemy: PBEnemy = sim.enemies()[0]
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
		enemy.distance = 0.5
		for i: int in 130:
			sim.step()
		damages.append(enemy.max_hp - enemy.hp)
		assert_eq(other.damage_per_shot(), 100.0)
	assert_gt(damages[1], damages[0])
	assert_almost_eq(fmod(damages[1], 100.0), 0.0, 0.000001)
