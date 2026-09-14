extends GutTest
## 「战场特效」面板（[PBFxForgePanel] + [PBFxShotPage] + [PBFxSegment] + [PBFxPreview]）和 `addons/` 那层外壳。
##
## 面板里真正点按钮、等编辑器导入那几步只有编辑器里才走得到；这里钉的是不需要编辑器的那几环：
## 建得起来、切得出帧、预览换得上、混合方式跟着背景走。

const ROOT := "user://fx_panel_test"


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	_wipe(ROOT)


## 一张黑底图集：三团亮块，横排，间隔很宽。
func _sheet_file() -> String:
	var image := Image.create_empty(400, 120, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	for x: int in [20, 150, 300]:
		image.fill_rect(Rect2i(x, 40, 40, 30), Color(1.0, 0.6, 0.1))
	var path: String = ProjectSettings.globalize_path("%s/sheet.png" % ROOT)
	image.save_png(path)
	return path


func test_the_plugin_points_at_a_panel_that_exists() -> void:
	# 外壳在 `addons/`，`check.ps1` 不 lint 也不测那一档 —— 路径写错了没有别的关拦得住。
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://addons/fx_forge/plugin.cfg"), OK, "plugin.cfg 要读得进来")
	var script: String = "res://addons/fx_forge/%s" % cfg.get_value("plugin", "script", "")
	assert_true(FileAccess.file_exists(script), "plugin.cfg 指的脚本不存在：%s" % script)
	var shell := FileAccess.get_file_as_string(script)
	assert_true(shell.contains("res://src/tools/fx_forge_panel.gd"), "外壳该 preload src/tools 里那块面板")
	assert_true(
		FileAccess.get_file_as_string("res://project.godot").contains(
			"res://addons/fx_forge/plugin.cfg"
		),
		"project.godot 里没启用这个插件，编辑器底栏不会出现那个按钮"
	)


func test_the_panel_builds_with_a_shot_page() -> void:
	var panel := PBFxForgePanel.new()
	add_child_autofree(panel)
	assert_eq(panel._tabs.get_tab_count(), 1, "现在只有一页")
	assert_eq(panel._tabs.get_tab_title(0), "子弹", "页名就是「子弹」")
	var page := panel._shot_page
	assert_eq(page._fly.anim, PBShotForge.FLY, "上面那段是飞行段")
	assert_eq(page._hit.anim, PBShotForge.HIT, "下面那段是命中段")
	assert_gt(page._ninja_pick.item_count, 0, "忍者下拉框读的是真名册")


func test_a_segment_cuts_frames_and_the_preview_shows_them() -> void:
	var page := PBFxShotPage.new()
	add_child_autofree(page)
	page._fly.use_sheet(_sheet_file())
	var dir: String = "%s/fx/probe" % ROOT
	assert_eq(page._fly.cut(dir), "", "切得开")
	assert_eq(page._fly.images.size(), 3, "三帧")
	assert_true(FileAccess.file_exists("%s/fly_2.png" % dir), "帧写到盘上了")
	assert_eq(page._preview.frame_count(0), 3, "预览马上换上 —— 不等导入")
	assert_true(page._preview.is_additive(0), "黑底按加法混合预览")

	page._fly.use_mode(PBFxForge.Mode.KEY)
	assert_false(page._fly.additive(), "洋红底就不是加法")
	assert_false(page._preview.is_additive(0), "预览跟着换")


func test_a_wrong_frame_count_is_refused() -> void:
	var page := PBFxShotPage.new()
	add_child_autofree(page)
	page._fly.use_sheet(_sheet_file())
	page._fly._frames.value = 4
	assert_ne(page._fly.cut("%s/fx/probe" % ROOT), "", "图上三帧、说要四帧，要报错")
	assert_true(page._fly.images.is_empty(), "报错时不换预览")


func test_reading_back_frames_from_disk() -> void:
	var page := PBFxShotPage.new()
	add_child_autofree(page)
	page._fly.use_sheet(_sheet_file())
	var dir: String = "%s/fx/probe" % ROOT
	assert_eq(page._fly.cut(dir), "", "前提：切得开")
	page._fly.images = []
	assert_eq(page._fly.load_from(dir), 3, "从盘上读回三帧")
	assert_eq(page._hit.load_from(dir), 0, "没切过的那段是零帧，不报错")


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe("%s/%s" % [dir_path, sub])
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)
