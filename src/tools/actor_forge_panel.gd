@tool
class_name PBActorForgePanel
extends Control
## 编辑器底栏那块「战场形象」面板：喂视频或图集，**逐帧看、逐帧挑、逐帧修**，出成品帧和形象表。
##
## 挑帧那一环交给人：自动挑帧的算法对得多、错得安静（手比划到一半的帧照样挑中）。算法还在，
## 按源帧数分两档（[method PBActorForge.frames_for]）：图集那条路正好几格就按顺序全要，视频那条路才走算法。
##
## 一个新角色的走法（三个按钮）：四段各抽一次帧 → **① 导出四段（帧自动定）** → 逐段翻着看，不对就重挑、
## **② 只覆盖那一段** → **③ 生成形象表**。① 是从零到有，② 是改 —— 合成一个的话想重调 `attack` 得四段一起重来。
##
## 修帧（**先擦再调**）：**擦除**（[PBFrameTouch]）去掉抠不掉的地面阴影（它会让包围盒横贯全图）；
## **手动锚点**修剩下一两格的左右晃。两者都逐帧记账，都有「套到整段」（镜头不动，阴影在每帧同一个位置）。
##
## 图像处理全在 [PBActorForge]，命令行那条路调同一个类。做成插件的实在好处：编辑器能当场重扫资源，
## 「挑完 → 出图 → 装表」是一个按钮（命令行得分两个进程、中间隔一次 `--import`）。

## 中间帧放哪儿。`build/` 有 `.gdignore`，所以这些帧**不会被导入** ——
## 而预览走的是 [method Image.load_from_file]，它不需要导入。
const MID_ROOT := "res://build/aires/mid"

## 左边那一栏多宽。右边全给预览 —— 这块面板存在的意义就是看清楚一帧。
const SIDE_WIDTH: float = 264.0

## 「这一段整体缩放」滑块的两头。**下限放得很低**：跨图集尺度不一致没有上界（同一套素材的 `attack` 图集
## 可能比 `idle` 大七成），不能按「上一次最极端是多少」定。拖不准的由「归 1.00」那个按钮兜着。
const ZOOM_MIN: float = 0.10
const ZOOM_MAX: float = 1.60

var _forge := PBActorForge.new()

## 当前这一段量出来的全部帧（[method PBActorForge.measure] 的结果）。
var _shots: Array = []

## 每一段每一帧的**手动锚点偏移**，`{段名: {帧号: Vector2i}}`，单位是成品像素。
## 和挑帧名单（[PBForgePicks]）同级、切段不丢，**只活在这一次会话里** ——
## 调完就该导出，而导出之后它已经烤进那几张 png 了。
var _nudges: Dictionary = {}

## `{段名: 倍率}`。**空 = 每段 1.00 = 一字不差**（同 [member _nudges]）。
## **按段各存各的**：存一个数的话切到别的段还留着上一段的倍率，导出时静默乘上去。
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
var _picks_ui: PBForgePicks
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
	for anim: String in PBActorForge.anim_names(true):
		_nudges[anim] = {}
	# **在 `add_child` 之后接线**：[PBForgeSource] 的控件是它在 `_ready` 里建的，进树之前 `bind` 落不到实处。
	_source.bind(_forge)
	_source.aim_at(_mid_dir())
	_use_tool()
	_say("新角色：四段各抽一次帧 → 按①一把全出 → 逐段翻着看，不满意就重挑再按② → 按③装表。")


## 左边那一栏：从上到下就是操作顺序 —— 键、段、帧来源、翻帧、修帧、挑帧、导出。
## **包一层滚动**：面板高度是人拖出来的，装不下的话最底下的导出按钮会被挤到看不见。
## **状态栏留在滚动区外面**：跟着一起滚的话工具说的每一句话都在屏幕外，报错说了等于没说。
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
	_key_edit.tooltip_text = "角色键：短、全小写。召唤物也用独立键；生成四态形象表后到战场特效 → 召唤物表现绑定"
	side.add_child(_titled("角色键", _key_edit))

	_anim_pick = OptionButton.new()
	for anim: String in PBActorForge.anim_names(true):
		_anim_pick.add_item(anim)
	_anim_pick.item_selected.connect(func(_i: int) -> void: _switch_anim())
	side.add_child(_titled("这一段", _anim_pick))

	# 「帧从哪来」整块在 [PBForgeSource]：两条路写同一个目录，所以底下「读已有的帧」两条路共用。
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
	# 挑帧那一块整个在 [PBForgePicks]，名单是它的，面板只「翻到那一帧」和「说一句」。
	_picks_ui = PBForgePicks.new()
	_picks_ui.show_frame.connect(_show)
	_picks_ui.changed.connect(func() -> void: _show(_index))
	_picks_ui.said.connect(_say)
	side.add_child(_picks_ui)

	side.add_child(HSeparator.new())
	# **三个按钮，从上到下就是一个新角色的走法**（玩家定的），见类顶部。
	side.add_child(_button("① 导出四段（帧自动定）", _on_export_all))
	side.add_child(_button("② 导出（只覆盖这一段）", _on_export))
	side.add_child(_button("③ 生成形象表", _on_link))
	var summon_tip := Label.new()
	summon_tip.text = "召唤物同样加工四态；生成后到\n战场特效 → 召唤物表现绑定。"
	summon_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(summon_tip)
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


## 橡皮那一块整个在 [PBForgeEraser]。它擦完只发信号说「这几帧变了」，量帧在这边 —— 那本账在这儿。
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
	# 尺子上标哪两条线，**两个数都从流水线拿**，否则尺子和导出会对「站姿多高」「上限在哪」说两个数。
	_canvas.mark_at(_forge.texture_height(), PBActorForge.CANVAS_CEILING * maxi(_forge.scale_up, 1))
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
	# **在那个空判断之前重画名单**，否则从挑满的 `idle` 切到还没抽帧的 `run` 时列表还摆着 idle 那几行。
	_picks_ui.aim_at(_anim(), _shots, 0)
	_picks_ui.refresh()
	if _shots.is_empty():
		_texture = null
		_canvas.show_nothing()
		_say("[color=#e06666]%s 里一帧都没有 —— 先抽帧。[/color]" % _mid_dir())
		return
	_canvas.fit_to(_widest())
	_refresh_scale()
	_show(0)
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
	_picks_ui.aim_at(_anim(), _shots, _index)
	# **下标 0 起，而总数是总数**（写「/ size-1」的话六帧永远显示成「/ 5」）。
	# 下标不改成 1 起：挑帧列表存的就是这个数，两处必须同一个。
	_count_label.text = (
		"第 %d 帧（共 %d 帧）%s" % [_index, _shots.size(), "　✓已选" if _picks_ui.holds(_index) else ""]
	)
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
	# **「成品高」是这一行里唯一能跨段比的数**：包围盒是源图尺度，拿成品高和 idle 那个 180 对才看得出大了一圈。
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
		(
			"[color=#71d08c]偏移 %d, %d 套到 %s 段全部 %d 帧。[/color]"
			% [nudge.x, nudge.y, _anim(), _shots.size()]
		)
	)


func _remeasure(index: int) -> void:
	var shot := _forge.measure_one(_shots[index]["path"])
	if not shot.is_empty():
		_shots[index] = shot


# ── 导出 ────────────────────────────────────────────────────────


## 只导**当前选中的这一段**。没挑过就替你定一版（[method PBActorForge.frames_for]）。
##
## 同一个角色**每一帧尺寸必须一致**，而画布按内容算（出拳那段最宽）：取这一段需要的和盘上已有的两者最大值，
## 需要变大时把旧帧重裱一遍（[method PBActorForge.recanvas]，纯补透明边）。否则人在动画之间跳一下，
## `tests/test_actor_data.gd` 会红。
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
		picked = _forge.frames_for(shots, anim)
		_set_picked(picked)
	if anim in ["skill1", "skill2"] and picked.size() != 6:
		_say("[color=#e06666]技能动作必须选择六帧，第 4 帧为释放姿态。[/color]")
		return
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
				("[color=#e0a666]%s 段 %d 帧，画布 %d×%d —— 撞上画布上限，" + "头被切掉了一截。挑帧里有跳得太高的那一张？[/color]")
				% [anim, picked.size(), canvas.x, canvas.y]
			)
		)
	else:
		_say(
			(
				"[color=#71d08c]%s 段 %d 帧覆盖好了[/color]，画布 %d×%d。都行了按③。"
				% [anim, picked.size(), canvas.x, canvas.y]
			)
		)
	await _rescan()
	await _relink_if_needed(key)


## 已经有形象表的角色，导出完**顺手把表重生成一遍**（两个导出按钮都调这里）。
##
## [method PBActorForge.save_frames] 会删掉多出来的旧帧，而已存在的图集还指着那几张 —— 不补的话项目是坏的：
## [PBActorLibrary] 读表 `push_error`、`tests/test_actor_data.gd` 全红，屏幕上只是「那个角色还是白模」。
## 谁弄坏的谁负责补。表还不存在时什么都不做（那一档归 ③，四段可能还没齐）。
func _relink_if_needed(key: String) -> void:
	if not ResourceLoader.exists("%s/%s.tres" % [_forge.data_dir, key]):
		return
	var err := _forge.link(key)
	if err != "":
		_say("[color=#e0a666]帧写好了，但形象表没跟上：%s[/color]" % err)
		return
	await _rescan()


## 新角色的第一趟：四段一把全出，**帧一律现定**，不看已经挑过的名单（按钮上写着「帧自动定」）。
## 定好的名单填回各段的列表里，接着改。四段一起量，画布一次定在最终尺寸上，后面逐段覆盖基本不用重裱。
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
		chosen[anim] = _forge.frames_for(shots, anim)

	var scales := _zoomed(_forge.scales(takes, _source.shares_idle_scale()))
	var canvas := _forge.fit_canvas(takes, scales, chosen)
	# 重做基础四态时也保留已制作技能动作的统一画布。
	var had := _forge.canvas_on_disk(key)
	canvas = Vector2i(maxi(canvas.x, had.x), maxi(canvas.y, had.y))
	_forge.canvas = canvas
	if had != Vector2i.ZERO and had != canvas:
		var error := _forge.recanvas(key, canvas)
		if error != "":
			_say(error)
			return
	for anim: String in PBActorForge.anim_names():
		var err := _write_take(
			key, anim, takes[anim], chosen[anim], float(scales[anim]), _nudges.get(anim, {})
		)
		if err != "":
			_say("[color=#e06666]%s[/color]" % err)
			return
		_picks_ui.set_picks(anim, chosen[anim])
	if _forge.clamped:
		_say(
			(
				("[color=#e0a666]四段出好了，画布 %d×%d —— 撞上画布上限，" + "头被切掉了一截。逐段翻一遍，把跳得太高的那张换掉。[/color]")
				% [canvas.x, canvas.y]
			)
		)
	else:
		_say(
			(
				("[color=#71d08c]四段出好了[/color]，画布 %d×%d。" + "逐段翻一遍，不满意就重挑再按②；都行了按③。")
				% [canvas.x, canvas.y]
			)
		)
	await _rescan()
	# **① 也要维持它自己弄坏的那个不变量**（见 [method _relink_if_needed]）。
	await _relink_if_needed(key)


## 把一段缩好、写盘。**两个导出按钮共用这一份**，否则「① 出的帧和 ② 出的帧差一像素」迟早发生。
## [param nudges] 是 `{帧号: Vector2i}` 的手动锚点偏移，**默认空 = 一字不差**。
func _write_take(
	key: String, anim: String, shots: Array, picked: Array, scale: float, nudges: Dictionary = {}
) -> String:
	var images: Array[Image] = []
	for index: int in picked:
		images.append(_forge.compose(shots[index], scale, nudges.get(index, Vector2i.ZERO)))
	return _forge.save_frames(key, anim, images)


## 这一段量缩放比要不要把 `idle` 也量进来：`dead`（人躺着，包围盒高度不是身高），
## 以及**按图集切**的每一段（六格同一种姿势，`run` 最高的一格也是弓着腰的，见 [method PBActorForge.scales]）。
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
			(
				"[color=#71d08c]形象表出好了。[/color]最后一步：把 "
				+ 'data/characters/<角色>.tres 的 actor_key 填成 &"%s"，'
				+ "再开预览台看一眼（scenes/actor_lab.tscn）。"
			)
			% key
		)
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
	# 扫描是异步的。**轮询而不是等信号**：`filesystem_changed` 在没有变化时不发，那时会永远等下去。
	for _tick: int in 600:
		await get_tree().process_frame
		if not files.call("is_scanning"):
			return


# ── 小工具 ──────────────────────────────────────────────────────


func _anim() -> String:
	return _anim_pick.get_item_text(_anim_pick.selected) if _anim_pick.selected >= 0 else "idle"


func _mid_dir() -> String:
	return "%s/%s" % [MID_ROOT, _anim()]


## 当前这一段的名单。**名单在 [PBForgePicks] 手上**，这两行只是导出那几条
## 路少写一个 `_anim()`。
func _picked() -> Array[int]:
	return _picks_ui.picks_of(_anim())


func _set_picked(picked: Array[int]) -> void:
	_picks_ui.set_picks(_anim(), picked)


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
