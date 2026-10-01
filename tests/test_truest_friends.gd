extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _caster(enabled: bool, equipment: Dictionary = {}) -> PBAttacker:
	var units: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(&"itachi"))]
	if enabled:
		units.append(PBUnit.new(_cfg.characters.by_id(&"shisui")))
	var passives: Dictionary = PBBondRules.active_passives(units, units, _cfg.bonds)
	return (
		PBCombatRules
		. build_attackers(
			units,
			PBElement.Type.PHYSICAL,
			1.0,
			PackedFloat64Array(),
			_cfg,
			null,
			1,
			0,
			{},
			passives,
			{},
			[equipment]
		)[0]
	)


func test_full_bond_raises_only_ninjutsu_crit_from_fifteen_to_twenty_two() -> void:
	var plain := _caster(false)
	var boosted := _caster(true)
	assert_almost_eq(PBCritRules.chance_of(plain, 0, PBDamageKind.Type.NINJUTSU), 0.15, 0.0001)
	assert_almost_eq(PBCritRules.chance_of(boosted, 0, PBDamageKind.Type.NINJUTSU), 0.22, 0.0001)
	assert_eq(PBCritRules.chance_of(boosted, 0), PBCritRules.chance_of(plain, 0))
	assert_eq(PBCritRules.attack_kind(boosted), PBDamageKind.Type.NINJUTSU)


func test_bonus_reaches_ninjutsu_normal_attacks_and_skills_but_not_taijutsu() -> void:
	var plain := _caster(false)
	var boosted := _caster(true)
	var base: Dictionary = PBCritRules.strike(plain, 0)
	var more: Dictionary = PBCritRules.strike(boosted, 0)
	assert_almost_eq(float(more[PBCritRules.DAMAGE]), float(base[PBCritRules.DAMAGE]) * 1.12, 0.001)
	var nin: Dictionary = PBCritRules.hit(boosted, 100.0, PBDamageKind.Type.NINJUTSU, 0)
	var tai: Dictionary = PBCritRules.hit(boosted, 100.0, PBDamageKind.Type.TAIJUTSU, 0)
	assert_almost_eq(float(nin[PBCritRules.DAMAGE]), 112.0, 0.001)
	assert_almost_eq(float(tai[PBCritRules.DAMAGE]), 100.0, 0.001)


func test_equipment_still_adds_crit_and_bond_description_uses_ninjutsu_words() -> void:
	var boosted := _caster(true, {PBPassiveRules.NINJUTSU_CRIT_CHANCE: 0.1})
	assert_almost_eq(boosted.ninjutsu_crit_chance, 0.32, 0.0001)
	var units: Array[PBUnit] = [
		PBUnit.new(_cfg.characters.by_id(&"itachi")),
		PBUnit.new(_cfg.characters.by_id(&"shisui")),
	]
	var passives: Dictionary = PBBondRules.active_passives(units, units, _cfg.bonds)
	var description: String = "、".join(PBShopLabels.mod_words(passives[&"itachi"]))
	assert_string_contains(description, "忍术暴击率 +7%")
	assert_string_contains(description, "忍术伤害 +12%")
