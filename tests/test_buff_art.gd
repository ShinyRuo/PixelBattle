extends GutTest


func _texture(size: int = 16) -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_empty(size, size, false, Image.FORMAT_RGBA8))


func test_save_reload_preserves_both_layers_and_rejects_invalid_geometry() -> void:
	var bindings := PBBuffArtBindings.new()
	bindings.output_dir = "user://buff_art_test"
	var skin := PBBuffSkin.new()
	skin.front_frames = [_texture(), _texture()]
	skin.back_frames = [_texture()]
	skin.anchor = Vector2(7, 15)
	skin.offset = Vector2(1, -2)
	assert_eq(bindings.save("sample", skin), "")
	var copied := bindings.read("sample")
	assert_eq(copied.front_frames.size(), 2)
	assert_eq(copied.back_frames.size(), 1)
	assert_eq(copied.anchor, skin.anchor)
	assert_eq(copied.offset, skin.offset)
	copied.front_frames = [_texture(32)]
	assert_ne(bindings.save("sample", copied), "")
	assert_eq(bindings.read("sample").front_frames.size(), 2)
	assert_ne(bindings.save("../escape", skin), "")
	DirAccess.remove_absolute("user://buff_art_test/sample.tres")
	DirAccess.remove_absolute("user://buff_art_test")


func test_bad_import_keeps_existing_layer_and_preview_uses_tick() -> void:
	var skin := PBBuffSkin.new()
	skin.front_frames = [_texture(), _texture()]
	var bindings := PBBuffArtBindings.new()
	assert_ne(bindings.import_layer(skin, ["res://missing_buff_frame.png"], true), "")
	assert_eq(skin.front_frames.size(), 2)
	var glow := PBBuffGlow.new()
	glow.front = true
	add_child_autofree(glow)
	glow.preview(skin, 0)
	assert_eq(glow._drawings[0].frame, 0)
	glow.preview(skin, 2)
	assert_eq(glow._drawings[0].frame, 1)
	glow.clear()
	assert_false(glow.visible)


func test_panel_exposes_buff_page_and_excludes_instant_states() -> void:
	var page := PBBuffArtPage.new()
	add_child_autofree(page)
	assert_gt(page._buffs.item_count, 0)
	for i: int in page._buffs.item_count:
		var id: String = page._buffs.get_item_metadata(i)
		var buff := load("res://data/buffs/%s.tres" % id) as PBBuff
		assert_ne(buff.kind, PBBuff.Kind.INSTANT)


func test_instant_page_only_exposes_instant_states() -> void:
	var page := PBBuffArtPage.new()
	page.instant_only = true
	add_child_autofree(page)
	assert_gt(page._buffs.item_count, 0)
	for i: int in page._buffs.item_count:
		var id: String = page._buffs.get_item_metadata(i)
		var buff := load("res://data/buffs/%s.tres" % id) as PBBuff
		assert_eq(buff.kind, PBBuff.Kind.INSTANT)


func test_whole_sheet_cut_keeps_layers_and_failed_cut_cannot_save_old_frames() -> void:
	var page := PBBuffArtPage.new()
	add_child_autofree(page)
	var source := Image.create_empty(96, 64, false, Image.FORMAT_RGBA8)
	source.fill(Color.BLACK)
	for i: int in 6:
		source.fill_rect(Rect2i((i % 3) * 32 + 8, (i / 3) * 32 + 8, 16, 16), Color.GOLD)
	var path := "user://buff_sheet_test.png"
	source.save_png(path)
	page._sheet.use_sheet(path)
	page._sheet._background.select(1)
	assert_true(page._cut())
	assert_eq(page._skin.back_frames.size(), 6)
	assert_eq(page._skin.front_frames.size(), 0)
	assert_true(page._pending.has(false))
	assert_false(page._skin.placeholder)
	page._sheet._path.text = "res://missing_sheet.png"
	assert_false(page._cut())
	assert_eq(page._skin.back_frames.size(), 6)
	page._clear(false)
	assert_false(page._pending.has(false))
	assert_eq(page._skin.back_frames.size(), 0)
	DirAccess.remove_absolute(path)


func test_instant_buff_art_is_bound_and_plays_once() -> void:
	for id: StringName in [&"heal_burst", &"danzo_izanagi", &"pein_rebirth"]:
		var skin := PBBuffGlow.instant_skin_for(id)
		assert_not_null(skin, "%s 应有瞬时恢复表现" % id)
		assert_eq(skin.front_frames.size(), 6, "%s 应为六帧" % id)
		var glow := PBBuffGlow.new()
		glow.front = true
		add_child_autofree(glow)
		glow.sync_instant(id, 0, 20)
		assert_true(glow.visible, "%s 触发时应显示" % id)
		glow.sync_instant(id, 20, 20)
		assert_false(glow.visible, "%s 播完后应自行收起" % id)
