extends GutTest
## 出手离散化与真弹道（§02，M4-b）。
##
## ## 这个文件守的是「节奏变了，总量没变」
##
## 离散化把「每 tick 抹平的一股连续伤害」换成「每 N tick 打一发」。
## 这种改动最容易出的错是**顺手改了总量**：间隔取整之后一发该打多少，
## 差一点点都会让整条配平曲线平移，而它不报错。
##
## 所以第一条是**平均 DPS 恒等**。其余几条钉的是弹道真的存在：
## 发出去的那一 tick 不结算、目标死了那一发就白放、近战没有子弹。
##
## 还有一条**退化锚点**：攻速为 0 时走的是 M3-a 之前那条连续输出的路
## （[method PBAttacker.whole_field]），它必须与解析式排队模型逐字段一致，
## 而那个模型假设溢出无损转移 —— 所以那一档的溢出留着，离散那一档没有。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# 压平战场：本文件量的是节奏和弹道，纵向一条都不涉及（见 `test_field_2d.gd`）。
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	# **关掉起手**（M9-e）。这个文件量的是一发的**形状**：一发是一坨不是涓流、
	# 一发只打死一个、子弹要飞一段才见血 —— 全都和「第一发落在第几 tick」无关。
	# 而起手把每一发整体推后 `windup_ticks`，于是每一句「跑 N tick 之后」
	# 都要跟着挪，那样改出来的断言测的就不再是原来那件事了。
	# 出手时刻本身由 `test_actor_pose.gd` 那两条钉着。
	_cfg.attack_hit_frame = 1
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260830


## 一个站着不动、血厚到打不死的靶子。
##
## 靶子不死也不走，是为了让「打出去多少伤害」这个量**没有别的出口** ——
## 会死就掺进溢出与浪费，会走就掺进射程，而这两样都是别的用例的题目。
func _dummy_wave() -> PBWave:
	var wave := PBWaveRules.build(5, _cfg, _rng)
	wave.count = 1
	wave.hp_each = 1e12
	# 这个文件量的是「一发 × 发数」，护甲会把每一发打个折（护甲在 `test_enemy_armor.gd`）。
	wave.armor_each = 0.0
	return wave


func _target_of(sim: PBBattleSim) -> PBEnemy:
	var enemy: PBEnemy = sim.enemies()[0]
	enemy.distance = 0.10
	enemy.speed = 0.0
	return enemy


## 一个只会普攻的射手。[param speed] 为 0 = 连续输出那条退化路径。
##
## **当场 `prime` 一次**：间隔和一发的伤害都是它算出来的，
## 不 prime 的话 [method PBAttacker.attack_interval] 报的是默认值 1，
## 而用例正是拿那个数去定要跑多少 tick 的。
## [PBBattleSim] 开波时还会再 prime 一次 —— 幂等，不冲突。
func _shooter(dps: float, speed: float, shot_speed: float = 0.0) -> PBAttacker:
	var out := PBAttacker.new()
	out.dps = dps
	# **一发就是攻击力**（M12-c5）。按面板攻速折算出来，
	# 这样这个夹具在新口径下与它此前的行为最接近。
	out.attack = dps / maxf(speed, 0.0001)
	out.pos = Vector2.ZERO
	out.reach = _cfg.field_diagonal()
	out.attack_speed = speed
	out.shot_speed = shot_speed
	out.prime(_cfg.tick_rate)
	return out


func _run(squad: Array[PBAttacker], ticks: int) -> PBEnemy:
	var sim := PBBattleSim.new(_dummy_wave(), 0.0, 0.0, _cfg, squad)
	var target := _target_of(sim)
	for _i: int in ticks:
		sim.step()
	return target


# ── 总量 = 一发 × 发数 ─────────────────────────────────────────


func test_every_swing_deals_exactly_one_attack_worth_of_damage() -> void:
	# **本文件的正题，M12-c5 换了口径。**
	#
	# 在那之前一发的伤害由**间隔反推**（`dps × 间隔 ÷ tick_rate`），
	# 这条断言问的是「平均 DPS 分毫不差」—— 那是离散化当年敢做的前提。
	# 玩家 M12-c5 定的口径是「每次攻击都是实时结算的，就像 RPG 里那样」：
	# **一发就是他的攻击力**，出手多快由攻速单独决定，
	# 两者的乘积降级成统计量。
	#
	# 所以现在守的是新的那条 —— **总量恰好是「一发 × 打了几发」**，
	# 一个零头都不许多也不许少。它同样拦得住「整条配平曲线悄悄平移」。
	for speed: float in [0.5, 1.0, 2.0, 4.0]:
		var squad: Array[PBAttacker] = [_shooter(1000.0, speed)]
		var interval: int = squad[0].attack_interval()
		var target := _run(squad, interval * 10)
		var dealt: float = target.max_hp - target.hp
		assert_almost_eq(
			dealt,
			squad[0].damage_per_shot() * 10.0,
			1e-6,
			"攻速 %.1f：十个间隔该正好打出十发" % speed
		)


func test_the_swing_rate_never_passes_the_cap() -> void:
	# 攻速 4.0 那一档现在会被 [constant PBAttacker.ATTACK_SPEED_CAP] 压下来 ——
	# 上一条里它因此只打得出 3 次/秒 的节奏，而不是 4 次。
	var fast := _shooter(1000.0, 4.0)
	assert_eq(fast.attack_interval(), PBAttacker.fastest_ticks(_cfg.tick_rate), "该被压到上限")


func test_a_shot_is_one_lump_not_a_trickle() -> void:
	# 离散化真的发生了：一发之后要**隔一整个间隔**才有下一发。
	# 不成立的话，攻速这个属性在战斗里仍然只是 `dps` 里的一个乘数。
	var squad: Array[PBAttacker] = [_shooter(1000.0, 1.0)]
	var interval: int = squad[0].attack_interval()
	assert_gt(interval, 1, "攻速 1 次/秒、20 tick/s，间隔该是 20 tick")
	var one := _run(squad, 1)
	var lump: float = one.max_hp - one.hp
	assert_gt(lump, 0.0, "第一 tick 就该出手")

	var squad2: Array[PBAttacker] = [_shooter(1000.0, 1.0)]
	var mid := _run(squad2, interval - 1)
	assert_almost_eq(mid.max_hp - mid.hp, lump, 1e-6, "一个间隔之内不该再有第二发")


func test_the_continuous_path_still_pours_and_overflows() -> void:
	# **退化锚点。** 攻速为 0 = M3-a 之前那条连续输出的路，
	# 它必须与 [PBCombatRules] 的解析式排队模型逐字段一致，
	# 而那个模型假设**溢出无损转移**。离散那一档没有溢出，这一档必须有。
	_cfg.field_height = 0.0
	var wave := PBWaveRules.build(9, _cfg, _rng)
	assert_gt(wave.count, 3, "这一波要有几个敌人才谈得上溢出")
	# 一 tick 的伤害够打死三个：连续档该真的一 tick 打死三个。
	var squad: Array[PBAttacker] = [_shooter(wave.hp_each * 3.0 * float(_cfg.tick_rate), 0.0)]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.step()
	assert_eq(sim.result().kills, 3, "连续档一 tick 的伤害该顺着队列浇下去")


func test_a_discrete_shot_wastes_its_overkill() -> void:
	# 一发打死了目标，多出来的伤害没有地方去 —— 那是「命中才结算」的代价。
	# 让它溢出的话，离散和连续就没有区别了，而**这一条会明显拉长单波时长**
	# （归数值回归）。
	var wave := PBWaveRules.build(9, _cfg, _rng)
	var squad: Array[PBAttacker] = [_shooter(wave.hp_each * 100.0 * float(_cfg.tick_rate), 8.0)]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	sim.step()
	assert_eq(sim.result().kills, 1, "一发只能打死一个，再高的伤害也一样")


# ── 弹道真的存在 ────────────────────────────────────────────────


func test_a_bullet_takes_time_to_arrive() -> void:
	# 发出去的那一 tick 不结算 —— 飞行时间等于 0 的话，
	# 子弹就只是一个画在屏幕上的装饰，而这一整步的理由就是不要那种装饰。
	var squad: Array[PBAttacker] = [_shooter(1000.0, 1.0, 0.02)]
	var sim := PBBattleSim.new(_dummy_wave(), 0.0, 0.0, _cfg, squad)
	var target := _target_of(sim)
	sim.step()
	assert_eq(target.hp, target.max_hp, "刚出膛的那一 tick 不该有人掉血")
	assert_eq(_flying(sim), 1, "该有一发在飞")

	for _i: int in 10:
		sim.step()
	assert_lt(target.hp, target.max_hp, "飞到了就该结算")
	assert_eq(_flying(sim), 0, "命中之后要回池，不然池子会漏光")


func test_melee_hits_on_contact_without_a_bullet() -> void:
	# 近战没有弹道（[member PBAttacker.shot_speed] 为 0）：接触即伤。
	# 给近战也发子弹的话，「贴身」这件事在时序上就没有意义了。
	var squad: Array[PBAttacker] = [_shooter(1000.0, 1.0, 0.0)]
	var sim := PBBattleSim.new(_dummy_wave(), 0.0, 0.0, _cfg, squad)
	var target := _target_of(sim)
	sim.step()
	assert_lt(target.hp, target.max_hp, "近战当场见血")
	assert_eq(_flying(sim), 0, "而且不该有子弹在飞")


func test_a_bullet_dies_with_its_target_instead_of_switching() -> void:
	# 追着换目标的话，一发子弹等于永远不会浪费，离散和连续就没有区别了。
	var wave := _dummy_wave()
	wave.count = 2
	var squad: Array[PBAttacker] = [_shooter(1000.0, 1.0, 0.01)]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	var first := _target_of(sim)
	var second: PBEnemy = sim.enemies()[1]
	second.distance = 0.10
	second.speed = 0.0
	sim.step()
	assert_eq(_flying(sim), 1, "该有一发正朝队头飞")

	# 队头在子弹落地之前被别的东西打死了（这里直接敲掉，测试才做的事）。
	first.take_damage(first.max_hp, sim.current_tick())
	sim.step()
	assert_eq(_flying(sim), 0, "目标没了，这一发就该消失")
	assert_eq(second.hp, second.max_hp, "而且绝不该转头打第二个")


func test_an_idle_shooter_does_not_burn_its_cooldown() -> void:
	# 射程内暂时没人时**不该进冷却**：进了的话，等敌人走进射程时
	# 他还得再等一个间隔，表现是「远程站在那儿发呆」。
	var squad: Array[PBAttacker] = [_shooter(1000.0, 1.0)]
	squad[0].reach = 0.0
	var sim := PBBattleSim.new(_dummy_wave(), 0.0, 0.0, _cfg, squad)
	var target := _target_of(sim)
	for _i: int in 30:
		sim.step()
	assert_eq(target.hp, target.max_hp, "射程为零，这三十 tick 一下都打不着")

	# 敌人走到脚下：**下一 tick 就该开火**，不用再等一个间隔。
	target.distance = 0.0
	sim.step()
	assert_lt(target.hp, target.max_hp, "够得着了就该立刻出手")


func _flying(sim: PBBattleSim) -> int:
	var count: int = 0
	for shot: PBProjectile in sim.shots():
		if shot.alive:
			count += 1
	return count
