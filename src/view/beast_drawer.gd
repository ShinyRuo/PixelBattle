class_name PBBeastDrawer
extends PBDrawer
## 开局选尾兽。§11，M3.5-f。
##
## ## 这是整局唯一一次、且不可撤销的选择
##
## §11 定的是**开局选定、全程不变**。所以这块面板做了两件在别处不做的事：
##
## 1. **鼠标停上去就把那一只讲完**（下面那段详情），因为点下去就没有回头路
## 2. **不提供「换一只」** —— [method PBShopRules.choose_beast] 只在还没选时收
##
## 允许中途换的话「选哪只」就退化成「哪一波用哪只」，而那正好抹掉这个决策：
## 不用取舍，全都能用上。
##
## ## 详情里数值和机制要并排写，不能只写伤害
##
## §11 点名警告过**机制型不能被数值型挤掉**：七尾是纯聚拢、六尾是重置全体
## 大招 CD，两只的伤害都是 0。只报「一发等于全队几秒输出」的话，
## 它们在面板上读起来就是两个废物，而实测里六尾是九只里最强的那一只。

## 玩家选定了这一只。
signal beast_chosen(beast_id: StringName)

const CARD_SIZE := Vector2(57.0, 42.0)
const CARD_STEP: float = 64.0

## 九只。§11 的定数，不是配置项。
const BEAST_COUNT: int = 9

var _cards: Array[Button] = []
var _ids: Array[StringName] = []
var _detail: RichTextLabel
var _cfg: PBSimConfig


func _build_body() -> void:
	set_title("选尾兽 · 开局选定，全程不变")
	for i: int in BEAST_COUNT:
		var card := Button.new()
		card.position = Vector2(8.0 + float(i) * CARD_STEP, 2.0)
		card.size = CARD_SIZE
		card.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		PBSkin.style_button(card)
		card.pressed.connect(func() -> void: _pick(i))
		card.mouse_entered.connect(func() -> void: _describe(i))
		body().add_child(card)
		_cards.append(card)
		_ids.append(&"")
	_detail = PBSkin.rich(body(), Rect2(8.0, 48.0, 576.0, 38.0))


func refresh(state: PBRunState, cfg: PBSimConfig) -> void:
	_cfg = cfg
	var table: PBBeastTable = cfg.beasts
	var beasts: Array[PBBeast] = table.all() if table != null else [] as Array[PBBeast]
	for i: int in _cards.size():
		var shown: bool = i < beasts.size()
		_cards[i].visible = shown
		_ids[i] = beasts[i].id if shown else &""
		if shown:
			# 显示名是「几尾 + 本名」这种两段式（中间一个空格，写在
			# `data/locale/` 里），拆成两行才塞得进 62px。
			_cards[i].text = PBLocale.text(beasts[i].name_key).replace(" ", "\n")
	if state.beast_id != &"":
		set_hint("这一局已经带着 %s 了 —— §11：开局选定，全程不变。" % PBLocale.text(_name_key(state)))
		_detail.text = ""
		return
	set_hint("鼠标停在一只上面看它干什么。[b]点下去就定了，整局不能换。[/b]")
	_detail.text = PBSkin.tint(
		"九只里有两只一点伤害都不打（聚拢、重置全体大招 CD）——"
		+ "§11 明写这种「机制型」不能被数值型挤掉，实测里重置 CD 那只排第一。",
		PBSkin.DIM
	)


func _pick(index: int) -> void:
	if index < _ids.size() and _ids[index] != &"":
		beast_chosen.emit(_ids[index])


## 鼠标停上去时把这一只讲完。**光环和大招各一行** ——
## 它们是两种不同的东西（全程生效 vs 手动交的底牌），混成一段读不出区别。
func _describe(index: int) -> void:
	if _cfg == null or index >= _ids.size() or _ids[index] == &"":
		return
	var beast := _cfg.beasts.by_id(_ids[index])
	if beast == null:
		return
	_detail.text = "[b]%s[/b]\n%s\n%s" % [
		PBLocale.text(beast.name_key), _aura_text(beast), _ultimate_text(beast)
	]


func _aura_text(beast: PBBeast) -> String:
	var parts := PackedStringArray()
	if beast.aura_power != 0.0:
		parts.append("%s伤害 +%.0f%%" % [_aura_scope(beast), beast.aura_power * 100.0])
	if beast.aura_ultimate_cd_scale < 1.0:
		parts.append("全队大招冷却 ×%.2f" % beast.aura_ultimate_cd_scale)
	if beast.aura_def_reduction > 0.0:
		# §11 / §10 的规矩：防御向效果在当前模型下诚实地等于 0，不折算成伤害。
		parts.append("基地减伤 +%.0f%%（敌人还手做出来之前恒为 0）" % (beast.aura_def_reduction * 100.0))
	if parts.is_empty():
		return PBSkin.tint("光环：无", PBSkin.DIM)
	return PBSkin.tint("光环（全程生效）　", PBSkin.DIM) + "　".join(parts)


## 光环打在谁身上。三只带筛选的（水系 / 土系 / 点名）正是尾兽和 §03 属性系统
## 的接口 —— 选了它就更想凑那一系，所以这一句必须写出来。
func _aura_scope(beast: PBBeast) -> String:
	if beast.aura_element != PBBeast.ANY_ELEMENT:
		return "%s系　" % PBUnitTile.ELEMENT_NAMES.get(beast.aura_element, "?")
	if not beast.aura_member_ids.is_empty():
		return "点名的 %d 人　" % beast.aura_member_ids.size()
	return "全体　"


func _ultimate_text(beast: PBBeast) -> String:
	if not beast.has_ultimate():
		return PBSkin.tint("大招：无", PBSkin.DIM)
	var parts := PackedStringArray()
	if beast.ultimate_damage_seconds > 0.0:
		parts.append("一发 = 全队 %.0f 秒输出" % beast.ultimate_damage_seconds)
	if beast.ultimate_max_targets == 1:
		parts.append("只打一个（BOSS 特化）")
	if beast.ultimate_gather:
		parts.append(PBSkin.tint("大范围聚拢", PBSkin.ACCENT))
	if beast.ultimate_knockback > 0.0:
		parts.append("范围击退")
	if beast.ultimate_slow_seconds > 0.0 and beast.ultimate_slow_scale < 1.0:
		parts.append(
			"减速至 ×%.1f 持续 %.0f 秒" % [beast.ultimate_slow_scale, beast.ultimate_slow_seconds]
		)
	if beast.ultimate_team_damage_scale > 1.0:
		parts.append(
			"全队增伤 ×%.2f 持续 %.0f 秒"
			% [beast.ultimate_team_damage_scale, beast.ultimate_buff_seconds]
		)
	if beast.ultimate_reset_cooldowns:
		parts.append(PBSkin.tint("重置全体角色大招 CD", PBSkin.ACCENT))
	var seconds: float = beast.ultimate_cooldown_seconds
	if seconds <= 0.0:
		seconds = _cfg.beast_ultimate_cooldown_seconds
	return (
		PBSkin.tint("大招（冷却 %.0f 秒，跨波保留）　" % seconds, PBSkin.DIM) + "　".join(parts)
	)


func _name_key(state: PBRunState) -> String:
	var beast := _cfg.beasts.by_id(state.beast_id) if _cfg.beasts != null else null
	return beast.name_key if beast != null else String(state.beast_id)
