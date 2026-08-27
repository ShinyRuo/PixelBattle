class_name PBCombatRules
extends RefCounted
## 单波战斗的结算。施工策划案 §03 的伤害系数 + §04 的波次参数。
##
## ## 这是一个解析式近似，不是真战斗
##
## M-1 要跑上万局来校准 `GROWTH`，逐单位逐 tick 模拟跑不动
## （48 单位 × 800 tick × 120 波 × 上万局 ≈ 千亿次更新）。
## 所以这里用一个**排队模型**代替：敌人按出场顺序排队，队伍以固定 DPS 推进，
## 每个敌人要么在抵达基地前被清掉，要么漏过去扣基地血。
##
## 时长仍然对齐到整 tick（§14 铁律：定帧 20 tick/s），
## 这样 M0 换成真 tick 模拟时两边的数字可以直接对照。
##
## ## 这个近似丢掉了什么（用到结论时要记得）
##
## 1. **AOE 与单体输出没有区别** —— 队列是单目标的。所以 §04 那条验收
##    「纯 AOE 阵容在精英波吃力、纯单体在潮水波吃力」**M-1 回答不了，留给 M0**。
##    路线图列的四个问题都不依赖它，是有意的取舍。
## 2. **没有波内动态** —— 前排先死导致输出下降、聚拢大招把敌人拖成一堆，
##    这些都不在模型里。
## 3. **敌人不还手** —— 只有漏怪才伤基地，己方单位不会被打死。


## 结算一波。
##
## [param dps] 是己方对本波的**有效**每秒伤害，属性克制已经算进去了
## （见 [method team_dps]）。[param def_reduction] 是防御科技的减伤比例，0–1。
static func resolve(
	wave: PBWave, dps: float, def_reduction: float, cfg: PBSimConfig
) -> PBCombatOutcome:
	var out := PBCombatOutcome.new()
	var leak_mult: float = cfg.boss_leak_mult if wave.is_boss() else 1.0
	var leak_damage: float = wave.atk_each * leak_mult * (1.0 - clampf(def_reduction, 0.0, 0.95))

	# DPS 为零是合法状态（全员派去做任务、或阵容全被克到近乎无伤）。
	# 不当成除零错误处理 —— 它就是「这波全漏」，是玩家真会遇到的局面。
	if dps <= 0.0:
		out.cleared = false
		out.leaked = wave.count
		out.base_damage = leak_damage * float(wave.count)
		out.battle_seconds = _spawn_time(wave.count - 1, wave.count, cfg) + cfg.march_seconds
		out.ticks = _to_ticks(out.battle_seconds, cfg)
		return out

	var seconds_per_kill: float = wave.hp_each / dps
	var clock: float = 0.0

	for i: int in wave.count:
		var spawned_at: float = _spawn_time(i, wave.count, cfg)
		var arrives_at: float = spawned_at + cfg.march_seconds
		# 打不了还没出场的敌人。
		clock = maxf(clock, spawned_at)
		var would_die_at: float = clock + seconds_per_kill

		if would_die_at <= arrives_at:
			out.kills += 1
			clock = would_die_at
		else:
			# 它跑掉了。已经砸在它身上的伤害是沉没成本，
			# 而且我们要等到它离场才能接着打下一个。
			out.leaked += 1
			out.base_damage += leak_damage
			clock = arrives_at

	out.cleared = out.leaked == 0
	out.battle_seconds = clock
	out.ticks = _to_ticks(clock, cfg)
	# 时长对齐到 tick 之后再报出去，保证与 M0 的真 tick 模拟可比。
	out.battle_seconds = float(out.ticks) / float(cfg.tick_rate)
	return out


## 一队单位对某一波的有效 DPS，属性克制、攻击科技、羁绊加成全部计入。
##
## 这个求和是 §03 成立与否的支点：只有当 [param deployed] 里真的换上了
## 克制系单位，2.0 的倍率才吃得到。全员固定上场的五系阵容平均只有 1.10，
## 和物理的 1.05 几乎没差别。
static func team_dps(
	deployed: Array[PBUnit],
	wave_element: PBElement.Type,
	atk_tech_mult: float,
	bond_mult: float,
	cfg: PBSimConfig
) -> float:
	var total: float = 0.0
	for unit: PBUnit in deployed:
		total += unit.effective_power(wave_element, cfg)
	return total * atk_tech_mult * bond_mult


## 第 [param index] 个敌人的出场时刻（秒）。整波在 `spawn_window` 内均匀出完。
static func _spawn_time(index: int, count: int, cfg: PBSimConfig) -> float:
	if count <= 1:
		return 0.0
	return cfg.spawn_window * float(index) / float(count - 1)


static func _to_ticks(seconds: float, cfg: PBSimConfig) -> int:
	return int(ceil(seconds * float(cfg.tick_rate)))
