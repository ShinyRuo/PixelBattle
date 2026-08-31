class_name PBBattleView
extends Node2D
## 战斗画面。把 `src/core/` 的模拟接上渲染。M0-b。
##
## ## 定帧：数物理帧，不累加 delta
##
## §14 的铁律：**定帧 20 tick/s，倍速只改每帧步进多少个 tick。**
##
## `_physics_process` 本身就是固定频率的（默认 60Hz），所以 60 / 20 = 3，
## 每 3 个物理帧推进一个逻辑 tick —— 全整数，零浮点。
##
## 不用 `_accumulator += delta` 是有理由的：那样每帧都在累加浮点误差，
## 3 倍速和 1 倍速跑出来的 tick 序列会慢慢错开，而 §12 的存档回滚、
## §13 的每日种子和战报回放全都要求「逐 tick 完全一致」。
## `Engine.time_scale` 同理，绝对不用。
##
## ## 这一层只读 sim，不改 sim
##
## 渲染层拿 [PBBattleSim] 的敌人数组画图，拿 [PBRunState] 画 HUD，
## 一个字段都不回写。要改状态只能通过 [PBRunSim] 的 `plan_wave` /
## `settle_wave` —— 那是批量模拟走的同一条路，两边不会分叉。

## 一波的三个阶段（§01）。
##
## M0 只有战斗 —— 准备阶段被 [method PBRunSim.plan_wave] 在一帧里做完了，
## 因为那时候玩家是脚本。M1 把它显式拆出来：**准备阶段不限时，等玩家**。
enum Phase {
	PREPARE,  ## 花钱、排阵、决定接不接任务。§01：不限时，可存档退出
	BATTLE,  ## 逐 tick 推进
	SETTLE,  ## 结算，看一眼战果
}

## 结算停多少个物理帧。§01 说 2–4 秒，这里取 1 秒够看清结果。
const WAVE_GAP_FRAMES: int = 60

## 点战场上的单位时，鼠标离多近算点中（像素，M4-e）。
##
## 比单位本身大一圈：敌人半径 5、己方 11×11，而 `640×360` 下一个像素
## 就是一大步。按外观尺寸判的话「点边上一点就选不中」，
## 而玩家不会认为自己点偏了 —— 他会认为点选坏了。
const PICK_RADIUS_PX: float = 12.0

## 本局的随机种子。0 表示用系统时间。
##
## 留成可指定的是为了两件事：**测试要可复现**，以及 §13 的每日种子挑战
## 将来只要把 `hash(date_utc)` 填进来就行，其余系统零改动。
@export var run_seed: int = 0

## 调试用：直接从第几波开始。1 表示正常从头打。
##
## 前面的波次用解析式模型瞬间跑完（不渲染），只有目标波才逐 tick 画出来。
## 这是为了能立刻检查后期波次的观感 —— `COUNT_CAP` 定夺要看的是
## 40 波之后几十个敌人同屏糊不糊，正常打过去要等十几分钟。
##
## **快进用的是和批量模拟同一条路**（`plan_wave` / `settle_wave`），
## 所以快进到第 N 波的状态和正常打到第 N 波是一致的，不是伪造的。
@export var start_wave: int = 1

## 调试用：强制第一波的敌人数量。0 表示按 §04 的公式正常算。
##
## **只为回答视觉问题**：「`COUNT_CAP` 取 48 时同屏糊不糊」是 §04 的待决策，
## §02 的验收项是「去色后仍能仅凭剪影区分五系」。这两条都只跟**画面**有关，
## 不该依赖「玩家能不能活到第 40 波」才看得到。
##
## 它只改这一波的敌人数量，不改任何平衡参数 —— 别拿它跑数值结论。
@export var debug_enemy_count: int = 0

## 自动推进：准备阶段由脚本玩家代劳，不等输入。
##
## §01 点名要这个模式（「PC：开自动推进，一次坐 30~60 分钟」）。
## 它同时是 M1 的**回归工具** —— 开着的时候整局的决策序列与批量模拟完全一致，
## 所以「UI 改动有没有把数值弄歪」可以直接和批量结果对拍。
##
## **默认关**：开局第一眼看到的应该是准备阶段那四块面板加编队页，
## 而不是一场自己打起来的第一波。M0–M3-d 期间默认是开的，
## 因为那时准备阶段还没有可玩的东西 —— 现在有了。
## 想回到挂机观战按 `A`，批量回归对拍走 `capture_battle.gd`。
@export var auto_play: bool = false

var _cfg: PBSimConfig
var _state: PBRunState
var _strategy: PBStrategy
var _rng: PBRngStreams
var _plan: PBWavePlan
var _battle: PBBattleSim

## 每几个物理帧推进一个逻辑 tick。由帧率和 tick 率算出来，不写死。
var _frames_per_tick: int = 3
var _frame_counter: int = 0

## 倍速：每次触发时步进几个 tick。1 / 2 / 3，见 §02。
var _speed: int = 1
var _paused: bool = false

## 本局是否已经结束（基地被打穿）。
var _run_over: bool = false

## 当前阶段。
var _phase: Phase = Phase.PREPARE

## 结算阶段的剩余帧数。
var _gap_frames: int = 0

## 战场上现在选中了什么（§02 的战场直接操作，M3.5-e）。
## 指令卡、信息栏、槽位高亮三处都读它 —— 见 [PBSelection]。
var _selection := PBSelection.new()

## 命中白闪 / 伤害飘字 / 击杀顿帧的接线（M3.5-h）。见 [PBHitFeedback]。
var _feel := PBHitFeedback.new()

## 战场上「点到了谁」和「让谁打谁」（§02 的战斗中操作，M4-e）。见 [PBFieldPicker]。
var _picker := PBFieldPicker.new()


## 击杀顿帧还剩几个物理帧。
##
## ## 它不碰 tick 序列
##
## 顿帧期间**只是不调 `_advance_logic`**，`_frame_counter` 也不动 ——
## 效果等同于按了几帧暂停。走完之后 tick 一个不多一个不少，
## 所以 §12 的存档回滚、§13 的战报回放与每日种子全都不受影响。
##
## **绝不能用「跳过一个 tick」或者 `Engine.time_scale` 来做顿帧**：
## 前者直接改模拟结果，后者违反铁律 2，而两者的表现都只是
## 「同一个种子跑出来的局慢慢对不上」。
var _hitstop_frames: int = 0

# @onready 必须排在普通成员之后 —— .gdlintrc 的 class-definitions-order
# 定死了「prvvars 在 onreadyprvvars 之前」。这一组的赋值时机也在 _ready() 之前，
# 所以 _init() 里访问不到它们。
@onready var _pool: PBEnemyPool = $Enemies
@onready var _shots: PBShotPool = $Shots
@onready var _allies: PBAllyPool = $Deployed
@onready var _telegraph: PBTelegraphPool = $Telegraph
@onready var _floats: PBFloatTextPool = $Floats
@onready var _base_rect: ColorRect = $Base
@onready var _limit: ColorRect = $Limit
@onready var _info: Label = $HUD/Info
@onready var _preview: Label = $HUD/Preview
@onready var _command: PBCommandCard = $HUD/Command
@onready var _unit_info: PBUnitInfo = $HUD/UnitInfo
@onready var _slots: PBFieldSlots = $HUD/Slots
@onready var _quest: PBQuestCard = $HUD/Quest
@onready var _bonds: PBBondPanel = $HUD/Bonds
@onready var _offer: PBOfferDrawer = $HUD/Offer
@onready var _equip: PBEquipDrawer = $HUD/Equip
@onready var _stash: PBRosterDrawer = $HUD/Stash
@onready var _beasts: PBBeastDrawer = $HUD/Beasts


func _ready() -> void:
	# 走装载器而不是 PBSimConfig.new()：后者默认的是给对拍用的合成卡池，
	# 忘了装真角色表不会报错，只表现为「玩到的和扫描结论对不上」（§14 铁律 5）。
	_cfg = PBGameData.config()
	# 画面必须逐 tick —— 排队模型算完就没了，没有中间状态可画。
	_cfg.use_tick_battle = true
	_frames_per_tick = maxi(Engine.physics_ticks_per_second / _cfg.tick_rate, 1)

	_rng = PBRngStreams.new(_resolve_seed())
	_state = PBRunSim.new_state(_cfg)
	_strategy = PBStratBalanced.new()

	_command.command.connect(_on_command)
	_slots.slot_picked.connect(_on_slot_picked)
	_slots.stash_toggled.connect(func() -> void: _toggle_drawer(_stash))
	# 四块抽屉各自只管「我被点了什么」，开关由这里统一裁决（见 [PBDrawer]）。
	_offer.picked.connect(_on_offer_picked)
	_equip.equip_requested.connect(_on_equip_changed.bind(true))
	_equip.unequip_requested.connect(_on_equip_changed.bind(false))
	_stash.unit_picked.connect(func(id: StringName) -> void: _select(PBSelection.Kind.UNIT, id))
	_beasts.beast_chosen.connect(_on_beast_chosen)
	# 任务卡自己记着接没接（[method PBQuestCard.accepted]），切换后只需重画。
	# **不在这里改 `state.dispatched`** —— 那个字段归 `lock_plan` 管，
	# 渲染层一个字段都不回写（见类顶部）。卡面本来就把两个分支并排显示，
	# 玩家不需要靠「先提交再看效果」来了解代价。
	_quest.quest_toggled.connect(func(_accepted: bool) -> void: _refresh_panels())
	_fast_forward_to(start_wave)
	_enter_prepare()


## 玩家在准备阶段买了一笔。
##
## **钱走 [PBStrategy] 的原语，不由界面自己扣** —— 那是批量模拟走的同一批函数。
## 界面自己扣钱的话，迟早会和 `pull_once` 里维护的保底计数之类的东西不同步，
## 而这种不同步不报错，只表现为「玩到的和扫描结论对不上」。
func _on_command(command_id: StringName) -> void:
	# 战斗中只有「打谁」那两条（§02，M4-e）。花钱、排阵、派任务
	# 全是准备阶段的决策 —— 留着它们等于让玩家在战斗中花本该更早花的钱。
	if _phase == Phase.BATTLE:
		_on_battle_command(command_id)
		return
	if _phase != Phase.PREPARE or _run_over:
		return
	match command_id:
		&"gacha":
			# **摆牌和挑人是分开的两步**（§08 的三选一）：这里只掏钱摆三张，
			# 挑哪一张是玩家在 [PBOfferDrawer] 上做的决定。
			# 直接走 `pull_once` 的话，脚本玩家的挑法会替真人做完这个决定。
			if PBShopRules.open_offer(_state, _plan.wave, _cfg, _rng):
				_toggle_drawer(_offer, true)
		&"equip":
			_strategy.buy_equip_part(_state, _cfg, _rng)
		&"economy_slot":
			if _state.open_slots(_cfg) > 1 and _state.spend(_cfg.gacha_cost):
				_state.economy_slot_count += 1
		PBCommandCard.CMD_REROLL_QUEST:
			PBRunSim.reroll_quest(_state, _plan, _cfg, _rng)
		PBCommandCard.CMD_START:
			_finish_prepare()
			return
		PBCommandCard.CMD_LEVEL_UP:
			PBShopRules.level_up(_state, _selection.unit_of(_state), _cfg)
		PBCommandCard.CMD_BENCH:
			_set_on_field(_selection.unit_of(_state), false)
		PBCommandCard.CMD_DEPLOY:
			_set_on_field(_selection.unit_of(_state), true)
		PBCommandCard.CMD_EQUIP:
			_toggle_drawer(_equip, true)
		PBCommandCard.CMD_DISPATCH:
			PBShopRules.toggle_dispatch(
				_state,
				_selection.unit_of(_state),
				PBEconomyRules.quest_cost_units(_plan.quest_grade),
				_cfg
			)
		PBCommandCard.CMD_BEAST_PICK:
			_toggle_drawer(_beasts, true)
		PBCommandCard.CMD_BEAST_UP:
			# M3.5-e 漏了这一条：没有分支的指令会掉进下面那个 `_`，
			# 于是「升级尾兽」被当成一条叫 `beast_up` 的科技去买 ——
			# 买不到，也不报错，点下去纯粹没反应。
			PBShopRules.upgrade_beast(_state, _cfg)
		_:
			_strategy.buy_tech(_state, StringName(String(command_id).trim_prefix("tech_")), _cfg)
	_sync_deployed()
	_refresh_panels()


## 战斗中的两条指令（§02，M4-e）。
##
## 「攻击」是个**开关**，不是一次动作：按下去进入指定状态，再按一次退出。
## 一步到位（按一下就打最近的）的话这一格没有意义 —— 那本来就是自动规则。
func _on_battle_command(command_id: StringName) -> void:
	match command_id:
		PBCommandCard.CMD_ATTACK:
			_picker.aiming = not _picker.aiming
		PBCommandCard.CMD_CLEAR_TARGET:
			_picker.release(_selected_attacker())
	_refresh_battle_panels()


## 玩家点了一个槽位。**再点一次同一个 = 取消选中** ——
## 没有「空白处点一下取消」这条路的话，选中框会一直挂在最后点过的那个人身上。
func _on_slot_picked(kind: PBSelection.Kind, unit_id: StringName) -> void:
	# **选中不再顺手弹装备栏**（M4-f）。
	#
	# §02 原话是「忍者信息栏和装备栏一起弹出和关闭」，M3.5-e 照做了 ——
	# 那时准备阶段的战场是**空的**，四块抽屉敢共用战场那条道靠的就是这一条。
	# 现在战场上站着上场名单、还能拖动摆位：每选一个人就弹一块盖住半个战场的
	# 抽屉，等于把最高频的那个操作挡在自己的反馈前面。
	# 装备栏还在，改成指令卡上点「装备」才开 —— 那是一个明确的意图。
	_select(kind, unit_id)


## 换一个选中。**再点一次同一个 = 取消选中** ——
## 没有「空白处点一下取消」这条路的话，选中框会一直挂在最后点过的那个人身上。
func _select(kind: PBSelection.Kind, unit_id: StringName) -> void:
	if _selection.is_same(kind, unit_id):
		_selection.set_to(PBSelection.Kind.NONE)
	else:
		_selection.set_to(kind, unit_id)
	_refresh_panels()


## 开这一块抽屉，**并把其余三块关掉**。[param force] 为真时只开不关，
## 用在「点了指令要看某块」的场合；为假时是开关（再点一次收起来）。
##
## 裁决集中在这里而不是各抽屉自己抢，见 [PBDrawer] 顶部。
func _toggle_drawer(which: PBDrawer, force: bool = false) -> void:
	var open: bool = force or not which.visible
	for drawer: PBDrawer in [_offer, _equip, _stash, _beasts]:
		if drawer != which:
			drawer.close()
	if open:
		which.open()
	else:
		which.close()
	_refresh_panels()


## 玩家从三选一里挑了一张。挑完这块抽屉就没有内容了，直接收起来。
func _on_offer_picked(index: int) -> void:
	if PBShopRules.take_offer(_state, index):
		_offer.close()
	_sync_deployed()
	_refresh_panels()


## 玩家挂上/卸下一件装备。**走 [PBEquipRules] 的原语，界面不自己动
## [member PBRunState.equipped]** —— 和花钱、排名单同一个理由。
func _on_equip_changed(item_id: StringName, put_on: bool) -> void:
	var unit := _selection.unit_of(_state)
	if unit == null:
		return
	if put_on:
		PBEquipRules.pin(_state.equipped, unit.key(), item_id, _cfg)
	else:
		PBEquipRules.unpin(_state.equipped, unit.key(), item_id)
	_refresh_panels()


## 玩家定下了这一局的尾兽（§11：开局选定，全程不变）。
func _on_beast_chosen(beast_id: StringName) -> void:
	if PBShopRules.choose_beast(_state, beast_id, _cfg):
		_beasts.close()
	_refresh_panels()


## 收掉现在开着的那一块抽屉。**没有开着的就返回 false**，
## 让 `Esc` 接着去做它的第二件事（取消选中）。
##
## 三选一那块不收 —— 那一组候选是掏了钱的，收起来它就找不回来了。
func _close_open_drawer() -> bool:
	for drawer: PBDrawer in [_equip, _stash, _beasts]:
		if drawer.visible:
			drawer.close()
			_refresh_panels()
			return true
	return false


## 这一波谁去做任务。**三种口径，选哪一种取决于阶段** ——
## 所以由这里决定，不由槽位那一层自己问（见 [method PBFieldSlots.refresh]）。
##
## 1. 已经锁过了（战斗/结算）：照 `dispatched_ids` 念，那是当时真的派出去的人
## 2. 准备阶段接了任务：按「现在开打会派谁」预览一份，钦定的人排在前面
## 3. 准备阶段还没接：只显示玩家已经钦定的那几个 —— 他挑一个就该看见一个，
##    等到「接下任务」才给反馈的话，挑人这件事没有中间态
func _dispatch_preview() -> Array[PBUnit]:
	if not _state.dispatched_ids.is_empty():
		return _units_of(_state.dispatched_ids)
	if _phase == Phase.PREPARE and _quest.accepted():
		return _state.dispatch_picks(_cfg, PBEconomyRules.quest_cost_units(_plan.quest_grade))
	return _units_of(_state.dispatch_manual)


## 这一波**真会打**的人。派出去做任务的不在里面（§06）。
##
## 战斗与结算阶段照 [member PBWavePlan.deployed] 念 ——
## [method PBRunSim.lock_plan] 已经把派出去的滤掉了。
## 准备阶段按「现在开打会是谁」预览一份，**同样要减掉派遣**。
##
## 不减的话，被派出去的人会**同时出现在出战席和出任务两排**，
## 而他只可能在一处。过滤本来只发生在 `lock_plan`，
## 也就是「点了开打他才从出战席上消失」—— 玩家在准备阶段
## 看到的是一支比实际多一个人的队伍，指令卡和装备栏也跟着多算他一份。
func _fighting_now(away: Array[PBUnit]) -> Array[PBUnit]:
	if _phase != Phase.PREPARE:
		return _plan.deployed
	var out: Array[PBUnit] = []
	for unit: PBUnit in _strategy.deploy(_state, _plan.wave, _cfg):
		if not away.has(unit):
			out.append(unit)
	return out


func _units_of(keys: Array[StringName]) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for key: StringName in keys:
		var unit := _state.roster.get(key, null) as PBUnit
		if unit != null:
			out.append(unit)
	return out


## 现在有没有抽屉摊着。预告行靠它决定要不要藏起来。
func _any_drawer_open() -> bool:
	for drawer: PBDrawer in [_offer, _equip, _stash, _beasts]:
		if drawer.visible:
			return true
	return false


## 把一个忍者放上出战席或收回仓库（§02 的指令卡）。
##
## **名单走 [PBStrategy] 的原语，界面不自己写 `state.lineup`** ——
## 和花钱那条是同一个理由：状态只由那一层改，
## 界面自己动字段迟早漏掉配套的在场名单刷新，而那种不同步不报错。
func _set_on_field(unit: PBUnit, on_field: bool) -> void:
	if unit == null:
		return
	var roster: Array[PBUnit] = _strategy.deploy(_state, _plan.wave, _cfg)
	if on_field:
		if roster.has(unit) or roster.size() >= _state.open_slots(_cfg):
			return
		roster.append(unit)
	else:
		roster.erase(unit)
	_strategy.set_lineup(_state, roster)


func _physics_process(_delta: float) -> void:
	if _run_over:
		return
	match _phase:
		Phase.PREPARE:
			# §01：准备阶段不限时。自动模式下由脚本玩家立刻做完，
			# 手动模式下就停在这里等 —— M1-b/c 的界面接在这个缝上。
			if auto_play:
				_finish_prepare()
		Phase.SETTLE:
			_gap_frames -= 1
			if _gap_frames <= 0:
				_enter_prepare()
		Phase.BATTLE:
			if not _paused:
				_advance_logic()
	_sync_visuals()


## 键盘：空格暂停，1/2/3 倍速，R 重开。
##
## 直接读 keycode 而不是走 Input Map —— 那段序列化格式跨版本很脆，
## 项目规范要求用编辑器加而不是手写进 project.godot。M0 阶段的调试键
## 还没定型，等操作方案定了再进 Input Map。
func _unhandled_input(event: InputEvent) -> void:
	# 战场上的点击（§02 的战斗中操作，M4-e）与拖动摆位（M4-f）。
	# **不看 [member _paused]** —— §02 原话是「暂停的时候也能点击」。
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		if _phase == Phase.PREPARE:
			_on_place_button(click)
		elif click.pressed:
			_on_field_click(click.position)
		return
	if event is InputEventMouseMotion and _picker.dragging != &"":
		_picker.drag_to(
			_state,
			_cfg,
			PBEnemyPool.to_field((event as InputEventMouseMotion).position, _field())
		)
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
		KEY_1:
			_speed = 1
		KEY_2:
			_speed = 2
		KEY_3:
			_speed = 3
		KEY_R:
			_restart()
		KEY_A:
			auto_play = not auto_play
			# 面板只在「手动 + 准备阶段」出现。切换时立刻反映，
			# 否则玩家关了自动却要等下一波才看得到商店。
			_set_panels_visible(_phase == Phase.PREPARE and not auto_play and not _run_over)
		KEY_Q:
			# 接/不接本波任务（§06）。手柄和触屏都点得到按钮，
			# 键盘上给一个快捷键 —— 这是准备阶段唯一需要反复试的开关。
			if _phase == Phase.PREPARE and not auto_play:
				_quest.toggle()
		KEY_B:
			# 带人方式：按战力，还是按羁绊（§09）。M2-d。
			#
			# **加这个键是因为不加的话羁绊面板是不可操作的信息。**
			# 面板第二行会说「还差 1 人就能进满档，+18%」，而玩家
			# 一个按钮都没有 —— 看得见动不了的 UI 比没有还糟，
			# 它只会让人以为自己漏掉了什么操作。
			#
			# 完整的「手动点选谁上场」要等阵容面板做成可交互。
			# 在那之前这个开关是同一个决策的**最小可玩形式**：
			# 一次按键就能看见「凑羁绊」和「堆战力」差多少。
			if _phase == Phase.PREPARE and not auto_play:
				_toggle_field_policy()
		KEY_V:
			# 开/关仓库。左边那个「仓库」按钮走同一条路 ——
			# 两条路各写一份迟早分叉（和任务卡的 Q 键同理）。
			if _phase == Phase.PREPARE and not auto_play:
				_toggle_drawer(_stash)
		KEY_ESCAPE:
			# **先收抽屉，再取消选中。** 一下按键做两件事会让人分不清
			# 刚才关掉的是哪一个；分两下按则每一下的后果都看得见。
			# 战场上没有「空白处」可点（面板铺满了下半屏），所以这个键是必需的。
			if _close_open_drawer():
				return
			# 战斗中还多一层：先退出「正在指定目标」（M4-e）。
			# 一下按键同时取消瞄准和选中的话，玩家分不清刚才取消的是哪一个。
			if _picker.aiming:
				_picker.aiming = false
				_refresh_panels()
				return
			_selection.set_to(PBSelection.Kind.NONE)
			_refresh_panels()
		KEY_ENTER:
			if _phase == Phase.PREPARE:
				_finish_prepare()


## 推进逻辑。倍速在这里体现为「一次多走几个 tick」，tick 本身的时长不变。
func _advance_logic() -> void:
	# 击杀顿帧（M3.5-h）。**只是不推进，不跳 tick** —— 见 [member _hitstop_frames]。
	if _hitstop_frames > 0:
		_hitstop_frames -= 1
		return
	_frame_counter += 1
	if _frame_counter < _frames_per_tick:
		return
	_frame_counter = 0
	for _i: int in _speed:
		if _battle.is_finished():
			break
		_battle.step()
	if _battle.is_finished():
		_end_wave()


## 进入准备阶段：把这一波的敌人和任务掷出来，然后**停下来**。
##
## 这一步之后玩家（或自动模式下的脚本玩家）花钱、排阵、决定接不接任务，
## 全部走 [PBStrategy] 那批原语 —— 与批量模拟同一套，RNG 次序不会分叉。
func _enter_prepare() -> void:
	_phase = Phase.PREPARE
	# 上一波的战场到此为止。**不丢掉的话准备阶段会一直画着上一波的队形** ——
	# 敌人都死了看不出来（死了就不画），己方却会站在那儿，
	# 而那份名单这一波可能已经换过人了。
	_battle = null
	_clear_feedback()
	_plan = PBRunSim.begin_wave(_state, _cfg, _rng)
	if debug_enemy_count > 0:
		# 纯视觉覆盖，见 debug_enemy_count 的说明。钳在 COUNT_CAP 内，
		# 因为「同屏不超过 COUNT_CAP」本身就是 §04 的验收项。
		_plan.wave.count = mini(debug_enemy_count, _cfg.count_cap)
	# 名单还没锁，先按「如果现在就开打」预览一份，让准备阶段有东西可看。
	_sync_deployed()
	_quest.reset(_state, _cfg, _plan)
	_set_panels_visible(not auto_play)
	_sync_visuals()


## 准备阶段结束：锁定名单与派遣，开打。
##
## 自动模式下由脚本玩家代做花钱决策；手动模式下玩家已经在面板上花完了，
## 所以**跳过 `prepare()`** —— 再调一次会让脚本玩家把剩下的钱也花掉。
func _finish_prepare() -> void:
	if _phase != Phase.PREPARE or _run_over:
		return
	# **摆着一组没挑的三选一时不许开打。** 钱在摆牌那一刻就扣了
	# （[method PBShopRules.open_offer]），开打会把那一组连同那笔钱一起冲掉，
	# 而账面上只表现为「金币怎么少了 300」。
	if not _state.pending_offer.is_empty():
		if not auto_play:
			_toggle_drawer(_offer, true)
			return
		# 自动模式下没有人去挑。**绝不能停在这里** ——
		# `_physics_process` 每帧调一次 `_finish_prepare`，整局会卡死在准备阶段。
		PBShopRules.take_offer(_state, 0)
	_set_panels_visible(false)
	if auto_play:
		_strategy.prepare(_state, _plan.wave, _cfg, _rng)
	# 手动模式下派遣是玩家的决定（M1-d）；自动模式仍由脚本玩家的
	# [enum PBStrategy.Dispatch] 策略决定，这样开着自动跑出来的整局
	# 与批量模拟逐波一致，UI 改动有没有把数值弄歪可以直接对拍。
	var accepted: bool = (
		_strategy.accept_quest(_state, _plan.wave, _plan.quest_grade, _cfg)
		if auto_play
		else _quest.accepted()
	)
	PBRunSim.lock_plan(_state, _plan, _strategy.deploy(_state, _plan.wave, _cfg), accepted, _cfg)
	_battle = PBBattleSim.new(
		_plan.wave, _plan.dps, _state.def_reduction(_cfg), _cfg, _plan.attackers
	)
	_frame_counter = 0
	_phase = Phase.BATTLE
	_picker.aiming = false
	# **再摆一次面板。** 上面那次是在 `_phase` 还是 PREPARE 时调的，
	# 而指令卡与信息栏的可见性现在要看阶段（§02 的战斗中操作，M4-e）——
	# 少这一行的话那两块会一直藏到下一波准备阶段。
	_set_panels_visible(false)
	# 血量快照要跟着新的一波从头来 —— 留着上一波的话，开波第一帧
	# 会把「上一波那个槽位剩 3 点血」和「这一波满血」的差算成一次巨额伤害，
	# 表现是开波瞬间满屏飘字。
	_clear_feedback()
	_sync_deployed()


func _end_wave() -> void:
	PBRunSim.settle_wave(_state, _plan, _battle.result(), _cfg, _rng)
	if _state.base_hp <= 0.0:
		_run_over = true
		_set_panels_visible(false)
		_sync_visuals()
		return
	_state.wave_index += 1
	_phase = Phase.SETTLE
	# 结算那一秒把指令卡也收掉：这一波已经没有什么可指挥的了，
	# 而留着一张能点的卡会让人以为还来得及做点什么。
	_set_panels_visible(false)
	_gap_frames = WAVE_GAP_FRAMES


## 准备阶段那几块面板一起显隐、一起刷新 —— 分开控制迟早漏掉一个，
## 表现为「战斗中还挂着半张商店」。
##
## ## M4-e 起指令卡与信息栏在战斗中也留着
##
## §02 要求「打起来之后照样点得到忍者、照样能指定他打谁」。
## 那两块因此分成了另一档：**战斗中可见，但内容整个换掉**
## （见 [method PBCommandCard.set_battle]）—— 升级、装备、派任务
## 都是准备阶段的决策，留着它们等于让玩家在战斗中花本该更早花的钱。
##
## 剩下三块（槽位列、任务卡、羁绊带）仍然只在准备阶段出现：
## 它们全都占着战场那条道，而战斗中那条道是有人的。
func _set_panels_visible(shown: bool) -> void:
	_command.visible = shown or _phase == Phase.BATTLE
	_unit_info.visible = _command.visible
	_slots.visible = shown
	_quest.visible = shown
	_bonds.visible = shown
	if not shown:
		# 抽屉全部收起来。战斗中留着一块的话它会盖在战场上，
		# 而它上面的按钮此刻一个都不该生效。
		for drawer: PBDrawer in [_offer, _equip, _stash, _beasts]:
			drawer.close()
		# 一波打完选中就该散掉 —— 留着的话下一波开局指令卡里还挂着
		# 上一波选的那个人，而他这一波可能压根没上场。
		_selection.set_to(PBSelection.Kind.NONE)
	# **判据是「指令卡露不露脸」，不是 `shown`**（M4-e）：战斗中那两块留着，
	# 而这里传进来的是 false —— 照 `shown` 判的话它们会**显示着上一个阶段的内容**。
	if _command.visible:
		_refresh_panels()


## 换一种带人方式，并立刻重画 —— 玩家按下去要马上看到倍率变了多少，
## 等下一波才生效的话这个开关就没法用来比较。
func _toggle_field_policy() -> void:
	_strategy.field_policy = (
		PBStrategy.Field.RAW_POWER
		if _strategy.field_policy == PBStrategy.Field.BOND_AWARE
		else PBStrategy.Field.BOND_AWARE
	)
	_refresh_panels()
	_sync_deployed()


func _refresh_panels() -> void:
	if _phase == Phase.BATTLE:
		_refresh_battle_panels()
		return
	if not _command.visible:
		return
	_command.set_battle(false)
	# 先把在场名单按当前策略重挑一遍，各块面板才看的是同一支队伍。
	# 漏了这一步，玩家抽到的新卡要等到点「开打」时才进队，
	# 而面板上的羁绊倍率会停在上一波 —— 不报错，只是数字不动。
	_strategy.bring_to_field(_state, _cfg)
	# 选中的人如果已经不在仓库里了（卖了/换局了），选中先散掉再画 ——
	# 不散的话指令卡会对着一张不存在的卡摆出「升级」。
	if _selection.unit_id != &"" and not _state.roster.has(_selection.unit_id):
		_selection.set_to(PBSelection.Kind.NONE)
	var away: Array[PBUnit] = _dispatch_preview()
	var deployed: Array[PBUnit] = _fighting_now(away)
	_command.refresh(_selection, _state, _cfg, _plan, deployed, away)
	_unit_info.refresh(_selection, _state, _cfg, _plan.wave, deployed)
	_slots.refresh(_selection, _state, _cfg, _plan.wave, deployed, away)
	_quest.refresh(_state, _cfg, _plan)
	_bonds.refresh(_state, _cfg, _strategy.field_policy == PBStrategy.Field.BOND_AWARE)
	# 抽屉只在开着的时候重画 —— 关着的那三块每次都算一遍纯属浪费，
	# 而装备栏那一份要跑一次完整的分配。
	if _offer.visible:
		_offer.refresh(_state, _cfg, _plan.wave)
	if _equip.visible:
		_equip.refresh(_selection.unit_of(_state), _state, _cfg, deployed)
	if _stash.visible:
		_stash.refresh(_selection, _state, _cfg, _plan.wave, deployed, away)
	if _beasts.visible:
		_beasts.refresh(_state, _cfg)


## 战斗中的那两块（§02，M4-e）。**只在选中变了之后调** ——
## 每帧重排整块文字要跑一次装备分配，一秒六十次太贵，而那几行字
## 在一波之内根本不变。会变的血蓝条走 [method PBUnitInfo.show_live]。
func _refresh_battle_panels() -> void:
	var live := _selected_attacker()
	_command.set_battle(true, _picker.aiming, live.forced_target if live != null else -1)
	_command.refresh(_selection, _state, _cfg, _plan, _plan.deployed)
	_unit_info.refresh(_selection, _state, _cfg, _plan.wave, _plan.deployed)


## 选中那个忍者这一波在场上的样子。反查在 [PBFieldPicker] 里。
func _selected_attacker() -> PBAttacker:
	if _selection.kind != PBSelection.Kind.UNIT:
		return null
	return _picker.attacker_of(_battle, _plan.deployed, _selection.unit_id)


## 玩家在战场上点了一下（§02 的战斗中操作，M4-e）。
##
## **暂停时照样有效** —— `_unhandled_input` 不受 [member _paused] 影响，
## 而 §02 原话就是「暂停的时候也能点击」。
func _on_field_click(at: Vector2) -> void:
	if _battle == null:
		return
	var field := _field()
	var spot := PBEnemyPool.to_field(at, field)
	var pick: float = PICK_RADIUS_PX / PBEnemyPool.px_per_unit(field)
	# 正在指定目标：只认敌人。点空地就当取消 —— 让「按错了」有一条退路。
	if _picker.aiming:
		_picker.aim(_selected_attacker(), _picker.enemy_at(_battle, spot, pick))
		_picker.aiming = false
		_refresh_battle_panels()
		return
	var ally := _picker.ally_at(_battle, spot, pick)
	if ally != null and ally.slot < _plan.deployed.size():
		_select(PBSelection.Kind.UNIT, _plan.deployed[ally.slot].key())
		return
	# 点空地取消选中。战场上没有别的「空白处」，不给这条路的话
	# 选中框会一直挂在最后点过的那个人身上。
	_selection.set_to(PBSelection.Kind.NONE)
	_refresh_battle_panels()


## 准备阶段在战场上按下 / 松开左键（§02 的开战位置，M4-f）。
##
## ## 按下就选中、拖动就摆位，是同一个动作的两段
##
## 分成「先点选、再拖」两步的话，玩家要点两次才能挪一个人，
## 而这是准备阶段最高频的操作。按下即选中还顺带把射程圈亮出来 ——
## 摆位要有依据，而依据就是「他够得到哪」。
func _on_place_button(click: InputEventMouseButton) -> void:
	if not click.pressed:
		_picker.dragging = &""
		return
	var units := _fighting_now(_dispatch_preview())
	var field := _field()
	var hit: int = PBFieldPicker.unit_at(
		units,
		_state.formation,
		_cfg,
		PBEnemyPool.to_field(click.position, field),
		PICK_RADIUS_PX / PBEnemyPool.px_per_unit(field)
	)
	_picker.dragging = units[hit].key() if hit >= 0 else &""
	if hit >= 0 and not _selection.is_same(PBSelection.Kind.UNIT, _picker.dragging):
		_select(PBSelection.Kind.UNIT, _picker.dragging)


func _restart() -> void:
	_run_over = false
	_paused = false
	_gap_frames = 0
	_battle = null
	_set_panels_visible(false)
	_state = PBRunSim.new_state(_cfg)
	_strategy = PBStratBalanced.new()
	_rng = PBRngStreams.new(_resolve_seed())
	_enter_prepare()


## 命中白闪 + 伤害飘字 + 击杀顿帧（§02 的手感那一段，M3.5-h）。见 [PBHitFeedback]。
##
## **只在真要顿的时候才写**：直接赋值的话，没人死的那些帧会把
## 正在走的顿帧**清成 0** —— 顿帧于是永远只持续一帧，
## 而画面上几乎看不出区别（`test_feedback.gd` 逐帧钉着这一条）。
func _feedback() -> void:
	var freeze: int = _feel.poll(_battle, _plan.wave, _pool, _floats, _field())
	if freeze > 0:
		_hitstop_frames = freeze


## 手感那几样的状态一起清掉。**必须是一起** ——
## 只清一半的话，新的一波会带着上一波的血量快照或者半屏没飘完的旧数字。
func _clear_feedback() -> void:
	_feel.reset()
	_floats.clear()
	_telegraph.clear()
	_shots.clear()
	_hitstop_frames = 0


## 把前面的波次用解析式模型瞬间跑完，不渲染。调试用，见 [member start_wave]。
##
## 走的是 `plan_wave` / `settle_wave` 这条正路，所以快进出来的状态
## 和正常打过去是一致的 —— 金币、卡池、科技、基地血全都对得上。
## 快进途中就死了的话，如实标成「本局结束」。
##
## 早先这里 break 完就接着渲染，画面会显示一个基地血为负的第 N 波 ——
## 看起来像「快进到了第 N 波」，实际是「第 N 波打不过去」。
## 这种「失败被画成正常状态」的错误极难从现象反推，必须显式处理。
func _fast_forward_to(target_wave: int) -> void:
	# M3-a 起**不能**在这里换成解析式模型抄近路。射程与多目标分配只有
	# 逐 tick 模型有，换过去等于用另一套战斗规则快进 ——
	# 快进出来的金币、卡池、基地血会和真打过去的对不上，且不报错。
	var quick := _cfg.clone()
	while _state.wave_index < target_wave:
		var plan := PBRunSim.plan_wave(_state, _strategy, quick, _rng)
		var outcome := PBRunSim.resolve_battle(plan, _state.def_reduction(quick), quick)
		PBRunSim.settle_wave(_state, plan, outcome, quick, _rng)
		if _state.base_hp <= 0.0:
			_run_over = true
			return
		_state.wave_index += 1


## 指定了种子就用它，否则用系统时间开一局新的。
func _resolve_seed() -> int:
	if run_seed != 0:
		return run_seed
	return int(Time.get_unix_time_from_system())


func _sync_visuals() -> void:
	_floats.step()
	var field := _field()
	# 准备阶段还没有敌人（要等 _finish_prepare() 才生成），
	# 但**己方要画出来** —— 摆位要成为一个操作，第一步是看得见现在摆成什么样。
	_limit.visible = _phase == Phase.PREPARE and not _run_over
	if _battle == null:
		_pool.sync_enemies([], 0, field, false)
		_telegraph.clear()
		_shots.clear()
		_sync_placed(field)
	else:
		_feedback()
		_telegraph.sync_pending(_battle.attackers(), _battle.current_tick(), field)
		# 飞行中的子弹（M4-b）。**它是 sim 里真有的东西** ——
		# 伤害要等它够到目标才结算，见 [PBProjectile]。
		_shots.sync_shots(_battle.shots(), field)
		# §02 第 8 点：己方忍者也要画在场上。射程、站位、防挤、敌人还手
		# 四件事全都只有在这里才看得见 —— 那是 M3-a 到 M3.5-c 做的全部内容。
		_allies.sync_allies(_battle.attackers(), _plan.deployed, field)
		# §02 的第三层视觉编码：克得住的敌人加一圈亮边。
		# 这是玩家在战斗中最需要的即时信息 —— 原版要点开技能说明才看得到。
		var counterable: bool = _state.can_counter(_plan.wave.element)
		_pool.sync_enemies(_battle.enemies(), _battle.current_tick(), field, counterable)
		_sync_selected(field)
	_sync_base()
	_sync_info()
	_sync_preview()


## 下一波预告 + 克制覆盖度。§03 称这是本案投入产出比最高的一处改进 ——
## 原版的克制关系要点开技能说明才看得到，玩家全靠背。
##
## 预告零副作用，因为波次生成是 `(种子, 波次)` 的纯函数，
## 见 [method PBRngStreams.wave_rng]。
func _sync_preview() -> void:
	if _run_over:
		_preview.text = ""
		return
	# 抽屉盖住这一行的位置（[constant PBDrawer.BAND]），但左边那 40px 盖不到 ——
	# 不藏起来的话，抽屉开着时行首那几个字会从缝里漏出来。
	_preview.visible = not _any_drawer_open()
	var next := PBRunSim.preview_wave(_state.wave_index + 1, _cfg, _rng)
	var missing := _state.missing_counters()
	var covered: int = PBWaveRules.WAVE_ELEMENTS.size() - missing.size()

	var gap_text: String = "已齐"
	if not missing.is_empty():
		var names := PackedStringArray()
		for element: int in missing:
			names.append(str(PBUnitTile.ELEMENT_NAMES.get(element, "?")))
		gap_text = "缺 %s" % "".join(names)

	var keys: String = "空格暂停　1/2/3 倍速　R 重开　A 自动:%s" % ("开" if auto_play else "关")
	if _phase == Phase.PREPARE and not auto_play:
		keys = "拖动摆位　回车开打　Q 接任务　V 仓库　B 换带人法　Esc 取消　A 自动:关"
	_preview.text = (
		"下一波：%s %s　　克制覆盖 %d/5（%s）　　%s"
		% [
			PBUnitTile.ELEMENT_NAMES.get(next.element, "?"),
			PBUnitTile.SHAPE_NAMES.get(next.shape, "?"),
			covered,
			gap_text,
			keys,
		]
	)


## 准备阶段：把上场名单画在他们的开战位置上（§02，M4-f）。
##
## 位置走 [method PBFormationRules.spot_of] —— 和
## [method PBCombatRules.build_attackers] 里那两行必须给出同一个答案，
## 两处分叉的表现是「我摆好的阵型，一开打就跳了一下」。
func _sync_placed(field: Vector2) -> void:
	if _run_over or _phase != Phase.PREPARE:
		_allies.clear()
		return
	var units := _fighting_now(_dispatch_preview())
	var spots := PBFormationRules.spots_of(units, _state.formation, _cfg)
	_allies.sync_placed(units, spots, field)
	var live: int = -1
	if _selection.kind == PBSelection.Kind.UNIT:
		live = PBFieldPicker.index_of(units, _selection.unit_id)
	if live < 0:
		_allies.show_range(Vector2.ZERO, 0.0)
		return
	# 选中谁就画谁的射程圈 —— 摆位要有依据，而依据就是「他够得到哪」。
	_allies.show_range(
		PBEnemyPool.to_screen(spots[live], field),
		_cfg.reach_distance(units[live].character.reach_tier()) * PBEnemyPool.px_per_unit(field)
	)


## 选中那个忍者的射程圈与实时血蓝（§02，M4-e）。每渲染帧一次。
##
## 这两样**必须每帧刷**：圈跟着他跑（他会前压、会贴身），
## 血蓝每 tick 都在变。而指令卡那一整块文字不用（[method _refresh_battle_panels]）。
func _sync_selected(field: Vector2) -> void:
	var live := _selected_attacker()
	if live == null:
		_allies.show_range(Vector2.ZERO, 0.0)
		return
	_allies.show_range(
		PBEnemyPool.to_screen(live.pos, field), live.reach * PBEnemyPool.px_per_unit(field)
	)
	_unit_info.show_live(live)


## 战场的尺寸，`Vector2(长, 高)`。渲染层全部坐标换算都收这一个参数。
##
## 现造而不是缓存：`_cfg` 是可变的（调试开关会改它），
## 缓存一份的话改了配置画面不跟着动，而那种不同步不报错。
func _field() -> Vector2:
	return Vector2(_cfg.field_length, _cfg.field_height)


## 基地血量画成一个高度随血量变化的条，长在战场那条道的左端。
##
## 高度和落点跟着战场那条道走。**M3.5-e 改版之后这里一直是错的**：
## 那时道从 95–300 缩到了 134–198，而这个条还按「底边在 y=300、最高 150」画，
## 满血时整根条从 150 一直盖到 300 —— 把羁绊带和预告行压在下面。
## 不报错，只是看起来像面板穿帮。所以现在下沿也是**算出来的**
## （[method PBEnemyPool.lane_bottom]），不是又一个手写的常量。
func _sync_base() -> void:
	var ratio: float = clampf(_state.base_hp / _cfg.base_hp, 0.0, 1.0)
	var bottom: float = PBEnemyPool.lane_bottom(_field())
	_base_rect.size.y = lerpf(4.0, bottom - PBEnemyPool.LANE_TOP, ratio)
	_base_rect.position.y = bottom - _base_rect.size.y
	_base_rect.color = PBSkin.GOOD.lerp(PBSkin.BAD, 1.0 - ratio)


## 上场名单现在由 [PBFieldSlots] 那一列可点的头像承担（M3.5-e）。
##
## M0 到 M3 这里画的是一列不可点的 `Polygon2D` 色块。换成头像格是因为
## §02 的战场直接操作要求「**点一下忍者就能操作他**」——
## 一个点不动的色块表达不了那件事，而两套并存会让屏幕上出现两列忍者。
##
## 战斗阶段显示锁定的名单，准备阶段显示「现在开打的话会是谁」的预览。
## [method PBStrategy.deploy] 只读不改状态，拿来预览是安全的。
func _sync_deployed() -> void:
	if not _slots.visible:
		return
	var away: Array[PBUnit] = _dispatch_preview()
	_slots.refresh(_selection, _state, _cfg, _plan.wave, _fighting_now(away), away)


func _sync_info() -> void:
	if _run_over:
		_info.text = "本局结束　卡在第 %d 波　按 R 重开" % _state.wave_index
		return
	var wave: PBWave = _plan.wave
	var head := (
		"第 %d 波　%s　%s　　基地 %d　金 %d　卡池 %d"
		% [
			wave.index,
			PBUnitTile.ELEMENT_NAMES.get(wave.element, "?"),
			PBUnitTile.SHAPE_NAMES.get(wave.shape, "?"),
			int(_state.base_hp),
			_state.gold,
			_state.roster.size(),
		]
	)
	if _phase == Phase.PREPARE:
		# §01：准备阶段不限时。所以这里不显示秒数，只说在等什么。
		_info.text = "%s　　【准备阶段】敌 %d　任务 %s" % [head, wave.count, _quest_name()]
		return
	var out: PBCombatOutcome = _battle.result()
	_info.text = (
		"%s　　敌 %d/%d　漏 %d　　%.1fs　%s"
		% [
			head,
			out.kills,
			wave.count,
			out.leaked,
			out.battle_seconds,
			"暂停" if _paused else "%d 倍速" % _speed,
		]
	)


## 属性名与波型名走 [PBUnitTile] 那两张表 —— M4-f 之前这里另有一份（全项目第三份）。
## 多一份不报错，只是有一天「物」和「物理」在两块面板上同时出现。
func _quest_name() -> String:
	return String(PBEconomyRules.QUEST_GRADES[_plan.quest_grade])
