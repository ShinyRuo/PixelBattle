class_name PBStrikeRules
extends RefCounted
## 己方这一 tick 的普攻：谁打得着谁、打多少、命中之后还发生什么。M10-d 从
## [PBBattleSim] 搬出来。全部 static，无状态，零引擎依赖。
##
## 和 [PBTargetRules]（敌人该打谁）、[PBMoveRules]（己方该往哪儿走）、
## [PBSkillRules]（一发技能落在谁身上）、[PBShotRules]（飞行中的那一发到了没有）
## 对称：**这一层答的是「他这一 tick 打出去了什么」。**
##
## ## 为什么这一步才搬
##
## `battle_sim.gd` 停在 gdlint 的 1000 行上限上，而 M10-d 要加的东西
## （命中之后的触发）恰恰要求先有一个**唯一的落点**。那条上限
## 「超了不是错，是该拆了的信号」，这次它指的地方也是对的：
## 出手那三段（单体 / 连续输出 / 范围）加上「够得着谁」全部只读位置与血量，
## 而周围那些函数全在推进状态。
##
## ## [method land] 是「一次命中落在一个敌人身上」的唯一落点
##
## 在它之前这件事发生在三处：近战当场见血、范围各打一份、
## 子弹飞到了结算（[method PBShotRules._hit_enemy]）。三处各写一遍
## 「记播报 → 扣血 → 记杀敌数」已经够呛，M10-d 还要往后面接触发 ——
## **漏一处的表现是「某一种攻击方式不触发」**，而它不报错。
##
## 所以子弹那一路也回头调它（[method PBShotRules] 顶上那条
## 「这一相只有这一个所有者」因此仍然成立：记账的入口还是唯一的，
## 只是从那个文件挪到了这个文件）。
##
## ## 触发型羁绊（§7 的 B05 / B10 / B15）
##
## 三个都挂在**载体本人**身上（[member PBAttacker.splash_damage] 那一批），
## 都默认 0 —— 所以没有任何羁绊配它们时**一位都不动**，
## 同 M3.5-f 装备那条「空着 = 一字不差」。
##
## **溅射不再触发溅射**：它直接走 [method PBEnemy.take_damage]，不回头调
## [method land]。递归的话一个高倍溅射会在密集波里指数展开，
## 而表现是「某几波突然卡住不动」（MAX_TICKS 兜着，但那是安全阀不是设计）。

## 溅射够得到多远（[member PBAttacker.splash_damage]，B15 神赐予的伤痛）。
##
## 0.06 是三倍的防挤间距（[member PBSimConfig.unit_min_gap] 约 0.012 ×
## 敌人那一侧的围攻环），也就是「贴着他站的那一圈」。
## 放大到大招那个量级（`ultimate_radius`）的话，一次普攻会盖住半个战场 ——
## 而 §02 把「一次罩住多少人」定为 AOE 的**全部价值**，那等于白送一个 AOE。
const SPLASH_RADIUS: float = 0.06

## 血量高过几成算「高血量」（[member PBAttacker.heavy_bonus]，B05 日向兄妹）。
const HEAVY_THRESHOLD: float = 0.5

## 按目标生命百分比那一笔最多能打这一下伤害的几倍（M12-c2）。
##
## **封顶不是配平，是结构上必须有的。** [member PBAttacker.heavy_bonus] 顶上
## 那条早就写着理由：§04 的 BOSS 血量按波次**指数**长，而百分比伤害是那条
## 曲线的常数倍 —— 不封顶的话这几个角色在后期独占全场，
## 而屏幕上只表现为「后面几波好像只有他在输出」。
##
## **原版自己也封**（柔拳最大 8000、骨拔最高 5000），只是它封的是绝对值。
## 这里封成「这一下伤害的几倍」是因为本项目的伤害口径和原版换算不到一起
## （同 `data/skills.tsv` 顶上那条「倍率是我们的」），
## 而绝对值上限会在数值回归改一次基数之后整个失效，**且不报错**。
const BITE_CAP: float = 3.0

## 命中之后那段暴击率加成持续几秒（[member PBAttacker.crit_on_hit]，B10）。
##
## 比普攻间隔长是有意的（最慢的攻速约 1.2 秒一下）：短于间隔的话
## 这个 buff 在下一发之前就过期了，**它就永远只在挂上的那一 tick 有效** ——
## 而那等于没有，且不报错。
const CRIT_WINDOW_SECONDS: float = 3.0

## 羁绊给的量。理由同 [constant PBCritRules.BOND_CRIT_CHANCE]：
## 这几个数不是配平出来的，是把 §7 的文字描述落成可跑的量。
const BOND_CRIT_ON_HIT: float = 0.25
const BOND_SPLASH: float = 0.35
const BOND_HEAVY_BONUS: float = 0.30
const BOND_REVIVES: int = 1

## 「命中之后提暴击」那一份的定义。见 [method crit_window]。
static var _crit_window: PBBuff = null


## 全队这一 tick 各自出一次手。**每个攻击者各自选目标，互不共享伤害池。**
##
## 「不共享」是 M3-a 那次改造的全部意义所在：整队一个池子就是单服务台排队，
## 而单服务台没有中间态。各打各的之后，射程外的敌人对某个攻击者不存在，
## 于是同一波敌人会被分批处理，战场上才可能长期有人。
##
## [param front] 是队伍最前面那个还活着的敌人的下标（[PBBattleSim] 的游标）——
## 全体敌人同速前进且按出场顺序排列，所以数组顺序天然就是距离顺序。
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
		# 死人不输出。M3.5-b 之前这一行不存在，因为没有人会死。
		# 冷却没转好也不出手（M4-b）—— 连续输出那条退化路径间隔是 1 tick，
		# 所以它每 tick 都过得了这道门，行为和离散化之前一模一样。
		if not attacker.alive or not attacker.ready_to_fire(tick):
			continue
		# **抬手**（M9-e）：冷却转好之后先起手，[member PBAttacker.windup_ticks]
		# 之后才结算。**要先确认射程内真有人** —— 对着空气抬手的话，
		# 抬完那一刻敌人正好走进来，伤害就会在没有起手的情况下落地，
		# 而那正是下面「打空了不进冷却」这条路留下的洞。
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
##
## **玩家点名的那个优先**（§02，M4-e）—— 但只在他还活着且够得着的时候。
## 够不着就照常自动选，不是站着不打：「我点了他，结果这个忍者整场发呆」
## 是玩家最不能接受的一种听话，理由见 [member PBAttacker.forced_target]。
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
	out.kills += _splash(attacker, enemy, enemies, damage, tick)
	_arm_crit(attacker, cfg, tick)
	out.kills += _hang_on_hit(attacker, enemy, crit, cfg, tick)


## 打出要害那一下把他自带的效果挂到目标身上
## （[member PBAttacker.on_hit_buffs]，M12-c2）。返回这一下挂死了几个。
##
## ## 三条
##
## **骑在暴击那个掷点上**，同 [method _bite_extra]：原版那几个各有自己的
## 概率（带土的扭曲攻击 10~15%），而另开一个骰子就是同一次出手掷两遍。
##
## **死了就不挂**（M7-d）：给一具尸体挂减速没有意义，
## 而且它会让「这一发定住了几个」虚高。
##
## **等级从大招那份上读**：[PBAttacker] 身上没有也不该有 `level`（铁律 5
## 那一条的同批决定，见 [member PBSkillCast.caster_level]），
## 而每个上场的人都带着一份按自己等级建的大招。拿不到就算 1 级。
static func _hang_on_hit(
	attacker: PBAttacker, enemy: PBEnemy, crit: bool, cfg: PBSimConfig, tick: int
) -> int:
	if not crit or not enemy.alive or attacker.on_hit_buffs.is_empty():
		return 0
	var level: int = 1
	if attacker.ultimate != null:
		level = attacker.ultimate.caster_level
	return 1 if PBSkillRules.apply_all_enemy(enemy, attacker.on_hit_buffs, level, cfg, tick) else 0


## 一次**敌人的攻击**落在一个忍者身上的唯一落点（M12-c2）。
## [param raw] 是没折算克制与护甲之前的那个数。
##
## ## 它和 [method land] 是对称的两半
##
## 那一头答「我方打敌人」，这一头答「敌人打我方」。在它之前，这件事
## 发生在两处（[PBBattleSim] 的近战、[method PBShotRules._hit_ally] 的子弹），
## 各写一遍「折算 → 记播报 → 扣血 → 记阵亡」—— 那还只是重复；
## 往后面接反弹（[member PBAttacker.reflect]）之后，
## **漏一处的表现是「被子弹打不反弹」**，而它不报错。
## 同 [method land] 顶上那条，也同重生判在 [method PBAttacker.take_damage] 里面。
##
## ## 反弹打死的那一个也要记账，而记账只有一个来源
##
## 反弹走 [method PBEnemy.take_damage]（易伤那一层在它里面）并在这里
## 把 `kills` 加上。放回调用方的话杀敌数就有了第二个来源 ——
## 同 [method PBBuffRules.advance_enemy] 顶上那条「周期伤害不在规则层当场扣血」。
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
	var hurt: float = PBStatRules.strike_damage(
		raw, element, target.defence, target.def_element, cfg
	)
	if book != null:
		book.hit(tick, -1 if source == null else source.slot, target.slot, hurt, true)
	if target.take_damage(hurt, tick, rng):
		out.allies_lost += 1
		if book != null:
			book.ally_down(tick, target.slot)
	_reflect(target, source, hurt, tick, book, out)


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


## 对**血还很多**的敌人那一笔追加伤害（B05）。没配就是 0。
##
## 判据看的是**这一下之前**的血量比 —— 打完再看的话，一记正好把人打到
## 半血以下的攻击会拿不到加成，而玩家读到的是「有时候触发有时候不」。
## 它和主伤害**加在一起**进 [method PBEnemy.take_damage]，不另打一下：
## 分开打的话易伤（M7-d）会乘两次，而且屏幕上一次普攻会飘出两个数。
static func _heavy_extra(attacker: PBAttacker, enemy: PBEnemy, damage: float) -> float:
	if attacker == null or attacker.heavy_bonus <= 0.0 or enemy.max_hp <= 0.0:
		return 0.0
	if enemy.hp / enemy.max_hp < HEAVY_THRESHOLD:
		return 0.0
	return damage * attacker.heavy_bonus


## 溅射（B15）。返回这一下顺带打死了几个。
##
## **不回头调 [method land]** —— 溅射不再触发溅射，见本类顶部。
## 也不记播报：一次普攻在屏幕上是一个数，而溅射打中的那几个会自己掉血、
## 由 [PBDamageWatch] 逐帧比出来（同「怪物死亡不记」那条，M6-j）。
## 打出要害那一下按目标生命百分比再追加的一笔（M12-c2：日向宁次的柔拳、
## 长十郎的骨拔）。没配就是 0。
##
## ## 它骑在暴击那个掷点上，不另掷一次
##
## 原版这两个各有自己的概率（18% / 15%），而「这一下打中了要害」
## **就是暴击在这个游戏里的语义** —— 另开一个骰子的话，同一次出手会掷两遍，
## 而 M10-c 那条「一个掷点」（[PBCritRules] 顶上）正是为了防这个。
## 这一步已经为闪避开了一个新掷点，那一个是非开不可的
## （挨打和出手不在同一条路上），这一个不是。
##
## **代价说清楚**：暴击光环会同时提高柔拳的触发率，而原版不会。
## 那是相关，不是 bug —— 归数值回归。
##
## ## 两个方向是互补的，所以是两个字段不是一个
##
## `bite_current` 按**还剩多少**算（越打越弱，适合开场那一下），
## `bite_lost` 按**已经掉了多少**算（越打越强，适合收尾）。
## 合成一个字段加一个方向开关的话，一个人就带不了两种 —— 而原版的
## 装备栏里两样都有。
##
## ## 加进主伤害，不另打一下
##
## 同 [method _heavy_extra]：分开打的话易伤（M7-d）会乘两次，
## 而且屏幕上一次普攻会飘出两个数。
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


static func _splash(
	attacker: PBAttacker,
	center: PBEnemy,
	enemies: Array[PBEnemy],
	damage: float,
	tick: int
) -> int:
	if attacker.splash_damage <= 0.0 or damage <= 0.0:
		return 0
	var each: float = damage * attacker.splash_damage
	var spot: Vector2 = center.pos()
	var killed: int = 0
	for other: PBEnemy in enemies:
		if other == center or not other.alive or not other.has_spawned(tick):
			continue
		if spot.distance_to(other.pos()) > SPLASH_RADIUS:
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
## ## 两条路：一发子弹，还是一股连续伤害
##
## [member PBAttacker.attack_speed] 大于 0 时这是**一次离散出手**：
## 一发打一个，远程放子弹（飞几 tick 才结算），近战当场见血。
## **不结算溢出** —— 一发打死了目标，多出来的伤害没有地方去，
## 那是「命中才结算」的代价，见 [PBProjectile] 顶部。
##
## 攻速为 0 时走的是 M3-a 之前那条**连续输出**的退化路径
## （[method PBAttacker.whole_field]），它必须与 [PBCombatRules] 的解析式
## 排队模型逐字段一致，而那个模型的前提之一就是**溢出无损转移**。
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
	# 暴击的**唯一掷点**（M10-c）。近战与子弹都走它，见 [PBCritRules]。
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
		# **花掉多少伤害，不是掉了多少血** —— 易伤（M7-d）让两者不再是同一个数，
		# 而这条退化路径正是对拍锚点（见 [method PBEnemy.damage_to_kill]）。
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
## 不结算溢出，是与单体型的实质区别：AOE 的价值写在命中数上
## （§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一个 AOE 攻击者在密集波里等于无限伤害。
##
## **范围型不发子弹**（M4-b）：一发子弹只追一个目标，而这里要同时打几个。
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
