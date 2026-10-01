extends GutTest

const BATTLE_SCENE := preload("res://scenes/battle.tscn")


func test_attack_range_uses_battle_clip_and_stays_above_background_below_actors() -> void:
	var root := BATTLE_SCENE.instantiate() as Node2D
	root.run_seed = 20260916
	add_child_autofree(root)
	var clip := root.get_node("TelegraphClip") as Control
	assert_true(clip.clip_contents)
	assert_eq(clip.position, PBLayout.B_FIELD.position)
	assert_eq(clip.size, PBLayout.B_FIELD.size)
	assert_eq(clip.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(clip.z_index, 0)
	assert_gt(clip.get_index(), root.get_node("Lane").get_index())
	assert_lt(clip.get_index(), root.get_node("Actors").get_index())
	var ring := clip.get_node("AttackRange") as PBAttackRangeRing
	assert_eq(ring.position, -clip.position)
	var at: Vector2 = PBLayout.B_FIELD.position + Vector2(1.0, 1.0)
	ring.sync(at, 200.0)
	assert_eq(ring.center, at)
	assert_eq(ring.radius_px, 200.0)
	ring.sync(Vector2.ZERO, 0.0)
	assert_eq(ring.radius_px, 0.0)


func test_battle_equipment_follows_selected_fighter_and_is_not_draggable() -> void:
	var root := BATTLE_SCENE.instantiate() as Node2D
	root.run_seed = 20260916
	root.auto_play = false
	add_child_autofree(root)
	var cfg: PBSimConfig = root._cfg
	var state: PBRunState = root._state
	var first := PBUnit.new(cfg.characters.by_id(&"minato"))
	var second := PBUnit.new(cfg.characters.by_id(&"kushina"))
	state.add_unit(first)
	state.add_unit(second)
	root._strategy.set_lineup(state, [first, second] as Array[PBUnit], true, true)
	var item := cfg.equipment.item(&"thunder_fang")
	for part: StringName in item.recipe:
		PBEquipRules.add_part(state.equip_parts, part)
	PBEquipRules.pin(state.equipped, first.key(), item.id, cfg)
	root._finish_prepare()
	root._selection.set_to(PBSelection.Kind.UNIT, first.key())
	root._refresh_battle_panels()
	var gear: PBEquipBay = root._gear
	assert_true(gear.visible)
	assert_string_contains(gear._title.text, "1/3")
	assert_true(gear._slots[0].visible)
	assert_false(gear._slots[0].draggable)
	root._on_equip_changed(item.id, false)
	assert_true(PBEquipRules.pinned_of(state.equipped, first.key()).has(item.id))
	root._selection.set_to(PBSelection.Kind.UNIT, second.key())
	root._on_equip_changed(item.id, true)
	assert_true(PBEquipRules.pinned_of(state.equipped, second.key()).is_empty())
	root._refresh_battle_panels()
	assert_string_contains(gear._title.text, "0/3")
	assert_false(gear._slots[0].visible)
	root._selection.set_to(PBSelection.Kind.NONE)
	root._refresh_battle_panels()
	assert_false(gear.visible)
