extends GutTest

var _cfg: PBSimConfig
var _unit: PBAttacker
var _cast: PBSkillCast
var _sim: PBBattleSim


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.spawn_window = 0.0
	_cfg.ultimate_min_targets = 1
	_cfg.unit_min_gap = 0.0
	_unit = PBAttacker.new()
	_unit.max_hp = 10000
	_unit.max_mp = 100
	var skill := PBSkill.new()
	skill.id = &"timeline_probe"
	skill.target = PBSkill.Target.NONE
	skill.affects = PBSkill.Party.ALLIES
	skill.mp_cost = 10
	skill.cooldown_ticks = 100
	var buff := PBBuff.new()
	buff.id = &"timeline_buff"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 5
	buff.mods = {PBBuffRules.DEFENCE: 30.0}
	skill.on_self = [buff]
	_cast = PBSkillCast.new(skill)
	_unit.skills = [_cast]
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 1000000
	_sim = PBBattleSim.new(wave, 0, 0, _cfg, [_unit])
	_sim.enemies()[0].speed = 0
	_sim.enemies()[0].damage_per_shot = 0
	_sim.log_to = PBBattleLog.new()


func _until(tick: int) -> void:
	while _sim.current_tick() < tick:
		_sim.step()


func test_six_frames_release_at_six_and_finish_at_twelve() -> void:
	assert_true(_sim.cast_skill_now(_unit, 1))
	assert_eq(_unit.mp, 100.0, "暂停指令不扣蓝")
	assert_false(_unit.casting.active(0))
	_until(1)
	assert_eq(_unit.mp, 90.0)
	assert_eq(_unit.casting.ends_at, 12)
	for tick: int in range(1, 12):
		_until(tick)
		assert_eq(_unit.casting.frame_at(tick), int(tick / 2.0))
		assert_eq(_unit.buffs.count(tick), 0 if tick < 6 else 1)
		assert_false(PBSkillRules.can_cast(_unit, 1, tick))
		assert_false(_unit.ready_to_fire(tick))
	assert_eq(_cast.ready_at, 106, "瞬发技能第 4 帧结算并起冷却")
	_until(12)
	assert_false(_unit.casting.active(12))
	assert_true(_unit.ready_to_fire(12))
	var events: Array = _sim.log_to.entries.filter(
		func(e: Dictionary) -> bool: return e.kind == PBBattleLog.Kind.ULTIMATE
	)
	assert_eq(events.size(), 1, "只释放一次")
	assert_eq(events[0].tick, 6)


func test_ground_delay_starts_at_release_and_survives_recovery() -> void:
	_cast.skill.target = PBSkill.Target.GROUND
	_cast.skill.delay_ticks = 20
	assert_true(_sim.cast_skill(_unit, Vector2(0.8, 0), 1))
	_until(1)
	assert_eq(_cast.lands_at, 26)
	_until(12)
	assert_false(_unit.casting.active(12))
	assert_true(_cast.is_pending(), "飞行延迟不延长人物动作")
	_until(25)
	assert_eq(_cast.impact_tick, -1)
	_until(26)
	assert_eq(_cast.impact_tick, 26)


func test_channel_action_holds_frame_four_then_plays_five_and_six() -> void:
	var skill := PBSkill.new()
	skill.id = &"channel_pose"
	skill.target = PBSkill.Target.NONE
	skill.affects = PBSkill.Party.ALLIES
	skill.channel_control = true
	var cast := PBSkillCast.new(skill)
	cast.cast_now(0)
	var timeline := PBCastTimeline.new()
	timeline.begin(_unit, cast, _cfg, 0)
	for tick: int in 6:
		assert_eq(timeline.frame_at(tick), int(tick / 2.0))
	timeline.advance(_unit, _cfg, 6, null)
	cast.land(6)
	assert_eq(timeline.frame_at(6), 3, "第 4 帧释放")
	assert_true(timeline.active(20))
	assert_eq(timeline.frame_at(20), 3, "引导期间一直保持第 4 帧")
	_unit.channel.active = false
	timeline.advance(_unit, _cfg, 20, null)
	assert_eq(timeline.frame_at(20), 4, "引导结束开始第 5 帧")
	assert_eq(timeline.frame_at(22), 5, "随后播放第 6 帧")
	timeline.advance(_unit, _cfg, 24, null)
	assert_false(timeline.active(24))


func test_attack_speed_does_not_change_timeline_and_blocks_second_skill() -> void:
	for speed: float in [0.5, 4.0]:
		_unit.attack_speed = speed
		_cast.cast_now(0)
		PBSkillOrders.begin(_unit, _cast, _cfg, 0, null)
		var second := PBSkill.new()
		_unit.skills.append(PBSkillCast.new(second))
		assert_eq(_unit.casting.releases_at, 6)
		assert_eq(_unit.casting.ends_at, 12)
		assert_false(PBSkillRules.can_cast(_unit, 2, 3))
		_unit.casting.cancel(_unit)


func test_stun_and_silence_cancel_before_release_and_refund_once() -> void:
	for key: StringName in [PBBuffRules.STUN, PBBuffRules.SILENCE]:
		_cast.cast_now(0)
		PBSkillOrders.begin(_unit, _cast, _cfg, 0, null)
		var buff := PBBuff.new()
		buff.id = &"interruption"
		buff.kind = PBBuff.Kind.DURATION
		_unit.buffs.add(buff, {key: 1.0}, 2, 10, 0)
		_unit.casting.advance(_unit, _cfg, 2, null)
		assert_false(_cast.is_pending())
		assert_eq(_unit.mp, 100.0)
		assert_eq(_cast.ready_at, 0)
		assert_false(_cast.first_cast_spent)
		assert_false(PBSkillRules.can_cast(_unit, 1, 2))
		_unit.casting.cancel(_unit)
		assert_eq(_unit.mp, 100.0)
		_unit.buffs.clear()


func test_death_before_release_cancels_even_with_instant_revive() -> void:
	assert_true(_sim.cast_skill_now(_unit, 1))
	_until(2)
	_unit.revives = 1
	_unit.take_damage(20000, 2)
	assert_true(_unit.alive)
	assert_false(_cast.is_pending())
	assert_eq(_unit.mp, 100.0)
	_until(8)
	assert_eq(_unit.buffs.count(8), 0)


func test_death_after_release_keeps_ground_payload() -> void:
	_cast.skill.target = PBSkill.Target.GROUND
	_cast.skill.delay_ticks = 10
	assert_true(_sim.cast_skill(_unit, Vector2(0.8, 0), 1))
	_until(6)
	_unit.take_damage(20000, 6)
	assert_false(_unit.casting.active(6))
	assert_true(_cast.is_pending())
	assert_eq(_unit.mp, 90.0)
	_until(16)
	assert_eq(_cast.impact_tick, 16)


func test_locked_projectile_only_exists_from_frame_four() -> void:
	_cast.skill.target = PBSkill.Target.ENEMY
	_cast.skill.affects = PBSkill.Party.ENEMIES
	_cast.skill.shot_cross_seconds = 1
	assert_true(_sim.cast_skill_at(_unit, _sim.enemies()[0], 1))
	_until(5)
	assert_eq(_sim.shots().filter(func(s: PBProjectile) -> bool: return s.alive).size(), 0)
	_until(6)
	assert_eq(_sim.shots().filter(func(s: PBProjectile) -> bool: return s.alive).size(), 1)
	assert_true(_unit.casting.active(6))
	assert_false(_cast.is_pending())


func test_autocast_uses_same_twelve_ticks() -> void:
	_unit.ultimate = _cast
	_unit.skills.clear()
	_cast.skill.target = PBSkill.Target.GROUND
	_cast.skill.radius = 10
	_sim._aim_policy = PBAimRules.Policy.AUTO
	_until(1)
	assert_eq(_unit.casting.started_at, 1)
	assert_eq(_unit.casting.releases_at, 7)
	assert_eq(_unit.casting.ends_at, 13)
	_until(6)
	assert_eq(_unit.buffs.count(6), 0)
	_until(7)
	assert_eq(_unit.buffs.count(7), 1)


func test_reset_and_clone_do_not_keep_action_state() -> void:
	assert_true(_sim.cast_skill_now(_unit, 1))
	_until(2)
	var copy := _unit.clone()
	assert_false(copy.casting.active(2))
	_unit.revive()
	_cast.reset()
	assert_false(_unit.casting.active(2))
	assert_eq(_cast.release_at, -1)
	assert_false(_cast.is_pending())
