extends GutTest
## 出手节奏：**一发就是攻击力，多久一发由攻速决定**（M12-c5），
## 外加一道 3 次/秒的墙（[constant PBAttacker.ATTACK_SPEED_CAP]）。
##
## ## 这几条守的是什么
##
## M12-c4 之前 [method PBAttacker.prime] 从 [member PBAttacker.dps] **反推**
## 每一发（`dps × 间隔 ÷ tick_rate`）。那条反推保证「平均 DPS 分毫不差」，
## 代价是**屏幕上两个数都不是真的**：每一发不等于攻击力、实际攻速不等于
## 面板攻速（实测各偏 ±2%），而且**建人之后再改攻速会被整个抵消** ——
## 抬攻速 → 间隔减半 → 每发伤害跟着减半 → 总量一位不动，**而它不报错**。
##
## 所以这个文件钉两头：**攻速真的抬产出**，**加成为 0 时逐位不变**
## （后者才是 [method PBAttacker.whole_field] 那条与解析式排队模型
## 对拍的退化路径还活着的保证）。
##
## 攻速的**加成**不在这里 —— M12-h1 起它是一条属性词条
## （[constant PBStatRules.ATTACK_SPEED]），在算三围那一刻就折进去了，
## 见 `tests/test_stat_mods.gd`。

const RATE: int = 20


func _striker(speed: float, attack: float = 5.0) -> PBAttacker:
	var one := PBAttacker.new()
	one.dps = attack * speed
	one.attack = attack
	one.attack_speed = speed
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


func test_a_faster_ninja_really_shortens_the_gap_between_swings() -> void:
	assert_eq(_striker(1.0).attack_interval(), RATE, "攻速 1.0 就是每秒一下")
	assert_eq(_striker(2.0).attack_interval(), RATE / 2, "翻倍该把间隔砍一半")


func test_the_damage_per_swing_does_not_depend_on_the_attack_speed() -> void:
	# **这一条是反推被拿掉的那个位置。** 反推还在的话，
	# 攻速翻倍会让每一发减半 —— 于是「配了不生效」。
	assert_almost_eq(
		_striker(2.0).damage_per_shot(),
		_striker(1.0).damage_per_shot(),
		0.0001,
		"每一发只跟攻击力有关"
	)


func test_doubling_the_attack_speed_really_doubles_the_output() -> void:
	var ticks: int = RATE * 20
	assert_almost_eq(
		_output_over(_striker(2.0), ticks),
		_output_over(_striker(1.0), ticks) * 2.0,
		0.001,
		"产出该翻倍"
	)


func test_the_interval_is_just_the_attack_speed_turned_upside_down() -> void:
	# 加成搬去属性层之后，这一句就是全部的规则了 ——
	# 而它必须和上限那道墙一起成立。
	for speed: float in [0.5, 0.847, 1.0, 2.5]:
		var expected: int = maxi(
			int(round(float(RATE) / speed)), PBAttacker.fastest_ticks(RATE)
		)
		assert_eq(_striker(speed).attack_interval(), expected, "间隔就是攻速的倒数")


func test_a_real_ninja_hits_for_exactly_his_attack_power() -> void:
	# **这一条是 M12-c5 的全部意义。** 在它之前每一发是反推出来的，
	# 于是屏幕上飘的那个数不等于他的攻击力，而玩家对的恰恰是属性栏上那个数。
	var cfg := PBGameData.config()
	var units: Array[PBUnit] = []
	for character: PBCharacter in cfg.characters.all():
		units.append(PBUnit.new(character))
	var built := PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), cfg
	)
	for one: PBAttacker in built:
		if one.summoned:
			continue
		one.prime(cfg.tick_rate, cfg)
		# **`attack` 为 0 时 `prime` 会退回旧口径**，而那条路只服务于测试夹具。
		# 生产代码漏填的表现是「伤害悄悄回到旧算法」—— 只差 ±2%，看不出来。
		assert_gt(one.attack, 0.0, "出战席上每个人都该有攻击力")
		assert_almost_eq(one.damage_per_shot(), one.attack, 0.0001, "一发就是攻击力")


func test_the_degenerate_scalar_attacker_is_untouched() -> void:
	# [method PBAttacker.whole_field] 那条与解析式排队模型逐位对拍的退化路径：
	# 攻速为 0、没有「一发」这个概念，每 tick 打 `dps / tick_rate`。
	var one := PBAttacker.whole_field(2000.0, 1.5)
	one.prime(RATE)
	assert_eq(one.attack_interval(), 1, "退化那一档每 tick 出一手")
	assert_almost_eq(one.damage_per_shot(), 100.0, 0.0001, "每 tick 正好是 dps/tick_rate")


func test_nobody_can_swing_faster_than_the_cap() -> void:
	# 上限是**结构性的**：攻速加成是乘算的（尾兽光环 × 羁绊 × 装备 × 科技），
	# 几样叠起来会把间隔压到 1 tick，而屏幕上只表现为「他怎么这么快」。
	var floor_ticks: int = PBAttacker.fastest_ticks(RATE)
	assert_eq(floor_ticks, 7, "20 tick/s 下 3 次每秒 = 最少 7 tick")
	for speed: float in [3.0, 10.0, 100.0]:
		var one := _striker(speed)
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
