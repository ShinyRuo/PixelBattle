extends GutTest
## 敌人打在忍者身上那条漏斗（[method PBStrikeRules.hurt_ally]，M12-c2）。

## ## 这个文件守的是什么
##
## 它和 [method PBStrikeRules.land] 是对称的两半：那一头答「我方打敌人」，
## 这一头答「敌人打我方」。在它之前这件事发生在两处
## （近战在 [PBBattleSim]、子弹在 [PBShotRules]），各写一遍
## 「折算 → 记播报 → 扣血 → 记阵亡」—— 那还只是重复；
## 往后面接反弹之后，**漏一处的表现是「被子弹打不反弹」**，而它不报错。
##
## 同 M10-d 那两条（[method PBStrikeRules.land] 唯一、重生判在
## [method PBAttacker.take_damage] 里面），也同 M12-c2 的闪避。

const SHOT_PATH := "res://src/core/rules/shot_rules.gd"
const SIM_PATH := "res://src/core/sim/battle_sim.gd"

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()

# ── 反弹：挨打那一侧的漏斗 ────────────────────────────────────


func test_both_ways_of_being_hit_go_through_the_same_funnel() -> void:
	# **同 [method PBStrikeRules.land] 那条。** 敌人打己方有两个落点
	# （近战在 `battle_sim`、子弹在 `shot_rules`），各写一遍
	# 「折算 → 记播报 → 扣血 → 记阵亡」之后再接反弹，
	# **漏一处的表现是「被子弹打不反弹」**，而它不报错。
	for path: String in [SIM_PATH, SHOT_PATH]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "读得到 %s" % path)
		assert_eq(
			text.split("PBStrikeRules.hurt_ally(").size() - 1, 1, "%s 该只调一次漏斗" % path
		)
		assert_false(text.contains("reflect"), "%s 不该自己判反弹" % path)


func test_both_sites_hand_the_dice_over_to_the_funnel() -> void:
	# 漏传一个 rng 今天是**解析错误**（那个参数没有默认值），
	# 所以这条拦的是另一半：**传进去的是不是真骰子**。
	# 随手填一个 null 会让那一路永远不闪避，**而它不报错**。
	for path: String in [SIM_PATH, SHOT_PATH]:
		var text := FileAccess.get_file_as_string(path)
		var at: int = text.find("PBStrikeRules.hurt_ally(")
		assert_gt(at, -1, "%s 该调一次漏斗" % path)
		var call: String = text.substr(at, 300)
		assert_true(call.contains("rng"), "%s 得把真骰子递进漏斗" % path)


func test_the_damage_comes_back_at_whoever_dealt_it() -> void:
	var target := _hurtable(0.0)
	target.reflect = 0.5
	target.slot = 0
	var enemy := _enemy()
	var out := PBCombatOutcome.new()
	var full: float = enemy.hp
	PBStrikeRules.hurt_ally(
		target, enemy, 100.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_lt(enemy.hp, full, "打人的那个该跟着掉血")
	assert_almost_eq(
		full - enemy.hp, (target.max_hp - target.hp) * 0.5, 0.001, "还回去的是挨的那一下的五成"
	)


func test_a_dodged_hit_still_comes_back() -> void:
	# 原版那一条是「免疫此次伤害**并**反弹 30%」—— 两件事一起发生。
	# 我们把它拆成两个能各自单独配的键，但顺序仍然对得上：
	# 闪避在 `take_damage` 里返回 false，而反弹排在它外面。
	var target := _hurtable(1.0)
	target.reflect = 0.5
	var enemy := _enemy()
	var out := PBCombatOutcome.new()
	var full: float = enemy.hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	PBStrikeRules.hurt_ally(
		target, enemy, 100.0, PBElement.Type.PHYSICAL, _cfg, 0, rng, null, out
	)
	assert_eq(target.hp, target.max_hp, "闪掉了就一点不掉")
	assert_lt(enemy.hp, full, "但那一下照样还回去")


func test_a_kill_by_reflection_is_counted_exactly_once() -> void:
	# **记账只有一个来源。** 反弹打死的那一个在漏斗里记，放回调用方的话
	# 杀敌数就有了第二个来源 —— 同「周期伤害不在规则层当场扣血」那条。
	var target := _hurtable(0.0)
	target.reflect = 100.0
	var enemy := _enemy()
	enemy.max_hp = 1.0
	enemy.hp = 1.0
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(
		target, enemy, 10.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_false(enemy.alive, "该被反弹打死")
	assert_eq(out.kills, 1, "记一次，不多不少")


func test_nothing_comes_back_from_a_corpse() -> void:
	# 那一发飞到的时候放它的人可能已经死了（子弹那一路查得到 null）。
	var target := _hurtable(0.0)
	target.reflect = 0.5
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(
		target, null, 100.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_eq(out.kills, 0, "没有来源就没有反弹，也不该崩")
	assert_lt(target.hp, target.max_hp, "但他自己照样挨了这一下")


func test_without_a_reflect_nothing_changes_at_all() -> void:
	# 同 M3.5-f 装备那条「空着 = 一字不差」：没配反弹时敌人一点血都不许掉。
	var target := _hurtable(0.0)
	var enemy := _enemy()
	var out := PBCombatOutcome.new()
	var full: float = enemy.hp
	PBStrikeRules.hurt_ally(
		target, enemy, 100.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_eq(enemy.hp, full, "没配就一点都不该掉")


func test_only_the_named_element_is_scaled() -> void:
	# 霸气「降低 55% 的风属性伤害」：风那一下乘 0.45，别的系一点不变；减到负数也只是不掉血。
	var out := PBCombatOutcome.new()
	var lost := {}
	for element: PBElement.Type in [PBElement.Type.WIND, PBElement.Type.FIRE]:
		var plain := _hurtable(0.0)
		var guarded := _hurtable(0.0)
		PBPassiveRules.grant(guarded, PBPassiveRules.WIND_TAKEN, -0.55)
		for one: PBAttacker in [plain, guarded]:
			PBStrikeRules.hurt_ally(one, null, 100.0, element, _cfg, 0, null, null, out)
		lost[element] = [plain.max_hp - plain.hp, guarded.max_hp - guarded.hp]
	var wind: Array = lost[PBElement.Type.WIND]
	assert_almost_eq(wind[1], wind[0] * 0.45, 0.001, "风系那一下少掉 55%")
	var fire: Array = lost[PBElement.Type.FIRE]
	assert_almost_eq(fire[1], fire[0], 0.001, "别的系不变")
	var stone := _hurtable(0.0)
	PBPassiveRules.grant(stone, PBPassiveRules.FIRE_TAKEN, -3.0)
	PBStrikeRules.hurt_ally(stone, null, 100.0, PBElement.Type.FIRE, _cfg, 0, null, null, out)
	assert_eq(stone.hp, stone.max_hp, "减过头也只是不掉，不会变成回血")


func _enemy() -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100000.0
	out.hp = out.max_hp
	out.slot = 0
	return out


# ── 闪避：判在挨打那一侧 ──────────────────────────────────────


func test_dodging_is_decided_inside_take_damage_not_by_the_callers() -> void:
	# **同 M10-d 重生那条。** 己方挨打有两个落点（敌人近战在 `battle_sim`、
	# 敌人子弹在 `shot_rules`），各判一次的表现是「被子弹打就闪不掉」，
	# 而它不报错。判据是**扫源码**：那两个文件里不许出现 `dodge`。
	for path: String in [SIM_PATH, SHOT_PATH]:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", "读得到 %s" % path)
		assert_false(text.contains("dodge"), "%s 不该自己判闪避，那是 take_damage 里面的事" % path)


func test_nobody_dodges_without_a_chance_and_no_dice_are_rolled() -> void:
	# **0 时一次都不掷** —— 同 [method PBCritRules.strike] 顶上那条：
	# 掷了就算没闪也已经拨动了那条流，而 `whole_field` 那条与解析式
	# 排队模型逐位对拍的退化路径靠的就是「该掷几次就掷几次」。
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var before: int = rng.state
	var plain := _hurtable(0.0)
	assert_false(PBPassiveRules.dodges(plain, rng, 0), "没配就不该闪")
	assert_eq(rng.state, before, "没配就一步都不许走")
	var lucky := _hurtable(0.6)
	PBPassiveRules.dodges(lucky, rng, 0)
	assert_ne(rng.state, before, "配了就该拨动那条流")


func test_a_dodged_hit_costs_nothing_at_all() -> void:
	# 闪避是「一点血都不掉」，不是「少掉一点」—— 后者是减伤
	# （[constant PBBuffRules.DAMAGE_TAKEN]），两件事。
	var one := _hurtable(1.0)
	var full: float = one.hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_false(one.take_damage(500.0, 0, rng), "闪掉了就不该死")
	assert_eq(one.hp, full, "一点都不该掉")


func test_without_dice_nobody_ever_dodges() -> void:
	# 批量扫描、悬崖二分、老的构造点都不给 rng —— 那一路必须
	# 和没有闪避这件事**完全一样**，否则全部既有配平数字会随这一步漂移。
	var one := _hurtable(1.0)
	one.take_damage(10.0, 0)
	assert_lt(one.hp, one.max_hp, "不给骰子就照常挨打")

## 一个满血、打不死的忍者。
func _hurtable(dodge: float) -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 1000.0
	one.hp = 1000.0
	one.alive = true
	one.dodge = dodge
	return one

