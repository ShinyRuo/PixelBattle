extends GutTest


func test_shark_variant_uses_dedicated_four_state_skin() -> void:
	var cfg := PBGameData.config()
	var skin := PBActorLibrary.skin_for(&"form_shark")
	assert_not_null(skin)
	if skin == null:
		return
	for anim: StringName in [&"idle", &"run", &"attack", &"dead"]:
		assert_eq(skin.frames.get_frame_count(anim), 6, String(anim))
	var attacker := PBAttacker.new()
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	assert_eq(pool._form_actor_key(attacker, 0), &"")
	var original := cfg.skills.by_id(&"shark_cut")
	var normal := PBSkillVariantRules.prepare(original, {}, cfg)
	attacker.skills.append(PBSkillCast.new(normal, 1))
	assert_eq(pool._form_actor_key(attacker, 0), &"")
	attacker.skills.clear()
	var variant := PBSkillVariantRules.prepare(
		original, {PBSkillPatchRules.VARIANT_ENABLE: 1.0}, cfg
	)
	assert_eq(variant.variant_art_id, &"shark_form")
	attacker.skills.append(PBSkillCast.new(variant, 1))
	assert_eq(pool._form_actor_key(attacker, 0), &"form_shark")
