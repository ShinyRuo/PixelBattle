class_name PBOfferModal
extends PBModal
## 抽卡三选一。§08，M3.5-f；M5-6 从抽屉改成模态。
##
## ## 为什么三选一要有自己的一块界面
##
## M3.5-e 之前抽卡是「点一下，一张卡进仓库」——**那里面没有决策**，
## 只有「钱够不够」。三选一把它变成一次真选择：三张摆开，挑一张，
## 另外两张**弃掉，不返金币**（[method PBShopRules.take_offer]）。
##
## 而一次选择要成立，玩家得看得见他在选什么。卡面上这几行不是装饰：
##
## - **攻元素 / 防元素**（§03A）—— 一张卡打哪一波、扛哪一波是两件事
## - **射程档**（M3-a）—— 决定他站前排还是后排，也就是要不要挨打
## - **所属羁绊**（§09）—— 一张能补满档的卡和一张谁都不搭的卡差一个数量级
## - **重复卡**（§08）—— 抽到已有的只加张数，那和一张新卡完全不是一回事
##
## 少了最后一条会出事：三张全是已有的卡时，玩家不看仓库根本不知道
## 自己在挑一张**只加星级进度**的卡，而界面上三张长得一模一样。
##
## ## 掏钱和挑人是分开的两步，所以这一层关不掉
##
## 钱在摆牌那一刻就扣了（见 [method PBShopRules.open_offer]），
## 那一组候选连同那笔钱会随着开打一起蒸发（拦在
## [method PBBattleView._finish_prepare]）。所以它是本项目唯一一块
## **没有关闭按钮、`Esc` 也收不掉**的面板（[method _closable]）——
## 给一个「关掉」的出口等于给一个把 300 金币变没的出口，
## 而账面上只表现为「金币怎么少了」。
##
## ## 卡宽 188 不是随手取的
##
## 抽屉那一版是 186，而带子只有 508 宽 —— 三张 186 加步距要 574，
## **右边那张有整整 65 像素画在屏幕外面**，从 M5-2 一直没人发现
## （见 [PBLayout] 顶部）。模态层宽 600，这次是算过的：
## `9 + 2×194 + 188 = 585 ≤ 600`。

## 玩家挑了第 [param index] 张。
signal picked(index: int)

const CARD_SIZE := Vector2(188.0, 86.0)
const CARD_STEP: float = 194.0

var _cards: Array[Button] = []
var _tiles: Array[PBUnitTile] = []
var _texts: Array[RichTextLabel] = []


func _body_height() -> float:
	return CARD_SIZE.y + 4.0


## **不给退路。** 见类顶部那段。
func _closable() -> bool:
	return false


func _build_body() -> void:
	set_title("抽卡 · 三选一")
	set_hint("挑一张收进仓库，另外两张弃掉 —— 不返金币，所以这一下是有代价的。")
	# 按 [member PBSimConfig.gacha_offer_size] 的上限一次建满（§14）。
	for i: int in PBSimConfig.new().gacha_offer_size:
		var card := Button.new()
		card.position = Vector2(9.0 + float(i) * CARD_STEP, 2.0)
		card.size = CARD_SIZE
		card.focus_mode = Control.FOCUS_NONE
		PBSkin.style_button(card, PBSkin.Tone.QUIET)
		card.pressed.connect(func() -> void: picked.emit(i))
		body().add_child(card)
		_cards.append(card)

		var tile := PBUnitTile.new()
		tile.position = Vector2(8.0, 24.0)
		card.add_child(tile)
		# `_ready` 会把格子设成 STOP（它在仓库里要自己收拖放），
		# 装进按钮里就得让开 —— 否则卡面正中间那一小块点不动。
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tiles.append(tile)

		_texts.append(PBSkin.rich(card, Rect2(44.0, 2.0, CARD_SIZE.x - 50.0, CARD_SIZE.y - 4.0)))


## 有没有一组候选正等着挑。开着它的时候不许开打（见类顶部）。
func has_offer(state: PBRunState) -> bool:
	return not state.pending_offer.is_empty()


func refresh(state: PBRunState, cfg: PBSimConfig, wave: PBWave) -> void:
	var offer: Array[PBUnit] = state.pending_offer
	set_title("抽卡 · 三选一　（本波 %s 系）" % PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"))
	for i: int in _cards.size():
		var shown: bool = i < offer.size()
		_cards[i].visible = shown
		if not shown:
			continue
		_tiles[i].set_unit(offer[i], wave.element)
		_texts[i].text = _card_text(offer[i], state, cfg, wave)


func _card_text(unit: PBUnit, state: PBRunState, cfg: PBSimConfig, wave: PBWave) -> String:
	var stats := unit.stats(cfg)
	var lines := PackedStringArray()
	lines.append(
		"[b]%s[/b]　%s"
		% [
			PBLocale.of_character(unit.character),
			PBSkin.tint(
				PBUnitTile.RARITY_NAMES[int(unit.rarity)],
				PBUnitTile.RARITY_COLORS[int(unit.rarity)]
			)
		]
	)
	lines.append(
		"攻 %s系 ×%.2f　防 %s系 ×%.2f"
		% [
			PBUnitTile.ELEMENT_NAMES.get(unit.element, "?"),
			cfg.damage_multiplier(PBElement.relation(unit.element, wave.element)),
			PBUnitTile.ELEMENT_NAMES.get(unit.def_element, "?"),
			cfg.damage_multiplier(PBElement.relation(wave.element, unit.def_element)),
		]
	)
	lines.append("战力 %.0f　血 %.0f　%s" % [stats.dps(), stats.hp, _reach_name(unit)])
	lines.append(_bond_text(unit, cfg))
	lines.append(_owned_text(unit, state))
	return "\n".join(lines)


func _reach_name(unit: PBUnit) -> String:
	match unit.character.reach_tier():
		PBCharacter.Reach.MELEE:
			return "近战"
		PBCharacter.Reach.LONG:
			return "超远程"
		_:
			return "远程"


## 这张卡进哪几组羁绊。**没有羁绊也要说出来** —— 空着的话读起来像漏了一行。
func _bond_text(unit: PBUnit, cfg: PBSimConfig) -> String:
	if cfg.bonds == null:
		return PBSkin.tint("羁绊 —", PBSkin.DIM)
	var parts := PackedStringArray()
	for bond: PBBond in cfg.bonds.all():
		if bond.counts_character(unit.character):
			parts.append(PBLocale.of_bond(bond))
	if parts.is_empty():
		return PBSkin.tint("不属于任何羁绊", PBSkin.DIM)
	return PBSkin.tint("羁绊 " + "·".join(parts), PBSkin.ACCENT)


## 已经有这张卡的话，挑它只推进星级进度（§08：同卡 3 张升 1 星）。
##
## **这一行是三选一里最容易被界面吃掉的信息**：三张卡长得一样，
## 而其中一张只加进度、另外两张是全新战力，差一个数量级。
func _owned_text(unit: PBUnit, state: PBRunState) -> String:
	var have := state.roster.get(unit.key(), null) as PBUnit
	if have == null:
		return PBSkin.tint("新卡", PBSkin.GOOD)
	return PBSkin.tint("已有 %d 张 —— 挑它只加星级进度" % have.copies, PBSkin.WARN)
