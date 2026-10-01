class_name PBSystemMenu
extends PBModal
## `Esc` 呼出的功能菜单：继续 / 图形 / 退出游戏。
##
## **它是 `Esc` 链的最后一层**（说明卡 → 弹层 → 瞄准 → 选中 → 菜单）：挡着一张说明卡时那一下的意思是「先收掉」。
## **它自己不听 `Esc`**：这一层在 HUD 里、比根节点先收到事件，想听就一定抢在链前面 ——
## 顺序只由 [PBBattleView] 一处裁决。
## **两页共用一块面板**（[PBModal] 一次只摊一层）：在图形页按 `Esc` 回主页，在主页按 `Esc` 关掉。

## 玩家选了「继续」，或者按 `Esc` 关掉了。
signal resumed

## 玩家选了「退出游戏」。**本层不自己退** —— 退出要不要先存档、
## 要不要二次确认，那是整局的事，不是一块面板的事。
signal quit_requested

enum Page { MAIN, GRAPHICS }

## 按钮尺寸与行距。三个按钮竖排居中。
const BUTTON: Vector2 = Vector2(104.0, 17.0)
const ROW_GAP: float = 6.0
const BODY_H: float = 78.0

## 下拉框那一行：左边标题占多宽，右边控件占多宽。
const FIELD_LABEL_W: float = 46.0
const FIELD_W: float = 104.0
const FIELD_H: float = 15.0

var _page: int = Page.MAIN
var _main: Control
var _graphics: Control
var _sizes: OptionButton


func _ready() -> void:
	super()
	set_title("菜单")
	_show_page(Page.MAIN)


## 摊开来，一律从主页开始。**不记上次停在哪一页** ——
## 玩家按 `Esc` 想要的是那三个选项，不是他上次翻到的设置项。
func open() -> void:
	_show_page(Page.MAIN)
	# **主页也要刷一遍下拉框。** 只在翻到图形页时刷的话，摊开到翻过去之间
	# 那一格里挂着的是 [method OptionButton.add_item] 自动选中的第一项 ——
	# 也就是「1280×720」，不管窗口其实多大。看不见不等于没错：
	# 那是一个已经写好的谎，只等一次翻页把它端出来。
	refresh()
	super()


## `Esc` 落到这一层时该做什么：在图形页退回主页（返回 `true`），在主页交给调用方去关（返回 `false`）。
## 判断和执行在同一处，否则加第三页的那天两边就分叉了。
func back() -> bool:
	if _page == Page.GRAPHICS:
		_show_page(Page.MAIN)
		return true
	return false


## 菜单里的分辨率下拉框**只在打开时同步一次**。玩家可能刚按过 `F10`/`F11`，
## 而一个显示着 1280×720 的下拉框配一个 1080p 的窗口，是在说谎。
func refresh() -> void:
	var current := DisplayServer.window_get_size()
	for i: int in PBDisplay.SIZES.size():
		if PBDisplay.SIZES[i] == current:
			_sizes.select(i)
			return
	# 不在档位表里（玩家手动拖过窗口边，或者正全屏）——**不选中任何一项**，
	# 而不是硬指一个。指错的那一项会让人以为「我已经是这个分辨率了」。
	_sizes.select(-1)


func _body_height() -> float:
	return BODY_H


func _build_body() -> void:
	_main = _page_root()
	_graphics = _page_root()
	_build_main()
	_build_graphics()


## 主页那三个。**「退出游戏」放最下面，和「继续」隔着一整行** ——
## 两个不可逆程度差最远的选项挨着放，是最容易误点的排法。
func _build_main() -> void:
	var rows: Array = [
		["继续", func() -> void: resumed.emit(), PBSkin.Tone.PRIMARY],
		["图形", func() -> void: _show_page(Page.GRAPHICS), PBSkin.Tone.PLAIN],
		["退出游戏", func() -> void: quit_requested.emit(), PBSkin.Tone.QUIET],
	]
	var left: float = (panel_rect().size.x - BUTTON.x) * 0.5
	for i: int in rows.size():
		var row: Array = rows[i]
		var button := Button.new()
		button.text = row[0] as String
		button.size = BUTTON
		button.position = Vector2(left, 6.0 + float(i) * (BUTTON.y + ROW_GAP))
		button.focus_mode = Control.FOCUS_NONE
		PBSkin.style_button(button, row[2] as PBSkin.Tone)
		button.pressed.connect(row[1] as Callable)
		_main.add_child(button)


## 图形页：现在只有一个下拉框。**留着「返回」按钮** ——
## `Esc` 是第二条路，而手在鼠标上的时候不该被逼着去够键盘（§01 要双端）。
func _build_graphics() -> void:
	var left: float = (panel_rect().size.x - FIELD_LABEL_W - FIELD_W) * 0.5
	var label := PBSkin.label(
		_graphics, Vector2(left, 9.0), FIELD_LABEL_W, PBSkin.FONT_BODY, PBSkin.TEXT
	)
	label.text = "分辨率"
	_sizes = OptionButton.new()
	_sizes.size = Vector2(FIELD_W, FIELD_H)
	_sizes.position = Vector2(left + FIELD_LABEL_W, 6.0)
	_sizes.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(_sizes, PBSkin.Tone.PLAIN)
	for size: Vector2i in PBDisplay.SIZES:
		_sizes.add_item("%d × %d" % [size.x, size.y])
	# 加第一项时引擎会顺手选中它。**先撤掉** —— 到底选哪一项只由
	# [method refresh] 按真实窗口决定，这里留一个自动选中的等于先写下一个谎。
	_sizes.select(-1)
	_sizes.item_selected.connect(_on_size_picked)
	_graphics.add_child(_sizes)

	var back_button := Button.new()
	back_button.text = "返回"
	back_button.size = BUTTON
	back_button.position = Vector2((panel_rect().size.x - BUTTON.x) * 0.5, BODY_H - BUTTON.y - 6.0)
	back_button.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(back_button, PBSkin.Tone.QUIET)
	back_button.pressed.connect(func() -> void: _show_page(Page.MAIN))
	_graphics.add_child(back_button)


func _on_size_picked(index: int) -> void:
	if index >= 0 and index < PBDisplay.SIZES.size():
		PBDisplay.set_window(PBDisplay.SIZES[index])


## 一页的容器。不吃鼠标，子控件照常收事件 —— 和 [method PBModal.body] 同理。
func _page_root() -> Control:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body().add_child(page)
	return page


func _show_page(page: int) -> void:
	_page = page
	_main.visible = page == Page.MAIN
	_graphics.visible = page == Page.GRAPHICS
	if page == Page.GRAPHICS:
		refresh()
		set_hint("窗口大小。游戏永远按 640×360 渲染，这里只改放大几倍。")
		return
	set_hint("Esc 关掉菜单接着打。")


func _closable() -> bool:
	# 不给右上角那个关闭按钮：「继续」就是它，两个做同一件事的按钮
	# 只会让人怀疑它们不一样。
	return false
