extends GutTest
## 图集切分（[PBSheetCutter]）。M8-f。
##
## ## 为什么这几条值得测
##
## 切歪了**不报错**：每一格看起来都很正常（一个人站在透明底上），
## 而下游 [PBActorForge] 全靠 [method Image.get_used_rect] 量人 ——
## 一格里混进半个邻居，包围盒就把两个人一起框住，于是那一帧的「人」
## 有两个头，缩放比、画布、脚底中点跟着全错，**而画面上只是「这个角色怎么变矮了」**。
##
## 这里守的三件事：切得出几格、**顺序对不对**（播放顺序就是这个顺序）、
## 以及「至少空多少」那个阈值两头的行为。

const MAGENTA := Color(1.0, 0.0, 1.0, 1.0)
const BODY := Color(0.2, 0.4, 0.8, 1.0)


## 造一张洋红底的假图集，[param cells] 里每个矩形画一个实心块。
##
## **故意不做成等分网格** —— 真图集就不是（实测 `attack` 那张最左一格
## 贴着画面左边，`dead` 那张上下两排中间空了三分之一）。
func _sheet(size: Vector2i, cells: Array) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(MAGENTA)
	for cell: Rect2i in cells:
		image.fill_rect(cell, BODY)
	return image


## 六块，两行三列，间距**不均匀**：上排靠左挤、下排靠右散，两排之间空得多。
func _six() -> Array:
	return [
		Rect2i(10, 10, 40, 60),
		Rect2i(90, 10, 40, 60),
		Rect2i(230, 10, 40, 60),
		Rect2i(20, 200, 40, 60),
		Rect2i(120, 200, 40, 60),
		Rect2i(240, 200, 40, 60),
	]


func test_it_finds_all_six_cells_on_an_uneven_grid() -> void:
	# **不能按「平均切成 2×3」做**：模型不给等分网格，平均切的话
	# 格子边界会从人物身上穿过去。
	var image := _sheet(Vector2i(300, 280), _six())
	PBSheetCutter.key_out(image)
	var cells := PBSheetCutter.cut(image)
	assert_eq(cells.size(), 6, "六块该切出六格，实际 %s" % str(cells))


func test_the_cells_come_out_in_reading_order() -> void:
	# **顺序就是播放顺序**（提示词里写的是「从左到右、从上到下」）。
	# 乱了的话 `attack` 段的第 0 帧就不是打出去那一下，
	# 游戏里表现为「先掉血、后挥手」。
	var image := _sheet(Vector2i(300, 280), _six())
	PBSheetCutter.key_out(image)
	var cells := PBSheetCutter.cut(image)
	assert_eq(cells.size(), 6, "先得切出六格")
	# 前三格在上排、后三格在下排；每一排内部按 x 递增。
	for i: int in 3:
		assert_lt(cells[i].position.y, cells[3].position.y, "第 %d 格该在上排" % i)
	for i: int in [0, 1, 3, 4]:
		assert_lt(cells[i].position.x, cells[i + 1].position.x, "第 %d 格该在下一格左边" % i)


func test_each_cell_holds_exactly_one_block() -> void:
	# 一格里混进半个邻居的话，包围盒会把两个人一起框住 —— 而每一帧
	# 看起来都还是「一个人站在透明底上」。
	var image := _sheet(Vector2i(300, 280), _six())
	PBSheetCutter.key_out(image)
	for cell: Rect2i in PBSheetCutter.cut(image):
		var one := image.get_region(cell)
		var used := one.get_used_rect()
		assert_eq(used.size, Vector2i(40, 60), "每一格里该正好是一个 40×60 的块")


func test_a_gap_smaller_than_the_threshold_keeps_one_figure_whole() -> void:
	# **出拳那一格的特效常常和身体断开一小截**（实测：手前方的电光）。
	# 阈值太小就会把它切成两格 —— 于是「一个人」变成「一个人 + 一道光」，
	# 而那道光会被当成独立的一帧量进去。
	# **两块都要大过 [constant PBSheetCutter.DEFAULT_CELL]**，否则小的那块
	# 会被当成噪点丢掉 —— 那样这两条断言测的就不是「合不合并」了。
	var image := _sheet(
		Vector2i(200, 100), [Rect2i(20, 20, 40, 60), Rect2i(70, 25, 30, 40)]
	)
	PBSheetCutter.key_out(image)
	# 两块之间空 10 像素：阈值 24（默认）应当把它们并成一格。
	assert_eq(PBSheetCutter.cut(image).size(), 1, "空 10 像素、阈值 24 —— 该并成一格")
	# 阈值调到 4 就该断开，这正是面板上那个滑块的两头。
	assert_eq(PBSheetCutter.cut(image, 4).size(), 2, "阈值调小就该切成两格")


func test_a_background_that_is_not_pure_magenta_still_cuts() -> void:
	# **玩家实际踩到的那条**（M8-f）：GPT Image 出的图集背景不是 `#FF00FF`，
	# 实测在 `#df2eda` 附近、离纯洋红 **0.263**，还带着噪点。
	# 拿纯洋红加 0.20 的容差去抠**一个像素都抠不掉** —— 投影全满、
	# 整张图被切成一格，而屏幕上只是「切图按钮好像没反应」。
	var off := Color8(223, 46, 218)
	assert_gt(
		Vector3(off.r, off.g, off.b).distance_to(Vector3(1.0, 0.0, 1.0)),
		PBSheetCutter.DEFAULT_TOL,
		"这个夹具的底色必须真的落在容差外，否则这条测的就不是那件事"
	)
	var image := Image.create_empty(300, 280, false, Image.FORMAT_RGBA8)
	image.fill(off)
	# 背景带一点噪点，和真图一样。
	for i: int in 400:
		image.set_pixel(
			(i * 7919) % 300, (i * 104729) % 280, Color8(223 + (i % 7) - 3, 46 + (i % 5) - 2, 218)
		)
	for cell: Rect2i in _six():
		image.fill_rect(cell, BODY)

	# 拿写死的纯洋红去抠 —— 抠不掉，于是只剩一格（这正是玩家看到的）。
	var wrong := image.duplicate() as Image
	PBSheetCutter.key_out(wrong)
	assert_lt(PBSheetCutter.cut(wrong).size(), 6, "写死纯洋红时本来就切不开，这条钉的是根因")

	# 量出来的底色才是对的中心。
	var key := PBSheetCutter.guess_key(image)
	assert_almost_eq(key.r, off.r, 0.02, "量出来的红分量该贴着真底色")
	assert_almost_eq(key.g, off.g, 0.02, "绿分量")
	assert_almost_eq(key.b, off.b, 0.02, "蓝分量")
	PBSheetCutter.key_out(image, key)
	assert_eq(PBSheetCutter.cut(image).size(), 6, "以真底色为心，容差照旧 0.20 就切得开")


func test_guessing_ignores_pixels_that_are_already_transparent() -> void:
	# 重切一张已经切过的图时，背景已经是透明的了 —— 那些像素不该参与投票，
	# 否则众数会变成「透明」，而 [method PBSheetCutter.key_out] 会拿它当底色，
	# 把人物整个抠掉。
	var image := Image.create_empty(120, 120, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(10, 10, 60, 60), BODY)
	var key := PBSheetCutter.guess_key(image)
	assert_almost_eq(key.b, BODY.b, 0.03, "只剩人物时，众数就该是人物的颜色")


func test_keying_out_leaves_a_hard_alpha() -> void:
	# 下游 [method PBActorForge.compose] 假设源帧是**预乘**过的：
	# 透明像素的 RGB 必须是 0，否则缩放会把洋红渗进人物边缘，
	# **而 alpha 看起来完全正常**。
	var image := _sheet(Vector2i(60, 60), [Rect2i(10, 10, 20, 20)])
	PBSheetCutter.key_out(image)
	var back := image.get_pixel(2, 2)
	assert_eq(back.a, 0.0, "背景要全透明")
	assert_eq(Vector3(back.r, back.g, back.b), Vector3.ZERO, "透明像素的 RGB 也要归零（预乘）")
	var body := image.get_pixel(20, 20)
	assert_eq(body.a, 1.0, "人身上要不透明")
	assert_eq(image.get_used_rect(), Rect2i(10, 10, 20, 20), "抠完之后包围盒就是那个块")


func test_an_empty_sheet_cuts_into_nothing() -> void:
	# 整张全是背景色时不许返回一个「整张图那么大的格子」——
	# 那一格会被当成一帧写盘，而它是空的。
	var image := _sheet(Vector2i(80, 80), [])
	PBSheetCutter.key_out(image)
	assert_true(PBSheetCutter.cut(image).is_empty(), "空图不该切出格子")


func test_stray_pixels_do_not_glue_two_cells_together() -> void:
	# AI 出的图边缘常留几个孤立像素。按「非空 = 有一个前景像素」算的话，
	# 它们会把本来分开的两格连成一格 —— [constant PBSheetCutter.FLOOR] 挡的就是这个。
	var image := _sheet(Vector2i(200, 100), [Rect2i(20, 20, 40, 40), Rect2i(140, 20, 40, 40)])
	# 在两格中间的空白带上点两个孤立像素。
	image.set_pixel(100, 40, BODY)
	image.set_pixel(101, 70, BODY)
	PBSheetCutter.key_out(image)
	assert_eq(PBSheetCutter.cut(image).size(), 2, "两个杂点不该把两格粘成一格")
