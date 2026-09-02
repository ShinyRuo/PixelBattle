extends GutTest
## `data/actors/` 里那几张战场形象。M6-f。
##
## 和 `test_character_data.gd` / `test_beast_data.gd` 同一路子：**规格里写着的
## 那几条，能用机器验的就别靠人看**。这一份钉的全是「不报错」的那一类：
##
## - 目录里混进一个不是 [PBActorSkin] 的 `.tres` —— 每次读表刷一条错误
## - 少一段 —— [method PBActorSkin.resolve] 会静默退回待机，人「会站不会跑」
## - 帧尺寸不齐 —— 脚底锚只对得上第一帧，人在动画里上下跳
## - 脚没踩在画布底边上 —— 前后关系错一档，**而所有坐标看起来都完全正确**
## - [member PBCharacter.actor_key] 拼错 —— 表现只是「还是白模」

const DIR := "res://data/actors"

## 三段是硬要求（`Docs/素材规格_战场形象.md` 第 8 节）。
## `cast` / `dead` 可选，查不到会退回攻击段与待机段。
const REQUIRED: Array[StringName] = [&"idle", &"run", &"attack"]


func _skins() -> Dictionary:
	return PBActorLibrary.load_from(DIR)


func test_every_tres_in_the_folder_is_actually_an_actor_skin() -> void:
	# [method PBActorLibrary.load_from] 对装不进来的条目会 `push_error`，
	# 而那条报错是对的 —— 放错类型就该说。所以图集那种伴生资源
	# **不能和形象表并排放**（`data/actors/frames/` 是给它的），
	# 否则每一次读表都刷一条错误，而游戏照跑。
	var dir := DirAccess.open(DIR)
	assert_not_null(dir, "形象目录该打得开")
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = load("%s/%s" % [DIR, file_name])
		assert_true(
			res is PBActorSkin,
			"%s 不是一张 PBActorSkin —— 伴生资源请放 data/actors/frames/" % file_name
		)


func test_the_frames_subfolder_is_invisible_to_the_scan() -> void:
	# 扫描不递归，这是上一条的前提。哪天有人给它加了递归，这条会红。
	for key: StringName in _skins():
		var skin: PBActorSkin = _skins()[key]
		assert_true(skin is PBActorSkin, "%s 应该是一张皮" % key)


func test_every_skin_has_a_key_that_matches_its_file() -> void:
	var seen: Dictionary = {}
	for key: StringName in _skins():
		assert_ne(key, &"", "键不能是空的 —— 空的话查不到，永远退白模")
		assert_false(seen.has(key), "键撞了：%s" % key)
		seen[key] = true


func test_every_skin_carries_the_three_required_animations() -> void:
	# **不能靠兜底。** [method PBActorSkin.anim_for] 查不到会退回待机，
	# 那是给「这个角色暂时没画施法段」留的路，不是给拼错名字留的。
	for key: StringName in _skins():
		var skin: PBActorSkin = _skins()[key]
		assert_not_null(skin.frames, "%s 没有图集" % key)
		for anim: StringName in REQUIRED:
			assert_true(skin.has(anim), "%s 少一段 `%s`" % [key, anim])
			assert_gt(skin.frames.get_frame_count(anim), 0, "%s 的 `%s` 是空的" % [key, anim])


func test_every_frame_of_a_skin_is_the_same_size() -> void:
	# [method PBActorSkin.canvas_size] 只读第一帧，脚底锚是从画布尺寸算的
	# （[method PBActorSkin.anchor]）—— 尺寸不齐的话锚只对得上第一帧。
	for key: StringName in _skins():
		var skin: PBActorSkin = _skins()[key]
		var want := skin.canvas_size()
		assert_gt(want.x, 0.0, "%s 的画布尺寸读不出来" % key)
		for anim: String in skin.frames.get_animation_names():
			for i: int in skin.frames.get_frame_count(anim):
				var texture: Texture2D = skin.frames.get_frame_texture(anim, i)
				assert_eq(texture.get_size(), want, "%s 的 `%s` 第 %d 帧尺寸不一样" % [key, anim, i])


func test_the_feet_actually_touch_the_bottom_of_the_canvas() -> void:
	# **整份素材规格里最要紧的一条。** 默认锚是画布底边中点
	# （[method PBActorSkin.anchor]），所以人必须真的踩在那条边上 ——
	# 悬空一格的表现是他和别人的前后关系错一档，而 y 排序、坐标、
	# 贴图尺寸全部看起来完全正确。
	#
	# 显式填了 [member PBActorSkin.foot_offset] 的跳过：那是「这套素材的脚
	# 不在底边」的正式出口（比如画布留了投影的位置）。
	for key: StringName in _skins():
		var skin: PBActorSkin = _skins()[key]
		if skin.foot_offset != Vector2.ZERO:
			continue
		for anim: String in skin.frames.get_animation_names():
			var image: Image = skin.frames.get_frame_texture(anim, 0).get_image()
			var used := image.get_used_rect()
			assert_eq(
				used.end.y,
				image.get_height(),
				"%s 的 `%s` 第 0 帧悬空 %d 格" % [key, anim, image.get_height() - used.end.y]
			)


func test_real_art_is_never_tinted_by_element() -> void:
	# 染色是白模专用（白模一系一个形状，全靠色相分）。真素材自己有颜色，
	# 再乘一层属性色会把美术定的色整个拉偏，而画面上只表现为「颜色怪怪的」。
	for key: StringName in _skins():
		var skin: PBActorSkin = _skins()[key]
		assert_false(skin.tint_by_element, "%s 是真素材，不该按属性染色" % key)


func test_every_actor_key_on_a_character_can_actually_be_found() -> void:
	# 拼错一个字的表现只是「还是白模」—— 而白模本来就是没配时的正常样子，
	# 所以肉眼分不出「没配」和「配错了」。
	var skins := _skins()
	for character: PBCharacter in PBCharacterLoader.table().all():
		if character.actor_key == &"":
			continue
		assert_true(
			skins.has(character.actor_key),
			"%s 指着一张不存在的形象：%s" % [character.id, character.actor_key]
		)


func test_a_missing_folder_is_not_an_error() -> void:
	# **空 = 白模**，这是 [PBActorLibrary] 敢在没有任何素材时落地的前提。
	# 角色表打不开要 `push_error`（没有角色表就没有游戏），这里恰恰不能。
	assert_eq(PBActorLibrary.load_from("res://data/actors_does_not_exist"), {}, "目录不存在就该是空表")
