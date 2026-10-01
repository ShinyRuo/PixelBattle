extends GutTest


func test_cloak_follows_only_living_skill_source_not_healing_recipients() -> void:
	var cfg := PBGameData.config()
	var cards: Array[PBUnit] = [
		PBUnit.new(cfg.characters.by_id(&"naruto")),
		PBUnit.new(cfg.characters.by_id(&"sakura")),
	]
	var team := PBCombatRules.build_attackers(
		cards, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), cfg
	)
	for attacker: PBAttacker in team:
		attacker.pos = Vector2.ZERO
		attacker.revive()
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	assert_not_null(PBBuffGlow.skin_for(&"kurama_cloak_source"))
	assert_has(pool._aura_ids(team[0], team), &"kurama_cloak_source")
	assert_does_not_have(pool._aura_ids(team[1], team), &"kurama_cloak_source")
	team[0].alive = false
	assert_does_not_have(pool._aura_ids(team[0], team), &"kurama_cloak_source")
	assert_does_not_have(pool._aura_ids(team[1], team), &"kurama_cloak_source")
