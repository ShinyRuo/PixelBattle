extends GutTest


func test_summon_lifesteal_link_follows_hit_log_and_expires() -> void:
	var skin := PBFieldArt.read("links", &"vampire_bugs")
	assert_not_null(skin)
	assert_eq(skin.frames.size(), 6)
	assert_eq(skin.fps, 12.0)
	assert_eq(skin.link_width, 56.0)
	for frame: Texture2D in skin.frames:
		assert_eq(frame.get_size(), Vector2(256, 256))
	var choices := PBFieldArtBindings.new().choices()
	assert_true(choices.any(func(row: Dictionary) -> bool:
		return row.kind == "links" and row.id == "vampire_bugs"))
	var bug := PBAttacker.new()
	bug.slot = 1
	bug.alive = true
	bug.summoned = true
	bug.summon_skill_id = &"vampire_bugs"
	bug.lifesteal = 0.2
	bug.pos = Vector2(0.4, 0.5)
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.7, 0.5, 0)
	enemy.slot = 0
	var team: Array[PBAttacker] = [bug]
	var foes: Array[PBEnemy] = [enemy]
	var book := PBBattleLog.new()
	var fx := PBFieldEffects.new()
	book.hit(3, bug.slot, enemy.slot, 40.0, false, false, -1, &"", 8.0)
	fx.sync_effects(team, foes, 3, 20, Vector2.ONE, [], book)
	assert_eq(fx._leech_links.size(), 1)
	fx.sync_effects(team, foes, 14, 20, Vector2.ONE, [], book)
	assert_eq(fx._leech_links.size(), 0)
	book.hit(15, bug.slot, enemy.slot, 40.0, false)
	fx.sync_effects(team, foes, 15, 20, Vector2.ONE, [], book)
	assert_eq(fx._leech_links.size(), 0)
	bug.lifesteal = 0.0
	book.hit(16, bug.slot, enemy.slot, 40.0, false)
	fx.sync_effects(team, foes, 16, 20, Vector2.ONE, [], book)
	assert_eq(fx._leech_links.size(), 0)
	fx.free()


func test_real_strike_records_only_actual_lifesteal_healing() -> void:
	var cfg := PBGameData.config()
	var bug := PBAttacker.new()
	bug.slot = 1
	bug.alive = true
	bug.max_hp = 100.0
	bug.hp = 50.0
	bug.lifesteal = 0.2
	var wave := PBWave.new()
	wave.hp_each = 1000.0
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.7, 0.5, 0)
	enemy.slot = 0
	var foes: Array[PBEnemy] = [enemy]
	var book := PBBattleLog.new()
	var before := bug.hp
	PBStrikeRules.land(bug, enemy, 80.0, false, foes, cfg, 1, book, PBCombatOutcome.new())
	assert_gt(bug.hp, before)
	assert_almost_eq(float(book.entries[0].get("leech", 0.0)), bug.hp - before, 0.001)
	bug.hp = bug.max_hp
	PBStrikeRules.land(bug, enemy, 80.0, false, foes, cfg, 2, book, PBCombatOutcome.new())
	assert_false(book.entries[1].has("leech"))
