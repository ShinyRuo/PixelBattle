class_name PBUnitInfo
extends Control
## 底部中间的忍者信息栏：**选中谁就显示谁的全部属性**。§02 / §03A，M3.5-e。
##
## ## 它兑现的是 §03 的那条改进
##
## 原版最大的短板是信息不透明 —— 一张卡的射程、所属羁绊、装备挂没挂上
## 全都要背攻略。这一栏把它们摊开：头像、名字、稀有度、等级、
## 血/蓝、攻/防、力/敏/智、攻元素与防元素、射程、羁绊、装备。
##
## ## 血蓝攻防不是装饰
##
## §03A 明确否掉了「展示层派生」那条路：这些数字**真的进战斗**
## （敌人还手、忍者会死、大招耗蓝）。显示一个不参与战斗的数字比不显示更糟 ——
## 玩家迟早会发现「加了力量没变强」，而那时整套属性表都不可信了。
##
## ## 攻元素和防元素要分两行写
##
## §03A 把它们拆开，正是为了让一张卡在「它打谁」和「它扛谁」两条线上
## 指向不同的波次。写成一行「火系」的话，玩家读到的还是旧模型。

## 面板占底栏中段，右边留给指令卡（[constant PBCommandCard.PANEL_RECT]）。
const PANEL_RECT := Rect2(46.0, 250.0, 350.0, 108.0)
const FONT_SIZE: int = 8

## 血条与蓝条。**先画满血的底再画当前值**，比只画一条读得快。
const BAR_SIZE := Vector2(96.0, 6.0)

const HP_COLOR := Color(0.85, 0.30, 0.30)
const MP_COLOR := Color(0.35, 0.55, 0.90)
const BAR_BACK := Color(0.16, 0.17, 0.21)

var _portrait: PBUnitTile
var _head: Label
var _body: RichTextLabel
var _hp_back: ColorRect
var _hp_fill: ColorRect
var _mp_back: ColorRect
var _mp_fill: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)

	# 头像复用编队页那套白模（属性底色 + 稀有度边框 + 星级角标）——
	# 换真美术时只改 [PBUnitTile] 一个类，这一栏一行不动。
	_portrait = PBUnitTile.new()
	_portrait.position = PANEL_RECT.position + Vector2(6.0, 14.0)
	add_child(_portrait)
	# **在 add_child 之后设**：格子的 `_ready` 会把自己设回 STOP（它在别处要
	# 自己收拖放），而这里它只是一张头像，收了事件就会挡住底下的东西。
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_head = PBSkin.label(
		self,
		PANEL_RECT.position + Vector2(6.0, 1.0),
		PANEL_RECT.size.x - 12.0,
		PBSkin.FONT_TITLE,
		PBSkin.TITLE
	)
	_hp_back = _add_bar(PANEL_RECT.position + Vector2(42.0, 17.0), BAR_BACK)
	_hp_fill = _add_bar(PANEL_RECT.position + Vector2(42.0, 17.0), HP_COLOR)
	_mp_back = _add_bar(PANEL_RECT.position + Vector2(42.0, 26.0), BAR_BACK)
	_mp_fill = _add_bar(PANEL_RECT.position + Vector2(42.0, 26.0), MP_COLOR)

	_body = PBSkin.rich(
		self,
		Rect2(PANEL_RECT.position + Vector2(6.0, 36.0), PANEL_RECT.size - Vector2(12.0, 40.0)),
		FONT_SIZE
	)


## 按当前选中重画。[param deployed] 是「现在开打的话会是谁」，用来算装备。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit]
) -> void:
	var unit := selection.unit_of(state)
	if unit == null:
		_show_team(state, cfg, wave)
		return
	_show_unit(unit, selection, state, cfg, wave, deployed)


## 战斗中把血蓝条刷成真值（§02，M4-e）。**每渲染帧调一次。**
##
## ## 为什么单独开一个入口，不直接每帧调 [method refresh]
##
## `refresh` 要重排整块文字，还要跑一次装备分配（[method PBEquipRules.assign]）——
## 一秒六十次太贵，而那几行字在一波之内根本不变。
## 会变的只有这两条，所以它们单独有一条便宜的路。
##
## [param live] 为 null（没选人、或者选中的人这一波没上场）就把条收掉。
func show_live(live: PBAttacker) -> void:
	if live == null:
		return
	_set_bar(_hp_back, _hp_fill, 0.0 if live.max_hp <= 0.0 else live.hp / live.max_hp)
	_set_bar(_mp_back, _mp_fill, 1.0 if live.max_mp <= 0.0 else live.mp / live.max_mp)


## 没选人时显示整队的账。**空着不写等于浪费屏幕上最好的一块地方。**
func _show_team(state: PBRunState, cfg: PBSimConfig, wave: PBWave) -> void:
	_portrait.visible = false
	_set_bar(_hp_back, _hp_fill, 0.0)
	_set_bar(_mp_back, _mp_fill, 0.0)
	_head.text = "第 %d 波（%s）　金 %d　卡池 %d" % [
		wave.index, PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"), state.gold, state.roster.size()
	]
	var lines := PackedStringArray()
	lines.append("羁绊 ×%.3f　在场 %d 人" % [state.bond_mult(cfg), state.bonded_units(cfg).size()])
	if state.dispatched > 0:
		lines.append("出任务 %d 人（这一波羁绊不算他们）" % state.dispatched)
	lines.append("")
	lines.append("点战场上的忍者看他的属性，点大本营花钱。")
	_body.text = "\n".join(lines)


func _show_unit(
	unit: PBUnit,
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit]
) -> void:
	var stats := unit.stats(cfg)
	_portrait.visible = true
	_portrait.set_unit(unit, wave.element)

	var away: String = "　出任务中" if selection.kind == PBSelection.Kind.DISPATCHED else ""
	_head.text = "%s　%s　Lv%d　★%d%s" % [
		PBLocale.of_character(unit.character),
		PBUnitTile.RARITY_NAMES[int(unit.rarity)],
		unit.level,
		unit.star(),
		away,
	]
	# 准备阶段没有战斗实例，血蓝都是满的 —— 显示满条是诚实的：
	# 那正是开波时的状态（§03A：每波满血满蓝复活）。
	# 战斗中由 [method show_live] 每帧覆盖成真值（M4-e）。
	_set_bar(_hp_back, _hp_fill, 1.0)
	_set_bar(_mp_back, _mp_fill, 1.0)

	var lines := PackedStringArray()
	lines.append("血 %.0f　蓝 %.0f　攻 %.0f　防 %.0f　攻速 %.2f" % [
		stats.hp, stats.mp, stats.atk, stats.def, stats.attack_speed
	])
	lines.append(_secondary_line(unit, stats))
	lines.append(_element_line(unit, wave, cfg))
	lines.append("%s　%s" % [_reach_name(unit), _equipment_text(unit, deployed, state, cfg)])
	lines.append(_bond_line(unit, state, cfg))
	_body.text = "\n".join(lines)


## 力/敏/智，**主属性加粗**。哪一项是主属性决定了这张卡往哪个方向长（§03A）。
func _secondary_line(unit: PBUnit, stats: PBStats) -> String:
	var parts := PackedStringArray()
	var pairs := [
		[PBCharacter.Primary.STRENGTH, "力", stats.strength],
		[PBCharacter.Primary.AGILITY, "敏", stats.agility],
		[PBCharacter.Primary.INTELLECT, "智", stats.intellect],
	]
	for pair: Array in pairs:
		var text: String = "%s %.0f" % [pair[1], pair[2]]
		if unit.character.primary == pair[0]:
			text = "[b]%s(主)[/b]" % text
		parts.append(text)
	return "　".join(parts)


## 攻元素与防元素分两截写 —— 合成一行的话玩家读到的还是旧模型（§03A）。
func _element_line(unit: PBUnit, wave: PBWave, cfg: PBSimConfig) -> String:
	var attack := PBElement.relation(unit.element, wave.element)
	var defend := PBElement.relation(wave.element, unit.def_element)
	return "攻 %s系 本波×%.2f　　防 %s系 挨打×%.2f" % [
		PBUnitTile.ELEMENT_NAMES.get(unit.element, "?"),
		cfg.damage_multiplier(attack),
		PBUnitTile.ELEMENT_NAMES.get(unit.def_element, "?"),
		cfg.damage_multiplier(defend),
	]


func _reach_name(unit: PBUnit) -> String:
	match unit.character.reach_tier():
		PBCharacter.Reach.MELEE:
			return "近战·顶前排"
		PBCharacter.Reach.LONG:
			return "超远程·站后排"
		_:
			return "远程·中排"


## 这个人身上挂着哪几件。**分类匹配意味着「挂不上」是常态**（§10），
## 所以挂不上要说出来，不能显示成 ×1.00 让人以为是没买。
##
## M3.5-f 起把件名逐个列出来，而不只报一个总倍率 —— 装备成了玩家能插手的
## 东西之后，「他身上是哪几件」才是可以行动的信息（[PBEquipDrawer]）。
func _equipment_text(
	unit: PBUnit, deployed: Array[PBUnit], state: PBRunState, cfg: PBSimConfig
) -> String:
	var index: int = deployed.find(unit)
	if index < 0:
		return "装备：未上场不分配"
	var held: PackedStringArray = PBEquipRules.assign(
		deployed, state.equip_parts, cfg, state.equipped
	)[index]
	if held.is_empty():
		return "装备：没挂上"
	var mults := PBEquipRules.unit_multipliers(deployed, state.equip_parts, cfg, state.equipped)
	var names := PackedStringArray()
	for item_id: String in held:
		var item := cfg.equipment.item(StringName(item_id))
		names.append(PBLocale.text(item.name_key) if item != null else item_id)
	return "装备 ×%.2f（%s）" % [mults[index], "·".join(names)]


## 这张卡进了哪几组羁绊，各在第几档。
func _bond_line(unit: PBUnit, state: PBRunState, cfg: PBSimConfig) -> String:
	if cfg.bonds == null:
		return "羁绊：无"
	var counted := state.bonded_units(cfg)
	var parts := PackedStringArray()
	for bond: PBBond in cfg.bonds.all():
		if not bond.counts_character(unit.character):
			continue
		var active: int = PBBondRules.active_count(bond, counted)
		var tier: int = bond.tier_at(active)
		var text: String = "%s %d/%d" % [PBLocale.of_bond(bond), active, bond.full_tier_count()]
		if tier > 0:
			text += "·%d档" % tier
		parts.append(text)
	if parts.is_empty():
		return "羁绊：无"
	return "羁绊　" + "　".join(parts)


func _set_bar(back: ColorRect, fill: ColorRect, ratio: float) -> void:
	var shown: bool = ratio > 0.0
	back.visible = shown
	fill.visible = shown
	fill.size = Vector2(BAR_SIZE.x * clampf(ratio, 0.0, 1.0), BAR_SIZE.y)


func _add_bar(at: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at
	rect.size = BAR_SIZE
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect
