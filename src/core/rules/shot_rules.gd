class_name PBShotRules
extends RefCounted
## 一发子弹飞一个 tick，够到目标会发生什么。M4-b 起在 [PBBattleSim] 里，M8-b 搬出来。
##
## 和 [PBTargetRules]（敌人该打谁）、[PBMoveRules]（己方该往哪儿走）、
## [PBSkillRules]（一发技能落在谁身上）对称：**这一层答的是
## 「飞行中的那一发到了没有、到了之后落在谁身上」。**
##
## ## 为什么这一步才搬
##
## M4-b 到 M8-a 之间它只有两条支路（打敌人 / 打忍者），各七八行，
## 留在 [PBBattleSim] 里读起来比拆出去顺。M8-b 给子弹加了**技能载荷**
## （[member PBProjectile.skill]）之后两条支路各自分岔，
## 而 `battle_sim.gd` 又贴着 gdlint 的 1000 行上限 ——
## 那条上限「超了不是错，是该拆了的信号」，这次它指的地方也是对的。
##
## ## 为什么这一层可以直接写 [PBCombatOutcome]
##
## 别处的规矩是「记账留在 sim」（[method PBSkillRules.land] 因此返回杀敌数，
## 由调用方加进去）—— 那条规矩防的是**同一本账有好几个来源**。
##
## 这里不一样：**子弹这一相只有这一个所有者**。返回值那条路要同时带回
## 「打死了几个敌人」和「倒下了几个忍者」两个数，而每 tick 造一个
## Dictionary 或者数组是热路径上的分配（§14）。所以这一处直接记账，
## 而它仍然是唯一的来源。

## 全部飞行中的子弹推进一个 tick。够到目标的当场结算并回池。
##
## 目标死了子弹就消失，**不改打别人** —— 理由写在 [PBProjectile] 顶部。
static func advance(
	shots: Array[PBProjectile],
	enemies: Array[PBEnemy],
	attackers: Array[PBAttacker],
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	for shot: PBProjectile in shots:
		if not shot.alive:
			continue
		if shot.at_ally:
			_hit_ally(shot, attackers, cfg, tick, book, out)
		else:
			_hit_enemy(shot, enemies, attackers, cfg, tick, book, out)


## 找一发空子弹。池子满了返回 null —— 那时**这一发就没了**，
## 不扩池也不覆盖别人：扩池会在热路径里分配（§14），
## 覆盖会让一发已经在飞的伤害凭空消失，而两者都不报错。
static func free_shot(shots: Array[PBProjectile]) -> PBProjectile:
	for shot: PBProjectile in shots:
		if not shot.alive:
			return shot
	return null


## 一发射向敌人的子弹。
##
## ## 技能那一发和普攻那一发在这里分岔
##
## 普攻只有伤害；技能那一发还带着 [member PBSkill.on_hit]（M8-b）——
## 而**那正是「飞到了才出伤、才上 buff」这句话的落点**。
## 挂在出膛那一刻的话，一发飞了半秒的火球会在目标还没挨到时就把他点燃。
##
## 命中之后才挂效果（同 [method PBSkillRules.land]）：给一具尸体挂减速
## 没有意义，而且会让「这一发定住了几个」虚高。
## **落地那一下走 [method PBStrikeRules.land]**（M10-d）：记播报、扣血、
## 记杀敌数、跑命中触发四件事因此和近战、范围那两条路**共用一份实现**。
## 各写一遍的话，「远程角色的羁绊触发不了」是一条要盯着数字看很久才发现的 bug，
## 而 §7 的 B15 神赐予的伤痛，载体恰恰是个远程。
static func _hit_enemy(
	shot: PBProjectile,
	enemies: Array[PBEnemy],
	attackers: Array[PBAttacker],
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	var enemy: PBEnemy = enemies[shot.target]
	if not enemy.alive:
		shot.retire()
		return
	if not shot.fly(enemy.pos()):
		return
	# 暴击标记是**出膛那一刻**掷好背过来的，见 [member PBProjectile.crit]。
	# 技能弹没有出手的人可查（施法者可能已经死了）—— 那时 `land` 只结算伤害。
	var alive_before: bool = enemy.alive
	PBStrikeRules.land(
		PBStrikeRules.by_slot(attackers, shot.source),
		enemy,
		shot.damage,
		shot.crit,
		enemies,
		cfg,
		tick,
		book,
		out
	)
	# 技能载荷那一档：**只在这一下没把人打死时才挂**（给尸体挂减速没有意义）。
	if alive_before and enemy.alive and shot.skill != null:
		if PBSkillRules.apply_hit(enemy, shot.skill, shot.level, cfg, tick):
			out.kills += 1
	shot.retire()


## 一发射向己方单位的子弹。
##
## ## 两种载荷，判据是有没有技能挂在上面
##
## **敌人的普攻**（M4-c）：伤害在**命中时**才按防御与属性折算 ——
## 出膛时算的话，飞行途中换了减伤（装备、光环）就对不上了，
## 而那种偏差只表现为「同一发子弹有时候疼有时候不疼」。
##
## **己方的技能弹**（M8-b，治疗那一类）：不走减伤、不掉血，
## 只把 [member PBSkill.on_hit] 挂上去。走减伤那条路的话，
## 一发治疗会被目标的护甲「减免」掉一部分，而那说不通。
static func _hit_ally(
	shot: PBProjectile,
	attackers: Array[PBAttacker],
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	var target: PBAttacker = attackers[shot.target]
	if not target.is_targetable():
		shot.retire()
		return
	if not shot.fly(target.pos):
		return
	if shot.skill != null:
		PBSkillRules.apply_hit_ally(target, shot.skill, shot.level, cfg, tick)
		shot.retire()
		return
	var hurt: float = PBStatRules.strike_damage(
		shot.damage, shot.element, target.defence, target.def_element, cfg
	)
	if book != null:
		book.hit(tick, shot.source, target.slot, hurt, true)
	if target.take_damage(hurt, tick):
		out.allies_lost += 1
		if book != null:
			book.ally_down(tick, target.slot)
	shot.retire()
