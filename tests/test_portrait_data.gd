extends GutTest
## `assets/portraits/` 里那三十张卡面头像，以及切图那条流水线。M9-g。
##
## 和 `test_actor_data.gd` 同一路子：**规格里写着的那几条，能用机器验的
## 就别靠人看**。这一份钉的全是「不报错」的那一类：
##
## - 尺寸不齐 —— 头像在格子里错位一圈，而两个数看起来都很正常
## - [member PBCharacter.icon_key] 带一个点 —— `get_basename()` 会把
##   `char.asuma` 截成 `char`，三十张一张都装不上
## - 拼错 —— 表现只是「还是白模卡面」
## - 网格按等分切 —— 切进邻格的头发里，而画布、坐标全都正确

const DIR := "res://assets/portraits"
const CHARACTERS := "res://data/characters"


func before_each() -> void:
	PBPortraitLibrary.reload()


func after_all() -> void:
	PBPortraitLibrary.reload()


func _portraits() -> Dictionary:
	return PBPortraitLibrary.load_from(DIR)


func test_a_missing_folder_is_not_an_error() -> void:
	# **空 = 白模卡面。** 这是整条链路敢在美术还没齐的时候落地的前提，
	# 和 [PBActorLibrary] 顶上那条一模一样。
	var none := PBPortraitLibrary.load_from("res://assets/没有这个目录")
	assert_eq(none.size(), 0, "目录不存在该返回空表，不是报错")


func test_every_portrait_is_the_size_the_card_expects() -> void:
	# 尺寸从 [constant PBUnitTile.TILE_SIZE] 推出来（[method
	# PBPortraitForge.texture_size]），所以这条同时钉住「卡面格子改了尺寸、
	# 头像没跟上」那一档。
	var want := PBPortraitForge.texture_size()
	var found := _portraits()
	assert_gt(found.size(), 0, "assets/portraits/ 里该有头像")
	for key: String in found:
		var texture: Texture2D = found[key]
		assert_eq(texture.get_size(), Vector2(want), "%s 的尺寸该是 %s" % [key, want])


func test_the_texture_is_three_times_what_it_draws_at() -> void:
	# 高清档：贴图是屏幕尺寸的 3 倍，缩小交给 GPU（M6-m 那条，头像沿用）。
	# 写死 78×90 的话，卡面改一次大小这里就悄悄错了。
	var body: Vector2 = PBUnitTile.TILE_SIZE - Vector2(4.0, 4.0)
	assert_eq(
		PBPortraitForge.texture_size(),
		Vector2i(int(body.x), int(body.y)) * PBPortraitForge.SCALE_UP,
		"成品尺寸该正好是卡面那块地方的 SCALE_UP 倍"
	)


func test_every_icon_key_can_actually_be_found() -> void:
	# 拼错的表现只是「还是白模卡面」—— 没有任何一处会报错。
	var dir := DirAccess.open(CHARACTERS)
	assert_not_null(dir, "角色目录该打得开")
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var character := load("%s/%s" % [CHARACTERS, file_name]) as PBCharacter
		assert_not_null(character, "%s 该是一个角色" % file_name)
		assert_ne(character.icon_key, "", "%s 的 icon_key 不能是空的" % file_name)
		assert_true(
			_portraits().has(character.icon_key),
			"%s 的 icon_key「%s」在 assets/portraits/ 里查不到" % [file_name, character.icon_key]
		)


func test_an_icon_key_can_be_used_as_a_file_name() -> void:
	# **它就是文件名**（`assets/portraits/<键>.png`）。带点的那份
	# （M9-g 之前是 `char.<id>`）会被 `get_basename()` 截断，
	# 于是三十张一张都装不上 —— 而库那边只会安静地返回空表。
	var dir := DirAccess.open(CHARACTERS)
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var character := load("%s/%s" % [CHARACTERS, file_name]) as PBCharacter
		assert_false(character.icon_key.contains("."), "icon_key 里不能有点：%s" % character.icon_key)
		assert_eq(
			character.icon_key.get_basename(),
			character.icon_key,
			"icon_key 当文件名用，截出来必须是它自己"
		)


func _tile() -> PBUnitTile:
	var tile := PBUnitTile.new()
	add_child_autofree(tile)
	return tile


## 一张**真表里的**卡。
##
## **不能走 [method PBUnit.of]** —— [member PBSimConfig.characters] 默认是
## [method PBCharacterTable.synthetic] 造的合成表，那批角色的 `icon_key`
## 是编出来的，`assets/portraits/` 里当然查不到。用它测的话这条永远是绿的
## （查不到 → 返回 null → 断言写成「该是 null」也能通过），而它什么都没测。
## [param ring_only] 为真时只挑克制环上的（不要物理）—— 物理不参与克制，
## 拿它去测「被克压暗」的话那一档根本不成立。
func _real_card(ring_only: bool = false) -> PBUnit:
	var dir := DirAccess.open(CHARACTERS)
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var character := load("%s/%s" % [CHARACTERS, file_name]) as PBCharacter
		if character == null or not _portraits().has(character.icon_key):
			continue
		if ring_only and not PBElement.RING.has(int(character.element)):
			continue
		return PBUnit.new(character)
	return null


func test_the_card_wears_the_portrait_and_takes_it_off_again() -> void:
	var card := _real_card()
	assert_not_null(card, "角色表里该有至少一个接了头像的人")
	var tile := _tile()
	tile.set_unit(card, card.element)
	assert_not_null(PBUnitTile.face_of(card), "有素材的角色该拿得到一张头像")
	tile.clear()
	# 空位不擦头像的话，仓库滚动时上一个人的脸会留在空格子里 ——
	# 而格子里没有卡，点也点不动。
	assert_null(PBUnitTile.face_of(null), "没有卡就没有头像")


func test_a_countered_card_dims_the_portrait_too() -> void:
	# §03 最值钱的那一格信息：这张卡这一波是废的。M9-g 之前它只压底色，
	# 而底色接了素材之后整个被头像盖住 —— 那条信息会静默消失。
	var card := _real_card(true)
	assert_not_null(card, "角色表里该有至少一个接了头像、且在克制环上的人")
	var beats := PBElement.counter_of(card.element)
	var tile := _tile()
	tile.set_unit(card, beats)
	assert_eq(
		PBElement.relation(card.element, beats),
		PBElement.Relation.WEAK,
		"前提：拿一个克制得了他的波次属性"
	)
	var faces: Array[TextureRect] = []
	for child: Node in tile.get_children():
		if child is TextureRect:
			faces.append(child as TextureRect)
	assert_eq(faces.size(), 1, "卡面上该只有一层头像")
	assert_eq(faces[0].modulate, PBUnitTile.WEAK_DIM, "被克的那一档头像也要压暗")


func test_the_grid_is_measured_not_divided() -> void:
	# 出图模型画的格线会飘：实测同一张 4096 见方的表，五行分别是
	# 800 / 804 / 901 / 855 / 666 像素高。所以这里造一张**行高故意不等**的假表，
	# 按等分切的话第二行会切错，而 [method PBPortraitForge.grid] 该量出真值。
	var image := Image.create_empty(40, 40, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.0, 1.0))
	for x: int in 40:
		for y: int in range(10, 12):
			image.set_pixel(x, y, Color.BLACK)
	for y: int in 40:
		image.set_pixel(20, y, Color.BLACK)

	var grid := PBPortraitForge.new().grid(image)
	assert_eq(grid["cols"].size(), 2, "一条竖线该切出两列")
	assert_eq(grid["rows"].size(), 2, "一条横线该切出两行")
	assert_eq(grid["rows"][0], Vector2i(0, 10), "第一行是 0..9，高 10 —— 不是等分的 20")
	assert_eq(grid["rows"][1], Vector2i(12, 28), "第二行从格线之后开始")
	assert_eq(grid["cols"][0], Vector2i(0, 20), "第一列该停在竖线前")
