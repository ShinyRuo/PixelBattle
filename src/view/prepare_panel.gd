class_name PBPreparePanel
extends Control
## 准备阶段的花钱面板。M1-b。
##
## §01 说准备阶段不限时，玩家在这里做三件事：花钱、排阵、决定接不接任务。
## 这一版只做**花钱**（排阵是 M1-c，任务是 M1-d）。
##
## ## 每个按钮都写着「买下去战力涨多少」
##
## 这不是锦上添花，是这一层存在的理由。原版最大的短板是信息不透明 ——
## §03 说克制关系要点开技能说明才看得到，§10 说秘卷箱贵 3.7 倍却因为
## 不可定向而实际更差、攻略直接教新手别买。**玩家算不出账，就只能背攻略。**
##
## 数字来自 [PBValuation]，也就是模拟玩家比价用的**同一份计算**。
## 这样「批量扫描得出结论时用的口径」和「玩家看到的数字」是同一个东西，
## 不会出现「按界面上的数做决定，却和策划调参的依据对不上」。
##
## ## 这一层不改游戏状态
##
## 按钮只发信号，钱由 [PBBattleView] 通过 [PBStrategy] 的原语去花 ——
## 那是批量模拟走的同一批函数。界面自己扣钱的话，
## 迟早会和 `pull_once` 里维护的保底计数之类的东西不同步。

## 玩家点了某个购买项。[param kind] 是 [constant KINDS] 里的一个。
signal purchase_requested(kind: StringName)

## 玩家点了「开打」。
signal start_requested

## 全部可购买项。顺序即左列/右列的排列顺序。
const KINDS: Array[StringName] = [
	&"gacha",
	&"equip",
	&"kakuzu",
	&"tech_gold",
	&"tech_pop",
	&"tech_atk",
	&"tech_def",
]

## 四条科技分支的显示名（§07）。
const TECH_NAMES := {
	&"gold": "金币科技",
	&"pop": "人口科技",
	&"atk": "攻击科技",
	&"def": "防御科技",
}

## 商店占左半屏，右半屏留给阵容面板（[PBRosterPanel]）。
const PANEL_RECT := Rect2(46.0, 96.0, 232.0, 224.0)
const BUTTON_SIZE := Vector2(216.0, 22.0)
const FONT_SIZE: int = 9

var _buttons: Dictionary = {}
var _summary: Label
var _start: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.07, 0.10, 0.92)
	backdrop.position = PANEL_RECT.position
	backdrop.size = PANEL_RECT.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_summary = _make_label(PANEL_RECT.position + Vector2(8.0, 6.0), PANEL_RECT.size.x - 16.0)
	add_child(_summary)

	for kind: StringName in KINDS:
		_buttons[kind] = _make_button(kind, _slot_position(kind))

	_start = Button.new()
	_start.text = "开打"
	_start.position = PANEL_RECT.position + Vector2(8.0, PANEL_RECT.size.y - 28.0)
	_start.size = Vector2(BUTTON_SIZE.x, 24.0)
	_start.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	_start.pressed.connect(func() -> void: start_requested.emit())
	add_child(_start)


## 按当前状态刷新每个按钮的文字与可点性。**只在状态变了之后调**，
## 里面每一项都要跑一次 [method PBValuation.mean_dps]，不适合每帧跑。
func refresh(state: PBRunState, cfg: PBSimConfig) -> void:
	var base: float = PBValuation.mean_dps(state, cfg)
	_summary.text = "花钱　金币 %d　（战力增幅按五波轮转均值算）" % state.gold
	for kind: StringName in KINDS:
		var button: Button = _buttons[kind]
		var cost: int = _cost_of(kind, state, cfg)
		button.text = _label_of(kind, state, cfg, base)
		# 买不起或已满级就禁用 —— 让「现在买不了什么」一眼可见，
		# 而不是点下去没反应。
		button.disabled = cost < 0 or cost > state.gold


func _slot_position(kind: StringName) -> Vector2:
	var row: int = KINDS.find(kind)
	return PANEL_RECT.position + Vector2(8.0, 24.0 + float(row) * (BUTTON_SIZE.y + 2.0))


func _make_button(kind: StringName, at: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = BUTTON_SIZE
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(func() -> void: purchase_requested.emit(kind))
	add_child(button)
	return button


func _make_label(at: Vector2, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, 16.0)
	label.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	return label


## 这一项要多少钱。-1 表示买不了（满级 / 装备已装满）。
func _cost_of(kind: StringName, state: PBRunState, cfg: PBSimConfig) -> int:
	match kind:
		&"gacha":
			return cfg.gacha_cost
		&"equip":
			return -1 if _equipment_full(state, cfg) else cfg.equip_part_cost
		&"kakuzu":
			# 角都是抽来的角色不是商店货，代价折成一次单抽 —— 与模拟玩家同口径。
			# 留一个出战位，否则整队都是经济卡、DPS 归零。
			return -1 if state.open_slots(cfg) <= 1 else cfg.gacha_cost
		_:
			return PBEconomyRules.tech_cost(_branch_of(kind), _tech_level(kind, state), cfg)


## 按钮上写什么。**「战力涨多少」是这一层的重点**，见类顶部的说明。
func _label_of(kind: StringName, state: PBRunState, cfg: PBSimConfig, base: float) -> String:
	var cost: int = _cost_of(kind, state, cfg)
	match kind:
		&"gacha":
			# 一张卡都没有时估值函数返回的是「无穷大」的哨兵值（1.0）。
			# 照着写成「+100%」会让开局这一屏看起来像坏了 —— 直接说人话。
			if state.roster.is_empty():
				return "抽卡 %d　先抽第一张" % cost
			return "抽卡 %d　期望战力 %s" % [cost, _percent(PBValuation.gacha_gain(state, cfg))]
		&"equip":
			return _label_equip(state, cfg, base, cost)
		&"kakuzu":
			return _label_kakuzu(state, cfg, base, cost)
	return _label_tech(kind, state, cfg, base, cost)


func _label_equip(state: PBRunState, cfg: PBSimConfig, base: float, cost: int) -> String:
	if cost < 0:
		return "装备配件　已装满"
	# 收益按「一件成品」量：配件凑不满 3 个不产生任何加成，
	# 单个配件的即时收益是 0，只写 0 会让玩家以为装备没用。
	var progress: int = state.equip_parts % cfg.equip_parts_per_item
	if base <= 0.0:
		return "配件 %d（%d/%d 成一件）" % [cost, progress, cfg.equip_parts_per_item]
	var per_item: String = _percent(PBValuation.equip_item_gain(state, cfg, base))
	return "配件 %d（%d/%d 成一件，满件战力 %s）" % [cost, progress, cfg.equip_parts_per_item, per_item]


## 角都是全场唯一一个**两种货币并列**的按钮：付出战力，收金币。
## 换算留给玩家 —— §07 的「经济位 = 战力空位」就是这个取舍本身。
func _label_kakuzu(state: PBRunState, cfg: PBSimConfig, base: float, cost: int) -> String:
	if cost < 0:
		return "角都　位置不够"
	if base <= 0.0:
		return "角都 %d　每波 +%d 金（先凑阵容）" % [cost, _kakuzu_step(state, cfg)]
	return (
		"角都 %d　战力 −%.1f%%　每波 +%d 金"
		% [cost, PBValuation.kakuzu_slot_loss(state, cfg, base) * 100.0, _kakuzu_step(state, cfg)]
	)


func _label_tech(
	kind: StringName, state: PBRunState, cfg: PBSimConfig, base: float, cost: int
) -> String:
	var branch := _branch_of(kind)
	var label: String = TECH_NAMES.get(branch, "科技")
	if cost < 0:
		return "%s　满级" % label
	var level: int = _tech_level(kind, state)
	# 金币和防御不直接产出 DPS，写「战力 +0%」会误导 —— 各写各的口径。
	if branch == &"gold":
		return "%s Lv%d　%d　每波 +%d 金" % [label, level, cost, _passive_step(state, cfg)]
	if branch == &"def":
		var reduction: float = cfg.tech_def_per_level * 100.0
		return "%s Lv%d　%d　基地减伤 +%.0f%%" % [label, level, cost, reduction]
	# 队伍是空的时候，「涨百分之几」算出来恒为 0（0 的 6% 还是 0）。
	# 照实显示「战力 —」会让开局这一屏看起来像坏了，改写标称效果 —— 那句同样是真的。
	if base <= 0.0:
		if branch == &"pop":
			return "%s Lv%d　%d　出战位 +1" % [label, level, cost]
		return "%s Lv%d　%d　全体攻击 +%.0f%%" % [label, level, cost, cfg.tech_atk_per_level * 100.0]
	return (
		"%s Lv%d　%d　战力 %s"
		% [label, level, cost, _percent(PBValuation.tech_gain(state, cfg, branch, base))]
	)


## 升一级金币科技，每波多赚多少。用上一波的实际时长估。
func _passive_step(state: PBRunState, cfg: PBSimConfig) -> int:
	var seconds: float = 10.0
	if state.wave_index > 1 and state.elapsed_seconds > 0.0:
		seconds = state.elapsed_seconds / float(state.wave_index - 1)
	var after := PBEconomyRules.passive_income(seconds, state.tech_gold + 1, cfg)
	return after - PBEconomyRules.passive_income(seconds, state.tech_gold, cfg)


## 多上一个角都，每波多赚多少。
func _kakuzu_step(state: PBRunState, cfg: PBSimConfig) -> int:
	var after := PBEconomyRules.kakuzu_income(state.kakuzu_count + 1, state.wave_index, cfg)
	return after - PBEconomyRules.kakuzu_income(state.kakuzu_count, state.wave_index, cfg)


func _equipment_full(state: PBRunState, cfg: PBSimConfig) -> bool:
	var items: int = state.equip_parts / cfg.equip_parts_per_item
	return items >= state.open_slots(cfg) * cfg.equip_items_per_unit


func _branch_of(kind: StringName) -> StringName:
	return StringName(String(kind).trim_prefix("tech_"))


func _tech_level(kind: StringName, state: PBRunState) -> int:
	match _branch_of(kind):
		&"gold":
			return state.tech_gold
		&"pop":
			return state.tech_pop
		&"atk":
			return state.tech_atk
		_:
			return state.tech_def


## 带符号的百分比。真的是 0 就显示「—」而不是「+0.0%」——
## 「这一笔没用」本身是要一眼看出来的信息，而一排 +0.0% 读起来像坏了。
func _percent(value: float) -> String:
	if absf(value) < 0.0005:
		return "—"
	return "%+.1f%%" % (value * 100.0)
