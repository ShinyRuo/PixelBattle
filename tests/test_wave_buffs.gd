extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _target() -> PBAttacker:
	var cards: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(&"rock_lee"))]
	return (
		PBCombatRules
		. build_attackers(cards, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), _cfg)[0]
	)


func test_gifts_keep_sources_and_revoke_all_derived_stats() -> void:
	var target := _target()
	var baseline := target.damage_attributes.duplicate()
	var skill := _cfg.skills.by_id(&"reincarnation")
	var first := {&"strength": 20.0, &"agility": 12.0, &"intellect": 15.0}
	var second := {&"strength": 30.0, &"agility": 18.0, &"intellect": 25.0}
	PBSacrificeRules.grant(target, skill, first, 0, _cfg, 4)
	PBSacrificeRules.grant(target, skill, second, 1, _cfg, 5)
	assert_eq(target.buffs.count(1000000), 2)
	for key: StringName in first:
		assert_eq(
			target.damage_attributes[key], baseline[key] + first.get(key, 0) + second.get(key, 0)
		)
	assert_eq(target.buffs.remove(skill.transfer_buff.id, 1000000, 0), 1)
	for key: StringName in second:
		assert_eq(target.damage_attributes[key], baseline[key] + second.get(key, 0))
	target.buffs.clear(1000001)
	assert_eq(target.damage_attributes, baseline)


func test_full_wave_bag_eviction_reverses_gift_and_same_source_refreshes() -> void:
	var target := _target()
	var baseline := target.damage_attributes.duplicate()
	var skill := _cfg.skills.by_id(&"reincarnation")
	PBSacrificeRules.grant(target, skill, {&"strength": 10.0}, 0, _cfg, 1)
	PBSacrificeRules.grant(target, skill, {&"strength": 20.0}, 0, _cfg, 2)
	assert_eq(target.buffs.count(2), 1)
	assert_eq(target.damage_attributes[&"strength"], baseline[&"strength"] + 20.0)
	for i: int in PBBuffBag.SLOTS:
		var buff := PBBuff.new()
		buff.id = StringName("wave_%d" % i)
		buff.until_wave_end = true
		target.buffs.add(buff, {}, i + 3, 0, 0)
	assert_eq(target.buffs.count(40), PBBuffBag.SLOTS)
	assert_eq(target.damage_attributes, baseline)


func test_opening_armor_preview_and_battle_are_one_bonus_without_shield() -> void:
	var cards: Array[PBUnit] = []
	for id: StringName in [&"hashirama", &"tobirama", &"hiruzen", &"minato", &"tsunade"]:
		cards.append(PBUnit.new(_cfg.characters.by_id(id)))
	var effects := PBBondBuffRules.collect(cards, cards, _cfg.bonds)
	var passives := PBBondRules.active_passives(cards, cards, _cfg.bonds, false)
	var team := PBCombatRules.build_attackers(
		cards, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), _cfg, null, 1, 0, passives
	)
	PBBondBuffRules.install(team, cards, effects)
	for actor: PBAttacker in team:
		var base := actor.defence
		actor.revive()
		assert_eq(actor.defence, base)
		assert_eq(actor.buffs.amount(PBBuffRules.DEFENCE, 999999), 30.0)
		assert_eq(actor.buffs.shield_left(0), 0.0)
		actor.buffs.remove(&"hokage_line_guard", 1)
		assert_eq(actor.buffs.amount(PBBuffRules.DEFENCE, 1), 0.0)
		actor.revive()
		assert_eq(actor.buffs.count(0), 1)
	var preview: Dictionary = {}
	PBBondBuffRules.preview(preview, effects)
	assert_eq(float(preview[&"hashirama"][PBBuffRules.DEFENCE]), 30.0)
	cards.pop_back()
	assert_true(PBBondBuffRules.collect(cards, cards, _cfg.bonds).is_empty())


func test_glow_follows_cancel_death_and_deduplicates_sources() -> void:
	var target := _target()
	var skill := _cfg.skills.by_id(&"reincarnation")
	PBSacrificeRules.grant(target, skill, {&"strength": 10.0}, 0, _cfg, 1)
	PBSacrificeRules.grant(target, skill, {&"strength": 20.0}, 1, _cfg, 1)
	var glow := PBBuffGlow.new()
	add_child_autofree(glow)
	glow.sync_bag(target.buffs, 10, 20)
	assert_true(glow.visible)
	assert_eq(glow._drawings.size(), 1)
	var frame: int = glow._drawings[0].frame
	glow.sync_bag(target.buffs, 10, 20)
	assert_eq(glow._drawings[0].frame, frame)
	glow.sync_bag(target.buffs, 11, 20, false)
	assert_false(glow.visible)
	target.buffs.remove(skill.transfer_buff.id, 11)
	glow.sync_bag(target.buffs, 11, 20)
	assert_false(glow.visible)


func test_wave_tooltip_uses_lifetime_and_actual_three_stats() -> void:
	var target := _target()
	var skill := _cfg.skills.by_id(&"reincarnation")
	PBSacrificeRules.grant(
		target, skill, {&"strength": 10.0, &"agility": 11.0, &"intellect": 12.0}, 0, _cfg, 1
	)
	var words := PBEffectWords.buff_body(target.buffs.states()[0], 999999, _cfg)
	assert_string_contains(words, "本波有效")
	assert_string_contains(words, "敏捷 +11")
	assert_string_contains(words, "智力 +12")
