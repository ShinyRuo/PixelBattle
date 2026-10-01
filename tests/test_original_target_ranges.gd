extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _skill(id: StringName, bond_id: StringName) -> PBSkill:
	var skill := _cfg.skills.by_id(id).clone()
	for bond: PBBond in _cfg.bonds.all():
		if bond.id != bond_id:
			continue
		for who: StringName in bond.member_skill_patches:
			if bond.member_skill_patches[who].has(id):
				PBSkillPatchRules.apply(skill, bond.member_skill_patches[who][id])
	return skill


func _allies() -> Array[PBAttacker]:
	var units: Array[PBAttacker] = []
	for x: float in [0.9, 0.1, 0.7, 0.701, 0.899]:
		var unit := PBAttacker.new()
		unit.hp = 1000.0
		unit.max_hp = 1000.0
		unit.pos = Vector2(x, 0.0)
		unit.slot = units.size()
		unit.attribute_profile = PBAttributeProfile.new()
		units.append(unit)
	return units


func test_inspire_uses_caster_circle_and_includes_boundary_not_primary_neighbors() -> void:
	var cast := PBSkillCast.new(_skill(&"inspire", &"three_of_them"))
	cast.origin = Vector2(0.2, 0.0)
	cast.target_slot = 0
	assert_eq(PBSkillTargets.allies(cast, _allies()), PackedInt32Array([0, 1, 2]))
	assert_eq(cast.skill.on_hit[0].duration_seconds, 15.0)
	assert_eq(_cfg.skills.by_id(&"inspire").max_targets, 0)


func test_mirror_larger_circle_and_missing_origin_do_not_become_global_search() -> void:
	var cast := PBSkillCast.new(_skill(&"mirror_ward", &"crimson_dusk"))
	cast.target_slot = 0
	assert_eq(PBSkillTargets.allies(cast, _allies()), PackedInt32Array([0]))
	cast.origin = Vector2(0.2, 0.0)
	assert_eq(PBSkillTargets.allies(cast, _allies()), PackedInt32Array([0, 1, 2, 3]))
	var units := _allies()
	units[0].alive = false
	assert_true(PBSkillTargets.allies(cast, units).is_empty())


func test_enemy_circle_centers_differ_between_haze_and_mind_transfer() -> void:
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	var enemies: Array[PBEnemy] = []
	for x: float in [0.9, 0.1, 0.7, 0.901]:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, x, 0)
		enemy.slot = enemies.size()
		enemies.append(enemy)
	var cast := PBSkillCast.new(_skill(&"haze_illusion", &"team_eight"))
	cast.origin = Vector2(0.2, 0.0)
	cast.target_slot = 0
	assert_eq(PBSkillTargets.enemies(cast, enemies, 0), PackedInt32Array([0, 1, 2]))
	cast.skill = _skill(&"mind_transfer", &"ino_shika_cho")
	assert_eq(PBSkillTargets.enemies(cast, enemies, 0), PackedInt32Array([0, 3]))
	assert_eq(cast.skill.extra_target_radius, 0.35)
	assert_eq(_skill(&"tsukuyomi", &"vermilion_pair").extra_target_radius, 0.3)


func test_transfer_extra_friend_uses_same_caster_center_and_tooltip_names_center() -> void:
	var cast := PBSkillCast.new(_skill(&"reincarnation", &"puppet_masters"))
	cast.origin = Vector2(0.2, 0.0)
	cast.target_slot = 0
	assert_eq(PBSkillTargets.allies(cast, _allies()), PackedInt32Array([0, 1]))
	var words := PBEffectWords.skill_body(cast.skill, _cfg)
	assert_true(words.contains("施法者周围 0.50"))
	words = PBEffectWords.skill_body(_skill(&"mind_transfer", &"ino_shika_cho"), _cfg)
	assert_true(words.contains("主目标周围 0.35"))
