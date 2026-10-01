extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _cast(level: int = 1, area: bool = false) -> PBSkillCast:
	var skill := _cfg.skills.by_id(&"leaf_gale").clone()
	if area:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"kai_squad":
				PBSkillPatchRules.apply(
					skill, bond.member_skill_patches[&"might_guy"][&"leaf_gale"]
				)
	var cast := PBSkillCast.new(skill, level)
	cast.target_slot = 0
	return cast


func _enemy(x: float = 0.5, y: float = 0.0) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 10000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 1.0, 0, y)
	enemy.distance = x
	return enemy


func test_target_and_neighbors_stun_only_inside_circle_and_primary_is_not_pushed() -> void:
	var cast := _cast()
	var main := _enemy()
	var near := _enemy(0.6)
	var far := _enemy(0.5, 0.14)
	PBSkillRules.land_on_enemy(cast, [main, near, far], _cfg, 5, null, 100.0)
	for enemy: PBEnemy in [main, near]:
		assert_eq(enemy.hp, 9900.0)
		assert_false(enemy.ready_to_fire(25))
		assert_true(enemy.ready_to_fire(26))
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 25), 0.0)
	assert_eq(far.hp, 10000.0)
	assert_true(far.ready_to_fire(5))
	assert_eq(main.distance, 0.5)
	assert_almost_eq(near.distance, 0.66, 0.00001)
	assert_eq(cast.skill.slow_ticks, 0)


func test_only_primary_loses_armor_at_all_levels_for_ten_seconds() -> void:
	for level: int in range(1, 11):
		var cast := _cast(level)
		var main := _enemy()
		var near := _enemy(0.6)
		PBSkillRules.land_on_enemy(cast, [main, near], _cfg, 1, null, 100.0)
		assert_eq(main.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 201), -8.0 * level)
		assert_eq(main.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 202), 0.0)
		assert_eq(near.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 1), 0.0)


func test_squad_extends_armor_effect_to_original_circle_before_knockback() -> void:
	var cast := _cast(5, true)
	var main := _enemy()
	var near := _enemy(0.62)
	var far := _enemy(0.64)
	PBSkillRules.land_on_enemy(cast, [main, near, far], _cfg, 1, null, 100.0)
	assert_gt(near.distance - main.distance, cast.skill.radius)
	assert_eq(main.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 1), -40.0)
	assert_eq(near.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 1), -40.0)
	assert_eq(far.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 1), 0.0)


func test_landing_follows_target_and_dead_target_does_not_hit_neighbors() -> void:
	var cast := _cast()
	cast.spot = Vector2.ZERO
	var main := _enemy(0.8)
	var near := _enemy(0.81)
	PBSkillRules.land_on_enemy(cast, [main, near], _cfg, 1, null, 100.0)
	assert_eq(cast.spot, Vector2(0.8, 0.0))
	main.alive = false
	var hp: float = near.hp
	PBSkillRules.land_on_enemy(cast, [main, near], _cfg, 2, null, 100.0)
	assert_eq(near.hp, hp)


func test_tooltip_distinguishes_area_stun_and_primary_armor() -> void:
	var body := PBEffectWords.skill_body(_cast().skill, _cfg)
	assert_string_contains(body, "点敌人")
	assert_string_contains(body, "眩晕")
	assert_string_contains(body, "主目标附带")
	assert_false(body.contains("全场减速"))
	assert_string_contains(PBEffectWords.skill_body(_cast(1, true).skill, _cfg), "范围附带")
