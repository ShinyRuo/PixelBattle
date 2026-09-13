class_name PBUnitInfo
extends Control
## 底部中间的忍者信息栏：**选中谁就显示谁的全部属性**；没选人时显示整队的账（生效的羁绊）。
##
## 兑现 §03 那条改进（原版信息不透明）：头像、名字、稀有度、等级、血/蓝、攻/防、力/敏/智、
## 攻元素与防元素、射程、羁绊、装备词条。**这些数字真的进战斗**，显示不参与战斗的数字比不显示更糟。
## **攻元素和防元素分两行写**：它们指向不同的波次。

## 鼠标停在一行羁绊上。参数顺序对齐 [method PBTooltip.show_hint]。
signal hint_requested(at: Rect2, title: String, body: String)

## 鼠标从那一行上移开了，把卡收掉。
signal hint_closed

## 点在一行羁绊上。**和悬停走两条路**：点开的那张会吃掉下一次点击
## （[method PBTooltip.show_card]），那是触屏上唯一收得掉它的办法 ——
## 而 §01 要 PC + 手机双端，手机上压根没有悬停。
signal tip_requested(at: Rect2, title: String, body: String)

## 面板占底栏中段，右边留给指令卡（[constant PBCommandCard.PANEL_RECT]）。
const PANEL_RECT := PBLayout.H_INFO
const FONT_SIZE: int = 8

## 羁绊那一行的链接前缀。RichTextLabel 的 `[url=…]` 是这一栏唯一能
## **按行**收鼠标的东西 —— 自己摆一排隐形按钮的话，行高、换行、
## 字体度量三样都要复算一遍，而算错的表现是「有时候悬停不出来」。
const BOND_META := "bond:"

## 血条与蓝条。**先画满血的底再画当前值**。宽度让出右边给 buff 图标条（[PBBuffStrip] 有这笔几何账）；
## 它是百分比条不是刻度尺，窄一点仍然读得出比例。
const BAR_SIZE := Vector2(76.0, 6.0)

## 图标条摆在条的右边。x 从 122 起、宽 40，正好接到正文右边界 162。
const STRIP_AT := Vector2(122.0, 20.0)

const HP_COLOR := Color(0.85, 0.30, 0.30)
const MP_COLOR := Color(0.35, 0.55, 0.90)
const BAR_BACK := Color(0.16, 0.17, 0.21)

## 羁绊成员的三色（玩家要的「场上有的和没有的用颜色区分」）。
## **三档不是两档**：在场 / 抽到了但不在场上（这一下就能补上）/ 压根没抽到（只能等抽卡）——
## 合成两档的话玩家看到灰名字不知道该去仓库找他还是该去抽卡。
const MEMBER_ON_FIELD := PBSkin.GOOD
const MEMBER_IN_STASH := PBSkin.WARN
const MEMBER_MISSING := PBSkin.DIM

var _portrait: PBUnitTile
var _head: Label
var _body: RichTextLabel
var _hp_back: ColorRect
var _hp_fill: ColorRect
var _mp_back: ColorRect
var _mp_fill: ColorRect
var _strip: PBBuffStrip

## 悬停要用的上下文。**存起来而不是每次现查** —— 悬停发生在两次
## [method refresh] 之间，那时调用方手上那几份名单已经不在栈上了。
var _state: PBRunState
var _cfg: PBSimConfig

## 现在站在场上的角色 id。羁绊成员的第一档颜色按它判。
var _on_field: Dictionary = {}


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
	_strip = PBBuffStrip.new()
	_strip.position = PANEL_RECT.position + STRIP_AT
	add_child(_strip)

	# **正文要五行**（属性 / 力敏智 / 攻防元素 / 射程装备 / 羁绊），框只有 94 高：上下留白已经收到最紧，
	# 头像再往上挪会盖住数字。
	_body = PBSkin.rich(
		self,
		Rect2(PANEL_RECT.position + Vector2(6.0, 34.0), PANEL_RECT.size - Vector2(12.0, 36.0)),
		FONT_SIZE
	)
	# **这一层不能是 IGNORE**，否则收不到悬停 —— 而本类自己仍然是 IGNORE，
	# 挡住底下的东西不是它的职责。`PASS` 是「我自己要，但不拦别人」。
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	_body.meta_hover_started.connect(_on_meta_hover)
	_body.meta_hover_ended.connect(func(_meta: Variant) -> void: hint_closed.emit())
	_body.meta_clicked.connect(_on_meta_click)


## 按当前选中重画。[param deployed] 是「现在开打的话会是谁」，用来算装备。
## [param bond_aware] 是玩家现在用哪种带人方式（`B` 键切换），只在队伍账那一档用。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	wave: PBWave,
	deployed: Array[PBUnit],
	bond_aware: bool = false
) -> void:
	_state = state
	_cfg = cfg
	_on_field = {}
	for one: PBUnit in deployed:
		_on_field[one.character.id] = true
	var unit := selection.unit_of(state)
	if unit == null:
		_show_team(state, cfg, wave, bond_aware)
		return
	_show_unit(unit, selection, state, cfg, wave, deployed)


## 战斗中把血蓝条与效果图标刷成真值（§02）。**每渲染帧调一次。**
## 单独一条便宜的路：[method refresh] 要重排整块文字、跑一次装备分配，一秒六十次太贵，而会变的只有这几样。
## [param live] 为 null（没选人、或选中的人这一波没上场）就把条收掉。
func show_live(live: PBAttacker, at_tick: int = 0) -> void:
	if live == null:
		return
	_set_bar(_hp_back, _hp_fill, 0.0 if live.max_hp <= 0.0 else live.hp / live.max_hp)
	_set_bar(_mp_back, _mp_fill, 1.0 if live.max_mp <= 0.0 else live.mp / live.max_mp)
	if _cfg != null:
		_strip.show_bag(live.buffs, at_tick, _cfg)


## 没选人时显示**整队的账**（「整队现在什么样」正是这个空档该回答的问题）。
## **只写已经生效的那几组**：羁绊只有「够」和「不够」两种状态，没凑上的也摊开等于把整张表抄在面板上。
## 「都有谁」在悬停卡里。
func _show_team(state: PBRunState, cfg: PBSimConfig, wave: PBWave, bond_aware: bool) -> void:
	_portrait.visible = false
	_set_bar(_hp_back, _hp_fill, 0.0)
	_set_bar(_mp_back, _mp_fill, 0.0)
	var units := state.bonded_units(cfg)
	_head.text = "第 %d 波（%s）　金 %d" % [
		wave.index, PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"), state.gold
	]
	var lines := PackedStringArray()
	lines.append(
		"羁绊 ×%.2f　在场 %d　B:%s"
		% [state.bond_mult(cfg), units.size(), "羁绊" if bond_aware else "战力"]
	)
	lines.append_array(_tier_lines(cfg, units))
	if state.dispatched > 0:
		lines.append(PBSkin.tint("出任务 %d 人（不算羁绊）" % state.dispatched, PBSkin.DIM))
	_body.text = "\n".join(lines)


## 现在生效的是哪几组，功能缀在后面（载体是谁留给选中那个人看）。
## 每一行都是一个 `[url]`：鼠标停上去弹出成员名单（[method _bond_body]）。
func _tier_lines(cfg: PBSimConfig, units: Array[PBUnit]) -> PackedStringArray:
	var out := PackedStringArray()
	if units.is_empty():
		out.append(PBSkin.tint("在场没有人 —— 先抽卡", PBSkin.DIM))
		return out
	for bond: PBBond in cfg.bonds.all():
		var active: int = PBBondRules.active_count(bond, units)
		if bond.tier_at(active) <= 0:
			continue
		var label: String = "· %s %d 人" % [PBLocale.of_bond(bond), active]
		var key: StringName = bond.function_at(active)
		if key != &"":
			label += "·" + PBLocale.of_bond_function(key)
		out.append(_link(bond, label))
	if out.is_empty():
		out.append(PBSkin.tint("一组都没凑齐", PBSkin.DIM))
	return out


## 把一行包成可悬停的链接。**颜色留在外面** —— `[url]` 自带下划线，
## 再套一层颜色标签会让「生效」和「没生效」两种行长得一样。
func _link(bond: PBBond, label: String) -> String:
	return "[url=%s%s]%s[/url]" % [BOND_META, bond.id, label]


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

	# **不写星级**（玩家定的）：重复抽到的是另一个人，这个数恒为 1，一个永远不变的数字只会让人以为漏了一套养成系统。
	var away: String = "　出任务中" if selection.kind == PBSelection.Kind.DISPATCHED else ""
	_head.text = "%s　%s　Lv%d%s" % [
		PBLocale.of_character(unit.character),
		PBUnitTile.RARITY_NAMES[int(unit.rarity)],
		unit.level,
		away,
	]
	# 准备阶段没有战斗实例，显示满条是诚实的（开波时每波满血满蓝）。战斗中由 [method show_live] 每帧覆盖。
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


## 这个人身上挂着哪几件、给了什么词条。**分类匹配意味着「挂不上」是常态**（§10），所以挂不上要说出来。
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
	# **列词条，不列倍率**：玩家要对的是属性栏上的数。
	var worn := PBEquipRules.unit_mods(deployed, state.equip_parts, cfg, state.equipped)[index]
	var names := PackedStringArray()
	for item_id: String in held:
		var item := cfg.equipment.item(StringName(item_id))
		names.append(PBLocale.text(item.name_key) if item != null else item_id)
	var words := PBShopLabels.mod_words(worn)
	return "装备：%s\n　%s" % ["·".join(names), "　".join(words)]


## 这张卡进了哪几组羁绊，每组**到了几个 / 要几个**。
##
## 每一组都是一个 `[url]`：停上去弹出成员名单，绿的在场、黄的在仓库、
## 灰的还没抽到（[method _bond_body]）。**「他还差谁」是这一栏最值钱的
## 一句话** —— 而它太长，写在行里会把攻防那几行挤没。
func _bond_line(unit: PBUnit, state: PBRunState, cfg: PBSimConfig) -> String:
	if cfg.bonds == null:
		return "羁绊：无"
	var counted := state.bonded_units(cfg)
	var parts := PackedStringArray()
	for bond: PBBond in cfg.bonds.all():
		if not bond.counts_character(unit.character):
			continue
		var active: int = PBBondRules.active_count(bond, counted)
		var need: int = bond.full_tier_count()
		var text: String = "%s %d/%d" % [PBLocale.of_bond(bond), active, need]
		# 生效的标一下：「3/3」和「2/3」在一行小字里几乎分不出来，而那是这一组值不值钱的全部区别。
		text = PBSkin.tint(text + "✓", PBSkin.GOOD) if active >= need else text
		parts.append(_link(bond, text))
	if parts.is_empty():
		return "羁绊：无"
	return "羁绊　" + "　".join(parts)


## 悬停卡的正文：这一组都有谁，各自在哪儿。
##
## [constant PBBond.Match.ELEMENT] 那几组没有点名的成员表，成员是
## **角色表里所有这个属性的人** —— 现算而不是往数据里抄一份：
## 抄一份的话，角色表加一个火系角色而忘了同步，表现是
## 「明明抽到了却不算数」，不报错。
func _bond_body(bond: PBBond) -> String:
	if _cfg == null or _cfg.characters == null:
		return ""
	var owned: Dictionary = {}
	if _state != null:
		for unit: PBUnit in _state.all_units():
			owned[unit.character.id] = true
	var lines := PackedStringArray()
	for character: PBCharacter in _cfg.characters.all():
		if not bond.counts_character(character):
			continue
		var name: String = PBLocale.of_character(character)
		if _on_field.has(character.id):
			lines.append(PBSkin.tint("● " + name + "（在场）", MEMBER_ON_FIELD))
		elif owned.has(character.id):
			lines.append(PBSkin.tint("○ " + name + "（仓库）", MEMBER_IN_STASH))
		else:
			lines.append(PBSkin.tint("· " + name + "（未拥有）", MEMBER_MISSING))
	return "\n".join(lines)


## 悬停卡的标题：够没够，差几个。
func _bond_head(bond: PBBond) -> String:
	var active: int = PBBondRules.active_count(bond, _state.bonded_units(_cfg))
	var need: int = bond.full_tier_count()
	if active >= need:
		return "%s　%d/%d 已生效 +%.0f%%" % [
			PBLocale.of_bond(bond), active, need, bond.bonus_at(active) * 100.0
		]
	return "%s　%d/%d　还差 %d 人" % [PBLocale.of_bond(bond), active, need, need - active]


## 鼠标停在一行羁绊上。**认不出来的 meta 一律不响应** ——
## 将来这一栏多几种链接时，静默弹一张空卡比什么都不做更难查。
func _on_meta_hover(meta: Variant) -> void:
	var bond := _bond_of(meta)
	if bond != null:
		hint_requested.emit(PANEL_RECT, _bond_head(bond), _bond_body(bond))


func _on_meta_click(meta: Variant) -> void:
	var bond := _bond_of(meta)
	if bond != null:
		tip_requested.emit(PANEL_RECT, _bond_head(bond), _bond_body(bond))


func _bond_of(meta: Variant) -> PBBond:
	var text := str(meta)
	if not text.begins_with(BOND_META) or _cfg == null or _cfg.bonds == null:
		return null
	return _cfg.bonds.by_id(StringName(text.substr(BOND_META.length())))


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
