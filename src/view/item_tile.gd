class_name PBItemTile
extends Control
## 一件装备或一个配件在面板上的样子：**一个小方块 + 一个数字**。§10 / §02，M5-5。
##
## ## 为什么不复用 [PBUnitTile]
##
## 那个格子 30×34，装的是「属性底色 + 稀有度边框 + 星级角标」——
## 三样都是角色才有的东西。装备要说的是另外三样：**分类**（决定挂不挂得上）、
## **是成品还是配件**（决定拖不拖得动）、**有几个**。
## 硬塞进同一个类的话，那个类会长出一串「如果我装的是装备就……」。
##
## ## 分类靠颜色，不靠文字
##
## 一格 20×20 写不下「法术装」三个字。三档分类各占一个色相，
## 而**具体是哪一件、加多少、要什么配件全在点开的说明卡里**（[PBTooltip]）。
## 这不是省事：§10 的分类匹配决定「挂不挂得上」，那是要一眼扫完整排的信息，
## 而读三个字比认一个颜色慢得多。
##
## ## 配件拖不动
##
## 拖动的意思是「挂到某个人身上」，而配件挂不上任何人 ——
## 它要先按配方合成成品。拖得动但拖过去没反应，比拖不动更让人困惑。

## 玩家点了这个格子（要看说明）。
signal picked(tile: PBItemTile)

## 三档分类的颜色。和 [enum PBEquipItem.Category] 对齐。
const CATEGORY_COLORS: Array[Color] = [
	Color(0.85, 0.45, 0.35),  # 物理
	Color(0.45, 0.55, 0.90),  # 法术
	Color(0.50, 0.72, 0.55),  # 坦克
]

## 配件（还没合成的半成品）的底色：**灰的**，一眼看出「这还不是装备」。
const PART_COLOR := Color(0.36, 0.38, 0.45)

const TILE_SIZE := Vector2(20.0, 20.0)

## 这一格代表哪件东西。成品是装备 id，配件是配件 id。
var item_id: StringName = &""

## 成品才拖得动（见类顶部）。
var draggable: bool = false

## 拖出去时报的区名，见 [PBUnitTile] 那几个 `ZONE_` 常量。
var zone: StringName = &""

var _body: ColorRect
var _count: Label


func _ready() -> void:
	custom_minimum_size = TILE_SIZE
	size = TILE_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_body = ColorRect.new()
	_body.size = TILE_SIZE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_count = PBSkin.label(self, Vector2(2.0, 9.0), TILE_SIZE.x - 2.0, PBSkin.FONT_BODY)


## 摆一件成品。[param count] 是仓库里有几件；[param dim] 为真表示
## 这个人吃不下它（分类不匹配），压暗但仍然摆出来 ——
## **去掉的话玩家看到的是「仓库里明明有，这里却没有」**，他会以为界面坏了。
func set_item(item: PBEquipItem, count: int, dim: bool = false) -> void:
	item_id = item.id
	draggable = true
	var tone: Color = CATEGORY_COLORS[clampi(int(item.category), 0, CATEGORY_COLORS.size() - 1)]
	_body.color = tone.darkened(0.6) if dim else tone.darkened(0.25)
	_count.text = "%d" % count if count > 1 else ""
	_count.modulate = PBSkin.DIM if dim else PBSkin.TEXT


## 摆一个配件。
func set_part(part_id: StringName, count: int) -> void:
	item_id = part_id
	draggable = false
	_body.color = PART_COLOR.darkened(0.5) if count <= 0 else PART_COLOR
	_count.text = "%d" % count
	_count.modulate = PBSkin.DIM if count <= 0 else PBSkin.TEXT


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click := event as InputEventMouseButton
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT and item_id != &"":
		picked.emit(self)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item_id == &"":
		return null
	var ghost := ColorRect.new()
	ghost.size = TILE_SIZE
	ghost.color = _body.color
	ghost.modulate = Color(1.0, 1.0, 1.0, 0.8)
	set_drag_preview(ghost)
	return {"zone": zone, "item": item_id}


## 一件装备的载荷。和 [method PBUnitTile.card_of] 分开 ——
## 两种东西拖到同一块面板上时，收件人必须分得清刚拖来的是人还是装备。
static func item_of(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var payload := data as Dictionary
	if not payload.has("zone") or not payload.has("item"):
		return {}
	return payload
