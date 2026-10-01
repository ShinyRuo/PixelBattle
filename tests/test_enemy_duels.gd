extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _enemy(slot: int, converted: bool = false) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	wave.atk_each = 100.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.05, 0.5 + slot * 0.1, 0)
	enemy.slot = slot
	enemy.reach = 1.0
	enemy.damage_per_shot = 100.0
	enemy.intellect = 100.0
	enemy.attack_interval = 20
	if converted:
		var buff := PBBuff.new()
		buff.id = &"duel_conversion"
		buff.kind = PBBuff.Kind.DURATION
		buff.friendly = false
		enemy.buffs.add(buff, {PBBuffRules.DOMINATED: 1.0}, 0, 100, 0)
		enemy.control_ref = weakref(enemy.buffs.states()[0])
	return enemy


func test_melee_and_projectile_preserve_two_damage_kinds_and_all_seven_elements() -> void:
	for kind: PBDamageKind.Type in PBDamageKind.Type.values():
		for element: PBElement.Type in PBElement.Type.values():
			for ranged: bool in [false, true]:
				var source := _enemy(0, true)
				var target := _enemy(1)
				source.element = element
				source.damage_kind = kind
				source.shot_speed = 1.0 if ranged else 0.0
				source.armor_pen = 0.2
				source.ninjutsu_pen = 0.4
				target.element = PBElement.Type.WATER
				target.armor = 20.0
				target.ninjutsu_resist = 0.3
				var expected: float = (
					100.0 * _cfg.damage_multiplier(PBElement.relation(element, target.element))
				)
				expected = PBDefenceRules.mitigated(expected, kind, 20.0, 0.3, 0.2, 0.4, _cfg)
				var shot := PBProjectile.new()
				var out := PBCombatOutcome.new()
				assert_true(
					PBEnemyDuelRules.attack(
						source, [source, target], [], [shot], _cfg, 1, null, null, out
					)
				)
				if ranged:
					assert_eq(target.hp, 1000.0)
					PBShotRules.advance([shot], [source, target], [], _cfg, 2, null, out)
				assert_almost_eq(target.hp, 1000.0 - expected, 0.001)


func test_enemy_can_damage_converted_unit_and_kill_counts_as_enemy_not_lost_ninja() -> void:
	var source := _enemy(0)
	var target := _enemy(1, true)
	target.hp = 10.0
	var out := PBCombatOutcome.new()
	assert_true(PBEnemyDuelRules.attack(source, [source, target], [], [], _cfg, 1, null, null, out))
	assert_false(target.alive)
	assert_eq(out.kills, 1)
	assert_eq(out.allies_lost, 0)


func test_reverting_target_cancels_inflight_friendly_fire_and_pool_reuse_clears_context() -> void:
	var source := _enemy(0)
	var target := _enemy(1, true)
	source.shot_speed = 0.01
	var shot := PBProjectile.new()
	var out := PBCombatOutcome.new()
	PBEnemyDuelRules.attack(source, [source, target], [], [shot], _cfg, 1, null, null, out)
	assert_true(shot.enemy_duel)
	target.buffs.clear()
	PBShotRules.advance([shot], [source, target], [], _cfg, 2, null, out)
	assert_false(shot.alive)
	assert_eq(target.hp, 1000.0)
	assert_null(shot.duel_context)
	shot.launch(Vector2.ZERO, 1, 50.0, 1.0)
	assert_false(shot.enemy_duel)
	assert_false(shot.duel_source_friendly)
	assert_true(shot.primary_target)


func test_stun_disarm_and_full_projectile_pool_do_not_create_instant_damage() -> void:
	for reason: int in 3:
		var source := _enemy(0, true)
		var target := _enemy(1)
		if reason < 2:
			var buff := PBBuff.new()
			buff.id = &"duel_lock"
			var key := PBBuffRules.STUN if reason == 0 else PBBuffRules.DISARM
			source.buffs.add(buff, {key: 1.0}, 0, 20, 0)
		else:
			source.shot_speed = 1.0
		PBEnemyDuelRules.attack(
			source, [source, target], [], [], _cfg, 1, null, null, PBCombatOutcome.new()
		)
		assert_eq(target.hp, 1000.0)


func test_controlled_unit_moves_toward_enemies_and_hostile_prefers_nearest_opponent() -> void:
	var controlled := _enemy(0, true)
	controlled.reach = 0.01
	var hostile := _enemy(1)
	hostile.distance = 0.9
	hostile.reach = 0.01
	assert_true(PBEnemyDuelRules.move(controlled, [controlled, hostile], [], 1.0, 1))
	assert_gt(controlled.distance, 0.5)
	var ally := PBAttacker.new()
	ally.max_hp = 1000.0
	ally.hp = 1000.0
	ally.pos = Vector2(0.89, 0.0)
	assert_false(PBEnemyDuelRules.move(hostile, [controlled, hostile], [ally], 1.0, 1))
	ally.pos = Vector2.ZERO
	assert_true(PBEnemyDuelRules.move(hostile, [controlled, hostile], [ally], 1.0, 1))
	assert_lt(hostile.distance, 0.9)


func test_old_enemy_projectile_cannot_hurt_ninja_while_shooter_is_converted() -> void:
	var enemy := _enemy(0, true)
	var ally := PBAttacker.new()
	ally.max_hp = 1000.0
	ally.hp = 1000.0
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 1.0, true, enemy.element, 0)
	PBShotRules.advance([shot], [enemy], [ally], _cfg, 1, null, PBCombatOutcome.new())
	assert_eq(ally.hp, 1000.0)
	assert_false(shot.alive)
