@tool
class_name PBActorForgePanel
extends Control
## 编辑器底栏那块「战场形象」面板：喂一段视频，**逐帧看、逐帧挑**，
## 挑完出成品帧和形象表。M6-l。
##
## ## 它替掉的是命令行那条路的哪一段
##
## `make_actor.ps1` 从头到尾没有人插手：挑哪几帧由 [method PBActorForge.select]
## 按剪影自相关、伸展量这些指标算出来。那套算法**对得多、错得也安静** ——
## AI 视频里总有一两帧手比划到一半、或者人整个糊掉，算法照样会挑中它，
## 而唯一能发现的办法是出完之后开预览台一段段看，再回去改参数重跑。
##
## 这块面板把那一环换成人：**帧就在眼前，点哪张要哪张。**
##
## ## 它没有替掉的：算法本身
##
## 「自动挑」那个按钮走的还是 [method PBActorForge.select] ——
## 先让它出一版，人再逐帧改。从零开始一帧帧翻 97 帧太贵，
## 而算法挑出来的那几帧八成是对的。
##
## ## 一个新角色的走法（三个按钮，M6-o）
##
## 四段各抽一次帧 → **① 导出四段（自动挑帧）**一把全出
## → 逐段翻着看，某一段不对就重挑、**② 只覆盖那一段**
## → 都行了 **③ 生成形象表**。
##
## ① 和 ② 的分工是**从零到有** vs **改**。合成一个按钮的话，
## 想重调 `attack` 就得连着另外三段一起重来。
##
## ## 修帧那一段（M6-r）
##
## 挑帧和导出之间多了一环：**这一帧本身对不对**。两件事，
## 而它们是同一个根因的两半 ——
##
## - **擦除**（[PBFrameTouch]）：AI 视频里人脚下常留一条抠不掉的地面阴影。
##   整条流水线量人全靠包围盒，一条横贯全图的黑影会同时让脚底中点跑到
##   画面正中、画布撑到半个屏幕、地面线落在黑影上。
## - **手动锚点**：擦干净之后剩下的一两格。自动量的那个中点只对
##   「两只脚并拢」最准，跑动那几帧一前一后总会左右晃。
##
## 所以顺序是**先擦再调**，工具条也按这个顺序摆。两者都逐帧记账
## （[member PBForgeEraser._marks] / [member _nudges]），都配一个「套到整段」——
## 镜头不动，那条阴影在 97 帧里是同一个位置。
##
## ## 为什么整个流水线在 [PBActorForge] 里而不在这儿
##
## 命令行那条路还留着（30 个角色批量走一遍时没人想点 120 次按钮）。
## 两条路各写一份图像处理的话，「命令行出的素材和插件出的素材差一像素」
## 迟早发生，而它不报错 —— 表现是同一个角色的两段动画高矮不一。
##
## ## 为什么做成插件，而不是像预览台那样一个能跑的场景
##
## 一条实在的好处：**编辑器能当场重扫资源**。命令行那条路要把
## 「写 PNG」和「装 SpriteFrames」分成两个进程，中间隔一次 `--import` ——
## 因为引擎只认导入过的贴图，刚写到磁盘上的 PNG 在同一次进程里
## `load()` 不出来。插件里一句 `scan()` 就跨过去了，于是
## 「挑完 → 出图 → 装表」是一个按钮。

## 中间帧放哪儿。`build/` 有 `.gdignore`，所以这些帧**不会被导入** ——
## 而预览走的是 [method Image.load_from_file]，它不需要导入。
const MID_ROOT := "res://build/aires/mid"

## 左边那一栏多宽。右边全给预览 —— 这块面板存在的意义就是看清楚一帧。
const SIDE_WIDTH: float = 264.0

## 笔刷半径的两头（中间帧像素）。上限 64 已经是「一笔盖住整条鞋底」的量级，
## 再大就该用框选了。

## 「这一段整体缩放」滑块的两头。够用就行 —— 实测最需要它的那一次是
## 一张图集里人画大了 16%（0.86 就补回来了）。开得太宽的代价是
## 拖一格跳太多，而这个数正是要一点点试的。
const ZOOM_MIN: float = 0.60
const ZOOM_MAX: float = 1.60

var _forge := PBActorForge.new()

## 当前这一段量出来的全部帧（[method PBActorForge.measure] 的结果）。
var _shots: Array = []

## 每一段挑中了哪几帧，`{段名: Array[int]}`。**切段不丢** —— 四段各挑各的。
## M6-n 起导出是一段一段来的（见 [method _on_export]），这份名单因此
## 只在「切回去看看上次挑了哪几帧」时用得上。
var _picks: Dictionary = {}

## 每一段每一帧的**手动锚点偏移**，`{段名: {帧号: Vector2i}}`，单位是成品像素。
## 和 [member _picks] 同级、切段不丢，**只活在这一次会话里** ——
## 调完就该导出，而导出之后它已经烤进那几张 png 了。
var _nudges: Dictionary = {}


## `{段名: 倍率}`。**空 = 每段 1.00 = 一字不差** —— 一个没调过的角色，
## 出来的帧和没有这个滑块的那一版逐字节相同，那是它敢加在导出这条路上的
## 全部理由（同 [member _nudges]）。
##
## **按段各存各的**：一个数存在面板上的话，切到别的段还留着上一段的倍率，
## 而导出的时候它会静默地乘上去。
var _zooms: Dictionary = {}


## 当前这一段的缩放比（中间帧 → 成品）。方向键和青线要拿它换算，
## 而它只在换段/擦完那几下算一次 —— 每帧现算的话翻一次帧要重量整段。
var _scale: float = 1.0

var _index: int = 0

var _key_edit: LineEdit
var _anim_pick: OptionButton
var _source: PBForgeSource
var _count_label: Label
var _measure_label: Label
var _status: RichTextLabel
var _slider: HSlider
var _zoom: HSlider
var _zoom_label: Label
var _list: ItemList
var _tool_pick: OptionButton
var _nudge_label: Label
var _anchor_box: Control
var _eraser: PBForgeEraser
var _canvas: PBForgeCanvas
var _texture: ImageTexture


func _ready() -> void:
	custom_minimum_size = Vector2(0.0, 320.0)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(row)
	row.add_child(_build_side())
	row.add_child(_build_preview())
	for anim: String in PBActorForge.anim_names():
		_picks[anim] = [] as Array[int]
		_nudges[anim] = {}
	# **在 `add_child` 之后接线**：[PBForgeSource] 的控件是它自己在
	# `_ready` 里建的，进树之前 `bind` / `aim_at` 落不到实处。
	_source.bind(_forge)
	_source.aim_at(_mid_dir())
	_use_tool()
	_say("新角色：四段各抽一次帧 → 按①一把全出 → 逐段翻着看，不满意就重挑再按② → 按③装表。")


## 左边那一栏：从上到下就是操作顺序 —— 键、段、视频、翻帧、**修帧**、挑帧、导出。
##
## **包一层滚动**（M6-r）：修帧那一段又摆了七八个控件，而这块面板挂在
## 编辑器底栏上，高度是人拖出来的 —— 装不下的话最底下那三个导出按钮
## 会被挤到看不见，而它不报错，只表现为「怎么没有导出按钮」。
##
## **但状态栏留在滚动区外面**（M8-f）：它原来跟着别的控件一起滚，于是
## 工具说的每一句话都在屏幕外 —— 实测玩家点了「切图并载入」看不到任何反应，
## 而那一下其实报了「只切出 1 格」。**报错说了等于没说，比不报还糟**：
## 人会以为按钮坏了，而不是去看它说了什么。
func _build_side() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(SIDE_WIDTH + 14.0, 0.0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_key_edit = LineEdit.new()
	_key_edit.text = "asm"
	_key_edit.tooltip_text = "角色键：短、全小写。它会变成目录名和 actor_key"
	side.add_child(_titled("角色键", _key_edit))

	_anim_pick = OptionButton.new()
	for anim: String in PBActorForge.anim_names():
		_anim_pick.add_item(anim)
	_anim_pick.item_selected.connect(func(_i: int) -> void: _switch_anim())
	side.add_child(_titled("这一段", _anim_pick))

	# 「帧从哪来」整块在 [PBForgeSource]（M8-f）：视频抽帧和图集切分两条路，
	# 下拉框选一条、另一条的按钮收起来。它们写的是同一个目录，
	# 所以底下那颗「读已有的帧」两条路共用。
	_source = PBForgeSource.new()
	_source.frames_ready.connect(_load_current)
	_source.said.connect(_say)
	side.add_child(_source)
	side.add_child(_button("读已有的帧（不重跑）", _load_current))

	side.add_child(HSeparator.new())
	_count_label = Label.new()
	_count_label.text = "第 0 / 0 帧"
	side.add_child(_count_label)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.step = 1.0
	_slider.value_changed.connect(func(v: float) -> void: _show(int(v)))
	side.add_child(_slider)
	var steps := HBoxContainer.new()
	steps.add_child(_button("◀ 上一帧", func() -> void: _show(_index - 1)))
	steps.add_child(_button("下一帧 ▶", func() -> void: _show(_index + 1)))
	side.add_child(steps)

	# 摆在翻帧的正下方，因为判断「这一段是不是大了」就是翻着帧看的那一刻。
	# **看的不是滑块上那个倍率，是上面那行「成品高」** —— 预览画的是源帧，
	# 倍率再怎么拖它都不变；能比的只有那个数（拿它和 idle 的 180 对）。
	_zoom_label = Label.new()
	side.add_child(_zoom_label)
	_zoom = HSlider.new()
	_zoom.min_value = ZOOM_MIN
	_zoom.max_value = ZOOM_MAX
	_zoom.step = 0.01
	_zoom.value = 1.0
	_zoom.value_changed.connect(_set_zoom)
	side.add_child(_zoom)
	# 归位得有个按钮：步长 0.01，拖回**正好** 1.00 很难，而「差 0.01」
	# 恰恰就是「一字不差」和「不是」的分界。
	side.add_child(_button("这一段缩放归 1.00", func() -> void: _zoom.value = 1.0))
	_refresh_zoom()

	side.add_child(_build_tools())

	side.add_child(HSeparator.new())
	var marks := HBoxContainer.new()
	marks.add_child(_button("＋ 要这一帧", _on_take))
	marks.add_child(_button("自动挑", _on_auto))
	side.add_child(marks)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 76.0)
	_list.item_selected.connect(func(i: int) -> void: _show(int(_picked()[i])))
	side.add_child(_list)
	var edits := HBoxContainer.new()
	edits.add_child(_button("↑", func() -> void: _move(-1)))
	edits.add_child(_button("↓", func() -> void: _move(1)))
	edits.add_child(_button("复制", _on_copy))
	edits.add_child(_button("移除", _on_drop))
	edits.add_child(_button("清空", func() -> void: _set_picked([] as Array[int])))
	side.add_child(edits)

	side.add_child(HSeparator.new())
	# **三个按钮，从上到下就是一个新角色的走法**（M6-n / M6-o，玩家定的）：
	# 先一把全出（帧是算法挑的，八成对），再逐段预览、重挑、覆盖，最后装表。
	# 合成一个的话，想重调 `attack` 就得连着另外三段一起重来。
	side.add_child(_button("① 导出四段（自动挑帧）", _on_export_all))
	side.add_child(_button("② 导出（只覆盖这一段）", _on_export))
	side.add_child(_button("③ 生成形象表", _on_link))
	scroll.add_child(side)
	column.add_child(scroll)
	# 固定在这一栏最底下，不跟着滚 —— 见上面那段。
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0.0, 64.0)
	column.add_child(_status)
	return column


## 修帧那一段：**先擦后调**，工具条也按这个顺序摆（见类顶）。
##
## 两块（锚点 / 擦除）**互斥显示**，而不是全摆着 —— 264 像素宽的一栏里
## 摆七八个控件之后，「现在这一下点在图上是干什么的」就得靠人自己记，
## 而点错的表现是「怎么擦了一块」或者「怎么人整个歪了」。
func _build_tools() -> Control:
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	_tool_pick = OptionButton.new()
	_tool_pick.add_item("调锚点（点图上真正的脚）")
	_tool_pick.add_item("擦除（涂掉多余的画面）")
	_tool_pick.item_selected.connect(func(_i: int) -> void: _use_tool())
	box.add_child(_titled("鼠标点在图上是干什么", _tool_pick))
	box.add_child(_build_anchor())
	box.add_child(_build_eraser())
	return box


## 橡皮那一块整个在 [PBForgeEraser] 里（M8-g 拆出去的）。
##
## **它不自己重量帧**：擦完发一个信号说「这几帧变了」，量帧的是
## [PBActorForge]，而那本账在这儿。各量各的话，「面板上写的包围盒」和
## 「导出时量的」迟早分叉，而两个数看起来都很正常。
func _build_eraser() -> Control:
	_eraser = PBForgeEraser.new()
	_eraser.said.connect(_say)
	_eraser.tool_changed.connect(_repaint_canvas)
	_eraser.touched.connect(_on_touched)
	_eraser.reset.connect(_on_reset)
	return _eraser


## 涂的过程中：橡皮已经把新像素写进贴图了，这儿只要让预览重画。
func _repaint_canvas() -> void:
	if _canvas != null:
		_canvas.queue_redraw()


## 擦了一笔（橡皮还在手上）：重量这几帧，刷新读数。**不重读贴图** ——
## 重读会把撤销栈一起放下，而人正要接着按「撤销一笔」。
func _on_touched(indexes: PackedInt32Array) -> void:
	for i: int in indexes:
		_remeasure(i)
	_refresh_scale()
	_refresh_frame()


## 还原 / 套到整段做完了：盘上的图换了内容，这一帧要从盘上重读。
func _on_reset(indexes: PackedInt32Array) -> void:
	for i: int in indexes:
		_remeasure(i)
	_refresh_scale()
	_show(_index)


## 锚点那一块：点图上定位（粗），四个方向键各一格（细），再加归零和套整段。
##
## **两条路都要**：点一下能一步跨到位，但一格一格那种「再往左一点」
## 用点的永远差半格 —— 而两者加的是同一个数（[method _set_nudge]），
## 所以不会出现「点完再按方向键跳一大格」。
func _build_anchor() -> Control:
	var box := VBoxContainer.new()
	_nudge_label = Label.new()
	_nudge_label.text = "偏移 0, 0（成品像素）"
	box.add_child(_nudge_label)
	var arrows := HBoxContainer.new()
	arrows.add_child(_button("←", func() -> void: _nudge_by(Vector2i(-1, 0))))
	arrows.add_child(_button("→", func() -> void: _nudge_by(Vector2i(1, 0))))
	arrows.add_child(_button("↑", func() -> void: _nudge_by(Vector2i(0, -1))))
	arrows.add_child(_button("↓", func() -> void: _nudge_by(Vector2i(0, 1))))
	box.add_child(arrows)
	var rest := HBoxContainer.new()
	rest.add_child(_button("归零", func() -> void: _set_nudge(Vector2i.ZERO)))
	rest.add_child(_button("套到整段", _on_nudge_all))
	box.add_child(rest)
	_anchor_box = box
	return box



func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas = PBForgeCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.anchor_aimed.connect(_on_anchor_aimed)
	_canvas.dabbed.connect(func(at: Vector2i) -> void: _eraser.on_dabbed(at))
	_canvas.wiped.connect(func(area: Rect2i) -> void: _eraser.on_wiped(area))
	_canvas.stroke_ended.connect(func() -> void: _eraser.on_stroke_ended())
	box.add_child(_canvas)
	_measure_label = Label.new()
	_measure_label.text = ""
	box.add_child(_measure_label)
	return box


func _use_tool() -> void:
	var tool_now: int = maxi(_tool_pick.selected, 0)
	_anchor_box.visible = tool_now == PBForgeCanvas.Tool.ANCHOR
	_eraser.visible = tool_now == PBForgeCanvas.Tool.ERASE
	_canvas.use_tool(tool_now, _eraser.nib(), _eraser.brush())


# ── 载入 ────────────────────────────────────────────────────────


## 换了段。**要把新目录告诉 [PBForgeSource]** —— 不告诉的话人在下拉框里
## 切到 `run`，抽出来/切出来的帧却写进了 `idle` 的目录，而两边的帧长得
## 都像这个角色，翻一遍才发现不对。
func _switch_anim() -> void:
	_source.aim_at(_mid_dir())
	# **不发信号**：发的话这一下会把滑块上那个数（上一段的倍率）写进新段 ——
	# [method _set_zoom] 写的是 `_anim()`，而这时候下拉框已经换过去了。
	# 表现是「我从来没调过 run，导出来却小了一圈」。
	_zoom.set_value_no_signal(_zoom_of(_anim()))
	_refresh_zoom()
	_load_current()


## 把当前段的中间帧量一遍、显示第一帧。**读盘，不重跑抽帧/切图** ——
## 源没变、只想重新挑帧时走这条。
func _load_current() -> void:
	_shots = _forge.measure(_mid_dir())
	_index = 0
	_slider.max_value = float(maxi(_shots.size() - 1, 0))
	if _shots.is_empty():
		_texture = null
		_canvas.show_nothing()
		_say("[color=#e06666]%s 里一帧都没有 —— 先抽帧。[/color]" % _mid_dir())
		return
	_canvas.fit_to(_widest())
	_refresh_scale()
	_show(0)
	_refresh_list()
	_say("载入 %d 帧。← → 翻帧，看中了按「＋ 要这一帧」。" % _shots.size())


## 这一段里最大的那一帧有多大 —— 预览拿它当固定的缩放基准，
## 见 [method PBForgeCanvas.fit_to]。
##
## 按**画布**取不按包围盒：包围盒是「人占了多少」，而各帧画布不一样大正是
## 图集路线的常态，缩放基准要按后者才是常数。
func _widest() -> Vector2i:
	var box := Vector2i.ZERO
	for shot: Dictionary in _shots:
		var one: Vector2i = shot["size"]
		box = Vector2i(maxi(box.x, one.x), maxi(box.y, one.y))
	return box


## 翻到第 [param to] 帧。**钳在两头**，不循环 —— 翻到尾巴自己停住，
## 比绕回第 0 帧更好判断「是不是已经看完了」。
func _show(to: int) -> void:
	if _shots.is_empty():
		return
	_index = clampi(to, 0, _shots.size() - 1)
	_slider.set_value_no_signal(float(_index))
	var image := Image.load_from_file(_shots[_index]["path"])
	_texture = ImageTexture.create_from_image(image) if image != null else null
	# **切帧就把橡皮放下**（[method PBForgeEraser.aim_at] 干的）。留着的话
	# 下一笔会落在上一帧那张图上，而相邻两帧长得几乎一样 ——
	# 要等存完盘翻回去才看得出擦错了张。
	_eraser.aim_at(_anim(), _shots, _index, _texture)
	# **下标 0 起，而总数是总数。** 原来写的是「第 %d / %d」加 `size() - 1`，
	# 于是六帧永远显示成「/ 5」—— 一个 0 起的下标配一个「总数减一」的分母，
	# 读起来就是「5 帧里的第 4 帧」，而那时候人会去找丢掉的那一帧。
	# 下标不改成 1 起：挑帧列表存的就是这个数（`_picked()`），两处必须是同一个。
	_count_label.text = "第 %d 帧（共 %d 帧）%s" % [
		_index, _shots.size(), "　✓已选" if _picked().has(_index) else ""
	]
	_refresh_frame()


## 把这一帧的现状推给预览和那两行读数。**擦完、调完都走这一处** ——
## 各写一份的话，「面板上写的偏移」和「预览里画的青线」迟早对不上，
## 而两个数看起来都很正常。
func _refresh_frame() -> void:
	if _shots.is_empty():
		return
	var nudge := _nudge_now()
	_canvas.show_frame(_texture, _shots[_index], nudge, _scale)
	var used: Rect2i = _shots[_index]["used"]
	# **「成品高」是这一行里唯一能跨段比的数。** 包围盒是源图尺度，
	# 而四张图集本来就可能画得不一样大（实测差过 16%）——
	# 拿它和 idle 段那个 180 对，才看得出这一段是不是整体大了一圈。
	_measure_label.text = (
		"包围盒 %d×%d　脚底 x=%.1f　偏移 %d, %d　成品高 %d"
		% [
			used.size.x,
			used.size.y,
			float(_shots[_index]["feet_x"]),
			nudge.x,
			nudge.y,
			roundi(float(used.size.y) * _scale),
		]
	)
	_nudge_label.text = "偏移 %d, %d（成品像素）" % [nudge.x, nudge.y]


## 这一段的缩放比，**问不出来就退回 1.0，一句话都不说**。
##
## **走的和导出同一份 [method _scale_for]**，只是不吭声：缺 `idle` 在导出那边
## 是要报错的，而预览这边报错没有意义 —— 刚抽完 `dead` 还没抽 `idle`
## 是很正常的一步。两份各算各的话，「预览里那条青线」和「导出真用的比」
## 会分叉，而两个数看起来都很正常。
func _refresh_scale() -> void:
	_scale = 1.0
	if _shots.is_empty():
		return
	var got := _scale_for(_anim(), _shots, false)
	if got > 0.0:
		_scale = got


# ── 修帧：锚点 ──────────────────────────────────────────────────


## 点在图上的那一下，意思是「真正的脚在这儿」。
##
## **换算成偏移量存下来，而不是记住这个点**：偏移的单位是成品像素，
## 方向键那四个按钮加的是同一个数。记点的话两条路就是两把尺子 ——
## 点完再按一下方向键会跳一大格，而两个数看起来都对。
func _on_anchor_aimed(at: Vector2i) -> void:
	if _shots.is_empty():
		return
	var shot: Dictionary = _shots[_index]
	var used: Rect2i = shot["used"]
	# 默认坐进画布的是 `(feet_x, used.end.y)` 这一点。用户说真脚在 `at`，
	# 那人就得往回挪这两点之差 —— 乘缩放比换到成品像素上。
	_set_nudge(
		Vector2i(
			roundi((float(shot["feet_x"]) - float(at.x)) * _scale),
			roundi((float(used.end.y) - float(at.y)) * _scale)
		)
	)


func _nudge_by(step: Vector2i) -> void:
	_set_nudge(_nudge_now() + step)


func _set_nudge(to: Vector2i) -> void:
	if _shots.is_empty():
		return
	_nudge_table()[_index] = to
	_refresh_frame()


## 把这一帧的偏移套到本段每一帧。**脚底中点算歪通常是整段一起歪的**
## （人物在源视频里整体偏一点、或者一条腿的影子没抠干净），
## 而 97 帧各按四次方向键不是给人干的。
func _on_nudge_all() -> void:
	if _shots.is_empty():
		return
	var nudge := _nudge_now()
	var table: Dictionary = _nudge_table()
	for i: int in _shots.size():
		table[i] = nudge
	_say(
		"[color=#71d08c]偏移 %d, %d 套到 %s 段全部 %d 帧。[/color]"
		% [nudge.x, nudge.y, _anim(), _shots.size()]
	)



func _remeasure(index: int) -> void:
	var shot := _forge.measure_one(_shots[index]["path"])
	if not shot.is_empty():
		_shots[index] = shot


# ── 挑帧 ────────────────────────────────────────────────────────


## 要这一帧。**再按一次就是取消** —— 一个按钮两个方向，
## 省掉「我到底选没选中」这个要去列表里数的问题。
func _on_take() -> void:
	if _shots.is_empty():
		return
	var picked := _picked()
	if picked.has(_index):
		picked.erase(_index)
	else:
		picked.append(_index)
	_set_picked(picked)


func _on_auto() -> void:
	if _shots.is_empty():
		return
	var spec := PBActorForge.spec_of(_anim())
	_set_picked(_forge.select(_shots, String(spec["pick"]), int(spec["want"])))
	_say("自动挑了 %d 帧 —— 逐帧看一遍，不合适就自己改。" % _picked().size())


## 把选中的那一帧在名单里**再放一份**，插在它后面。M9-e。
##
## ## 为什么「＋ 要这一帧」做不到
##
## 那个按钮是**开关**（在名单里就拿掉、不在就加上），所以同一帧按两次
## 等于没按。而 [member PBSimConfig.anim_frames] 要求每一段 6 帧 ——
## 源片里凑不够 6 个像样姿势的时候，就得**把某一帧停久一点**。
##
## ## 和载入时那次补有什么不同
##
## [method PBActorSkin.hold_last_to] 也补，但它只会重复**最后一帧**（那是
## 兜底，对 27 个已入库的角色一视同仁）。这里能选**停哪一帧** ——
## 攻击段常常是想让「伸得最远」那一格多停两帧，而不是让收招拖长。
##
## ## 复制的**恒是当前这一帧**
##
## 列表里那个选中项只用来**区分同一帧的哪一份**（复制过之后同一帧会出现
## 两次），不用来决定复制谁 —— 用它决定的话，翻帧不会清掉旧的选中项，
## 于是「翻到第 5 帧按复制，出来的是第 2 帧」，而屏幕上两处各说各的。
func _on_copy() -> void:
	if _shots.is_empty():
		return
	var picked := _picked()
	var rows := _list.get_selected_items()
	var at: int = -1
	if not rows.is_empty() and picked[rows[0]] == _index:
		at = rows[0]
	else:
		at = picked.find(_index)
	if at < 0:
		_say("[color=#e06666]这一帧还不在名单里 —— 先按「＋ 要这一帧」。[/color]")
		return
	var frame: int = picked[at]
	picked.insert(at + 1, frame)
	_set_picked(picked)
	_list.select(at + 1)
	_say("第 %d 帧多留了一份，这一段现在 %d 帧。" % [frame, picked.size()])


func _on_drop() -> void:
	var rows := _list.get_selected_items()
	if rows.is_empty():
		return
	var picked := _picked()
	picked.remove_at(rows[0])
	_set_picked(picked)


## 调整顺序。**顺序就是播放顺序** —— 攻击段第 0 帧必须是打出去那一下
## （规格第 8 节），起手排在前面的话游戏里会「先掉血、后挥手」。
func _move(by: int) -> void:
	var rows := _list.get_selected_items()
	if rows.is_empty():
		return
	var from: int = rows[0]
	var to: int = from + by
	var picked := _picked()
	if to < 0 or to >= picked.size():
		return
	var moved: int = picked[from]
	picked.remove_at(from)
	picked.insert(to, moved)
	_set_picked(picked)
	_list.select(to)


func _refresh_list() -> void:
	_list.clear()
	for slot: int in _picked().size():
		_list.add_item("第 %d 帧 → %s_%d" % [_picked()[slot], _anim(), slot])


# ── 导出 ────────────────────────────────────────────────────────


## 只导**当前选中的这一段**。M6-n 之前是四段一起。
##
## ## 一段一段导，画布怎么保持一致
##
## 规格要求同一个角色**每一帧尺寸完全一致**（[method PBActorSkin.canvas_size]
## 只读第一帧算锚点），而画布是按内容算的 —— 出拳那一段几乎总是最宽。
## 所以这里取**这一段需要的**和**已经在盘上的**两者的最大值，
## 需要变大时把旧帧重新裱一遍（[method PBActorForge.recanvas]，纯补透明边）。
##
## 不这么做的话，后导的那一段会带着更大的画布落地而前面几段还是旧尺寸 ——
## 人在动画之间跳一下，`tests/test_actor_data.gd` 会红。
##
## **没挑过就自动挑**：先让算法出一版是这块面板一贯的用法。
func _on_export() -> void:
	var key: String = _key_edit.text.strip_edges()
	if key == "":
		_say("[color=#e06666]先填角色键。[/color]")
		return
	var anim: String = _anim()
	var shots := _forge.measure(_mid_dir())
	if shots.is_empty():
		_say("[color=#e06666]%s 段一帧都没有 —— 先抽帧。[/color]" % anim)
		return
	var picked: Array[int] = _picked()
	if picked.is_empty():
		var spec := PBActorForge.spec_of(anim)
		picked = _forge.select(shots, String(spec["pick"]), int(spec["want"]))
		_set_picked(picked)
	var scale := _scale_for(anim, shots)
	if scale <= 0.0:
		return

	var want := _forge.fit_canvas({anim: shots}, {anim: scale}, {anim: picked})
	var had := _forge.canvas_on_disk(key)
	var canvas := Vector2i(maxi(want.x, had.x), maxi(want.y, had.y))
	_forge.canvas = canvas
	if had != Vector2i.ZERO and had != canvas:
		var grow_err := _forge.recanvas(key, canvas)
		if grow_err != "":
			_say("[color=#e06666]%s[/color]" % grow_err)
			return
	var err := _write_take(key, anim, shots, picked, scale, _nudge_table())
	if err != "":
		_say("[color=#e06666]%s[/color]" % err)
		return
	if _forge.clamped:
		_say(
			(
				"[color=#e0a666]%s 段 %d 帧，画布 %d×%d —— 撞上头顶上限，"
				+ "头被切掉了一截。挑帧里有跳得太高的那一张？[/color]"
			)
			% [anim, picked.size(), canvas.x, canvas.y]
		)
	else:
		_say(
			"[color=#71d08c]%s 段 %d 帧覆盖好了[/color]，画布 %d×%d。都行了按③。"
			% [anim, picked.size(), canvas.x, canvas.y]
		)
	await _rescan()
	await _relink_if_needed(key)


## 已经有形象表的角色，覆盖完一段要**顺手把表重生成一遍**。
##
## ## 为什么这一步不能等玩家按③
##
## [method PBActorForge.save_frames] 会删掉多出来的旧帧（这次挑 3 帧、
## 上次挑 4 帧的话 `dead_3.png` 就没了），**而已经存在的图集还指着那一张**。
## 中间这段时间项目是坏的：[PBActorLibrary] 每次读表都 `push_error`，
## `tests/test_actor_data.gd` 全红，而屏幕上只是「那个角色还是白模」。
##
## 实测就是这么坏的：某个角色的 `dead` 段重导过一次，
## 图集里留着一个 `ext_resource` 指向已经删掉的 `dead_3.png`。
##
## **①那条路原来也漏着**（这段注释以前写的是「四段一起导的那一版没有这个洞」，
## 那是错的 —— 它只 `_rescan()`，从来没重生成过表）。M8-g 补上了，
## 两个导出按钮现在都调这一份。所以这里不是「导出偷偷做了③的事」——
## 是谁弄坏的谁负责补。表还不存在时什么都不做，
## 那一档归③（那时四段可能还没齐，`link` 本来就该失败）。
func _relink_if_needed(key: String) -> void:
	if not ResourceLoader.exists("%s/%s.tres" % [_forge.data_dir, key]):
		return
	var err := _forge.link(key)
	if err != "":
		_say("[color=#e0a666]帧写好了，但形象表没跟上：%s[/color]" % err)
		return
	await _rescan()


## 新角色的第一趟：四段一把全出，帧全由算法挑（M6-o，玩家定的）。
##
## ## 它和 [method _on_export] 的分工
##
## 这一个负责**从零到有**：从零开始一帧帧翻 97 帧 × 4 段太贵，而算法挑的
## 八成是对的。那一个负责**改**：预览某一段、重挑、只覆盖它。
##
## ## 为什么它的画布算得比逐段那条好
##
## 四段一起量，画布一次就定在最终尺寸上（出拳那段最宽、跑动那段最高），
## 后面逐段覆盖时基本不用再重裱。反过来先导窄的那几段，
## 等导到 `attack` 时就要把前面几段全部重裱一遍 —— 结果一样，只是多跑几趟。
##
## **挑帧一律走算法，不看已经挑过的名单** —— 按钮上写着「自动挑帧」，
## 而「有时候用我挑的、有时候不用」是一个说不清的按钮。挑好的名单会填回
## 各段的列表里，接着改就是了。
func _on_export_all() -> void:
	var key: String = _key_edit.text.strip_edges()
	if key == "":
		_say("[color=#e06666]先填角色键。[/color]")
		return
	var takes: Dictionary = {}
	var chosen: Dictionary = {}
	for anim: String in PBActorForge.anim_names():
		var shots := _forge.measure("%s/%s" % [MID_ROOT, anim])
		if shots.is_empty():
			_say("[color=#e06666]%s 段一帧都没有 —— 四段都要抽过帧才导得出。[/color]" % anim)
			return
		takes[anim] = shots
		var spec := PBActorForge.spec_of(anim)
		chosen[anim] = _forge.select(shots, String(spec["pick"]), int(spec["want"]))

	var scales := _zoomed(_forge.scales(takes, _source.shares_idle_scale()))
	var canvas := _forge.fit_canvas(takes, scales, chosen)
	for anim: String in PBActorForge.anim_names():
		var err := _write_take(
			key, anim, takes[anim], chosen[anim], float(scales[anim]), _nudges.get(anim, {})
		)
		if err != "":
			_say("[color=#e06666]%s[/color]" % err)
			return
		_picks[anim] = chosen[anim]
	_refresh_list()
	if _forge.clamped:
		_say(
			(
				"[color=#e0a666]四段出好了，画布 %d×%d —— 撞上头顶上限，"
				+ "头被切掉了一截。逐段翻一遍，把跳得太高的那张换掉。[/color]"
			)
			% [canvas.x, canvas.y]
		)
	else:
		_say(
			(
				"[color=#71d08c]四段出好了[/color]，画布 %d×%d。"
				+ "逐段翻一遍，不满意就重挑再按②；都行了按③。"
			)
			% [canvas.x, canvas.y]
		)
	await _rescan()
	# **①也要维持它自己弄坏的那个不变量**（见 [method _relink_if_needed]）。
	# [method PBActorForge.save_frames] 会删掉多出来的旧帧，而已经存在的图集
	# 还指着那几张 —— 于是按完①项目就是坏的：`PBActorLibrary` 每次读表都
	# `push_error`，`tests/test_actor_data.gd` 全红，而屏幕上只是
	# 「那个角色还是白模」，面板还写着「四段出好了」。
	#
	# 那个函数顶上原来写着「四段一起导的那一版没有这个洞」——**写错了**，
	# 洞一直在，实测踩到过：重导一次之后 `data/actors/<键>.tres` 里留着
	# 五个 `ext_resource` 指向已经删掉的帧。表还不存在时它什么都不做，
	# 那一档照旧归③。
	await _relink_if_needed(key)


## 把一段缩好、写盘。**两个导出按钮共用这一份** —— 各写一份的话
## 「①出的帧和②出的帧差一像素」迟早发生，而它不报错。
##
## [param nudges] 是 `{帧号: Vector2i}` 的手动锚点偏移（M6-r）。
## **默认空 = 一字不差**：一个偏移都没调过的角色，出来的帧和 M6-o 那一版
## 逐字节相同 —— 那是这个参数敢加在这条路上的全部理由。
func _write_take(
	key: String, anim: String, shots: Array, picked: Array, scale: float, nudges: Dictionary = {}
) -> String:
	var images: Array[Image] = []
	for index: int in picked:
		images.append(_forge.compose(shots[index], scale, nudges.get(index, Vector2i.ZERO)))
	return _forge.save_frames(key, anim, images)


## 这一段量缩放比要不要把 `idle` 也量进来。**两种情况**：
##
## - `dead`：人躺着，包围盒高度不是身高，照自己算他会被放大到站着那么高（M6-o）
## - **按图集切**：六格全是同一种姿势，`run` 那张最高的一格也还是弓着腰的 ——
##   照自己量会把跑动的人放大四成（M8-g，见 [method PBActorForge.scales]）
func _needs_idle(anim: String) -> bool:
	return anim == "dead" or _source.shares_idle_scale()


## 缺 `idle` 时该说哪一句。**两种情况的原因不同**，而说错原因的话人会去查错的地方。
func _no_idle_says(anim: String) -> String:
	if anim == "dead":
		return "导 dead 要先抽一次 idle 的帧 —— 人躺着，包围盒高度不是身高，缩放比得借 idle 的。"
	return "按图集切要先切一次 idle 的帧 —— 一张图集六格全是同一种姿势，缩放比得借 idle 的。"


## 这一段的缩放比，**手动倍率已经乘进去了**。
##
## **两种情况要借 `idle` 的**，见 [method _needs_idle] —— 那两种都要求
## `idle` 的中间帧还在盘上。返回 0 = 说不出来（[param loud] 为真时已经说过话了）。
##
## 手动倍率只乘在这一句上：预览、②逐段导出走的都是这一份，
## 各乘各的话「面板上写的成品高」和「导出真用的比」会分叉。
## ①那条路不经过这里，它走 [method _zoomed]。
func _scale_for(anim: String, shots: Array, loud: bool = true) -> float:
	var takes: Dictionary = {anim: shots}
	if _needs_idle(anim):
		var idle := _forge.measure("%s/idle" % MID_ROOT)
		if idle.is_empty():
			if loud:
				_say("[color=#e06666]%s[/color]" % _no_idle_says(anim))
			return 0.0
		takes["idle"] = idle
	var got: float = float(_forge.scales(takes, _source.shares_idle_scale()).get(anim, 0.0))
	return got * _zoom_of(anim) if got > 0.0 else 0.0


## 四段的缩放比，手动倍率乘进去。**①那条路必须走这一份** ——
## 不乘的话「①出的帧和②出的帧差一截」，而它不报错：表现是四段一把重出之后，
## 手动调过的那一段又变回去了。
func _zoomed(scales: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for anim: String in scales:
		out[anim] = float(scales[anim]) * _zoom_of(anim)
	return out


func _zoom_of(anim: String) -> float:
	return float(_zooms.get(anim, 1.0))


## 拖了滑块。**三样都要跟着刷**：标签上的倍率、预览那条青线用的比、
## 以及读数里那个「成品高」—— 而那个数才是人真正在看的东西。
func _set_zoom(to: float) -> void:
	_zooms[_anim()] = to
	_refresh_zoom()
	_refresh_scale()
	_refresh_frame()


func _refresh_zoom() -> void:
	_zoom_label.text = "这一段整体缩放 %.2f（1.00 = 不动）" % _zoom_of(_anim())


## 四段都导完之后：装 [SpriteFrames] + [PBActorSkin]。
##
## 少一段就停在这里报错（[method PBActorForge.link] 自己会说是哪一段）——
## 那是对的：缺一段的表现是那个人「会站不会跑」，而它不报错。
func _on_link() -> void:
	var key: String = _key_edit.text.strip_edges()
	if key == "":
		_say("[color=#e06666]先填角色键。[/color]")
		return
	var link_err := _forge.link(key)
	if link_err != "":
		_say("[color=#e06666]%s[/color]" % link_err)
		return
	# [method PBActorForge.link] 顺手改了贴图的 `.import`（开 mipmap），
	# **改完要再导一次才生效** —— 少这一趟的表现是人一走动身上就闪，
	# 而静止看完全正常。
	await _rescan()
	_say(
		(
			"[color=#71d08c]形象表出好了。[/color]最后一步：把 "
			+ "data/characters/<角色>.tres 的 actor_key 填成 &\"%s\"，"
			+ "再开预览台看一眼（scenes/actor_lab.tscn）。"
		)
		% key
	)


## 让编辑器把刚写的 PNG 导进来。**这就是做成插件换到的东西** ——
## 命令行那条路只能把流水线切成两个进程，中间隔一次 `--import`。
##
## 走 [method Engine.get_singleton] 而不是直接写 `EditorInterface`：
## 那个单例只在编辑器里存在，直接引用的话这个文件在**游戏进程**里
## （GUT 跑测试就是游戏进程）会解析不过。
func _rescan() -> void:
	var editor := Engine.get_singleton(&"EditorInterface")
	if editor == null:
		return
	var files: Object = editor.get_resource_filesystem()
	files.call("scan")
	# 扫描是异步的，扫完之前 `load()` 还是拿不到贴图。**轮询而不是等信号**：
	# `filesystem_changed` 在没有变化时压根不发，那时这里会永远等下去。
	for _tick: int in 600:
		await get_tree().process_frame
		if not files.call("is_scanning"):
			return


# ── 小工具 ──────────────────────────────────────────────────────


func _anim() -> String:
	return _anim_pick.get_item_text(_anim_pick.selected) if _anim_pick.selected >= 0 else "idle"


func _mid_dir() -> String:
	return "%s/%s" % [MID_ROOT, _anim()]


func _picked() -> Array[int]:
	return _picks.get(_anim(), [] as Array[int])


func _set_picked(picked: Array[int]) -> void:
	_picks[_anim()] = picked
	_refresh_list()
	if not _shots.is_empty():
		_show(_index)


## 这一段的锚点偏移账。**按需建**：段名是从下拉框里读的，
## 而 [method _ready] 那一趟只铺了 [constant PBActorForge.ANIMS] 里那四段。
func _nudge_table() -> Dictionary:
	if not _nudges.has(_anim()):
		_nudges[_anim()] = {}
	return _nudges[_anim()]


func _mark_table() -> Dictionary:
	return _eraser.marks_of(_anim())


func _nudge_now() -> Vector2i:
	return _nudge_table().get(_index, Vector2i.ZERO)


## 这一段的橡皮笔迹账。


func _say(text: String) -> void:
	_status.text = text


func _titled(title: String, node: Control) -> Control:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = title
	box.add_child(label)
	box.add_child(node)
	return box


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_press)
	return button
