extends GutTest


func test_malice_sense_uses_dedicated_golden_sensing_pulse() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("malice_sense"), &"cast_malice_sense")
	var skin := PBCastGlow.start_for(&"malice_sense", PBElement.Type.SAGE)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_kotoamatsukami_uses_dedicated_short_green_eye_glint() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("kotoamatsukami"), &"cast_kotoamatsukami")
	var skin := PBCastGlow.start_for(&"kotoamatsukami", PBElement.Type.PHYSICAL)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_flying_raijin_ball_uses_dedicated_preblink_glow() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("flying_raijin_ball"), &"cast_flying_raijin_ball")
	var skin := PBCastGlow.start_for(&"flying_raijin_ball", PBElement.Type.WATER)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.32)
	assert_eq(skin.offset, Vector2(0, -30))
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))


func test_giant_rasengan_uses_dedicated_held_chakra_orb() -> void:
	PBCastGlow.clear_cache()
	assert_eq(PBCastArtBindings.new().read("giant_rasengan"), &"cast_giant_rasengan")
	var skin := PBCastGlow.start_for(&"giant_rasengan", PBElement.Type.SAGE)
	assert_not_null(skin)
	assert_eq(skin.back_frames.size(), 6)
	assert_eq(skin.front_frames.size(), 0)
	assert_eq(skin.blend_style, PBBuffSkin.BlendStyle.ADDITIVE)
	assert_eq(skin.fps, 20.0)
	assert_eq(skin.pixel_scale, 0.35)
	assert_eq(skin.offset, Vector2(5, -25))
	for frame: Texture2D in skin.back_frames:
		assert_eq(frame.get_size(), Vector2(256, 256))
