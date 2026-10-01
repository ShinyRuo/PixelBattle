extends GutTest


func test_eight_map_textures_are_unique_and_match_battlefield_aspect() -> void:
	assert_eq(PBMapBackground.MAPS.size(), 8)
	var seen: Dictionary = {}
	for texture: Texture2D in PBMapBackground.MAPS:
		assert_not_null(texture)
		assert_false(seen.has(texture.resource_path))
		seen[texture.resource_path] = true
		assert_eq(texture.get_size(), Vector2(1000, 440))


func test_map_cycles_once_through_all_eight_before_repeating() -> void:
	var index := 0
	var seen: Dictionary = {}
	for i: int in PBMapBackground.MAPS.size():
		assert_false(seen.has(index))
		seen[index] = true
		index = PBMapBackground.following(index)
	assert_eq(index, 0)


func test_map_fits_battlefield_and_loads_requested_texture() -> void:
	var map := PBMapBackground.new()
	add_child_autofree(map)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.show_map(3)
	assert_eq(map.texture, PBMapBackground.MAPS[3])
	assert_eq(map.position, PBLayout.B_FIELD.position - PBLayout.B_LANE_INSET)
	assert_eq(map.size, PBLayout.B_FIELD.size + PBLayout.B_LANE_INSET * 2.0)
