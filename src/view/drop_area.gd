class_name PBDropArea
extends Control
## 一块**能接住拖过来的卡**的矩形。§02 的拖放三区，M5-4。
##
## ## 为什么需要它
##
## 引擎的拖放协议（`_get_drag_data` / `_can_drop_data` / `_drop_data`）
## 只认 [Control]。而三个区里有两个不是：
##
## - **战场**是一堆 [Node2D] 对象池，忍者是画出来的方块，不是节点树上的控件
## - **仓库**里的空位是**藏起来的**格子，藏起来的控件收不到拖放 ——
##   于是「往空仓库里拖一个人」这条最自然的操作会没有反应
##
## 一块透明的矩形把这两件事一起解决：它盖在那个区上面，
## 负责回答「拖到我这儿了」，具体要做什么由 [PBBattleView] 决定。
##
## ## 为什么坐标发的是屏幕坐标
##
## 战场那块要把落点换成战场坐标（[method PBLayout.to_field]），
## 另外两块根本不在乎落在哪。**换算放在收件人那边做**，
## 这一层只报「在屏幕的这个点松手了」—— 它不知道战场有多大，也不该知道。
##
## ## `MOUSE_FILTER_PASS`
##
## 战场那块盖住了整个战斗区域，而战斗中的点选（M4-e）走的是
## [method PBBattleView._unhandled_input]。`STOP` 会把那些点击全吃掉，
## 表现是「打起来之后点谁都没反应」。`PASS` 收得到拖放，又不挡后面的路。

## 玩家按住本区里的某个单位开始拖。**只有给了 [member unit_at] 的区才发** ——
## 格子（[PBUnitTile]）自己会拖，不需要这一层代劳。
signal grabbed(unit_id: StringName)

## 拖动中，鼠标正停在本区上（引擎每帧问一次）。用来让被拖的人跟着鼠标走。
signal hovered(from_zone: StringName, unit_id: StringName, at: Vector2)

## 在本区松手了。[param at] 是**屏幕坐标**。
signal card_dropped(from_zone: StringName, unit_id: StringName, at: Vector2)

## 松手的是一件**装备**（M5-5）。
##
## 和卡分成两条信号，不是一条带类型标记的：同一块面板上两种东西
## 要做的事完全不同（挂装备 vs 换人），合成一条的话每个收件人
## 第一行都得先分流，而漏掉那一行不报错 —— 只表现为「拖过去没反应」。
signal item_dropped(from_zone: StringName, item_id: StringName)

## 本区的名字，会进拖放载荷。见 [PBUnitTile] 那三个 `ZONE_` 常量。
var zone: StringName = &""

## 屏幕上那个点站着谁，返回空 [StringName] 表示没人。
##
## **默认是个空 [Callable]，也就是「本区拖不出东西」** ——
## 仓库和任务栏里拖得动的是格子自己，这一层只负责接。
var unit_at: Callable = Callable()


## 摆到 [param rect] 上，认领 [param of_zone]。**不在 `_ready` 里读 [PBLayout]** ——
## 同一个类要盖三个不同的区，位置只能由拥有者给。
## [param hit] 给了才拖得出东西，见 [member unit_at]。
func cover(rect: Rect2, of_zone: StringName, hit := Callable()) -> void:
	position = rect.position
	size = rect.size
	zone = of_zone
	unit_at = hit
	mouse_filter = Control.MOUSE_FILTER_PASS


func _get_drag_data(at: Vector2) -> Variant:
	if not unit_at.is_valid():
		return null
	var unit_id: StringName = unit_at.call(at + position)
	if unit_id == &"":
		return null
	grabbed.emit(unit_id)
	set_drag_preview(_ghost())
	return {"zone": zone, "unit": unit_id}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not PBItemTile.item_of(data).is_empty():
		return true
	var card := PBUnitTile.card_of(data)
	if card.is_empty():
		return false
	# **每帧发一次**，不是松手才发：拖动过程中战场上那个方块要跟着鼠标走，
	# 否则玩家会以为没拖起来（M4-f 那一版的原话）。
	hovered.emit(StringName(card["zone"]), StringName(card["unit"]), at + position)
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	var item := PBItemTile.item_of(data)
	if not item.is_empty():
		item_dropped.emit(StringName(item["zone"]), StringName(item["item"]))
		return
	var card := PBUnitTile.card_of(data)
	if card.is_empty():
		return
	card_dropped.emit(StringName(card["zone"]), StringName(card["unit"]), at + position)


## 跟着鼠标走的影子。战场上拖的是一个方块，这里也画一个方块 ——
## 拖起来变成另一种东西会让人以为自己抓错了。
func _ghost() -> Control:
	var dot := ColorRect.new()
	dot.size = Vector2(11.0, 11.0)
	dot.color = Color(1.0, 1.0, 1.0, 0.7)
	return dot
