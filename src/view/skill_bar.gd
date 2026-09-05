class_name PBSkillBar
extends RefCounted
## 指令卡上那几格技能（§02 / 技能案 §4.1、§4.3，M7-e）。全部 static，无状态。
##
## ## 它答三个问题，而三个问题必须用同一个下标
##
## | 问 | 谁在问 |
## |---|---|
## | 这几格各自叫什么、亮不亮、还差几秒 | [PBCommandCard] 每次重排 |
## | 按下这一格之后进什么状态 | [method begin] |
## | 那之后战场上的一下点击是什么意思 | [method land] |
##
## 三处认的都是 [method PBSkillRules.cast_at] 的下标（0 = 大招，1.. = 角色自己的）。
## **各自去判「这一格是大招还是技能表里的」就是同一句话写三遍** ——
## 而漏改一处的表现是「第二个技能的按钮点了放出第一个」，不报错。
##
## ## 为什么从 [PBBattleView] 里搬出来
##
## 直接的触发是那个文件又破了 gdlint 的 1000 行上限（M6-j 拆
## [PBFieldRoster] 时也是这条）。那条上限「超了不是错，是该拆了的信号」，
## 这次它指的地方也是对的：这三件事**共用一个下标约定**，
## 而周围那些是画面装配与阶段推进。
##
## ## 这一层能碰 sim，因为它就是玩家的指令
##
## 和 [PBFieldPicker] 顶上那条同一个理由（§14 渲染层只读的那个例外）：
## 施放是玩家下的令，而令就该是玩家能改的那种状态。
## 门槛仍然只有一份 —— [method PBBattleSim.can_cast]，按钮的亮灰和
## 真正下达时的第一道门读的是同一个函数。


## 把选中那个忍者的技能格摆到 [param card] 上。
##
## 三条平行数组一次算完一起交出去：指令卡手上**没有** [PBBattleSim]，
## 让它自己去问就要给它一条通往战斗实例的路，而那条路一开，
## 界面离「直接改 sim」只剩一步。
static func show_on(
	card: PBCommandCard, battle: PBBattleSim, live: PBAttacker, picker: PBFieldPicker
) -> void:
	var names := PackedStringArray()
	var ready: Array[bool] = []
	var wait := PackedInt32Array()
	if battle != null:
		for i: int in PBSkillRules.cast_count(live):
			var cast := PBSkillRules.cast_at(live, i)
			if cast == null:
				continue
			names.append(label_of(cast.skill, i))
			ready.append(battle.can_cast(live, i))
			wait.append(maxi(cast.ready_at - battle.current_tick(), 0))
	card.set_battle(
		true,
		picker.aim_mode,
		picker.aim_skill,
		live.forced_target if live != null else -1,
		names,
		ready,
		wait,
		battle.order_of(live) if battle != null and live != null else -1
	)


## 第 [param index] 格写什么字。
##
## **第 0 格（大招）M7-h 起不摆**（见 [constant PBCommandCard.CMD_ULTIMATE]），
## 所以这里只会用在角色自己表里那几个上 —— 它们都是 `data/` 里的一条，
## 名字一律查表（铁律 5：`src/` 里不出现技能名）。名单里仍然给它留了一格，
## 是为了下标和 [method PBSkillRules.cast_at] 一一对齐。
static func label_of(skill: PBSkill, index: int) -> String:
	return "" if index < PBCommandCard.FIRST_SKILL else PBLocale.of_skill(skill)


## 这个人那几格技能这一刻的状态，压成一个整数（M7-h）。
##
## [PBBattleView] 每渲染帧拿它和上一帧比，**变了才重排指令卡** ——
## 每帧重排要跑一次装备分配，一秒六十次太贵（见
## [method PBBattleView._refresh_battle_panels]）。
##
## 压进去两件会自己变的事：**冷却转好没有**（转好那一帧格子该亮）、
## **手上攒着的那条指令还在不在**（放出去那一帧「已下令」该换成秒数）。
## 在这之前它只盯大招那一格 —— 而那一格 M7-h 起压根不摆，
## 于是技能格的亮/灰再也不会自己更新，表现是「冷却好了按钮还是灰的」。
static func state_mask(battle: PBBattleSim, live: PBAttacker) -> int:
	if battle == null or live == null:
		return 0
	var mask: int = battle.order_of(live) + 1
	for i: int in PBSkillRules.cast_count(live):
		if battle.can_cast(live, i):
			mask |= 1 << (8 + i)
	return mask


## 玩家按了指令卡上的 [param command_id]。不是技能格就什么都不做。
##
## ## 不挑目标的那一档不进瞄准状态机
##
## [constant PBSkill.Target.NONE] 按一下就放完了。让它先进一个「等你点」
## 的状态再由下一次点击放出去，等于凭空多要一下点击 ——
## 而那两步存在的理由是「点错了有一个能后悔的中间态」，
## 一个没有目标可点错的技能没有这个问题。
static func begin(
	battle: PBBattleSim, picker: PBFieldPicker, live: PBAttacker, command_id: StringName
) -> void:
	var index: int = PBCommandCard.SKILL_COMMANDS.find(command_id)
	# **大招那一格放不出来**（M7-h）：它没有按钮，这里也不留后门 ——
	# 留着的话 `screenshot.gd` 那条 `--aim` 就是第二个入口，而屏幕上没有它。
	if index < PBCommandCard.FIRST_SKILL or battle == null:
		return
	var cast := PBSkillRules.cast_at(live, index)
	if cast == null:
		return
	# 手上已经攒着这一格 → 再按一次就是收回（M7-h）。同
	# [method PBFieldPicker.toggle] 那条「再按一次退出」，说的是同一件事：
	# 玩家按第二下的意思从来都是「算了」。
	if battle.order_of(live) == index:
		battle.cancel_order(live)
		picker.stop()
		return
	if cast.skill.target == PBSkill.Target.NONE:
		battle.cast_skill_now(live, index)
		picker.stop()
		return
	picker.toggle(PBFieldPicker.Aim.SKILL, index)


## 等待中的那一格收到了战场上的一下点击。
##
## ## 这一下是什么意思由**技能自己**说
##
## [enum PBFieldPicker.Aim] 里只有一个 `SKILL`，正是为了不在这儿再摆一份
## 「哪个模式配哪种点击」的表 —— 那会是第二份真相，而它和技能表可以分叉：
## 改了技能的档位却忘了改这里，表现是「点了队友却在地上炸了一发」。
##
## 地面档**哪个点都算**，不用点中谁：它打的是一个圆，「落在哪」本来就是
## 玩家要挑的那件事（M5-9）。锁定档反过来，**点空了就是一次取消** ——
## 就近改治别人的话，玩家点的那个和实际受益的那个不是同一个人，
## 而他不会知道（同 [method PBSkillRules.land_on_ally] 顶上那条）。
static func land(
	battle: PBBattleSim,
	picker: PBFieldPicker,
	live: PBAttacker,
	spot: Vector2,
	field: Vector2,
	pick: float
) -> void:
	var cast := PBSkillRules.cast_at(live, picker.aim_skill)
	if cast == null or battle == null:
		return
	if cast.skill.target == PBSkill.Target.ALLY:
		battle.cast_skill_on(live, picker.ally_at(battle, spot, field, pick), picker.aim_skill)
		return
	if cast.skill.target == PBSkill.Target.GROUND:
		battle.cast_skill(live, spot, picker.aim_skill)
