class_name PBCommandCard
extends Control
## 右下角的指令卡：**选中谁，就显示谁能做的事**（§02 的战场直接操作）。
##
## 原版（War3 RPG 地图）的骨架：一个 3×3 的格子网格，内容随选中的东西整体换掉，视线不离开战场。
## 格子里写不下长句，所以格子上写短的，悬停时提示条上写长的（「买下去战力涨多少」），两截都出自 [PBShopLabels]。

## 玩家点了某一格。[param command] 是下面那几组常量里的一个。
signal command(command_id: StringName)

## 大本营的指令：花钱那六项 + 「科技 ▸」 + 重抽任务 + 开打。
const CMD_REROLL_QUEST: StringName = &"reroll_quest"
const CMD_START: StringName = &"start"

## 「科技 ▸」进二级页、「◂ 返回」回首页。
##
## **这两条不往外发**（[signal command] 收不到）：翻页不改任何局面；发出去的话 [PBBattleView] 那条
## 「不认识的都当科技买」的兜底会拿它去买一条科技，买不到也不报错。
## 要翻页是因为首页九格已经满了，而训练分近战三条、远程一条。
const CMD_TECH_PAGE: StringName = &"tech_page"
const CMD_BACK: StringName = &"back"

## 忍者的指令。
const CMD_LEVEL_UP: StringName = &"level_up"
const CMD_BENCH: StringName = &"bench"
const CMD_DEPLOY: StringName = &"deploy"
const CMD_DISPATCH: StringName = &"dispatch"

## 尾兽的指令。**选和升是两条**：§11 的选定只发生一次且不可撤销，
## 而升级每波都能点 —— 摆成同一格的两种状态会让人以为点它可以换尾兽。
const CMD_BEAST_UP: StringName = &"beast_up"
const CMD_BEAST_PICK: StringName = &"beast_pick"

## 战斗中的指令（§02）。**只有这两条在打起来之后还能点。**
## 「攻击」按下去是**进入指定状态**，再点敌人才改打他 —— 点错人有一个可以后悔的中间态。
const CMD_ATTACK: StringName = &"attack"
const CMD_CLEAR_TARGET: StringName = &"clear_target"

## 大招那一格的键。**没有按钮** —— 它只是下标 0 的占位，让 `SKILL_COMMANDS.find(id)` 恒等于
## [method PBSkillRules.cast_at] 的下标。
##
## 不摆忍术格（玩家定的）：大招由 [PBSimConfig] 现造、谁都一样，那一格不表达任何角色差异；
## 「配了技能的人多一格按钮」才是技能阶梯要玩家看见的东西。**[member PBAttacker.ultimate] 本身没删**：
## 批量扫描走 [constant PBAimRules.Policy.AUTO]，§02 的分层验收量的就是它。
const CMD_ULTIMATE: StringName = &"ultimate"

## 角色自己表里的那两个技能，排在「攻击 / 自动选敌」后面。
## 两个常量而不是一个带下标的键：拼字符串出来的键在 `match` 里对不上是一个静默失败。
const CMD_SKILL_1: StringName = &"skill_1"
const CMD_SKILL_2: StringName = &"skill_2"

## 第 i 格技能对应哪个指令键。下标和 [method PBSkillRules.cast_at] 是同一套
## （0 = 大招），所以按钮和施放入口不可能对不上。
const SKILL_COMMANDS: Array[StringName] = [CMD_ULTIMATE, CMD_SKILL_1, CMD_SKILL_2]

## 指令卡上摆出来的第一格技能对应 `cast_at` 的哪个下标。**只是不摆，不是重新编号** ——
## 否则按钮、瞄准状态机、施放入口三处又各有一套编号。
const FIRST_SKILL: int = 1

## 3×3。和原版一致 —— 九格装得下任何一种上下文，多了就该拆界面了。
const COLUMNS: int = 3
const ROWS: int = 3

const PANEL_RECT := PBLayout.J_COMMAND

## 一格多大，以及格与格之间的步距。**两个数必须一起改**，只改一个的话格子会画出面板（`test_layout.gd` 钉着）。
## 算式：`4 + 2 × 60 + 58 = 182 ≤ 188 − 4`，纵向 `10 + 2 × 24 + 23 = 81`，底下留 13 给提示行。
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
## 翻页要原样重画一遍，所以上一次 [method refresh] 的另外两个参数也记着。
var _selection: PBSelection
var _plan: PBWavePlan

## 大本营现在翻在「科技 ▸」那一页。**换选中对象、开打都退回首页** ——
## 否则下次点大本营时首页的「开打」不见了，而玩家不记得自己翻过页。
var _tech_page: bool = false
## 这一波**真会打**的人。派出去做任务的已经不在里面了（见 [member _away]）。
var _deployed: Array[PBUnit] = []

## 这一波去做任务的人（要显示「出任务中」，和「在仓库里」是两回事）。
## **他们不占人口**：门槛是 [method PBRunState.field_slots]，和 [method PBCardMoves.set_on_field] 读同一个数 ——
## 差一个的表现是「按钮说行、点下去没反应」。
var _away: Array[PBUnit] = []

## 本波任务的等级。「派去任务」那一格要靠它算**要派几个人**。
var _grade: int = 0

## 现在是战斗中。**指令卡整块换一套** —— 升级、装备、派任务打起来之后一条都不该点得到。
var _battle_mode: bool = false

## 战场上正在等玩家点什么（[enum PBFieldPicker.Aim]）。
var _aim: int = PBFieldPicker.Aim.OFF

## [constant PBFieldPicker.Aim.SKILL] 档下正在放第几格。-1 = 没在放。
var _aim_skill: int = -1

## 选中那个忍者现在点名打谁（敌人下标）。-1 = 没点名。
var _target: int = -1

## 他手上攒着的是第几格技能（[method PBBattleSim.order_of]）。-1 = 没有。
## 暂停里下的令不当场生效（[PBSkillOrders]），所以那一格必须写出「已下令」。
var _queued: int = -1

## 选中那个忍者每一格技能的名字、这一刻放不放得出、还差几秒。三条平行数组，下标同 [method PBSkillRules.cast_at]。
## **传进来而不是自己算**：冷却和蓝只有 [PBBattleSim] 知道，自己再算一遍就是第二把尺子。
var _skill_names: PackedStringArray = PackedStringArray()
var _skill_ready: Array[bool] = []
var _skill_wait: PackedInt32Array = PackedInt32Array()


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
	_selection = selection
	_plan = plan
	_deployed = deployed
	_away = away
	_grade = plan.quest_grade
	for i: int in _bound.size():
		_bound[i] = &""
		_slots[i].visible = false
	_hint.text = ""

	if _battle_mode or selection.kind != PBSelection.Kind.BASE:
		_tech_page = false
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


## 切到战斗中那一套指令。[param aim] 是战场正在等玩家点什么（[enum PBFieldPicker.Aim]），
## [param aim_skill] 是那一档下正在放第几格，[param target] 是选中那个忍者点名打谁（-1 = 没点名）。
## [param names] / [param ready] / [param wait] 是每一格技能的名字、放不放得出、还差几 tick。
##
## **全部状态一起传**：指令卡手上没有 [PBBattleSim]，给它一条通往战斗实例的路，界面离「直接改 sim」就只剩一步。
func set_battle(
	battle: bool,
	aim: int = PBFieldPicker.Aim.OFF,
	aim_skill: int = -1,
	target: int = -1,
	names: PackedStringArray = PackedStringArray(),
	ready: Array[bool] = [],
	wait: PackedInt32Array = PackedInt32Array(),
	queued: int = -1
) -> void:
	_battle_mode = battle
	_aim = aim
	_aim_skill = aim_skill
	_target = target
	_skill_names = names
	_skill_ready = ready
	_skill_wait = wait
	_queued = queued


## 这一格现在绑着哪个指令。测试拿它确认「选中什么就该出现什么」。
func command_at(index: int) -> StringName:
	if index < 0 or index >= _bound.size():
		return &""
	return _bound[index]


## 这一格现在亮着还是灰着（「按钮亮 ⇔ 放得出」那条验收量的就是它）。灰着不等于没绑。
func enabled_at(index: int) -> bool:
	if index < 0 or index >= _slots.size():
		return false
	return _slots[index].visible and not _slots[index].disabled


## 战斗中的那一套：**只有「打谁」这一件事**。花钱是上一个准备阶段的取舍，打起来之后不该点得到。
func _fill_battle(selection: PBSelection) -> void:
	_title.text = "战斗中"
	var unit: PBUnit = selection.unit_of(_state)
	if unit == null:
		_hint.text = "点战场上的忍者选中他。空格暂停时照样点得到。"
		return
	_title.text = "忍者　%s" % PBLocale.of_character(unit.character)
	var picking: bool = _aim == PBFieldPicker.Aim.TARGET
	var casting: bool = _aim == PBFieldPicker.Aim.SKILL
	_bind(
		0,
		CMD_ATTACK,
		"取消指定" if picking else "攻击",
		true,
		PBSkin.Tone.PRIMARY if picking else PBSkin.Tone.PLAIN
	)
	_bind(1, CMD_CLEAR_TARGET, "自动选敌", _target >= 0)
	# 角色自己那几个技能从第 2 格起，**格子仍按 `cast_at` 的下标走**。
	# 从 [constant FIRST_SKILL] 起而不是留一个空格：网格里的洞看起来像 bug。
	for i: int in range(FIRST_SKILL, mini(_skill_names.size(), SKILL_COMMANDS.size())):
		_bind_skill(2 + i - FIRST_SKILL, i)
	_hint.text = _battle_hint(picking, casting)


## 第 [param index] 格技能画在第 [param slot] 格上。
## **冷却没好就是灰的**（而不是按下去没反应），灰着的那一格照样写秒数 —— 「还要多久」正是这时候想知道的事。
func _bind_skill(slot: int, index: int) -> void:
	var live: bool = _aim == PBFieldPicker.Aim.SKILL and _aim_skill == index
	var title: String = _skill_names[index]
	var wait: int = _skill_wait[index] if index < _skill_wait.size() else 0
	var ready: bool = index < _skill_ready.size() and _skill_ready[index]
	# 手上攒着这一格：**格子照样亮着，再按一次就是收回**（反悔是暂停操作的一半意义）。
	if _queued == index:
		_bind(slot, SKILL_COMMANDS[index], "已下令\n%s" % title, true, PBSkin.Tone.PRIMARY)
		return
	var label: String = "取消" if live else title
	if not live and wait > 0:
		# 秒数向上取整：还差半秒时写「1」比写「0」诚实 —— 写 0 的那一格
		# 看起来该亮了却是灰的，而那正是「按钮说谎」的样子。
		var rate: int = maxi(_cfg.tick_rate, 1) if _cfg != null else 20
		label = "%s\n%d 秒" % [title, ceili(float(wait) / float(rate))]
	_bind(
		slot,
		SKILL_COMMANDS[index],
		label,
		live or ready,
		PBSkin.Tone.PRIMARY if live else PBSkin.Tone.PLAIN
	)


## 提示行那一句。[constant HINT_BUDGET] 是 22 个汉字，每一句都写在预算里。
func _battle_hint(picking: bool, casting: bool) -> String:
	if casting:
		return "点战场上的目标放技能。右键取消。"
	if picking:
		return "点一个敌人改打他。右键取消。"
	# 「已下令」排在点名前面：那是他刚做的那一下，而点名可能是十秒前的事。
	if _queued >= 0:
		return "已下令，取消暂停就放。再按一次收回。"
	if _target >= 0:
		# 「不会站着发呆」那半句删了 —— 它讲的是**没发生的事**，
		# 而一行只有 22 个字（见 [constant HINT_BUDGET]）。
		return "点名中。够不着或目标死了就自动接管。"
	# 没配技能的忍者只会普攻，说出来，否则那一行空着看起来像没加载出来。
	if _skill_names.size() <= FIRST_SKILL:
		return "他没有忍术，普攻会自己找目标。"
	return "按「攻击」再点敌人，可以指定他打谁。"


func _fill_base(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> void:
	if _tech_page:
		_title.text = "大本营　科技"
		_fill_kinds(PBShopLabels.TRAINING_KINDS, state, cfg)
		_bind(COLUMNS * ROWS - 1, CMD_BACK, "◂ 返回", true)
		_hint.text = "训练分线：前三条加近战，精准加远程。"
		return
	var slot: int = _fill_kinds(PBShopLabels.BASE_KINDS, state, cfg)
	_bind(slot, CMD_TECH_PAGE, "科技 ▸", true)
	slot += 1
	# 重抽任务（§06：`50 + 5n`）。**按钮在大本营**，和原版一致。
	var reroll: int = PBEconomyRules.quest_reroll_cost(plan.wave.index, cfg)
	_bind(slot, CMD_REROLL_QUEST, "重抽任务\n%d" % reroll, reroll <= state.gold)
	slot += 1
	_bind(slot, CMD_START, "开打\n回车", true, PBSkin.Tone.PRIMARY)


## 从第 0 格起摆一串购买项，返回下一个空格。
func _fill_kinds(kinds: Array[StringName], state: PBRunState, cfg: PBSimConfig) -> int:
	var slot: int = 0
	for kind: StringName in kinds:
		var cost: int = PBShopLabels.cost_of(kind, state, cfg)
		_bind(slot, kind, PBShopLabels.short_of(kind, state, cfg), cost >= 0 and cost <= state.gold)
		slot += 1
	return slot


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
	# 没有「装备」格：装备栏（[PBEquipBay]）跟着选中常驻显示，打开一直开着的东西的按钮只会让人以为漏了一步。
	_fill_dispatch(unit, state, cfg)


## 「派去任务」那一格（§06）。代价大小完全取决于派的是谁，所以派谁必须是玩家能点的。
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
	if id == CMD_TECH_PAGE or id == CMD_BACK:
		_tech_page = id == CMD_TECH_PAGE
		if _selection != null:
			refresh(_selection, _state, _cfg, _plan, _deployed, _away)
		return
	if id != &"":
		command.emit(id)


## 悬停时把长句写进提示条 —— **「买下去战力涨多少」在这里兑现**。
func _on_slot_hovered(index: int) -> void:
	var id: StringName = _bound[index]
	if id == &"" or _state == null:
		return
	if PBShopLabels.KINDS.has(id):
		_hint.text = PBShopLabels.detail_of(id, _state, _cfg)
