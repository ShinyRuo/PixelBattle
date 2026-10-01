extends GutTest


func test_base_uses_transparent_five_head_art_and_motion_overlay() -> void:
	var slots := PBFieldSlots.new()
	add_child_autofree(slots)
	var base := slots._base
	assert_eq(base.texture, PBIconArt.base())
	assert_eq(base.size, Vector2.ONE * PBIconArt.base_size())
	assert_eq(base.expand_mode, TextureRect.EXPAND_IGNORE_SIZE)
	assert_true(base.get_child(0) is PBBaseMotion)
	var image: Image = base.texture.get_image()
	assert_eq(image.get_size(), Vector2i(256, 256))
	assert_lt(image.get_pixel(0, 0).a, 0.05)
	assert_gt(image.get_pixel(128, 128).a, 0.9)


func test_flags_and_birds_are_updated_as_time_passes() -> void:
	var motion := PBBaseMotion.new()
	add_child_autofree(motion)
	motion._process(0.25)
	assert_almost_eq(motion._time, 0.25, 0.001)
	motion._process(0.5)
	assert_almost_eq(motion._time, 0.75, 0.001)
