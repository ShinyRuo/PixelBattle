extends GutTest

const ROOT := "user://art_binding_test"
var _bindings: PBArtBindings


func before_each() -> void:
	_bindings = PBArtBindings.new()
	_bindings.presentation_dir = ROOT + "/presentation"
	_bindings.skill_sheet = ROOT + "/skills.tsv"
	_bindings.skill_dir = ROOT
	_bindings.shot_dir = ROOT
	_bindings.actor_dir = ROOT
	_bindings.character_dir = ROOT
	DirAccess.make_dir_recursive_absolute(ROOT)
	var file := FileAccess.open(_bindings.skill_sheet, FileAccess.WRITE)
	file.store_string("sample\towner\t示例\t水\t点敌人\t敌方\t1\t0\t10\t5\tfly=0.3;base=3\n")
	file.close()
	var skill := PBSkill.new()
	skill.id = &"sample"
	skill.shot_cross_seconds = 0.3
	ResourceSaver.save(skill, ROOT + "/sample.tres")
	var shot := PBShotSkin.new()
	ResourceSaver.save(shot, ROOT + "/test_shot.tres")
	var owner := PBCharacter.new()
	owner.actor_key = &"test_actor"
	ResourceSaver.save(owner, ROOT + "/owner.tres")
	var skin := PBActorSkin.new()
	skin.frames = SpriteFrames.new()
	skin.frames.add_animation(&"attack")
	skin.frames.add_frame(&"attack", _texture())
	ResourceSaver.save(skin, ROOT + "/test_actor.tres")
	for name: String in ["sample", "test_shot", "owner", "test_actor"]:
		ResourceLoader.load(ROOT + "/%s.tres" % name, "", ResourceLoader.CACHE_MODE_REPLACE)


func _texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	return ImageTexture.create_from_image(image)


func test_missing_or_broken_cast_mapping_uses_attack_and_valid_mapping_wins() -> void:
	var skin := load(ROOT + "/test_actor.tres") as PBActorSkin
	assert_eq(skin.skill_anim(&"sample"), &"attack")
	skin.skill_anims[&"sample"] = &"missing"
	assert_eq(skin.skill_anim(&"sample"), &"attack")
	skin.frames.add_animation(&"cast_sample")
	skin.frames.add_frame(&"cast_sample", _texture())
	skin.skill_anims[&"sample"] = &"cast_sample"
	assert_eq(skin.skill_anim(&"sample"), &"cast_sample")
	assert_eq(_bindings.clear_cast("sample"), "")
	var saved := (
		ResourceLoader.load(ROOT + "/test_actor.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		as PBActorSkin
	)
	assert_eq(saved.skill_anim(&"sample"), &"attack")


func test_shot_binding_persists_to_source_sheet_and_can_be_removed() -> void:
	assert_eq(_bindings.assign_shot("sample", "test_shot"), "")
	var text := FileAccess.get_file_as_string(_bindings.skill_sheet)
	assert_string_contains(text, "fly=0.3;base=3;shot=test_shot")
	var skill := (
		ResourceLoader.load(ROOT + "/sample.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PBSkill
	)
	assert_eq(skill.shot_key, &"test_shot")
	assert_eq(skill.shot_cross_seconds, 0.3)
	assert_eq(_bindings.assign_shot("sample", ""), "")
	assert_false(FileAccess.get_file_as_string(_bindings.skill_sheet).contains("shot="))


func test_shot_rejects_non_projectile_without_modifying_sheet() -> void:
	var original := FileAccess.get_file_as_string(_bindings.skill_sheet)
	var skill := load(ROOT + "/sample.tres") as PBSkill
	skill.shot_cross_seconds = 0.0
	skill.delay_ticks = 0
	assert_ne(_bindings.assign_shot("sample", "test_shot"), "")
	assert_eq(FileAccess.get_file_as_string(_bindings.skill_sheet), original)


func test_ground_carrier_binding_keeps_damage_timing_and_targeting() -> void:
	var skill := load(ROOT + "/sample.tres") as PBSkill
	skill.shot_cross_seconds = 0.0
	skill.target = PBSkill.Target.GROUND
	skill.delay_ticks = 10
	assert_eq(_bindings.assign_shot("sample", "test_shot"), "")
	var saved := (
		ResourceLoader.load(ROOT + "/sample.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PBSkill
	)
	assert_eq(saved.shot_cross_seconds, 0.0)
	assert_eq(saved.delay_ticks, 10)
	assert_eq(saved.target, PBSkill.Target.GROUND)


func test_rebuilding_four_states_keeps_cast_frames_duration_and_loop() -> void:
	var skin := load(ROOT + "/test_actor.tres") as PBActorSkin
	skin.frames.add_animation(&"cast_sample")
	skin.frames.set_animation_loop(&"cast_sample", false)
	skin.frames.set_animation_speed(&"cast_sample", 10.0)
	for index: int in 6:
		skin.frames.add_frame(&"cast_sample", _texture(), 1.0 + index)
	var fresh := SpriteFrames.new()
	fresh.add_animation(&"attack")
	PBArtBindings.keep_extra_animations(skin, fresh)
	assert_eq(fresh.get_frame_count(&"attack"), 0)
	assert_eq(fresh.get_frame_count(&"cast_sample"), 6)
	assert_eq(fresh.get_frame_duration(&"cast_sample", 5), 6.0)
	assert_false(fresh.get_animation_loop(&"cast_sample"))
	assert_eq(fresh.get_animation_speed(&"cast_sample"), 10.0)


func test_cast_import_validates_six_frames_before_writing() -> void:
	var before := FileAccess.get_file_as_string(ROOT + "/test_actor.tres")
	assert_ne(_bindings.assign_cast("sample", PackedStringArray()), "")
	assert_eq(FileAccess.get_file_as_string(ROOT + "/test_actor.tres"), before)


func test_six_imported_textures_persist_mapping_and_preserve_attack() -> void:
	# 复用已有贴图验证资源持久化，不向项目写测试图片。
	var paths := PackedStringArray()
	for index: int in 6:
		paths.append("res://assets/portraits/zetsu.png")
	assert_eq(_bindings.assign_cast("sample", paths), "")
	var saved := (
		ResourceLoader.load(ROOT + "/test_actor.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		as PBActorSkin
	)
	assert_eq(saved.skill_anim(&"sample"), &"cast_sample")
	assert_eq(saved.frames.get_frame_count(&"cast_sample"), 6)
	assert_eq(saved.frames.get_frame_count(&"attack"), 1)
	assert_false(saved.frames.get_animation_loop(&"cast_sample"))
	assert_eq(saved.frames.get_animation_speed(&"cast_sample"), 10.0)


func test_existing_skill_track_binding_does_not_duplicate_frames() -> void:
	var path := ROOT + "/test_actor.tres"
	var skin := load(path) as PBActorSkin
	skin.frames.add_animation(&"skill1")
	for i: int in 6:
		skin.frames.add_frame(&"skill1", _texture())
	ResourceSaver.save(skin, path)
	assert_eq(_bindings.assign_animation("sample", &"skill1"), "")
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBActorSkin
	assert_eq(saved.skill_anim(&"sample"), &"skill1")
	assert_false(saved.frames.has_animation(&"cast_sample"))
	assert_ne(_bindings.assign_animation("sample", &"skill2"), "")
	assert_eq(_bindings.clear_cast("sample"), "")
	assert_eq(PBShotForge.key_error("skillbulletA"), "")


func test_optional_skill_tracks_use_six_frames_at_fixed_speed() -> void:
	assert_eq(PBActorForge.anim_names().size(), 4)
	assert_true("skill1" in PBActorForge.anim_names(true))
	assert_true("skill2" in PBActorForge.anim_names(true))
	for anim: String in ["skill1", "skill2"]:
		var spec := PBActorForge.spec_of(anim)
		assert_eq(spec.fps, 10.0)
		assert_false(spec.loop)
		assert_eq(PBActorForge.new().frames_for([{}, {}, {}, {}, {}, {}], anim), [0, 1, 2, 3, 4, 5])


func test_flight_modes_preserve_start_and_hiding_preserves_hit_art() -> void:
	DirAccess.make_dir_recursive_absolute(_bindings.presentation_dir)
	var path := _bindings.presentation_dir + "/sample.tres"
	var art := PBSkillStartArt.new()
	art.start_key = &"keep_start"
	ResourceSaver.save(art, path)
	assert_eq(_bindings.assign_flight("sample", PBArtBindings.Flight.NAMED, "test_shot"), "")
	var original := FileAccess.get_file_as_string(_bindings.skill_sheet)
	assert_eq(_bindings.assign_flight("sample", PBArtBindings.Flight.HIDDEN), "")
	art = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(art.hide_flight)
	assert_eq(art.start_key, &"keep_start")
	assert_eq(FileAccess.get_file_as_string(_bindings.skill_sheet), original)
	var starts := PBCastArtBindings.new()
	starts.skill_dir = ROOT
	starts.binding_dir = _bindings.presentation_dir
	assert_eq(starts.assign("sample", ""), "")
	art = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_true(art.hide_flight, "修改起手光不能清除飞行模式")
	assert_eq(_bindings.assign_flight("sample", PBArtBindings.Flight.DEFAULT), "")
	art = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	assert_false(art.hide_flight)
	assert_false(FileAccess.get_file_as_string(_bindings.skill_sheet).contains("shot="))
	assert_ne(_bindings.assign_flight("sample", PBArtBindings.Flight.NAMED), "")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(_bindings.presentation_dir)
