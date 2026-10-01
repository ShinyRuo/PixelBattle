class_name PBFieldSlots
extends Control
## C / D 区：左边那两个可点的形象（**尾兽、大本营**），血条在图顶上。
##
## 两样在一个类里：它们是同一件事（一个能被点、然后在指令卡上出现指令的形象），分开的话
## 「点了 C 要不要取消 D 的选中」会散在两处。用图不用方框按钮：九只尾兽要一眼看得出换了哪只（颜色 + 尾数）。

## 玩家点了某个槽位。
signal slot_picked(kind: PBSelection.Kind, unit_id: StringName)

## **坐标住在 [PBLayout] 里**，这里只取短名字 —— 见那个文件顶上的排版图。
const BEAST_RECT := PBLayout.C_BEAST
const BASE_RECT := PBLayout.D_BASE

## 血条：横在大本营那张图的正上方。**和图一样宽** ——
## 窄一截会让人以为它是别的东西的进度条。
const BAR_HEIGHT: float = 6.0

## 选中时垫在图后面的那块底。**不是描边** —— 图本身是不规则的，
## 沿它描边要逐像素算，而那一圈在 2 倍放大之后会粗得像故障。
const MARK_PAD: float = 3.0

var _beast: TextureRect
var _base: TextureRect
var _beast_label: Label
var _base_label: Label
var _bar_back: ColorRect
var _bar_fill: ColorRect
var _mark: Panel

## 上一次画的是第几尾。**只在换了之后才重建那张图** ——
## 每次刷新都取一次纹理是查表，但赋值会让 [TextureRect] 重新布局。
var _tails: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 选中底垫在最下面，靠 move_child 提到对应位置（和 [PBRosterBay] 同一套）。
	_mark = Panel.new()
	_mark.add_theme_stylebox_override(
		"panel", PBSkin.box(Color(PBSkin.TITLE, 0.22), PBSkin.TITLE, PBSkin.RADIUS, 1)
	)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	add_child(_mark)

	# ── C：尾兽 ──
	_beast = _add_icon(BEAST_RECT, PBIconArt.beast_size(), PBSelection.Kind.BEAST)
	_beast_label = _add_label(BEAST_RECT)

	# ── D：大本营 ──
	# 血条在图的**上方**，所以这张图整体往下让出 BAR_HEIGHT + 2。
	_bar_back = _add_bar(PBSkin.PANEL_DEEP)
	_bar_fill = _add_bar(PBSkin.GOOD)
	_base = _add_icon(BASE_RECT, PBIconArt.base_size(), PBSelection.Kind.BASE, BAR_HEIGHT + 2.0)
	_base.texture = PBIconArt.base()
	_base.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_base.add_child(PBBaseMotion.new())
	_base_label = _add_label(BASE_RECT)


## 按当前状态重画。
func refresh(selection: PBSelection, state: PBRunState, cfg: PBSimConfig) -> void:
	_beast_label.text = "尾兽 Lv%d" % state.beast_level if state.beast_id != &"" else "尾兽 · 未选"
	# 血条和那个数走同一个入口（见 [method show_base_hp]）——
	# 两处各写一份的话，战斗中那个数会停在开波那一刻，而条在动。
	show_base_hp(state.base_hp, cfg.base_hp if cfg != null else 0.0)

	var tails: int = _tail_count(state, cfg)
	if tails != _tails:
		_tails = tails
		_beast.texture = PBIconArt.beast(tails)

	# **每次重画都从头摆一遍。** 增量维护的话，一个形象藏起来时那个底会
	# 留在原地，看起来像选中了空气。
	_mark.visible = true
	match selection.kind:
		PBSelection.Kind.BEAST:
			_show_mark(_beast)
		PBSelection.Kind.BASE:
			_show_mark(_base)
		_:
			_mark.visible = false


## 血条。**每帧调**（[method PBBattleView._sync_base]）—— 战斗中它一直在掉。
##
## 和 [method refresh] 分开是同一条老规矩：那一个要重排文字、查尾兽表，
## 一秒六十次太贵，而血条只是改两个数。
func show_base_hp(hp: float, max_hp: float) -> void:
	var safe: float = clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	_base_label.text = "大本营 %d" % int(maxf(hp, 0.0))
	_bar_fill.size.x = _bar_back.size.x * safe
	# 绿 → 红。**不是三档跳色**：血量是连续量，跳色会让玩家去记阈值。
	_bar_fill.color = PBSkin.GOOD.lerp(PBSkin.BAD, 1.0 - safe)


## 这一局带的是第几尾。**0 = 还没选**，那时画的是带问号的剪影。
##
## 尾数就是它在 [method PBBeastTable.all] 里的序号 + 1 —— 那份顺序来自
## `data/beasts/` 的文件名，前缀就是尾数（装载器按文件名排序）。
##
## **不去解析显示名**（§14 铁律 5）：语言表里那一行是给人看的文案，
## 拿它抠数字等于让界面依赖一句随时可能改的话，而改了不报错。
func _tail_count(state: PBRunState, cfg: PBSimConfig) -> int:
	if state.beast_id == &"" or cfg == null or cfg.beasts == null:
		return 0
	return cfg.beasts.ids().find(state.beast_id) + 1


func _show_mark(on: TextureRect) -> void:
	_mark.position = on.position - Vector2(MARK_PAD, MARK_PAD)
	_mark.size = on.size + Vector2(MARK_PAD, MARK_PAD) * 2.0
	move_child(_mark, 0)


## 一张可点的图，**没有边框和按钮样式**（玩家定的）。收点击靠 `mouse_filter = STOP` + `gui_input`，
## 反馈是选中底（[member _mark]）。
func _add_icon(rect: Rect2, side: float, kind: PBSelection.Kind, drop: float = 0.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.size = Vector2(side, side)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = Vector2(rect.position.x + (rect.size.x - side) * 0.5, rect.position.y + drop)
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.gui_input.connect(
		func(event: InputEvent) -> void:
			var click := event as InputEventMouseButton
			if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
				slot_picked.emit(kind, &"")
	)
	add_child(icon)
	return icon


## 图底下那行字。**居中**：图是居中的，字靠左会看起来像是别人的标题。
func _add_label(rect: Rect2) -> Label:
	var label := PBSkin.label(
		self,
		Vector2(rect.position.x, rect.position.y + rect.size.y - 10.0),
		rect.size.x,
		PBSkin.FONT_BODY,
		PBSkin.DIM
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _add_bar(color: Color) -> ColorRect:
	var bar := ColorRect.new()
	var width: float = PBIconArt.base_size()
	bar.position = Vector2(
		BASE_RECT.position.x + (BASE_RECT.size.x - width) * 0.5, BASE_RECT.position.y
	)
	bar.size = Vector2(width, BAR_HEIGHT)
	bar.color = color
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar
