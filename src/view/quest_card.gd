class_name PBQuestCard
extends Control
## 准备阶段的任务卡。M1-d。
##
## §06 的验收原话是「**派了羁绊掉几档，准备阶段能一眼看出**」。
## 这一层就是那句话的兑现。
##
## ## 为什么它是 M1 里唯一真正的决策
##
## 阵容不是（[PBRosterPanel] 里说了为什么：按有效战力取前 N 严格最优）。
## 花钱只是排序，买不买得起是唯一的约束。
## **只有任务是两难**：接了这一波变弱，不接这一辈子变穷。
##
## 而且它在数值上是量得出来的 —— M-1 扫描下 `dispatch_never` 与
## `dispatch_always` 差 13.4% 的波次，任务奖励占总收入的 46%。
##
## ## 为什么不把「值不值」算成一个数
##
## 试过的写法是「奖励 402 金能在商店买 +8.2% 战力，派遣要付 −10.5%，所以亏」。
## **那个算法是错的**，而且错得不显眼：金币买到的战力是**永久**的，
## 派遣的代价**只在这一波**。两个数单位不同，相减没有意义。
##
## 所以卡面把两边并排摆着，并且把「这一波的代价」翻译成玩家真正在乎的东西 ——
## **离打不动还差多远**（[method PBValuation.leak_threshold_dps]）。
##
## 那个口径也是量出来的，不是拍的：先写的是「基地会掉多少血」，
## 实测下来两个分支在能被玩到的每一波都是同一个 0 ——
## 战斗是个单服务器排队，那个量在悬崖前没有分辨率。详见上面那个方法的说明。

## 玩家切换了接/不接。
signal quest_toggled(accepted: bool)

## 顶栏：左边是信息，右边是那个按钮。夹在 HUD 的 Info 行（y≈5）
## 与两个准备面板（y=96）之间。
const PANEL_RECT := Rect2(46.0, 28.0, 548.0, 62.0)
const BUTTON_SIZE := Vector2(100.0, 26.0)
const FONT_SIZE: int = 9

var _accepted: bool = false

var _head: Label
var _bond: Label
var _outcome: Label
var _toggle: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.07, 0.10, 0.92)
	backdrop.position = PANEL_RECT.position
	backdrop.size = PANEL_RECT.size
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var width: float = PANEL_RECT.size.x - BUTTON_SIZE.x - 24.0
	_head = _add_label(PANEL_RECT.position + Vector2(8.0, 4.0), width)
	_bond = _add_label(PANEL_RECT.position + Vector2(8.0, 22.0), width)
	_outcome = _add_label(PANEL_RECT.position + Vector2(8.0, 40.0), width)

	_toggle = Button.new()
	_toggle.position = (
		PANEL_RECT.position + Vector2(PANEL_RECT.size.x - BUTTON_SIZE.x - 8.0, 18.0)
	)
	_toggle.size = BUTTON_SIZE
	_toggle.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	_toggle.pressed.connect(_on_pressed)
	add_child(_toggle)


## 玩家这一波接没接。[PBBattleView] 在 `lock_plan` 时取这个值。
func accepted() -> bool:
	return _accepted


## 新的一波：默认不接，重新算一遍卡面。
##
## 默认不接而不是默认接，是因为**没决定就是没决定** —— 默认接的话，
## 一个没注意到这张卡的玩家会莫名其妙在 BOSS 波掉羁绊，
## 而他连自己付了代价都不知道。
func reset(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> void:
	_accepted = false
	refresh(state, cfg, plan)


## 按当前状态刷新。**只在状态变了之后调** —— 里面要跑两遍
## [method PBValuation.mean_dps] 和两遍战斗解析，不适合每帧跑。
func refresh(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> void:
	var grade: int = plan.quest_grade
	var need: int = PBEconomyRules.quest_cost_units(grade)
	var spare: int = state.standby_available(cfg)
	var reward: int = PBEconomyRules.quest_reward(grade, plan.wave.index)

	# 人不够就派不出去。这时候卡面要说清是「人不够」而不是「不划算」，
	# 否则玩家会去调阵容找一个根本不存在的原因。
	if need > spare:
		_accepted = false
		_head.text = "本波任务　%s 级　奖励 %d 金　需派 %d 人" % [_grade_name(grade), reward, need]
		_bond.text = "待命台只有 %d 人，派不出去 —— 先去左边多抽几张卡。" % spare
		_outcome.text = ""
		_toggle.text = "派不出"
		_toggle.disabled = true
		return

	_toggle.disabled = false
	_toggle.text = "接下任务" if not _accepted else "已接 · 取消"
	_head.text = (
		"本波任务　%s 级　奖励 %d 金　需派 %d 人（待命台 %d 人可派）　Q 键切换" % [_grade_name(grade), reward, need, spare]
	)
	_bond.text = _bond_text(state, cfg, need)
	_outcome.text = _outcome_text(state, cfg, plan, need)


## §06 那句「派了羁绊掉几档」。
func _bond_text(state: PBRunState, cfg: PBSimConfig, need: int) -> String:
	var size: int = state.roster.size()
	var before: int = state.bonded_count_for(size, 0, cfg)
	var after: int = state.bonded_count_for(size, need, cfg)
	# 卡池够大时被派走的人本来就在羁绊上限之外 —— 这一波派遣是白捡的钱。
	# 这一格是整张卡里最值钱的信息，值得单独说一句。
	if after >= before:
		return "羁绊 %d 档不变（人数已过上限 %d，派谁都不掉）　战力不变" % [before, cfg.bond_unit_cap]
	var base: float = PBValuation.mean_dps(state, cfg)
	var loss: float = PBValuation.dispatch_loss(state, cfg, base, need)
	return (
		"派了：羁绊 %d → %d 档（掉 %d 档，×%.2f → ×%.2f）　战力 −%.1f%%"
		% [
			before,
			after,
			before - after,
			state.bond_mult_for(size, cfg),
			1.0 + cfg.bond_power_per_unit * float(after),
			loss * 100.0,
		]
	)


## 把「战力 −x%」翻译成玩家真正在乎的东西：**这一波离打不动还差多远。**
##
## 第一版写的是「不接 基地 −0 / 接了 基地 −128」，实测下来那一行在
## 几乎每一波都读作两个相同的 0（详见 [method PBValuation.leak_threshold_dps]）——
## 战斗是个单服务器排队，基地伤害在悬崖前恒为 0、悬崖后一步到底。
##
## 富余倍数有分辨率。而且**它正是这个游戏最缺的一格信息**：
## 不给的话整局读起来是「好好好、死」，玩家永远不知道自己什么时候该转经济。
func _outcome_text(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan, need: int) -> String:
	if state.roster.is_empty():
		return "还没有人上场 —— 先去左边抽卡。"
	# 名单还没锁（`lock_plan` 要等玩家点开打），所以按「现在开打会派谁」预览一份。
	var units: Array[PBUnit] = PBValuation.deployed_for(state, plan.wave.element, cfg)
	var cliff: float = PBValuation.leak_threshold_dps(plan.wave, state.def_reduction(cfg), cfg)
	var kept: float = PBValuation.dps_if_dispatched(state, plan.wave, units, 0, cfg)
	var sent: float = PBValuation.dps_if_dispatched(state, plan.wave, units, need, cfg)
	return (
		"本波打空要 %.0f DPS　　不接 %.0f（%s）　　接了 %.0f（%s）"
		% [cliff, kept, _margin(kept, cliff), sent, _margin(sent, cliff)]
	)


## 富余倍数。跌破 1 倍就是要漏怪了，这时候必须说得比一个数字更重。
##
## 两位小数不是随手定的：后期两个分支挨得很近（实测第 40 波是 1.61× 对 1.55×），
## 只留一位会把它们四舍五入成同一个数 —— 而那个差值**正是这张卡要卖的东西**。
func _margin(dps: float, cliff: float) -> String:
	if cliff <= 0.0:
		return "富余充足"
	var ratio: float = dps / cliff
	if ratio < 1.0:
		return "不够！会漏"
	return "富余 %.2f×" % ratio


## 切换接/不接。按钮和 Q 键走同一条路 —— 两条路各写一份迟早分叉。
## 派不出去（待命台人不够）时什么都不做。
func toggle() -> void:
	if _toggle.disabled:
		return
	_accepted = not _accepted
	quest_toggled.emit(_accepted)


func _on_pressed() -> void:
	toggle()


func _grade_name(grade: int) -> String:
	return String(PBEconomyRules.QUEST_GRADES[grade])


func _add_label(at: Vector2, width: float) -> Label:
	var label := Label.new()
	label.position = at
	label.size = Vector2(width, 16.0)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(label)
	return label
