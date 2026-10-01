extends GutTest


func test_mobile_controls_fit_canvas_and_emit_keyboard_equivalents() -> void:
	assert_lte(PBTouchControls.PANEL.end.x, PBLayout.SCREEN.x)
	assert_lte(PBTouchControls.PANEL.end.y, PBLayout.SCREEN.y)
	var controls := PBTouchControls.new()
	add_child_autofree(controls)
	var keys: Array[Key] = []
	controls.key_requested.connect(func(keycode: Key) -> void: keys.append(keycode))
	controls._buttons[&"pause"].pressed.emit()
	controls._buttons[&"start"].pressed.emit()
	assert_eq(keys.size(), 2)
	assert_eq(keys[0], KEY_SPACE)
	assert_eq(keys[1], KEY_ENTER)
	controls.refresh(true, 2, false, false, true)
	assert_eq(controls._buttons[&"pause"].text, "继续")
	assert_true(controls._buttons[&"start"].disabled)
	assert_false(controls._buttons[&"cancel"].disabled)
