extends GutTest
## 羁绊功能档（§09 的聚拢 / 吸附 / 定身 / 减速 / 金币）。M3-f。
##
## ## 这个文件守的是什么
##
## §09 的功能档不是「再加几个百分比」，它是给一条**结构性冲突**的解药：
##
## > 「兜底」的定义是「不用会玩也能拿到」，「技能阶梯」的定义是
## > 「会玩才拿得到」。在只有倍率一种货币时，这两样在抢同一个池子。
##
## 所以功能档的每一条判据都是「**这件事真的发生了**」，不是「这个数变大了」。
## 一个功能悄悄失效不会让任何数值断言变红 —— 玩家只会觉得「凑满了好像没什么用」，
## 而那正是 §09 想避免的那种隐性数值。
##
## 三层各测各的：
##
## 1. **数据层** —— 5 组命名羁绊各解锁一个功能，载体是真角色、且是本组成员
## 2. **规则层** —— 凑齐 + 载体上场才发；载体在待命台不发；派出去就掉
## 3. **战斗层** —— 每个功能在场上真有后果（拖动 / 定住 / 减速 / 不倒扣）

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260829


# ── 数据层 ────────────────────────────────────────────────────


func test_the_five_named_bonds_each_unlock_one_function() -> void:
	# §09 的硬性规范：小队型「3 档功能」、阵营型「6 档功能」——
	# **每组命名羁绊的最高档必须解锁一个机制**，不能只是更大的百分比。
	var found: Array[StringName] = []
	for bond: PBBond in _cfg.bonds.all():
		if bond.match_mode != PBBond.Match.MEMBERS:
			continue
		var key: StringName = bond.function_at(bond.full_tier_count())
		assert_ne(key, &"", "命名羁绊 %s 的满档该解锁一个功能" % bond.id)
		found.append(key)
	assert_eq(found.size(), 5, "§09 首批是 5 组命名羁绊")


func test_every_carrier_is_a_real_member_of_its_own_bond() -> void:
	# 载体写错成一个不在名单里的人，功能就永远发不出去 —— 而且不报错：
	# 那个人凑不进这组羁绊，档位到了他也不在场上。
	for bond: PBBond in _cfg.bonds.all():
		for i: int in bond.tier_function_keys.size():
			if bond.tier_function_keys[i] == &"":
				continue
			var carrier: StringName = bond.tier_function_carriers[i]
			var character := _cfg.characters.by_id(carrier)
			assert_not_null(character, "%s 的载体 %s 该是真角色" % [bond.id, carrier])
			assert_true(bond.member_ids.has(carrier), "%s 的载体该是本组成员" % bond.id)


func test_the_element_fallback_bonds_stay_purely_numeric() -> void:
	# **这是本节的支点。** 属性型是兜底档，随便带都会自动激活
	# （在场 16 张卡摊到六个属性，平均每系 2.7 个）。
	# 给兜底档配功能等于把机制也白送出去，技能阶梯就又回到原点了。
	for bond: PBBond in _cfg.bonds.all():
		if bond.match_mode != PBBond.Match.ELEMENT:
			continue
		assert_eq(bond.function_at(bond.full_tier_count()), &"", "兜底羁绊 %s 不该有功能" % bond.id)


func test_a_misspelled_function_key_is_rejected_instead_of_ignored() -> void:
	# 拼错一个字母不会崩，只会让这一档静默地什么都不做。
	var table := PBBondTable.new()
	assert_false(table.add(_bond(&"typo", &"gathr", &"someone")), "认不出来的功能键该被拒收")
	assert_false(table.add(_bond(&"orphan", PBBondFunctionRules.GATHER, &"")), "没载体的功能该被拒收")
	assert_true(table.add(_bond(&"fine", PBBondFunctionRules.GATHER, &"someone")), "写对了该收下")


# ── 规则层 ────────────────────────────────────────────────────


func test_a_function_needs_both_the_headcount_and_the_carrier_on_the_field() -> void:
	# 数值档按「在场」算（出战席 + 待命台双场景全额，§09），
	# 但功能挂在载体的大招上，**待命台上的人没有大招**。
	# 所以功能档多一条门槛，而那条门槛正是它从「自动发生」变成「一次取舍」的地方。
	var bond := _bond_with_function()
	var members := _units_of(bond)
	var carrier_id: StringName = bond.function_carrier_at(bond.full_tier_count())

	var bonded := members.duplicate()
	var without_carrier: Array[PBUnit] = []
	for unit: PBUnit in members:
		if unit.key() != carrier_id:
			without_carrier.append(unit)

	assert_true(
		PBBondRules.active_functions(bonded, bonded, _cfg.bonds).has(carrier_id),
		"凑齐了且载体上场，功能该发出去"
	)
	assert_false(
		PBBondRules.active_functions(bonded, without_carrier, _cfg.bonds).has(carrier_id),
		"载体在待命台上，功能就没有大招可挂"
	)
	assert_false(
		PBBondRules.active_functions(without_carrier, bonded, _cfg.bonds).has(carrier_id),
		"人数不够，档位就没到"
	)


func test_dispatching_the_squad_costs_the_function_too() -> void:
	# §06：派出去做任务的人羁绊暂时失效。功能档跟着掉是必然结果 ——
	# 只掉倍率不掉功能的话，派遣的代价就被少算了一半，
	# 而那笔账正是任务卡上「派遣会掉哪几组羁绊」那一行在报的。
	var bond := _bond_with_function()
	var state := PBRunState.new()
	for unit: PBUnit in _units_of(bond):
		state.add_unit(unit)
	var carrier_id: StringName = bond.function_carrier_at(bond.full_tier_count())
	var kept := state.bonded_units(_cfg)
	assert_true(
		PBBondRules.active_functions(kept, kept, _cfg.bonds).has(carrier_id), "不派遣时功能在"
	)

	state.dispatched = 1
	var sent := state.bonded_units(_cfg)
	assert_false(
		PBBondRules.active_functions(sent, kept, _cfg.bonds).has(carrier_id), "派出去就该掉档"
	)


# ── 战斗层 ────────────────────────────────────────────────────


func test_gathering_really_drags_the_pack_onto_the_landing_spot() -> void:
	# 「聚拢」的价值是给别人创造命中数，它自己不多打一点伤害。
	# 所以判据是**位置**：范围内的活人被拖到了同一个点上。
	#
	# 敌人按出场顺序错开、全场同速，所以没有聚拢时任意两个的距离都不相等；
	# 被拖到一起的那几个此后会一直叠着走。这个判据不吃半径和出怪窗口的取值。
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(9)
	var plain := _ultimate_sim(&"", wave)
	var gathered := _ultimate_sim(PBBondFunctionRules.GATHER, wave)
	for _i: int in 120:
		plain.step()
		gathered.step()
	assert_eq(_largest_stack(plain), 1, "不聚拢的话，任意两个敌人都不同位置")
	assert_gt(_largest_stack(gathered), 1, "聚拢该把落点罩住的那几个拖到同一个点上")


func test_pulling_reaches_further_than_plain_gathering() -> void:
	# 单点吸附 = 聚拢 + 半径放大。强化的是**够得着多远**，不是伤害。
	var skill := PBSkill.new()
	skill.radius = _cfg.ultimate_radius
	PBBondFunctionRules.apply_to_skill(skill, PBBondFunctionRules.PULL, _cfg)
	assert_true(skill.gather, "吸附也是一种聚拢")
	assert_gt(skill.radius, _cfg.ultimate_radius, "吸附该够得更远")


func test_rooting_stops_the_advance_and_boosts_damage_in_the_same_window() -> void:
	# §09 把定身和「井野控制期间敌人受伤 +30%」写成同一条功能 ——
	# 那个 +30% 的条件就是这段定身窗口，两者必须同长。
	var skill := PBSkill.new()
	PBBondFunctionRules.apply_to_skill(skill, PBBondFunctionRules.ROOT, _cfg)
	assert_eq(skill.slow_scale, 0.0, "定身就是速度归零")
	assert_gt(skill.team_damage_scale, 1.0, "控制期间该有增伤")
	assert_eq(skill.buff_ticks, skill.slow_ticks, "增伤窗口 = 定身窗口")

	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(9)
	assert_lt(
		_front_progress(PBBondFunctionRules.ROOT, wave),
		_front_progress(&"", wave),
		"定身期间队伍该停在原地"
	)


func test_the_slow_field_lasts_much_longer_than_the_root() -> void:
	# 两者走同一个字段（[member PBSkill.slow_scale]），差别只有「多狠」「多久」。
	# 定身刻意短：M3-d 实测过每波一发的长时全屏控制会把行军队列压扁成一堆，
	# 解除那一刻整群同时涌进交战区，反而更糟。
	var root := PBSkill.new()
	PBBondFunctionRules.apply_to_skill(root, PBBondFunctionRules.ROOT, _cfg)
	var field := PBSkill.new()
	PBBondFunctionRules.apply_to_skill(field, PBBondFunctionRules.SLOW_FIELD, _cfg)
	assert_gt(field.slow_scale, root.slow_scale, "减速力场比定身温和")
	assert_gt(field.slow_ticks, root.slow_ticks, "减速力场比定身持久")


func test_the_slow_field_actually_delays_the_wave() -> void:
	# 减速换的是「敌人晚到多久」—— 塔防里位置操纵就是这么定价的。
	# 所以判据是**队头走了多远**，不是漏了几个：这个大招几乎不打伤害，
	# 漏怪数只反映「有没有人杀得动」，减速在那个数上一位都不会动。
	_cfg.ultimate_delay_seconds = 0.0
	var wave := _wave(9)
	assert_lt(
		_front_progress(PBBondFunctionRules.SLOW_FIELD, wave),
		_front_progress(&"", wave),
		"减速之后队头该走得更近出生点"
	)


func test_the_gold_floor_removes_the_loss_without_moving_the_dice() -> void:
	# §07 说那台老虎机「原版保留不动，别去修」。这个功能不是修它，
	# 是把「关掉波动」做成一个要凑齐羁绊才拿得到的选项。
	#
	# **掷骰次数必须不变**（铁律 3）：少掷一次会让 `combat` 流错位，
	# 于是「带不带这组羁绊」会改变之后每一波的敌人，同种子对拍随之失效。
	var plain_rng := RandomNumberGenerator.new()
	plain_rng.seed = 4242
	var floor_rng := RandomNumberGenerator.new()
	floor_rng.seed = 4242
	var plain: int = PBEconomyRules.kill_drop_income(200, _cfg, plain_rng, false)
	var floored: int = PBEconomyRules.kill_drop_income(200, _cfg, floor_rng, true)
	assert_gt(floored, plain, "关掉倒扣该更赚")
	assert_eq(plain_rng.randf(), floor_rng.randf(), "两条路该掷了同样多次骰子")


func test_the_gold_floor_reaches_the_run_through_the_wave_plan() -> void:
	# 接线测试：功能表在 `lock_plan` 里算好、存进 [PBWavePlan]，
	# 结算那一路从计划里读。各算一遍的话，`dispatched` 被清零之后
	# 再算就会多算一档，且不报错。
	var plan := PBWavePlan.new()
	assert_false(PBBondFunctionRules.grants_gold_floor(plan.bond_functions), "空计划没有功能")
	plan.bond_functions = {&"someone": [PBBondFunctionRules.GOLD_FLOOR] as Array[StringName]}
	assert_true(PBBondFunctionRules.grants_gold_floor(plan.bond_functions), "带上了就该读得到")
	plan.bond_functions = {&"someone": [PBBondFunctionRules.GATHER] as Array[StringName]}
	assert_false(PBBondFunctionRules.grants_gold_floor(plan.bond_functions), "别的功能不管钱")


func test_the_carrier_gets_the_function_through_build_attackers() -> void:
	# 端到端：功能表交给 [method PBCombatRules.build_attackers]，
	# 载体那一位的大招上真的带着聚拢，别人没有。
	var bond := _bond_with_function()
	var units := _units_of(bond)
	var carrier_id: StringName = bond.function_carrier_at(bond.full_tier_count())
	var functions := {carrier_id: [PBBondFunctionRules.GATHER] as Array[StringName]}
	var squad := PBCombatRules.build_attackers(
		units,
		PBElement.Type.PHYSICAL,
		1.0,
		1.0,
		PackedFloat64Array(),
		_cfg,
		null,
		1,
		0,
		functions
	)
	var seen: int = 0
	for i: int in units.size():
		if squad[i].ultimate.skill.gather:
			seen += 1
			assert_eq(units[i].key(), carrier_id, "只有载体该拿到聚拢")
	assert_eq(seen, 1, "一组羁绊只出一个载体 —— 发给全组就变成乘以人数的倍率了")


# ── 夹具 ──────────────────────────────────────────────────────


## 造一组只为验收表检查而生的羁绊。
func _bond(bond_id: StringName, key: StringName, carrier: StringName) -> PBBond:
	var bond := PBBond.new()
	bond.id = bond_id
	bond.name_key = String(bond_id)
	bond.tier_counts = [2]
	bond.tier_power = [0.1]
	bond.tier_function_keys = [key]
	bond.tier_function_carriers = [carrier]
	return bond


## 真表里第一组带功能的命名羁绊。
func _bond_with_function() -> PBBond:
	for bond: PBBond in _cfg.bonds.all():
		if bond.function_at(bond.full_tier_count()) != &"":
			return bond
	fail_test("真羁绊表里该有带功能的组")
	return null


## 一组羁绊的全体成员，各一张卡。
func _units_of(bond: PBBond) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for character: PBCharacter in _cfg.characters.all():
		if bond.counts_character(character):
			out.append(PBUnit.new(character))
	return out


func _wave(index: int) -> PBWave:
	return PBWaveRules.build(index, _cfg, _rng)


## 一场只有「一个带指定功能的大招」的战斗。伤害压到最低，
## 好让位置与速度的变化不被击杀掩盖掉。
func _ultimate_sim(key: StringName, wave: PBWave) -> PBBattleSim:
	var attacker := PBAttacker.new()
	attacker.dps = 0.0
	attacker.reach = 1.0
	var skill := PBSkill.new()
	skill.damage = 1.0
	skill.radius = _cfg.ultimate_radius
	skill.cooldown_ticks = 40
	if key != &"":
		PBBondFunctionRules.apply_to_skill(skill, key, _cfg)
	attacker.ultimate = PBSkillCast.new(skill)
	return PBBattleSim.new(wave, 0.0, 0.0, _cfg, [attacker] as Array[PBAttacker])


## 最密的一小段里挤了几个活着的敌人。
##
## M3.5-c 的防挤之后坐标不再相等（聚拢到同一点的会展开成紧队列），
## 所以尺子是「一小段里有几个」而不是「几个坐标相同」——
## 那也更贴近聚拢真正兑现价值的方式：让一发 AOE 罩住更多人。
## 挤得最紧的那一堆有几个人。**按二维位置数** —— 理由同
## [method PBBeastTest._largest_stack]：一个方阵的一整列共用同一个 x，
## 只看 x 的话「没聚拢」也会数出一堆人来。
func _largest_stack(sim: PBBattleSim) -> int:
	var alive := sim.active_enemies()
	var best: int = 0
	for anchor: PBEnemy in alive:
		var packed: int = 0
		for enemy: PBEnemy in alive:
			if enemy.pos().distance_to(anchor.pos()) <= _cfg.unit_min_gap * 1.5:
				packed += 1
		best = maxi(best, packed)
	return best


## 跑 120 tick 之后队头一共走了多远。减速与定身的唯一直接后果就是这个数 ——
## 这个夹具的大招几乎不打伤害，漏怪数只反映「有没有人杀得动」，控制在那上面一位不动。
func _front_progress(key: StringName, wave: PBWave) -> float:
	var sim := _ultimate_sim(key, wave)
	for _i: int in 120:
		sim.step()
	var walked: float = 0.0
	for enemy: PBEnemy in sim.active_enemies():
		walked = maxf(walked, _cfg.field_length - enemy.distance)
	return walked
