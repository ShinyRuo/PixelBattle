extends GutTest
## 特效图集切分（[PBFxForge]）。
##
## 切歪、抠错都不报错：光晕被裁掉一圈、边缘渗粉、爆炸每一帧一样大，看起来都只是「特效有点丑」。

const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const MAGENTA := Color(1.0, 0.0, 1.0, 1.0)
const GLOW := Color(1.0, 0.6, 0.1, 1.0)


## 一张图集：每个矩形画一个实心块，[param halo] 为真时再在四周套一圈暗淡的光晕。
func _sheet(ground: Color, cells: Array, halo: bool = false) -> Image:
	var image := Image.create_empty(400, 120, false, Image.FORMAT_RGBA8)
	image.fill(ground)
	for cell: Rect2i in cells:
		if halo:
			image.fill_rect(cell.grow(4), Color(0.15, 0.09, 0.02, 1.0))
		image.fill_rect(cell, GLOW)
	return image


## 三块，大小不一。每块都不小于 [constant PBSheetCutter.DEFAULT_CELL]，否则会被当成噪点丢掉。
func _three() -> Array:
	return [Rect2i(20, 30, 26, 26), Rect2i(150, 20, 40, 60), Rect2i(300, 40, 30, 30)]


# ── 抠图 ─────────────────────────────────────────────────────────


func test_dark_to_alpha_turns_brightness_into_opacity() -> void:
	var image := Image.create_empty(3, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, BLACK)
	image.set_pixel(1, 0, Color8(200, 100, 0))
	image.set_pixel(2, 0, Color.WHITE)
	PBFxForge.dark_to_alpha(image)
	assert_eq(image.get_pixel(0, 0).a8, 0, "纯黑就是背景")
	var glow := image.get_pixel(1, 0)
	assert_eq(glow.a8, 200, "透明度取最亮的那个通道")
	assert_eq(glow.r8, 255, "颜色除回来")
	assert_almost_eq(glow.g8, 127, 1, "颜色按同一个比例除回来")
	assert_eq(image.get_pixel(2, 0).a8, 255, "纯白完全不透明")


func test_near_black_noise_counts_as_background() -> void:
	# 出图模型的「纯黑」常带几级噪点，不算背景的话整张图都是一格。
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color8(6, 5, 7))
	PBFxForge.dark_to_alpha(image)
	assert_eq(image.get_pixel(0, 0).a8, 0, "低于门槛的暗噪点该透明")


func test_additive_blend_of_the_result_matches_the_black_sheet() -> void:
	# 加法混合叠上去 = 颜色 × 透明度，要和原来黑底上的颜色一致。
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var source := Color8(180, 90, 30)
	image.set_pixel(0, 0, source)
	PBFxForge.dark_to_alpha(image)
	var pixel := image.get_pixel(0, 0)
	assert_almost_eq(pixel.r * pixel.a, source.r, 0.01, "红")
	assert_almost_eq(pixel.g * pixel.a, source.g, 0.01, "绿")
	assert_almost_eq(pixel.b * pixel.a, source.b, 0.01, "蓝")


# ── 切格与摆齐 ────────────────────────────────────────────────────


func test_a_black_sheet_cuts_into_its_frames_in_order() -> void:
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three()), PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER
	)
	assert_eq(frames.size(), 3, "三块该切出三帧")


func test_every_frame_shares_one_canvas() -> void:
	# 各自一个画布的话，一个扩散的爆炸每一帧都一样大。
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three()), PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER
	)
	assert_eq(frames.size(), 3, "先得切出三帧")
	for frame: Image in frames:
		assert_eq(frame.get_size(), frames[1].get_size(), "每一帧同一个画布")
	var small := frames[0].get_used_rect()
	assert_lt(small.size.x, frames[1].get_used_rect().size.x, "小的那一帧在画布里仍然是小的")


func test_center_anchor_puts_the_content_in_the_middle() -> void:
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three()), PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER
	)
	var used := frames[0].get_used_rect()
	var mid := Vector2(frames[0].get_size()) * 0.5
	assert_almost_eq(Vector2(used.get_center()).x, mid.x, 1.0, "横向居中")
	assert_almost_eq(Vector2(used.get_center()).y, mid.y, 1.0, "纵向居中")


func test_bottom_anchor_seats_the_content_on_the_bottom_edge() -> void:
	# 立起来的爆发（落雷、土刺）从地面长出来，底边要贴着画布底。
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three()), PBFxForge.Mode.DARK, PBFxForge.Anchor.BOTTOM
	)
	var used := frames[0].get_used_rect()
	assert_eq(used.end.y, frames[0].get_height(), "底边贴着画布底")


func test_a_dim_halo_is_kept_not_cropped() -> void:
	# 切格的门槛要够低，否则光晕的外圈会被切出来的矩形裁掉。
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three(), true), PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER
	)
	assert_eq(frames.size(), 3, "带光晕照样切出三帧")
	assert_eq(frames[1].get_used_rect().size, Vector2i(48, 68), "光晕那一圈要在帧里")


func test_size_scales_the_long_side_and_keeps_it_even() -> void:
	var frames := PBFxForge.new().slice(
		_sheet(BLACK, _three()), PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER, 31
	)
	var size := frames[0].get_size()
	assert_eq(maxi(size.x, size.y), 32, "长边缩到要的尺寸（凑成偶数）")
	assert_eq(size.x % 2, 0, "宽是偶数")
	assert_eq(size.y % 2, 0, "高是偶数")


func test_a_magenta_sheet_keys_out_to_transparency() -> void:
	var frames := PBFxForge.new().slice(
		_sheet(MAGENTA, _three()), PBFxForge.Mode.KEY, PBFxForge.Anchor.CENTER
	)
	assert_eq(frames.size(), 3, "洋红底也切出三帧")
	var corner := frames[0].get_pixel(0, 0)
	assert_eq(corner.a8, 0, "小的那一帧四周是背景，该透明")
	var body := frames[1].get_pixel(frames[1].get_width() / 2, frames[1].get_height() / 2)
	assert_eq(body.a8, 255, "实体不透明")
	assert_almost_eq(body.b8, 26, 2, "实体颜色没被洋红染过")


func test_soft_key_clears_the_background_and_keeps_a_solid_object() -> void:
	var image := Image.create_empty(2, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, MAGENTA)
	image.set_pixel(1, 0, Color8(60, 60, 60))
	PBFxForge.soft_key(image, MAGENTA)
	assert_eq(image.get_pixel(0, 0).a8, 0, "纯洋红全透明")
	var solid := image.get_pixel(1, 0)
	assert_eq(solid.a8, 255, "暗灰色的物体实心")
	assert_eq(solid.r8, 60, "颜色原样")


func test_soft_key_turns_a_magenta_edge_back_into_the_object_colour() -> void:
	# 实测的紫边：边缘那一圈是「灰 × 一半 + 洋红 × 一半」，二值抠图把它们全留下来、alpha 拉满。
	var grey := Color8(70, 70, 70)
	var image := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, grey.lerp(MAGENTA, 0.5))
	PBFxForge.soft_key(image, MAGENTA)
	PBFxForge.unpremultiply(image)
	var edge := image.get_pixel(0, 0)
	assert_between(edge.a8, 60, 200, "边缘是半透明的")
	assert_almost_eq(edge.r8, edge.g8, 12, "红和绿差不多 —— 洋红减回去了")
	assert_almost_eq(edge.b8, edge.g8, 12, "蓝和绿差不多")


func test_slicing_does_not_touch_the_input() -> void:
	var sheet := _sheet(BLACK, _three())
	var before := sheet.get_pixel(5, 5)
	PBFxForge.new().slice(sheet, PBFxForge.Mode.DARK, PBFxForge.Anchor.CENTER)
	assert_eq(sheet.get_pixel(5, 5), before, "原图不该被改")
	assert_eq(sheet.get_pixel(5, 5).a8, 255, "原图还是不透明的黑底")
