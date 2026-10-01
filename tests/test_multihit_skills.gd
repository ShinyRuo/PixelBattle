extends GutTest
## 真正跨 tick 的连击：公式、命中几何、逐段防御、冷却及战斗记账。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.march_seconds = 1000000.0


func _caster(id: StringName, level: int = 1) -> PBAttacker:
	for character: PBCharacter in _cfg.characters.all():
		if character.skill_ids.has(id):
			var unit := PBUnit.new(character)
			unit.level = level
			return (
				PBCombatRules
				. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
			)
	fail_test("没有技能所属角色")
	return PBAttacker.new()


func _cast(one: PBAttacker, id: StringName) -> PBSkillCast:
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == id:
			cast.spot = Vector2(0.5, 0.0)
			return cast
	return null


func _enemy(at: float = 0.5) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, at, 0)
	return enemy


func test_original_per_hit_formulas_at_three_levels_and_kind() -> void:
	for id: StringName in [&"iron_sand", &"false_darkness"]:
		for level: int in [1, 5, 10]:
			var one := _caster(id, level)
			var skill := _cast(one, id).skill
			var sand: bool = id == &"iron_sand"
			var stat: StringName = &"agility" if sand else &"strength"
			var raw: float = (20.0 if sand else 30.0) * level
			var value := float(one.damage_attributes[stat])
			raw += (value if sand else floorf(value)) * (0.2 if sand else 0.1)
			var relation := PBElement.relation(skill.element, PBElement.Type.PHYSICAL)
			assert_almost_eq(skill.damage, raw * _cfg.damage_multiplier(relation), 0.001)
			assert_eq(skill.kind, PBDamageKind.Type.NINJUTSU)
			assert_eq(skill.hit_count, 30 if sand else 60)
			assert_true(skill.on_hit.is_empty(), "不能再额外挂旧磨蚀伤害")


func test_sand_exact_thirty_hits_with_no_extra_initial_or_final_hit() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	cast.skill.damage = 10.0
	var barrage := PBSkillBarrage.new()
	barrage.begin(one, cast, 7)
	var enemy := _enemy()
	for tick: int in 75:
		barrage.advance([enemy], 0, _cfg, tick, null, null)
		var expected: int = 0 if tick < 7 else mini(1 + int((tick - 7) / 2.0), 30)
		assert_almost_eq(enemy.hp, enemy.max_hp - 10.0 * expected, 0.001)
	assert_eq(barrage.fired, 30)
	assert_false(barrage.active())
	assert_eq(barrage.last_at, 65)


func test_lightning_sixty_landings_in_twenty_simultaneous_rounds() -> void:
	var one := _caster(&"false_darkness")
	var cast := _cast(one, &"false_darkness")
	cast.skill.damage = 10.0
	var barrage := PBSkillBarrage.new()
	barrage.begin(one, cast, 0)
	var enemy := _enemy(one.pos.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var hits := 0
	for tick: int in 85:
		barrage.advance([enemy], 0, _cfg, tick, rng, null)
		assert_eq(barrage.fired, mini(tick / 4, 20) * 3)
		if tick > 0 and tick <= 80 and tick % 4 == 0:
			assert_eq(barrage.landings.size(), 3)
			for spot: Vector2 in barrage.landings:
				var ring := spot.distance_to(one.pos) / 0.0375
				assert_almost_eq(ring, roundf(ring), 0.00001)
				assert_between(roundi(ring), 1, 7)
				if spot.distance_to(enemy.pos()) <= 0.0775:
					hits += 1
	assert_eq(barrage.last_at, 80)
	assert_false(barrage.active())
	assert_gt(hits, 0)
	assert_lt(hits, 60)
	assert_almost_eq(enemy.hp, enemy.max_hp - hits * 10.0, 0.001)
	assert_eq(cast.skill.radius, 0.2625)


func test_each_hit_rechecks_entry_exit_spawn_and_dead_targets() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	cast.skill.damage = 10.0
	var barrage := PBSkillBarrage.new()
	barrage.begin(one, cast, 0)
	var leaving := _enemy()
	var entering := _enemy(0.9)
	var late := _enemy()
	late.spawn_tick = 2
	var enemies: Array[PBEnemy] = [leaving, entering, late]
	barrage.advance(enemies, 0, _cfg, 0, null, null)
	assert_eq(leaving.hp, leaving.max_hp - 10.0)
	assert_eq(late.hp, late.max_hp)
	leaving.distance = 0.9
	entering.distance = 0.5
	barrage.advance(enemies, 0, _cfg, 2, null, null)
	assert_eq(leaving.hp, leaving.max_hp - 10.0)
	assert_eq(entering.hp, entering.max_hp - 10.0)
	assert_eq(late.hp, late.max_hp - 10.0)
	entering.hp = 5.0
	assert_eq(barrage.advance(enemies, 0, _cfg, 4, null, null), 1)
	assert_eq(barrage.advance(enemies, 0, _cfg, 6, null, null), 0)


func test_each_hit_uses_ninjutsu_crit_pen_resistance_and_shield() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	cast.skill.damage = 100.0
	one.ninjutsu_bonus = 0.5
	one.ninjutsu_pen = 0.5
	one.ninjutsu_crit_chance = 1.0
	one.taijutsu_bonus = 99.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 83
	var enemy := _enemy()
	enemy.armor = 10000.0
	enemy.ninjutsu_resist = 0.4
	var guard := PBBuff.new()
	guard.id = &"test_multihit_shield"
	guard.kind = PBBuff.Kind.DURATION
	enemy.buffs.add(guard, {PBBuffRules.SHIELD: 300.0}, 0, 100, 0)
	var barrage := PBSkillBarrage.new()
	barrage.begin(one, cast, 0)
	var book := PBBattleLog.new()
	barrage.advance([enemy], 0, _cfg, 0, rng, book)
	assert_eq(enemy.hp, enemy.max_hp)
	assert_almost_eq(enemy.buffs.shield_left(0), 60.0, 0.001)
	# 第二段改抗性：必须重新减伤，不能首段算一个总伤害。
	enemy.ninjutsu_resist = 0.8
	barrage.advance([enemy], 0, _cfg, 2, rng, book)
	assert_almost_eq(enemy.hp, enemy.max_hp - 120.0, 0.001)
	assert_true(book.entries[0]["crit"])
	assert_true(book.entries[1]["crit"])
	assert_almost_eq(float(book.entries[1]["amount"]), 180.0, 0.001)


func _sim(one: PBAttacker, cast: PBSkillCast) -> PBBattleSim:
	one.ultimate = null
	one.skills = [cast]
	one.dps = 0.0
	one.attack = 0.0
	one.move_speed = 0.0
	one.max_hp = 0.0
	one.max_mp = 100.0
	one.mp_regen = 0.0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	return PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])


func test_real_sim_charges_once_and_reset_allows_independent_overlap() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	cast.skill.damage = 10.0
	var sim := _sim(one, cast)
	var enemy := sim.enemies()[0]
	assert_true(sim.cast_skill(one, enemy.pos(), 1))
	for tick: int in 15:
		sim.step()
	assert_eq(enemy.hp, enemy.max_hp)
	sim.step()
	assert_eq(enemy.hp, enemy.max_hp - 10.0)
	assert_eq(one.mp, 90.0)
	assert_eq(cast.ready_at, 476)
	assert_false(cast.is_pending())
	assert_false(sim.cast_skill(one, enemy.pos(), 1))
	cast.ready_at = sim.current_tick()
	assert_true(sim.cast_skill(one, enemy.pos(), 1))
	for tick: int in 16:
		sim.step()
	assert_eq(sim.barrages().size(), 2)
	assert_eq(one.mp, 80.0)
	assert_eq(enemy.hp, enemy.max_hp - 100.0)
	for tick: int in 65:
		sim.step()
	assert_eq(enemy.hp, enemy.max_hp - 600.0)
	assert_eq(one.mp, 80.0)
	assert_eq(cast.ready_at, 492)


func test_real_sim_caster_death_keeps_cast_and_counts_kill_once() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	cast.skill.damage = 10.0
	var sim := _sim(one, cast)
	var enemy := sim.enemies()[0]
	enemy.hp = 25.0
	assert_true(sim.cast_skill(one, enemy.pos(), 1))
	PBCastTestClock.release(sim, one)
	one.alive = false
	for tick: int in 30:
		sim.step()
	assert_false(enemy.alive)
	assert_eq(sim.result().kills, 1)
	assert_eq(sim.current_tick(), 20)
	assert_eq(sim.barrages()[0].fired, 3)


func test_new_wave_does_not_retain_old_barrage_and_cast_is_reusable() -> void:
	var one := _caster(&"iron_sand")
	var cast := _cast(one, &"iron_sand")
	var old_sim := _sim(one, cast)
	assert_true(old_sim.cast_skill(one, old_sim.enemies()[0].pos(), 1))
	for tick: int in 18:
		old_sim.step()
	assert_true(old_sim.barrages()[0].active())
	var next_sim := _sim(one, cast)
	assert_true(next_sim.barrages().is_empty())
	assert_eq(cast.ready_at, 0)
	assert_eq(one.mp, 100.0)
	for tick: int in 18:
		next_sim.step()
	assert_eq(next_sim.enemies()[0].hp, next_sim.enemies()[0].max_hp)


func test_invalid_multihit_data_is_rejected() -> void:
	var skill := PBSkill.new()
	assert_eq(PBSkillRules.validate(skill), "")
	skill.hit_count = 0
	assert_ne(PBSkillRules.validate(skill), "")
	skill.hit_count = 2
	assert_ne(PBSkillRules.validate(skill), "")
	skill.hit_interval_ticks = 2
	assert_eq(PBSkillRules.validate(skill), "")
	skill.target = PBSkill.Target.NONE
	assert_eq(PBSkillRules.validate(skill), "")
	skill.hit_radius = 0.1
	assert_ne(PBSkillRules.validate(skill), "")
	skill.target = PBSkill.Target.GROUND
	skill.hit_radius = NAN
	assert_ne(PBSkillRules.validate(skill), "")
	skill.hit_radius = 0.1
	skill.hit_count = 1
	assert_ne(PBSkillRules.validate(skill), "")


func test_tooltip_and_ground_ring_use_per_hit_geometry() -> void:
	var one := _caster(&"false_darkness")
	var cast := _cast(one, &"false_darkness")
	var body := PBEffectWords.skill_body(cast.skill, _cfg)
	assert_string_contains(body, "共 60 段")
	assert_string_contains(body, "每段伤害")
	assert_string_contains(body, "单个目标不一定全中")
	var barrage := PBSkillBarrage.new()
	barrage.begin(one, cast, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	barrage.advance([_enemy()], 0, _cfg, 4, rng, null)
	var pool := PBTelegraphPool.new()
	add_child_autofree(pool)
	var field := Vector2(1.0, 0.6)
	pool.sync_pending([], 4, field, [barrage])
	assert_eq(pool.shown(), 3)
	assert_almost_eq(pool.radius_of(0), 0.0775 * PBLayout.px_per_unit(field), 0.001)
	pool.sync_pending([], 7, field, [barrage])
	assert_eq(pool.shown(), 0)
