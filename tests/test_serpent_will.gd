extends GutTest

var _cfg: PBSimConfig
var _team: Array[PBAttacker]
var _enemy: PBEnemy


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.spawn_window = 0
	_cfg.unit_min_gap = 0
	_cfg.aim_policy = PBAimRules.Policy.NONE
	var cards: Array[PBUnit] = []
	for id: StringName in [&"orochimaru", &"kabuto", &"rock_lee"]:
		var card := PBUnit.new(_cfg.characters.by_id(id))
		card.level = 3 if id == &"rock_lee" else 5
		cards.append(card)
	var patches := PBBondRules.active_skill_patches(cards, cards, _cfg.bonds)
	_team = PBCombatRules.build_attackers(
		cards, PBElement.Type.PHYSICAL, 1, PackedFloat64Array(), _cfg, null, 1, 0, {}, {}, patches
	)
	for unit: PBAttacker in _team:
		unit.prime(_cfg.tick_rate, _cfg)
		unit.revive()
		unit.pos = Vector2(0.3, 0.3)
		unit.defence = 0
		unit.def_element = PBElement.Type.PHYSICAL
		unit.dodge = 0
	var wave := PBWave.new()
	wave.hp_each = 10000
	_enemy = PBEnemy.new()
	_enemy.spawn(wave, 0, 0.4, 0, 0.3)


func _hit(target: PBAttacker, raw: float = 10, tick: int = 1) -> void:
	PBStrikeRules.hurt_ally(
		target,
		_enemy,
		raw,
		PBElement.Type.PHYSICAL,
		_cfg,
		tick,
		null,
		null,
		PBCombatOutcome.new(),
		PBEnemyHitContext.new(_team)
	)


func test_threshold_is_inclusive_and_heals_receiver_level_over_twelve_seconds() -> void:
	var target := _team[2]
	target.hp = target.max_hp * 0.5 + 10
	_hit(target)
	assert_true(target.rescue_used)
	var start := target.hp
	assert_almost_eq(start, target.max_hp * 0.5, 0.000001)
	PBBuffRules.advance_ally(target, 20, _cfg.tick_rate)
	assert_eq(target.hp, start, "不能瞬间恢复")
	for tick: int in range(21, 242):
		PBBuffRules.advance_ally(target, tick, _cfg.tick_rate)
	assert_almost_eq(target.hp - start, 650.0 * 3, 0.001, "按受益者三级而非来源五级")
	assert_eq(target.buffs.count(242), 0)


func test_small_or_absorbed_hits_and_above_threshold_do_not_consume_once() -> void:
	var target := _team[2]
	target.hp = target.max_hp * 0.5 + 11
	_hit(target)
	assert_false(target.rescue_used)
	target.hp = target.max_hp * 0.4
	_hit(target, 5)
	assert_false(target.rescue_used)
	var shield := PBBuff.new()
	shield.id = &"rescue_test_shield"
	shield.kind = PBBuff.Kind.DURATION
	target.buffs.add(shield, {PBBuffRules.SHIELD: 100.0}, 0, 100, 0)
	_hit(target, 10)
	assert_false(target.rescue_used)
	target.buffs.clear()
	_enemy.max_hp = 399
	_hit(target)
	assert_false(target.rescue_used)
	_enemy.max_hp = 400
	_hit(target)
	assert_true(target.rescue_used)


func test_range_source_liveness_and_real_ninja_only() -> void:
	var target := _team[2]
	target.hp = target.max_hp * 0.4
	target.pos = Vector2(1.301, 0.3)
	_hit(target)
	assert_false(target.rescue_used)
	target.pos = Vector2(0.3, 0.3)
	_team[1].alive = false
	_hit(target)
	assert_false(target.rescue_used)
	_team[1].alive = true
	target.summoned = true
	_hit(target)
	assert_false(target.rescue_used)
	target.summoned = false
	target.phantom = true
	_hit(target)
	assert_false(target.rescue_used)
	target.phantom = false
	_hit(target)
	assert_true(target.rescue_used)


func test_once_shared_between_sources_remove_and_eviction_do_not_rearm() -> void:
	var target := _team[2]
	target.hp = target.max_hp * 0.4
	_team.append(_team[1].clone())
	_hit(target)
	assert_eq(target.buffs.count(1), 1)
	target.buffs.remove(&"serpent_regen", 2)
	_hit(target, 10, 3)
	assert_eq(target.buffs.count(3), 0)
	target.revive()
	target.hp = target.max_hp * 0.4
	_hit(target, 10, 4)
	assert_eq(target.buffs.count(4), 1)
	for i: int in 32:
		var buff := PBBuff.new()
		buff.id = StringName("rescue_filler_%d" % i)
		buff.kind = PBBuff.Kind.DURATION
		target.buffs.add(buff, {}, 5, 1000, 0)
	var hp := target.hp
	PBBuffRules.advance_ally(target, 24, _cfg.tick_rate)
	assert_eq(target.hp, hp)
	_hit(target, 10, 25)
	assert_true(target.rescue_used)
	assert_eq(target.buffs.amount(PBBuffRules.HEAL, 25), 0.0)


func test_granted_regen_survives_source_death_and_does_not_rescue_lethal_hit() -> void:
	var target := _team[2]
	target.hp = target.max_hp * 0.4
	_hit(target)
	var hp := target.hp
	_team[1].alive = false
	target.pos = Vector2(3, 3)
	PBBuffRules.advance_ally(target, 21, _cfg.tick_rate)
	assert_gt(target.hp, hp)
	target.revive()
	_team[1].alive = true
	target.hp = 1
	_hit(target)
	assert_false(target.alive)
	assert_false(target.rescue_used)


func test_basic_regeneration_total_and_no_bond_no_rescue() -> void:
	var target := _team[2]
	var skill := _team[1].skills[0]
	assert_eq(skill.skill.id, &"mending_jutsu")
	assert_eq(skill.skill.rescue_radius, 1.0)
	assert_eq(_cfg.skills.by_id(&"mending_jutsu").rescue_radius, 0.0)
	var buff := skill.skill.on_hit[0]
	var total := float(PBBuffRules.resolve(buff, 5)[PBBuffRules.HEAL]) * 12
	assert_eq(total, 1500.0 * 5)
	skill.skill.rescue_radius = 0
	target.hp = target.max_hp * 0.4
	_hit(target)
	assert_false(target.rescue_used)


func test_ranged_enemy_triggers_only_when_projectile_really_lands() -> void:
	var wave := PBWave.new()
	wave.count = 1
	wave.hp_each = 100000
	var sim := PBBattleSim.new(wave, 0, 0, _cfg, _team)
	for i: int in _team.size():
		_team[i].pos = Vector2(0.1 + i * 0.15, 0.3)
		_team[i].attack = 0
		_team[i].dps = 0
		_team[i].move_speed = 0
	var target := _team[2]
	target.hp = target.max_hp * 0.5 + 10
	var foe := sim.enemies()[0]
	foe.distance = 0.42
	foe.lane = 0.3
	foe.speed = 0
	foe.reach = 0.2
	foe.shot_speed = 0.002
	foe.damage_per_shot = 10
	foe.element = PBElement.Type.PHYSICAL
	foe.windup_ticks = 1
	foe.next_shot_at = 0
	sim.step()
	sim.step()
	assert_false(target.rescue_used)
	foe.next_shot_at = 10000
	for tick: int in 15:
		sim.step()
	assert_true(target.rescue_used)
	assert_eq(target.buffs.count(sim.current_tick()), 1)


func test_rescue_configuration_rejects_nonperiodic_or_missing_effects() -> void:
	var skill := _cfg.skills.by_id(&"mending_jutsu").clone()
	assert_eq(PBRescueRules.validate(skill), "")
	skill.rescue_radius = 1
	skill.on_rescue.clear()
	assert_ne(PBRescueRules.validate(skill), "")
	var bad := PBBuff.new()
	bad.kind = PBBuff.Kind.INSTANT
	bad.friendly = true
	bad.mods = {PBBuffRules.HEAL: 10.0}
	skill.on_rescue = [bad]
	assert_ne(PBRescueRules.validate(skill), "")
