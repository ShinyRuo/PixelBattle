class_name PBSkillRules
extends RefCounted
## 一发技能落地时结算什么（M7-b）。全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules]（敌人该打哪个己方单位）、[PBMoveRules]（己方该往哪儿走）
## 对称：**这一层答的是「这一发落在谁身上、他们身上发生了什么」。**
## [PBBattleSim] 只留「什么时候调它」——排在哪个 tick、要不要放、
## 冷却与蓝够不够，那些是战斗节奏的事，不是「落地结算」本身的事。
##
## ## 为什么从 `battle_sim.gd` 搬出来
##
## 直接的触发是那个文件贴着 gdlint 的 1000 行上限。那条上限
## 「超了不是错，是该拆了的信号」，这次它指的地方也是对的：
## 圈人、挂 buff、重置冷却这一整段和「什么时候能放」是两件独立的事，
## 混在一起写会让 [PBBattleSim] 的 `step()` 越来越难读。


## 一发落地：范围内每个敌人各吃一份完整伤害，聚拢/击退的还会被挪位置。
## 返回这一下打死了几个 —— 调用方要把它加进 [PBCombatOutcome]。
##
## 和 [method PBBattleSim._strike_area] 一样**不结算溢出** —— 技能的价值
## 写在命中数上（§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一发范围技能在密集波里等于无限伤害。
static func land(
	cast: PBSkillCast, enemies: Array[PBEnemy], front: int, tick: int
) -> int:
	var skill := cast.skill
	var kills: int = 0
	var hits: int = 0
	for i: int in range(front, enemies.size()):
		if skill.max_targets > 0 and hits >= skill.max_targets:
			break
		var enemy: PBEnemy = enemies[i]
		if not enemy.has_spawned(tick):
			break
		if not enemy.alive:
			continue
		# 真圆（[member PBSkill.radius]），圆心是落点。
		if enemy.pos().distance_to(cast.spot) > skill.radius:
			continue
		hits += 1
		if enemy.take_damage(skill.damage):
			kills += 1
			continue
		# 活下来的才挪 —— 挪一个尸体没有意义，而且会让「聚拢值多少」虚高。
		if skill.gather:
			# 聚拢是**两轴一起**拖到落点上：只拖 x 的话一圈人会被拉成
			# 一条横线，而「聚成一堆」正是这个机制唯一的产出。
			enemy.distance = cast.spot.x
			enemy.lane = cast.spot.y
		elif skill.knockback > 0.0:
			# 击退只作用在推进轴上 —— 它买的是「敌人晚到基地多久」。
			# 上限是**他自己的出生点**，不是战场长度：方阵后面几列出生在
			# 战场之外，拿战场长度封顶会把他们往前拽（见 [member PBEnemy.start_x]）。
			enemy.distance = minf(enemy.distance + skill.knockback, enemy.start_x)
	return kills


## 落地时给全队挂一份短时增伤（§11 二尾、§09 定身档的控制期增伤）。
## 没配这一项（`buff_ticks <= 0` 或倍率不大于 1）什么都不做。
##
## M7-a 起这是「给每个人都挂一份 [PBBuff]」，不再是场上的一份标量 ——
## 见 [method PBBuffRules.team_damage] 顶上那句「全队增伤于是变成
## 给每个人都挂一份的特例」。
static func apply_team_buff(skill: PBSkill, attackers: Array[PBAttacker], tick: int) -> void:
	if skill.buff_ticks <= 0 or skill.team_damage_scale <= 1.0:
		return
	# **一份 Dictionary 发给全队**，不是一人造一个：谁都不改
	# [member PBBuffState.mods]，共用是安全的，而 §14 那条
	# 「热路径不 `.new()`」在这里省的是十一次分配。
	var boost: Dictionary = {PBBuffRules.DAMAGE_SCALE: skill.team_damage_scale}
	for attacker: PBAttacker in attackers:
		attacker.buffs.add(PBBuffRules.team_damage(), boost, tick, skill.buff_ticks, 0)


## 落地时把**其他**技能的冷却清零（§11 六尾）。没配这一项什么都不做。
##
## 清的是别人不是自己 —— 自己也清的话它会在同一 tick 反复自我重置。
## 这一条的强度与队伍里技能的总量成正比，而不是和它自己的数值成正比，
## 所以它在数据上伤害为 0 却可能是最强的一只。
static func reset_other_cooldowns(
	skill: PBSkill, caster: PBSkillCast, attackers: Array[PBAttacker], tick: int
) -> void:
	if not skill.reset_cooldowns:
		return
	for attacker: PBAttacker in attackers:
		var other: PBSkillCast = attacker.ultimate
		if other != null and other != caster and not other.is_pending():
			other.ready_at = tick
