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


## 一个单位的第 [param index] 个技能（M7-e）。**0 是大招，1.. 是他自己表里的。**
## 越界或者压根没有就返回 null。
##
## ## 为什么要一个统一的下标
##
## [member PBAttacker.ultimate] 和 [member PBAttacker.skills] 是两个字段
## （来源不同，见那里），但**指令卡、瞄准状态机、施放入口三处只该认一个数**。
## 各自去判「这一格是大招还是技能表里的」就是同一句话写三遍，
## 而漏改一处的表现是「第二个技能的按钮点了放出第一个」，不报错。
##
## ## 为什么在这里，不做成 [PBAttacker] 的方法
##
## 那个类已经贴着 gdlint 的 20 个公开方法上限。而这件事本来就是**规则**
## 不是**状态** —— 「第 0 个是大招」是一条约定，和「一发落在谁身上」同层。
static func cast_at(unit: PBAttacker, index: int) -> PBSkillCast:
	if unit == null or index < 0:
		return null
	if index == 0:
		return unit.ultimate
	var i: int = index - 1
	return unit.skills[i] if i < unit.skills.size() else null


## 这个人一共有几格技能（含大招那一格）。指令卡拿它决定画几个格子。
static func cast_count(unit: PBAttacker) -> int:
	return 0 if unit == null else 1 + unit.skills.size()


## 他这一刻放不放得出第 [param index] 个技能：活着 / 冷却转好 / 蓝够（§3.5）。
##
## **指令卡那一格的亮灰、和真正下达时的第一道门，读的是同一份。**
## 各写一份的话「按钮亮着但点了没反应」迟早出现，而它不报错 ——
## 玩家只会觉得这一格时灵时不灵。
static func can_cast(unit: PBAttacker, index: int, at_tick: int) -> bool:
	if unit == null or not unit.alive:
		return false
	var cast := cast_at(unit, index)
	if cast == null:
		return false
	return cast.is_ready(at_tick) and unit.can_pay(cast.skill.mp_cost)


## 这份技能的数据合不合法。返回空串表示没问题，否则是给人看的原因（M7-c）。
##
## 三条都是**静默生效**的错，所以必须在装表那一刻拦下来：
##
## - **`ALLY` 却打敌人 / `ENEMY` 却打自己人** —— 点谁和打谁在这两档上
##   不可能是两个方向，写反了不会报错，只会「点了一个队友然后他掉血」
## - **非 `GROUND` 却配了施法延迟** —— 见下
##
## ## 为什么施法延迟只对 `GROUND` 有意义
##
## 延迟存在的**全部理由**是 §02 的预判窗口（见 [PBSkill] 顶部），
## 而锁定单体的技能没有预判可言：目标跟着走，落点也跟着走。
## 允许非 0 的话，「飞行途中目标死了怎么办」「跑出射程怎么办」
## 两个问题要现在回答，而它们没有依据 —— 玩家已经拍了「单体技能不要飞行体」。
static func validate(skill: PBSkill) -> String:
	if skill == null:
		return "技能是空的"
	if skill.target == PBSkill.Target.ALLY and skill.affects != PBSkill.Party.ALLIES:
		return "target=ALLY 的技能必须 affects=ALLIES —— 点队友却打敌人说不通"
	if skill.target == PBSkill.Target.ENEMY and skill.affects != PBSkill.Party.ENEMIES:
		return "target=ENEMY 的技能必须 affects=ENEMIES —— 点敌人却打自己人说不通"
	if skill.target != PBSkill.Target.GROUND and skill.delay_ticks != 0:
		return "只有 GROUND 档能配施法延迟 —— 锁定目标的技能没有预判窗口"
	return _check_shot(skill)


## 子弹那几条（M8-b）。见 [member PBSkill.shot_cross_seconds]。
##
## ## 三条都是静默生效的错
##
## - **地面档配了飞行速度**：那一档的飞行时间是 [member PBSkill.delay_ticks]
##   （预判窗口），再来一个就是两把尺子 —— 而两者不会打架，只会有一个生效
## - **不挑目标的那一档配了飞行速度**：它没有目标可飞，那一发不知道往哪去
## - **子弹技能配了位置操纵与全场效果**：那五个字段
##   （[member PBSkill.gather] 那一批）是 §11 尾兽与 §09 功能档的词汇，
##   全部挂在地面档的大招上。子弹这一发只结算「打中的那一个」
##   （[method PBShotRules._hit_enemy]），配了**不会生效** ——
##   而「配了不生效」比「配不了」难查得多
static func _check_shot(skill: PBSkill) -> String:
	if skill.shot_cross_seconds <= 0.0:
		return ""
	if skill.target != PBSkill.Target.ALLY and skill.target != PBSkill.Target.ENEMY:
		return "只有锁定档（ALLY / ENEMY）能配飞行速度 —— 别的档没有目标可追"
	if skill.gather or skill.knockback > 0.0 or skill.reset_cooldowns:
		return "子弹技能不结算位置操纵与重置冷却 —— 那几项是地面档大招的词汇"
	if skill.slow_ticks > 0 or skill.buff_ticks > 0:
		return "子弹技能不结算全场效果（减速 / 全队增伤）—— 同上"
	return ""


## 一发**子弹**打在敌人身上（M8-b）。返回它有没有被这一下打死。
##
## 伤害由 [method PBShotRules._hit_enemy] 先结算（那本账在它手上），
## 这里只挂 [member PBSkill.on_hit] —— 拆成两半是因为「打死了几个」
## 必须只有一个来源。
static func apply_hit(
	enemy: PBEnemy, skill: PBSkill, level: int, cfg: PBSimConfig, tick: int
) -> bool:
	return _apply_all_enemy(enemy, skill.on_hit, level, cfg, tick)


## 一发**子弹**落在己方单位身上（M8-b，治疗那一类）。
static func apply_hit_ally(
	unit: PBAttacker, skill: PBSkill, level: int, cfg: PBSimConfig, tick: int
) -> void:
	_apply_all(unit, skill.on_hit, level, cfg, tick)


## 一发落地：范围内每个敌人各吃一份完整伤害，聚拢/击退的还会被挪位置。
## 返回这一下打死了几个 —— 调用方要把它加进 [PBCombatOutcome]。
##
## 和 [method PBBattleSim._strike_area] 一样**不结算溢出** —— 技能的价值
## 写在命中数上（§02 那条 `实际清怪效率 = AOE伤害 × 命中敌人数 × 属性系数`），
## 再让它吃溢出的话，一发范围技能在密集波里等于无限伤害。
static func land(
	cast: PBSkillCast, enemies: Array[PBEnemy], front: int, cfg: PBSimConfig, tick: int
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
		if enemy.take_damage(skill.damage, tick):
			kills += 1
			continue
		# **命中之后才挂 [member PBSkill.on_hit]**（M7-d）：给一具尸体
		# 挂减速没有意义，而且它会让「这一发定住了几个」虚高。
		if _apply_all_enemy(enemy, skill.on_hit, cast.caster_level, cfg, tick):
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


## 落在一个**锁定的己方单位**身上（[constant PBSkill.Target.ALLY]，M7-c）。
##
## ## 目标没了就空放，不崩也不改打别人
##
## 下达和落地之间隔着一个 tick（下达发生在 [method PBBattleSim._resolve_ultimates]
## 那一趟的后半，而落地的检查在**下一趟**的开头），那一 tick 里目标可能
## 被敌人打死。这时候正确的行为是**什么都不做**：
##
## - 改打别人 → 玩家点的那个人和实际受益的人不是同一个，而他不会知道
## - 硬治一具尸体 → [method PBAttacker.heal] 自己拦着（死人回不了血），
##   但那是它的兜底，不是这里可以不判的理由
##
## 「一发打空」和 [PBProjectile] 那条「目标死了子弹就消失，不改打别人」
## 是同一条规矩。
static func land_on_ally(
	cast: PBSkillCast, attackers: Array[PBAttacker], cfg: PBSimConfig, tick: int
) -> void:
	if cast.target_slot < 0 or cast.target_slot >= attackers.size():
		return
	var target: PBAttacker = attackers[cast.target_slot]
	if not target.is_targetable():
		return
	_apply_all(target, cast.skill.on_hit, cast.caster_level, cfg, tick)


## 落在一个**锁定的敌人**身上（[constant PBSkill.Target.ENEMY]，M8-b）。
## 返回这一下打死了几个（0 或 1）。
##
## 和 [method land_on_ally] 对称，连「目标没了就空放」那条也一样：
## 下达和落地之间隔着一个 tick，那一 tick 里他可能已经死了 ——
## 这时改打别人的话，玩家点的那个和实际挨打的那个不是同一个，而他不会知道。
##
## **这一档 M7-c 只做了合法形状，没有入口**；M8-b 接上操作层之后
## 它才真的落得到（火球术那一类）。
static func land_on_enemy(
	cast: PBSkillCast, enemies: Array[PBEnemy], cfg: PBSimConfig, tick: int
) -> int:
	if cast.target_slot < 0 or cast.target_slot >= enemies.size():
		return 0
	var enemy: PBEnemy = enemies[cast.target_slot]
	if not enemy.alive or not enemy.has_spawned(tick):
		return 0
	if enemy.take_damage(cast.skill.damage, tick):
		return 1
	return 1 if _apply_all_enemy(enemy, cast.skill.on_hit, cast.caster_level, cfg, tick) else 0


## 打全场：伤害发给**每一个已出场且还活着的敌人**，不看位置
## （[constant PBSkill.Target.NONE] + [constant PBSkill.Party.ENEMIES]，M7-c）。
## 返回打死了几个。
##
## 和 [method land] 的区别只有一条：那一个按半径圈人，这一个不圈 ——
## 所以 [member PBSkill.max_targets] 在这里仍然管用（0 = 不限）。
static func land_on_field(
	cast: PBSkillCast, enemies: Array[PBEnemy], front: int, cfg: PBSimConfig, tick: int
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
		hits += 1
		if enemy.take_damage(skill.damage, tick):
			kills += 1
			continue
		if _apply_all_enemy(enemy, skill.on_hit, cast.caster_level, cfg, tick):
			kills += 1
	return kills


## 下达那一刻挂给施法者自己的效果（[member PBSkill.on_self]，M7-c）。
static func apply_on_self(
	attacker: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int
) -> void:
	_apply_all(attacker, cast.skill.on_self, cast.caster_level, cfg, tick)


## 把一串效果挂到一个己方单位身上，数值按 [param level] 现算（决策 7）。
static func _apply_all(
	unit: PBAttacker, buffs: Array[PBBuff], level: int, cfg: PBSimConfig, tick: int
) -> void:
	for buff: PBBuff in buffs:
		apply_one(unit, buff, PBBuffRules.resolve(buff, level), cfg, tick)


## 把**一份**效果挂到一个己方单位身上。
##
## ## 瞬间的那一档不进效果袋
##
## §2.3 那条分界线：**瞬间效果改的是「量」（血、蓝），写进字段；
## 持续效果改的是「率」，只在用的那一刻问一次。** 所以瞬间档在这里当场
## 结算完就没了，而 [method PBBuffBag.add] 那条路是给有窗口的那两档走的
## —— 顺带它自己也拦着（`ticks <= 0` 直接返回），瞬间档的窗口正好是 0。
static func apply_one(
	unit: PBAttacker, buff: PBBuff, mods: Dictionary, cfg: PBSimConfig, tick: int
) -> void:
	if buff == null:
		return
	if buff.kind == PBBuff.Kind.INSTANT:
		unit.heal(float(mods.get(PBBuffRules.HEAL, 0.0)))
		unit.restore_mana(float(mods.get(PBBuffRules.MANA, 0.0)))
		return
	unit.buffs.add(buff, mods, tick, buff.duration_ticks(cfg), buff.period_ticks(cfg))


## 把一串效果挂到一个**敌人**身上。返回它有没有被这一串里的瞬间伤害打死。
static func _apply_all_enemy(
	enemy: PBEnemy, buffs: Array[PBBuff], level: int, cfg: PBSimConfig, tick: int
) -> bool:
	for buff: PBBuff in buffs:
		if apply_one_enemy(enemy, buff, PBBuffRules.resolve(buff, level), cfg, tick):
			return true
	return false


## 把**一份**效果挂到一个敌人身上（M7-d）。返回这一下有没有把它打死。
##
## ## 敌方的词汇表不是己方那张照搬
##
## 己方那一档（[method apply_one]）的瞬间效果是回血回蓝，
## 敌方这一档是[b]掉血[/b]（[constant PBBuffRules.HARM]）——
## 而掉血必须走 [method PBEnemy.take_damage]，因为「打死了几个」这本账
## 只有它数得对（易伤也在它里面乘）。所以两档的瞬间分支不可能共用一份实现。
##
## 持续那两档倒是完全一样（往袋子里放一份），可 [PBBuffBag] 收的是裸值、
## 两边的袋子是同一个类 —— 共用的那一半已经共用了。
static func apply_one_enemy(
	enemy: PBEnemy, buff: PBBuff, mods: Dictionary, cfg: PBSimConfig, tick: int
) -> bool:
	if buff == null:
		return false
	if buff.kind == PBBuff.Kind.INSTANT:
		var harm: float = float(mods.get(PBBuffRules.HARM, 0.0))
		return harm > 0.0 and enemy.take_damage(harm, tick)
	enemy.buffs.add(buff, mods, tick, buff.duration_ticks(cfg), buff.period_ticks(cfg))
	return false


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
		# **每一格都清，不只是大招那一格**（M7-e）。只清大招的话，
		# 这一条的强度会在角色配上技能的那一天悄悄缩水一半 ——
		# 它的价值本来就与队伍里技能的**总量**成正比（见上）。
		for i: int in cast_count(attacker):
			var other := cast_at(attacker, i)
			if other != null and other != caster and not other.is_pending():
				other.ready_at = tick
