class_name PBQuestCard
extends Control
## E 区：**任务栏** —— 本波任务 + 4 个出任务的忍者槽。M1-d；M5-6 收进左侧一列。
##
## §06 的验收原话是「**派了羁绊掉几档，准备阶段能一眼看出**」。
## 这一层就是那句话的兑现。
##
## ## M5-7：没有「接下任务」这个按钮了
##
## 接不接**由任务栏里站着几个人直接说出来** —— 拖满就是接，空着就是不接，
## 人数不符就是失败（拿不到奖励，而那几个人照样离场）。
##
## 在那之前有一个开关按钮，于是同一件事有**两把尺子**：按钮说「已接」、
## 栏里却只站着 1 个人。两者对不上时以哪个为准没有答案，
## 而这个项目为这种形状的 bug 付过三次代价（M3.5-i 那三条）。
##
## 四个槽是**固定的**（[constant PBEconomyRules.QUEST_SLOTS]），
## 不随本波要几个人变 —— 槽位跟着需求变的话玩家**塞不进多余的人**，
## 「人数不符」这条判定就只剩「塞不满」一种，塞多了不可能发生。
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

## 任务栏一共几个槽。**固定 4 个**，见类顶部与 [constant PBEconomyRules.QUEST_SLOTS]。
const SLOT_COUNT: int = PBEconomyRules.QUEST_SLOTS

## **4 个槽排成一横排**（M6-k，玩家定的）。
##
## M5-6 排成 2×2 的理由是那时格子是 30 宽的 [constant PBUnitTile.TILE_SIZE]，
## 四个横着要 120 而这一列只有 100。**格子能缩之后那条理由就没了** ——
## 21 见方装得下属性字和稀有度字，而一横排换来的正是这次要让给 C/D 的高度。
const SLOT_SIZE := Vector2(21.0, 24.0)
const SLOT_ORIGIN := Vector2(5.0, 32.0)
const SLOT_PITCH: float = 23.0

var _head: Label
var _terms: Label
var _need: Label
var _away: Label
var _detail: Button
var _tiles: Array[PBUnitTile] = []
var _mark: ColorRect


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	PBSkin.panel(self, PANEL_RECT)
	var at: Vector2 = PANEL_RECT.position
	var width: float = PANEL_RECT.size.x - PAD * 2.0

	# **M6-k 压成三行 + 一排槽**（面板从 142 高掉到 58）。挤掉的是行距，
	# 不是内容：奖励和人数并进一行，判定那一行**一个字都不能省** ——
	# 「人数不符」是一次有代价的失误，它必须在开打**之前**看得见（M5-7）。
	_head = PBSkin.label(self, at + Vector2(PAD, 1.0), 60.0, PBSkin.FONT_TITLE, PBSkin.TITLE)
	# 奖励和人数并成一行，「已派几个」缩到行尾的一个数 ——
	# **那个数本来也不必写得长**：底下那排槽子里站着几个人一眼就数得出来。
	_terms = _add_label(at + Vector2(PAD, 12.0), 48.0)
	_need = _add_label(at + Vector2(width - 34.0, 12.0), 38.0)
	# 右对齐：奖励涨到四位数、派的人从 0 数到 4，左对齐的话这两截会互相挤。
	_need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# 判定行：**这一行就是原来那个按钮**。绿 = 拖满了、红 = 人数不符。
	# **整行留给它，一个字都不省** —— 「人数不符」是一次有代价的失误，
	# 缩成两个字之后玩家读到的只是一个颜色（M5-7 那条的全部意义就在这句话）。
	_away = _add_label(at + Vector2(PAD, 21.0), width)

	_detail = _add_button(at + Vector2(width - 18.0, 1.0), Vector2(22.0, 11.0), "详情")
	_detail.pressed.connect(_on_detail)

	# **整块槽位区都能接**，不只是那些格子：一个人都没派的时候
	# 格子全是空的，而「把人拖过去派任务」正是这时候要成立的那一下。
	# 加在格子之前，好让格子画在它上面。
	var drop := PBDropArea.new()
	drop.cover(
		Rect2(at + Vector2(PAD, 30.0), Vector2(width, PANEL_RECT.size.y - 32.0)),
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
		var tile := _add_tile(at + SLOT_ORIGIN + Vector2(float(i) * SLOT_PITCH, 0.0))
		tile.shrink_to(SLOT_SIZE)
		_tiles.append(tile)


## 这一波的任务算不算完成了。**判据只有一条：任务栏里正好站着要求的人数。**
##
## [PBBattleView] 在 `lock_plan` 时取这个值，[method PBRunSim.settle_wave]
## 拿它决定发不发奖励。栏里那几个人**无论如何都会走**
## （[method PBRunSim.lock_plan]）—— 人数不符的代价就是白白少几个打手。
##
## static 是有意的：判定不该依赖界面有没有刷新过。
## 挂在实例上的话，「面板上写着失败、结算却给了钱」这种分叉迟早出现。
static func is_done(state: PBRunState, plan: PBWavePlan) -> bool:
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	return need > 0 and state.dispatch_manual.size() == need


## 新的一波：重新算一遍卡面。
##
## **不再需要「重置成不接」** —— 接没接现在完全由任务栏里站着谁决定，
## 而那份名单每波结算时由 [method PBRunSim.settle_wave] 清空。
func reset(state: PBRunState, plan: PBWavePlan) -> void:
	refresh(PBSelection.new(), state, plan)


## 按当前状态刷新。**只在状态变了之后调** —— 里面要跑两遍
## [method PBValuation.mean_dps]，约 1 毫秒，不适合每帧跑。
##
## 一次点击就是一次刷新（[method PBBattleView._refresh_panels]），
## 所以这里的每一毫秒都直接变成点击延迟。**别往里加战斗模拟** ——
## 悬崖那一行就是这么把点击拖到半秒的，见类顶部。
##
## [param away] 是「这一波谁去做任务」，由调用方算好传进来 ——
## 战斗中它是**锁定的那一份**（`dispatched_ids`），准备阶段是任务栏里站着的那几个
## （见 [method PBFieldRoster.dispatch_preview]）。
##
## **不收 `cfg`**（M5-7）：判定只看「拖进来几个 vs 本波要几个」，
## 两个数一个在状态里一个在任务表里，配置一样都用不上。
## 留一个用不到的参数会让人以为这里还在查什么表。
func refresh(
	selection: PBSelection,
	state: PBRunState,
	plan: PBWavePlan,
	away: Array[PBUnit] = []
) -> void:
	var grade: int = plan.quest_grade
	var need: int = PBEconomyRules.quest_cost_units(grade)
	var picked: int = state.dispatch_manual.size()

	_head.text = "任务 %s 级" % _grade_name(grade)
	_terms.text = "奖 %d 金" % PBEconomyRules.quest_reward(grade, plan.wave.index)
	_need.text = "需 %d · 已 %d" % [need, picked]
	_show_slots(selection, plan.wave, away)

	# **判定行，也就是原来那个按钮。** 三种状态各有各的颜色，
	# 而三种都要在开打**之前**看得见 —— 「人数不符」是一次有代价的失误
	# （那几个人照样走），把它留到结算才说等于让玩家事后才知道自己错了。
	if picked == 0:
		_away.text = "未派 · 无奖励"
		_away.add_theme_color_override(&"font_color", PBSkin.DIM)
	elif picked == need:
		_away.text = "已派满 · 可完成"
		_away.add_theme_color_override(&"font_color", PBSkin.GOOD)
	else:
		# 人不够也走这一支。**不再单独区分「场上没人可派」** ——
		# 那条旧分支的门槛（`dispatch_available`）和指令卡放行的口径
		# 是两把尺子，M3.5-i 已经为同一形状的 bug 付过一次代价。
		# 现在玩家只需要读一个数：拖进来几个，要几个。
		_away.text = "人数不符 · 失败"
		_away.add_theme_color_override(&"font_color", PBSkin.BAD)


## 说明卡的正文。**面板上写不下的整句全在这里**，见类顶部。
##
## 公开是有意的：`test_quest_card.gd` 断的就是这几句 ——
## 它们才是 §06 那条验收（「派了羁绊掉几档，一眼看出」）的载体，
## 而面板上那几个短句只是它的索引。
func tip_body(state: PBRunState, cfg: PBSimConfig, plan: PBWavePlan) -> String:
	var need: int = PBEconomyRules.quest_cost_units(plan.quest_grade)
	return "\n".join(
		PackedStringArray(
			[
				_picked_text(state, need),
				_bond_text(state, cfg, need),
				_outcome_text(state, cfg, plan, need),
			]
		)
	)


## 出任务那 4 个槽。**四个一直都在，空的画成空框**（M5-7）。
##
## M5-6 那一版只显示派了几个就画几个，理由是「四个空框会让人以为这里
## 应该放满」。判定改成看人数之后那条理由反过来了：**玩家必须先看得见
## 有几个槽、现在占了几个**，否则「人数不符」是一条无处可读的规则。
func _show_slots(selection: PBSelection, wave: PBWave, away: Array[PBUnit]) -> void:
	_mark.visible = false
	for i: int in _tiles.size():
		var tile: PBUnitTile = _tiles[i]
		if i >= away.size():
			tile.clear()
			continue
		tile.set_unit(away[i], wave.element)
		if selection.kind == PBSelection.Kind.DISPATCHED and selection.unit_id == away[i].key():
			_mark.position = tile.position - Vector2(2.0, 2.0)
			_mark.size = tile.size + Vector2(4.0, 4.0)
			_mark.visible = true
			move_child(_mark, 0)


## 玩家自己挑了几个人去（§06，M3.5-g）。
##
## **人数不符要说清楚会发生什么**：那几个人照样离场
## （[method PBRunSim.lock_plan]），只是拿不到奖励。不写的话，
## 拖了一半的玩家会以为「反正没接成，他们还在场上」——
## 而那个落差要到战斗开始才看得见。
func _picked_text(state: PBRunState, need: int) -> String:
	var chosen: int = state.dispatch_manual.size()
	if chosen == 0:
		return "任务栏空着 —— 这一波不接，没有奖励也没有代价。"
	if chosen == need:
		return "已派 %d/%d 人，打完这一波就能领奖励。" % [chosen, need]
	return "已派 %d 人，本波要 %d —— 人数不符，任务失败：他们照样离场，但一分钱拿不到。" % [
		chosen, need
	]


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


## **上下内边距要清掉**（M6-k）。[method PBSkin.style_button] 的
## [StyleBoxFlat] 各留 2 像素内边距，于是一个写着 11 高的按钮实际有 15 高 ——
## 面板压到 58 之后，那多出来的 4 像素正好盖住下一行的「已 N」。
##
## 和 [PBActorLab] 那次是同一个坑，那边的解法是把行距放大；
## 这里没有行距可放，所以改成把内边距摘掉。
func _add_button(at: Vector2, of_size: Vector2, text: String) -> Button:
	var button := Button.new()
	button.position = at
	button.size = of_size
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	PBSkin.style_button(button, PBSkin.Tone.PLAIN, FONT_SIZE)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box != null:
			box.content_margin_top = 0.0
			box.content_margin_bottom = 0.0
	button.custom_minimum_size = of_size
	add_child(button)
	return button


## 一个任务槽。**一直可见**（空的画成空框）—— 玩家要先看得见有几个槽，
## 「人数不符」才是一条读得到的规则。空格子照样收拖放，见 [method PBUnitTile.clear]。
func _add_tile(at: Vector2) -> PBUnitTile:
	var tile := PBUnitTile.new()
	tile.position = at
	tile.zone = PBUnitTile.ZONE_QUEST
	tile.dropped.connect(card_dropped.emit)
	tile.picked.connect(
		func(hit: PBUnitTile) -> void:
			slot_picked.emit(PBSelection.Kind.DISPATCHED, hit.unit.key())
	)
	add_child(tile)
	return tile
