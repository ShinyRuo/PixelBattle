extends GutTest

const TIMES: Array[float] = [2.5, 2.5, 4.0, 4.0, 4.0, 5.5, 5.5, 6.0, 6.0, 7.5]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _skill() -> PBSkill:
	var skill := _cfg.skills.by_id(&"shadow_bind").clone()
	for bond: PBBond in _cfg.bonds.all():
		if bond.id == &"strategist_couple":
			PBSkillPatchRules.apply(skill, bond.member_skill_patches[&"shikamaru"][skill.id])
	return skill


func _caster() -> PBAttacker:
	var caster := PBAttacker.new()
	caster.slot = 0
	caster.max_hp = 10000.0
	caster.hp = caster.max_hp
	caster.max_mp = 1000.0
	caster.mp = caster.max_mp
	caster.pos = Vector2(0.2, 0.0)
	return caster


func _enemies() -> Array[PBEnemy]:
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	var result: Array[PBEnemy] = []
	for i: int in 2:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, 0.5, 0, i * 0.1)
		enemy.slot = i
		result.append(enemy)
	return result


func _launch(caster: PBAttacker, enemies: Array[PBEnemy], level: int = 10) -> PBProjectile:
	var skill := _skill()
	var cast := PBSkillCast.new(skill)
	cast.caster_level = level
	cast.cast_on(0, 0)
	PBSkillOrders.issue(caster, cast, _cfg, 0, null)
	var shot := PBProjectile.new()
	shot.launch(caster.pos, 0, 0.0, 1.0, false, skill.element, caster.slot, skill, level)
	shot.channel = caster.channel
	shot.channel.target_ref = weakref(enemies[0])
	return shot


func _hit(caster: PBAttacker, enemies: Array[PBEnemy], shot: PBProjectile, tick: int = 10) -> void:
	PBShotRules.advance([shot], enemies, [caster], _cfg, tick, null, PBCombatOutcome.new())


func test_ten_levels_start_duration_at_impact_and_release_both_sides() -> void:
	for level: int in range(1, 11):
		var caster := _caster()
		var enemies := _enemies()
		var shot := _launch(caster, enemies, level)
		assert_false(caster.ready_to_fire(1))
		assert_eq(enemies[0].buffs.count(1), 0)
		_hit(caster, enemies, shot)
		var end: int = 10 + roundi(TIMES[level - 1] * 20.0)
		assert_false(enemies[0].ready_to_fire(end))
		assert_false(caster.ready_to_fire(end))
		assert_true(enemies[0].ready_to_fire(end + 1))
		assert_true(caster.ready_to_fire(end + 1))
		# 时间查询不能倒退：独立验证周围效果的上限。
		caster = _caster()
		enemies = _enemies()
		_hit(caster, enemies, _launch(caster, enemies, level))
		assert_false(enemies[1].ready_to_fire(60))
		assert_true(enemies[1].ready_to_fire(61))


func test_death_stun_silence_and_target_loss_interrupt_without_sweeping() -> void:
	for reason: int in 4:
		var caster := _caster()
		var enemies := _enemies()
		_hit(caster, enemies, _launch(caster, enemies))
		match reason:
			0:
				caster.take_damage(caster.hp + 1.0, 11)
			1, 2:
				var buff := PBBuff.new()
				buff.id = &"interrupt_probe"
				var key := PBBuffRules.STUN if reason == 1 else PBBuffRules.SILENCE
				caster.buffs.add(buff, {key: 1.0}, 11, 1, 0)
			3:
				enemies[0].alive = false
		assert_eq(enemies[1].buffs.amount(PBBuffRules.STUN, 11), 0.0)
		assert_eq(enemies[0].buffs.amount(PBBuffRules.STUN, 11), 0.0)
		assert_false(caster.channel.is_live(20), "中断条件消失也不能恢复旧引导")


func test_interrupt_before_impact_prevents_control_and_does_not_refund() -> void:
	var caster := _caster()
	var enemies := _enemies()
	var shot := _launch(caster, enemies)
	var mana: float = caster.mp
	caster.take_damage(caster.hp + 1.0, 1)
	_hit(caster, enemies, shot)
	assert_false(shot.alive)
	assert_eq(caster.mp, mana)
	assert_eq(enemies[0].buffs.count(10), 0)
	assert_eq(enemies[1].buffs.count(10), 0)


func test_new_source_refresh_does_not_inherit_old_channel_cancellation() -> void:
	var first := _caster()
	var second := _caster()
	second.slot = 1
	var enemies := _enemies()
	_hit(first, enemies, _launch(first, enemies))
	_hit(second, enemies, _launch(second, enemies), 11)
	assert_false(first.channel.is_live(11), "主控制已被后一次覆盖，旧施法者结束引导")
	first.alive = false
	assert_false(enemies[0].ready_to_fire(12))
	assert_false(enemies[1].ready_to_fire(12))
	second.alive = false
	assert_true(enemies[0].ready_to_fire(13))
	assert_true(enemies[1].ready_to_fire(13))


func test_real_sim_blocks_movement_normal_attacks_and_other_manual_or_auto_skills() -> void:
	var caster := _caster()
	caster.move_speed = 0.01
	var skill := _skill()
	caster.skills = [PBSkillCast.new(skill)]
	caster.ultimate = PBSkillCast.new(PBSkill.new())
	caster.ultimate.skill.radius = 1.0
	caster.ultimate.skill.mp_cost = 1.0
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [caster])
	for enemy: PBEnemy in sim.enemies():
		enemy.distance = 0.5
		enemy.speed = 0.0
		enemy.damage_per_shot = 0.0
	assert_true(sim.cast_skill_at(caster, sim.enemies()[0], 1))
	var origin: Vector2 = caster.pos
	for i: int in 20:
		sim.step()
	assert_eq(caster.pos, origin)
	assert_false(caster.ready_to_fire(sim.current_tick()))
	assert_false(sim.can_cast(caster, 0))
	assert_false(sim.cast_skill(caster, Vector2(0.5, 0.0), 0))
	assert_eq(caster.mp, 1000.0 - skill.mp_cost)
	assert_eq(sim.enemies()[0].hp, sim.enemies()[0].max_hp)
	var old: PBSkillChannel = caster.channel
	caster.revive()
	assert_false(old.is_live(sim.current_tick()))
	assert_null(caster.channel)
	assert_eq(sim.enemies()[0].buffs.count(sim.current_tick()), 0)


func test_failed_launch_releases_caster_and_validation_rejects_unsupported_shape() -> void:
	var caster := _caster()
	caster.skills = [PBSkillCast.new(_skill())]
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [caster])
	assert_true(sim.cast_skill_at(caster, sim.enemies()[0], 1))
	sim.enemies()[0].alive = false
	sim.step()
	assert_false(PBSkillChannel.blocked(caster, sim.current_tick()))
	var skill := _skill()
	skill.max_targets = 2
	assert_ne(PBSkillRules.validate(skill), "")
	assert_true(PBEffectWords.skill_body(_skill(), _cfg).contains("需要持续施法"))


func test_full_projectile_pool_releases_channel_without_instant_fallback() -> void:
	var caster := _caster()
	caster.skills = [PBSkillCast.new(_skill())]
	var wave := PBWave.new()
	wave.count = 2
	wave.hp_each = 10000.0
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [caster])
	for shot: PBProjectile in sim.shots():
		shot.launch(Vector2.ZERO, 0, 0.0, 0.001)
	assert_true(sim.cast_skill_at(caster, sim.enemies()[0], 1))
	caster.swinging = true
	PBCastTestClock.release(sim, caster)
	assert_false(PBSkillChannel.blocked(caster, sim.current_tick()))
	assert_false(caster.swinging)
	assert_eq(sim.enemies()[0].buffs.count(sim.current_tick()), 0)
	assert_eq(caster.mp, 1000.0 - caster.skills[0].skill.mp_cost)
	assert_gt(caster.skills[0].ready_at, sim.current_tick())


func test_cleared_primary_control_ends_channel_but_unrelated_effect_survives() -> void:
	var caster := _caster()
	var enemies := _enemies()
	_hit(caster, enemies, _launch(caster, enemies))
	var other := PBBuff.new()
	other.id = &"unrelated_control"
	enemies[1].buffs.add(other, {PBBuffRules.ENEMY_SPEED_SCALE: 0.5}, 10, 200, 0)
	enemies[0].buffs.clear()
	assert_true(caster.ready_to_fire(11))
	assert_eq(enemies[1].buffs.amount(PBBuffRules.STUN, 11), 0.0)
	assert_eq(enemies[1].buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 11), 0.5)
