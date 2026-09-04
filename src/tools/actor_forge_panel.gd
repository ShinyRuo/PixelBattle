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

## 预览上那两条辅助线的颜色：包围盒、脚底中线。
const BOX_COLOR := Color(0.38, 0.62, 0.95, 0.85)
const FEET_COLOR := Color(0.98, 0.85, 0.45, 0.95)

var _forge := PBActorForge.new()

## 当前这一段量出来的全部帧（[method PBActorForge.measure] 的结果）。
var _shots: Array = []

## 每一段挑中了哪几帧，`{段名: Array[int]}`。**切段不丢** —— 四段各挑各的。
## M6-n 起导出是一段一段来的（见 [method _on_export]），这份名单因此
## 只在「切回去看看上次挑了哪几帧」时用得上。
var _picks: Dictionary = {}

var _index: int = 0
var _video: String = ""

var _key_edit: LineEdit
var _anim_pick: OptionButton
var _video_label: Label
var _count_label: Label
var _measure_label: Label
var _status: RichTextLabel
var _slider: HSlider
var _list: ItemList
var _preview: Control
var _dialog: FileDialog
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
	_say("新角色：四段各抽一次帧 → 按①一把全出 → 逐段翻着看，不满意就重挑再按② → 按③装表。")


## 左边那一栏：从上到下就是操作顺序 —— 键、段、视频、翻帧、挑帧、导出。
func _build_side() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0.0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_key_edit = LineEdit.new()
	_key_edit.text = "asm"
	_key_edit.tooltip_text = "角色键：短、全小写。它会变成目录名和 actor_key"
	side.add_child(_titled("角色键", _key_edit))

	_anim_pick = OptionButton.new()
	for anim: String in PBActorForge.anim_names():
		_anim_pick.add_item(anim)
	_anim_pick.item_selected.connect(func(_i: int) -> void: _load_current())
	side.add_child(_titled("这一段", _anim_pick))

	_video_label = Label.new()
	_video_label.text = "（还没选视频）"
	_video_label.clip_text = true
	side.add_child(_video_label)
	side.add_child(_button("选视频…", _on_pick_video))
	side.add_child(_button("抽帧并载入（跑 ffmpeg）", _on_extract))
	side.add_child(_button("读已抽的帧（不跑 ffmpeg）", _load_current))

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

	var marks := HBoxContainer.new()
	marks.add_child(_button("＋ 要这一帧", _on_take))
	marks.add_child(_button("自动挑", _on_auto))
	side.add_child(marks)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0.0, 76.0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(i: int) -> void: _show(int(_picked()[i])))
	side.add_child(_list)
	var edits := HBoxContainer.new()
	edits.add_child(_button("↑", func() -> void: _move(-1)))
	edits.add_child(_button("↓", func() -> void: _move(1)))
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
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(0.0, 52.0)
	side.add_child(_status)
	return side


func _build_preview() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview = Control.new()
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.draw.connect(_draw_preview)
	box.add_child(_preview)
	_measure_label = Label.new()
	_measure_label.text = ""
	box.add_child(_measure_label)
	return box


## 预览。**自己画，不用 [TextureRect]** —— 辅助线要和图用同一个变换，
## 交给容器去缩放的话两者会差几个像素，而那正好是这块面板要看的东西。
##
## 画的两条：**包围盒**（这一帧的人有多大）和**脚底中线**
## （[method PBActorForge._feet_x] 量的那个位置）。
## 脚底那条是最要紧的 —— 出拳那几帧手伸得老远，包围盒中心会跟着偏，
## 而对齐用的是脚。看得见它才判得出「这一帧能不能要」。
func _draw_preview() -> void:
	var full := Rect2(Vector2.ZERO, _preview.size)
	_preview.draw_rect(full, Color(0.09, 0.10, 0.13, 1.0))
	if _texture == null or _shots.is_empty():
		return
	var source := Vector2(_texture.get_size())
	var scale: float = minf(full.size.x / source.x, full.size.y / source.y)
	var shown := Rect2(
		full.position + (full.size - source * scale) * 0.5, source * scale
	)
	_preview.draw_texture_rect(_texture, shown, false)
	var shot: Dictionary = _shots[_index]
	var used: Rect2i = shot["used"]
	_preview.draw_rect(
		Rect2(shown.position + Vector2(used.position) * scale, Vector2(used.size) * scale),
		BOX_COLOR,
		false,
		1.0
	)
	var feet_x: float = shown.position.x + float(shot["feet_x"]) * scale
	var floor_y: float = shown.position.y + float(used.end.y) * scale
	_preview.draw_line(
		Vector2(feet_x, shown.position.y), Vector2(feet_x, shown.end.y), FEET_COLOR, 1.0
	)
	_preview.draw_line(
		Vector2(shown.position.x, floor_y), Vector2(shown.end.x, floor_y), FEET_COLOR, 1.0
	)


# ── 载入 ────────────────────────────────────────────────────────


func _on_pick_video() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.mp4,*.mov,*.mkv,*.webm ; 视频"])
		_dialog.file_selected.connect(_on_video_chosen)
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _on_video_chosen(path: String) -> void:
	_video = path
	_video_label.text = path.get_file()
	_say("选好了。点「抽帧并载入」——一段 97 帧大约十几秒。")


## 跑 ffmpeg 抽帧，然后立刻载入。
##
## **抽帧和载入是一个按钮**：分成两个的话，「抽完了但没载入」是一个
## 屏幕上看不出来的状态，而人会以为工具没反应。
func _on_extract() -> void:
	if _video == "":
		_say("[color=#e06666]先选一段视频。[/color]")
		return
	_say("正在抽帧…（这一步会卡住编辑器十几秒，正常）")
	var err := _forge.extract(_video, _mid_dir())
	if err != "":
		_say("[color=#e06666]%s[/color]" % err)
		return
	_load_current()


## 把当前段的中间帧量一遍、显示第一帧。**读盘不跑 ffmpeg** ——
## 视频没变、只想重新挑帧时走这条。
func _load_current() -> void:
	_shots = _forge.measure(_mid_dir())
	_index = 0
	_slider.max_value = float(maxi(_shots.size() - 1, 0))
	if _shots.is_empty():
		_texture = null
		_preview.queue_redraw()
		_say("[color=#e06666]%s 里一帧都没有 —— 先抽帧。[/color]" % _mid_dir())
		return
	_show(0)
	_refresh_list()
	_say("载入 %d 帧。← → 翻帧，看中了按「＋ 要这一帧」。" % _shots.size())


## 翻到第 [param to] 帧。**钳在两头**，不循环 —— 翻到尾巴自己停住，
## 比绕回第 0 帧更好判断「是不是已经看完了」。
func _show(to: int) -> void:
	if _shots.is_empty():
		return
	_index = clampi(to, 0, _shots.size() - 1)
	_slider.set_value_no_signal(float(_index))
	var image := Image.load_from_file(_shots[_index]["path"])
	_texture = ImageTexture.create_from_image(image) if image != null else null
	_count_label.text = "第 %d / %d 帧%s" % [
		_index, _shots.size() - 1, "　✓已选" if _picked().has(_index) else ""
	]
	var used: Rect2i = _shots[_index]["used"]
	_measure_label.text = "包围盒 %d×%d　脚底 x=%.1f" % [
		used.size.x, used.size.y, float(_shots[_index]["feet_x"])
	]
	_preview.queue_redraw()


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
	var err := _write_take(key, anim, shots, picked, scale)
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
## 四段一起导的那一版没有这个洞（表总是紧跟着重生成），
## **是 M6-n 拆按钮拆出来的**。所以这里不是「②偷偷做了③的事」——
## 是②必须维持它自己弄坏的那个不变量。表还不存在时什么都不做，
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

	var scales := _forge.scales(takes)
	var canvas := _forge.fit_canvas(takes, scales, chosen)
	for anim: String in PBActorForge.anim_names():
		var err := _write_take(key, anim, takes[anim], chosen[anim], float(scales[anim]))
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


## 把一段缩好、写盘。**两个导出按钮共用这一份** —— 各写一份的话
## 「①出的帧和②出的帧差一像素」迟早发生，而它不报错。
func _write_take(key: String, anim: String, shots: Array, picked: Array, scale: float) -> String:
	var images: Array[Image] = []
	for index: int in picked:
		images.append(_forge.compose(shots[index], scale))
	return _forge.save_frames(key, anim, images)


## 这一段的缩放比。**`dead` 借用 `idle` 的** —— 人躺着，包围盒高度不是身高，
## 照自己算的话他会被放大到站着那么"高"。
##
## 所以导 `dead` 那一段要求 `idle` 的中间帧还在盘上。返回 0 = 说过话了、别往下走。
func _scale_for(anim: String, shots: Array) -> float:
	var takes: Dictionary = {anim: shots}
	if anim == "dead":
		var idle := _forge.measure("%s/idle" % MID_ROOT)
		if idle.is_empty():
			_say(
				(
					"[color=#e06666]导 dead 要先抽一次 idle 的帧 —— 人躺着，"
					+ "包围盒高度不是身高，缩放比得借 idle 的。[/color]"
				)
			)
			return 0.0
		takes["idle"] = idle
	return float(_forge.scales(takes).get(anim, 0.0))


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
