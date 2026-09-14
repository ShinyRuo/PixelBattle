class_name PBSkillBar
extends RefCounted
## 指令卡上那几格技能。全部 static，无状态。三个问题用同一个下标：
##
## | 问 | 谁在问 |
## |---|---|
## | 这几格各自叫什么、亮不亮、还差几秒 | [PBCommandCard] 每次重排 |
## | 按下这一格之后进什么状态 | [method begin] |
## | 那之后战场上的一下点击是什么意思 | [method land] |
##
## 下标是 [method PBSkillRules.cast_at] 那一套（0 = 大招，1.. = 角色自己的）。
##
## **这一层能碰 sim**：施放是玩家下的令（同 [PBFieldPicker]）。门槛只有一份 ——
## 按钮的亮灰和真正下达时的第一道门读的都是 [method PBBattleSim.can_cast]。


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
	var skills: Array[PBSkill] = []
	var level: int = 1
	if battle != null:
		for i: int in PBSkillRules.cast_count(live):
			var cast := PBSkillRules.cast_at(live, i)
			if cast == null:
				continue
			names.append(label_of(cast.skill, i))
			ready.append(battle.can_cast(live, i))
			wait.append(maxi(cast.ready_at - battle.current_tick(), 0))
			skills.append(cast.skill)
			level = maxi(level, cast.caster_level)
	card.set_skills(skills, level)
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


## 第 [param index] 格写什么字。第 0 格（大招）不摆（[constant PBCommandCard.CMD_ULTIMATE]），
## 名单里仍然给它留一格，是为了下标和 [method PBSkillRules.cast_at] 对齐。名字一律查表（铁律 5）。
static func label_of(skill: PBSkill, index: int) -> String:
	return "" if index < PBCommandCard.FIRST_SKILL else PBLocale.of_skill(skill)


## 这个人那几格技能这一刻的状态，压成一个整数。[PBBattleView] 每帧拿它和上一帧比，**变了才重排指令卡**
## （每帧重排要跑一次装备分配）。压进去两件会自己变的事：冷却转好没有、手上攒着的那条指令还在不在。
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
	# **大招那一格放不出来**：它没有按钮，这里也不留后门，否则截图工具就成了第二个入口。
	if index < PBCommandCard.FIRST_SKILL or battle == null:
		return
	var cast := PBSkillRules.cast_at(live, index)
	if cast == null:
		return
	# 手上已经攒着这一格 → 再按一次就是收回（玩家按第二下的意思从来都是「算了」）。
	if battle.order_of(live) == index:
		battle.cancel_order(live)
		picker.stop()
		return
	if cast.skill.target == PBSkill.Target.NONE:
		battle.cast_skill_now(live, index)
		picker.stop()
		return
	picker.toggle(PBFieldPicker.Aim.SKILL, index)


## 等待中的那一格收到了战场上的一下点击。**这一下是什么意思由技能自己说**（[member PBSkill.target]）。
##
## 地面档**哪个点都算**（落在哪本来就是要挑的事）；锁定档**点空了就是取消** ——
## 就近改治别人的话，玩家点的和实际受益的不是同一个人。
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
	if cast.skill.target == PBSkill.Target.ENEMY:
		# 点敌人那一档**和「攻击」共用同一份命中判定**（[method PBFieldPicker.enemy_at]）。
		battle.cast_skill_at(live, picker.enemy_at(battle, spot, field, pick), picker.aim_skill)
		return
	if cast.skill.target == PBSkill.Target.GROUND:
		battle.cast_skill(live, spot, picker.aim_skill)
