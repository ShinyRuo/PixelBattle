extends GutTest

const SECONDS := [1, 1, 2, 2, 2, 3, 3, 3, 3, 4]
var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.march_seconds = 1000000.0
	_cfg.unit_min_gap = 0.0


func _caster(level: int = 1) -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"kushina"))
	unit.level = level
	var one: PBAttacker = (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	for cast: PBSkillCast in one.skills:
		if cast.skill.id == &"adamantine_chains":
			one.skills = [cast]
			break
	return one


func _ability() -> PBEnemyAbility:
	var skill := PBEnemyAbility.new()
	skill.id = &"probe_blast"
	skill.damage_base = 100.0
	skill.intellect_scale = 0.0
	skill.element = PBElement.Type.PHYSICAL
	skill.reach = 1.0
	skill.cooldown_ticks = 10
	return skill


func _enemy(abilities: Array[PBEnemyAbility] = []) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.abilities = abilities
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.5, 0)
	return enemy


func _seal(one: PBAttacker, enemy: PBEnemy, tick: int = 0) -> void:
	var cast := one.skills[0]
	cast.spot = enemy.pos()
	PBSkillRules.land(cast, [enemy], 0, _cfg, tick, one, cast.skill.damage)


func test_ten_level_silence_slow_and_expiry_without_damage_or_stun() -> void:
	for level: int in range(1, 11):
		var one := _caster(level)
		var enemy := _enemy()
		_seal(one, enemy)
		var end: int = SECONDS[level - 1] * 20
		assert_eq(enemy.hp, enemy.max_hp)
		assert_eq(enemy.buffs.amount(PBBuffRules.SILENCE, end), 1.0)
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, end), 0.5)
		assert_eq(enemy.buffs.amount(PBBuffRules.SILENCE, end + 1), 0.0)
		assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_SPEED_SCALE, end + 1), 1.0)
		assert_true(enemy.ready_to_fire(1))
		assert_eq(one.skills[0].skill.slow_ticks, 0)
		assert_string_contains(PBEffectWords.skill_body(one.skills[0].skill, _cfg, level), "无直接伤害")


func test_area_control_does_not_touch_neighbors_outside_circle() -> void:
	var one := _caster()
	var inside := _enemy()
	var outside := _enemy()
	outside.lane = 0.18
	var cast := one.skills[0]
	cast.spot = inside.pos()
	PBSkillRules.land(cast, [inside, outside], 0, _cfg, 0, one, 0.0)
	assert_eq(inside.buffs.amount(PBBuffRules.SILENCE, 1), 1.0)
	assert_eq(outside.buffs.amount(PBBuffRules.SILENCE, 1), 0.0)
	inside.speed = 0.1
	inside.march_to(Vector2.ZERO, 1.0, 1)
	assert_almost_eq(inside.distance, 0.45, 0.00001)


func test_silence_blocks_skill_without_spending_cooldown_and_expires() -> void:
	var one := _caster()
	one.hp = one.max_hp
	one.alive = true
	one.ninjutsu_resist = 0.0
	var enemy := _enemy([_ability()])
	_seal(one, enemy)
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 20, null, null, PBCombatOutcome.new())
	assert_eq(one.hp, one.max_hp)
	assert_eq(enemy.ability_ready_at[0], 0)
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 21, null, null, PBCombatOutcome.new())
	assert_almost_eq(one.max_hp - one.hp, 100.0, 0.001)
	assert_eq(enemy.ability_ready_at[0], 31)
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 22, null, null, PBCombatOutcome.new())
	assert_almost_eq(one.max_hp - one.hp, 100.0, 0.001)


func test_six_frame_chain_link_uses_real_debuff_source() -> void:
	var one := _caster()
	var enemy := _enemy()
	_seal(one, enemy)
	var found := false
	for state: PBBuffState in enemy.buffs.states():
		if state.buff == null or state.buff.id != &"kushina_chains":
			continue
		found = true
		assert_eq(state.source_slot, one.slot)
		assert_null(state.channel)
		assert_true(state.is_live(1))
	assert_true(found)
	var skin := PBFieldArt.read("links", &"kushina_chains")
	assert_not_null(skin)
	assert_eq(skin.frames.size(), 6)
	assert_eq(skin.link_width, 56.0)
	for frame: Texture2D in skin.frames:
		assert_eq(frame.get_size(), Vector2(256, 256))
	var choices := PBFieldArtBindings.new().choices()
	assert_true(choices.any(func(row: Dictionary) -> bool:
		return row.kind == "links" and row.id == "kushina_chains"))


func test_both_normal_attack_kinds_continue_while_silenced() -> void:
	for kind: PBDamageKind.Type in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		var one := _caster()
		var enemy := _enemy()
		enemy.damage_kind = kind
		enemy.damage_per_shot = 100.0
		enemy.intellect = 100.0
		_seal(one, enemy)
		assert_true(enemy.ready_to_fire(1))
		assert_gt(float(PBCritRules.enemy_strike(enemy, 1)[PBCritRules.DAMAGE]), 0.0)


func test_ability_uses_own_kind_and_element_and_ninjutsu_defence() -> void:
	var one := _caster()
	one.hp = one.max_hp
	one.alive = true
	one.defence = 100000.0
	one.ninjutsu_resist = 0.4
	var enemy := _enemy([_ability()])
	enemy.damage_kind = PBDamageKind.Type.TAIJUTSU
	enemy.ninjutsu_pen = 0.5
	enemy.ninjutsu_bonus = 0.5
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_almost_eq(one.max_hp - one.hp, 120.0, 0.001)


func test_spawn_and_target_range_and_pool_reset() -> void:
	var one := _caster()
	one.hp = one.max_hp
	one.alive = true
	one.pos = Vector2.ZERO
	var ability := _ability()
	ability.reach = 0.1
	var enemy := _enemy([ability])
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(enemy.ability_ready_at[0], 0)
	one.pos = enemy.pos()
	enemy.spawn_tick = 10
	PBEnemyAbilityRules.advance(enemy, [one], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(one.hp, one.max_hp)
	var wave := PBWave.new()
	enemy.spawn(wave, 0.0, 0.5, 0)
	assert_true(enemy.abilities.is_empty())
	assert_true(enemy.ability_ready_at.is_empty())


func test_real_sim_casts_enemy_ability_only_after_seal_expires() -> void:
	var one := _caster()
	one.ultimate = null
	one.attack = 0.0
	one.dps = 0.0
	one.move_speed = 0.0
	one.ninjutsu_resist = 0.0
	one.pos = Vector2(0.5, 0.0)
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000.0
	wave.abilities = [_ability()]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, [one])
	var enemy := sim.enemies()[0]
	enemy.distance = 0.5
	enemy.speed = 0.0
	enemy.damage_per_shot = 0.0
	enemy.ability_ready_at[0] = 6  # 起手期间不抢先施法，单独测封印窗口。
	assert_true(sim.cast_skill(one, enemy.pos(), 1))
	for tick: int in 26:
		sim.step()
	assert_eq(one.hp, one.max_hp)
	sim.step()
	assert_almost_eq(one.max_hp - one.hp, 100.0, 0.001)


func test_invalid_ability_parameters_are_rejected() -> void:
	var ability := _ability()
	assert_eq(ability.validate(), "")
	ability.cooldown_ticks = 0
	assert_ne(ability.validate(), "")
	ability.cooldown_ticks = 10
	ability.reach = NAN
	assert_ne(ability.validate(), "")


func test_stun_blocks_active_casts_and_cooldowns_belong_to_each_enemy() -> void:
	var one := _caster()
	one.hp = one.max_hp
	one.alive = true
	var shared := _ability()
	var first := _enemy([shared])
	var second := _enemy([shared])
	var stun := PBBuff.new()
	stun.id = &"probe_stun"
	stun.kind = PBBuff.Kind.DURATION
	first.buffs.add(stun, {PBBuffRules.STUN: 1.0}, 0, 10, 0)
	PBEnemyAbilityRules.advance(first, [one], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(first.ability_ready_at[0], 0)
	PBEnemyAbilityRules.advance(second, [one], _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(second.ability_ready_at[0], 11)
	assert_eq(first.ability_ready_at[0], 0)
	assert_false(first.ready_to_fire(1))
