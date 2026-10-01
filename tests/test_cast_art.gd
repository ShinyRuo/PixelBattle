extends GutTest

const ROOT := "user://cast_art_test"
var _skin: PBBuffSkin
var _unit: PBAttacker
var _cast: PBSkillCast
var _glow: PBCastGlow


func before_each() -> void:
	_skin = PBBuffSkin.new()
	_skin.fps = 20
	var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for i: int in 6:
		_skin.back_frames.append(ImageTexture.create_from_image(image))
		_skin.front_frames.append(ImageTexture.create_from_image(image))
	_unit = PBAttacker.new()
	_unit.max_hp = 1000
	_unit.max_mp = 100
	_unit.revive()
	var skill := PBSkill.new()
	skill.id = &"start_probe"
	skill.target = PBSkill.Target.NONE
	_cast = PBSkillCast.new(skill)
	_cast.cast_now(0)
	_unit.skills = [_cast]
	PBSkillOrders.begin(_unit, _cast, PBSimConfig.new(), 0, null)
	PBCastGlow._starts[&"start_probe"] = _skin
	_glow = PBCastGlow.new()
	add_child_autofree(_glow)


func after_each() -> void:
	PBCastGlow.clear_cache()


func test_start_frames_use_ticks_stop_at_release_and_never_add_buff() -> void:
	for tick: int in 6:
		_glow.sync_cast(_unit, tick, 20)
		assert_true(_glow.visible)
		assert_eq(_glow._drawings[0].frame, tick)
		assert_eq(_unit.buffs.count(tick), 0)
		_glow.sync_cast(_unit, tick, 20)
		assert_eq(_glow._drawings[0].frame, tick, "暂停不推进动画")
	_glow.sync_cast(_unit, 6, 20)
	assert_false(_glow.visible)
	_unit.casting.advance(_unit, PBSimConfig.new(), 6, null)
	_glow.sync_cast(_unit, 8, 20)
	assert_false(_glow.visible, "收招阶段不能重播起手光")


func test_front_layer_holds_last_frame_without_looping() -> void:
	_glow.front = true
	_skin.front_frames.resize(2)
	_glow.sync_cast(_unit, 5, 20)
	assert_eq(_glow._drawings[0].frame, 1)
	assert_same(_glow._drawings[0].skin, _skin)


func test_interruption_and_missing_art_clear_previous_drawings() -> void:
	for key: StringName in [PBBuffRules.STUN, PBBuffRules.SILENCE]:
		_glow.sync_cast(_unit, 2, 20)
		assert_true(_glow.visible)
		var control := PBBuff.new()
		control.id = &"interrupt_probe"
		_unit.buffs.add(control, {key: 1.0}, 2, 10, 0)
		_glow.sync_cast(_unit, 2, 20)
		assert_false(_glow.visible)
		_unit.buffs.clear()
	_unit.alive = false
	_glow.sync_cast(_unit, 2, 20)
	assert_false(_glow.visible)
	_unit.alive = true
	_unit.casting.skill_id = &"unconfigured_start_probe"
	_glow.sync_cast(_unit, 2, 20)
	assert_false(_glow.visible)


func test_repeated_cast_restarts_first_frame() -> void:
	_glow.sync_cast(_unit, 5, 20)
	_unit.casting.cancel(_unit)
	_glow.sync_cast(_unit, 5, 20)
	assert_false(_glow.visible)
	_cast.cast_now(20)
	PBSkillOrders.begin(_unit, _cast, PBSimConfig.new(), 20, null)
	_glow.sync_cast(_unit, 20, 20)
	assert_eq(_glow._drawings[0].frame, 0)


func test_bind_unbind_and_invalid_asset_leave_skill_definition_alone() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	ResourceSaver.save(_cast.skill, ROOT + "/start_probe.tres")
	ResourceSaver.save(_skin, ROOT + "/castGlowA.tres")
	var bindings := PBCastArtBindings.new()
	bindings.art_dir = ROOT
	bindings.skill_dir = ROOT
	bindings.binding_dir = ROOT + "/bindings"
	var original := FileAccess.get_file_as_string(ROOT + "/start_probe.tres")
	assert_eq(bindings.assign("start_probe", "castGlowA"), "")
	assert_eq(bindings.read("start_probe"), &"castGlowA")
	assert_ne(bindings.assign("start_probe", "missing"), "")
	assert_ne(bindings.assign("start_probe", "../escape"), "")
	assert_eq(bindings.read("start_probe"), &"castGlowA")
	assert_eq(bindings.assign("start_probe", ""), "")
	assert_eq(bindings.read("start_probe"), &"")
	assert_eq(FileAccess.get_file_as_string(ROOT + "/start_probe.tres"), original)
	for path: String in ["bindings/start_probe.tres", "start_probe.tres", "castGlowA.tres"]:
		DirAccess.remove_absolute(ROOT + "/" + path)
	DirAccess.remove_absolute(ROOT + "/bindings")
	DirAccess.remove_absolute(ROOT)


func test_named_start_page_reuses_sheet_controls_and_defaults_to_twenty_fps() -> void:
	var page := PBCastArtPage.new()
	add_child_autofree(page)
	assert_not_null(page._sheet)
	assert_not_null(page._sheet_preview)
	assert_true(page.cast_preview)
	assert_eq(page._skin.fps, 20.0)
	assert_eq(page._bindings.output_dir, "res://data/cast_art")
	assert_eq(page.asset_dir, "res://assets/fx/casts")
	page._key.text = "castTestB"
	assert_eq(page._id(), "castTestB")


func test_unbound_skills_fall_back_to_nonphysical_attack_element() -> void:
	var old_starts := PBCastGlow._starts
	PBCastGlow._starts = {}
	for element: PBElement.Type in [
		PBElement.Type.FIRE,
		PBElement.Type.WIND,
		PBElement.Type.THUNDER,
		PBElement.Type.EARTH,
		PBElement.Type.WATER,
		PBElement.Type.SAGE,
	]:
		var skill_id := StringName("element_probe_%d" % element)
		var skin := PBCastGlow.start_for(skill_id, element)
		assert_not_null(skin, "非物理属性应有起手光：%s" % element)
		assert_eq(skin.back_frames.size(), 6)
	assert_null(PBCastGlow.start_for(&"physical_probe", PBElement.Type.PHYSICAL))
	PBCastGlow._starts = old_starts


func test_explicit_skill_start_still_wins_over_element_fallback() -> void:
	var explicit := PBBuffSkin.new()
	explicit.fps = 20.0
	for _i: int in 6:
		explicit.back_frames.append(
			ImageTexture.create_from_image(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8))
		)
	PBCastGlow._starts[&"explicit_probe"] = explicit
	assert_same(PBCastGlow.start_for(&"explicit_probe", PBElement.Type.FIRE), explicit)


func test_same_unbound_skill_can_use_different_element_fallbacks() -> void:
	PBCastGlow.clear_cache()
	var fire := PBCastGlow.start_for(&"shared_probe", PBElement.Type.FIRE)
	var water := PBCastGlow.start_for(&"shared_probe", PBElement.Type.WATER)
	assert_not_null(fire)
	assert_not_null(water)
	assert_ne(fire, water)


func test_kagura_eye_uses_dedicated_red_sensing_start_not_element_fallback() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("kagura_eye"), &"cast_kagura_eye")
	var skin := PBCastGlow.start_for(&"kagura_eye", PBElement.Type.PHYSICAL)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))
	assert_same(PBCastGlow.start_for(&"kagura_eye", PBElement.Type.FIRE), skin)


func test_tool_control_uses_dedicated_scroll_start_with_normal_alpha() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("tool_control"), &"cast_tool_control")
	var skin := PBCastGlow.start_for(&"tool_control", PBElement.Type.PHYSICAL)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_hidden_mist_uses_dedicated_short_alpha_cast_fog() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("hidden_mist"), &"cast_hidden_mist")
	var skin := PBCastGlow.start_for(&"hidden_mist", PBElement.Type.WATER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_release_blades_uses_dedicated_blue_sword_chakra_start() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("release_blades"), &"cast_release_blades")
	var skin := PBCastGlow.start_for(&"release_blades", PBElement.Type.WATER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.32)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_paper_wings_uses_dedicated_short_paper_burst_before_buff_wings() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("paper_wings"), &"cast_paper_wings")
	var skin := PBCastGlow.start_for(&"paper_wings", PBElement.Type.WATER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ALPHA)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_eight_gates_uses_dedicated_unlock_pulse_before_green_flame_buff() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("eight_gates"), &"cast_eight_gates")
	var skin := PBCastGlow.start_for(&"eight_gates", PBElement.Type.PHYSICAL)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_chidori_uses_dedicated_hand_lightning_start() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("chidori"), &"cast_chidori")
	var skin := PBCastGlow.start_for(&"chidori", PBElement.Type.THUNDER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.28)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_rasengan_flame_uses_dedicated_handheld_fire_spiral_start() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("rasengan_flame"), &"cast_rasengan_flame")
	var skin := PBCastGlow.start_for(&"rasengan_flame", PBElement.Type.FIRE)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.19)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_lightning_armor_uses_dedicated_short_unlock_flash() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("lightning_armor"), &"cast_lightning_armor")
	var skin := PBCastGlow.start_for(&"lightning_armor", PBElement.Type.THUNDER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.3)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))

