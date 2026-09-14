class_name PBStrikeRules
extends RefCounted
## 己方这一 tick 的普攻：谁打得着谁、打多少、命中之后还发生什么。
## 全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules] / [PBMoveRules] / [PBSkillRules] / [PBShotRules] 对称：
## 这一层答「他这一 tick 打出去了什么」。
##
## ## 两个唯一落点
##
## - [method land]：一次命中落在一个敌人身上（近战、范围、子弹都调它）。
##   各写一遍「记播报 → 扣血 → 记杀敌数 → 触发」的话，漏一处就是
##   「某一种攻击方式不触发」，而它不报错。
## - [method hurt_ally]：一次敌人的攻击落在一个忍者身上（近战、子弹都调它）。
##
## 触发型字段（[member PBAttacker.splash_damage] 那一批）默认 0，没人配时一位都不动。
## **溅射不再触发溅射**：它直接走 [method PBEnemy.take_damage] 不回头调 [method land]，
## 否则高倍溅射在密集波里指数展开。

## 溅射**默认**够得到多远（[member PBAttacker.splash_damage]，B15 神赐予的伤痛）。
## 自带原版溅射范围的人（[member PBAttacker.splash_radius]）不用它，见 [method splash_reach]。
##
## 0.06 是三倍的防挤间距（[member PBSimConfig.unit_min_gap] 约 0.012 ×
## 敌人那一侧的围攻环），也就是「贴着他站的那一圈」。
## 放大到大招那个量级（`ultimate_radius`）的话，一次普攻会盖住半个战场 ——
## 而 §02 把「一次罩住多少人」定为 AOE 的**全部价值**，那等于白送一个 AOE。
const SPLASH_RADIUS: float = 0.06

## 血量高过几成算「高血量」（[member PBAttacker.heavy_bonus]，B05 日向兄妹）。
const HEAVY_THRESHOLD: float = 0.5

## 按目标生命百分比那一笔最多能打这一下伤害的几倍。
##
## **封顶是结构上必须有的**：BOSS 血量按波次指数长，百分比伤害是那条曲线的常数倍，
## 不封顶的话这几个角色在后期独占全场。封成「几倍」而不是绝对值（原版封 8000 / 5000）：
## 绝对值上限会在数值回归改一次基数之后整个失效，而且不报错。
const BITE_CAP: float = 3.0

## 命中之后那段暴击率加成持续几秒（[member PBAttacker.crit_on_hit]）。
## **必须比普攻间隔长**（最慢约 1.2 秒一下）：短于间隔的话它只在挂上那一 tick 有效，等于没有。
const CRIT_WINDOW_SECONDS: float = 3.0

## 羁绊给的量。理由同 [constant PBCritRules.BOND_CRIT_CHANCE]：
## 这几个数不是配平出来的，是把 §7 的文字描述落成可跑的量。
const BOND_CRIT_ON_HIT: float = 0.25
const BOND_SPLASH: float = 0.35
const BOND_HEAVY_BONUS: float = 0.30
const BOND_REVIVES: int = 1

## 「命中之后提暴击」那一份的定义。见 [method crit_window]。
static var _crit_window: PBBuff = null


## 全队这一 tick 各自出一次手。**每个攻击者各自选目标，互不共享伤害池** ——
## 整队一个池子就是单服务台排队，没有中间态；各打各的，同一波敌人才会被分批处理。
##
## [param front] 是队伍最前面那个还活着的敌人的下标 —— 敌人按出场顺序排列，
## 数组顺序天然就是距离顺序。
static func deal(
	attackers: Array[PBAttacker],
	enemies: Array[PBEnemy],
	shots: Array[PBProjectile],
	front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	for attacker: PBAttacker in attackers:
		# 死人不输出；冷却没转好也不出手（连续输出的退化路径间隔是 1 tick，每 tick 都过得了）。
		if not attacker.alive or not attacker.ready_to_fire(tick):
			continue
		# **抬手**：冷却转好之后先起手，[member PBAttacker.windup_ticks] 之后才结算。
		# 要先确认射程内真有人 —— 对着空气抬手的话，抬完那一刻敌人走进来，
		# 伤害会在没有起手的情况下落地。
		if first_reachable(attacker, enemies, front, tick) != null and attacker.begin_swing(tick):
			continue
		var fired: bool = (
			_strike_area(attacker, enemies, front, cfg, tick, rng, book, out)
			if attacker.shape == PBAttacker.Shape.AOE
			else _strike_single(attacker, enemies, shots, front, cfg, tick, rng, book, out)
		)
		# **打空了不进冷却。** 进的话，射程内暂时没人的那几 tick 会白白
		# 吃掉一个间隔，等敌人走进来时他还得再等 —— 表现是「远程有时候发呆」。
		if fired:
			attacker.on_fired(tick)
		else:
			# 抬着手却打空了（目标死了、走了）—— 手放下，下次重新抬。
			# 不放的话下一个走进射程的敌人会挨一发没有起手的伤害。
			attacker.swinging = false


## 玩家点名的那个敌人，**只在他还活着、也已经出场的时候**。否则 null。
static func named_target(attacker: PBAttacker, enemies: Array[PBEnemy], tick: int) -> PBEnemy:
	if attacker.forced_target < 0 or attacker.forced_target >= enemies.size():
		return null
	var named: PBEnemy = enemies[attacker.forced_target]
	return named if named.alive and named.has_spawned(tick) else null


## 射程内最接近基地的那个活敌人。没有就返回 null。
## **玩家点名的那个优先**，但只在他还活着且够得着时 —— 够不着就照常自动选，
## 理由见 [member PBAttacker.forced_target]。
static func first_reachable(
	attacker: PBAttacker, enemies: Array[PBEnemy], front: int, tick: int
) -> PBEnemy:
	var named := named_target(attacker, enemies, tick)
	if named != null and attacker.can_reach(named.pos()):
		return named
	for i: int in range(front, enemies.size()):
		var enemy: PBEnemy = enemies[i]
		if not enemy.has_spawned(tick):
			# 后面的出场更晚，这一 tick 不会再有可打的目标了。
			break
		if enemy.alive and attacker.can_reach(enemy.pos()):
			return enemy
	return null


## 按 [member PBAttacker.slot] 找人。子弹落地那一路要回头问「谁打的」，
## 而它手上只有一个槽位号（[member PBProjectile.source]）。
##
## 线性扫是有意的：出战席最多十几个人，而这只发生在**命中**那一 tick。
## 拿 `attackers[slot]` 直接下标的话，尾兽那一位
## （[constant PBBeastRules.BEAST_SLOT] 是负数）会把它索引到队尾。
static func by_slot(attackers: Array[PBAttacker], slot: int) -> PBAttacker:
	for attacker: PBAttacker in attackers:
		if attacker.slot == slot:
			return attacker
	return null


## **一次命中落在一个敌人身上。** 记播报 → 扣血 → 记杀敌数 → 跑触发。
## 三条出手路径和子弹那一路全部走这里，见本类顶部。
##
## [param attacker] 允许为 null（找不到出手的人时），那时只结算伤害、不跑触发。
static func land(
	attacker: PBAttacker,
	enemy: PBEnemy,
	damage: float,
	crit: bool,
	enemies: Array[PBEnemy],
	cfg: PBSimConfig,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	var total: float = damage + _heavy_extra(attacker, enemy, damage)
	total += _bite_extra(attacker, enemy, damage, crit)
	if book != null:
		book.hit(tick, -1 if attacker == null else attacker.slot, enemy.slot, total, false, crit)
	if enemy.take_damage(total, tick):
		out.kills += 1
	if attacker == null:
		return
	out.kills += _splash(attacker, enemy, enemies, damage, cfg, tick)
	_arm_crit(attacker, cfg, tick)
	out.kills += _hang_on_hit(attacker, enemy, crit, cfg, tick)


## 打出要害那一下把他自带的效果挂到目标身上（[member PBAttacker.on_hit_buffs]）。
## 返回挂死了几个。
##
## - **骑在暴击那个掷点上**，不另开骰子（同 [method _bite_extra]）。
## - **死了就不挂**：给尸体挂减速会让「定住了几个」虚高。
## - **等级从大招那份上读**：[PBAttacker] 身上没有 `level`（见 [member PBSkillCast.caster_level]），
##   拿不到就算 1 级。
static func _hang_on_hit(
	attacker: PBAttacker, enemy: PBEnemy, crit: bool, cfg: PBSimConfig, tick: int
) -> int:
	if not crit or not enemy.alive or attacker.on_hit_buffs.is_empty():
		return 0
	var level: int = 1
	if attacker.ultimate != null:
		level = attacker.ultimate.caster_level
	return 1 if PBSkillRules.apply_all_enemy(enemy, attacker.on_hit_buffs, level, cfg, tick) else 0


## 一次**敌人的攻击**落在一个忍者身上的唯一落点。
## [param raw] 是没折算克制与护甲之前的那个数。
##
## 和 [method land] 是对称的两半。己方挨打有两条路（[PBBattleSim] 的近战、
## [method PBShotRules._hit_ally] 的子弹），各写一遍的话漏一处就是「被子弹打不反弹」。
##
## **反弹打死的那一个在这里记账**：放回调用方的话杀敌数就有了第二个来源。
static func hurt_ally(
	target: PBAttacker,
	source: PBEnemy,
	raw: float,
	element: PBElement.Type,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	# 临时防御（[constant PBBuffRules.DEFENCE]）在这里加：护甲只在这一句折算。
	var armour: float = target.defence + target.buffs.amount(PBBuffRules.DEFENCE, tick)
	var hurt: float = PBStatRules.strike_damage(raw, element, armour, target.def_element, cfg)
	if book != null:
		book.hit(tick, -1 if source == null else source.slot, target.slot, hurt, true)
	wound_ally(target, hurt, cfg, tick, rng, book, out)
	_reflect(target, source, hurt, tick, book, out)


## 一个忍者**掉血**的唯一落点：扣血、阵亡记账、血量阈值触发。返回这一下有没有让他倒下。
##
## 进来的两条路是敌人的攻击（[method hurt_ally]，近战和子弹都走它）与自身掉血
## （[constant PBBuffRules.DRAIN_MAX]，[PBBattleSim] 每 tick 调）。**阈值判在这里、调用方不判**：
## 判在 `hurt_ally` 的话，自己掉血掉过线的那一下就不触发。
##
## [param hurt] 是折算完护甲与克制之后的数。播报（挨了多少）归调用方 —— 自身掉血每秒一跳，
## 记进去会把另外几种冲掉；**倒下**那一条在这里记，否则掉血掉死的人没有播报。
static func wound_ally(
	target: PBAttacker,
	hurt: float,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> bool:
	if target.take_damage(hurt, tick, rng):
		# **召唤物没了不算「折了一个」**（玩家定的）：`allies_lost` 是玩家要心疼的数，
		# 影分身本来就是拿来炸的；播报同理，否则「忍者倒下」那一档会被冲干净。
		if not target.summoned:
			out.allies_lost += 1
			if book != null:
				book.ally_down(tick, target.slot)
		# 阵亡技能在这里只记一笔：放出去要全场的敌我名单，那在 [PBBattleSim] 手上。
		target.death_pending = not target.death_casts.is_empty()
		return true
	if target.lethal_pending:
		target.lethal_pending = false
		_hang_self(target, target.lethal_buffs, cfg, tick)
	_arm_low_hp(target, cfg, tick)
	return false


## 血量掉到阈值以下那一刻，把他自带的那几份效果挂到自己身上。**一波一次**（[member PBAttacker.low_hp_fired]）。
##
static func _arm_low_hp(target: PBAttacker, cfg: PBSimConfig, tick: int) -> void:
	if target.low_hp_fired or target.low_hp_at <= 0.0 or target.low_hp_buffs.is_empty():
		return
	if not target.alive or target.hp >= target.max_hp * target.low_hp_at:
		return
	target.low_hp_fired = true
	_hang_self(target, target.low_hp_buffs, cfg, tick)


## 把他自带的一串效果挂到自己身上。等级读法同 [method _hang_on_hit]。
static func _hang_self(
	target: PBAttacker, buffs: Array[PBBuff], cfg: PBSimConfig, tick: int
) -> void:
	var level: int = 1 if target.ultimate == null else target.ultimate.caster_level
	for buff: PBBuff in buffs:
		PBSkillRules.apply_one(target, buff, PBBuffRules.resolve(buff, level), cfg, tick)


## 把挨的这一下按比例还回去。没配就是 0。
##
## **还的是折算之后的那个数**（也就是他实际会掉的血），不是敌人报出来的原始值 ——
## 后者没有经过护甲与克制，而玩家看到的伤害数字是前者。两者不一致的表现是
## 「反弹出来的数和挨的那一下对不上」。
##
## **闪掉的那一下照样反弹**：[method PBAttacker.take_damage] 里闪避返回 false，
## 而这一句排在它外面。原版那一条正是「免疫此次伤害**并**反弹」——
## 两件事一起发生，只是我们把它们拆成了两个能各自单独配的键。
static func _reflect(
	target: PBAttacker,
	source: PBEnemy,
	hurt: float,
	tick: int,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> void:
	if source == null or not source.alive or target.reflect <= 0.0 or hurt <= 0.0:
		return
	var back: float = hurt * target.reflect
	if book != null:
		book.hit(tick, target.slot, source.slot, back, false)
	if source.take_damage(back, tick):
		out.kills += 1
## 「命中之后提暴击」的效果定义（B10）。同 [method PBBuffRules.team_damage]：
## 它只提供**身份**，数值每次挂的时候另给。
static func crit_window() -> PBBuff:
	if _crit_window == null:
		_crit_window = PBBuff.new()
		_crit_window.id = &"crit_window"
		_crit_window.name_key = "buff.crit_window"
		_crit_window.icon_key = "buff.crit_window"
		_crit_window.kind = PBBuff.Kind.DURATION
		_crit_window.friendly = true
	return _crit_window


## 对**血还很多**的敌人那一笔追加伤害。没配就是 0。
##
## 判据看**这一下之前**的血量比 —— 打完再看的话，正好打到半血以下那一下拿不到加成。
## 和主伤害**加在一起**进 [method PBEnemy.take_damage]：分开打的话易伤乘两次，
## 屏幕上一次普攻飘两个数。
static func _heavy_extra(attacker: PBAttacker, enemy: PBEnemy, damage: float) -> float:
	if attacker == null or attacker.heavy_bonus <= 0.0 or enemy.max_hp <= 0.0:
		return 0.0
	if enemy.hp / enemy.max_hp < HEAVY_THRESHOLD:
		return 0.0
	return damage * attacker.heavy_bonus


## 打出要害那一下按目标生命百分比再追加的一笔。没配就是 0。
##
## **骑在暴击那个掷点上**：「这一下打中了要害」就是暴击在这个游戏里的语义，
## 另开骰子会让同一次出手掷两遍。代价是暴击光环会同时提高它的触发率（原版不会）。
##
## `bite_current` 按**还剩多少**算（越打越弱），`bite_lost` 按**已经掉了多少**算
## （越打越强）—— 两个字段，一个人才带得了两种。加进主伤害，理由同 [method _heavy_extra]。
static func _bite_extra(
	attacker: PBAttacker, enemy: PBEnemy, damage: float, crit: bool
) -> float:
	if attacker == null or not crit or enemy.max_hp <= 0.0:
		return 0.0
	var share: float = enemy.hp * attacker.bite_current
	share += maxf(enemy.max_hp - enemy.hp, 0.0) * attacker.bite_lost
	if share <= 0.0:
		return 0.0
	return minf(share, damage * BITE_CAP)


## 这个人的溅射够得到多远（战场坐标）。配了原版码数（[member PBAttacker.splash_radius]）就按它换算，
## 没配就是 [constant SPLASH_RADIUS]。**换算只在这里**，同 [method PBSimConfig.reach_of]。
static func splash_reach(attacker: PBAttacker, cfg: PBSimConfig) -> float:
	if attacker == null or attacker.splash_radius <= 0.0 or cfg == null:
		return SPLASH_RADIUS
	return cfg.units_to_field(attacker.splash_radius)


## 溅射。返回这一下顺带打死了几个。
##
## **不回头调 [method land]**（溅射不触发溅射），也不记播报 —— 被溅到的那几个
## 自己掉血，由 [PBDamageWatch] 逐帧比出来。
static func _splash(
	attacker: PBAttacker,
	center: PBEnemy,
	enemies: Array[PBEnemy],
	damage: float,
	cfg: PBSimConfig,
	tick: int
) -> int:
	if attacker.splash_damage <= 0.0 or damage <= 0.0:
		return 0
	var each: float = damage * attacker.splash_damage
	var spot: Vector2 = center.pos()
	var reach: float = splash_reach(attacker, cfg)
	var killed: int = 0
	for other: PBEnemy in enemies:
		if other == center or not other.alive or not other.has_spawned(tick):
			continue
		if spot.distance_to(other.pos()) > reach:
			continue
		if other.take_damage(each, tick):
			killed += 1
	return killed


## 命中之后给自己挂那段暴击率（B10）。没配就什么都不发生。
static func _arm_crit(attacker: PBAttacker, cfg: PBSimConfig, tick: int) -> void:
	if attacker.crit_on_hit <= 0.0:
		return
	attacker.buffs.add(
		crit_window(),
		{PBBuffRules.CRIT_CHANCE: attacker.crit_on_hit},
		tick,
		PBBuffRules.to_ticks(CRIT_WINDOW_SECONDS, cfg),
		0,
		attacker.slot
	)


## 单体攻击：打射程内最接近基地的那个。**打不到人返回 false。**
##
## [member PBAttacker.attack_speed] 大于 0 时是**一次离散出手**：远程放子弹，近战当场见血，
## **不结算溢出**（一发打死了目标，多出来的伤害没处去，见 [PBProjectile] 顶部）。
##
## 攻速为 0 时走**连续输出**的退化路径（[method PBAttacker.whole_field]），
## 必须与 [PBCombatRules] 的解析式排队模型逐字段一致，那个模型的前提之一是溢出无损转移。
static func _strike_single(
	attacker: PBAttacker,
	enemies: Array[PBEnemy],
	shots: Array[PBProjectile],
	front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> bool:
	if attacker.attack_speed <= 0.0:
		return _pour_damage(attacker, enemies, front, tick, rng, out)
	var target := first_reachable(attacker, enemies, front, tick)
	if target == null:
		return false
	# 暴击的**唯一掷点**。近战与子弹都走它，见 [PBCritRules]。
	var swing: Dictionary = PBCritRules.strike(attacker, tick, rng)
	var damage: float = swing[PBCritRules.DAMAGE]
	var crit: bool = swing[PBCritRules.CRIT]
	# 近战没有子弹（[member PBAttacker.shot_speed] 为 0），当场结算。
	if attacker.shot_speed <= 0.0:
		land(attacker, target, damage, crit, enemies, cfg, tick, book, out)
		return true
	var shot := PBShotRules.free_shot(shots)
	if shot == null:
		return false
	shot.launch(
		attacker.pos, target.slot, damage, attacker.shot_speed,
		false, PBElement.Type.PHYSICAL, attacker.slot, null, 1, crit
	)
	return true


## 连续输出那条退化路径：一股伤害顺着队列往下浇，打死了溢出接着打下一个。
##
## 溢出必须结算：高 DPS 一 tick 能打死好几个，漏掉溢出会让战斗时长
## 被系统性拉长 —— 而这条路径存在的全部理由就是与解析式排队模型对拍。
##
## **它不走 [method land]**：那条路上的是 [method PBAttacker.whole_field]
## 造的退化标量 —— 没有 slot、不记播报、也不该跑触发，
## 而它必须与排队模型逐位相同。
static func _pour_damage(
	attacker: PBAttacker,
	enemies: Array[PBEnemy],
	front: int,
	tick: int,
	rng: RandomNumberGenerator,
	out: PBCombatOutcome
) -> bool:
	# 也走掷点（一把尺子），但这条路上的攻击者暴击率恒为 0 ——
	# 于是一次骰子都不掷，解析式对拍逐位相同。见 [PBCritRules]。
	var remaining: float = PBCritRules.strike(attacker, tick, rng)[PBCritRules.DAMAGE]
	var hit: bool = false
	var index: int = front
	while remaining > 0.0 and index < enemies.size():
		var enemy: PBEnemy = enemies[index]
		if not enemy.has_spawned(tick):
			break
		if not enemy.alive or not attacker.can_reach(enemy.pos()):
			index += 1
			continue
		hit = true
		# **花掉多少伤害，不是掉了多少血** —— 易伤让两者不同，而这条退化路径是对拍锚点
		# （见 [method PBEnemy.damage_to_kill]）。
		var cost: float = enemy.damage_to_kill(tick)
		if enemy.take_damage(remaining, tick):
			out.kills += 1
			remaining -= cost
			index += 1
		else:
			remaining = 0.0
	return hit


## 范围攻击：对射程内最靠近基地的若干个目标**各打一份完整伤害**。
## **一个都够不着时返回 false。**
##
## 不结算溢出：AOE 的价值写在命中数上，再吃溢出的话在密集波里等于无限伤害。
## **范围型不发子弹**：一发子弹只追一个目标。
static func _strike_area(
	attacker: PBAttacker,
	enemies: Array[PBEnemy],
	front: int,
	cfg: PBSimConfig,
	tick: int,
	rng: RandomNumberGenerator,
	book: PBBattleLog,
	out: PBCombatOutcome
) -> bool:
	# **一次出手掷一次**，命中的几个共用它 —— 逐个目标掷的话，
	# 一发范围攻击会同时飘出黄的和白的数字，而那本来就是同一下。
	var swing: Dictionary = PBCritRules.strike(attacker, tick, rng)
	var damage: float = swing[PBCritRules.DAMAGE]
	if damage <= 0.0:
		return false
	var hits: int = 0
	var index: int = front
	while hits < attacker.max_targets and index < enemies.size():
		var enemy: PBEnemy = enemies[index]
		if not enemy.has_spawned(tick):
			break
		index += 1
		if not enemy.alive or not attacker.can_reach(enemy.pos()):
			continue
		land(attacker, enemy, damage, swing[PBCritRules.CRIT], enemies, cfg, tick, book, out)
		hits += 1
	return hits > 0
