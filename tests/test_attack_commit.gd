extends GutTest

var _cfg: PBSimConfig
var _unit: PBAttacker
var _enemy: PBEnemy
var _sim: PBBattleSim


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.spawn_window = 0
	_cfg.unit_min_gap = 0
	_cfg.field_height = 1
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_unit = PBAttacker.new()
	_unit.slot = 0
	_unit.attack_speed = 1
	_unit.dps = 50
	_unit.max_hp = 100000
	_unit.home = Vector2(0.4, 0.4)
	_unit.pos = _unit.home
	_unit.reach = 0.06
	_unit.move_speed = 0.02
	_unit.leash = 2
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000
	_sim = PBBattleSim.new(wave, 0, 0, _cfg, [_unit])
	_enemy = _sim.enemies()[0]
	_enemy.distance = 0.45
	_enemy.lane = 0.41
	_enemy.reach = 0.3
	_enemy.speed = 0.03
	_enemy.damage_per_shot = 1
	_enemy.attack_interval = 20


func test_ranged_enemy_holds_position_when_melee_attacker_closes() -> void:
	_unit.home = Vector2(0.15, 0.4)
	_unit.pos = _unit.home
	var stopped := Vector2.INF
	for i: int in 100:
		_sim.step()
		if _enemy.engaged:
			if stopped == Vector2.INF:
				stopped = _enemy.pos()
			assert_eq(_enemy.pos(), stopped, "交战期间不追着围攻环绕位")
	assert_lt(_enemy.hp, 100000.0, "近战能追到并完成伤害")
	assert_lt(_unit.hp, 100000.0)


func test_target_leaving_range_does_not_cancel_windup_or_start_chasing() -> void:
	_sim.step()
	assert_true(_unit.swinging)
	var end := _unit.attack_ends_at
	assert_gt(end, _unit.next_shot_at)
	var origin := _unit.pos
	_enemy.distance = 0.8
	_enemy.speed = 0
	_enemy.damage_per_shot = 0
	while _sim.current_tick() < end - 1:
		_sim.step()
		assert_eq(_unit.pos, origin, "起手与收招完成前不追赶")
	assert_false(_unit.swinging, "离开射程也应完成起手，不永久卡住")
	assert_eq(_enemy.hp, 100000.0, "越界不伪造近战命中")
	_sim.step()
	assert_gt(_unit.pos.x, origin.x, "本次动作结束后继续追赶")


func test_attack_pose_stays_locked_out_of_range_then_returns_to_run() -> void:
	var pose := PBActorPose.new()
	pose.reset(Vector2.ZERO, PBActorPose.FACE_RIGHT)
	pose.update(Vector2.ZERO, true, 0, false, NAN, 60, true)
	pose.update(Vector2.ZERO, true, 5, false, NAN, 60, false, true, 15, true)
	assert_eq(pose.state, PBActorPose.State.ATTACK)
	for frame: int in 20:
		pose.update(Vector2.ZERO, true, 20, false, NAN, 60, false, false, 15, true)
		assert_eq(pose.state, PBActorPose.State.ATTACK)
	pose.update(Vector2(0.02, 0), true, 20, false, NAN, 60, false)
	assert_eq(pose.state, PBActorPose.State.RUN)


func test_revive_and_skill_cast_clear_old_attack_lock() -> void:
	_unit.begin_swing(1)
	assert_gt(_unit.attack_ends_at, 1)
	_unit.revive()
	assert_eq(_unit.attack_ends_at, -1)
	_unit.begin_swing(2)
	var skill := PBSkill.new()
	var cast := PBSkillCast.new(skill)
	_unit.casting.begin(_unit, cast, _cfg, 3)
	assert_eq(_unit.attack_ends_at, -1)
	assert_false(_unit.swinging)


func test_no_target_at_cooldown_does_not_create_an_attack_lock() -> void:
	_enemy.distance = 0.9
	_enemy.speed = 0
	_unit.move_speed = 0
	_sim.step()
	assert_false(_unit.swinging)
	assert_eq(_unit.attack_ends_at, -1)
