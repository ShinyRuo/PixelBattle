extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _cast() -> PBSkillCast:
	var cast := PBSkillCast.new(_cfg.skills.by_id(&"earth_dragon"), 1)
	cast.cast(Vector2(0.7, 0.25), 0)
	cast.origin = Vector2(0.2, 0.25)
	return cast


func _enemy(at: Vector2) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at.x, 0, at.y)
	return enemy


func test_line_hits_near_origin_and_midpoint_but_excludes_sides_rear_and_beyond_end() -> void:
	var cast := _cast()
	var inside := _enemy(Vector2(0.21, 0.25))
	var middle := _enemy(Vector2(0.45, 0.29))
	var side := _enemy(Vector2(0.45, 0.31))
	var rear := _enemy(Vector2(0.19, 0.25))
	var beyond := _enemy(Vector2(0.71, 0.25))
	PBSkillRules.land(cast, [inside, middle, side, rear, beyond], 0, _cfg, 8, null, 100.0)
	for enemy: PBEnemy in [inside, middle]:
		assert_eq(enemy.hp, 99900.0)
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 68), 0.7)
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 69), 1.0)
		assert_true(enemy.ready_to_fire(8))
	for enemy: PBEnemy in [side, rear, beyond]:
		assert_eq(enemy.hp, enemy.max_hp)
		assert_eq(enemy.buffs.count(8), 0)
	assert_eq(cast.skill.slow_ticks, 0)


func test_direction_rotates_in_two_dimensions_and_zero_aim_uses_forward() -> void:
	var cast := _cast()
	cast.spot = cast.origin + Vector2(0.0, 0.5)
	assert_true(PBSkillArea.contains(cast.skill, cast.origin, cast.spot, Vector2(0.24, 0.6)))
	assert_false(PBSkillArea.contains(cast.skill, cast.origin, cast.spot, Vector2(0.26, 0.6)))
	assert_false(PBSkillArea.contains(cast.skill, cast.origin, cast.spot, Vector2(0.2, 0.24)))
	assert_eq(PBSkillArea.heading(cast.origin, cast.origin), Vector2.RIGHT)


func test_issued_origin_is_snapshot_and_reset_clears_it() -> void:
	var cast := _cast()
	var one := PBAttacker.new()
	one.pos = Vector2(0.3, 0.25)
	one.mp = 100.0
	PBSkillOrders.issue(one, cast, _cfg, 0, null)
	one.pos = Vector2(0.8, 0.3)
	assert_eq(cast.origin, Vector2(0.3, 0.25))
	var enemy := _enemy(Vector2(0.4, 0.25))
	PBSkillRules.land(cast, [enemy], 0, _cfg, 8, one, 100.0)
	assert_eq(enemy.hp, 99900.0)
	cast.reset()
	assert_eq(cast.origin, PBSkillCast.NO_SPOT)


func test_line_impact_keeps_issued_origin_for_art_after_pending_state_clears() -> void:
	var cast := _cast()
	cast.land(8)
	assert_eq(cast.impact_tick, 8)
	assert_eq(cast.impact_origin, Vector2(0.2, 0.25))
	assert_eq(cast.impact_spot, Vector2(0.7, 0.25))
	assert_eq(cast.origin, PBSkillCast.NO_SPOT)
	assert_true(PBFieldArt.supports_line_area(cast.impact_skill))
	cast.reset()
	assert_eq(cast.impact_origin, PBSkillCast.NO_SPOT)


func test_telegraph_uses_same_polygon_as_hit_shape() -> void:
	var cast := _cast()
	var one := PBAttacker.new()
	one.skills = [cast]
	var pool := PBTelegraphPool.new()
	add_child_autofree(pool)
	var field := Vector2(1.0, 0.5)
	pool.sync_pending([one], 1, field)
	assert_eq(pool.shown(), 1)
	var expected := PackedVector2Array()
	for point: Vector2 in PBSkillArea.outline(cast.skill, cast.origin, cast.spot):
		expected.append(PBLayout.to_screen(point, field))
	assert_eq(pool._outlines[0], expected)
	assert_eq(expected.size(), 5)


func test_line_validation_and_description() -> void:
	var skill := _cast().skill.clone()
	assert_eq(PBSkillArea.validate(skill), "")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg), "前方直线")
	assert_false(PBEffectWords.skill_body(skill, _cfg).contains("全场减速"))
	skill.target = PBSkill.Target.ENEMY
	assert_ne(PBSkillArea.validate(skill), "")
	skill.target = PBSkill.Target.GROUND
	skill.line_length = NAN
	assert_ne(PBSkillArea.validate(skill), "")
