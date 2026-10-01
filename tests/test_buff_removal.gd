extends GutTest

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _unit() -> PBAttacker:
	var unit := PBUnit.new(_cfg.characters.by_id(&"raikage"))
	var one := (
		PBCombatRules
		. build_attackers([unit], PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg)[0]
	)
	one.prime(_cfg.tick_rate, _cfg)
	one.revive()
	return one


func _buff(id: StringName, strength: float = 0.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = id
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = true
	buff.duration_seconds = 5.0
	buff.mods = {PBBuffRules.STRENGTH: strength, PBBuffRules.DEFENCE: 3.0}
	return buff


func test_thirty_two_effects_then_eviction_revokes_derived_attributes_immediately() -> void:
	var one := _unit()
	var base: float = one.damage_attributes[&"strength"]
	var hp: float = one.max_hp
	one.hp *= 0.4
	var first := _buff(&"first", 10.0)
	one.buffs.add(first, first.mods, 0, 10, 0)
	for i: int in 31:
		var buff := _buff(StringName("slot_%d" % i))
		one.buffs.add(buff, buff.mods, 0, 100, 0)
	assert_eq(one.buffs.count(0), 32)
	assert_eq(one.damage_attributes[&"strength"], base + 10.0)
	var incoming := _buff(&"incoming")
	one.buffs.add(incoming, incoming.mods, 1, 100, 0)
	assert_eq(one.buffs.count(1), 32)
	assert_eq(one.damage_attributes[&"strength"], base)
	assert_almost_eq(one.max_hp, hp, 0.00001)
	assert_almost_eq(one.hp / one.max_hp, 0.4, 0.00001)
	assert_eq(one.buffs.remove(&"first", 1), 0)


func test_cancel_and_clear_revoke_only_their_own_current_bonus() -> void:
	var one := _unit()
	var base: float = one.damage_attributes[&"strength"]
	var first := _buff(&"first", 10.0)
	var second := _buff(&"second", 20.0)
	one.buffs.add(first, first.mods, 0, 100, 0)
	one.buffs.add(second, second.mods, 0, 100, 0)
	PBAttributeRules.grant(one, {PBStatRules.STRENGTH: 7.0}, _cfg)
	assert_eq(one.buffs.remove(first.id, 1), 1)
	assert_eq(one.damage_attributes[&"strength"], base + 27.0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 3.0)
	assert_eq(one.buffs.remove(first.id, 1), 0)
	one.buffs.clear(1)
	assert_eq(one.damage_attributes[&"strength"], base + 7.0)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 0.0)


func test_expiry_and_same_id_replacement_do_not_leave_stale_strength() -> void:
	var one := _unit()
	var base: float = one.damage_attributes[&"strength"]
	var buff := _buff(&"replace", 10.0)
	one.buffs.add(buff, buff.mods, 0, 10, 0)
	one.buffs.add(buff, {PBBuffRules.STRENGTH: 4.0}, 1, 10, 0)
	assert_eq(one.damage_attributes[&"strength"], base + 4.0)
	one.buffs.sweep(12)
	assert_eq(one.damage_attributes[&"strength"], base)
	assert_eq(one.buffs.count(12), 0)


func test_cancelling_shield_and_periodic_effect_removes_remaining_payload() -> void:
	var one := _unit()
	var buff := _buff(&"shield")
	one.buffs.add(buff, {PBBuffRules.SHIELD: 100.0, PBBuffRules.HEAL: 20.0}, 0, 100, 1)
	one.hp -= 50.0
	var before: float = one.hp
	one.buffs.remove(buff.id, 1)
	assert_eq(one.buffs.absorb(80.0, 1), 80.0)
	PBBuffRules.advance_ally(one, 2, _cfg.tick_rate)
	assert_eq(one.hp, before)
