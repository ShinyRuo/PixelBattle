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

## 波次之间停多少个物理帧。§01 说结算 2–4 秒，这里取 1 秒够看清结果。
const WAVE_GAP_FRAMES: int = 60

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

## 波间停顿的剩余帧数。
var _gap_frames: int = 0

var _deployed_nodes: Array[Polygon2D] = []

# @onready 必须排在普通成员之后 —— .gdlintrc 的 class-definitions-order
# 定死了「prvvars 在 onreadyprvvars 之前」。这一组的赋值时机也在 _ready() 之前，
# 所以 _init() 里访问不到它们。
@onready var _pool: PBEnemyPool = $Enemies
@onready var _deployed_root: Node2D = $Deployed
@onready var _base_rect: ColorRect = $Base
@onready var _info: Label = $HUD/Info
@onready var _preview: Label = $HUD/Preview


func _ready() -> void:
	_cfg = PBSimConfig.new()
	# 画面必须逐 tick —— 排队模型算完就没了，没有中间状态可画。
	_cfg.use_tick_battle = true
	_frames_per_tick = maxi(Engine.physics_ticks_per_second / _cfg.tick_rate, 1)

	_rng = PBRngStreams.new(_resolve_seed())
	_state = PBRunSim.new_state(_cfg)
	_strategy = PBStratBalanced.new()

	_build_deployed_nodes()
	_fast_forward_to(start_wave)
	_start_wave()


func _physics_process(_delta: float) -> void:
	if _run_over:
		return
	if _gap_frames > 0:
		_gap_frames -= 1
		if _gap_frames == 0:
			_start_wave()
		return
	if not _paused:
		_advance_logic()
	_sync_visuals()


## 键盘：空格暂停，1/2/3 倍速，R 重开。
##
## 直接读 keycode 而不是走 Input Map —— 那段序列化格式跨版本很脆，
## 项目规范要求用编辑器加而不是手写进 project.godot。M0 阶段的调试键
## 还没定型，等操作方案定了再进 Input Map。
func _unhandled_input(event: InputEvent) -> void:
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


## 推进逻辑。倍速在这里体现为「一次多走几个 tick」，tick 本身的时长不变。
func _advance_logic() -> void:
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


## 准备下一波。走的是批量模拟的同一个入口，保证两边 RNG 次序一致。
func _start_wave() -> void:
	_plan = PBRunSim.plan_wave(_state, _strategy, _cfg, _rng)
	if debug_enemy_count > 0:
		# 纯视觉覆盖，见 debug_enemy_count 的说明。钳在 COUNT_CAP 内，
		# 因为「同屏不超过 COUNT_CAP」本身就是 §04 的验收项。
		_plan.wave.count = mini(debug_enemy_count, _cfg.count_cap)
	_battle = PBBattleSim.new(_plan.wave, _plan.dps, _state.def_reduction(_cfg), _cfg)
	_frame_counter = 0
	_sync_deployed()
	_sync_visuals()


func _end_wave() -> void:
	PBRunSim.settle_wave(_state, _plan, _battle.result(), _cfg, _rng)
	if _state.base_hp <= 0.0:
		_run_over = true
		_sync_visuals()
		return
	_state.wave_index += 1
	_gap_frames = WAVE_GAP_FRAMES


func _restart() -> void:
	_run_over = false
	_paused = false
	_gap_frames = 0
	_state = PBRunSim.new_state(_cfg)
	_strategy = PBStratBalanced.new()
	_rng = PBRngStreams.new(_resolve_seed())
	_start_wave()


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
	var quick := _cfg.clone()
	quick.use_tick_battle = false
	while _state.wave_index < target_wave:
		var plan := PBRunSim.plan_wave(_state, _strategy, quick, _rng)
		var outcome := PBCombatRules.resolve(
			plan.wave, plan.dps, _state.def_reduction(quick), quick
		)
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
	# §02 的第三层视觉编码：克得住的敌人加一圈亮边。
	# 这是玩家在战斗中最需要的即时信息 —— 原版要点开技能说明才看得到。
	var counterable: bool = _state.can_counter(_plan.wave.element)
	_pool.sync_enemies(_battle.enemies(), _battle.current_tick(), _cfg.field_length, counterable)
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
	var next := PBRunSim.preview_wave(_state.wave_index + 1, _cfg, _rng)
	var missing := _state.missing_counters()
	var covered: int = PBWaveRules.WAVE_ELEMENTS.size() - missing.size()

	var gap_text: String = "已齐"
	if not missing.is_empty():
		var names := PackedStringArray()
		for element: int in missing:
			names.append(_element_name(element as PBElement.Type))
		gap_text = "缺 %s" % "".join(names)

	_preview.text = (
		"下一波：%s %s　　克制覆盖 %d/5（%s）　　%s"
		% [
			_element_name(next.element),
			_shape_name(next.shape),
			covered,
			gap_text,
			"空格暂停　1/2/3 倍速　R 重开",
		]
	)


## 基地血量画成一个高度随血量变化的条。
func _sync_base() -> void:
	var ratio: float = clampf(_state.base_hp / _cfg.base_hp, 0.0, 1.0)
	_base_rect.size.y = lerpf(4.0, 150.0, ratio)
	_base_rect.position.y = 300.0 - _base_rect.size.y
	_base_rect.color = Color(0.35, 0.75, 0.45).lerp(Color(0.85, 0.25, 0.25), 1.0 - ratio)


## 上场名单画成基地旁边的一列方块，颜色按属性。
##
## 这一列每波会换色 —— 那正是 §03「每波换上克制系」在画面上的样子。
## 换人如果没发生，这一列的颜色就不会变，一眼能看出来。
func _sync_deployed() -> void:
	for i: int in _deployed_nodes.size():
		var node: Polygon2D = _deployed_nodes[i]
		if i >= _plan.deployed.size():
			node.visible = false
			continue
		var unit: PBUnit = _plan.deployed[i]
		node.visible = true
		node.color = PBEnemyPool.ELEMENT_COLORS.get(unit.element, Color.WHITE)


func _build_deployed_nodes() -> void:
	# 按出战席上限建满，之后只改 visible 和颜色。
	_deployed_nodes.resize(_cfg.deploy_slots_max)
	for i: int in _cfg.deploy_slots_max:
		var node := Polygon2D.new()
		node.polygon = PackedVector2Array(
			[Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)]
		)
		node.position = Vector2(30.0, 110.0 + float(i) * 18.0)
		node.visible = false
		_deployed_root.add_child(node)
		_deployed_nodes[i] = node


func _sync_info() -> void:
	if _run_over:
		_info.text = "本局结束　卡在第 %d 波　按 R 重开" % _state.wave_index
		return
	var wave: PBWave = _plan.wave
	var out: PBCombatOutcome = _battle.result()
	_info.text = (
		"第 %d 波　%s　%s　　敌 %d/%d　漏 %d　　基地 %d　金 %d　　%.1fs　%s"
		% [
			wave.index,
			_element_name(wave.element),
			_shape_name(wave.shape),
			out.kills,
			wave.count,
			out.leaked,
			int(_state.base_hp),
			_state.gold,
			out.battle_seconds,
			"暂停" if _paused else "%d 倍速" % _speed,
		]
	)


func _element_name(element: PBElement.Type) -> String:
	match element:
		PBElement.Type.FIRE:
			return "火"
		PBElement.Type.WIND:
			return "风"
		PBElement.Type.THUNDER:
			return "雷"
		PBElement.Type.EARTH:
			return "土"
		PBElement.Type.WATER:
			return "水"
		_:
			return "物理"


func _shape_name(shape: PBWave.Shape) -> String:
	match shape:
		PBWave.Shape.SWARM:
			return "潮水"
		PBWave.Shape.ELITE:
			return "精英"
		PBWave.Shape.BOSS:
			return "BOSS"
		PBWave.Shape.MEGA_BOSS:
			return "大BOSS"
		_:
			return "常规"
