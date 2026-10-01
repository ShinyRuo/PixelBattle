class_name PBOfferModal
extends PBModal
## 抽卡三选一（§08）：三张摆开挑一张，另外两张**弃掉，不返金币**（[method PBShopRules.take_offer]）。
##
## 选择要成立，玩家得看得见他在选什么。卡面上这几行不是装饰：**攻元素 / 防元素**（打哪一波、扛哪一波）、
## **射程档**（站前排还是后排）、**所属羁绊**（补满档的卡和谁都不搭的卡差一个数量级）、**是否已有**。
##
## **这一层关不掉**（没有关闭按钮、`Esc` 也收不掉，[method _closable]）：钱在摆牌那一刻就扣了，
## 给一个「关掉」的出口等于给一个把 300 金币变没的出口。开打前拦在 [method PBBattleView._finish_prepare]。
##
## 卡宽是算过的：`9 + 2×194 + 188 = 585 ≤ 600`（模态层宽）。

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
		(
			"[b]%s[/b]　%s"
			% [
				PBLocale.of_character(unit.character),
				PBSkin.tint(
					PBUnitTile.RARITY_NAMES[int(unit.rarity)],
					PBUnitTile.RARITY_COLORS[int(unit.rarity)]
				)
			]
		)
	)
	(
		lines
		. append(
			(
				"攻 %s系 ×%.2f　防 %s系 ×%.2f"
				% [
					PBUnitTile.ELEMENT_NAMES.get(unit.element, "?"),
					cfg.damage_multiplier(PBElement.relation(unit.element, wave.element)),
					PBUnitTile.ELEMENT_NAMES.get(unit.def_element, "?"),
					cfg.damage_multiplier(PBElement.relation(wave.element, unit.def_element)),
				]
			)
		)
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


## 已经有这个角色的话说一声。重复抽到的是另一个人（能上场、升级、带装备），
## 但**羁绊按角色算档**（[method PBBondRules.active_count]），同名的第二个人一组都不多。
func _owned_text(unit: PBUnit, state: PBRunState) -> String:
	var have: int = 0
	for owned: PBUnit in state.roster.values():
		if owned.character.id == unit.character.id:
			have += 1
	if have == 0:
		return PBSkin.tint("新卡", PBSkin.GOOD)
	return PBSkin.tint("已有 %d 个 —— 再来一个，但不加羁绊" % have, PBSkin.WARN)
