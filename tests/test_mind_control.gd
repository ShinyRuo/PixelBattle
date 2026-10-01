extends GutTest

const TIMES: Array[float] = [1, 1, 2, 2, 2, 3, 3, 4, 4, 5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _caster(level: int = 10, bonded: bool = true) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"ino"))
	unit.level = level
	var caster: PBAttacker = (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	caster.ultimate = null
	caster.attack = 0.0
	caster.dps = 0.0
	caster.move_speed = 0.0
	caster.pos = Vector2(0.2, 0.0)
	caster.revive()
	if bonded:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"ino_shika_cho":
				PBSkillPatchRules.apply(
					caster.skills[0].skill, bond.member_skill_patches[&"ino"][&"mind_transfer"]
				)
	return caster


func _enemies(level: int = 1) -> Array[PBEnemy]:
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	wave.enemy_level = level
	var enemies: Array[PBEnemy] = []
	for i: int in 3:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, 0.6 + i * 0.05, 0)
		enemy.slot = i
		enemies.append(enemy)
	return enemies


func _shots(caster: PBAttacker, enemies: Array[PBEnemy]) -> Array[PBProjectile]:
	var cast := caster.skills[0]
	cast.cast_on(0, 0)
	PBSkillOrders.issue(caster, cast, _cfg, 0, null)
	var shots: Array[PBProjectile] = []
	for i: int in 2:
		var shot := PBProjectile.new()
		shot.launch(
			caster.pos,
			i,
			0.0,
			1.0,
			false,
			cast.skill.element,
			caster.slot,
			cast.skill,
			cast.caster_level
		)
		shot.primary_target = i == 0
		if i == 0:
			shot.channel = caster.channel
			shot.channel.target_ref = weakref(enemies[0])
		shots.append(shot)
	return shots


func test_ten_levels_primary_and_extra_have_independent_pve_durations() -> void:
	for level: int in range(1, 11):
		var caster := _caster(level)
		var enemies := _enemies(99)
		PBShotRules.advance(
			_shots(caster, enemies), enemies, [caster], _cfg, 10, null, PBCombatOutcome.new()
		)
		var end: int = 10 + roundi(TIMES[level - 1] * 20.0)
		assert_false(caster.ready_to_fire(end))
		assert_false(enemies[0].ready_to_fire(end))
		assert_true(caster.ready_to_fire(end + 1))
		assert_true(enemies[0].ready_to_fire(end + 1))
		assert_false(enemies[1].ready_to_fire(end + 1))
		assert_false(enemies[1].ready_to_fire(10 + roundi(TIMES[level - 1] * 40.0)))
		assert_true(enemies[1].ready_to_fire(11 + roundi(TIMES[level - 1] * 40.0)))
		assert_false(enemies[1].controlled(end + 1))


func test_strictly_lower_level_converts_only_primary_and_restores_at_expiry() -> void:
	for enemy_level: int in [9, 10, 11]:
		var caster := _caster()
		var enemies := _enemies(enemy_level)
		PBShotRules.advance(
			_shots(caster, enemies), enemies, [caster], _cfg, 10, null, PBCombatOutcome.new()
		)
		assert_eq(enemies[0].controlled(10), enemy_level < 10)
		assert_eq(enemies[0].is_hostile(10), enemy_level >= 10)
		assert_true(enemies[0].is_active(10))
		assert_false(enemies[1].controlled(10))
		assert_false(caster.ready_to_fire(10))
		assert_false(enemies[0].controlled(111))
		assert_true(enemies[0].is_hostile(111))


func test_interruption_restores_primary_without_releasing_extra_stun() -> void:
	for reason: int in 4:
		var caster := _caster()
		var enemies := _enemies()
		PBShotRules.advance(
			_shots(caster, enemies), enemies, [caster], _cfg, 10, null, PBCombatOutcome.new()
		)
		match reason:
			0:
				caster.alive = false
			1, 2:
				var buff := PBBuff.new()
				buff.id = &"mind_interrupt"
				var key := PBBuffRules.STUN if reason == 1 else PBBuffRules.SILENCE
				caster.buffs.add(buff, {key: 1.0}, 11, 20, 0)
			3:
				enemies[0].buffs.clear()
		assert_false(enemies[0].controlled(11))
		assert_false(enemies[1].ready_to_fire(11))


func test_real_order_pays_once_and_controlled_units_fight_each_other_not_caster() -> void:
	var caster := _caster(10, false)
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	wave.atk_each = 100.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [caster])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.6 + enemy.slot * 0.05
		enemy.speed = 0.0
		enemy.reach = 0.1
		enemy.windup_ticks = 0
		enemy.shot_speed = 0.0
		enemy.attack_interval = 20
	var mana: float = caster.mp
	caster.mp_regen = 0.0
	assert_true(sim.cast_skill_at(caster, sim.enemies()[0], 1))
	for i: int in 12:
		sim.step()
	assert_true(sim.enemies()[0].controlled(sim.current_tick()))
	assert_lt(sim.enemies()[0].hp, 10000.0)
	assert_lt(sim.enemies()[1].hp, 10000.0)
	assert_eq(caster.hp, caster.max_hp)
	assert_eq(caster.mp, mana - 82.0)
	assert_eq(caster.skills[0].ready_at, caster.skills[0].skill.cooldown_ticks + 6)


func test_allied_normal_area_and_inflight_attacks_skip_converted_target() -> void:
	var caster := _caster()
	var enemies := _enemies()
	PBShotRules.advance(
		_shots(caster, enemies), enemies, [caster], _cfg, 10, null, PBCombatOutcome.new()
	)
	var ally := PBAttacker.new()
	ally.reach = 2.0
	ally.forced_target = 0
	assert_null(PBStrikeRules.named_target(ally, enemies, 11))
	assert_ne(PBStrikeRules.first_reachable(ally, enemies, 0, 11), enemies[0])
	var out := PBCombatOutcome.new()
	PBStrikeRules.land(ally, enemies[0], 100.0, false, enemies, _cfg, 11, null, out)
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 1.0)
	PBShotRules.advance([shot], enemies, [ally], _cfg, 11, null, out)
	var skill := PBSkill.new()
	skill.radius = 2.0
	var cast := PBSkillCast.new(skill)
	cast.spot = Vector2.ZERO
	PBSkillRules.land(cast, enemies, 0, _cfg, 11, ally, 100.0)
	assert_eq(enemies[0].hp, 10000.0)
	assert_lt(enemies[1].hp, 10000.0)
	assert_false(shot.alive)


func test_controlled_last_enemy_cannot_leak_and_spawn_clears_old_control() -> void:
	var caster := _caster()
	var enemies := _enemies()
	PBShotRules.advance(
		_shots(caster, enemies), enemies, [caster], _cfg, 10, null, PBCombatOutcome.new()
	)
	var before: Vector2 = enemies[0].pos()
	assert_true(PBEnemyDuelRules.move(enemies[0], [enemies[0]], [], 1.0, 11))
	assert_eq(enemies[0].pos(), before)
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	wave.enemy_level = 7
	enemies[0].spawn(wave, 0.0, 0.7, 12)
	assert_false(enemies[0].controlled(12))
	assert_eq(enemies[0].level, 7)


func test_level_source_and_configuration_tooltip_are_explicit() -> void:
	var rng := RandomNumberGenerator.new()
	assert_eq(PBWaveRules.build(10, _cfg, rng).enemy_level, 4)
	assert_eq(PBWaveRules.build(1, _cfg, rng).enemy_level, 1)
	var skill := _caster().skills[0].skill
	assert_eq(PBSkillLoader.check(skill), "")
	var words := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_true(words.contains("等级更低"))
	assert_true(words.contains("追加目标只眩晕"))
	assert_true(words.contains("2.0"))
	skill.damage_base = 1.0
	assert_ne(PBSkillLoader.check(skill), "")
	skill.damage_base = 0.0
	skill.shot_cross_seconds = 0.0
	assert_ne(PBSkillLoader.check(skill), "")
