extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0.0
	_cfg.field_height = 0.0
	_cfg.unit_min_gap = 0.0


func _team(level: int = 1, bonded: bool = false) -> Array[PBAttacker]:
	var cards: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(&"shisui"))]
	if bonded:
		cards.append(PBUnit.new(_cfg.characters.by_id(&"itachi")))
	for card: PBUnit in cards:
		card.level = level
	var team := PBCombatRules.build_attackers(
		cards,
		PBElement.Type.PHYSICAL,
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
	for one: PBAttacker in team:
		if not one.summoned:
			one.revive()
	team[0].pos = Vector2.ZERO
	return team


func _enemy(slot: int = 0, ranged: bool = true) -> PBEnemy:
	var wave := PBWave.new()
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.1 + slot * 0.1, 0)
	enemy.slot = slot
	enemy.shot_speed = 0.1 if ranged else 0.0
	return enemy


func _sequence(team: Array[PBAttacker]) -> PBExpandingStrike:
	var sequence := PBExpandingStrike.new()
	sequence.team = team
	sequence.begin(team[0], team[0].skills[1], 0)
	sequence.cast.skill.damage = 0.0
	return sequence


func _phantoms(team: Array[PBAttacker]) -> Array[PBAttacker]:
	var out: Array[PBAttacker] = []
	for one: PBAttacker in team:
		if one.phantom and one.alive:
			out.append(one)
	return out


func test_ten_levels_inherit_attack_crit_and_native_interval_with_three_second_lifetime() -> void:
	for level: int in range(1, 11):
		var team := _team(level)
		team[0].crit_chance = 0.25
		var sequence := _sequence(team)
		var enemy := _enemy()
		sequence.advance([enemy], 0, _cfg, 2, null, null)
		var phantoms := _phantoms(team)
		assert_eq(phantoms.size(), 1)
		var one := phantoms[0]
		assert_almost_eq(one.attack, team[0].damage_attributes[&"attack"] * 0.35, 0.001)
		assert_eq(one.crit_chance, 0.25)
		assert_eq(one.attack_element, PBElement.Type.THUNDER)
		assert_eq(PBCritRules.attack_kind(one), PBDamageKind.Type.TAIJUTSU)
		assert_almost_eq(one.attack_speed, (1.0 + 0.15 * level) / 1.5, 0.00001)
		assert_eq(one.windup_ticks, 4)
		assert_almost_eq(one.reach, 0.06, 0.00001)
		assert_eq(one.expires_at, 62)
		assert_false(one.is_targetable())
		assert_eq(PBSummonRules.expire(team, 61), 0)
		assert_eq(PBSummonRules.expire(team, 62), 1)


func test_full_bond_reserves_eighteen_phantoms_and_gives_double_count_and_fifty_five_percent(
) -> void:
	var team := _team(1, true)
	assert_eq(team.size(), 20)
	var sequence := _sequence(team)
	var enemies: Array[PBEnemy] = []
	for i: int in 9:
		var enemy := _enemy(i)
		enemy.distance = 0.1 + i * 0.02
		enemies.append(enemy)
	for tick: int in range(2, 19, 2):
		sequence.advance(enemies, 0, _cfg, tick, null, null)
	var phantoms := _phantoms(team)
	assert_eq(phantoms.size(), 18)
	assert_almost_eq(phantoms[0].attack, sequence.inherited_attack * 0.55, 0.001)
	assert_eq(phantoms[0].expires_at, 92)
	assert_eq(phantoms[17].expires_at, 108)
	assert_ne(phantoms[0].pos, phantoms[1].pos)
	assert_eq(_cfg.skills.by_id(&"sun_halo_dance").phantom_count, 1)
	assert_eq(_cfg.skills.by_id(&"sun_halo_dance").summon_power, 0.35)


func test_last_actual_target_decides_teleport_and_empty_steps_preserve_it() -> void:
	for final_ranged: bool in [false, true]:
		var team := _team()
		var sequence := _sequence(team)
		var enemies: Array[PBEnemy] = [_enemy(0, true), _enemy(1, final_ranged)]
		for tick: int in range(2, 19, 2):
			sequence.advance(enemies, 0, _cfg, tick, null, null)
		assert_eq(_phantoms(team).size(), 2 if final_ranged else 1)
		var expected := enemies[1].pos() + Vector2(0.04, 0.0) if final_ranged else Vector2.ZERO
		assert_eq(team[0].pos, expected)
		assert_eq(team[0].forced_target, 1 if final_ranged else -1)


func test_phantom_is_immune_untargetable_and_does_not_inherit_passive_chains() -> void:
	var team := _team()
	var enemy := _enemy()
	var sequence := _sequence(team)
	sequence.advance([enemy], 0, _cfg, 2, null, null)
	var one := _phantoms(team)[0]
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(one, enemy, 100000.0, enemy.element, _cfg, 3, null, null, out)
	assert_eq(one.hp, 5.0)
	assert_eq(out.allies_lost, 0)
	assert_null(PBTargetRules.nearest_ally([one], enemy))
	assert_true(one.skills.is_empty())
	assert_null(one.ultimate)
	assert_true(one.attack_buffs.is_empty())
	assert_true(one.on_hit_buffs.is_empty())
	assert_eq(one.lifesteal, 0.0)


func test_attack_is_frozen_at_cast_while_crit_is_read_when_each_phantom_appears() -> void:
	var team := _team()
	var sequence := _sequence(team)
	var inherited: float = sequence.inherited_attack
	team[0].damage_attributes[&"attack"] = 99999.0
	team[0].crit_chance = 0.75
	team[0].alive = false
	var enemy := _enemy()
	sequence.advance([enemy], 0, _cfg, 2, null, null)
	var one := _phantoms(team)[0]
	assert_almost_eq(one.attack, inherited * 0.35, 0.001)
	assert_eq(one.crit_chance, 0.75)
	for tick: int in range(4, 19, 2):
		sequence.advance([enemy], 0, _cfg, tick, null, null)
	assert_eq(team[0].pos, Vector2.ZERO)
	assert_true(one.alive)


func test_melee_hits_and_full_pool_do_not_fake_extra_damage() -> void:
	var team := _team()
	var sequence := _sequence(team)
	var melee := _enemy(0, false)
	sequence.advance([melee], 0, _cfg, 2, null, null)
	assert_true(_phantoms(team).is_empty())
	sequence.team = [team[0]]
	var ranged := _enemy(1, true)
	sequence.advance([ranged], 0, _cfg, 4, null, null)
	assert_true(_phantoms(team).is_empty())
	assert_eq(ranged.hp, ranged.max_hp)


func test_reusing_phantom_slot_for_normal_summon_clears_immunity_and_inherited_crit() -> void:
	var team := _team()
	team[0].crit_chance = 0.75
	var sequence := _sequence(team)
	sequence.advance([_enemy()], 0, _cfg, 2, null, null)
	var one := _phantoms(team)[0]
	PBSummonRules.expire(team, 62)
	var summon := PBSkill.new()
	summon.summon_count = 1
	summon.summon_power = 0.2
	summon.summon_hp_share = 0.5
	summon.summon_seconds = 3.0
	assert_eq(PBSummonRules.raise_from(team, team[0], summon, 63, _cfg), 1)
	assert_false(one.phantom)
	assert_true(one.is_targetable())
	assert_eq(one.appearance_slot, -1)
	assert_eq(one.crit_chance, 0.0)
	assert_eq(one.clone().phantom, false)


func test_real_battle_phantoms_attack_and_expire_without_lost_ninja_accounting() -> void:
	var team := _team()
	var caster := team[0]
	caster.attack = 0.0
	caster.dps = 0.0
	caster.move_speed = 0.0
	caster.skills[1].skill.damage = 0.0
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000.0
	wave.element = PBElement.Type.PHYSICAL
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, team)
	var enemy := sim.enemies()[0]
	enemy.distance = 0.18
	enemy.shot_speed = 0.1
	enemy.speed = 0.0
	enemy.damage_per_shot = 0.0
	assert_true(sim.cast_skill_now(caster, 2))
	for tick: int in 15:
		sim.step()
	assert_eq(_phantoms(team).size(), 1)
	assert_lt(enemy.hp, enemy.max_hp)
	assert_eq(caster.hp, caster.max_hp)
	for tick: int in 60:
		sim.step()
	assert_true(_phantoms(team).is_empty())
	assert_eq(sim.result().allies_lost, 0)


func test_configuration_and_bond_tooltips_report_real_values() -> void:
	var skill := _cfg.skills.by_id(&"sun_halo_dance").clone()
	assert_eq(PBSkillLoader.check(skill), "")
	var words: String = PBEffectWords.skill_body(_team(1, true)[0].skills[1].skill, _cfg)
	assert_true(words.contains("2 个无敌幻影"))
	assert_true(words.contains("55%"))
	assert_true(words.contains("4.5 秒"))
	skill.summon_seconds = 0.0
	assert_ne(PBSkillLoader.check(skill), "")

	skill.summon_seconds = 3.0
	skill.summon_count = 1
	assert_ne(PBSkillLoader.check(skill), "")


func test_phantom_normal_hits_keep_seven_elements_and_armor_and_log_owner() -> void:
	for element: int in PBElement.Type.values():
		var team := _team()
		var sequence := _sequence(team)
		var enemy := _enemy()
		enemy.element = element as PBElement.Type
		enemy.armor = 20.0
		enemy.ninjutsu_resist = 0.95
		sequence.advance([enemy], 0, _cfg, 2, null, null)
		var one := _phantoms(team)[0]
		var book := PBBattleLog.new()
		PBStrikeRules.land(
			one, enemy, one.strike_for(3), false, [enemy], _cfg, 3, book, PBCombatOutcome.new()
		)
		var expected: float = sequence.inherited_attack * 0.35
		expected *= _cfg.damage_multiplier(
			PBElement.relation(PBElement.Type.THUNDER, enemy.element)
		)
		expected /= 1.0 + 20.0 * _cfg.armor_scale
		assert_almost_eq(enemy.max_hp - enemy.hp, expected, 0.001)
		assert_eq(book.entries[0]["source"], one.slot)
		assert_eq(book.entries[0]["owner"], team[0].slot)
		var panel := PBBattleLogPanel.new()
		var cards: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(&"shisui"))]
		assert_true(panel.line_of(book.entries[0], cards, null).contains("宇智波止水·幻影"))
		panel.free()
