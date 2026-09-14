class_name PBBattleSim
extends RefCounted
## 单波战斗的**逐 tick** 模拟。真游戏走这里。
##
## 与 [PBCombatRules] 的解析式排队模型**语义保持一致，好让两者能对拍**：
## 不传 [param attackers] 时整队折成一个覆盖全场的单体攻击者（[method PBAttacker.whole_field]），
## 结果要与闭式解逐位相同。`max_hp == 0` 的攻击者敌人看不见，这条约定让锚点不用加配置开关。
##
## ## 每个 tick 干七件事，顺序不能换
##
## 1. **技能** —— 先结算落地的，再下达新的，见 [method _resolve_ultimates]
## 2. **己方跑动** —— 射程内没目标就往前压，见 [method _move_attackers]
## 3. **定攻击目标** —— 每人一个，画线与开火共用一份，见 [method _aim_targets]
## 4. **己方分配伤害** —— 每个攻击者各自在射程内选目标，见 [method _deal_damage]
## 5. **敌人还手** —— 咬住射程内的己方单位，见 [method _enemies_attack]
## 6. **推进位置** —— 先打后走（抵达那一 tick 仍然可以被打死，与排队模型同一条边界）；
##    咬住了人的不动，没咬住的扑向最近的活忍者，全死光了才走基地
## 7. **防挤** —— 把重合的单位推开，见 [method _separate]
##
## 己方先打是有意的：刚被打死的敌人不该在同一 tick 还手。
##
## 敌人咬住射程内最近的己方单位并停止推进；己方会被打死，死了不再输出也不再放技能。
## **每波开波全员满血复活**（§03A）。

## 同屏最多几发子弹。同时在飞的远不到 10 发，64 宽到不用再想；池子按上限一次建满（§14）。
const SHOT_CAPACITY: int = 64

## 安全阀：单波最多跑这么多 tick。
##
## 正常情况下战斗必定结束（敌人每 tick 都在前进，迟早抵达基地）。
## 这个上限是防「速度配成 0」之类的配置错误把批量模拟挂死 ——
## 死循环在跑几万局的场景里表现为「卡住不动」，极难定位。
const MAX_TICKS: int = 20000

## 战斗播报（§02）。**默认 null = 一个字都不记**（批量扫描一局几万 tick）。见 [PBBattleLog]。
var log_to: PBBattleLog = null

var _cfg: PBSimConfig
var _wave: PBWave
var _enemies: Array[PBEnemy] = []
var _outcome: PBCombatOutcome

## 本波的己方攻击者，按出战席顺序。**遍历顺序固定，不排序、不打乱** ——
## 两个攻击者同 tick 打同一个目标时，谁先打决定了溢出伤害归谁，
## 顺序一变结果就变，而那种差异在批量统计里只表现为「波次悄悄偏了一点」。
var _attackers: Array[PBAttacker] = []

## 一个敌人漏进基地扣多少血，防御科技减伤已经算进去了。
var _leak_damage: float = 0.0

## 飞行中的子弹。**一次建满、之后只改字段**，和敌人池同一条规矩（§14）。
var _shots: Array[PBProjectile] = []

## 子弹每 tick 飞多远。由 `projectile_cross_seconds` 反推，不是新拍的参数。
var _shot_speed: float = 0.0

var _enemy_speed: float = 0.0
var _tick: int = 0

## 大招落点策略（§02 的双端差异）。从配置抄一份，一波之内不变。
var _aim_policy: PBAimRules.Policy = PBAimRules.Policy.AUTO

## 手动档最多攒多少 tick 就得放。由 `ultimate_max_hold_seconds` 换算。
var _max_hold_ticks: int = 0

## 场上的减速（一尾 / 五尾那一类）。
##
## **是「场」的属性，不是单位的属性**：它要作用于还没出场的敌人，存到每个敌人身上的话
## 减速期间新出场的敌人会漏掉它。个体减速在敌人的效果袋里，**两者相乘**（[method PBEnemy._speed_mult]）。
## **后来者覆盖前者** —— 一局只有一只尾兽、冷却 75 秒，两次同类效果不会重叠；真会重叠时再定怎么叠。
var _slow_scale: float = 1.0
var _slow_until: int = -1

## 玩家下了但还没放出去的施法指令。**每 tick 推进之前一次放完**，见 [PBSkillOrders]。
var _orders: PBSkillOrders = PBSkillOrders.new()

## 队伍最前面那个还活着的敌人在 [member _enemies] 里的下标。
##
## 全体敌人同速前进、且按出场顺序排列，所以**数组顺序天然就是距离顺序** ——
## 不需要每 tick 排序找目标，从这个游标往后扫就行。
var _front: int = 0

## 战斗内部的掷骰流（暴击、闪避、致盲）。**null = 不掷**。
## 是 [method PBRngStreams.battle_rng] 派生的本波专属流，不是 [member PBRngStreams.combat]。
var _crit_rng: RandomNumberGenerator = null


## [param attackers] 为空时走退化路径：整队折成一个覆盖全场的单体攻击者，[param dps] 就是整队 DPS。
## 给了攻击者列表时 [param dps] 只是报数用的汇总量。[param crit_rng] 见 [member _crit_rng]。
func _init(
	wave: PBWave,
	dps: float,
	def_reduction: float,
	cfg: PBSimConfig,
	attackers: Array[PBAttacker] = [],
	crit_rng: RandomNumberGenerator = null
) -> void:
	_crit_rng = crit_rng
	_cfg = cfg
	_wave = wave
	_outcome = PBCombatOutcome.new()
	_aim_policy = cfg.aim_policy
	_max_hold_ticks = int(round(cfg.ultimate_max_hold_seconds * float(cfg.tick_rate)))
	_attackers = attackers
	if _attackers.is_empty():
		var solo: Array[PBAttacker] = [PBAttacker.whole_field(dps, cfg.field_diagonal())]
		_attackers = solo
	for attacker: PBAttacker in _attackers:
		attacker.prime(cfg.tick_rate, cfg)
		# 召唤物的位子开波是**空着**的，走 `revive()` 的话它会满血站在场上。
		if attacker.summoned:
			PBSummonRules.dismiss(attacker)
			continue
		# 开波满血（§03A）。和大招的冷却一样，攻击者对象会跨波、跨探测复用，
		# 不重置的话上一场的残血会漏进这一场，表现为「同一支队伍越探越弱」。
		attacker.revive()
		# 技能对象跨波、跨探测复用，**每一格都要清**，漏一格就是「某个技能开波就是灰的」。
		for i: int in PBSkillRules.cast_count(attacker):
			var cast := PBSkillRules.cast_at(attacker, i)
			if cast != null:
				cast.reset()
	_orders.reset(_attackers.size())

	var leak_mult: float = cfg.boss_leak_mult if wave.is_boss() else 1.0
	_leak_damage = wave.atk_each * leak_mult * (1.0 - clampf(def_reduction, 0.0, 0.95))

	# 速度由 march_seconds 反推：那个参数的含义本来就是「走完全场要多久」。
	# 这里没有引入新的拍脑袋参数，只是换了个表达。
	var march_ticks: float = maxf(cfg.march_seconds, 0.001) * float(cfg.tick_rate)
	_enemy_speed = cfg.field_length / march_ticks
	# 子弹速度同理由「飞完全场要几秒」反推。0 秒 = 瞬时命中。
	if cfg.projectile_cross_seconds > 0.0:
		_shot_speed = cfg.field_length / (cfg.projectile_cross_seconds * float(cfg.tick_rate))

	_shots.resize(SHOT_CAPACITY)
	for i: int in SHOT_CAPACITY:
		_shots[i] = PBProjectile.new()

	_spawn_all(wave, cfg)


## 推进一个 tick。战斗已结束时什么都不做。
func step() -> void:
	if is_finished():
		return
	# **玩家攒着的指令排在推进之前**：「排队再放」和「当场放」的 `lands_at` 与冷却因此逐位相同。
	_orders.flush(_attackers, _cfg, _tick, log_to)
	_tick += 1
	_resolve_ultimates()
	# 到点的召唤物散场。**排在技能落地之后**：本体同一 tick 放的新一发能用上刚空出来的位子。
	PBSummonRules.expire(_attackers, _tick)
	# **排在技能落地之后**：这一 tick 挂上的 buff 对这一 tick 的出手就生效。
	_advance_buffs()
	_move_attackers()
	# **排在跑动之后**：目标是「他站定之后打得到谁」。
	_aim_targets()
	# **飞行结算排在出手之前**：这一 tick 发出去的子弹不该同一 tick 落地，否则飞行时间等于 0。
	_advance_shots()
	_deal_damage()
	_enemies_attack()
	_advance_and_leak()
	# **排在所有会死人的阶段之后**：挨打、子弹、自身掉血死的人同一 tick 放掉阵亡技能。
	_fire_death_casts()
	_separate()


## 一路跑到战斗结束，返回结算结果。批量模拟走这个入口。
func run_to_end() -> PBCombatOutcome:
	while not is_finished() and _tick < MAX_TICKS:
		step()
	return result()


func is_finished() -> bool:
	return _front >= _enemies.size()


## 结算结果。战斗没结束也能取，拿到的是「到目前为止」的快照。
func result() -> PBCombatOutcome:
	_outcome.cleared = _outcome.leaked == 0 and is_finished()
	_outcome.ticks = _tick
	_outcome.battle_seconds = float(_tick) / float(_cfg.tick_rate)
	return _outcome


## 全部敌人，含还没出场和已经死掉的。**渲染层只读，不要改。**
func enemies() -> Array[PBEnemy]:
	return _enemies


## 全部己方攻击者，含已经阵亡的。**渲染层只读，不要改。**
func attackers() -> Array[PBAttacker]:
	return _attackers


## 飞行中的子弹，含已经回池的（`alive` 为 false）。**渲染层只读，不要改。**
func shots() -> Array[PBProjectile]:
	return _shots


func current_tick() -> int:
	return _tick


## 出场时刻已到、且还活着的敌人 —— 渲染层要画的就是这些。
func active_enemies() -> Array[PBEnemy]:
	var out: Array[PBEnemy] = []
	for enemy: PBEnemy in _enemies:
		if enemy.is_active(_tick):
			out.append(enemy)
	return out


## 一次性把整波敌人建好。规则在 [PBSpawnRules]，这里只记进 [member _enemies]。
func _spawn_all(wave: PBWave, cfg: PBSimConfig) -> void:
	PBSpawnRules.fill(_enemies, wave, cfg, _enemy_speed, _shot_speed)


## 大招：先结算落地的，再下达新的。**顺序不能反。**
##
## 反过来的话，同一 tick 下达的大招会在下达的那一瞬间就落地，
## 施法延迟等于 0 —— 而那个延迟正是 §02 分层验收的全部依据
## （见 [PBSkill] 顶部）。
func _resolve_ultimates() -> void:
	for attacker: PBAttacker in _attackers:
		# **每一格都要过一遍**：只扫大招那一格的话玩家手放的技能永远落不了地，而按钮那边一切正常。
		for i: int in PBSkillRules.cast_count(attacker):
			var cast := PBSkillRules.cast_at(attacker, i)
			# 已经下达的照样落地，哪怕施法者中途死了 —— 技能已经出手了。
			# 那是 §02 施法延迟的直接后果，也是「预判」这件事的对称代价。
			if cast != null and cast.is_pending() and _tick >= cast.lands_at:
				_land_skill(attacker, cast)
	for attacker: PBAttacker in _attackers:
		attacker.regen_mana()
	for attacker: PBAttacker in _attackers:
		var cast: PBSkillCast = attacker.ultimate
		if cast == null or not attacker.alive or not cast.is_ready(_tick):
			continue
		# **自动档只放地面技能**：[PBAimRules] 答的是「往哪块地放」，不知道该治谁、该点谁。
		if cast.skill.target != PBSkill.Target.GROUND:
			continue
		# 第二道门槛：冷却转好了还得有蓝。
		if not attacker.can_pay(cast.skill.mp_cost):
			continue
		var spot := PBAimRules.pick_spot(
			_aim_policy,
			_enemies,
			_tick,
			cast.skill,
			_tick - cast.ready_at,
			_cfg.ultimate_min_targets,
			_cfg.ultimate_hold_targets,
			_max_hold_ticks
		)
		if PBSkillCast.is_spot(spot):
			_order(attacker, spot)
	_skip_dead()


## 玩家亲手下达一发地面技能（§02）。**收下了返回 true，下一个 tick 才放出去**（见 [PBSkillOrders]）。
##
## 手动有自己的入口：自动档那一支（[method _resolve_ultimates]）要判断值不值得放，
## 玩家点了就是要放。门槛（活着 / 冷却好了 / 蓝够）**共用一份**，否则「按钮亮着点了没反应」迟早出现。
func cast_skill(attacker: PBAttacker, spot: Vector2, index: int = 0) -> bool:
	return _orders.place(_attackers, _attackers.find(attacker), index, spot, -1, _tick)


## 玩家亲手把一发技能放在**一个队友**身上（[constant PBSkill.Target.ALLY]）。
## 目标要活着；下达之后他再死掉，那一发落地时空放（[method PBSkillRules.land_on_ally]）。
func cast_skill_on(attacker: PBAttacker, target: PBAttacker, index: int = 0) -> bool:
	var slot: int = -1 if target == null else target.slot
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, slot, _tick
	)


## 玩家亲手把一发技能放在**一个敌人**身上（[constant PBSkill.Target.ENEMY]）。
func cast_skill_at(attacker: PBAttacker, enemy: PBEnemy, index: int = 0) -> bool:
	var slot: int = -1 if enemy == null else enemy.slot
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, slot, _tick
	)


## 玩家亲手放一发**不需要挑目标**的技能（[constant PBSkill.Target.NONE]）。
func cast_skill_now(attacker: PBAttacker, index: int = 0) -> bool:
	return _orders.place(
		_attackers, _attackers.find(attacker), index, PBSkillCast.NO_SPOT, -1, _tick
	)


## 收回这个人手上那条还没放出去的指令。
func cancel_order(attacker: PBAttacker) -> void:
	_orders.cancel(_attackers.find(attacker))


## 这个人手上攒着的是第几格技能（-1 = 没有）。指令卡拿它显示「已下令」。
func order_of(attacker: PBAttacker) -> int:
	return _orders.index_of(_attackers.find(attacker))


## 攒着的全部指令，下标和 [method attackers] 一一对应。**渲染层只读，不要改。**
func orders() -> PBSkillOrders:
	return _orders


## 这个人现在放不放得出第 [param index] 个技能（0 = 大招）。
## **指令卡那一格的亮/灰读的就是它。** 规则在 [method PBSkillRules.can_cast]。
##
## **它不看「手上攒着一条没放出去的指令」** —— 那是操作层的事
## （指令卡把那一格写成「已下令」，见 [method PBSkillBar.show_on]）。
## 混进来的话，一个攒着指令的人会被判成「放不出」，而放出去那一遍
## 恰恰要再问一次这个函数。
func can_cast(attacker: PBAttacker, index: int = 0) -> bool:
	return PBSkillRules.can_cast(attacker, index, _tick)


## 自动档下达一发地面技能。**不进指令队列** —— 队列是「玩家下的令」，
## 而这一支是 [PBAimRules] 替玩家挑的落点，本来就发生在 tick 里面。
## 下达之后那三件事两条路共用（[method PBSkillOrders.issue]）。
func _order(attacker: PBAttacker, spot: Vector2) -> void:
	var cast: PBSkillCast = attacker.ultimate
	cast.cast(spot, _tick)
	PBSkillOrders.issue(attacker, cast, _cfg, _tick, log_to)


## 一发技能落地：圈人、挂效果、位置操纵全部交给 [PBSkillRules]。
## 本类只留跟「场」有关的三件事：减速（见 [member _slow_scale]）、记账、转入冷却。
##
## **落地的形状由 [member PBSkill.target] 决定**：地面档按半径圈人，锁定档只找那一个，
## 不挑目标的打全场。全场效果（减速 / 全队增伤 / 重置冷却）三档共用。
func _land_skill(attacker: PBAttacker, cast: PBSkillCast) -> void:
	var skill := cast.skill
	# 召唤物跟着**下达**而不是命中（同扣蓝），而且**排在子弹那条提前 return 之前** ——
	# 召唤技能恰好是子弹技能时，排在后面的话一只都不会出现。
	PBSummonRules.raise_from(_attackers, attacker, skill, _tick, _cfg)
	# **子弹技能：这一刻只是出膛**，伤害与 `on_hit` 等飞到才结算。冷却从出膛算起
	# （子弹追着目标走，没有「落点已定、还没结算」的预判窗口）。
	if skill.shot_cross_seconds > 0.0:
		_launch_skill(attacker, cast)
		cast.land(_tick)
		return
	match skill.target:
		PBSkill.Target.ALLY:
			PBSkillRules.land_on_ally(cast, _attackers, _cfg, _tick)
		PBSkill.Target.NONE:
			if skill.affects == PBSkill.Party.ENEMIES:
				_outcome.kills += PBSkillRules.land_on_field(
					cast, _enemies, _front, _cfg, _tick
				)
			else:
				PBSkillRules.land_around_allies(cast, attacker.pos, _attackers, _cfg, _tick)
		PBSkill.Target.ENEMY:
			_outcome.kills += PBSkillRules.land_on_enemy(cast, _enemies, _cfg, _tick)
		_:
			if skill.affects == PBSkill.Party.ALLIES:
				PBSkillRules.land_around_allies(cast, cast.spot, _attackers, _cfg, _tick)
			else:
				_outcome.kills += PBSkillRules.land(cast, _enemies, _front, _cfg, _tick)
	if skill.slow_ticks > 0 and skill.slow_scale < 1.0:
		_slow_scale = skill.slow_scale
		_slow_until = _tick + skill.slow_ticks
	PBSkillRules.apply_team_buff(skill, _attackers, _tick)
	PBSkillRules.reset_other_cooldowns(skill, cast, _attackers, _tick)
	cast.land(_tick)


## 刚倒下的人把阵亡技能放掉（[member PBAttacker.death_casts]）。落点是尸体。
##
## 走 [method _land_skill]，和手动施法同一条路：伤害按他的战力、打死的怪照常记账、
## 回血圈照样按半径圈人。不进 [PBSkillOrders]，也不查冷却和蓝 —— 死人没有这两样。
func _fire_death_casts() -> void:
	for attacker: PBAttacker in _attackers:
		if not attacker.death_pending:
			continue
		attacker.death_pending = false
		for cast: PBSkillCast in attacker.death_casts:
			cast.spot = attacker.pos
			if log_to != null:
				log_to.ultimate(_tick, attacker.slot, cast.skill.affects == PBSkill.Party.ALLIES)
			_land_skill(attacker, cast)
	_skip_dead()


## 一发子弹技能出膛。池子满了或目标已经不在名单里就当空放 ——
## **不退回「瞬间结算」**，否则同一个技能在池子满的时候变成另一种技能。
func _launch_skill(attacker: PBAttacker, cast: PBSkillCast) -> void:
	var shot := PBShotRules.free_shot(_shots)
	if shot == null:
		return
	var skill := cast.skill
	var at_ally: bool = skill.target == PBSkill.Target.ALLY
	var limit: int = _attackers.size() if at_ally else _enemies.size()
	if cast.target_slot < 0 or cast.target_slot >= limit:
		return
	# 速度由「飞完全场要几秒」反推，和普攻子弹同一条换算
	# （[member PBSimConfig.projectile_cross_seconds]）—— 两处各拍一个速度单位
	# 的话，「技能子弹比普攻快多少」会变成一个没人说得清的数。
	var per_tick: float = _cfg.field_length / maxf(
		skill.shot_cross_seconds * float(_cfg.tick_rate), 1.0
	)
	shot.launch(
		attacker.pos,
		cast.target_slot,
		skill.damage,
		per_tick,
		at_ally,
		skill.element,
		attacker.slot,
		skill,
		cast.caster_level
	)


## 这一 tick 敌人走多快。1.0 是正常速度，减速生效期间小于 1。
func _speed_scale() -> float:
	return _slow_scale if _tick <= _slow_until else 1.0


## 推进两边身上挂着的效果一个 tick。**怎么推进在 [PBBuffRules]**，这里只留记账：
## 周期伤害打死的敌人要计进 [member PBCombatOutcome.kills]，规则层当场扣血的话杀敌数就有了第二个来源。
## 敌人那一趟从 [member _front] 起扫、碰到没出场的就停（数组按出场顺序排）。
func _advance_buffs() -> void:
	for attacker: PBAttacker in _attackers:
		var drain: float = PBBuffRules.advance_ally(attacker, _tick)
		# 自身掉血（地之咒印）。扣血与阵亡记账走和挨打同一个落点。
		if drain > 0.0 and attacker.alive:
			PBStrikeRules.wound_ally(attacker, drain, _cfg, _tick, null, log_to, _outcome)
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive:
			continue
		var harm: float = PBBuffRules.advance_enemy(enemy, _tick)
		if harm > 0.0 and enemy.take_damage(harm, _tick):
			_outcome.kills += 1
	_skip_dead()


## 把这一 tick 的伤害打出去。规则在 [PBStrikeRules]，这里只留调用时机和游标维护。
func _deal_damage() -> void:
	PBStrikeRules.deal(
		_attackers, _enemies, _shots, _front, _cfg, _tick, _crit_rng, log_to, _outcome
	)
	_skip_dead()


## 子弹飞一个 tick，够到目标就结算（[PBShotRules]）。目标死了子弹就消失，见 [PBProjectile] 顶部。
func _advance_shots() -> void:
	PBShotRules.advance(
		_shots, _enemies, _attackers, _cfg, _tick, log_to, _outcome, _crit_rng
	)
	_skip_dead()


## 己方跑动（§02 / §03A）。**射程内没目标就往前压，有目标就站住开火。**
##
## 不是「一路跑向最近的敌人」：那会让所有人挤到最前面接敌，§02 的射程梯度
## （「场上稳定有人」的唯一来源）就没了。跑动拴在 [member PBAttacker.leash] 上，只在打不着时往前。
##
## 怎么挪在 [PBMoveRules]，这里只管挑目标和分支。三条互斥状态：够得着就站住、够不着就靠过去、
## 场上没有活敌人就走回自己的位置（不退的话下一波开波的阵型就不是玩家排的那个了）。
func _move_attackers() -> void:
	for attacker: PBAttacker in _attackers:
		if not attacker.alive or attacker.move_speed <= 0.0:
			continue
		var target := _nearest_enemy(attacker)
		if target == null:
			attacker.pos = attacker.pos.move_toward(attacker.home, attacker.move_speed)
			continue
		if attacker.can_reach(target.pos()):
			continue
		var leash: float = PBMoveRules.leash_for(
			attacker, target, _named_target(attacker), _cfg
		)
		if attacker.shot_speed > 0.0:
			PBMoveRules.press_forward(attacker, target, leash)
		else:
			PBMoveRules.close_in(attacker, target, leash)


## 离 [param attacker] 最近的、已出场且活着的敌人。没有就返回 null。
##
## **离我最近，不是打得最深**：挑最深的话近战会越过身边的敌人去追另一条泳道的目标。
##
## **先在自己守得住的范围里挑**（`home` 半径 `leash + reach`），挑不到才退回全场最近 ——
## 自己那一格还有活可干就不跑去帮别人，那正是射程梯度要的站位。
## `leash + reach` **必须和 [method PBMoveRules.leash_for] 的门槛是同一个数**：分叉的话会挑中
## 一个绳子不肯为它放长的目标，贴在绳边整波一发不放。退回全场最近那一档必须留着，
## 否则谁都够不着时全队站着挨打。
func _nearest_enemy(attacker: PBAttacker) -> PBEnemy:
	# 玩家点名了就朝那个走 —— **哪怕现在够不着**，那正是「点他」的意思。
	var named := _named_target(attacker)
	if named != null:
		return named
	var best: PBEnemy = null
	var best_gap: float = 0.0
	# **守得住的那个优先。** 见下面那段注释。
	var post: PBEnemy = null
	var post_gap: float = 0.0
	var post_reach: float = attacker.leash + attacker.reach
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			# 后面的出场更晚，这一 tick 不会再有目标了。
			break
		if not enemy.alive:
			continue
		var gap: float = attacker.pos.distance_to(enemy.pos())
		if best == null or gap < best_gap:
			best = enemy
			best_gap = gap
		if attacker.home.distance_to(enemy.pos()) <= post_reach:
			if post == null or gap < post_gap:
				post = enemy
				post_gap = gap
	return post if post != null else best


## 玩家点名的那个敌人，**这一 tick 还算不算数**（活着、已出场）。不算就 null。
##
## 三处读它：走位（[method _nearest_enemy]）、开火（[method PBStrikeRules.first_reachable]）、
## 画线（[method _aim_targets]）。抄成三份的话「点名什么时候失效」会有三个答案，
## 而分叉的表现是**线、脚、枪各指一个人**。
func _named_target(attacker: PBAttacker) -> PBEnemy:
	return PBStrikeRules.named_target(attacker, _enemies, _tick)


## 每人这一 tick 的攻击目标，存进 [member PBAttacker.aim_at]。
##
## 三档取第一个有的：**有效点名 → 射程内最靠近基地的 → 全场最近的**。第一档不问射程 ——
## 点了一个还没走到的人，意思是「去打他」。
##
## **它不决定伤害打给谁**：开火仍走 [method PBStrikeRules.first_reachable]，两个答案可以不同
## （线指着要去打的那个，手上打着路过的那个）。**单独一遍**，搭在开火那一遍上会继承冷却与射程门槛。
func _aim_targets() -> void:
	for attacker: PBAttacker in _attackers:
		_aim_one(attacker)


func _aim_one(attacker: PBAttacker) -> void:
	var mark: PBEnemy = null
	if attacker.alive:
		mark = _named_target(attacker)
		if mark == null:
			mark = PBStrikeRules.first_reachable(attacker, _enemies, _front, _tick)
		if mark == null:
			mark = _nearest_enemy(attacker)
	attacker.aim_at = -1 if mark == null else mark.slot


## 玩家点名一个敌人（[param slot] 为 -1 = 交回自动选敌）。**点名的唯一入口。**
##
## ## 为什么不能让渲染层自己写那个字段
##
## 因为点名要**立刻**改变「他要打谁」，而那件事由 [method _aim_one] 算。
## 只写 [member PBAttacker.forced_target] 的话，绿线要等
## [method _aim_targets] 下一次跑才切过去 —— 而**暂停时那一遍不跑**。
## 于是玩家在暂停下点了一个敌人，画面上一动不动，直到他取消暂停。
##
## §02 特意允许暂停下操作，那一刻的即时反馈正是这两步操作的全部意义
## （不然玩家无从知道自己那一下点中了没有）。
func name_target(attacker: PBAttacker, slot: int) -> void:
	if attacker == null:
		return
	attacker.forced_target = slot
	_aim_one(attacker)


## 防挤：把重合的单位推开。**两边都做**，实现在 [PBCrowdRules]。
func _separate() -> void:
	PBCrowdRules.separate_enemies(
		_enemies, _front, _tick, _cfg.unit_min_gap, _cfg.field_height
	)
	PBCrowdRules.separate_attackers(_attackers, _cfg.unit_min_gap)


## 敌人还手（§03A）。**咬住射程内最近的己方单位，并停止推进。**
##
## 咬住了就不走：忍者是一堵**墙**，漏怪意味着墙破了。边打边走的话防御和血量影响不了
## 「敌人到没到基地」，坦克、前排、站位全部贬值。
##
## 目标是**离我最近的**，不是血最少的：集火 AI 会让站位失去意义，挑最近的之后「谁站前排」有后果。
func _enemies_attack() -> void:
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		enemy.engaged = false
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive or enemy.damage_per_shot <= 0.0:
			continue
		var target := PBTargetRules.nearest_defender(_attackers, enemy)
		if target == null:
			continue
		# **远近都咬住**：远程边走边射的话会从活着的忍者身边溜过去扣基地血，
		# 而规则是「场上忍者全部死亡才走向基地」。
		#
		# 终止性靠敌人伤害恒大于 0（[method PBStatRules.strike_damage] 断言护甲不可能全免）
		# 且忍者不回血，所以咬住的一方必定在有限时间内清完场。
		# 「咬住了就不走」和出手冷却**不绑在一起**，否则近战会在两次出手之间一步步往前挪。
		enemy.engaged = true
		if not enemy.ready_to_fire(_tick):
			continue
		# 抬手，同己方那一支 —— 这里目标已经找到了，不用再问一遍。
		if enemy.begin_swing(_tick):
			continue
		enemy.on_fired(_tick)
		# 致盲：手抬了、冷却也走了，只是这一下打空。**排在近战/远程分岔之前**。
		# 和晕眩不同档：晕眩连手都抬不起来（[method PBEnemy.ready_to_fire]）。
		if PBBuffRules.misses(enemy, _tick, _crit_rng):
			continue
		# 远程的那一份走弹道，减伤与克制在命中时才折算。
		if enemy.shot_speed > 0.0:
			var shot := PBShotRules.free_shot(_shots)
			if shot != null:
				shot.launch(
					enemy.pos(),
					_attackers.find(target),
					enemy.damage_per_shot,
					enemy.shot_speed,
					true,
					enemy.element,
					enemy.slot
				)
			continue
		# 折算、播报、扣血、阵亡、反弹全在那一处，子弹那一路调的是同一个。
		PBStrikeRules.hurt_ally(
			target,
			enemy,
			enemy.damage_per_shot,
			enemy.element,
			_cfg,
			_tick,
			_crit_rng,
			log_to,
			_outcome
		)


## 全体前进。**场上还有活忍者就扑向最近的那个，全死光了才走基地。**
##
## 不是「一直往基地走、路过谁打谁」：那样一条没人站的泳道就是一条高速公路，
## 忍者还站着基地已经在掉血。扑向最近的活人之后，玩家摆的阵型就是敌人的行军路线。
##
## 扑人那一支**结构上不可能漏怪**，走没有返回值的 [method PBEnemy.march_to]；
## 只有「场上一个活人都没有」那一支可能抵达基地。
func _advance_and_leak() -> void:
	var speed_scale: float = _speed_scale()
	for i: int in range(_front, _enemies.size()):
		var enemy: PBEnemy = _enemies[i]
		if not enemy.has_spawned(_tick):
			break
		if not enemy.alive:
			continue
		var prey := PBTargetRules.nearest_ally(_attackers, enemy)
		if prey != null:
			# **围到自己那一格上去**，否则先到的堵死近侧、后面的垫成长队。咬住了的照样走这一条 ——
			# 那个点在忍者身前，越不过他（见 [method PBEnemy.siege_to]）。
			enemy.siege_to(
				PBCrowdRules.siege_spot(
					prey.pos, enemy.slot, enemy.reach, _cfg.field_height
				),
				speed_scale,
				_tick
			)
			continue
		# 场上一个活人都没有了才走基地。
		# 这里不用再判 `engaged` —— 没有可咬的人，它这一 tick 就不可能咬着
		# （[method _enemies_attack] 每 tick 从 false 重算）。
		if enemy.advance(speed_scale, _tick):
			enemy.alive = false
			_outcome.leaked += 1
			_outcome.base_damage += _leak_damage
			if log_to != null:
				log_to.base_hit(_tick, _leak_damage)
	_skip_dead()


## 把游标推到下一个还活着的敌人。已经死掉或漏掉的不再参与任何计算。
func _skip_dead() -> void:
	while _front < _enemies.size() and not _enemies[_front].alive:
		_front += 1
