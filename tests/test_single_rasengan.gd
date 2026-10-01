extends GutTest
## 锁定技能只控制所选目标，单体击退与施法者闪烁分别结算。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _enemy(x: float = 0.5) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 1.0, 0)
	enemy.distance = x
	return enemy


func _cast(id: StringName) -> PBSkillCast:
	var cast := PBSkillCast.new(_cfg.skills.by_id(id), 1)
	cast.target_slot = 0
	return cast


func test_flame_stuns_only_selected_enemy_and_pushes_survivor() -> void:
	var cast := _cast(&"rasengan_flame")
	var primary := _enemy()
	var neighbor := _enemy(0.501)
	PBSkillRules.land_on_enemy(cast, [primary, neighbor], _cfg, 1, null, 100.0)
	assert_eq(primary.hp, 99900.0)
	assert_almost_eq(primary.distance, 0.54, 0.000001)
	assert_false(primary.ready_to_fire(61))
	assert_true(primary.ready_to_fire(62))
	assert_eq(primary.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, 61), 0.0)
	assert_eq(neighbor.hp, neighbor.max_hp)
	assert_eq(neighbor.distance, 0.501)
	assert_true(neighbor.ready_to_fire(1))
	assert_eq(cast.skill.radius, 0.0)
	assert_eq(cast.skill.slow_ticks, 0)


func test_single_push_respects_spawn_limit_and_does_not_move_corpse() -> void:
	var cast := _cast(&"rasengan_flame")
	var primary := _enemy(0.99)
	PBSkillRules.land_on_enemy(cast, [primary], _cfg, 1, null, 100.0)
	assert_eq(primary.distance, 1.0)
	primary.distance = 0.5
	assert_eq(PBSkillRules.land_on_enemy(cast, [primary], _cfg, 2, null, 200000.0), 1)
	assert_eq(primary.distance, 0.5)


func test_flash_moves_caster_behind_target_without_pve_knockback() -> void:
	var cast := _cast(&"flying_raijin_ball")
	var caster := PBAttacker.new()
	caster.alive = true
	caster.reach = 0.0625
	caster.pos = Vector2(0.1, 0.0)
	var primary := _enemy()
	PBSkillRules.land_on_enemy(cast, [primary], _cfg, 1, caster, 100.0)
	assert_eq(caster.pos, primary.pos() + Vector2(caster.stop_gap(), 0.0))
	assert_lt(caster.pos.distance_to(primary.pos()), caster.reach)
	assert_eq(primary.distance, 0.5)
	assert_false(primary.ready_to_fire(41))
	assert_true(primary.ready_to_fire(42))
	assert_eq(cast.skill.knockback, 0.0)
	assert_eq(cast.skill.slow_ticks, 0)


func test_flash_does_not_teleport_to_dead_or_unspawned_target() -> void:
	var cast := _cast(&"flying_raijin_ball")
	var caster := PBAttacker.new()
	caster.alive = true
	caster.pos = Vector2(0.1, 0.2)
	var primary := _enemy()
	primary.alive = false
	PBSkillRules.land_on_enemy(cast, [primary], _cfg, 1, caster, 100.0)
	assert_eq(caster.pos, Vector2(0.1, 0.2))
	primary.alive = true
	primary.spawn_tick = 10
	PBSkillRules.land_on_enemy(cast, [primary], _cfg, 1, caster, 100.0)
	assert_eq(caster.pos, Vector2(0.1, 0.2))


func test_flame_formula_preserves_strength_and_max_health() -> void:
	var skill := _cast(&"rasengan_flame").skill
	var stats := PBStats.new()
	stats.strength = 50.0
	stats.hp = 2000.0
	stats.intellect = 1000.0
	assert_eq(PBSkillDamage.raw(skill, stats, 1), 300.0)
	assert_eq(PBSkillDamage.raw(skill, stats, 10), 300.0)
	assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
	assert_eq(skill.element, PBElement.Type.FIRE)


func test_blink_validation_and_tooltips_prevent_silent_unsupported_modes() -> void:
	var skill := _cast(&"flying_raijin_ball").skill.clone()
	assert_eq(PBSkillDamage.validate(skill), "")
	assert_string_contains(PBEffectWords.skill_body(skill, _cfg), "闪到目标后侧")
	assert_false(PBEffectWords.skill_body(skill, _cfg).contains("全场减速"))
	skill.target = PBSkill.Target.GROUND
	assert_ne(PBSkillDamage.validate(skill), "")
	skill.target = PBSkill.Target.ENEMY
	skill.shot_cross_seconds = 0.3
	assert_ne(PBSkillDamage.validate(skill), "")
