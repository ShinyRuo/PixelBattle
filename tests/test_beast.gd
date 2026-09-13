extends GutTest
## [PBBeast] / [PBBeastRules] 与尾兽大招的机制测试。§11，M3-d。
##
## ## 这个文件守的是什么
##
## §11 有一条硬性要求，而且它是**结构性**的，不是数值性的：
##
## > 七尾必须存在。它的大招是纯聚拢，等于给玩家一条不依赖特定羁绊的聚怪路径。
## > 同理，六尾的「重置全体大招 CD」是连招流的开关。
## > **这两只是机制型尾兽，不能被数值型挤掉。**
##
## 「不能被挤掉」在代码层只能守住一半：**机制必须真的存在、真的有后果**。
## 另一半（它们在实战里排第几）只能靠扫描量，那不是单测的事。
##
## 所以这里逐条钉的是「这个机制真的发生了」：聚拢真把敌人拖过去了、
## 重置真让别人的大招提前好了、减速真让敌人晚到了。
## 一条机制悄悄失效不会让任何数值断言变红 —— 它只会让那只尾兽变弱一点，
## 而尾兽本来就还没定数值，弱一点看不出来。
##
## 数据本身（九只都在、名字不泄漏进 src）在 `test_beast_data.gd`。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260829


## 造一只只有指定字段的尾兽。测试不读 `data/`，免得数据一调这里就红。


# ── 常驻光环走被动词汇表（M12-e）─────────────


func test_a_beast_aura_is_written_per_level_not_as_a_total() -> void:
	# 原版九只的光环全是 `[N x 等级]` 的形状。写死总量的话，升级这件事对
	# 这一档就没有意义了 —— **而它不报错**，只是玩家花钱升的尾兽什么都没变。
	var beast := PBBeast.new()
	beast.aura_passives = {PBPassiveRules.DODGE: 0.02}
	var low: Dictionary = PBBeastRules.aura_passives(beast, 1, _cfg)
	var high: Dictionary = PBBeastRules.aura_passives(beast, 5, _cfg)
	assert_almost_eq(float(low[PBPassiveRules.DODGE]), 0.02, 0.0001, "一级就是表里那个数")
	assert_gt(float(high[PBPassiveRules.DODGE]), float(low[PBPassiveRules.DODGE]), "升级该变多")


func test_no_beast_means_no_aura_at_all() -> void:
	# 没带尾兽是扫描的分母（[PBBeastTable] 顶上那条）—— 那一路必须一位都不动。
	assert_eq(PBBeastRules.aura_passives(null, 5, _cfg).size(), 0, "没带就什么都不发")


func test_every_aura_key_in_the_real_table_is_one_we_know() -> void:
	# **九只是设计定死的**（§11），不是进度 —— 所以这个数可以写死，
	# 而且 [constant PBBeastLoader.SPEC_BEASTS] 已经写着它了。
	# 光环表现在还是空的（按原版重铺是 M12-e2），这条先守住
	# 「填进去的键必须认得」，以及「九只一只都不许少」。
	var table := PBBeastLoader.table()
	assert_eq(table.size(), PBBeastLoader.SPEC_BEASTS, "尾兽该是九只")
	for beast: PBBeast in table.all():
		for key: StringName in beast.aura_passives:
			assert_true(PBModRules.is_known(key), "「%s」这个键没人认得" % key)


func _beast(beast_id: StringName) -> PBBeast:
	var beast := PBBeast.new()
	beast.id = beast_id
	beast.name_key = String(beast_id)
	return beast


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 把一只尾兽的大招摆到场上，全队普攻输出记为 [param team_dps]。
func _sim_with(beast: PBBeast, wave: PBWave, team_dps: float) -> PBBattleSim:
	var attacker := PBBeastRules.build_ultimate_attacker(
		beast, 1, team_dps, wave.element, _cfg
	)
	var squad: Array[PBAttacker] = []
	if attacker != null:
		squad.append(attacker)
	return PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)


func test_no_beast_changes_nothing_at_all() -> void:
	# **对拍锚点。** 装上尾兽表但一只都不选，结果必须与「根本没有尾兽系统」
	# 逐字段相同 —— 否则后面量出来的「尾兽值多少波」里混着一份接线的副作用，
	# 而那两种情况的修法完全相反。
	var plain := PBGameData.config()
	var control := PBGameData.config()
	control.beasts = PBBeastTable.new()
	for run_seed: int in [20260829, 20260830, 20260831]:
		var with_table := PBRunSim.run(plain, PBStrategyRegistry.make(&"balanced"), run_seed)
		var without := PBRunSim.run(control, PBStrategyRegistry.make(&"balanced"), run_seed)
		assert_eq(
			with_table.wave_reached,
			without.wave_reached,
			"种子 %d：没选尾兽时，装不装尾兽表都该跑出同一局" % run_seed
		)
		assert_eq(with_table.gold_earned, without.gold_earned, "收入也该逐位相同")


func test_the_aura_only_reaches_the_units_it_names() -> void:
	# 三只尾兽的光环带筛选（属性型两只、点名型一只）。筛选失效的表现是
	# 「选哪只尾兽都差不多」—— 那正好抹掉尾兽与 §03 属性系统的接口。
	var water := _beast(&"elemental")
	water.aura_power = 0.15
	water.aura_element = int(PBElement.Type.WATER)
	var deployed: Array[PBUnit] = [
		PBUnit.of(_cfg, PBElement.Type.WATER, PBUnit.Rarity.SR),
		PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.SR),
	]
	var mults := PBBeastRules.unit_multipliers(deployed, water, 1, _cfg)
	assert_almost_eq(mults[0], 1.15, 1e-9, "水系单位吃得到水系光环")
	assert_almost_eq(mults[1], 1.0, 1e-9, "火系单位吃不到水系光环")

	var named := _beast(&"named")
	named.aura_power = 0.6
	named.aura_member_ids = [deployed[1].key()]
	var by_name := PBBeastRules.unit_multipliers(deployed, named, 1, _cfg)
	assert_almost_eq(by_name[0], 1.0, 1e-9, "没被点名的单位吃不到专属强化")
	assert_almost_eq(by_name[1], 1.6, 1e-9, "被点名的单位吃满专属强化")


func test_the_aura_grows_with_the_level_but_the_mechanisms_do_not() -> void:
	# 等级只放大三样：光环、大招伤害、大招频率。**机制一概不变** ——
	# 一个 Lv10 的全屏定身等于游戏结束，见 [PBBeastRules] 顶部。
	var beast := _beast(&"grower")
	beast.aura_power = 0.10
	beast.ultimate_damage_seconds = 4.0
	beast.ultimate_slow_scale = 0.5
	beast.ultimate_slow_seconds = 5.0
	var units: Array[PBUnit] = [PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.R)]

	var lv1 := PBBeastRules.unit_multipliers(units, beast, 1, _cfg)
	var lv5 := PBBeastRules.unit_multipliers(units, beast, 5, _cfg)
	assert_almost_eq(lv1[0], 1.10, 1e-9, "Lv1 就是 .tres 里写的那个数")
	assert_gt(lv5[0], lv1[0], "等级该把光环放大")

	var a1 := PBBeastRules.build_ultimate_attacker(beast, 1, 1000.0, PBElement.Type.WIND, _cfg)
	var a5 := PBBeastRules.build_ultimate_attacker(beast, 5, 1000.0, PBElement.Type.WIND, _cfg)
	assert_gt(a5.ultimate.skill.damage, a1.ultimate.skill.damage, "伤害该随等级涨")
	assert_lt(
		a5.ultimate.skill.cooldown_ticks, a1.ultimate.skill.cooldown_ticks, "冷却该随等级缩短"
	)
	assert_eq(
		a5.ultimate.skill.slow_scale, a1.ultimate.skill.slow_scale, "减速倍率**不该**随等级变强"
	)


func test_the_beast_ultimate_scales_with_the_team_not_with_itself() -> void:
	# 尾兽没有自己的战力，一发大招以「全队几秒输出」计量 ——
	# 这让它自动跟着 §04 那条指数曲线走，不会前期无敌、后期作废。
	var beast := _beast(&"nuke")
	beast.ultimate_damage_seconds = 8.0
	var weak := PBBeastRules.build_ultimate_attacker(beast, 1, 100.0, PBElement.Type.WIND, _cfg)
	var strong := PBBeastRules.build_ultimate_attacker(beast, 1, 800.0, PBElement.Type.WIND, _cfg)
	assert_almost_eq(weak.ultimate.skill.damage, 800.0, 1e-6, "一发 = 全队 8 秒输出")
	assert_almost_eq(
		strong.ultimate.skill.damage / weak.ultimate.skill.damage, 8.0, 1e-6, "该按全队输出等比例放大"
	)
	assert_eq(weak.dps, 0.0, "尾兽没有普攻 —— 它只是一个挂着大招的空壳")
	assert_eq(PBCombatRules.total_dps([weak]), 0.0, "所以它一分战力都不该报进队伍战力里")


func test_a_beast_with_no_effect_at_all_takes_no_slot() -> void:
	# 八尾的「召唤分身承伤」在当前模型下恒为 0（敌人不还手）。
	# 全 0 的大招不该占一个攻击者槽位：它每 tick 都会去挑落点、
	# 每次冷却好都会「放」一发什么也不发生的大招，还会给对照组混进噪声。
	var numbers_only := _beast(&"numbers")
	numbers_only.aura_power = 0.12
	assert_false(numbers_only.has_ultimate(), "光环型尾兽没有可观测的大招")
	assert_null(
		PBBeastRules.build_ultimate_attacker(numbers_only, 1, 500.0, PBElement.Type.WIND, _cfg),
		"没有后果的大招不该造出攻击者"
	)


func test_gathering_drags_the_pack_onto_the_landing_spot() -> void:
	# **§11 点名的机制型之一。** 七尾给的是「不依赖特定羁绊的聚怪路径」——
	# 抽不到聚拢角色的局靠它救命，所以它必须真的把人拖过去。
	#
	# 判据是「有几个敌人叠在同一个位置上」。敌人按出场顺序错开、全场同速，
	# 所以**没有聚拢时任意两个的距离都不相等**；聚拢过一次之后被罩住的那几个
	# 会一直叠着走。这个判据不受出怪窗口和半径的具体取值影响。
	_cfg.ultimate_delay_seconds = 0.0
	var beast := _beast(&"gatherer")
	beast.ultimate_gather = true
	beast.ultimate_radius = 0.35
	var wave := _wave(9)
	var control := PBBattleSim.new(wave, 0.0, 0.0, _cfg)
	var gathered := _sim_with(beast, wave, 0.0)
	for _i: int in 120:
		control.step()
		gathered.step()
	assert_eq(_largest_stack(control.active_enemies()), 1, "不聚拢的话，任意两个敌人都不同位置")
	assert_gte(
		_largest_stack(gathered.active_enemies()),
		_cfg.ultimate_min_targets,
		"聚拢该把落点罩住的那几个拖到同一个点上"
	)


func test_resetting_cooldowns_helps_everyone_else_but_not_itself() -> void:
	# **§11 点名的机制型之二。** 六尾自己一点伤害都不打，
	# 价值完全来自「让别人多放一轮」—— 所以判据只能是「队友多放了几发」，
	# 不能是「队友的 `ready_at` 变小了」：清完冷却队友立刻又放一发、
	# 又转回冷却，那个字段读起来和没清过一模一样。
	#
	# 清自己的话它会在同一 tick 反复自我重置，那是个死循环而不是一个机制。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(9)
	var beast := _beast(&"resetter")
	beast.ultimate_reset_cooldowns = true
	var beast_attacker := PBBeastRules.build_ultimate_attacker(beast, 1, 0.0, wave.element, _cfg)
	var alone: Array[PBAttacker] = [_mate_with_ultimate(wave)]
	var helped: Array[PBAttacker] = [_mate_with_ultimate(wave), beast_attacker]
	assert_gt(
		_kills_over(wave, helped, 200),
		_kills_over(wave, alone, 200),
		"有尾兽在场，队友的大招该多放出几发来"
	)
	assert_gt(beast_attacker.ultimate.ready_at, 0, "尾兽自己照常进冷却，不自我重置")


func test_slowing_the_field_buys_time_for_everyone() -> void:
	# 一尾的全屏减速力场、五尾的地形阻挡。**减速是场的属性，不是单位的属性** ——
	# 所以判据是「整波都晚到」，不是「某几个敌人晚到」。
	#
	# 出怪窗口压成 0 是必须的：默认窗口 10 秒，而减速只有 4 秒 ——
	# 最后一个怪在减速早就过期之后才出场，整波的结束时刻由它决定，
	# 于是**减速确实生效了、总时长却一 tick 不差**。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(5)
	var beast := _beast(&"slower")
	beast.ultimate_slow_scale = 0.0
	beast.ultimate_slow_seconds = 4.0
	var slowed := _sim_with(beast, wave, 0.0).run_to_end()
	var control := PBBattleSim.new(wave, 0.0, 0.0, _cfg).run_to_end()
	assert_eq(slowed.leaked, control.leaked, "谁都打不动的话，减速只改到达时间不改结局")
	assert_gt(slowed.ticks, control.ticks, "定身 4 秒应该让整波都晚到")


func test_knockback_pushes_the_pack_back_towards_the_spawn() -> void:
	# 三尾的范围击退。和聚拢是相反方向的两种位置操纵，
	# 两者都不产生伤害，价值全在「敌人晚到基地多久」上。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(5)
	var beast := _beast(&"pusher")
	beast.ultimate_knockback = 0.3
	beast.ultimate_radius = _cfg.field_length
	var pushed := _sim_with(beast, wave, 0.0).run_to_end()
	var control := PBBattleSim.new(wave, 0.0, 0.0, _cfg).run_to_end()
	assert_gt(pushed.ticks, control.ticks, "被推回去的敌人要多走一段才到基地")


func test_a_single_target_ultimate_only_ever_hits_one() -> void:
	# 九尾的超大单体爆发。§04 靠「单体 vs 范围」把精英波与潮水波的价值分开，
	# 只有伤害数字的话那条分化不成立。
	#
	# 两个 tick 而不是一个：落地结算排在下达**前面**（[PBBattleSim] 顶部那条
	# 顺序），所以哪怕施法延迟为 0，一发大招也要到下一 tick 才落地。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(9)
	var beast := _beast(&"sniper")
	beast.ultimate_max_targets = 1
	beast.ultimate_damage_seconds = 1.0
	var sim := _sim_with(beast, wave, wave.hp_each * 1000.0)
	sim.step()
	sim.step()
	assert_eq(sim.result().kills, 1, "再高的伤害，单体大招也只打得死一个")


func test_the_damage_buff_only_lasts_as_long_as_it_says() -> void:
	# 二尾的「短时全体暴击必中」。暴击在当前模型里没有独立的掷骰，
	# 唯一能观测到的后果就是这段时间内伤害更高 —— 那就该只在这段时间内更高。
	_cfg.spawn_window = 0.0
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(6)
	var beast := _beast(&"buffer")
	beast.ultimate_team_damage_scale = 4.0
	beast.ultimate_buff_seconds = 1.0
	var beast_attacker := PBBeastRules.build_ultimate_attacker(beast, 1, 0.0, wave.element, _cfg)
	var alone: Array[PBAttacker] = [_mate_without_ultimate(wave)]
	var buffed: Array[PBAttacker] = [_mate_without_ultimate(wave), beast_attacker]
	# 量**打出去多少伤害**而不是打死几个：击杀是离散的，一个增伤窗口
	# 可能一个也没多杀，也可能刚好多杀两个，读不出「窗口有没有到期」。
	var early: int = _cfg.tick_rate * 2
	var late: int = _cfg.tick_rate * 8
	var gap_early: float = _damage_over(wave, buffed, early) - _damage_over(wave, alone, early)
	var gap_late: float = _damage_over(wave, buffed, late) - _damage_over(wave, alone, late)
	assert_gt(gap_early, 0.0, "增伤窗口内该多打出伤害来")
	assert_almost_eq(gap_late, gap_early, gap_early * 1e-6, "窗口过期之后差距不该继续拉开")


func test_the_cooldown_aura_makes_character_ultimates_come_round_sooner() -> void:
	# 六尾的「团队回蓝 +25%」。没有蓝条的模型里它唯一能观测到的后果就是
	# 大招放得更勤，所以直接折成冷却倍率 —— 这不是把机制折算成数值，
	# 是同一件事在没有资源条的模型里的等价表达。
	var faster := _beast(&"quickener")
	faster.aura_ultimate_cd_scale = 0.8
	var deployed: Array[PBUnit] = [PBUnit.of(_cfg, PBElement.Type.FIRE, PBUnit.Rarity.SR)]
	var plain := PBCombatRules.build_attackers(
		deployed, PBElement.Type.WIND, 1.0, PackedFloat64Array(), _cfg
	)
	var hasted := PBCombatRules.build_attackers(
		deployed, PBElement.Type.WIND, 1.0, PackedFloat64Array(), _cfg, faster
	)
	assert_lt(
		hasted[0].ultimate.skill.cooldown_ticks,
		plain[0].ultimate.skill.cooldown_ticks,
		"回蓝光环该让角色大招的冷却变短"
	)


func test_upgrade_costs_follow_the_spec_curve_and_stop_at_the_cap() -> void:
	# §11：`400 × 1.6^Lv`，上限 10。价格曲线比攻击科技（1.4）陡是有道理的 ——
	# 一级尾兽同时买到光环、大招伤害和大招频率三样。
	assert_eq(PBBeastRules.upgrade_cost(1, _cfg), 640, "Lv1 → Lv2 = 400 × 1.6")
	assert_gt(
		PBBeastRules.upgrade_cost(5, _cfg), PBBeastRules.upgrade_cost(4, _cfg), "价格该逐级上涨"
	)
	assert_eq(PBBeastRules.upgrade_cost(_cfg.beast_level_max, _cfg), -1, "满级返回 −1，与科技同约定")


func test_upgrading_actually_spends_the_gold() -> void:
	# 升级和抽卡、科技抢同一笔钱。不真扣钱的话它就是白送的加成，
	# 而 §11 把它定成一个和抽卡竞争的金币坑。
	var state := PBRunState.new()
	state.beast_id = &"anything"
	state.gold = 100000
	var strategy := PBStrategy.new()
	strategy.beast_level_target = 4
	strategy.upgrade_beast(state, _cfg)
	assert_eq(state.beast_level, 4, "钱够就该升到目标等级")
	assert_gt(state.gold_spent, 0, "升级要真的花钱")

	var broke := PBRunState.new()
	broke.beast_id = &"anything"
	broke.gold = 10
	strategy.upgrade_beast(broke, _cfg)
	assert_eq(broke.beast_level, 1, "钱不够就停在原地，不赊账")


## 一个自带大招的队友。**一发只打死一个**（`max_targets = 1`），
## 好让「尾兽让他多放了几发」直接等于击杀数之差。
func _mate_with_ultimate(wave: PBWave) -> PBAttacker:
	var mate := PBAttacker.new()
	mate.reach = _cfg.field_length
	var skill := PBSkill.new()
	skill.damage = wave.hp_each * 1.5
	skill.radius = _cfg.field_length
	skill.max_targets = 1
	skill.cooldown_ticks = 100000
	mate.ultimate = PBSkillCast.new(skill)
	return mate


## 一个只有普攻、而且打得很慢的队友。慢是有意的：
## 整段观测窗口内这一波都清不完，「打出去多少伤害」才是个连续量。
func _mate_without_ultimate(wave: PBWave) -> PBAttacker:
	var mate := PBAttacker.new()
	mate.dps = wave.hp_each * 0.02 * float(_cfg.tick_rate)
	mate.reach = _cfg.field_length
	return mate


## 这批攻击者在 [param ticks] 个 tick 里打死几个。
func _kills_over(wave: PBWave, attackers: Array[PBAttacker], ticks: int) -> int:
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, attackers)
	for _i: int in ticks:
		sim.step()
	return sim.result().kills


## 这批攻击者在 [param ticks] 个 tick 里打出去多少伤害（按敌人掉的血算）。
func _damage_over(wave: PBWave, attackers: Array[PBAttacker], ticks: int) -> float:
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, attackers)
	for _i: int in ticks:
		sim.step()
	var total: float = 0.0
	for enemy: PBEnemy in sim.enemies():
		total += enemy.max_hp - enemy.hp
	return total


## 场上叠在同一个位置的敌人最多有几个。聚拢的判据。
##
## 敌人按出场顺序错开、全场同速，所以**没有聚拢时这个数恒为 1**。
## 最密的一段里有几个敌人 —— 用「一发大招罩得住几个」当尺子。
##
## M3.5-c 的防挤之后**坐标不再相等**（拖到同一点的会展开成一条紧队列，
## 不然画出来是一个单位）。聚拢的价值本来也不是坐标相等，
## 是「一发 AOE 能罩住几个」，所以尺子换成半径内的人数，
## 这比数重合点更贴近它真正兑现价值的方式。
## 挤得最紧的那一堆有几个人。
##
## **按二维位置数**（M4-a/M4-d）：升维之前只有推进轴，「同一个 x」就等于重合；
## 现在一个方阵的一整列共用同一个 x 而分散在各条泳道上，只看 x 的话
## 「没聚拢」也会数出一堆人来。
func _largest_stack(enemies: Array[PBEnemy]) -> int:
	var best: int = 0
	for anchor: PBEnemy in enemies:
		var packed: int = 0
		for enemy: PBEnemy in enemies:
			if enemy.pos().distance_to(anchor.pos()) <= _cfg.unit_min_gap * 1.5:
				packed += 1
		best = maxi(best, packed)
	return best
