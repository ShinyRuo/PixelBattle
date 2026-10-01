extends GutTest


func _sheet() -> Image:
	var image := Image.create_empty(90, 40, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(10, 10, 8, 8), Color.RED)
	image.fill_rect(Rect2i(35, 7, 16, 16), Color(0, 1, 0, 0.5))
	return image


func test_grid_preserves_order_transparency_empty_tail_and_relative_size() -> void:
	var forge := PBFieldSheetForge.new()
	forge.rows = 1
	forge.count = 3
	forge.output_size = 64
	var original := _sheet()
	var before := original.get_data()
	var images := forge.slice(original)
	assert_eq(images.size(), 3)
	assert_eq(original.get_data(), before, "不修改源图")
	assert_eq(images[0].get_size(), Vector2i(64, 64))
	assert_gt(images[0].get_pixel(32, 32).r, 0.9)
	assert_gt(images[1].get_pixel(32, 32).g, 0.9)
	assert_almost_eq(images[1].get_pixel(32, 32).a, 0.5, 0.01)
	assert_lt(images[0].get_used_rect().size.x, images[1].get_used_rect().size.x)
	assert_false(images[2].get_used_rect().has_area(), "空尾帧必须保留")


func test_smoke_removes_light_checker_and_keeps_soft_dark_content() -> void:
	var source := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	source.fill(Color(0.96, 0.96, 0.96, 1))
	source.fill_rect(Rect2i(8, 8, 16, 16), Color(0.5, 0.5, 0.5, 1))
	var forge := PBFieldSheetForge.new()
	forge.rows = 1
	forge.columns = 1
	forge.count = 1
	forge.output_size = 32
	forge.center_frames = false
	forge.background = PBFieldSheetForge.Background.SMOKE
	var result := forge.slice(source)[0]
	assert_eq(result.get_pixel(0, 0).a, 0.0)
	assert_between(result.get_pixel(16, 16).a, 0.4, 0.6)
	assert_lt(result.get_pixel(16, 16).r, 0.1)


func test_automatic_cut_and_bad_frame_count_report_errors() -> void:
	var forge := PBFieldSheetForge.new()
	forge.automatic = true
	forge.gap = 5
	forge.count = 2
	assert_eq(forge.slice(_sheet()).size(), 2)
	forge.count = 6
	assert_true(forge.slice(_sheet()).is_empty())
	assert_ne(forge.error, "")
	assert_true(forge.slice(null).is_empty())


func test_area_art_adjustment_never_changes_skill_radius() -> void:
	var skill := PBSkill.new()
	skill.radius = 0.15
	var skin := PBFieldSkin.new()
	skin.area_scale = 1.5
	skin.area_offset = Vector2(0.2, -0.1)
	var box := PBFieldArt.area_rect(skin, Vector2.ZERO, 75)
	assert_eq(box.size.x, 225.0)
	assert_almost_eq(box.get_center().x, 15.0, 0.001)
	assert_almost_eq(box.get_center().y, -7.5 * PBLayout.Y_SCALE, 0.001)
	assert_eq(skill.radius, 0.15)
	skin.area_scale = NAN
	assert_ne(skin.problem(), "")


func test_preview_zone_centers_match_real_hazard_geometry() -> void:
	var skill := PBGameData.config().skills.by_id(&"boil_acid_kage").clone()
	var view := PBFieldArtPreview.new()
	add_child_autofree(view)
	view.kind = "zones"
	view.skill = skill
	var caster := PBAttacker.new()
	caster.prime(20)
	var cast := PBSkillCast.new(skill)
	cast.spot = Vector2.ZERO
	var zone := PBHazardZone.new()
	zone.begin(caster, cast, 0)
	assert_eq(view.centers().size(), zone.points.size())
	for i: int in zone.points.size():
		assert_lt(view.centers()[i].distance_to(zone.points[i]), 0.000001)
	assert_eq(view.radius_units(), skill.zone_radius)


func test_editor_page_cuts_whole_sheet_and_roundtrips_source_settings() -> void:
	var path := "user://field_sheet_probe.png"
	assert_eq(_sheet().save_png(path), OK)
	var page := PBFieldArtPage.new()
	add_child_autofree(page)
	page._sheet.use_sheet(path)
	page._sheet._rows.value = 1
	page._sheet._count.value = 3
	page._cut()
	assert_eq(page._skin.frames.size(), 3)
	assert_true(page._generated)
	var saved: Dictionary = page._skin.get_meta("sheet")
	assert_eq(int(saved.count), 3)
	page._sheet.restore(saved)
	assert_eq(page._sheet._path.text, path)
	assert_eq(page._cut_images.size(), 3, "换源图不破坏上次已预览帧")
	page._clear()
	assert_false(page._generated)
	assert_true(page._skin.frames.is_empty())
	DirAccess.remove_absolute(path)


func test_real_generated_asset_is_portable_and_has_no_opaque_background() -> void:
	var skin := load("res://data/field_art/areas/ash_burn.tres") as PBFieldSkin
	assert_eq(skin.problem(), "")
	assert_eq(skin.frames.size(), 6)
	assert_false(skin.placeholder)
	for texture: Texture2D in skin.frames:
		assert_true(texture.resource_path.begins_with("res://assets/"))
		var image := texture.get_image()
		assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(int(skin.get_meta("sheet", {}).get("count")), 6)


func test_saved_binding_reads_new_values_even_when_old_resource_is_cached() -> void:
	var bindings := PBFieldArtBindings.new()
	bindings.output_dir = "user://field_sheet_binding_probe"
	var skin := PBFieldSkin.new()
	assert_eq(bindings.save("areas", "ash_burn", skin), "")
	var path := bindings.output_dir + "/areas/ash_burn.tres"
	var old := load(path) as PBFieldSkin
	assert_eq(old.fps, 10.0)
	skin = skin.duplicate() as PBFieldSkin
	skin.fps = 17
	assert_eq(bindings.save("areas", "ash_burn", skin), "")
	assert_eq(bindings.read("areas", "ash_burn").fps, 17.0)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(bindings.output_dir + "/areas")
	DirAccess.remove_absolute(bindings.output_dir)


func test_link_strip_keeps_aspect_ratio_when_generating_frames() -> void:
	var source := Image.create_empty(80, 20, false, Image.FORMAT_RGBA8)
	source.fill(Color.WHITE)
	var forge := PBFieldSheetForge.new()
	forge.square_canvas = false
	forge.count = 1
	forge.columns = 1
	forge.rows = 1
	forge.output_size = 160
	assert_eq(forge.slice(source)[0].get_size(), Vector2i(160, 40))
