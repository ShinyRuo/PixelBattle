extends GutTest


func _view() -> PBBattleView:
	var view := (load("res://scenes/battle.tscn") as PackedScene).instantiate() as PBBattleView
	view.run_seed = 20260924
	add_child_autofree(view)
	return view


func _pick(view: PBBattleView, id: StringName) -> void:
	for i: int in view._debug._ninjas.item_count:
		if view._debug._ninjas.get_item_metadata(i) == id:
			view._debug._ninjas.select(i)
			return


func test_button_opens_and_deploys_selected_ninja_without_cost_or_gacha() -> void:
	var view := _view()
	var gold := view._state.gold
	var rng_state: int = view._rng.gacha.state
	view._debug_button.pressed.emit()
	assert_true(view._debug.visible)
	_pick(view, &"asuma")
	assert_string_contains(view._debug._ninjas.get_item_text(view._debug._ninjas.selected), "猿飞阿斯玛")
	view._debug._deploy.pressed.emit()
	assert_eq(view._state.gold, gold)
	assert_eq(view._rng.gacha.state, rng_state)
	assert_eq(view._state.pending_offer.size(), 0)
	assert_eq(view._state.roster.size(), 1)
	assert_true(view._state.field.has(&"asuma"))
	assert_eq(view._selection.unit_id, &"asuma")
	view._debug.close()
	view._finish_prepare()
	assert_eq(view._plan.deployed[0].character.id, &"asuma")
	assert_eq(view._plan.attackers[0].skills[0].skill.id, &"ash_burn")
	assert_gt(view._plan.attackers[0].hp, 0.0)


func test_duplicates_have_separate_keys_and_full_field_does_not_create_more() -> void:
	var view := _view()
	view._open_debug()
	var capacity := view._state.field_slots(view._cfg)
	for i: int in capacity:
		view._debug_deploy(&"asuma")
	assert_eq(view._state.roster.size(), capacity)
	assert_true(view._state.roster.has(&"asuma#1"))
	var lineup: Array[StringName] = view._state.lineup.duplicate()
	view._debug_deploy(&"itachi")
	assert_eq(view._state.roster.size(), capacity)
	assert_eq(view._state.lineup, lineup)
	assert_string_contains(view._debug._status.text, "已满")


func test_invalid_id_does_not_change_roster() -> void:
	var view := _view()
	view._debug_deploy(&"missing_debug_character")
	assert_eq(view._state.roster.size(), 0)


func test_battle_window_blocks_addition_and_freezes_tick_without_changing_pause() -> void:
	var view := _view()
	view._finish_prepare()
	view._paused = false
	view._open_debug()
	assert_true(view._debug._deploy.disabled)
	var tick := view._battle.current_tick()
	for i: int in 10:
		view._physics_process(0.0)
	assert_eq(view._battle.current_tick(), tick)
	view._debug_deploy(&"asuma")
	assert_eq(view._state.roster.size(), 0)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	view._unhandled_input(event)
	assert_false(view._debug.visible)
	assert_false(view._paused)
	view._paused = true
	view._open_debug()
	view._debug.close()
	assert_true(view._paused)


func test_auto_prepare_cannot_advance_behind_debug_window() -> void:
	var view := _view()
	view.auto_play = true
	view._open_debug()
	view._physics_process(0.0)
	assert_eq(view._phase, PBBattleView.Phase.PREPARE)
	view._debug_deploy(&"asuma")
	assert_false(view.auto_play)


func test_debug_does_not_cover_pending_offer() -> void:
	var view := _view()
	view._on_command(&"gacha")
	assert_true(view._offer.visible)
	view._open_debug()
	assert_false(view._debug.visible)
