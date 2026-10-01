extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _unit(hp: float = 10000.0) -> PBAttacker:
	var unit := PBAttacker.new()
	unit.max_hp = hp
	unit.hp = hp
	return unit


func _skill(boosted: bool = false) -> PBSkill:
	var skill := _cfg.skills.by_id(&"mirror_ward").clone()
	if boosted:
		for bond: PBBond in _cfg.bonds.all():
			if bond.id == &"crimson_dusk":
				PBSkillPatchRules.apply(skill, bond.member_skill_patches[&"kurenai"][skill.id])
	return skill


func test_all_levels_absorb_only_ninjutsu_independently_of_seven_elements() -> void:
	for level: int in range(1, 11):
		for element: PBElement.Type in PBElement.Type.values():
			for kind: PBDamageKind.Type in PBDamageKind.Type.values():
				var unit := _unit()
				PBSkillRules.apply_hit_ally(unit, _skill(), level, _cfg, 0)
				var hurt: float = (
					100.0 * _cfg.damage_multiplier(PBElement.relation(element, unit.def_element))
				)
				var context := PBEnemyHitContext.new([], false, kind)
				PBStrikeRules.hurt_ally(
					unit, null, 100.0, element, _cfg, 1, null, null, PBCombatOutcome.new(), context
				)
				var absorbed: float = hurt if kind == PBDamageKind.Type.NINJUTSU else 0.0
				assert_almost_eq(unit.hp, unit.max_hp - hurt + absorbed, 0.001)
				assert_almost_eq(
					unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 1),
					800.0 * level - absorbed,
					0.001
				)


func test_bond_five_targets_each_use_their_own_max_hp_and_shared_resource_stays_clean() -> void:
	var units: Array[PBAttacker] = []
	for i: int in 6:
		var unit := _unit(10000.0 + i * 1000.0)
		unit.slot = i
		unit.pos = Vector2(0.01 * i, 0.0)
		units.append(unit)
	var cast := PBSkillCast.new(_skill(true), 3)
	cast.target_slot = 0
	cast.origin = Vector2.ZERO
	PBSkillRules.land_on_ally(cast, units, _cfg, 10)
	for i: int in 5:
		assert_almost_eq(
			units[i].buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 10),
			2400.0 + units[i].max_hp * 0.1,
			0.001
		)
	assert_eq(units[5].buffs.count(10), 0)
	assert_false(
		_cfg.skills.by_id(&"mirror_ward").on_hit[0].mods.has(PBBuffRules.NINJUTSU_SHIELD_MAX)
	)


func test_projectile_and_active_enemy_ability_preserve_ninjutsu_kind_to_shield() -> void:
	var unit := _unit()
	PBSkillRules.apply_hit_ally(unit, _skill(), 1, _cfg, 0)
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 1.0, true)
	shot.enemy_hit = PBEnemyHitContext.new([unit], false, PBDamageKind.Type.NINJUTSU)
	PBShotRules.advance([shot], [], [unit], _cfg, 1, null, PBCombatOutcome.new())
	assert_eq(unit.hp, unit.max_hp)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 1), 700.0)
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.0, 0.0, 0)
	var ability := PBEnemyAbility.new()
	ability.id = &"shield_probe"
	ability.damage_base = 100.0
	ability.intellect_scale = 0.0
	enemy.abilities = [ability]
	enemy.ability_ready_at = PackedInt32Array([0])
	PBEnemyAbilityRules.advance(enemy, [unit], _cfg, 2, null, null, PBCombatOutcome.new())
	assert_eq(unit.hp, unit.max_hp)
	assert_lt(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 2), 700.0)


func test_general_shield_still_absorbs_taijutsu_and_overflow_is_paid_once() -> void:
	var unit := _unit()
	PBSkillRules.apply_hit_ally(unit, _skill(), 1, _cfg, 0)
	var buff := PBBuff.new()
	buff.id = &"general_guard"
	unit.buffs.add(buff, {PBBuffRules.SHIELD: 300.0}, 0, 200, 0)
	unit.take_damage(500.0, 1)
	assert_eq(unit.hp, 9800.0)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 1), 800.0)
	unit.take_damage(1000.0, 2, null, PBDamageKind.Type.NINJUTSU)
	assert_eq(unit.hp, 9600.0)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 2), 0.0)


func test_snapshot_refresh_expiry_and_dodge_do_not_duplicate_or_consume_shield() -> void:
	var unit := _unit()
	var skill := _skill(true)
	PBSkillRules.apply_hit_ally(unit, skill, 1, _cfg, 0)
	unit.max_hp = 20000.0
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 1), 1800.0)
	unit.dodge = 1.0
	unit.take_damage(1000.0, 1, RandomNumberGenerator.new(), PBDamageKind.Type.NINJUTSU)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 1), 1800.0)
	PBSkillRules.apply_hit_ally(unit, skill, 1, _cfg, 10)
	assert_eq(unit.buffs.count(10), 1)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 190), 2800.0)
	assert_eq(unit.buffs.amount(PBBuffRules.NINJUTSU_SHIELD, 191), 0.0)


func test_invalid_hostile_shield_is_rejected_and_tooltip_describes_target_hp_bonus() -> void:
	var buff: PBBuff = _skill().on_hit[0].duplicate(true)
	buff.friendly = false
	assert_ne(PBBuffRules.validate(buff), "")
	var words := PBEffectWords.skill_body(_skill(true), _cfg, 2)
	assert_true(words.contains("忍术护盾 1600"))
	assert_true(words.contains("目标最大生命"))
