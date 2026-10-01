extends GutTest
## 范围伤害、主目标控制、范围眩晕和范围沉默不能互相替代。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _enemy(at: Vector2 = Vector2(0.5, 0.0)) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at.x, 0, at.y)
	return enemy


func _cast(id: StringName, level: int = 1) -> PBSkillCast:
	var cast := PBSkillCast.new(_cfg.skills.by_id(id), level)
	cast.target_slot = 0
	cast.spot = Vector2(0.5, 0.0)
	return cast


func test_giant_damage_hits_circle_but_only_primary_is_stunned() -> void:
	var cast := _cast(&"giant_rasengan")
	var primary := _enemy()
	var near := _enemy(Vector2(0.5, 0.18))
	var far := _enemy(Vector2(0.5, 0.19))
	PBSkillRules.land_on_enemy(cast, [primary, near, far], _cfg, 1, null, 500.0)
	assert_eq(primary.hp, 99500.0)
	assert_eq(near.hp, 99500.0)
	assert_eq(far.hp, far.max_hp)
	assert_false(primary.ready_to_fire(41))
	assert_true(primary.ready_to_fire(42))
	assert_eq(primary.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 41), 0.0)
	assert_true(near.ready_to_fire(1))
	assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
	assert_eq(cast.skill.element, PBElement.Type.SAGE)
	assert_eq(cast.skill.kind, PBDamageKind.Type.NINJUTSU)
	assert_eq(cast.skill.slow_ticks, 0)
	assert_eq(cast.skill.radius, 375.0 / 2000.0)


func test_giant_follows_living_primary_and_does_not_retarget_a_corpse() -> void:
	var cast := _cast(&"giant_rasengan")
	var primary := _enemy(Vector2(0.8, 0.0))
	var previous := _enemy()
	PBSkillRules.land_on_enemy(cast, [primary, previous], _cfg, 1, null, 500.0)
	assert_eq(previous.hp, previous.max_hp)
	primary.alive = false
	previous.distance = primary.distance
	PBSkillRules.land_on_enemy(cast, [primary, previous], _cfg, 2, null, 500.0)
	assert_eq(previous.hp, previous.max_hp)
	assert_true(previous.ready_to_fire(2))


func test_sharks_control_uses_unlevelled_original_carrier_and_its_own_radius() -> void:
	for level: int in range(1, 11):
		var cast := _cast(&"infinite_sharks", level)
		var near := _enemy(Vector2(0.5, 0.17))
		var far := _enemy(Vector2(0.5, 0.18))
		var source := PBAttacker.new()
		source.prime(_cfg.tick_rate, _cfg)
		var zone := PBHazardZone.new()
		zone.begin(source, cast, 1)
		zone.advance([near, far], 0, _cfg, 1, null, null)
		var end: int = 21
		assert_false(near.ready_to_fire(end))
		assert_true(near.ready_to_fire(end + 1))
		assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, end), 0.0)
		assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, end + 1), 1.0)
		assert_eq(far.hp, far.max_hp)
		assert_true(far.ready_to_fire(1))
		assert_eq(cast.skill.slow_ticks, 0)


func test_white_rage_silences_without_stopping_normal_attack_or_movement() -> void:
	var seconds := [1, 1, 2, 2, 2, 3, 3, 3, 3, 4]
	for level: int in range(1, 11):
		var cast := _cast(&"white_rage", level)
		var near := _enemy(Vector2(0.5, 0.17))
		var far := _enemy(Vector2(0.5, 0.18))
		PBSkillRules.land(cast, [near, far], 0, _cfg, 1, null, 500.0)
		var end: int = 1 + seconds[level - 1] * _cfg.tick_rate
		assert_eq(near.buffs.amount(PBBuffRules.SILENCE, end), 1.0)
		assert_eq(near.buffs.amount(PBBuffRules.SILENCE, end + 1), 0.0)
		assert_true(near.ready_to_fire(1))
		assert_eq(near.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 1), 1.0)
		assert_eq(far.hp, far.max_hp)
		assert_eq(far.buffs.amount(PBBuffRules.SILENCE, 1), 0.0)


func test_local_control_tooltips_match_targeting_and_level_windows() -> void:
	var giant := PBEffectWords.skill_body(_cast(&"giant_rasengan").skill, _cfg)
	assert_string_contains(giant, "点敌人")
	assert_string_contains(giant, "主目标附带")
	assert_false(giant.contains("全场减速"))
	var sharks := PBEffectWords.skill_body(_cast(&"infinite_sharks").skill, _cfg, 10)
	assert_string_contains(sharks, "1.0 秒")
	assert_string_contains(sharks, "共 10 段")
	assert_false(sharks.contains("全场减速"))
	var white := PBEffectWords.skill_body(_cast(&"white_rage").skill, _cfg, 10)
	assert_string_contains(white, "沉默")
	assert_string_contains(white, "4 秒")
