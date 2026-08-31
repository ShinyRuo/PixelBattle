class_name PBQuestCard
extends Control
## 准备阶段的任务卡。M1-d。
##
## §06 的验收原话是「**派了羁绊掉几档，准备阶段能一眼看出**」。
## 这一层就是那句话的兑现。
##
## ## 为什么它是 M1 里唯一真正的决策
##
## 阵容不是（M1 那会儿按有效战力取前 N 严格最优，不构成决策）。
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
const PANEL_RECT := Rect2(46.0, 28.0, 548.0, 56.0)
const BUTTON_SIZE := Vector2(100.0, 24.0)
const FONT_SIZE: int = 9

var _accepted: bool = false

var _head: Label
var _bond: Label
var _outcome: Label
var _toggle: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)

	var width: float = PANEL_RECT.size.x - BUTTON_SIZE.x - 24.0
	_head = _add_label(PANEL_RECT.position + Vector2(8.0, 2.0), width, PBSkin.TITLE)
	_bond = _add_label(PANEL_RECT.position + Vector2(8.0, 20.0), width, PBSkin.TEXT)
	_outcome = _add_label(PANEL_RECT.position + Vector2(8.0, 36.0), width, PBSkin.TEXT)

	_toggle = Button.new()
	_toggle.position = (
		PANEL_RECT.position + Vector2(PANEL_RECT.size.x - BUTTON_SIZE.x - 8.0, 16.0)
	)
	_toggle.size = BUTTON_SIZE
	PBSkin.style_button(_toggle, PBSkin.Tone.PLAIN, FONT_SIZE)
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
	var spare: int = state.dispatch_available(cfg)
	var reward: int = PBEconomyRules.quest_reward(grade, plan.wave.index)

	# 人不够就派不出去。这时候卡面要说清是「人不够」而不是「不划算」，
	# 否则玩家会去调阵容找一个根本不存在的原因。
	#
	# **门槛口径 M3.5-i 换过一次。** 旧的是 `standby_available`（溢出到板凳上
	# 的那几个），而指令卡的「派去任务」放行的是**在场**的人 —— 两把尺子，
	# 于是会出现「已经挑了 2 个人，卡面还说待命台 0 人派不出去」。
	if need > spare:
		_accepted = false
		_head.text = "本波任务　%s 级　奖励 %d 金　需派 %d 人" % [_grade_name(grade), reward, need]
		_bond.text = "场上只有 %d 人，派不出 %d 人 —— 先去左边多抽几张卡。" % [spare, need]
		_outcome.text = ""
		_toggle.text = "派不出"
		_toggle.disabled = true
		return

	_toggle.disabled = false
	_toggle.text = "接下任务" if not _accepted else "已接 · 取消"
	_head.text = (
		"本波任务　%s 级　奖励 %d 金　需派 %d 人　%s　Q 键切换"
		% [_grade_name(grade), reward, need, _picked_text(state, need)]
	)
	_bond.text = _bond_text(state, cfg, need)
	_outcome.text = _outcome_text(state, cfg, plan, need)


## 玩家自己挑了几个人去（§06，M3.5-g）。
##
## **没挑够要说清楚会发生什么**：名单只在人数刚好对上时才算数
## （[member PBRunState.dispatch_manual]），否则整份作废、退回末尾规则。
## 不写的话，挑了一半的玩家会以为自己挑的那个一定会去，
## 而实际上系统按板凳末尾另派了一批 —— 那个落差在结算之后才看得见。
func _picked_text(state: PBRunState, need: int) -> String:
	var chosen: int = state.dispatch_manual.size()
	if chosen == 0:
		return "自动派名单末尾 %d 人（点忍者可以自己挑）" % need
	if chosen < need:
		return "已挑 %d/%d —— 挑不够就整份作废，仍按名单末尾派" % [chosen, need]
	return "已挑 %d/%d 人（自己挑的）" % [chosen, need]


## §06 那句「派了羁绊掉几档」。
##
## ## M2-b 之后这一行重写过一次
##
## 旧版走的是 [method PBRunState.bonded_count_for]，也就是**人头数**：
## 「羁绊 12 档 → 9 档」。那在替身曲线下是对的（一个人就是一档），
## 装上真羁绊表之后就不成立了 —— 档位是每组羁绊各有各的，
## 12 个人可能是「某小队 3 档 + 另一小队 2 档 + 某属性 1 档」。
##
## 而且这个错**不会报错**：卡面照样显示一个像模像样的数字，
## 只是那个数字和游戏里真正生效的东西没有关系。
##
## 现在的写法是把派遣前后的档位表对比一遍，只报**真的掉了的那几组**。
## 玩家要的本来就不是「掉了几档」这个标量，而是「我会失去哪一组」。
func _bond_text(state: PBRunState, cfg: PBSimConfig, need: int) -> String:
	var before: int = state.dispatched
	state.dispatched = 0
	var kept := PBBondRules.active_tiers(state.bonded_units(cfg), cfg.bonds)
	var kept_mult: float = state.bond_mult(cfg)
	state.dispatched = need
	var sent := PBBondRules.active_tiers(state.bonded_units(cfg), cfg.bonds)
	var sent_mult: float = state.bond_mult(cfg)
	state.dispatched = before

	var broken := PackedStringArray()
	for bond: PBBond in cfg.bonds.all():
		var was: int = int(kept.get(bond.id, 0))
		var now: int = int(sent.get(bond.id, 0))
		if now < was:
			broken.append("%s %d→%d 档" % [PBLocale.of_bond(bond), was, now])

	# 被派走的人没在给任何一组羁绊补档时，代价只剩「少一个打手」。
	# **不能再写「战力不变」**：M3.5-i 之前派的是不上场的板凳，那句是对的；
	# 现在派的是在场的人，他这一波真的不打了。
	if broken.is_empty():
		return "派了：没有羁绊会掉档（派的那几个谁都没顶着档位）　但他们这一波不上场"

	var base: float = PBValuation.mean_dps(state, cfg)
	var loss: float = PBValuation.dispatch_loss(state, cfg, base, need)
	return (
		"派了：%s　（羁绊 ×%.2f → ×%.2f）　战力 −%.1f%%"
		% [String("、").join(broken), kept_mult, sent_mult, loss * 100.0]
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
	# 悬崖按这份预览名单的**真实射程结构**量（M3-a）。拿解析式排队模型算的话，
	# 卡面上那句「本波打空要 x DPS」说的是另一套战斗规则里的事，
	# 而玩家会照着它做决定 —— CLAUDE.md 那条「四块面板与比价同源」管的就是这个。
	var preview := PBCombatRules.build_attackers(
		units,
		plan.wave.element,
		state.atk_mult(cfg),
		state.bond_mult(cfg),
		PBCombatRules.unit_multipliers(units, state, cfg),
		cfg,
		PBBeastRules.beast_of(state, cfg),
		state.beast_level,
		0,
		PBBondRules.active_functions(state.bonded_units(cfg), units, cfg.bonds)
	)
	var cliff: float = PBValuation.leak_threshold_dps(
		plan.wave, state.def_reduction(cfg), cfg, preview
	)
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
## 派不出去（场上人不够）时什么都不做。
func toggle() -> void:
	if _toggle.disabled:
		return
	_accepted = not _accepted
	quest_toggled.emit(_accepted)


func _on_pressed() -> void:
	toggle()


func _grade_name(grade: int) -> String:
	return String(PBEconomyRules.QUEST_GRADES[grade])


func _add_label(at: Vector2, width: float, color: Color) -> Label:
	return PBSkin.label(self, at, width, FONT_SIZE, color)
