class_name PBBattleView
extends Node2D
## 战斗画面。把 `src/core/` 的模拟接上渲染。M0-b。
##
## ## 定帧：数物理帧，不累加 delta
##
## §14 的铁律：**定帧 20 tick/s，倍速只改每帧步进多少个 tick。**
## `_physics_process` 本身就是固定频率的（默认 60Hz），60 / 20 = 3，
## 每 3 个物理帧推进一个逻辑 tick —— 全整数，零浮点。
## `_accumulator += delta` 会每帧累加浮点误差，3 倍速和 1 倍速跑出来的
## tick 序列慢慢就错开了，而 §12 的存档回滚、§13 的每日种子与战报回放
## 全都要求「逐 tick 完全一致」。`Engine.time_scale` 同理，绝对不用。
##
## ## 这一层只读 sim，改的只有玩家的指令
##
## 画图与 HUD 一个字段都不回写；改状态只能走 [PBRunSim] 的 `plan_wave` /
## `settle_wave`（批量模拟走的同一条路）。**只有两个例外，都是玩家的指令，
## 而且各自只有一个入口**：点名（[member PBAttacker.forced_target]）
## 和手动放忍术（[method PBBattleSim.cast_ultimate]）。

## 一波的三个阶段（§01）。**准备阶段不限时，等玩家**（M1 把它显式拆出来，
## 在那之前它被 [method PBRunSim.plan_wave] 在一帧里做完了）。
enum Phase {
	PREPARE,  ## 花钱、排阵、决定接不接任务。§01：不限时，可存档退出
	BATTLE,  ## 逐 tick 推进
	SETTLE,  ## 结算，看一眼战果
}

## 结算停多少个物理帧。§01 说 2–4 秒，这里取 1 秒够看清结果。
const WAVE_GAP_FRAMES: int = 60

## 点战场上的单位时，鼠标离多近算点中（像素，M4-e）。**比单位本身大一圈** ——
## 按外观尺寸判的话「点边上一点就选不中」，而玩家会认为点选坏了。
const PICK_RADIUS_PX: float = 12.0

## 本局的随机种子。0 表示用系统时间。留成可指定是为了**测试可复现**，
## 以及 §13 的每日种子挑战将来只要把 `hash(date_utc)` 填进来就行。
@export var run_seed: int = 0

## 调试用：直接从第几波开始。1 表示正常从头打。前面的波次瞬间跑完（不渲染），
## **走的是批量模拟同一条路**（`plan_wave` / `settle_wave`），
## 所以快进到第 N 波的状态是真的，不是伪造的。
@export var start_wave: int = 1

## 调试用：强制第一波的敌人数量。0 表示按 §04 的公式正常算。
## **只为回答视觉问题**（「`COUNT_CAP` 取 48 时同屏糊不糊」）。
## 它不改任何平衡参数 —— 别拿它跑数值结论。
@export var debug_enemy_count: int = 0

## 自动推进：准备阶段由脚本玩家代劳，不等输入。§01 点名要这个模式。
## 它同时是 M1 的**回归工具** —— 开着的时候整局的决策序列与批量模拟完全一致。
##
## **默认关**：开局第一眼看到的应该是准备阶段，不是一场自己打起来的第一波。
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

## 呼出功能菜单之前是不是已经暂停着。见 [method _open_menu]。
var _paused_before_menu: bool = false

## 战场上现在选中了什么（§02，M3.5-e）。指令卡、信息栏、槽位高亮三处都读它。
var _selection := PBSelection.new()

## 命中白闪 / 伤害飘字 / 击杀顿帧的接线（M3.5-h）。见 [PBHitFeedback]。
var _feel := PBHitFeedback.new()

## 战场上「点到了谁」和「让谁打谁」（§02 的战斗中操作，M4-e）。见 [PBFieldPicker]。
var _picker := PBFieldPicker.new()

## 选中那个忍者上一帧放不放得出忍术（M5-9）。
## 只记「上一次是什么」，好在真的翻面那一帧才去重排指令卡。
var _cast_ready: bool = false


## 击杀顿帧还剩几个物理帧。**它不碰 tick 序列**：期间只是不调
## `_advance_logic`，`_frame_counter` 也不动，走完之后 tick 一个不多一个不少。
## **绝不能用「跳过一个 tick」或者 `Engine.time_scale`**：前者直接改模拟结果，
## 后者违反铁律 2，而两者的表现都只是「同一个种子跑出来的局慢慢对不上」。
var _hitstop_frames: int = 0

# @onready 必须排在普通成员之后 —— .gdlintrc 的 class-definitions-order
# 定死了「prvvars 在 onreadyprvvars 之前」。赋值时机也在 _ready() 之前（_init() 取不到）。
@onready var _pool: PBEnemyPool = $Actors/Enemies
@onready var _shots: PBShotPool = $Shots
@onready var _allies: PBAllyPool = $Actors/Deployed
@onready var _telegraph: PBTelegraphPool = $Telegraph
@onready var _floats: PBFloatTextPool = $Floats
@onready var _aim: PBAimLines = $Aim
@onready var _lane: ColorRect = $Lane
@onready var _base_rect: ColorRect = $Base
@onready var _limit: ColorRect = $Limit
@onready var _info: Label = $HUD/Info
@onready var _preview: Label = $HUD/Preview
@onready var _command: PBCommandCard = $HUD/Command
@onready var _unit_info: PBUnitInfo = $HUD/UnitInfo
@onready var _slots: PBFieldSlots = $HUD/Slots
@onready var _quest: PBQuestCard = $HUD/Quest
@onready var _offer: PBOfferModal = $HUD/Offer
@onready var _parts: PBPartsBay = $HUD/Equip
@onready var _gear: PBEquipBay = $HUD/Gear
@onready var _tip: PBTooltip = $HUD/Tip
@onready var _menu: PBSystemMenu = $HUD/Menu
@onready var _bay: PBRosterBay = $HUD/Stash
@onready var _ground: PBDropArea = $HUD/Ground
@onready var _beasts: PBBeastModal = $HUD/Beasts


func _ready() -> void:
	# 走装载器而不是 PBSimConfig.new()：后者默认的是给对拍用的合成卡池，
	# 忘了装真角色表不会报错，只表现为「玩到的和扫描结论对不上」（§14 铁律 5）。
	_cfg = PBGameData.config()
	# 画面必须逐 tick —— 排队模型算完就没了，没有中间状态可画。
	_cfg.use_tick_battle = true
	# **忍术改成玩家自己放**（M5-9）。默认那一档（[constant PBAimRules.Policy.AUTO]）
	# 是 §02 给手机端留的，它在开波那一刻会让**整队同时下达、0.5 秒后同时落地** ——
	# 玩家看到的是「开打自动炸一下」，而那也正是「单波 0.55 秒」的根源。
	# 扫描那一路仍然走 AUTO（那是它要量的东西），所以只在这里改。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_frames_per_tick = maxi(Engine.physics_ticks_per_second / _cfg.tick_rate, 1)

	PBLayout.apply_to(_lane, _base_rect, _limit, _info, _preview, _field(), _cfg.deploy_limit_x)

	_rng = PBRngStreams.new(_resolve_seed())
	_state = PBRunSim.new_state(_cfg)
	_strategy = PBStratBalanced.new()

	_command.command.connect(_on_command)
	_slots.slot_picked.connect(_on_slot_picked)
	_quest.slot_picked.connect(_on_slot_picked)
	_quest.card_dropped.connect(_on_card_moved)
	_bay.scrolled.connect(_refresh_panels)
	_bay.card_dropped.connect(_on_card_moved)
	# 战场是 Node2D，收不了引擎的拖放协议 —— 这一层透明矩形是它的收件人。
	_ground.cover(PBLayout.B_FIELD, PBUnitTile.ZONE_FIELD, _unit_on_field_at)
	_ground.grabbed.connect(func(id: StringName) -> void: _select(PBSelection.Kind.UNIT, id))
	_ground.hovered.connect(_on_drag_over_field)
	_ground.card_dropped.connect(
		func(from: StringName, id: StringName, at: Vector2) -> void:
			_on_card_moved(from, id, PBUnitTile.ZONE_FIELD, PBLayout.to_field(at, _field()))
	)
	# 两块弹层各自只管「我被点了什么」，开关由这里统一裁决（见 [PBModal]）。
	_offer.picked.connect(_on_offer_picked)
	_gear.item_equipped.connect(_on_equip_changed.bind(true))
	_parts.item_returned.connect(_on_equip_changed.bind(false))
	_parts.tip_requested.connect(_tip.show_card)
	_gear.tip_requested.connect(_tip.show_card)
	_bay.unit_picked.connect(func(id: StringName) -> void: _select(PBSelection.Kind.UNIT, id))
	_beasts.beast_chosen.connect(_on_beast_chosen)
	_menu.resumed.connect(_close_menu)
	# **退出走 `quit()` 而不是 `get_tree().quit()` 的别名** —— 前者会走完
	# `NOTIFICATION_WM_CLOSE_REQUEST` 那一套，将来加自动存档时挂在那儿就行。
	_menu.quit_requested.connect(get_tree().quit)
	# 任务卡那三句长话由这里组一遍再交给 tooltip —— 组它要 state / cfg / plan
	# 三样，而任务卡一样都不持有（见 [signal PBQuestCard.detail_requested]）。
	_quest.detail_requested.connect(
		func(anchor: Rect2) -> void:
			_tip.show_card(
				anchor,
				"本波任务 · %s 级" % PBEconomyRules.QUEST_GRADES[_plan.quest_grade],
				_quest.tip_body(_state, _cfg, _plan)
			)
	)
	_fast_forward_to(start_wave)
	_enter_prepare()


## 玩家在准备阶段买了一笔。**钱走 [PBStrategy] 的原语，不由界面自己扣** ——
## 那是批量模拟走的同一批函数。界面自己扣钱的话迟早会和保底计数之类的东西
## 不同步，而这种不同步不报错，只表现为「玩到的和扫描结论对不上」。
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
			# 挑哪一张是玩家在 [PBOfferModal] 上做的决定。
			# 直接走 `pull_once` 的话，脚本玩家的挑法会替真人做完这个决定。
			if PBShopRules.open_offer(_state, _plan.wave, _cfg, _rng):
				_open_modal(_offer)
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
			_on_card_moved(PBUnitTile.ZONE_FIELD, _selection.unit_id, PBUnitTile.ZONE_STASH)
			return
		PBCommandCard.CMD_DEPLOY:
			_on_card_moved(PBUnitTile.ZONE_STASH, _selection.unit_id, PBUnitTile.ZONE_FIELD)
			return
		PBCommandCard.CMD_DISPATCH:
			# **走 [PBCardMoves] 那一份**（M5-13）：派任务要同时改两处状态，
			# 而这一格在那之前直接调 `toggle_dispatch`，只改了一处。
			PBCardMoves.toggle_quest(
				_state, _strategy, _plan, _selection.unit_of(_state), _cfg
			)
		PBCommandCard.CMD_BEAST_PICK:
			_open_modal(_beasts)
		PBCommandCard.CMD_BEAST_UP:
			# M3.5-e 漏了这一条：没有分支的指令会掉进下面那个 `_`，
			# 于是「升级尾兽」被当成一条叫 `beast_up` 的科技去买 ——
			# 买不到，也不报错，点下去纯粹没反应。
			PBShopRules.upgrade_beast(_state, _cfg)
		_:
			_strategy.buy_tech(_state, StringName(String(command_id).trim_prefix("tech_")), _cfg)
	_sync_deployed()
	_refresh_panels()


## 战斗中的三条指令（§02，M4-e / M5-9）。开关语义见
## [method PBFieldPicker.toggle]。
func _on_battle_command(command_id: StringName) -> void:
	match command_id:
		PBCommandCard.CMD_ATTACK:
			_picker.toggle(PBFieldPicker.Aim.TARGET)
		PBCommandCard.CMD_ULTIMATE:
			_picker.toggle(PBFieldPicker.Aim.ULTIMATE)
		PBCommandCard.CMD_CLEAR_TARGET:
			_picker.release(_battle, _selected_attacker())
	_refresh_battle_panels()


## 玩家点了一个槽位。**再点一次同一个 = 取消选中** ——
## 没有「空白处点一下取消」这条路的话，选中框会一直挂在最后点过的那个人身上。
func _on_slot_picked(kind: PBSelection.Kind, unit_id: StringName) -> void:
	# **选中不再顺手弹装备栏**（M4-f）。§02 原话是「信息栏和装备栏一起弹出」，
	# 而那是在准备阶段的战场还空着的时候写的。现在战场上站着人、还能拖动摆位：
	# 每选一个人就弹一块盖住半个战场的面板，等于把最高频的那个操作
	# 挡在自己的反馈前面。
	_select(kind, unit_id)


## 换一个选中。**再点一次同一个 = 取消选中** ——
## 没有「空白处点一下取消」这条路的话，选中框会一直挂在最后点过的那个人身上。
func _select(kind: PBSelection.Kind, unit_id: StringName) -> void:
	if _selection.is_same(kind, unit_id):
		_selection.set_to(PBSelection.Kind.NONE)
	else:
		_selection.set_to(kind, unit_id)
	_refresh_panels()


## 摊开这一层模态，**并把另一层关掉**。
##
## 裁决集中在这里而不是各弹层自己抢，见 [PBModal] 顶部。两层都是
## 「不选就不能继续」，同时摊着两层的话上面那一层挡住的是一个
## 玩家已经欠下的回答 —— 而它不报错，只是下面那层永远点不到。
func _open_modal(which: PBModal) -> void:
	for modal: PBModal in [_offer, _beasts]:
		if modal != which:
			modal.close()
	which.open()
	_refresh_panels()


## 玩家从三选一里挑了一张。挑完这一层就没有内容了，直接收起来。
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


## 收掉现在摊着的那一层模态。**没有摊着的就返回 false**，
## 让 `Esc` 接着去做它的第二件事（取消选中）。
##
## 三选一那层不收 —— 那一组候选是掏了钱的，收起来它就找不回来了
## （[method PBOfferModal._closable] 也不给关闭按钮，两处是同一条规矩）。
func _close_modal() -> bool:
	if not _beasts.visible:
		return false
	_beasts.close()
	_refresh_panels()
	return true


## 这一波谁去做任务：锁过了照 `dispatched_ids` 念，准备阶段就是任务栏里站着的那几个。
##
## **M5-7 少了一种口径**：「接了任务但一个人都没挑」跟着那个按钮一起没了 ——
## 接不接现在**就是**任务栏里站着几个人（见 [PBQuestCard] 顶部）。
## 脚本玩家仍走末尾规则，但那条路在 `lock_plan` 里，不经过这里。
func _dispatch_preview() -> Array[PBUnit]:
	if not _state.dispatched_ids.is_empty():
		return _units_of(_state.dispatched_ids)
	return _units_of(_state.dispatch_manual)


## 这一波**真会打**的人。派出去做任务的不在里面（§06）。
##
## 战斗与结算阶段照 [member PBWavePlan.deployed] 念 ——
## [method PBRunSim.lock_plan] 已经把派出去的滤掉了。
## 准备阶段按「现在开打会是谁」预览一份，**同样要减掉派遣**：
## 不减的话被派出去的人会**同时出现在战场和任务栏**，而他只可能在一处。
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


## 一张卡被拖到了另一个区（§02 的拖放三区，M5-4）。规则在 [PBCardMoves] ——
## **指令卡上的「派上场 / 下场 / 派任务」走的是同一批函数**，
## 各写一份的话「拖过去能做但按按钮做不到」迟早出现，而它不报错。
func _on_card_moved(
	from_zone: StringName, unit_id: StringName, to_zone: StringName, at := PBCardMoves.NO_SPOT
) -> void:
	if _phase != Phase.PREPARE or _run_over:
		return
	var unit := _state.roster.get(unit_id, null) as PBUnit
	PBCardMoves.move(_state, _strategy, _plan, unit, from_zone, to_zone, at, _cfg)
	# 搬完顺手选中他。走 `set_to` 不走 `_select` —— 后者再点同一个人是
	# 「取消选中」，而拖完把选中取消掉等于反馈消失。
	_selection.set_to(PBSelection.Kind.UNIT, unit_id)
	_sync_deployed()
	_refresh_panels()


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


## 键盘：空格暂停，1/2/3 倍速，R 重开，F10 换窗口大小，F11 全屏（[PBDisplay]）。
##
## 直接读 keycode 而不是走 Input Map —— 那段序列化格式跨版本很脆，
## 项目规范要求用编辑器加而不是手写进 project.godot；操作方案定了再进 Input Map。
func _unhandled_input(event: InputEvent) -> void:
	# 战场上的点击（§02 的战斗中操作，M4-e）与拖动摆位（M4-f）。
	# **不看 [member _paused]** —— §02 原话是「暂停的时候也能点击」。
	# 准备阶段的战场归拖放协议管（M5-4，见 [PBDropArea]）。
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			# **`make_input_local` 不是多此一举**（M6-d）。`click.position` 是
			# **窗口像素**，而战场那套判定全在 640×360 这个画布坐标系里 ——
			# `stretch/mode` 从 `viewport` 换成 `canvas_items` 之后两者差一个
			# 缩放倍数，1080p 下点哪儿都偏三倍，而所有数字看起来都很正常。
			# 走本地坐标则**两种模式下都对**，因为它问的是引擎当前的变换。
			_on_field_click((make_input_local(click) as InputEventMouseButton).position)
		# **右键取消**（M5-11）：两步操作的第一步按下去之后，
		# 玩家需要一条不用把手挪回指令卡的退路。`Esc` 是第二条路。
		elif click.button_index == MOUSE_BUTTON_RIGHT and click.pressed:
			if _picker.aim_mode != PBFieldPicker.Aim.OFF:
				_picker.aim_mode = PBFieldPicker.Aim.OFF
				_refresh_battle_panels()
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
		KEY_F10:
			PBDisplay.cycle_window()
		KEY_F11:
			PBDisplay.toggle_fullscreen()
		KEY_A:
			auto_play = not auto_play
			# 面板只在「手动 + 准备阶段」出现。切换时立刻反映，
			# 否则玩家关了自动却要等下一波才看得到商店。
			_set_panels_visible(_phase == Phase.PREPARE and not auto_play and not _run_over)
			# **`Q` 没了**（M5-7）：接不接现在等于「任务栏里站着几个人」，只能靠拖。
		KEY_B:
			# 带人方式：按战力，还是按羁绊（§09）。M2-d。
			#
			# **加这个键是因为不加的话羁绊那几行是不可操作的信息** ——
			# 面板会说「还差 1 人就能进满档，+18%」而玩家一个按钮都没有，
			# 看得见动不了的 UI 只会让人以为自己漏掉了什么操作。
			if _phase == Phase.PREPARE and not auto_play:
				_toggle_field_policy()
		KEY_ESCAPE:
			_on_escape()
		KEY_ENTER:
			if _phase == Phase.PREPARE:
				_finish_prepare()


## **`Esc` 一下只收一层：菜单 → 说明卡 → 弹层 → 瞄准 → 选中 → 呼出菜单。**
## 一下做几件事会让人分不清刚才关掉的是哪一个。
##
## 说明卡排在弹层前面（M5-7）—— 它盖在最上面，手上有东西挡着的时候，
## 那一下的意思一定是「先把它收掉」。菜单则排在**两头**：摊开时第一个收，
## 没有东西可收时才呼出（M6-d）。顺序只在这一处裁决，
## [PBSystemMenu] 自己不听 `Esc` —— 它在 `HUD` 里会比这里先收到事件，
## 那样「按 Esc 关掉了什么」就由节点顺序偷偷决定了。
func _on_escape() -> void:
	if _menu.visible:
		if not _menu.back():
			_close_menu()
		return
	if _tip.is_open():
		_tip.hide_card()
		return
	if _close_modal():
		return
	# 战斗中还多一层：先退出「正在等你点战场」（M4-e / M5-9 的忍术）。
	if _picker.aim_mode != PBFieldPicker.Aim.OFF:
		_picker.aim_mode = PBFieldPicker.Aim.OFF
		_refresh_panels()
		return
	if _selection.kind != PBSelection.Kind.NONE:
		_selection.set_to(PBSelection.Kind.NONE)
		_refresh_panels()
		return
	_open_menu()


## 摊开功能菜单。**顺手暂停** —— 菜单上第一项写着「继续」，
## 而底下的战斗照跑的话那两个字就是假的；玩家翻设置的这几秒也会挨打。
##
## 记住原来暂停没暂停：他可能是自己按空格停下来看局面，
## 顺手开了菜单 —— 关掉菜单就替他取消暂停的话，那一波会突然动起来。
func _open_menu() -> void:
	_paused_before_menu = _paused
	_paused = true
	_menu.open()


func _close_menu() -> void:
	_menu.close()
	_paused = _paused_before_menu


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
	_quest.reset(_state, _plan)
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
			_open_modal(_offer)
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
	# **手动模式下「接没接」不是开关，是任务栏里站着几个人**（M5-7）：人数不符
	# 就是失败，那几个人照样离场，只是拿不到奖励。判据走那一份 static，
	# 界面写的和结算算的因此不可能分叉。
	var accepted: bool = (
		_strategy.accept_quest(_state, _plan.wave, _plan.quest_grade, _cfg)
		if auto_play
		else PBQuestCard.is_done(_state, _plan)
	)
	PBRunSim.lock_plan(_state, _plan, _strategy.deploy(_state, _plan.wave, _cfg), accepted, _cfg)
	_battle = PBBattleSim.new(
		_plan.wave, _plan.dps, _state.def_reduction(_cfg), _cfg, _plan.attackers
	)
	_frame_counter = 0
	_phase = Phase.BATTLE
	_picker.aim_mode = PBFieldPicker.Aim.OFF
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
## **M4-e 起指令卡与信息栏在战斗中也留着**（§02 要「打起来之后照样点得到
## 忍者、照样能指定他打谁」），但内容整个换掉（[method PBCommandCard.set_battle]）
## —— 升级、装备、派任务都是准备阶段的决策。
func _set_panels_visible(shown: bool) -> void:
	_command.visible = shown or _phase == Phase.BATTLE
	_unit_info.visible = _command.visible
	_slots.visible = shown
	_quest.visible = shown
	# 仓库常驻，但只在准备阶段：战斗中改名单是没有意义的操作（M5-3）。
	# 战场那块收件人同理 —— 打起来之后不该还能把人拖来拖去（M5-4）。
	_bay.visible = shown
	_ground.visible = shown
	if not shown:
		# 弹层全部收起来。战斗中留着一层的话它会盖满整个画面，
		# 而它上面的按钮此刻一个都不该生效。
		for modal: PBModal in [_offer, _beasts]:
			modal.close()
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
	var aware: bool = _strategy.field_policy == PBStrategy.Field.BOND_AWARE
	_unit_info.refresh(_selection, _state, _cfg, _plan.wave, deployed, aware)
	_slots.refresh(_selection, _state)
	_quest.refresh(_selection, _state, _plan, away)
	# 弹层只在摊着的时候重画 —— 关着的那一层每次都算一遍纯属浪费。
	if _offer.visible:
		_offer.refresh(_state, _cfg, _plan.wave)
	_parts.refresh(_state, _cfg)
	_gear.refresh(_selection.unit_of(_state), _state, _cfg, deployed)
	_gear.visible = _selection.kind == PBSelection.Kind.UNIT
	# 仓库是常驻面板（M5-3），不在「开着才画」那一档里。
	_bay.refresh(_selection, _state, _cfg, _plan.wave, deployed, away)
	if _beasts.visible:
		_beasts.refresh(_state, _cfg)


## 战斗中的那两块（§02，M4-e）。**只在选中变了之后调** ——
## 每帧重排整块文字要跑一次装备分配，一秒六十次太贵，而那几行字
## 在一波之内根本不变。会变的血蓝条走 [method PBUnitInfo.show_live]。
func _refresh_battle_panels() -> void:
	var live := _selected_attacker()
	_command.set_battle(
		true,
		_picker.aim_mode,
		live.forced_target if live != null else -1,
		_battle != null and _battle.can_cast(live)
	)
	_command.refresh(_selection, _state, _cfg, _plan, _plan.deployed)
	_unit_info.refresh(_selection, _state, _cfg, _plan.wave, _plan.deployed)


## 选中那个忍者这一波在场上的样子。反查在 [PBFieldPicker] 里。
func _selected_attacker() -> PBAttacker:
	if _selection.kind != PBSelection.Kind.UNIT:
		return null
	return _picker.attacker_of(_battle, _plan.deployed, _selection.unit_id)


## 玩家在战场上点了一下（§02 的战斗中操作，M4-e；准备阶段那一支是 M5-7）。
##
## **暂停时照样有效** —— `_unhandled_input` 不受 [member _paused] 影响，
## 而 §02 原话就是「暂停的时候也能点击」。
##
## **准备阶段也要点得中**（M5-7）。在那之前这个函数一上来就
## `if _phase != Phase.PREPARE` 拦掉了，而在场的人已经不在仓库里
## （一个人只在一处）—— 于是**他们根本没有选中入口**，指令卡和信息栏全失效。
func _on_field_click(at: Vector2) -> void:
	if _phase == Phase.PREPARE:
		# 准备阶段没有 [PBBattleSim]，站位来自 [PBFormationRules]。
		# 点空地取消选中 —— 和战斗中那一支同一条规矩。
		var who := _unit_on_field_at(at)
		if who == &"":
			_selection.set_to(PBSelection.Kind.NONE)
			_refresh_panels()
		else:
			_select(PBSelection.Kind.UNIT, who)
		return
	if _battle == null:
		return
	var field := _field()
	var spot := PBLayout.to_field(at, field)
	# 判定半径是**屏幕像素**（M6-a），见 [method PBLayout.screen_gap]。
	var pick: float = PICK_RADIUS_PX
	# 正在指定目标：只认敌人。点空地就当取消 —— 让「按错了」有一条退路。
	if _picker.aim_mode == PBFieldPicker.Aim.TARGET:
		_picker.aim(
			_battle, _selected_attacker(), _picker.enemy_at(_battle, spot, field, pick)
		)
		_picker.aim_mode = PBFieldPicker.Aim.OFF
		_refresh_battle_panels()
		return
	# 正在选忍术落点（M5-9）：战场上**哪个点都算**，不用点中谁 ——
	# 大招打的是一个圆，「落在哪」本来就是玩家要挑的那件事。
	if _picker.aim_mode == PBFieldPicker.Aim.ULTIMATE:
		_battle.cast_ultimate(_selected_attacker(), spot)
		_picker.aim_mode = PBFieldPicker.Aim.OFF
		_refresh_battle_panels()
		return
	var ally := _picker.ally_at(_battle, spot, field, pick)
	if ally != null and ally.slot < _plan.deployed.size():
		_select(PBSelection.Kind.UNIT, _plan.deployed[ally.slot].key())
		return
	# 点空地取消选中。战场上没有别的「空白处」，不给这条路的话
	# 选中框会一直挂在最后点过的那个人身上。
	_selection.set_to(PBSelection.Kind.NONE)
	_refresh_battle_panels()


## 拖动中，鼠标正停在战场上（M5-4）。**每一帧都写进状态，不是松手才写** ——
## 松手才写的话方块不会跟着走，玩家会以为没拖起来（M4-f 的原话）。
## 只有本来就在场上的人才跟着走：仓库那张卡还没上场，提前画上去
## 等于替玩家做完了他还没做的决定。
func _on_drag_over_field(from_zone: StringName, unit_id: StringName, at: Vector2) -> void:
	if from_zone != PBUnitTile.ZONE_FIELD or _phase != Phase.PREPARE:
		return
	var unit := _state.roster.get(unit_id, null) as PBUnit
	PBFormationRules.place(_state, unit, PBLayout.to_field(at, _field()), _cfg)
	_sync_deployed()


## 屏幕上 [param at] 那个点站着哪个上场的忍者。空 = 没人。
## [PBDropArea] 拿它决定「按下去能不能拖起一个人」（M5-4）。
func _unit_on_field_at(at: Vector2) -> StringName:
	var units := _fighting_now(_dispatch_preview())
	var field := _field()
	var hit: int = PBFieldPicker.unit_at(
		units, _state.formation, _cfg, PBLayout.to_field(at, field), field, PICK_RADIUS_PX
	)
	return units[hit].key() if hit >= 0 else &""


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


## 手感那几样的状态一起清掉。**必须是一起** —— 只清一半的话，
## 新的一波会带着上一波的血量快照或者半屏没飘完的旧数字。
func _clear_feedback() -> void:
	_feel.reset()
	_floats.clear()
	_telegraph.clear()
	_shots.clear()
	_hitstop_frames = 0


## 把前面的波次用解析式模型瞬间跑完，不渲染。调试用，见 [member start_wave]。
##
## 走的是 `plan_wave` / `settle_wave` 这条正路，所以快进出来的状态
## 和正常打过去是一致的。**快进途中就死了要如实标成「本局结束」** ——
## 早先这里 break 完接着渲染，画面上是一个基地血为负的第 N 波，
## 看起来像「快进到了」，实际是「打不过去」。
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
	# 动画跟着倍速走，暂停和顿帧一起冻住（M6-b）。**不跟的话暂停时一群人
	# 还在原地跑步** —— §02 特意把暂停当成一个正经的操作时机，那一刻画面
	# 必须是静止的局面；顿帧同理，底下的人接着跑就没有「这一下打死了」。
	var beat: float = 0.0 if _paused or _hitstop_frames > 0 else float(_speed)
	_allies.set_anim_speed(beat)
	_pool.set_anim_speed(beat)
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
		# 敌人那一份只用来查「他要打的那个在哪」（朝向，M6-b）。
		_allies.sync_allies(_battle.attackers(), _plan.deployed, field, _battle.enemies())
		# §02 的第三层视觉编码：克得住的敌人加一圈亮边。
		# 这是玩家在战斗中最需要的即时信息 —— 原版要点开技能说明才看得到。
		var counterable: bool = _state.can_counter(_plan.wave.element)
		_pool.sync_enemies(_battle.enemies(), _battle.current_tick(), field, counterable)
		_sync_selected(field)
	_sync_base()
	_sync_info()
	_sync_preview()


## 下一波预告 + 克制覆盖度 + 现在能按哪些键。文案在 [PBPreviewLabel]。
##
## **M5-6 起不用再藏这一行了**：抽屉那一版只盖住中间那一截，行首几个字
## 会从左边的缝里漏出来；模态的遮罩盖满全屏（[PBModal]）。
func _sync_preview() -> void:
	if _run_over:
		_preview.text = ""
		return
	_preview.text = PBTopBarText.preview(
		_state, _cfg, _rng, _phase == Phase.PREPARE, auto_play
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
		PBLayout.to_screen(spots[live], field),
		_cfg.reach_distance(units[live].character.reach_tier()) * PBLayout.px_per_unit(field)
	)


## 选中那个忍者的射程圈与实时血蓝（§02，M4-e）。每渲染帧一次。
##
## 这两样**必须每帧刷**：圈跟着他跑（他会前压、会贴身），
## 血蓝每 tick 都在变。而指令卡那一整块文字不用（[method _refresh_battle_panels]）。
func _sync_selected(field: Vector2) -> void:
	var live := _selected_attacker()
	# 「他要打谁」「正在等你点哪儿」那三条虚线（M5-11）。见 [PBAimLines]。
	# **暂停时绿线画全场**（M5-12）：那正是用来读局面的一刻。
	_aim.sync(
		# 鼠标同样走画布坐标，不走窗口像素 —— 见 [method _unhandled_input]。
		_battle, field, live, _picker.aim_mode, get_global_mouse_position(), _paused
	)
	if live == null:
		_allies.show_range(Vector2.ZERO, 0.0)
		return
	_allies.show_range(
		PBLayout.to_screen(live.pos, field), live.reach * PBLayout.px_per_unit(field)
	)
	_unit_info.show_live(live)
	# 忍术那一格的亮/灰会在战斗中途自己变（冷却转好、蓝攒够，M5-9），
	# 而指令卡整块只在选中变了之后才重排。**只在真的翻面那一帧重排** ——
	# 每帧重排要跑一次装备分配，一秒六十次太贵（见 [method _refresh_battle_panels]）。
	var ready: bool = _battle != null and _battle.can_cast(live)
	if ready != _cast_ready:
		_cast_ready = ready
		_refresh_battle_panels()


## 战场的尺寸，`Vector2(长, 高)`。渲染层全部坐标换算都收这一个参数。
##
## 现造而不是缓存：`_cfg` 是可变的（调试开关会改它），
## 缓存一份的话改了配置画面不跟着动，而那种不同步不报错。
func _field() -> Vector2:
	return Vector2(_cfg.field_length, _cfg.field_height)


## 基地血量画成一个高度随血量变化的条，长在战场那条道的左端。
## 下沿是**算出来的**（[method PBLayout.lane_bottom]）不是手写的常量 ——
## 手写那一版穿帮过一次，见 [method PBLayout.apply_to]。
func _sync_base() -> void:
	var ratio: float = clampf(_state.base_hp / _cfg.base_hp, 0.0, 1.0)
	var bottom: float = PBLayout.lane_bottom(_field())
	# 满血时和地面带一样高（M6-a 起那是 GROUND_TOP，不是框的上沿）。
	_base_rect.size.y = lerpf(4.0, bottom - PBLayout.GROUND_TOP, ratio)
	_base_rect.position.y = bottom - _base_rect.size.y
	_base_rect.color = PBSkin.GOOD.lerp(PBSkin.BAD, 1.0 - ratio)


## 名单变了之后要跟着动的那两块：C/D 两个形象，和任务栏那 4 个槽。
##
## **上场名单本身不在这里** —— 准备阶段它直接画在战场上（[method _sync_placed]）。
## 战斗阶段显示锁定的名单，准备阶段显示「现在开打的话会是谁」的预览：
## [method PBStrategy.deploy] 只读不改状态，拿来预览是安全的。
func _sync_deployed() -> void:
	if not _quest.visible:
		return
	_slots.refresh(_selection, _state)
	_quest.refresh(_selection, _state, _plan, _dispatch_preview())


func _sync_info() -> void:
	if _run_over:
		_info.text = "本局结束　卡在第 %d 波　按 R 重开" % _state.wave_index
		return
	# **准备阶段传 `null` 而不是一份空战报**：那一行该说「在等什么」，
	# 而不是报一份 0 杀 0 漏的战果（§01 说准备阶段不限时）。见 [PBTopBarText]。
	var out: PBCombatOutcome = null if _phase == Phase.PREPARE else _battle.result()
	_info.text = PBTopBarText.status(_state, _plan, out, _paused, _speed)
