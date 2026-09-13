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

## 鼠标停在一行羁绊上（M6-j）。参数顺序对齐 [method PBTooltip.show_hint]。
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

## 血条与蓝条。**先画满血的底再画当前值**，比只画一条读得快。
##
## **M7-f 从 96 缩到 76**，腾出右边 44 像素给 buff 图标条
## （[PBBuffStrip]，那里有这笔几何账）。条是一条**百分比条不是刻度尺**，
## 缩掉两成仍然读得出比例；而正文那五行一行都动不了
## （M6-j 刚为第五行上下各收 2 像素买回一整行）。
const BAR_SIZE := Vector2(76.0, 6.0)

## 图标条摆在条的右边。x 从 122 起、宽 40，正好接到正文右边界 162。
const STRIP_AT := Vector2(122.0, 20.0)

const HP_COLOR := Color(0.85, 0.30, 0.30)
const MP_COLOR := Color(0.35, 0.55, 0.90)
const BAR_BACK := Color(0.16, 0.17, 0.21)

## 羁绊成员的三色（M6-j，玩家点名要的「场上有的和没有的用颜色区分」）。
##
## **三档不是两档**：「在场」「抽到了但不在场上」「压根没抽到」是三种
## 完全不同的处境 —— 第二档是**这一下就能补上**的，第三档只能等抽卡。
## 合成两档的话，玩家看到一个灰名字不知道该去仓库找他还是该去抽卡。
##
## 这也正是编队页删掉之后一直没找到家的那份三色名单（M3-e 起记在待决策表上）。
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

	# **正文要五行**（属性 / 力敏智 / 攻防元素 / 射程装备 / 羁绊），而这个框
	# 只有 94 高。M6-j 之前顶上留 36、底下留 4，装得下四行半 ——
	# **第五行（羁绊）被裁掉一半**，而它正是玩家这次点名要看的那一行。
	# 上下各收 2 像素买回一整行；头像那 34 像素本来就压着正文第一行的顶，
	# 再往上挪会盖住数字。
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


## 战斗中把血蓝条刷成真值（§02，M4-e）。**每渲染帧调一次。**
##
## ## 为什么单独开一个入口，不直接每帧调 [method refresh]
##
## `refresh` 要重排整块文字，还要跑一次装备分配（[method PBEquipRules.assign]）——
## 一秒六十次太贵，而那几行字在一波之内根本不变。
## 会变的只有这两条，所以它们单独有一条便宜的路。
##
## [param live] 为 null（没选人、或者选中的人这一波没上场）就把条收掉。
##
## 身上挂着的效果也走这一条（M7-f）：它每 tick 都在变（周期触发、到期），
## 和血蓝同一个量级，而重排整块文字那条路一秒六十次太贵。
func show_live(live: PBAttacker, at_tick: int = 0) -> void:
	if live == null:
		return
	_set_bar(_hp_back, _hp_fill, 0.0 if live.max_hp <= 0.0 else live.hp / live.max_hp)
	_set_bar(_mp_back, _mp_fill, 1.0 if live.max_mp <= 0.0 else live.mp / live.max_mp)
	if _cfg != null:
		_strip.show_bag(live.buffs, at_tick, _cfg)


## 没选人时显示**整队的账**，也就是原来那条羁绊带（M5-5 并进来的）。
##
## ## 羁绊带为什么搬进这里
##
## 新布局（[PBLayout]）里 A~J 十个框没有一个是给它的，而它压在战场上
## 又正好占着 M5-2 之后有人站的那一块。搬进这里不是找地方塞：
## **这一栏没选中人时本来就是空的**，而「整队现在什么样」正是
## 那个空档该回答的问题 —— 和指令卡「选中谁就显示谁能做的事」是同一条规矩。
##
## ## 只写已经生效的那几组（M6-j）
##
## 在那之前这里还有第二段「再补就能进：某某 差1 +18%」。删掉是玩家定的，
## 而它和羁绊改成**全有或全无**（见 [PBBond]）是同一个决定的两半：
## 分档的时候「差一个人」处处都是，那份提示是导航；
## 不分档之后**每一组都只有「够」和「不够」两种状态**，
## 把没凑上的也摊开等于把整张羁绊表抄在一块 168 像素宽的面板上。
##
## 「都有谁」搬进了悬停卡 —— 那是问一次就走的信息，不该常驻占三行。
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


## 现在生效的是哪几组。功能缀在后面（M3-f）—— **载体是谁留给选中那个人看**，
## 这一栏塞不下「要把某某排进出战席」。
##
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

	# **不写星级**（M6-j，玩家定的）。M5-9 起重复抽到的是**另一个人**，
	# 「同卡 3 张升 1 星」那条规则随之作废 —— 这个数因此恒为 1，
	# 而一个永远不变的数字只会让人以为自己漏了一套没做出来的养成系统。
	var away: String = "　出任务中" if selection.kind == PBSelection.Kind.DISPATCHED else ""
	_head.text = "%s　%s　Lv%d%s" % [
		PBLocale.of_character(unit.character),
		PBUnitTile.RARITY_NAMES[int(unit.rarity)],
		unit.level,
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
	# **列词条，不列倍率**（M12-h2）—— 装备从此给的是属性，
	# 而「×1.40」在属性栏里找不到对应的数。
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
		# 生效的标一下。不标的话「3/3」和「2/3」在一行小字里几乎分不出来，
		# 而那正好是这一组值不值钱的全部区别（M6-j：不凑齐就是不生效）。
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
