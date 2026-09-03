class_name PBUnitTile
extends Control
## 一张卡在编队页上的样子：**一个可拖动、可悬停的小方块**。M3-e。
##
## ## 这是白模图标，不是美术
##
## 真美术在 M5（§14：白模阶段不动 `assets/`）。在那之前一张卡靠三件事认：
##
## 1. **底色 = 属性** —— 与 [constant PBEnemyPool.ELEMENT_COLORS] 同一套色相，
##    所以战场上看到的颜色和编队页上的是同一个
## 2. **边框 = 稀有度** —— 灰 / 蓝 / 紫 / 金，四档一眼分得开
## 3. **角标 = 星级** —— 只有升过星才画，没升的不占视觉噪声
##
## 换成真图标时改的是本类，其余一行不动 —— 编队页只认 [method set_unit]。
##
## ## 拖放走引擎内建的那套，不自己算鼠标
##
## `_get_drag_data` / `_can_drop_data` / `_drop_data` 是 [Control] 自带的协议：
## 引擎负责按住、跟随、松手判定，还免费给一个跟着鼠标走的预览。
## 自己监听 `InputEventMouseButton` 再算矩形碰撞的话，要重写一遍拖影、
## 边界钳制和「拖到窗口外松手」的处理，而那三样每一样都能单独出 bug。

## 鼠标进了这个格子。[param tile] 是自己 —— 详情栏要问它是谁。
signal hovered(tile: PBUnitTile)

## 鼠标离开了。
signal exited(tile: PBUnitTile)

## 玩家点了这个格子（§02 的战场直接操作，M3.5-e）。
##
## 和 [signal hovered] 分开：悬停是「让我看看」，点击是「我选它了」。
## 用悬停当选中的话，鼠标划过一排头像会把选中拖着走，
## 而指令卡跟着一路重画 —— 那既点不准，也看不清。
signal picked(tile: PBUnitTile)

## 有人把一张卡拖到了这个格子上。
signal dropped(from_zone: StringName, unit_id: StringName, to_zone: StringName)

## 一张卡此刻在哪一区。**三档互斥**，也就是屏幕上的三块地方：
## 战场（在打）、仓库（存着）、任务栏（这一波出去做任务）。
## 拖放就是在这三者之间搬，[method PBBattleView._on_card_moved] 一处兑现。
const ZONE_FIELD: StringName = &"field"
const ZONE_STASH: StringName = &"stash"
const ZONE_QUEST: StringName = &"quest"

## 稀有度边框色。下标对齐 [enum PBUnit.Rarity]。
const RARITY_COLORS: Array[Color] = [
	Color(0.45, 0.47, 0.52),  # R
	Color(0.35, 0.60, 0.88),  # SR
	Color(0.68, 0.45, 0.90),  # SSR
	Color(0.95, 0.75, 0.30),  # USR
]

const RARITY_NAMES: Array[String] = ["R", "SR", "SSR", "USR"]

## 属性的单字名。**全项目唯一一份** —— 界面各处都从这里取。
const ELEMENT_NAMES := {
	PBElement.Type.FIRE: "火",
	PBElement.Type.WIND: "风",
	PBElement.Type.THUNDER: "雷",
	PBElement.Type.EARTH: "土",
	PBElement.Type.WATER: "水",
	PBElement.Type.PHYSICAL: "物",
}

## 波型名。**和 [constant ELEMENT_NAMES] 摆在一起是有意的** ——
## 界面各处要显示「第 12 波　雷　潮水」这一串，两半分开放的话
## 第二半迟早被人就地再写一遍（M4-f 之前 [PBBattleView] 里就有一份）。
##
## 这个类叫「卡面」而波型不是卡的属性，确实有点勉强。但它已经是
## 界面事实上的标签表（四个文件从这里取属性名），而**多开一个类
## 只装两个字典**会让「该去哪儿找名字」这个问题多一个答案。
const SHAPE_NAMES := {
	PBWave.Shape.SWARM: "潮水",
	PBWave.Shape.ELITE: "精英",
	PBWave.Shape.BOSS: "BOSS",
	PBWave.Shape.MEGA_BOSS: "大BOSS",
	PBWave.Shape.NORMAL: "常规",
}

const TILE_SIZE := Vector2(30.0, 34.0)

## 这个格子在本区里的下标。空格子也有下标 —— 拖到空格子上就是「放到这个位置」。
var slot: int = 0

var zone: StringName = ZONE_STASH

## 格子里的卡。**`null` 表示空位**，空位仍然可以被拖入。
var unit: PBUnit = null

var _border: Panel
var _body: ColorRect
var _element: Label
var _rarity: Label
var _star: Label


func _ready() -> void:
	custom_minimum_size = TILE_SIZE
	size = TILE_SIZE
	# STOP 而不是 PASS：格子要自己收 hover 和拖放，不能把事件漏给底下的面板。
	mouse_filter = Control.MOUSE_FILTER_STOP

	# 边框走 [Panel] + [StyleBoxFlat]（圆角），底色仍是一块 [ColorRect]。
	# **描边的颜色靠 `modulate` 换，不重建样式** —— 仓库那一屏一次要摆
	# 三十几个格子，每次重画都 new 一个 StyleBoxFlat 太浪费。
	_border = Panel.new()
	_border.size = TILE_SIZE
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_border.add_theme_stylebox_override(
		"panel", PBSkin.box(PBSkin.PANEL_DEEP, Color.WHITE, PBSkin.RADIUS, 1)
	)
	add_child(_border)

	_body = _add_rect(Vector2(2.0, 2.0), TILE_SIZE - Vector2(4.0, 4.0))
	_element = _add_label(Vector2(3.0, 0.0), 11)
	_rarity = _add_label(Vector2(2.0, 17.0), 8)
	_star = _add_label(Vector2(16.0, 17.0), 8)

	mouse_entered.connect(func() -> void: hovered.emit(self))
	mouse_exited.connect(func() -> void: exited.emit(self))
	clear()


## 把这个格子缩到 [param to] 那么大。M6-k：任务栏那 4 个槽要排成一横排，
## 而 100 像素宽的一列装不下四个 30 宽的格子。
##
## ## 为什么是「缩」而不是「另做一个小格子」
##
## 缩的是同一个类：底色、稀有度描边、克制亮边三样规则一个字都不变。
## 另做一份的话，「克制系描亮边」这条 §03 最值钱的信息迟早只在一处更新，
## 而那不报错 —— 玩家只会觉得任务栏里的卡「看起来跟仓库里不一样」。
##
## **字号跟着一起缩**：位置按比例挪、字号取比例的整数倍。
## 只挪位置不缩字的话，11 号的属性字会宽出 21 像素的格子，
## 而溢出的那一截**只是画在格子外面**，不报错（[PBLayout] 顶上那条断言
## 讲的就是这种失败）。
func shrink_to(to: Vector2) -> void:
	var ratio: Vector2 = to / TILE_SIZE
	custom_minimum_size = to
	size = to
	_border.size = to
	_body.position = Vector2(1.0, 1.0)
	_body.size = to - Vector2(2.0, 2.0)
	_element.position = Vector2(2.0, -1.0)
	_element.size.x = to.x - 3.0
	_rarity.position = Vector2(1.0, roundf(17.0 * ratio.y))
	_star.position = Vector2(roundf(16.0 * ratio.x), roundf(17.0 * ratio.y))
	_element.add_theme_font_size_override(&"font_size", maxi(int(11.0 * ratio.x), 6))
	for label: Label in [_rarity, _star]:
		label.add_theme_font_size_override(&"font_size", maxi(int(8.0 * ratio.x), 6))


## 放一张卡进来。[param wave_element] 决定描什么边 —— 见函数体里那段克制编码。
func set_unit(card: PBUnit, wave_element: PBElement.Type) -> void:
	unit = card
	if card == null:
		clear()
		return
	var rarity := RARITY_COLORS[clampi(int(card.rarity), 0, RARITY_COLORS.size() - 1)]
	_body.color = PBEnemyPool.ELEMENT_COLORS.get(card.element, Color.WHITE).darkened(0.45)
	_border.modulate = rarity
	_element.text = ELEMENT_NAMES.get(card.element, "?")
	_element.modulate = PBEnemyPool.ELEMENT_COLORS.get(card.element, Color.WHITE)
	_rarity.text = RARITY_NAMES[int(card.rarity)]
	_rarity.modulate = rarity
	# 没升过星就不画 —— 一排 ★1 是纯噪声，而「这张升过星」是要一眼看到的。
	_star.text = "★%d" % card.star() if card.star() > 1 else ""

	# §03 的克制关系，直接画在格子上：克制系描亮边、被克的压暗。
	# 这是编队页上最值钱的一格信息 —— 原版要点开技能说明才看得到。
	match PBElement.relation(card.element, wave_element):
		PBElement.Relation.COUNTER:
			_border.modulate = PBSkin.TITLE
		PBElement.Relation.WEAK:
			_body.color = _body.color.darkened(0.5)
		_:
			pass


## 变回空位。空位仍然接收拖放（拖到它上面 = 放到这个位置）。
##
## **不碰 `visible`** —— 显不显示是拥有者的决定（出战位不够、仓库空行都要藏），
## 在这里顺手设一下会让那些决定悄悄失效。
func clear() -> void:
	unit = null
	_border.modulate = PBSkin.EDGE_SOFT
	_body.color = PBSkin.PANEL_DEEP
	_element.text = ""
	_rarity.text = ""
	_star.text = ""


## 左键点在有卡的格子上 = 选中它。
##
## 走 `_gui_input` 而不是 `mouse_entered`：见 [signal picked]。
## 空格子不发 —— 选中一个空位没有任何指令可给。
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var button := event as InputEventMouseButton
	if button.pressed and button.button_index == MOUSE_BUTTON_LEFT and unit != null:
		picked.emit(self)
		accept_event()


## 拖放载荷：**谁**从**哪一区**被拖起来了。
##
## **载的是角色 id，不是格子下标。** 下标那一版（M3-e 的编队页）在
## 会滚动、会重排的名单上直接坏掉：拖到一半名单少一个人，
## 后面所有人的下标挪一位，手上拖的就换了个人 —— 而那不报错。
## [member PBRunState.formation] 按 id 存也是同一条理由。
##
## 空的返回 `{}`，调用方用 `is_empty()` 判。
static func card_of(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var payload := data as Dictionary
	if not payload.has("zone") or not payload.has("unit"):
		return {}
	return payload


## 引擎的拖放协议：按住空格子不产生拖动。
func _get_drag_data(_at_position: Vector2) -> Variant:
	if unit == null:
		return null
	set_drag_preview(_make_preview())
	return {"zone": zone, "unit": unit.key()}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return not card_of(data).is_empty()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var card := card_of(data)
	if not card.is_empty():
		dropped.emit(StringName(card["zone"]), StringName(card["unit"]), zone)


## 跟着鼠标走的那个影子。引擎会自己摆位置和释放，这里只负责画得像。
func _make_preview() -> Control:
	var ghost := Control.new()
	ghost.size = TILE_SIZE
	var body := ColorRect.new()
	body.size = TILE_SIZE
	body.color = _body.color
	body.modulate = Color(1.0, 1.0, 1.0, 0.8)
	ghost.add_child(body)
	var text := Label.new()
	text.text = _element.text
	text.position = Vector2(3.0, 1.0)
	text.add_theme_font_size_override("font_size", 11)
	text.modulate = _element.modulate
	ghost.add_child(text)
	return ghost


func _add_rect(at: Vector2, of_size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = of_size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func _add_label(at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
