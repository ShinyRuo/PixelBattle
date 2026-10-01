extends GutTest


func test_legacy_defaults_and_saved_blend_survive_reload() -> void:
	var existing := load("res://data/buff_art/hokage_line_guard.tres") as PBBuffSkin
	assert_eq(existing.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	var skin := PBBuffSkin.new()
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	skin.blend_style = PBBuffSkin.BlendStyle.ALPHA
	var bindings := PBBuffArtBindings.new()
	bindings.output_dir = "user://buff_blend_probe"
	assert_eq(bindings.save("blend_probe", skin), "")
	assert_eq(bindings.read("blend_probe").blend_style, PBBuffSkin.BlendStyle.ALPHA)
	DirAccess.remove_absolute("user://buff_blend_probe/blend_probe.tres")
	DirAccess.remove_absolute(bindings.output_dir)


func test_both_modes_can_coexist_and_clear_without_allocating_nodes() -> void:
	var glow := PBBuffGlow.new()
	add_child_autofree(glow)
	var count := glow.find_children("*", "", true, false).size()
	var bag := PBBuffBag.new()
	for i: int in 2:
		var buff := PBBuff.new()
		buff.id = StringName("blend_probe_%d" % i)
		var skin := PBBuffSkin.new()
		skin.blend_style = i as PBBuffSkin.BlendStyle
		skin.placeholder = true
		PBBuffGlow._library[buff.id] = skin
		bag.add(buff, {}, 0, 100, 0)
	glow.sync_bag(bag, 2, 20)
	assert_eq(glow._normal._drawings.size(), 1)
	assert_eq(glow._additive._drawings.size(), 1)
	assert_eq(glow._normal.material.blend_mode, CanvasItemMaterial.BLEND_MODE_MIX)
	assert_eq(glow._additive.material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD)
	assert_lt(glow._normal.get_index(), glow._additive.get_index())
	bag.remove(&"blend_probe_1", 3)
	glow.sync_bag(bag, 3, 20)
	assert_false(glow._normal.visible)
	assert_true(glow._additive.visible)
	glow.clear()
	assert_false(glow._normal.visible)
	assert_false(glow._additive.visible)
	assert_eq(glow.find_children("*", "", true, false).size(), count)
	for id: StringName in [&"blend_probe_0", &"blend_probe_1"]:
		PBBuffGlow._library.erase(id)


func test_same_resource_mode_edit_and_cast_preview_move_between_channels() -> void:
	var glow := PBCastGlow.new()
	add_child_autofree(glow)
	var skin := PBBuffSkin.new()
	skin.placeholder = true
	glow.front = true
	glow.preview_once(skin, 2, 20)
	assert_true(glow._additive.visible)
	skin.blend_style = PBBuffSkin.BlendStyle.ALPHA
	glow.preview_once(skin, 2, 20)
	assert_true(glow._normal.visible)
	assert_true(glow._normal.front)
	assert_false(glow._additive.visible)
	glow.clear()
	assert_false(glow.visible)
	assert_true(glow._normal._drawings.is_empty())


func test_editor_reload_preserves_blend_across_buff_switch_and_cut() -> void:
	var page := PBBuffArtPage.new()
	add_child_autofree(page)
	page._bindings.output_dir = "user://blend_editor_probe"
	var id := page._id()
	page._blend.select(1)
	page._update_skin()
	assert_eq(page._skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	var source := Image.create_empty(96, 64, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.1, 0.1, 0.1, 0.5))
	var path := "user://blend_sheet.png"
	assert_eq(source.save_png(path), OK)
	page._sheet.use_sheet(path)
	assert_true(page._cut())
	assert_eq(page._skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	assert_eq(page._bindings.save(id, page._skin), "")
	page._blend.select(0)
	page._update_skin()
	page._select()
	assert_eq(page._blend.selected, 1)
	assert_eq(page._skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	DirAccess.remove_absolute("user://blend_editor_probe/%s.tres" % id)
	DirAccess.remove_absolute(page._bindings.output_dir)
	DirAccess.remove_absolute(path)
