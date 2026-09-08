extends GutTest
## 中间帧上的人工擦除（[PBFrameTouch]）。M6-r。
##
## ## 为什么这几条值得测
##
## 擦除本身在屏幕上是看得见的（涂哪儿哪儿没了），**它的三个后果看不见**：
## 包围盒有没有真的收回人身上、撤销是不是逐位还原、
## 「套到整段」重放出来的和手擦的是不是同一张图。
## 三样错了都不报错 —— 表现是某一段的画布比别的段宽一点点，
## 而画布取的是各段最大值，于是全套素材跟着那一帧一起变胖。

const ROOT := "user://touch_test"


func before_each() -> void:
	_wipe(ROOT)
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	_wipe(ROOT)


## 造一帧「带地面阴影的素材」：人在左边，脚下一条横贯全图的黑线。
##
## **人故意不居中**（30..50，中点 40），而黑线的中点是 100 ——
## 两个数一样的话「脚底中点被黑影带偏了」这条就量不出来。
func _fake_frame(path: String) -> void:
	var image := Image.create_empty(200, 120, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.fill_rect(Rect2i(30, 20, 20, 80), Color(0.8, 0.5, 0.3, 1.0))
	image.fill_rect(Rect2i(0, 104, 200, 3), Color(0.1, 0.1, 0.1, 1.0))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe("%s/%s" % [dir_path, sub])
	for file_name: String in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(dir_path)


func test_wiping_the_shadow_brings_the_bounding_box_back_to_the_body() -> void:
	# **这是整个功能的正题。** 流水线量人全靠 [method Image.get_used_rect]，
	# 而一条横贯全图的地面阴影会同时弄坏三件事：脚底中点跑到画面正中、
	# 画布撑到半个屏幕、地面线落在黑影上（人因此悬空）。
	#
	# 三样都不报错 —— 出来的图只是「这个角色怎么又偏又扁」。
	var forge := PBActorForge.new()
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var before := forge.measure_one(path)
	assert_eq((before["used"] as Rect2i).size.x, 200, "黑影横贯，包围盒该是整张图那么宽")
	assert_almost_eq(float(before["feet_x"]), 100.0, 2.0, "脚底中点该被黑影拽到画面正中")

	var touch := PBFrameTouch.new()
	assert_eq(touch.open(path, []), "", "打得开这一帧")
	touch.wipe(Rect2i(0, 102, 200, 18))
	assert_eq(touch.save(), "", "写得回中间帧")

	var after := forge.measure_one(path)
	assert_eq((after["used"] as Rect2i).size.x, 20, "擦掉之后包围盒只该框住人")
	assert_almost_eq(float(after["feet_x"]), 40.0, 1.0, "脚底中点该回到人身上")


func test_undo_puts_back_exactly_what_the_stroke_took() -> void:
	# 撤销走的是「原图重放前 n-1 笔」，不是「把擦掉的像素记下来再画回去」——
	# 后者要存一份反向补丁，而它和正向那份迟早对不上。
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var touch := PBFrameTouch.new()
	assert_eq(touch.open(path, []), "", "打得开")
	var was := touch.image().get_data()
	touch.dab(Vector2i(40, 60), 10)
	assert_ne(touch.image().get_data(), was, "涂了一笔就该不一样")
	touch.undo()
	assert_eq(touch.image().get_data(), was, "撤销之后必须逐位回到原样")


func test_replaying_marks_matches_erasing_by_hand() -> void:
	# 「套到整段」把同一串笔迹重放到 97 帧上，而人只在其中一帧上手擦过。
	# 两条路出的图必须逐位相同 —— 差一个像素的表现是那一帧的包围盒
	# 比别的帧宽一点点，而画布取的是各段最大值。
	var one: String = "%s/a.png" % ROOT
	var two: String = "%s/b.png" % ROOT
	_fake_frame(one)
	_fake_frame(two)
	var hand := PBFrameTouch.new()
	assert_eq(hand.open(one, []), "", "打得开第一帧")
	hand.wipe(Rect2i(0, 102, 200, 18))
	hand.dab(Vector2i(35, 95), 6)
	var replay := PBFrameTouch.new()
	assert_eq(replay.open(two, hand.marks()), "", "打得开第二帧")
	assert_eq(replay.image().get_data(), hand.image().get_data(), "重放和手擦必须一模一样")


func test_reopening_a_saved_frame_keeps_what_was_already_erased() -> void:
	# 擦除**当场写盘**（那是它修正包围盒的唯一办法，见 [PBFrameTouch] 类顶），
	# 所以下一次打开时底图已经带着上一次的擦除，而笔迹还会再重放一遍。
	# **擦除必须是幂等的** —— 不幂等的话撤销会把上一次擦掉的东西请回来，
	# 而它不报错。
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var first := PBFrameTouch.new()
	assert_eq(first.open(path, []), "", "打得开")
	first.wipe(Rect2i(0, 102, 200, 18))
	assert_eq(first.save(), "", "存下去")

	var again := PBFrameTouch.new()
	assert_eq(again.open(path, first.marks()), "", "重开")
	assert_eq(again.image().get_data(), first.image().get_data(), "重开之后该一模一样")
	again.undo()
	assert_eq(again.image().get_data(), first.image().get_data(), "撤销不该把已落盘的那一笔请回来")


func test_restoring_goes_back_to_the_extracted_frame() -> void:
	# 可逆性靠打开那一下的备份，**不靠「先不写盘」** —— 后者和
	# 「擦完要立刻重量包围盒」直接冲突。
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var was := Image.load_from_file(path).get_data()
	var touch := PBFrameTouch.new()
	assert_eq(touch.open(path, []), "", "打得开")
	assert_true(FileAccess.file_exists(PBFrameTouch.backup_of(path)), "第一次打开就该备份原帧")
	touch.wipe(Rect2i(0, 0, 200, 120))
	assert_eq(touch.save(), "", "整张擦光存下去")
	assert_ne(Image.load_from_file(path).get_data(), was, "盘上确实变了")

	assert_eq(touch.restore(), "", "还原不该出错")
	assert_eq(Image.load_from_file(path).get_data(), was, "还原之后必须回到抽帧那一刻")
	assert_true(touch.marks().is_empty(), "还原之后笔迹也该清空")


func test_strokes_outside_the_frame_do_not_crash() -> void:
	# 框选很容易拖出画面。**钳位收在 [PBFrameTouch] 里** —— 交给面板钳的话
	# 拖出去那半笔会被静默丢掉，表现是「靠边那一块怎么擦不干净」。
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var touch := PBFrameTouch.new()
	assert_eq(touch.open(path, []), "", "打得开")
	touch.wipe(Rect2i(-50, -50, 100, 100))
	touch.dab(Vector2i(-20, 200), 30)
	touch.wipe(Rect2i(500, 500, 40, 40))
	assert_eq(touch.image().get_size(), Vector2i(200, 120), "这几笔不该改了图的尺寸")
	# 第一笔和图是有交集的（左上 50×50），人的 (40, 30) 正在里面。
	assert_eq(touch.image().get_pixel(40, 30).a, 0.0, "有交集的那一笔要真的生效")


func test_a_rect_drawn_backwards_still_erases() -> void:
	# 从右下往左上拉框是很自然的一下，而 [Rect2i] 那时的 `size` 是负的 ——
	# 不取绝对值的话 `intersection` 直接给空，表现是「有时候框了没反应」。
	var path: String = "%s/000.png" % ROOT
	_fake_frame(path)
	var touch := PBFrameTouch.new()
	assert_eq(touch.open(path, []), "", "打得开")
	touch.wipe(Rect2i(60, 110, -60, -20))
	assert_eq(touch.image().get_pixel(40, 99).a, 0.0, "反着拉的框也该擦掉")
