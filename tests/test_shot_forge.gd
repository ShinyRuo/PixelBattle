extends GutTest
## 子弹资源的生成、名册的「普攻子弹」列、以及「配给忍者」（[PBShotForge] + [PBRosterSheet]）。
##
## 这一条链上每一处错了都不报错：名册改一格却冲掉了表头注释、配了子弹却只写进名册没写进角色数据、
## 键填错了查不到 —— 屏幕上全都只是「还是白模」。

const ROOT := "user://shot_forge_test"

const SHEET := (
	"# 表头注释，改一格时不能丢\n"
	+ "\n"
	+ "#角色键\t显示名\n"
	+ "alpha_one\tA\tR\t远程\t火\t火\t力量\t1\t1\t1\t1\t1\t1\t1.5\t-\t-\t-\t600\n"
	+ "beta_two\tB\tR\t远程\t火\t火\t力量\t1\t1\t1\t1\t1\t1\t1.5\t-\t-\tkunai\t600\n"
	+ "gamma_three\tC\tR\t远程\t火\t火\t力量\t1\t1\t1\t1\t1\t1\t1.5\t-\t-\n"
)


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute("%s/shots" % ROOT)
	DirAccess.make_dir_recursive_absolute("%s/characters" % ROOT)


func after_all() -> void:
	_wipe(ROOT)


func _sheet() -> PBRosterSheet:
	var sheet := PBRosterSheet.new()
	sheet.lines = SHEET.split("\n")
	return sheet


## 一个目录全指到 `user://` 下的生成器，名册、角色数据、子弹各放一份假的。
func _forge() -> PBShotForge:
	var forge := PBShotForge.new()
	forge.assets_dir = "%s/fx" % ROOT
	forge.data_dir = "%s/shots" % ROOT
	forge.characters_dir = "%s/characters" % ROOT
	forge.roster_path = "%s/roster.tsv" % ROOT
	assert_eq(_sheet().save(forge.roster_path), "", "前提：假名册写得下")
	for id: String in ["alpha_one", "beta_two"]:
		var character := PBCharacter.new()
		character.id = StringName(id)
		ResourceSaver.save(character, "%s/%s.tres" % [forge.characters_dir, id])
	var shot := PBShotSkin.new()
	shot.key = &"fire_ball"
	ResourceSaver.save(shot, forge.shot_path("fire_ball"))
	return forge


func _textures(count: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for _i: int in count:
		out.append(
			ImageTexture.create_from_image(Image.create_empty(8, 8, false, Image.FORMAT_RGBA8))
		)
	return out


# ── 名册的一格 ──────────────────────────────────────────────────


func test_reading_a_cell_finds_the_row_by_id() -> void:
	var sheet := _sheet()
	assert_eq(sheet.cell("beta_two", PBRosterSheet.COL_SHOT), "kunai", "按角色键找行、按列号取格")
	assert_eq(sheet.cell("gamma_three", PBRosterSheet.COL_SHOT), "", "这一行没那么多列就是空串")
	assert_eq(sheet.cell("nobody_here", PBRosterSheet.COL_SHOT), "", "没有这个人也是空串")
	assert_eq(sheet.rows().size(), 3, "注释和空行不算数据行")


func test_setting_a_cell_touches_only_that_cell() -> void:
	var sheet := _sheet()
	assert_eq(sheet.set_cell("alpha_one", PBRosterSheet.COL_SHOT, "fire_ball"), "", "改得动")
	var lines := "\n".join(sheet.lines).split("\n")
	var before := SHEET.split("\n")
	assert_eq(lines.size(), before.size(), "行数不变")
	for i: int in before.size():
		if before[i].begins_with("alpha_one"):
			assert_true(lines[i].ends_with("\t-\t-\tfire_ball\t600"), "只换了普攻子弹那一格：%s" % lines[i])
			assert_eq(lines[i].split("\t").size(), PBRosterSheet.COLUMNS, "列数不变")
		else:
			assert_eq(lines[i], before[i], "别的行（包括注释）原样留着：%s" % before[i])


func test_a_short_row_is_padded_with_nothing() -> void:
	# 补齐的只能是「没有」—— 补成空串的话生成器会把它当成少了一列、整行拒收。
	var sheet := _sheet()
	assert_eq(sheet.set_cell("gamma_three", PBRosterSheet.COL_SHOT, "kunai"), "", "列数不够也改得动")
	var row: PackedStringArray = sheet.rows()[2]
	assert_eq(row.size(), PBRosterSheet.COL_SHOT + 1, "补齐到那一格")
	assert_eq(row[PBRosterSheet.COL_SHOT], "kunai", "那一格是新值")


func test_setting_keeps_a_carriage_return() -> void:
	var sheet := PBRosterSheet.new()
	sheet.lines = PackedStringArray(["alpha_one\tA\r", ""])
	assert_eq(sheet.set_cell("alpha_one", PBRosterSheet.COL_NAME, "Z"), "", "改得动")
	assert_eq(sheet.lines[0], "alpha_one\tZ\r", "CRLF 的名册改完一行还是 CRLF")


func test_setting_an_unknown_id_or_a_tab_is_refused() -> void:
	var sheet := _sheet()
	assert_ne(sheet.set_cell("nobody_here", PBRosterSheet.COL_SHOT, "kunai"), "", "没有这个人要报错")
	assert_ne(sheet.set_cell("alpha_one", PBRosterSheet.COL_SHOT, "a\tb"), "", "值里带 Tab 会多出一列")
	assert_eq("\n".join(sheet.lines), SHEET, "被拒的改动一个字都不许落下")


func test_users_of_lists_who_uses_a_shot() -> void:
	var users := _sheet().users_of(PBRosterSheet.COL_SHOT, "kunai")
	assert_eq(users, PackedStringArray(["beta_two"]), "只有配了这颗子弹的那个人")


func test_a_dash_means_no_shot_and_a_missing_shot_is_an_error() -> void:
	assert_eq(PBRosterSheet.shot_key_of("-"), &"", "`-` 是没配")
	assert_eq(PBRosterSheet.shot_key_of(" kunai "), &"kunai", "去掉首尾空白")
	assert_eq(PBRosterSheet.shot_error("-", ROOT), "", "没配不是错")
	assert_ne(PBRosterSheet.shot_error("no_such_shot", ROOT), "", "填了却找不到要报错")


# ── 真名册 ──────────────────────────────────────────────────────


func test_every_roster_row_has_a_shot_cell_that_resolves() -> void:
	# 生成器那一关只在有人跑它的时候拦；这一条在每次自检里拦。
	var rows := PBRosterSheet.read().rows()
	assert_gt(rows.size(), 0, "前提：名册读得到")
	for row: PackedStringArray in rows:
		assert_eq(row.size(), PBRosterSheet.COLUMNS, "%s 的列数不对" % row[0])
		if row.size() > PBRosterSheet.COL_SHOT:
			assert_eq(
				PBRosterSheet.shot_error(row[PBRosterSheet.COL_SHOT]), "", "%s 的普攻子弹" % row[0]
			)


func test_generated_characters_carry_the_roster_shot() -> void:
	# 名册是真相、`.tres` 是生成出来的。两边对不上 = 改了名册忘了重跑生成器，而屏幕上只是「还是白模」。
	for row: PackedStringArray in PBRosterSheet.read().rows():
		var path: String = "res://data/characters/%s.tres" % row[PBRosterSheet.COL_ID]
		var character := load(path) as PBCharacter
		assert_not_null(character, "角色数据该在：%s" % path)
		if character == null or row.size() <= PBRosterSheet.COL_SHOT:
			continue
		assert_eq(
			character.shot_key,
			PBRosterSheet.shot_key_of(row[PBRosterSheet.COL_SHOT]),
			"%s 的普攻子弹和名册对不上 —— 重跑 make_roster.gd" % row[PBRosterSheet.COL_ID]
		)


# ── 子弹资源 ────────────────────────────────────────────────────


func test_a_key_is_lowercase_words_only() -> void:
	assert_eq(PBShotForge.key_error("fire_ball2"), "", "小写、数字、下划线")
	assert_ne(PBShotForge.key_error(""), "", "空的不行")
	assert_ne(PBShotForge.key_error("Fire Ball"), "", "大写和空格不行（它是目录名也是表里的一格）")


func test_assemble_builds_a_looping_flight_and_a_one_shot_hit() -> void:
	var forge := PBShotForge.new()
	forge.fly_fps = 10.0
	forge.hit_fps = 16.0
	forge.spin = false
	forge.additive_fly = false
	forge.additive_hit = true
	var skin := forge.assemble("kunai", _textures(2), _textures(4))
	assert_eq(skin.key, &"kunai", "键")
	assert_eq(skin.frames.get_frame_count(skin.anim_fly), 2, "飞行段帧数")
	assert_eq(skin.frames.get_frame_count(skin.anim_hit), 4, "命中段帧数")
	assert_true(skin.frames.get_animation_loop(skin.anim_fly), "飞行段循环")
	assert_false(skin.frames.get_animation_loop(skin.anim_hit), "命中段播一遍就收")
	assert_almost_eq(skin.hit_seconds(), 0.25, 0.001, "命中活多久 = 帧数 / 帧率")
	assert_false(skin.frames.has_animation(&"default"), "不留引擎自带的空段")
	assert_almost_eq(skin.pixel_scale, 1.0 / PBShotForge.HD_FACTOR, 0.0001, "高清档缩回屏幕尺寸")
	assert_true(skin.smooth, "高清档平滑过滤")
	assert_false(skin.tint_by_side, "真素材不按敌我染色")
	assert_false(skin.spin, "转不转照填")
	assert_false(skin.additive_for(skin.anim_fly), "飞行段按实体算")
	assert_true(skin.additive_for(skin.anim_hit), "命中段按发光算")


func test_a_shot_may_have_no_hit_segment() -> void:
	# 玩家定的：子弹可以只配飞行段，打中时用默认火花（[method PBShotPool._spark]）。
	var skin := PBShotForge.new().assemble("kunai", _textures(3), [] as Array[Texture2D])
	assert_eq(skin.frames.get_frame_count(skin.anim_fly), 3, "飞行段照装")
	assert_false(skin.has(skin.anim_hit), "没切命中段就没有这一段 —— 不许拿飞行段顶上")


func test_build_refuses_when_frames_are_missing() -> void:
	var forge := _forge()
	assert_ne(forge.build("kunai"), "", "一帧都没切过要报错")
	assert_false(FileAccess.file_exists(forge.shot_path("kunai")), "报错时不留半份资源")


# ── 配给忍者 ────────────────────────────────────────────────────


func test_assign_writes_the_roster_and_the_character() -> void:
	var forge := _forge()
	assert_eq(forge.assign("alpha_one", "fire_ball"), "", "配得上")
	var sheet := PBRosterSheet.read(forge.roster_path)
	assert_eq(sheet.cell("alpha_one", PBRosterSheet.COL_SHOT), "fire_ball", "名册那一格写上了")
	assert_true(sheet.lines[0].begins_with("# 表头注释"), "注释还在")
	var path: String = "%s/alpha_one.tres" % forge.characters_dir
	var character := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBCharacter
	assert_eq(character.shot_key, &"fire_ball", "角色数据也写上了 —— 不重跑生成器就生效")

	assert_eq(forge.assign("alpha_one", ""), "", "取消也走同一条路")
	sheet = PBRosterSheet.read(forge.roster_path)
	assert_eq(sheet.cell("alpha_one", PBRosterSheet.COL_SHOT), PBRosterSheet.NONE, "名册回到 `-`")
	character = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBCharacter
	assert_eq(character.shot_key, &"", "角色回到白模")


func test_assign_refuses_a_shot_that_does_not_exist() -> void:
	var forge := _forge()
	assert_ne(forge.assign("alpha_one", "no_such_shot"), "", "配一颗不存在的子弹要报错")
	var sheet := PBRosterSheet.read(forge.roster_path)
	assert_eq(sheet.cell("alpha_one", PBRosterSheet.COL_SHOT), "-", "被拒时名册不动")


func test_assign_without_generated_character_still_fixes_the_roster() -> void:
	var forge := _forge()
	var err := forge.assign("gamma_three", "fire_ball")
	assert_string_contains(err, "make_roster", "要说清楚得重跑生成器")
	var sheet := PBRosterSheet.read(forge.roster_path)
	assert_eq(sheet.cell("gamma_three", PBRosterSheet.COL_SHOT), "fire_ball", "名册照样写上（它是真相）")


func test_roster_shots_lists_everyone_in_order() -> void:
	var shots := _forge().roster_shots()
	assert_eq(shots.size(), 3, "三个人")
	assert_eq(shots[0]["id"], "alpha_one", "按名册顺序")
	assert_eq(shots[0]["shot"], &"", "没配的是空")
	assert_eq(shots[1]["shot"], &"kunai", "配了的是键")
	assert_eq(shots[2]["shot"], &"", "列数不够的也当没配")


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe("%s/%s" % [dir_path, sub])
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)
