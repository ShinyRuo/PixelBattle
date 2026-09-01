class_name PBCommandCard
extends Control
## 右下角的指令卡：**选中谁，就显示谁能做的事**。§02 的战场直接操作，M3.5-e。
##
## ## 它取代了什么
##
## M1-b 的花钱面板（`PBPreparePanel`）是一块常驻在左半屏的按钮列。
## 那块面板和「在战场界面就能操作一切」直接冲突：它挡着战场，
## 而且**只有一种上下文** —— 忍者、尾兽、大本营各自能做什么，它一个都表达不了。
##
## 指令卡是原版（War3 RPG 地图）的骨架：一个 3×3 的格子网格，
## 内容随选中的东西整体换掉。玩家的视线不离开战场。
##
## ## 「买下去战力涨多少」搬到了提示条
##
## 那句话是 CLAUDE.md 点名的核心信息，**没有丢**，但格子里写不下
## 「忍具箱 300（配件 14，每箱战力 +0.6%）」。所以：格子上写短的，
## 鼠标停上去在下面那条提示里写长的。两截都出自 [PBShopLabels] 同一份计算。

## 玩家点了某一格。[param command] 是下面那几组常量里的一个。
signal command(command_id: StringName)

## 大本营的指令：花钱那七项 + 重抽任务 + 开打。
const CMD_REROLL_QUEST: StringName = &"reroll_quest"
const CMD_START: StringName = &"start"

## 忍者的指令。
const CMD_LEVEL_UP: StringName = &"level_up"
const CMD_BENCH: StringName = &"bench"
const CMD_DEPLOY: StringName = &"deploy"
const CMD_DISPATCH: StringName = &"dispatch"

## 尾兽的指令。**选和升是两条**：§11 的选定只发生一次且不可撤销，
## 而升级每波都能点 —— 摆成同一格的两种状态会让人以为点它可以换尾兽。
const CMD_BEAST_UP: StringName = &"beast_up"
const CMD_BEAST_PICK: StringName = &"beast_pick"

## 战斗中的指令（§02，M4-e）。**只有这两条在打起来之后还能点。**
##
## 「攻击」按下去不是立刻打谁，而是**进入指定状态**：这时候点战场上的
## 一个敌人，这个忍者就改打他。分两步是 War3 那套（先按 A 再点地面），
## 而且它让「点错人」有一个可以后悔的中间态 ——
## 一步到位的话，手一抖就把主力指到一个残血杂兵身上。
const CMD_ATTACK: StringName = &"attack"
const CMD_CLEAR_TARGET: StringName = &"clear_target"

## 手动放忍术（§02，M5-9）。和「攻击」一样是两步：按下去进入选落点状态，
## 再点战场上的一个点才真的下达。
##
## ## 为什么它必须是一格按钮，而不是自动放
##
## M5-9 之前大招走的是 [PBAimRules] 的**自动档**（那是 §02 给手机端留的）。
## 冷却在开波那一刻全员是好的，于是**整队在第 1 tick 同时下达、
## 第 11 tick 同时落地** —— 玩家看到的是「开打就自动炸一下」，
## 而这也正是「单波只有 0.55 秒」那条已知配平问题的根源。
##
## §02 那对分层验收（手动比自动强 15–25%）本来就要求手动是玩家在放，
## 而在它接上之前，自动档等于替玩家把这一整维决策做完了。
const CMD_ULTIMATE: StringName = &"ultimate"

## 3×3。和原版一致 —— 九格装得下任何一种上下文，多了就该拆界面了。
const COLUMNS: int = 3
const ROWS: int = 3

const PANEL_RECT := PBLayout.J_COMMAND

## 一格多大，以及格与格之间的步距。
##
## **两个数必须一起改。** M5-2 把面板从 548 缩到 174 时只改了框，
## 格子还是 74×26 —— 第三列从 614 画到 688，**出界 48 像素**，
## 而它不报错（见 [PBLayout] 顶部）。`test_layout.gd` 现在钉着这一条。
##
## 算式：`4 + 2 × 60 + 58 = 182 ≤ 188 − 4`，
## 纵向 `10 + 2 × 24 + 23 = 81`，底下留 13 给提示行。
const CELL := Vector2(58.0, 23.0)
const CELL_STEP := Vector2(60.0, 24.0)

## 格子从面板顶下面这么远开始 —— 上面那截是标题行。
const GRID_TOP: float = 10.0

## 提示行：**必须留在面板里**。溢出去会糊在信息栏和屏幕外面，
## 而白字压深底两边都读不清。
##
## 三行格子占完之后只剩这 13 像素，也就是**一行、约 22 个汉字**
## （176 像素宽 ÷ 字号 8）。所以下面每一句提示都写在这个预算里 ——
## 写长了不报错，只是后半句被 `clip_text` 剪掉，
## 而剪掉的往往正是「然后会怎样」那一半。
##
## **13 是字号 8 那一行的真实行高，不是随手取的余数。** 给 11
## （也就是「剩多少给多少」）的话整行会被裁掉大半，屏幕上看着像空的 ——
## 而那比写长了更糟：**它连第一句都不显示**。
const HINT_TOP: float = 81.0
const HINT_H: float = 13.0

## 提示行一行装得下几个汉字。写提示时对着它数。
const HINT_BUDGET: int = 22
const FONT_SIZE: int = 8

var _slots: Array[Button] = []

## 每一格现在代表哪个指令。空表示这一格没用上。
var _bound: Array[StringName] = []

var _hint: Label
var _title: Label
var _state: PBRunState
var _cfg: PBSimConfig
## 这一波**真会打**的人。派出去做任务的已经不在里面了（见 [member _away]）。
var _deployed: Array[PBUnit] = []

## 这一波去做任务的人。
##
## 单独收一份而不是从 `_deployed` 反推：这一格要显示「出任务中」，
## 而那和「在仓库里」是两回事。
##
## **他们不占人口**（M5-9）：门槛因此是 [method PBRunState.field_slots]
## 而不是 `open_slots`，两份加起来跟它比。这一侧和
## [method PBCardMoves.set_on_field] 必须读同一个数 ——
## 差一个的表现是「按钮说行、点下去没反应」，而它不报错。
var _away: Array[PBUnit] = []

## 本波任务的等级。「派去任务」那一格要靠它算**要派几个人**。
var _grade: int = 0

## 现在是战斗中（M4-e）。**指令卡整块换一套** ——
## 升级、装备、派任务全是准备阶段的事，打起来之后一条都不该点得到。
var _battle_mode: bool = false

## 战场上正在等玩家点什么（[enum PBFieldPicker.Aim]）。
var _aim: int = PBFieldPicker.Aim.OFF

## 选中那个忍者现在点名打谁（敌人下标）。-1 = 没点名。
var _target: int = -1

## 选中那个忍者这一刻放不放得出忍术（[method PBBattleSim.can_cast]）。
##
## **传进来而不是自己算**：指令卡手上没有 [PBBattleSim]，而冷却和蓝
## 只有那儿知道。自己照着 [PBUltimate] 再算一遍就是第二把尺子 ——
## 「按钮亮着点了没反应」正是这种分叉的标准表现。
var _can_cast: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)

	_title = PBSkin.label(
		self,
		PANEL_RECT.position + Vector2(6.0, 0.0),
		PANEL_RECT.size.x - 12.0,
		PBSkin.FONT_TITLE,
		PBSkin.TITLE
	)
	_hint = PBSkin.label(
		self,
		PANEL_RECT.position + Vector2(6.0, HINT_TOP),
		PANEL_RECT.size.x - 12.0,
		PBSkin.FONT_BODY,
		PBSkin.DIM
	)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.size.y = HINT_H

	# 按上限一次建满，之后只改文字和可点性 —— 和敌人池、出战席同一条规矩（§14）。
	_slots.resize(COLUMNS * ROWS)
	_bound.resize(COLUMNS * ROWS)
	for i: int in COLUMNS * ROWS:
		var at := (
			PANEL_RECT.position
			+ Vector2(
				4.0 + float(i % COLUMNS) * CELL_STEP.x,
				GRID_TOP + float(i / COLUMNS) * CELL_STEP.y
			)
		)
		_slots[i] = _make_slot(i, at)
		_bound[i] = &""


## 按当前选中重画。[param plan] 用来算「重抽任务」那一格的价钱，
## [param deployed] 是「现在开打的话会是谁」（装备那一格要数他身上挂了几件），
## [param away] 是这一波去做任务的那几个。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	plan: PBWavePlan,
	deployed: Array[PBUnit] = [],
	away: Array[PBUnit] = []
) -> void:
	_state = state
	_cfg = cfg
	_deployed = deployed
	_away = away
	_grade = plan.quest_grade
	for i: int in _bound.size():
		_bound[i] = &""
		_slots[i].visible = false
	_hint.text = ""

	if _battle_mode:
		_fill_battle(selection)
		return
	match selection.kind:
		PBSelection.Kind.BASE:
			_title.text = "大本营"
			_fill_base(state, cfg, plan)
		PBSelection.Kind.BEAST:
			_title.text = "尾兽"
			_fill_beast(state, cfg)
		PBSelection.Kind.UNIT:
			_title.text = "忍者"
			_fill_unit(selection.unit_of(state), state, cfg)
		PBSelection.Kind.DISPATCHED:
			_title.text = "忍者（出任务中）"
			_hint.text = "做任务中：羁绊不算他，也动不了。"
		_:
			_title.text = "指令"
			_hint.text = "点谁，这里就换成谁能做的事。"


## 切到战斗中那一套指令（M4-e）。[param aim] 是战场正在等玩家点什么
## （[enum PBFieldPicker.Aim]），[param target] 是选中那个忍者现在点名打谁
## （-1 = 没点名），[param can_cast] 是他这一刻放不放得出忍术。
##
## 四个状态一起传，不让指令卡自己去问：**它手上没有 [PBBattleSim]**，
## 而「谁被点名了」「冷却好没好」只有那儿知道。让它自己去拿就要给它一条
## 通往战斗实例的路，而那条路一开，界面离「直接改 sim」只剩一步
## （§14：渲染层只读）。
func set_battle(
	battle: bool,
	aim: int = PBFieldPicker.Aim.OFF,
	target: int = -1,
	can_cast: bool = false
) -> void:
	_battle_mode = battle
	_aim = aim
	_target = target
	_can_cast = can_cast


## 这一格现在绑着哪个指令。测试拿它确认「选中什么就该出现什么」。
func command_at(index: int) -> StringName:
	if index < 0 or index >= _bound.size():
		return &""
	return _bound[index]


## 现在一共摆着几个可点的指令。
func command_count() -> int:
	var count: int = 0
	for id: StringName in _bound:
		if id != &"":
			count += 1
	return count


## 战斗中的那一套（M4-e）。**只有「打谁」这一件事**。
##
## 升级、装备、派任务、抽卡全是准备阶段的决策，打起来之后一条都不该点得到 ——
## 留着它们的话玩家会在战斗中花钱，而那笔钱本该是上一个准备阶段的取舍。
func _fill_battle(selection: PBSelection) -> void:
	_title.text = "战斗中"
	var unit: PBUnit = selection.unit_of(_state)
	if unit == null:
		_hint.text = "点战场上的忍者选中他。空格暂停时照样点得到。"
		return
	_title.text = "忍者　%s" % PBLocale.of_character(unit.character)
	var picking: bool = _aim == PBFieldPicker.Aim.TARGET
	var casting: bool = _aim == PBFieldPicker.Aim.ULTIMATE
	_bind(
		0,
		CMD_ATTACK,
		"取消指定" if picking else "攻击",
		true,
		PBSkin.Tone.PRIMARY if picking else PBSkin.Tone.PLAIN
	)
	_bind(1, CMD_CLEAR_TARGET, "自动选敌", _target >= 0)
	# 忍术（M5-9）。**冷却没好就是灰的**，而不是按下去没反应 ——
	# 后者玩家分不清是「还没好」还是「我点歪了」。
	_bind(
		2,
		CMD_ULTIMATE,
		"取消忍术" if casting else "忍术",
		casting or _can_cast,
		PBSkin.Tone.PRIMARY if casting else PBSkin.Tone.PLAIN
	)
	if casting:
		_hint.text = "点战场上一个点放忍术。右键取消。"
	elif picking:
		_hint.text = "点一个敌人改打他。右键取消。"
	elif _target >= 0:
		# 「不会站着发呆」那半句删了 —— 它讲的是**没发生的事**，
		# 而一行只有 22 个字（见 [constant HINT_BUDGET]）。
		_hint.text = "点名中。够不着或目标死了就自动接管。"
	elif _can_cast:
		_hint.text = "忍术转好了 —— 按下去再点落点。"
	else:
		_hint.text = "按「攻击」再点敌人，可以指定他打谁。"


func _fill_base(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> void:
	var slot: int = 0
	for kind: StringName in PBShopLabels.KINDS:
		var cost: int = PBShopLabels.cost_of(kind, state, cfg)
		_bind(slot, kind, PBShopLabels.short_of(kind, state, cfg), cost >= 0 and cost <= state.gold)
		slot += 1
	# 重抽任务（§06：`50 + 5n`）。**按钮在大本营**，和原版一致。
	var reroll: int = PBEconomyRules.quest_reroll_cost(plan.wave.index, cfg)
	_bind(slot, CMD_REROLL_QUEST, "重抽任务\n%d" % reroll, reroll <= state.gold)
	slot += 1
	_bind(slot, CMD_START, "开打\n回车", true, PBSkin.Tone.PRIMARY)


func _fill_beast(state: PBRunState, cfg: PBSimConfig) -> void:
	if state.beast_id == &"":
		_bind(0, CMD_BEAST_PICK, "选尾兽\n九选一", true, PBSkin.Tone.PRIMARY)
		_hint.text = "九选一，开局定终身。点开逐只看详情。"
		return
	var cost: int = PBBeastRules.upgrade_cost(state.beast_level, cfg)
	if cost < 0:
		_bind(0, CMD_BEAST_UP, "升级尾兽\n满级", false)
		_hint.text = "尾兽 Lv%d，已经满级。" % state.beast_level
		return
	_bind(0, CMD_BEAST_UP, "升级尾兽\n%d" % cost, cost <= state.gold)
	# §11：等级只放大光环与大招伤害，**半径、聚拢、减速、重置 CD 一概不变**。
	_hint.text = (
		"Lv%d → Lv%d，%d 金。只放大数值，机制不变。"
		% [state.beast_level, state.beast_level + 1, cost]
	)


func _fill_unit(unit: PBUnit, state: PBRunState, cfg: PBSimConfig) -> void:
	if unit == null:
		_hint.text = "这张卡已经不在仓库里了。"
		return
	var cost: int = PBEconomyRules.unit_level_cost(unit.level, cfg)
	if cost < 0:
		_bind(0, CMD_LEVEL_UP, "升级\n满级", false)
	else:
		_bind(0, CMD_LEVEL_UP, "升级 Lv%d\n%d" % [unit.level, cost], cost <= state.gold)
	# 上场 / 下场是同一格的两种状态 —— 一个人不可能既在场上又不在。
	#
	# ## 判据必须是 `_deployed`，不能是 `state.lineup`
	#
	# `lineup` 是**手排**名单，自动模式下**永远是空的**。照它判的话，
	# 一个已经自动上场的人会显示成「派上场」，而点下去
	# [method PBBattleView._set_on_field] 看的是真名单、发现他已经在里面，
	# 直接返回 —— 按钮点了没反应，且不报错。两处必须读同一份名单。
	if _away.has(unit):
		# 去做任务的人这一波不上场，所以也不显示「派上场」。
		_bind(1, CMD_BENCH, "出任务中", false)
	elif _deployed.has(unit):
		_bind(1, CMD_BENCH, "收回仓库", true)
	else:
		_bind(
			1,
			CMD_DEPLOY,
			"派上场",
			_deployed.size() + _away.size() < state.field_slots(cfg)
		)
	# **「装备」那一格 M5-5 删了**：装备栏（[PBEquipBay]）现在跟着选中常驻显示，
	# 一个「打开一直开着的东西」的按钮只会让人以为自己漏了一步。
	_fill_dispatch(unit, state, cfg)


## 「派去任务」那一格（§06，M3.5-g）。
##
## **代价的大小完全取决于派的是谁** —— 派一个谁的档都不顶的板凳末尾是白捡的钱，
## 派一个正撑着满档的成员要掉一整档。所以这一格必须存在：
## 自动按末尾派的话，玩家只能接受或不接受一个系统替他算好的价格。
func _fill_dispatch(unit: PBUnit, state: PBRunState, cfg: PBSimConfig) -> void:
	var need: int = PBEconomyRules.quest_cost_units(_grade)
	var chosen: int = state.dispatch_manual.size()
	var going: bool = state.dispatch_manual.has(unit.key())
	if going:
		_bind(3, CMD_DISPATCH, "取消派遣\n%d/%d" % [chosen, need], true)
		_hint.text = "去做任务：不上场，羁绊也不算他。"
		return
	# 仓库里的人派出去一分代价都没有（他本来就不给羁绊），那样任务就是白送 ——
	# §06 整节的张力在于「派谁」要付羁绊，所以门槛是「在不在场」。
	var on_field: bool = state.field_units(cfg).has(unit)
	_bind(3, CMD_DISPATCH, "派去任务\n%d/%d" % [chosen, need], on_field and chosen < need)
	if not on_field:
		_hint.text = "他不在场上 —— 派他去等于白送，先派上场。"
	elif chosen >= need:
		_hint.text = "本波只要 %d 人，已选满。换人先取消一个。" % need
	else:
		_hint.text = "升级抬的是二级属性（力/敏/智）。"


func _bind(
	slot: int, id: StringName, text: String, enabled: bool, tone: PBSkin.Tone = PBSkin.Tone.PLAIN
) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	_bound[slot] = id
	var button: Button = _slots[slot]
	button.visible = true
	button.text = text
	# 买不起或做不了就禁用 —— 让「现在做不了什么」一眼可见，
	# 而不是点下去没反应。这一条是从花钱面板继承来的。
	button.disabled = not enabled
	PBSkin.style_button(button, tone)


func _make_slot(index: int, at: Vector2) -> Button:
	var button := Button.new()
	button.position = at
	button.size = CELL
	button.visible = false
	PBSkin.style_button(button)
	button.pressed.connect(func() -> void: _on_slot_pressed(index))
	button.mouse_entered.connect(func() -> void: _on_slot_hovered(index))
	add_child(button)
	return button


func _on_slot_pressed(index: int) -> void:
	var id: StringName = _bound[index]
	if id != &"":
		command.emit(id)


## 悬停时把长句写进提示条 —— **「买下去战力涨多少」在这里兑现**。
func _on_slot_hovered(index: int) -> void:
	var id: StringName = _bound[index]
	if id == &"" or _state == null:
		return
	if PBShopLabels.KINDS.has(id):
		_hint.text = PBShopLabels.detail_of(id, _state, _cfg)
