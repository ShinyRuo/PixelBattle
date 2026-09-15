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

## 穿透段每多穿一个敌人衰减几成（纸手里剑「每穿透一个目标会衰减 15% 的伤害」）。
## 这是原版那一句的数，不是配平出来的；只有一个人用，所以不进词汇表。
const PIERCE_DECAY: float = 0.15

## 穿透段扫多宽（战场坐标，直线两侧各这么多）。取溅射默认半径的一半：
## 贴着直线站的那一排算穿到，隔一个身位的不算。
const PIERCE_HALF_WIDTH: float = 0.03


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
	if shot.piercing:
		out.kills += _pierce(shot, enemies, PBStrikeRules.by_slot(attackers, shot.source), cfg, tick)
		return
	var enemy: PBEnemy = enemies[shot.target]
	if not enemy.alive:
		shot.retire()
		return
	if not shot.fly(enemy.pos()):
		return
	# 暴击标记是**出膛那一刻**掷好背过来的，见 [member PBProjectile.crit]。
	# 出手的人可能已经死了（找不到是 null）—— 那时只结算伤害、不算穿透、不跑触发。
	var shooter := PBStrikeRules.by_slot(attackers, shot.source)
	if shot.skill != null:
		# 技能子弹不是普攻：减伤按技能的类型，不跑普攻那几样触发。
		out.kills += PBSkillRules.hit_by_shot(enemy, shot, shooter, cfg, tick, book)
		shot.retire()
		return
	PBStrikeRules.land(shooter, enemy, shot.damage, shot.crit, enemies, cfg, tick, book, out)
	# 穿透的普攻打中第一个之后不回池，接着往前飞（玩家定的：子弹不能碰到第一个敌人就消失）。
	if shot.pierce_left > 0.0:
		shot.start_pierce(shot.target)
		return
	shot.retire()


## 穿透段飞一个 tick（[member PBProjectile.piercing]）：沿直线往前走，这一步扫过的窄带里
## 还没挨过这一发的敌人各挨一下，每多穿一个衰减 [constant PIERCE_DECAY]。返回打死了几个。
##
## **同溅射**：直接 [method PBEnemy.take_damage]，不回头调 [method PBStrikeRules.land] ——
## 穿到的那几下不吸血、不溅射、不挂命中效果，也不记播报（掉血由 [PBDamageWatch] 逐帧比出来）。
## 一步之内按数组顺序结算而不是按远近：一 tick 飞的距离比两个敌人的间距短，差不出一档衰减。
## 减伤照算（[method PBStrikeRules.mitigated]）：穿到的仍是普攻，类型跟着射手。[param shooter] 死了是 null，那时不算穿透。
static func _pierce(
	shot: PBProjectile,
	enemies: Array[PBEnemy],
	shooter: PBAttacker,
	cfg: PBSimConfig,
	tick: int
) -> int:
	var start: Vector2 = shot.pos
	var more: bool = shot.glide()
	var killed: int = 0
	for i: int in enemies.size():
		var other: PBEnemy = enemies[i]
		if not other.alive or not other.has_spawned(tick) or shot.struck.has(i):
			continue
		if _off_line(other.pos(), start, shot.pos) > PIERCE_HALF_WIDTH:
			continue
		var hit: float = shot.damage * pow(1.0 - PIERCE_DECAY, shot.struck.size())
		shot.struck.append(i)
		var kind := PBCritRules.attack_kind(shooter)
		if other.take_damage(PBStrikeRules.mitigated(shooter, other, hit, kind, cfg, tick), tick):
			killed += 1
	if not more:
		shot.retire()
	return killed


## [param spot] 离线段 [param a]→[param b] 最近有多远。
static func _off_line(spot: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var span: float = ab.length_squared()
	var along: float = 0.0 if span <= 0.0 else clampf((spot - a).dot(ab) / span, 0.0, 1.0)
	return spot.distance_to(a + ab * along)


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
		target,
		_shooter(shot, enemies),
		shot.damage,
		shot.element,
		cfg,
		tick,
		rng,
		book,
		out,
		attackers
	)
	shot.retire()
