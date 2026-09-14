extends GutTest
## 敌人子弹表（`data/enemy_shots.tsv`）的写与读：
## 面板配给某一种敌人（[method PBShotForge.assign_enemy]），渲染层查（[PBEnemyShotTable]）。
##
## 错了都不报错：改一格把注释弄丢、给不开枪的近战怪配上子弹、配了一颗不存在的子弹（游戏里退回白模）。

const ROOT := "user://enemy_shots_test"


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute("%s/shots" % ROOT)


func after_all() -> void:
	_wipe(ROOT)


func _forge() -> PBShotForge:
	var forge := PBShotForge.new()
	forge.data_dir = "%s/shots" % ROOT
	var shot := PBShotSkin.new()
	shot.key = &"fire_ball"
	ResourceSaver.save(shot, forge.shot_path("fire_ball"))
	return forge


func test_assign_enemy_writes_only_that_cell_of_the_enemy_table() -> void:
	var forge := _forge()
	forge.enemy_table_path = "%s/enemy_shots.tsv" % ROOT
	var file := FileAccess.open(forge.enemy_table_path, FileAccess.WRITE)
	file.store_string("# 注释留着\nenemy_fire_ranged\t-\nenemy_fire_boss\t-\n")
	file.close()
	assert_eq(forge.assign_enemy("enemy_fire_boss", "fire_ball"), "", "配得上")
	var sheet := PBRosterSheet.read(forge.enemy_table_path)
	assert_eq(sheet.cell("enemy_fire_boss", 1), "fire_ball", "那一格写上了")
	assert_eq(sheet.cell("enemy_fire_ranged", 1), "-", "别的不动")
	assert_true(sheet.lines[0].begins_with("# 注释留着"), "注释还在")
	var read := PBEnemyShotTable.load_from(forge.enemy_table_path)
	assert_eq(read, {&"enemy_fire_boss": &"fire_ball"}, "读回来只收配了的")
	assert_ne(forge.assign_enemy("enemy_fire_boss", "no_such_shot"), "", "不存在的子弹要拦")
	assert_ne(forge.assign_enemy("enemy_fire_melee", "fire_ball"), "", "表里没有的那一种要拦（近战不开枪）")
	assert_eq(forge.assign_enemy("enemy_fire_boss", ""), "", "取消也走同一条路")
	assert_eq(PBRosterSheet.read(forge.enemy_table_path).cell("enemy_fire_boss", 1), "-", "回到 `-`")
	var names: Array = forge.enemy_shots().map(func(one: Dictionary) -> String: return one["name"])
	assert_eq(names, ["火 · 远程小怪", "火 · BOSS"], "下拉框里是人话，按表里的顺序")


func test_a_missing_table_reads_as_all_white() -> void:
	assert_eq(PBEnemyShotTable.load_from("%s/no_such.tsv" % ROOT), {}, "表不在就是一张空表，不报错")


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe("%s/%s" % [dir_path, sub])
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)
