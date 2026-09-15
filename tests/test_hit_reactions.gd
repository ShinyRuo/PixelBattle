extends GutTest
## 出手与挨打的几个小读点（M12-c4 批十三）：每下普攻都挂的效果、闪避反打、近战专属的减伤与反弹、
## 只认远程的受击与跳跃、穿透的普攻子弹。
##
## 这里错了都不报错：每下都挂的效果只在暴击时挂；同一 tick 挨两下、只闪掉一下却反打两次；
## 远程打他也反弹近战那一份；受击跳跃跳到了近战怪身上；穿透子弹打中第一个就回池、或者同一个敌人挨好几下。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _ninja() -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 100000.0
	one.attack = 100.0
	one.attack_speed = 1.0
	one.reach = 0.0625
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


func _enemy(at: float, lane: float = 0.0, shot_speed: float = 0.0) -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100000.0
	out.hp = out.max_hp
	out.distance = at
	out.lane = lane
	out.shot_speed = shot_speed
	return out


func _debuff(id: StringName, mods: Dictionary) -> PBBuff:
	var out := PBBuff.new()
	out.id = id
	out.kind = PBBuff.Kind.DURATION
	out.duration_seconds = 2.0
	out.mods = mods
	return out


func _hit(one: PBAttacker, source: PBEnemy, tick: int, rng: RandomNumberGenerator = null) -> void:
	PBStrikeRules.hurt_ally(
		one, source, 100.0, PBElement.Type.PHYSICAL, _cfg, tick, rng, null, PBCombatOutcome.new()
	)


func test_an_attack_buff_lands_on_every_hit_not_only_on_crits() -> void:
	# 加重岩之术「攻击时降低敌人 50% 的攻速和移速」：没暴击也挂。
	var one := _ninja()
	one.attack_buffs = [_debuff(&"probe_weight", {&"enemy_attack_speed_scale": 0.5})]
	var enemy := _enemy(0.3)
	var enemies: Array[PBEnemy] = [enemy]
	PBStrikeRules.land(one, enemy, 10.0, false, enemies, _cfg, 1, null, PBCombatOutcome.new())
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 1), 0.5, "没暴击也挂上了")


func test_a_dodge_hits_back_once_and_a_landed_hit_does_not() -> void:
	# 蛙组手「每次闪避成功时对目标造成伤害」。同一 tick 再挨一下没闪掉，不许再反打。
	var one := _ninja()
	one.dodge_counter = 0.5
	one.dodge = 1.0
	var enemy := _enemy(0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_hit(one, enemy, 5, rng)
	assert_almost_eq(enemy.max_hp - enemy.hp, 50.0, 0.001, "闪掉了，反打一发普攻的五成")
	one.dodge = 0.0
	_hit(one, enemy, 5, rng)
	assert_almost_eq(enemy.max_hp - enemy.hp, 50.0, 0.001, "同一 tick 没闪掉的那一下不反打")
	assert_lt(one.hp, one.max_hp, "前提：第二下真挨上了")


func test_melee_words_only_apply_to_melee_attackers() -> void:
	# 针地藏「反弹近战攻击伤害、降低近战普攻伤害」：远程打他两样都不生效。
	for ranged: bool in [false, true]:
		var plain := _ninja()
		var guarded := _ninja()
		guarded.melee_taken = -0.15
		guarded.melee_reflect = 0.2
		var enemy := _enemy(0.3, 0.0, 0.01 if ranged else 0.0)
		_hit(plain, enemy, 1)
		var before: float = enemy.hp
		_hit(guarded, enemy, 1)
		var lost_plain: float = plain.max_hp - plain.hp
		var lost: float = guarded.max_hp - guarded.hp
		if ranged:
			assert_almost_eq(lost, lost_plain, 0.001, "远程那一下不减")
			assert_eq(enemy.hp, before, "远程那一下不反弹")
		else:
			assert_almost_eq(lost, lost_plain * 0.85, 0.001, "近战那一下少掉 15%")
			assert_almost_eq(before - enemy.hp, lost * 0.2, 0.001, "近战那一下反弹两成")


func test_a_ranged_only_struck_effect_ignores_melee_and_leaps_at_the_shooter() -> void:
	# 雷梨热刀「在受远程攻击时突袭跳跃到目标身前」。
	var one := _ninja()
	one.pos = Vector2(0.1, 0.0)
	var guard := _debuff(&"probe_guard", {&"defence": 50.0})
	guard.friendly = true
	one.struck_buffs = [guard]
	one.struck_ranged = 1.0
	one.struck_leap = 1.0
	_hit(one, _enemy(0.5), 1)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 0.0, "近战那一下不触发")
	assert_eq(one.pos, Vector2(0.1, 0.0), "也不跳")
	var shooter := _enemy(0.5, 0.0, 0.01)
	_hit(one, shooter, 2)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 2), 50.0, "远程那一下触发了")
	assert_almost_eq(
		one.pos.distance_to(shooter.pos()), one.reach * PBAttacker.STOP_RING, 0.0001, "落在射手身前、够得着它"
	)


func test_a_piercing_shot_keeps_flying_and_decays_per_target() -> void:
	# 纸手里剑「攻击力能够穿透目标……每穿透一个目标会衰减 15% 的伤害，穿透距离 500」。
	var shooter := _ninja()
	shooter.slot = 0
	var attackers: Array[PBAttacker] = [shooter]
	var enemies: Array[PBEnemy] = [
		_enemy(0.30),
		_enemy(0.35),
		_enemy(0.40),
		_enemy(0.80),
		_enemy(0.37, 0.2),
	]
	for i: int in enemies.size():
		enemies[i].slot = i
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 0.02, false, PBElement.Type.PHYSICAL, 0)
	shot.pierce_left = _cfg.units_to_field(500.0)
	var shots: Array[PBProjectile] = [shot]
	var out := PBCombatOutcome.new()
	var alive_after_first: bool = false
	for tick: int in 200:
		PBShotRules.advance(shots, enemies, attackers, _cfg, tick, null, out)
		if enemies[0].hp < enemies[0].max_hp and not alive_after_first:
			alive_after_first = shot.alive
		if not shot.alive:
			break
	assert_true(alive_after_first, "打中第一个之后子弹还在飞")
	assert_false(shot.alive, "走完穿透距离就回池")
	var lost: Array[float] = []
	for enemy: PBEnemy in enemies:
		lost.append(enemy.max_hp - enemy.hp)
	assert_almost_eq(lost[0], 100.0, 0.001, "第一个挨满额")
	assert_almost_eq(lost[1], 85.0, 0.001, "穿过去的第一个 85%")
	assert_almost_eq(lost[2], 72.25, 0.001, "再往后的一个再衰减 15%")
	assert_eq(lost[3], 0.0, "穿透距离之外的不挨")
	assert_eq(lost[4], 0.0, "不在直线上的不挨")


func test_a_recycled_shot_does_not_pierce_by_accident() -> void:
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 0.02)
	shot.pierce_left = 0.25
	shot.start_pierce(0)
	shot.retire()
	shot.launch(Vector2.ZERO, 1, 100.0, 0.02)
	assert_eq(shot.pierce_left, 0.0, "上一发的穿透距离清掉了")
	assert_false(shot.piercing, "也不在穿透段")
	assert_eq(shot.struck.size(), 0, "打过谁也清掉了")
