extends GutTest
## 常驻攻速加成（M12-c4）：**它必须真的抬产出**，而不是被
## [method PBAttacker.prime] 那条反推抵消掉。
##
## ## 这一条为什么值得一个文件
##
## `prime` 从 [member PBAttacker.dps] 反推每一发的伤害 ——
## 那是 [method PBAttacker.whole_field] 与解析式排队模型逐位对拍的前提，
## 不能动。于是「直接往 [member PBAttacker.attack_speed] 上加」这个最直觉的
## 写法**加了等于没加**：攻速抬一倍 → 间隔减半 → 每发伤害跟着减半 → 总量一位不动，
## **而它不报错**。
##
## 所以加成走一格自己的数，只缩间隔、不参与反推。这个文件钉两头：
## **加了要真的多打**，**没加要逐位不变**（后者才是对拍还活着的保证）。

const RATE: int = 20


func _striker(speed: float, bonus: float = 0.0) -> PBAttacker:
	var one := PBAttacker.new()
	one.dps = 100.0
	one.attack_speed = speed
	one.attack_speed_bonus = bonus
	one.prime(RATE)
	return one


## 这个人在 [param ticks] 个 tick 里一共打出去多少。
func _output_over(one: PBAttacker, ticks: int) -> float:
	var shots: int = 0
	var tick: int = 0
	one.revive()
	while tick < ticks:
		if one.ready_to_fire(tick):
			shots += 1
			one.on_fired(tick)
		tick += 1
	return float(shots) * one.damage_per_shot()


func test_a_lasting_bonus_really_shortens_the_gap_between_swings() -> void:
	var plain := _striker(1.0)
	var fast := _striker(1.0, 1.0)
	assert_eq(plain.attack_interval(), RATE, "攻速 1.0 就是每秒一下")
	assert_eq(fast.attack_interval(), RATE / 2, "+100% 该把间隔砍一半")


func test_the_damage_per_swing_is_decided_by_the_base_speed_only() -> void:
	# **加成不许参与反推。** 参与了的表现正是「配了不生效」——
	# 间隔减半、每发伤害也减半，总量一位不动。
	var plain := _striker(1.0)
	var fast := _striker(1.0, 1.0)
	assert_almost_eq(
		fast.damage_per_shot(), plain.damage_per_shot(), 0.0001, "每一发该和没加成时一样重"
	)


func test_doubling_the_attack_speed_really_doubles_the_output() -> void:
	# 这一条是这个键存在的全部理由。
	var plain := _striker(1.0)
	var fast := _striker(1.0, 1.0)
	var ticks: int = RATE * 20
	assert_almost_eq(
		_output_over(fast, ticks), _output_over(plain, ticks) * 2.0, 0.001, "产出该翻倍"
	)


func test_a_zero_bonus_changes_nothing_at_all() -> void:
	# **这条守的是对拍。** [method PBAttacker.whole_field] 那条退化路径
	# 与解析式排队模型要逐位相同，而它身上不会有任何被动 ——
	# 所以加成为 0 时每一个派生量都必须和加这个字段之前一模一样。
	for speed: float in [0.0, 0.5, 0.847, 1.0, 2.5]:
		var one := _striker(speed)
		var expected: int = 1
		if speed > 0.0:
			expected = maxi(
				int(round(float(RATE) / speed)), PBAttacker.fastest_ticks(RATE)
			)
		assert_eq(one.attack_interval(), expected, "间隔该是基础攻速定的那个")
		assert_almost_eq(
			one.damage_per_shot(),
			100.0 * float(expected) / float(RATE),
			0.0001,
			"每发伤害该仍然由 dps 反推"
		)


func test_the_bonus_survives_being_cloned() -> void:
	# 漏拷贝的话，悬崖二分探的是一支**出手更慢**的队伍，而真正上场的那支更快 ——
	# 探出来的悬崖系统性偏保守，且不报错。同 [member PBAttacker.crit_chance] 那条。
	var one := _striker(1.0, 0.5)
	var copy := one.clone()
	copy.prime(RATE)
	assert_almost_eq(copy.attack_speed_bonus, 0.5, 0.0001, "加成该跟着复制品走")
	assert_eq(copy.attack_interval(), one.attack_interval(), "复制品的节奏该一样")


func test_a_bonus_below_minus_one_does_not_make_time_run_backwards() -> void:
	# 负数是合法的（原版有代价型被动），但 −1 以下会算出 0 或负的间隔。
	var crawling := _striker(1.0, -5.0)
	assert_gt(crawling.attack_interval(), 0, "间隔必须是正的")
	assert_gte(crawling.attack_interval(), RATE, "变慢就该比原来慢")


# ── 一发就是攻击力（M12-c5）────────────────────────────────────


func test_a_real_ninja_hits_for_exactly_his_attack_power() -> void:
	# **这一条是第二步的全部意义。** 在它之前每一发是 `dps × 间隔 ÷ tick_rate`
	# 反推出来的，于是屏幕上飘的那个数不等于他的攻击力（实测偏 ±2%），
	# 而玩家对的恰恰是属性栏上那个数。
	var cfg := PBGameData.config()
	var units: Array[PBUnit] = []
	for character: PBCharacter in cfg.characters.all():
		units.append(PBUnit.new(character))
		if units.size() >= 6:
			break
	var built := PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, 1.0, PackedFloat64Array(), cfg
	)
	for i: int in units.size():
		built[i].prime(cfg.tick_rate, cfg)
		assert_gt(built[i].attack, 0.0, "建人那一步必须填上攻击力")
		assert_almost_eq(
			built[i].damage_per_shot(), built[i].attack, 0.0001, "一发就是攻击力，不许反推"
		)


func test_every_production_attacker_carries_an_attack_power() -> void:
	# **`attack` 为 0 时 [method PBAttacker.prime] 会退回旧口径**，
	# 而那条路只服务于测试夹具。生产代码漏填的表现是「伤害悄悄回到旧算法」——
	# 数字只差 ±2%，看不出来。所以这里钉住真名册建出来的每一个人。
	var cfg := PBGameData.config()
	var units: Array[PBUnit] = []
	for character: PBCharacter in cfg.characters.all():
		units.append(PBUnit.new(character))
	var built := PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, 1.0, PackedFloat64Array(), cfg
	)
	for one: PBAttacker in built:
		if one.summoned:
			continue
		assert_gt(one.attack, 0.0, "出战席上每个人都该有攻击力")


func test_the_degenerate_scalar_attacker_is_untouched() -> void:
	# [method PBAttacker.whole_field] 那条与解析式排队模型逐位对拍的退化路径：
	# 攻速为 0、没有「一发」这个概念，每 tick 打 `dps / tick_rate`。
	var one := PBAttacker.whole_field(2000.0, 1.5)
	one.prime(RATE)
	assert_eq(one.attack_interval(), 1, "退化那一档每 tick 出一手")
	assert_almost_eq(one.damage_per_shot(), 100.0, 0.0001, "每 tick 正好是 dps/tick_rate")


func test_nobody_can_swing_faster_than_the_cap() -> void:
	# 上限是**结构性的**（[constant PBAttacker.ATTACK_SPEED_CAP]）：加成是乘算的，
	# 几样叠起来会把间隔压到 1 tick，而屏幕上只表现为「他怎么这么快」。
	var floor_ticks: int = PBAttacker.fastest_ticks(RATE)
	assert_eq(floor_ticks, 7, "20 tick/s 下 3 次每秒 = 最少 7 tick")
	for bonus: float in [2.0, 9.0, 99.0]:
		var one := _striker(1.0, bonus)
		assert_eq(one.attack_interval(), floor_ticks, "再怎么堆也不许破上限")
		assert_lte(
			float(RATE) / float(one.attack_interval()),
			PBAttacker.ATTACK_SPEED_CAP,
			"实际每秒出手数不许超过上限"
		)


func test_the_cap_does_not_bind_anyone_in_the_real_roster() -> void:
	# **名册里最快的是 0.919 次/秒**，所以这道墙今天只会被加成顶到。
	# 哪天有角色天生破了上限，这一条会变红 —— 那时要决定的是
	# 「抬上限」还是「那个角色的攻速填错了」，而两者都需要有人来判断。
	var cfg := PBGameData.config()
	for character: PBCharacter in cfg.characters.all():
		var stats := PBUnit.new(character).stats(cfg)
		assert_lt(
			stats.attack_speed, PBAttacker.ATTACK_SPEED_CAP, "%s 的裸攻速破了上限" % character.id
		)
