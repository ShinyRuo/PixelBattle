class_name PBQuestCard
extends Control
## E 区：**任务栏** —— 本波任务 + 4 个出任务的忍者槽。M1-d；M5-6 收进左侧一列。
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
## 所以说明卡把两边并排摆着：不接多少 DPS、接了多少 DPS，让玩家自己比。
##
## ## M5-6：三行散文搬进了 [PBTooltip]
##
## 这块面板从 548 像素宽掉到 100（[constant PBLayout.E_QUEST]），
## 字号 8 下一行只写得下 11 个汉字 —— 而「派了：某小队 3→2 档（羁绊
## ×1.42 → ×1.28）战力 −10.5%」是三十几个。
##
## 所以面板上只留**能立刻行动的那几个数**（几级、多少金、派几人、
## 已挑几个），整句留在点开的说明卡里。和忍具仓库、装备栏同一条规矩，
## 理由也同一条：**格子上写不下，而删掉信息不是选项**。
##
## ## 出任务那 4 个槽从战场上搬了过来
##
## M3.5-e 到 M5-5 期间它们是一排压在战场上的头像
## （`PBLayout.TEMP_DISPATCH_ROW`）—— B 长高之后（M5-2）那里已经
## 没有空地了，而准备阶段的战场上现在站着人、还能拖动摆位。
##
## 排成 **2×2** 不是一横排：格子 30 宽，四个横着要 120，
## 而这一列只有 100，再宽就要吃掉战场的左沿。
##
## ## 「本波打空要 x DPS」为什么删掉了
##
## 那一行（还有挂在它上面的富余倍数）走的是
## [method PBValuation.leak_threshold_dps] —— **它要二分 32 次，
## 每次跑完一整场仗，实测 457 毫秒**，而这张卡在每一次
## [method PBBattleView._refresh_panels] 里都刷新一遍。
## 于是点开仓库、点一个忍者、开关弹层，每一下都要等半秒。
##
## 病灶不是它算得慢，是**准备阶段去算战斗**：那一行要回答的
## 「打不打得动」只有真打起来才知道，而准备阶段每一次点击都要付这个钱。
##
## 悬崖那个量本身没有作废，`src/tools/pressure_curve.gd` 还在用它
## 离线量压力曲线 —— 那里跑一次几百毫秒无所谓，这里不行。

## 玩家切换了接/不接。
signal quest_toggled(accepted: bool)

## 玩家点了出任务那一排里的某个人。
signal slot_picked(kind: PBSelection.Kind, unit_id: StringName)

## 有人把一张卡拖进任务栏了（§02 的拖放三区，M5-4）。
signal card_dropped(from_zone: StringName, unit_id: StringName, to_zone: StringName)

## 玩家点了「详情」，请把整句摊开在 [param anchor] 旁边。
##
## **正文不由这里给**（对比 [PBPartsBay] 的 `tip_requested`）：
## 组一遍要 state / cfg / plan 三样，而本类一样都不持有 ——
## 存一份下来就是第二份真相，而它会停在上一次刷新的局面上，
## 玩家点开详情恰恰是为了看刚才那一下改变了什么。
signal detail_requested(anchor: Rect2)

const PANEL_RECT := PBLayout.E_QUEST
const PAD: float = 4.0
const FONT_SIZE: int = 8

## 派遣人数的上限是 SSS 任务的 4 人（§06 的任务表）。
const SLOT_COUNT: int = 4

## 4 个槽排成 2×2。见类顶部那段。
const SLOT_COLUMNS: int = 2
const SLOT_ORIGIN := Vector2(14.0, 69.0)
const SLOT_PITCH := Vector2(32.0, 36.0)

var _accepted: bool = false

var _head: Label
var _terms: Label
var _need: Label
var _away: Label
var _toggle: Button
var _detail: Button
var _tiles: Array[PBUnitTile] = []
var _mark: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)
	var at: Vector2 = PANEL_RECT.position
	var width: float = PANEL_RECT.size.x - PAD * 2.0

	_head = PBSkin.label(self, at + Vector2(PAD, 2.0), 62.0, PBSkin.FONT_TITLE, PBSkin.TITLE)
	_terms = _add_label(at + Vector2(PAD, 15.0), width)
	_need = _add_label(at + Vector2(PAD, 25.0), width)
	_away = PBSkin.label(self, at + Vector2(PAD, 57.0), width, FONT_SIZE, PBSkin.DIM)

	_detail = _add_button(at + Vector2(width - 20.0, 2.0), Vector2(24.0, 12.0), "详情")
	_detail.pressed.connect(_on_detail)
	_toggle = _add_button(at + Vector2(PAD, 38.0), Vector2(width, 16.0), "接下任务")
	_toggle.pressed.connect(toggle)

	# **整块槽位区都能接**，不只是那些格子：一个人都没派的时候
	# 一个可见格子都没有，而「把人拖过去派任务」正是这时候要成立的那一下。
	# 加在格子之前，好让格子画在它上面。
	var drop := PBDropArea.new()
	drop.cover(
		Rect2(at + Vector2(PAD, 55.0), Vector2(width, PANEL_RECT.size.y - 58.0)),
		PBUnitTile.ZONE_QUEST
	)
	drop.card_dropped.connect(
		func(from: StringName, id: StringName, _spot: Vector2) -> void:
			card_dropped.emit(from, id, PBUnitTile.ZONE_QUEST)
	)
	add_child(drop)

	# 选中框：一块比格子大三像素的实心块，格子盖在它上面（和 [PBRosterBay] 同一套）。
	_mark = ColorRect.new()
	_mark.color = PBSkin.TITLE
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	add_child(_mark)

	# 按上限一次建满，之后只改内容 —— 和敌人池、指令卡同一条规矩（§14）。
	for i: int in SLOT_COUNT:
		_tiles.append(
			_add_tile(
				at
				+ SLOT_ORIGIN
				+ Vector2(
					float(i % SLOT_COLUMNS) * SLOT_PITCH.x,
					float(i / SLOT_COLUMNS) * SLOT_PITCH.y
				)
			)
		)


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
	refresh(PBSelection.new(), state, cfg, plan)


## 按当前状态刷新。**只在状态变了之后调** —— 里面要跑两遍
## [method PBValuation.mean_dps]，约 1 毫秒，不适合每帧跑。
##
## 一次点击就是一次刷新（[method PBBattleView._refresh_panels]），
## 所以这里的每一毫秒都直接变成点击延迟。**别往里加战斗模拟** ——
## 悬崖那一行就是这么把点击拖到半秒的，见类顶部。
##
## [param away] 是「这一波谁去做任务」，由调用方算好传进来 ——
## 它有三种口径，而选哪一种取决于阶段（见 [method PBBattleView._dispatch_preview]）。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	cfg: PBSimConfig,
	plan: PBWavePlan,
	away: Array[PBUnit] = []
) -> void:
	var grade: int = plan.quest_grade
	var need: int = PBEconomyRules.quest_cost_units(grade)
	var spare: int = state.dispatch_available(cfg)

	_head.text = "任务 %s 级" % _grade_name(grade)
	_terms.text = "奖 %d 金" % PBEconomyRules.quest_reward(grade, plan.wave.index)
	_need.text = "需派 %d 人" % need
	_show_slots(selection, plan.wave, away)

	# 人不够就派不出去。这时候面板要说清是「人不够」而不是「不划算」，
	# 否则玩家会去调阵容找一个根本不存在的原因。
	#
	# **门槛口径 M3.5-i 换过一次。** 旧的是 `standby_available`（溢出到板凳上
	# 的那几个），而指令卡的「派去任务」放行的是**在场**的人 —— 两把尺子，
	# 于是会出现「已经挑了 2 个人，卡面还说待命台 0 人派不出去」。
	if need > spare:
		_accepted = false
		_away.text = "场上只有 %d 人" % spare
		_toggle.text = "人不够"
		_toggle.disabled = true
		return

	_toggle.disabled = false
	_toggle.text = "接下任务" if not _accepted else "已接 · 取消"
	if away.is_empty():
		_away.text = "已挑 %d/%d 人" % [state.dispatch_manual.size(), need]


## 说明卡的正文。**面板上写不下的整句全在这里**，见类顶部。
##
## 公开是有意的：`test_quest_card.gd` 断的就是这几句 ——
## 它们才是 §06 那条验收（「派了羁绊掉几档，一眼看出」）的载体，
## 而面板上那几个短句只是它的索引。
func tip_body(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> String:
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	if need > state.dispatch_available(cfg):
		return "场上只有 %d 人，派不出 %d 人 —— 先去仓库多抽几张卡。" % [
			state.dispatch_available(cfg), need
		]
	return "\n".join(
		PackedStringArray(
			[
				_picked_text(state, need),
				_bond_text(state, cfg, need),
				_outcome_text(state, cfg, plan, need),
			]
		)
	)


## 切换接/不接。按钮和 Q 键走同一条路 —— 两条路各写一份迟早分叉。
## 派不出去（场上人不够）时什么都不做。
func toggle() -> void:
	if _toggle.disabled:
		return
	_accepted = not _accepted
	quest_toggled.emit(_accepted)


## 出任务那 4 个槽。**没派人的时候一个都不显示** ——
## 四个空框会让人以为「这里应该放满」，而 §06 的常态是一个都不派。
func _show_slots(selection: PBSelection, wave: PBWave, away: Array[PBUnit]) -> void:
	_mark.visible = false
	for i: int in _tiles.size():
		var tile: PBUnitTile = _tiles[i]
		tile.visible = i < away.size()
		if not tile.visible:
			continue
		tile.set_unit(away[i], wave.element)
		if selection.kind == PBSelection.Kind.DISPATCHED and selection.unit_id == away[i].key():
			_mark.position = tile.position - Vector2(2.0, 2.0)
			_mark.size = PBUnitTile.TILE_SIZE + Vector2(4.0, 4.0)
			_mark.visible = true
			move_child(_mark, 0)
	if not away.is_empty():
		_away.text = "出任务 %d 人" % away.size()


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


## 两个分支各剩多少战力。**两个数都是解析式的队伍 DPS，不跑战斗模拟** ——
## 准备阶段的每一次点击都会走到这里，见类顶部那段。
##
## 只写「接了多少」不够：玩家要的是**差值**，而差值要有个参照物才读得出来。
## 两个数并排摆着，减法交给玩家 —— 替他减成一个百分比的那一版在
## [method _bond_text] 里已经有了，两处口径不同会互相打架。
func _outcome_text(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan, need: int) -> String:
	if state.roster.is_empty():
		return "还没有人上场 —— 先去仓库抽卡。"
	# 名单还没锁（`lock_plan` 要等玩家点开打），所以按「现在开打会派谁」预览一份。
	var units: Array[PBUnit] = PBValuation.deployed_for(state, plan.wave.element, cfg)
	var kept: float = PBValuation.dps_if_dispatched(state, plan.wave, units, 0, cfg)
	var sent: float = PBValuation.dps_if_dispatched(state, plan.wave, units, need, cfg)
	return "本波战力　　不接 %.0f DPS　　接了 %.0f DPS" % [kept, sent]


func _on_detail() -> void:
	detail_requested.emit(PANEL_RECT)


func _grade_name(grade: int) -> String:
	return String(PBEconomyRules.QUEST_GRADES[grade])


func _add_label(at: Vector2, width: float) -> Label:
	return PBSkin.label(self, at, width, FONT_SIZE, PBSkin.TEXT)


func _add_button(at: Vector2, of_size: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = at
	button.size = of_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(button, PBSkin.Tone.PLAIN, FONT_SIZE)
	add_child(button)
	return button


func _add_tile(at: Vector2) -> PBUnitTile:
	var tile := PBUnitTile.new()
	tile.position = at
	tile.visible = false
	tile.zone = PBUnitTile.ZONE_QUEST
	tile.dropped.connect(card_dropped.emit)
	tile.picked.connect(
		func(hit: PBUnitTile) -> void:
			slot_picked.emit(PBSelection.Kind.DISPATCHED, hit.unit.key())
	)
	add_child(tile)
	return tile
