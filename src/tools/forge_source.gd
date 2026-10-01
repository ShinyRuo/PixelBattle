@tool
class_name PBForgeSource
extends VBoxContainer
## 「战场形象」面板里**帧从哪来**那一段。两条路，下拉框选一条，另一条的按钮收起来（玩家定的）：
##
## | 来源 | 干什么 | 出处 |
## | ---- | ------ | ---- |
## | **视频** | 喂一段视频，ffmpeg 抽帧 | [method PBActorForge.extract] |
## | **图集** | 喂一张 2×3 六格图，按空白带切 | [PBSheetCutter] |
##
## 两条路产出**完全一样**（`build/aires/mid/<段>/` 里一帧一个 png），下游一个字都不用改；加第三条路也只动这里。
## 按钮藏起来而不是灰掉：这一栏只有 264 像素宽，另一条路的按钮这一整趟都用不到。

## 帧已经写进目录了，面板该重新量一遍。
signal frames_ready

## 状态栏要说的话 —— 面板转发给它自己那块 [RichTextLabel]。
##
## **不自己持有那个标签**：状态栏是面板的东西，两处都能往里写的话，
## 「谁最后说的那句」会由调用顺序偷偷决定。
signal said(text: String)

enum From {
	VIDEO,  ## 一段视频 → ffmpeg
	SHEET,  ## 一张图集 → 按空白带切
}

## 「至少空多少像素才算两格」那个滑块的两头，见 [constant PBSheetCutter.DEFAULT_GAP]。
const GAP_MIN: int = 8
const GAP_MAX: int = 160

var _forge: PBActorForge = null
var _dir: String = ""
var _video: String = ""
var _sheet: String = ""

var _from_pick: OptionButton
var _video_box: Control
var _sheet_box: Control
var _video_label: Label
var _sheet_label: Label
var _gap: HSlider
var _gap_label: Label
var _tol: HSlider
var _tol_label: Label
var _dialog: FileDialog


func _ready() -> void:
	_from_pick = OptionButton.new()
	_from_pick.add_item("视频（跑 ffmpeg 抽帧）")
	_from_pick.add_item("图集（一张图 6 格，切开）")
	_from_pick.item_selected.connect(func(_i: int) -> void: _use_from())
	add_child(_titled("这一段的帧从哪来", _from_pick))
	add_child(_build_video())
	add_child(_build_sheet())
	_use_from()


## 面板建好之后把流水线和当前段的目录交过来。
func bind(forge: PBActorForge) -> void:
	_forge = forge


## 换段了 —— 抽帧/切图要写进哪个目录跟着换。
##
## **每次换段都要调**：不调的话人在下拉框里切到 `run`，抽出来的帧却写进了
## `idle` 的目录，而两边的帧长得都像这个角色，翻一遍才发现不对。
func aim_at(dir_path: String) -> void:
	_dir = dir_path


## 这条路出的四段要不要共用 `idle` 的缩放比（见 [method PBActorForge.scales]）。
##
## **图集要，视频不要**：图集六格全是同一种姿势，`run` 那张最高的一格也是弓着腰的，照它归一化会把跑动的人放大四成；
## 视频一段几十帧里总有一帧是站直的。**跟着下拉框走，不是另一个勾** —— 分开的话忘了勾的表现是跑动那段大四成。
func shares_idle_scale() -> bool:
	return _from_pick != null and maxi(_from_pick.selected, 0) == From.SHEET


func _build_video() -> Control:
	var box := VBoxContainer.new()
	_video_label = Label.new()
	_video_label.text = "（还没选视频）"
	_video_label.clip_text = true
	box.add_child(_video_label)
	box.add_child(_button("选视频…", _on_pick_video))
	box.add_child(_button("抽帧并载入（跑 ffmpeg）", _on_extract))
	_video_box = box
	return box


func _build_sheet() -> Control:
	var box := VBoxContainer.new()
	_sheet_label = Label.new()
	_sheet_label.text = "（还没选图集）"
	_sheet_label.clip_text = true
	box.add_child(_sheet_label)
	box.add_child(_button("选图集…", _on_pick_sheet))
	_gap_label = Label.new()
	box.add_child(_gap_label)
	_gap = HSlider.new()
	_gap.min_value = float(GAP_MIN)
	_gap.max_value = float(GAP_MAX)
	_gap.step = 1.0
	_gap.value = float(PBSheetCutter.DEFAULT_GAP)
	_gap.value_changed.connect(func(_v: float) -> void: _refresh_gap())
	box.add_child(_gap)
	_tol_label = Label.new()
	box.add_child(_tol_label)
	_tol = HSlider.new()
	_tol.min_value = 0.05
	_tol.max_value = 0.60
	_tol.step = 0.01
	_tol.value = PBSheetCutter.DEFAULT_TOL
	_tol.value_changed.connect(func(_v: float) -> void: _refresh_gap())
	box.add_child(_tol)
	box.add_child(_button("切图并载入", _on_cut))
	_sheet_box = box
	_refresh_gap()
	return box


func _use_from() -> void:
	var now: int = maxi(_from_pick.selected, 0)
	_video_box.visible = now == From.VIDEO
	_sheet_box.visible = now == From.SHEET


func _refresh_gap() -> void:
	_gap_label.text = "两格之间至少空 %d 像素" % _gap_size()
	_tol_label.text = "抠底容差 %.2f（背景没抠干净就调大）" % _tol_size()


func _gap_size() -> int:
	return int(_gap.value)


func _tol_size() -> float:
	return _tol.value


# ── 视频 ────────────────────────────────────────────────────────


func _on_pick_video() -> void:
	_pick("*.mp4,*.mov,*.mkv,*.webm ; 视频", _on_video_chosen)


func _on_video_chosen(path: String) -> void:
	_video = path
	_video_label.text = path.get_file()
	said.emit("选好了。点「抽帧并载入」——一段 97 帧大约十几秒。")


## 跑 ffmpeg 抽帧，然后立刻载入。
##
## **抽帧和载入是一个按钮**：分成两个的话，「抽完了但没载入」是一个
## 屏幕上看不出来的状态，而人会以为工具没反应。
func _on_extract() -> void:
	if not _ready_to_run():
		return
	if _video == "":
		said.emit("[color=#e06666]先选一段视频。[/color]")
		return
	said.emit("正在抽帧…（这一步会卡住编辑器十几秒，正常）")
	var err := _forge.extract(_video, _dir)
	if err != "":
		said.emit("[color=#e06666]%s[/color]" % err)
		return
	frames_ready.emit()


# ── 图集 ────────────────────────────────────────────────────────


func _on_pick_sheet() -> void:
	_pick("*.png,*.jpg,*.jpeg,*.webp ; 图集", _on_sheet_chosen)


func _on_sheet_chosen(path: String) -> void:
	_sheet = path
	_sheet_label.text = path.get_file()
	said.emit("选好了。点「切图并载入」—— 切完 ← → 翻一遍，确认没切歪。")


## 切图并载入。
##
## 顺序是**先抠背景、再按空白带切**（见 [PBSheetCutter] 类顶）：投影只看
## alpha 才够快，而抠出来的透明底正好也是下游要的那种帧
## （[method PBActorForge.compose] 假设源帧是预乘过的）。
func _on_cut() -> void:
	if not _ready_to_run():
		return
	if _sheet == "":
		said.emit("[color=#e06666]先选一张图集。[/color]")
		return
	var sheet := Image.load_from_file(_sheet)
	if sheet == null:
		said.emit("[color=#e06666]读不出这张图：%s[/color]" % _sheet)
		return
	said.emit("正在切图…（这一步会卡住编辑器几秒，正常）")
	# **背景色是量出来的，不是假设的**：出图模型给的背景离纯洋红有一段距离，拿纯洋红去抠一个像素都抠不掉。
	# 见 [method PBSheetCutter.guess_key]。
	var key := PBSheetCutter.guess_key(sheet)
	PBSheetCutter.key_out(sheet, key, _tol_size())
	var cells := PBSheetCutter.cut(sheet, _gap_size(), PBSheetCutter.DEFAULT_CELL, cells_wanted())
	if cells.is_empty():
		said.emit(
			(
				(
					"[color=#e06666]一格都没切出来。[/color]量出来的背景色是 [b]#%s[/b] —— "
					+ "不是这张图的底色的话，说明人物占的地方比背景还多。"
				)
				% key.to_html(false)
			)
		)
		return
	var err := _write(sheet, cells)
	if err != "":
		said.emit("[color=#e06666]%s[/color]" % err)
		return
	frames_ready.emit()
	_report(cells.size(), key)


## 把切好的格子写成一帧一个 png。**编号从 1 起**，和 ffmpeg 的 `%03d` 一致 ——
## [method PBActorForge.measure] 按文件名排序，两条路因此排出同一个顺序。
func _write(sheet: Image, cells: Array[Rect2i]) -> String:
	_forge.wipe_frames(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	for i: int in cells.size():
		var cell := sheet.get_region(cells[i])
		var err := cell.save_png("%s/%03d.png" % [_dir, i + 1])
		if err != OK:
			return "第 %d 格存不下来（%d）：%s" % [i + 1, err, _dir]
	return ""


## 一张图集该有几格。**从 [member PBSimConfig.anim_frames] 来，不写死 6** ——
## 图集的格数就是一段动画的帧数，两处各写一个 6 的话，哪天默认帧数变了，
## 这块面板会一直报「切出 8 格，不是 6 格」而其实是对的。
static func cells_wanted() -> int:
	return PBSimConfig.new().anim_frames


## 切出几格要说出来。**不对就标黄** —— 切歪了之后每一帧看起来
## 都很正常（就是一个人站在洋红底上），只有数一数才发现少了一格
## 或者一个人被劈成了两半。
func _report(count: int, key: Color) -> void:
	var tone: String = "底色 #%s" % key.to_html(false)
	var want: int = cells_wanted()
	if count == want:
		said.emit("[color=#71d08c]切出 %d 格[/color]（%s）。← → 翻一遍确认没切歪，再挑帧。" % [want, tone])
		return
	if count == 1:
		said.emit(("[color=#e06666]只切出 1 格 —— 背景没抠掉。[/color]量出来的 %s，" + "把「抠底容差」往上调再重切。") % tone)
		return
	if count < want:
		# 走到这里说明连补刀都没救回来 —— 滑块只能让更窄的缝也算缝，两只重叠时那道缝是负的。
		said.emit(
			(
				(
					"[color=#e0a666]切出 %d 格，少了 %d 格[/color]（%s）。两只叠在一起了，"
					+ "连按最深的谷补刀都切不开 —— 把这一段重出一版（宽的生物排成"
					+ "3 行 2 列，每格宽一倍就挤得开），或者在图上把它们之间涂一条底色。"
				)
				% [count, want - count, tone]
			)
		)
		return
	said.emit(
		(
			("[color=#e0a666]切出 %d 格，多了 %d 格[/color]（%s）。一个人被切成两半了，" + "把「至少空多少」调大再重切。")
			% [count, count - want, tone]
		)
	)


# ── 小工具 ──────────────────────────────────────────────────────


func _ready_to_run() -> bool:
	if _forge == null or _dir == "":
		said.emit("[color=#e06666]面板还没接好（没有目标目录）。[/color]")
		return false
	return true


## 两条路共用一个 [FileDialog]，只换过滤器 —— 各建一个的话，
## 「上次停在哪个文件夹」会分成两份。
func _pick(filter: String, on_chosen: Callable) -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		add_child(_dialog)
	for old: Dictionary in _dialog.file_selected.get_connections():
		_dialog.file_selected.disconnect(old["callable"])
	_dialog.file_selected.connect(on_chosen)
	_dialog.filters = PackedStringArray([filter])
	_dialog.popup_centered_ratio(0.6)


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
