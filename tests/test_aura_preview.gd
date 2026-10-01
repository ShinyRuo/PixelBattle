extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _card(ids: Array[StringName]) -> PBCommandCard:
	var state := PBRunState.new()
	var units: Array[PBUnit] = []
	for id: StringName in ids:
		var unit := PBUnit.new(_cfg.characters.by_id(id))
		state.add_unit(unit)
		units.append(unit)
	var card := PBCommandCard.new()
	add_child_autofree(card)
	card.refresh(PBSelection.of_unit(units[0].key()), state, _cfg, PBWavePlan.new(), units)
	return card


func _skill(card: PBCommandCard, id: StringName) -> PBSkill:
	for skill: PBSkill in card.skill_definitions():
		if skill != null and skill.id == id:
			return skill
	return null


func test_preparation_aura_uses_active_bond_and_keeps_source_immutable() -> void:
	var card := _card([&"kurotsuchi", &"onoki"])
	assert_eq(_skill(card, &"light_rock").radius, 0.3)
	assert_eq(_cfg.skills.by_id(&"light_rock").radius, 0.0)
	var solo := _card([&"kurotsuchi"])
	assert_eq(_skill(solo, &"light_rock").radius, 0.0)
	card.refresh(card._selection, card._state, _cfg, PBWavePlan.new(), [])
	assert_eq(_skill(card, &"light_rock").radius, 0.0)


func test_preparation_followup_and_duration_match_battle_patch() -> void:
	var card := _card([&"tobirama", &"hashirama"])
	var skill := _skill(card, &"water_wall")
	assert_eq(skill.on_self[0].seconds_at(), 4.5)
	assert_true(skill.followup_enabled)
	assert_not_null(skill.followup)
	assert_eq(skill.followup.id, &"water_surge")
	assert_eq(skill.followup.kind, skill.kind)
	assert_eq(_cfg.skills.by_id(&"water_wall").on_self[0].seconds_at(), 3.0)
	assert_null(_cfg.skills.by_id(&"water_wall").followup)


func test_preview_ring_uses_aura_only_and_self_only_has_no_area() -> void:
	var ring := PBAuraRing.new()
	add_child_autofree(ring)
	var field := Vector2(1.0, 0.3)
	var card := _card([&"kurotsuchi", &"onoki"])
	ring.sync_preview(Vector2(0.2, 0.1), card.skill_definitions(), field)
	assert_eq(ring.radius_px, 0.3 * PBLayout.px_per_unit(field))
	assert_eq(ring.center, PBLayout.to_screen(Vector2(0.2, 0.1), field))
	ring.sync_preview(Vector2.ZERO, [_cfg.skills.by_id(&"dust_release")], field)
	assert_eq(ring.radius_px, 0.0)
	ring.sync_preview(Vector2.ZERO, [_cfg.skills.by_id(&"light_rock")], field)
	assert_eq(ring.radius_px, 0.0)


func test_live_ring_tracks_carrier_and_clears_after_death() -> void:
	var ring := PBAuraRing.new()
	add_child_autofree(ring)
	var field := Vector2(1.0, 0.3)
	var one := PBAttacker.new()
	one.alive = true
	one.max_hp = 100.0
	var skill := _cfg.skills.by_id(&"light_rock").clone()
	skill.radius = 0.3
	var cast := PBSkillCast.new(skill)
	one.skills.append(cast)
	ring.sync_live(one, field)
	assert_gt(ring.radius_px, 0.0)
	one.pos = Vector2(0.4, 0.2)
	ring.sync_live(one, field)
	assert_eq(ring.center, PBLayout.to_screen(one.pos, field))
	one.alive = false
	ring.sync_live(one, field)
	assert_eq(ring.radius_px, 0.0)


func test_aura_art_uses_live_beneficiaries_and_retracts_on_range_or_source_loss() -> void:
	var cards: Array[PBUnit] = []
	for id: StringName in [&"kushina", &"sakura"]:
		cards.append(PBUnit.new(_cfg.characters.by_id(id)))
	var team := PBCombatRules.build_attackers(
		cards, PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg
	)
	for unit: PBAttacker in team:
		unit.revive()
	team[0].pos = Vector2(0.2, 0.5)
	team[1].pos = Vector2(0.3, 0.5)
	var pool := PBAllyPool.new()
	add_child_autofree(pool)
	assert_has(pool._aura_ids(team[1], team), &"battle_chakra_aura")
	team[1].pos = Vector2(0.8, 0.5)
	assert_does_not_have(pool._aura_ids(team[1], team), &"battle_chakra_aura")
	team[1].pos = Vector2(0.3, 0.5)
	team[0].alive = false
	assert_does_not_have(pool._aura_ids(team[1], team), &"battle_chakra_aura")


func test_ring_respects_arena_clipping() -> void:
	var clip := Control.new()
	clip.clip_contents = true
	add_child_autofree(clip)
	var ring := PBAuraRing.new()
	clip.add_child(ring)
	assert_eq(clip.position, PBLayout.B_FIELD.position)
	assert_eq(clip.size, PBLayout.B_FIELD.size)
	assert_eq(ring.position, -clip.position)


func test_dispatch_preview_removes_carried_enemy_aura_and_bond_status_immediately() -> void:
	var card := _card([&"kisame", &"itachi"])
	assert_eq(_skill(card, &"shark_cut").enemy_aura_radius, 0.3)
	var state: PBRunState = card._state
	var team := state.field_units(_cfg)
	state.dispatch_manual.append(team[1].key())
	assert_eq(state.dispatched, 0, "准备名单尚未锁定，不改实战派遣计数")
	card.refresh(card._selection, state, _cfg, PBWavePlan.new(), [team[0]])
	assert_eq(_skill(card, &"shark_cut").enemy_aura_radius, 0.0)
	var info := PBUnitInfo.new()
	add_child_autofree(info)
	info.refresh(card._selection, state, _cfg, PBWave.new(), [team[0]])
	assert_string_contains(info._bond_head(_cfg.bonds.by_id(&"vermilion_pair")), "1/2")
	assert_eq(state.dispatched, 0)
