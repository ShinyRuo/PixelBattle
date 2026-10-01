extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _unit() -> PBAttacker:
	var unit := PBAttacker.new()
	unit.max_hp = 10000.0
	unit.hp = unit.max_hp
	unit.base_attack = 100.0
	unit.attack = 450.0
	unit.damage_attributes = {&"attack": 300.0, &"intellect": 50.0}
	unit.attack_speed = 1.0
	unit.prime(20)
	return unit


func _apply(unit: PBAttacker, level: int = 1, tick: int = 0) -> void:
	PBSkillRules.apply_hit_ally(unit, _cfg.skills.by_id(&"inspire"), level, _cfg, tick)


func test_ten_levels_increase_only_base_attack_and_add_defence() -> void:
	for level: int in range(1, 11):
		var unit := _unit()
		_apply(unit, level)
		var bonus: float = 0.1 + 0.03 * level
		assert_almost_eq(unit.strike_for(1), 450.0 + 150.0 * bonus, 0.001)
		assert_almost_eq(unit.buffs.amount(PBBuffRules.DEFENCE, 1), 3.0 * level, 0.001)
		assert_eq(unit.damage_attributes[&"attack"], 300.0)
		assert_eq(unit.buffs.amount(PBBuffRules.DAMAGE_SCALE, 1), 1.0)


func test_refresh_does_not_stack_and_every_attack_path_expires_at_same_tick() -> void:
	var unit := _unit()
	_apply(unit)
	_apply(unit, 10, 20)
	assert_eq(unit.buffs.count(20), 1)
	var skill := PBSkill.new()
	skill.damage = 600.0
	skill.attack_formula_scale = 2.0
	assert_almost_eq(unit.strike_for(320), 510.0, 0.001)
	assert_almost_eq(PBAllyAuraRules.skill_damage(unit, skill, 0.0, 320), 680.0, 0.001)
	assert_almost_eq(
		PBHarmContext.from_caster(unit, skill, 320).attributes[&"attack"], 340.0, 0.001
	)
	assert_eq(unit.strike_for(321), 450.0)
	assert_eq(PBAllyAuraRules.skill_damage(unit, skill, 0.0, 321), 600.0)
	assert_eq(PBHarmContext.from_caster(unit, skill, 321).attributes[&"attack"], 300.0)


func test_melee_receives_buff_but_intellect_attacks_and_spells_do_not() -> void:
	var unit := _unit()
	unit.ranged_attack = false
	_apply(unit)
	assert_almost_eq(unit.strike_for(1), 469.5, 0.001)
	unit.attack_ninjutsu = 1.0
	unit.ninjutsu_attack = 70.0
	assert_eq(unit.strike_for(1), 70.0)
	var skill := PBSkill.new()
	skill.damage = 200.0
	assert_eq(PBAllyAuraRules.skill_damage(unit, skill, 0.0, 1), 200.0)
	assert_eq(PBHarmContext.from_caster(unit, skill, 1).attributes[&"intellect"], 50.0)


func test_aura_and_inspire_add_their_base_attack_rates() -> void:
	var unit := _unit()
	unit.ranged_attack = true
	var provider := _unit()
	provider.skills.append(PBSkillCast.new(_cfg.skills.by_id(&"gale_dance"), 1))
	PBAllyAuraRules.install([provider, unit])
	_apply(unit)
	assert_almost_eq(unit.strike_for(1), 489.0, 0.001)
	provider.alive = false
	assert_almost_eq(unit.strike_for(2), 469.5, 0.001)


func test_bond_applies_to_five_friends_and_leaves_sixth_unchanged() -> void:
	var skill := _cfg.skills.by_id(&"inspire").clone()
	for bond: PBBond in _cfg.bonds.all():
		if bond.id == &"three_of_them":
			PBSkillPatchRules.apply(skill, bond.member_skill_patches[&"rin_nohara"][skill.id])
	var units: Array[PBAttacker] = []
	for i: int in 6:
		var unit := _unit()
		unit.slot = i
		unit.pos = Vector2(i * 0.01, 0.0)
		units.append(unit)
	var cast := PBSkillCast.new(skill, 1)
	cast.target_slot = 0
	cast.origin = Vector2.ZERO
	PBSkillRules.land_on_ally(cast, units, _cfg, 0)
	for i: int in 5:
		assert_almost_eq(units[i].strike_for(1), 469.5, 0.001)
	assert_eq(units[5].strike_for(1), 450.0)


func test_defence_reduces_taijutsu_but_not_ninjutsu() -> void:
	for kind: PBDamageKind.Type in PBDamageKind.Type.values():
		var plain := _unit()
		var boosted := _unit()
		_apply(boosted, 10)
		for unit: PBAttacker in [plain, boosted]:
			PBStrikeRules.hurt_ally(
				unit,
				null,
				100.0,
				PBElement.Type.PHYSICAL,
				_cfg,
				1,
				null,
				null,
				PBCombatOutcome.new(),
				PBEnemyHitContext.new([], false, kind)
			)
		if kind == PBDamageKind.Type.TAIJUTSU:
			assert_gt(boosted.hp, plain.hp)
		else:
			assert_eq(boosted.hp, plain.hp)


func test_validation_tooltip_and_transfer_resource_are_independent() -> void:
	var skill := _cfg.skills.by_id(&"inspire")
	var words := PBEffectWords.skill_body(skill, _cfg, 10)
	assert_true(words.contains("基础攻击 +40%"))
	assert_true(words.contains("30"))
	var buff: PBBuff = skill.on_hit[0].duplicate(true)
	buff.friendly = false
	assert_ne(PBBuffRules.validate(buff), "")
	assert_true(_cfg.skills.by_id(&"reincarnation").on_hit.is_empty())
