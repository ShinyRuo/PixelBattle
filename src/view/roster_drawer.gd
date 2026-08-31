class_name PBRosterDrawer
extends PBDrawer
## 仓库：**手上全部的卡摆成一片**，点一张就选中它。§05 / §02，M3.5-f。
##
## ## 没有它的话「派上场」是个点不到的指令
##
## M3.5-e 的指令卡上有「派上场」，但屏幕上只画了出战席和出任务两排 ——
## **仓库里的人一个都看不见**，于是那条指令只有在
## 「先把某人收回仓库、再立刻派回去」时才点得到。
##
## ## 三档身份要分得开
##
## 一张卡有三种处境，行动完全不同：
##
## - **出战席**（绿）：这一波真的会打，吃装备、吃站位、算羁绊
## - **出任务**（黄）：这一波不打，羁绊也不算他（§06）
## - **仓库**（灰）：什么都不算，只是存着
##
## 混成一个颜色等于没说 —— 「羁绊怎么少了一档」的答案往往就是
## 某个人被派出去了，而那件事在一片同色的格子里看不出来。
##
## **M3.5-i 之前中间那一档是「待命台」（不参战但羁绊全额生效，§05）。**
## 待命台删掉之后那一格空了出来，正好给出任务的人 ——
## 他们同样是「在队里但这一波不打」，而且比板凳更需要被看见：
## 那是玩家自己刚做的决定。

## 玩家点了仓库里的一张卡。
signal unit_picked(unit_id: StringName)

## 一行摆几个。格子 30 宽，留 6px 给选中框和间隙。
const COLUMNS: int = 16
const PITCH := Vector2(36.0, 42.0)
const ORIGIN := Vector2(8.0, 4.0)

## 身份色。和下面那条图例是同一份，改色只改这里。
const ON_FIELD := Color(0.443, 0.816, 0.549, 1.0)
const ON_QUEST := Color(0.898, 0.749, 0.353, 1.0)
const IN_STASH := Color(0.318, 0.341, 0.408, 1.0)

var _tiles: Array[PBUnitTile] = []
var _bars: Array[ColorRect] = []
var _ring: ColorRect


func _build_body() -> void:
	set_title("仓库")
	# 选中框画在全部格子底下，靠 move_child 提到对应位置 —— 和 [PBFieldSlots]
	# 同一套：一个比格子大三像素的实心块，格子盖在上面，效果是一圈描边。
	_ring = ColorRect.new()
	_ring.color = PBSkin.TITLE
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.visible = false
	body().add_child(_ring)

	# 卡池上限就是角色表的大小，按它一次建满（§14）。
	for i: int in COLUMNS * 2:
		var at := ORIGIN + Vector2(float(i % COLUMNS) * PITCH.x, float(i / COLUMNS) * PITCH.y)
		var tile := PBUnitTile.new()
		tile.position = at
		tile.visible = false
		tile.picked.connect(
			func(hit: PBUnitTile) -> void: unit_picked.emit(hit.unit.key())
		)
		body().add_child(tile)
		_tiles.append(tile)

		var bar := ColorRect.new()
		bar.position = at + Vector2(0.0, PBUnitTile.TILE_SIZE.y + 1.0)
		bar.size = Vector2(PBUnitTile.TILE_SIZE.x, 3.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		body().add_child(bar)
		_bars.append(bar)


func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit],
	away: Array[PBUnit] = []
) -> void:
	var cards := state.all_units()
	set_title(
		"仓库 %d 张　出战 %d/%d　出任务 %d" % [
			cards.size(), deployed.size(), state.open_slots(cfg), away.size()
		]
	)
	set_hint(_legend())

	_ring.visible = false
	for i: int in _tiles.size():
		var tile: PBUnitTile = _tiles[i]
		var shown: bool = i < cards.size()
		tile.visible = shown
		_bars[i].visible = shown
		if not shown:
			continue
		var card: PBUnit = cards[i]
		tile.set_unit(card, wave.element)
		_bars[i].color = _tone_of(card, deployed, away)
		if selection.unit_id == card.key() and selection.kind == PBSelection.Kind.UNIT:
			_mark(tile)


## 这张卡现在算哪一档。三档互斥 —— 出任务的人已经不在 [param deployed] 里
## （见 [method PBBattleView._fighting_now]）。
func _tone_of(card: PBUnit, deployed: Array[PBUnit], away: Array[PBUnit]) -> Color:
	if deployed.has(card):
		return ON_FIELD
	if away.has(card):
		return ON_QUEST
	return IN_STASH


func _mark(tile: PBUnitTile) -> void:
	_ring.position = tile.position - Vector2(3.0, 3.0)
	_ring.size = PBUnitTile.TILE_SIZE + Vector2(6.0, 6.0)
	_ring.visible = true
	body().move_child(_ring, 0)


func _legend() -> String:
	return (
		"%s 出战席（这一波真的会打）　%s 出任务（不打，羁绊也不算他）　%s 仓库（什么都不算）　　点一张卡 → 右下角指令卡里派他上场或升级"
		% [
			PBSkin.tint("■", ON_FIELD),
			PBSkin.tint("■", ON_QUEST),
			PBSkin.tint("■", IN_STASH),
		]
	)
