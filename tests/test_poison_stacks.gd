extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _team(level: int = 1, bonded: bool = false) -> Array[PBAttacker]:
	var cards: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(&"sasori"))]
	if bonded:
		cards.append(PBUnit.new(_cfg.characters.by_id(&"chiyo")))
	for card: PBUnit in cards:
		card.level = level
	var team := PBCombatRules.build_attackers(
		cards,
		PBElement.Type.WIND,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		{},
		PBBondRules.active_passives(cards, cards, _cfg.bonds),
		PBBondRules.active_skill_patches(cards, cards, _cfg.bonds)
	)
	for unit: PBAttacker in team:
		unit.revive()
	return team


func _enemy() -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.5, 0)
	enemy.slot = 0
	return enemy


func _hit(caster: PBAttacker, enemy: PBEnemy, tick: int) -> void:
	PBStrikeRules.land(caster, enemy, 1.0, false, [enemy], _cfg, tick, null, PBCombatOutcome.new())


func test_ten_levels_each_hit_has_five_independent_ticks() -> void:
	for level: int in range(1, 11):
		var caster := _team(level)[0]
		var enemy := _enemy()
		_hit(caster, enemy, 0)
		var total: float = 0.0
		for tick: int in range(1, 102):
			var damage: float = PBBuffRules.advance_enemy(enemy, tick, _cfg)
			if tick % 20 == 0:
				assert_almost_eq(damage, 10.0 + 4.0 * level, 0.001)
			else:
				assert_eq(damage, 0.0)
			total += damage
		assert_almost_eq(total, (10.0 + 4.0 * level) * 5.0, 0.001)
		assert_eq(enemy.buffs.count(101), 0)


func test_many_layers_keep_their_schedule_and_restore_each_armor_share() -> void:
	var caster := _team(1, true)[0]
	var enemy := _enemy()
	for tick: int in 12:
		_hit(caster, enemy, tick)
	assert_eq(enemy.buffs.count(12), 13)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 12), -24.0)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 12), 0.7)
	var total: float = 0.0
	for tick: int in range(12, 112):
		total += PBBuffRules.advance_enemy(enemy, tick, _cfg)
		if tick >= 100:
			assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, tick), -2.0 * (111 - tick))
	assert_almost_eq(total, 12.0 * 5.0 * 21.0, 0.001)
	assert_eq(enemy.buffs.count(112), 0)


func test_refreshing_slow_and_overflowing_normal_slots_cannot_discard_poison() -> void:
	var caster := _team()[0]
	var enemy := _enemy()
	_hit(caster, enemy, 0)
	_hit(caster, enemy, 10)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 50), 0.7)
	for i: int in PBBuffBag.SLOTS + 4:
		var buff := PBBuff.new()
		buff.id = StringName("probe_%d" % i)
		buff.kind = PBBuff.Kind.DURATION
		enemy.buffs.add(buff, {PBBuffRules.HURT: 1.0}, 11, 200, 0)
	assert_eq(enemy.buffs.count(12), PBBuffBag.SLOTS + 2)
	assert_eq(PBBuffRules.advance_enemy(enemy, 20, _cfg), 14.0)
	assert_eq(PBBuffRules.advance_enemy(enemy, 30, _cfg), 14.0)
	var capacity: int = enemy.buffs.states().size()
	enemy.buffs.clear()
	_hit(caster, enemy, 40)
	_hit(caster, enemy, 40)
	assert_eq(enemy.buffs.states().size(), capacity)
	assert_eq(enemy.buffs.count(40), 3)


func test_poison_uses_ninjutsu_resistance_and_wind_relation_independent_of_armor() -> void:
	var caster := _team()[0]
	caster.ninjutsu_bonus = 0.2
	caster.ninjutsu_pen = 0.25
	for element: int in range(PBElement.Type.size()):
		var enemy := _enemy()
		enemy.element = element as PBElement.Type
		enemy.armor = 10000.0
		enemy.ninjutsu_resist = 0.6
		_hit(caster, enemy, 0)
		var expected: float = 14.0 * 1.2 * (1.0 - 0.6 * 0.75)
		expected *= _cfg.damage_multiplier(PBElement.relation(PBElement.Type.WIND, enemy.element))
		assert_almost_eq(PBBuffRules.advance_enemy(enemy, 20, _cfg), expected, 0.001)


func test_existing_layers_keep_source_snapshot_after_death_and_new_hits_change() -> void:
	var caster := _team(1, true)[0]
	var enemy := _enemy()
	_hit(caster, enemy, 0)
	caster.stack_harm_bonus = 2.0
	caster.stack_defence = -7.0
	caster.ninjutsu_bonus = 3.0
	caster.alive = false
	assert_eq(PBBuffRules.advance_enemy(enemy, 20, _cfg), 21.0)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 20), -2.0)
	caster.alive = true
	_hit(caster, enemy, 21)
	assert_eq(enemy.buffs.amount(PBBuffRules.ENEMY_DEFENCE, 21), -9.0)
	assert_eq(PBBuffRules.advance_enemy(enemy, 41, _cfg), 21.0 + 14.0 * 3.0 * 4.0)


func test_real_bond_boosts_transfer_and_poison_without_polluting_base_resources() -> void:
	var team := _team(10, true)
	var caster := team[1]
	var cast := caster.skills[0]
	assert_eq(team[0].stack_harm_bonus, 0.5)
	assert_eq(cast.skill.transfer_scale, 1.5)
	cast.origin = caster.pos
	cast.target_slot = 0
	PBSkillRules.land_on_ally(cast, team, _cfg, 0, caster)
	for key: StringName in [&"strength", &"agility", &"intellect"]:
		var expected: float = floorf(floorf(floorf(caster.damage_attributes[key]) * 0.99) * 0.6)
		assert_eq(float(team[0].attribute_profile.temporary[key]), expected)
	assert_eq(_cfg.skills.by_id(&"reincarnation").transfer_scale, 1.0)
	assert_eq(_team()[0].stack_harm_bonus, 0.0)
	assert_eq(team[0].clone().stack_defence, -2.0)
	assert_false(
		_cfg.characters.by_id(&"sasori").attack_buffs[1].mods.has(PBBuffRules.ENEMY_DEFENCE)
	)


func test_stack_validation_and_tooltips_describe_only_supported_effects() -> void:
	var buff: PBBuff = _cfg.characters.by_id(&"sasori").attack_buffs[1].duplicate(true)
	assert_eq(PBBuffRules.validate(buff), "")
	assert_true(PBEffectWords.buff_line(buff, 10).contains("独立叠层"))
	buff.mods[PBBuffRules.ENEMY_ATTACK_SPEED_SCALE] = 0.7
	assert_ne(PBBuffRules.validate(buff), "")
	buff.mods.erase(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE)
	buff.friendly = true
	assert_ne(PBBuffRules.validate(buff), "")
	assert_true(PBShopLabels.mod_words({PBPassiveRules.STACK_HARM_BONUS: 0.5})[0].contains("50%"))


func test_poison_kill_is_counted_once_and_next_wave_clears_layers() -> void:
	var team := _team()
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 15.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	var enemy := sim.enemies()[0]
	_hit(team[0], enemy, 0)
	team[0].alive = false
	enemy.speed = 0.0
	enemy.damage_per_shot = 0.0
	for tick: int in 45:
		sim.step()
	assert_false(enemy.alive)
	assert_eq(sim.result().kills, 1)
	enemy.spawn(wave, 0.0, 0.5, 0)
	assert_eq(enemy.buffs.count(0), 0)
