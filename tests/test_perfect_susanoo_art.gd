extends GutTest


func test_real_perfect_buff_swaps_form_and_expires_cleanly() -> void:
	var cfg := PBGameData.config()
	var card := PBUnit.new(cfg.characters.by_id(&"madara"))
	var team := PBCombatRules.build_attackers(
		[card], PBElement.Type.FIRE, 1.0, PackedFloat64Array(), cfg
	)
	var attacker: PBAttacker = team[0]
	attacker.revive()
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	var skin := PBActorLibrary.skin_for(&"form_susanoo_perfect")
	assert_not_null(skin)
	assert_eq(skin.frames.get_frame_count(&"idle"), 6)
	assert_eq(skin.frames.get_frame_count(&"run"), 6)
	assert_eq(skin.frames.get_frame_count(&"attack"), 6)
	assert_eq(skin.frames.get_frame_count(&"dead"), 6)
	assert_eq(pool._form_actor_key(attacker, 5), &"")
	var buff := cfg.skills.by_id(&"susanoo_perfect").on_self[0]
	attacker.buffs.add(buff, buff.mods, 5, 20, 0)
	assert_eq(pool._form_actor_key(attacker, 5), &"form_susanoo_perfect")
	var glow := PBBuffGlow.new()
	add_child_autofree(glow)
	glow.sync_bag(attacker.buffs, 5, cfg.tick_rate)
	assert_true(glow._drawings.is_empty(), "完整形态不再叠旧环身光")
	assert_eq(pool._form_actor_key(attacker, 25), &"form_susanoo_perfect")
	assert_eq(pool._form_actor_key(attacker, 26), &"")
