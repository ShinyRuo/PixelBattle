class_name PBShotRules
extends RefCounted
## 一发子弹飞一个 tick，够到目标会发生什么。
##
## 和 [PBTargetRules] / [PBMoveRules] / [PBSkillRules] 对称：这一层答
## 「飞行中的那一发到了没有、到了之后落在谁身上」。
##
## **这一层直接写 [PBCombatOutcome]**，破了「记账留在 sim」那条：那条规矩防的是
## 同一本账有好几个来源，而子弹这一相只有这一个所有者；走返回值要每 tick 分配
## 一个容器带回两个数（§14 热路径）。

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
	out: PBCombatOutcome,
	rng: RandomNumberGenerator = null
) -> void:
	for shot: PBProjectile in shots:
		if not shot.alive:
			continue
		if shot.at_ally:
			_hit_ally(shot, attackers, enemies, cfg, tick, book, out, rng)
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
## 技能那一发带着 [member PBSkill.on_hit]，**命中才挂**：挂在出膛那一刻的话，
## 飞了半秒的火球会在目标还没挨到时就把他点燃；给尸体挂减速也会让计数虚高。
##
## **落地走 [method PBStrikeRules.land]**，和近战、范围共用一份实现 ——
## 各写一遍的表现是「远程角色的命中触发不生效」。
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


## 放这一发的敌人。**[member PBProjectile.source] 存的就是它在池子里的下标**
## （见 [member PBEnemy.slot]），但那一发飞到的时候它可能已经死了 ——
## 找不到就是 null，反弹那一句会自己认。
static func _shooter(shot: PBProjectile, enemies: Array[PBEnemy]) -> PBEnemy:
	if shot.source < 0 or shot.source >= enemies.size():
		return null
	return enemies[shot.source]


## 一发射向己方单位的子弹。
##
## **敌人的普攻**：伤害在命中时才按防御与属性折算 —— 出膛时算的话，
## 飞行途中换了减伤就对不上了。
##
## **己方的技能弹**（治疗那一类）：不走减伤、不掉血，只挂 [member PBSkill.on_hit]。
static func _hit_ally(
	shot: PBProjectile,
	attackers: Array[PBAttacker],
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome,
	rng: RandomNumberGenerator
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
	# 折算、播报、扣血、阵亡、反弹全走 [method PBStrikeRules.hurt_ally]，近战那一路调的是同一个。
	PBStrikeRules.hurt_ally(
		target, _shooter(shot, enemies), shot.damage, shot.element, cfg, tick, rng, book, out
	)
	shot.retire()
