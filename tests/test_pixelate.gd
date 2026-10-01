extends GutTest
## 降采样流水线（[PBPixelate]）。M6-p。
##
## 钉的全是「错了也不报错」的那几条：倍数取整、边缘不留半透明、
## 背景还是纯洋红（否则 [PBActorForge] 那一趟抠不干净）、放大是整数倍。

const SIZE: int = 240
const KEY := Color(1.0, 0.0, 1.0)


## 造一张洋红底、中间一块渐变方块的测试图。
func _source(width: int = SIZE, height: int = SIZE) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(KEY)
	for y: int in range(height / 4, height * 3 / 4):
		for x: int in range(width / 4, width * 3 / 4):
			image.set_pixel(x, y, Color(float(x) / float(width), float(y) / float(height), 0.4))
	return image


func test_factor_is_an_integer() -> void:
	var forge := PBPixelate.new()
	forge.height = 96
	assert_eq(forge.factor(1024), 11, "1024 配 96 应该取整成 11 倍")
	forge.height = 60
	assert_eq(forge.factor(240), 4, "240 配 60 正好 4 倍")
	forge.height = 5000
	assert_eq(forge.factor(240), 1, "目标比原图还大时不放大，退回 1 倍")


func test_small_and_big_line_up() -> void:
	var forge := PBPixelate.new()
	forge.height = 60
	var made := forge.run(_source())
	var small: Image = made["small"]
	var big: Image = made["big"]
	assert_eq(small.get_height(), 60, "小图应该正好是目标高度")
	assert_eq(big.get_width(), small.get_width() * int(made["factor"]), "放大必须是整数倍")
	assert_eq(big.get_height(), small.get_height() * int(made["factor"]), "放大必须是整数倍")


## 半透明边缘留着的话，盖回洋红上就是一圈粉边，而 alpha 看起来完全正常。
func test_no_half_transparent_edges() -> void:
	var forge := PBPixelate.new()
	forge.height = 60
	var small: Image = forge.run(_source())["small"]
	for y: int in small.get_height():
		for x: int in small.get_width():
			assert_almost_eq(small.get_pixel(x, y).a, 1.0, 0.001, "第 %d,%d 格还是半透明" % [x, y])


## 背景必须还是**纯**洋红：[PBActorForge] 那一趟按颜色抠它，
## 偏一点点就抠不干净，而那时图看起来完全正常。
func test_background_stays_pure_magenta() -> void:
	var forge := PBPixelate.new()
	forge.height = 60
	var small: Image = forge.run(_source())["small"]
	var corner := small.get_pixel(1, 1)
	assert_almost_eq(corner.r, 1.0, 0.02, "背景红通道跑了")
	assert_almost_eq(corner.g, 0.0, 0.02, "背景绿通道跑了")
	assert_almost_eq(corner.b, 1.0, 0.02, "背景蓝通道跑了")


func test_palette_is_capped() -> void:
	var forge := PBPixelate.new()
	forge.height = 60
	forge.colors = 8
	var small: Image = forge.run(_source())["small"]
	var seen: Dictionary = {}
	for y: int in small.get_height():
		for x: int in small.get_width():
			var c := small.get_pixel(x, y)
			seen[(int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)] = true
	assert_lte(seen.size(), 8, "压到 8 色之后不该还有 %d 种颜色" % seen.size())


## 不压色那一档要真的不压 —— 渐变方块降下来必然多于 8 种颜色。
func test_no_quantize_keeps_colors() -> void:
	var forge := PBPixelate.new()
	forge.height = 60
	forge.colors = 0
	var small: Image = forge.run(_source())["small"]
	var seen: Dictionary = {}
	for y: int in small.get_height():
		for x: int in small.get_width():
			var c := small.get_pixel(x, y)
			seen[(int(c.r * 255.0) << 16) | (int(c.g * 255.0) << 8) | int(c.b * 255.0)] = true
	assert_gt(seen.size(), 8, "关掉压色之后颜色数不该只剩 %d 种" % seen.size())


## 插件外壳里那句 preload 拼错了不报错，只表现为「底栏那块面板是空的」。
func test_plugin_shell_points_at_the_panel() -> void:
	var shell := FileAccess.get_file_as_string("res://addons/pixelate/plugin.gd")
	assert_true(shell.contains("res://src/tools/pixelate_panel.gd"), "插件外壳没指向 src/ 里的面板本体")
	assert_true(ResourceLoader.exists("res://src/tools/pixelate_panel.gd"), "面板本体不在")
