extends GutTest
## 技能的两根轴：**点什么**（[enum PBSkill.Target]）与**落在谁**
## （[enum PBSkill.Party]）。M7-c。
##
## ## 这个文件守的是「新形状没有踩坏旧形状」
##
## M7-b 之前每一发大招都是「点一块地」，所以「有落点」和「有一发在路上」
## 一直是同义词。`NONE` 档进来之后那条等价关系断了 —— 它既没有落点、
## 也没有锁定谁，**但照样有一发在路上**。哨兵因此从 `spot` 换到了
## `lands_at`（[method PBSkillCast.is_pending]），而那次替换必须对
## 地面档**逐位等价**，否则每一条既有的大招断言都会跟着变。
##
## 另外两条压在具体行为上：
##
## - **目标死了 → 空放，不崩也不改打别人**（下达和落地之间隔着一个 tick）
## - **只有地面档能配施法延迟** —— 锁定目标的技能没有预判可言

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBSimConfig.new()
	# 自动档会在开波第一 tick 替玩家把地面技能放掉，那会盖住手动那几条
	# 断言想量的东西（见 `test_battle_control.gd` 里同一条设置）。
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_cfg.spawn_window = 0.0


func _wave() -> PBWave:
	return PBWaveRules.build(4, _cfg, RandomNumberGenerator.new())


## 一份瞬间回血的效果。[param per_level] 不为 0 时它随施法者等级长（决策 7）。
func _heal(amount: float, per_level: float = 0.0) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = &"cure"
	buff.kind = PBBuff.Kind.INSTANT
	buff.mods = {PBBuffRules.HEAL: amount}
	if per_level != 0.0:
		buff.mods_growth = {PBBuffRules.HEAL: per_level}
	return buff


## 一个能挨打、能被治的己方单位。
func _ally(slot: int = 0) -> PBAttacker:
	var out := PBAttacker.new()
	out.slot = slot
	out.max_hp = 500.0
	out.reach = _cfg.field_diagonal()
	out.prime(_cfg.tick_rate)
	out.revive()
	return out


## 给 [param attacker] 装一个技能。[param caster_level] 走决策 7 的等级缩放。
func _give(
	attacker: PBAttacker,
	target: PBSkill.Target,
	affects: PBSkill.Party,
	caster_level: int = 1
) -> PBSkill:
	var skill := PBSkill.new()
	skill.target = target
	skill.affects = affects
	skill.cooldown_ticks = 10000
	attacker.ultimate = PBSkillCast.new(skill, caster_level)
	return skill


# ── 两根轴的数据校验 ────────────────────────────────────────────


func test_pointing_at_a_friend_but_hitting_enemies_is_rejected() -> void:
	# 点谁和打谁在这两档上不可能是两个方向。写反了不报错，
	# 只会「点了一个队友然后他掉血」。
	var skill := PBSkill.new()
	skill.target = PBSkill.Target.ALLY
	skill.affects = PBSkill.Party.ENEMIES
	assert_ne(PBSkillRules.validate(skill), "", "ALLY 却打敌人该被拦下来")
	skill.affects = PBSkill.Party.ALLIES
	assert_eq(PBSkillRules.validate(skill), "", "配对了就该放行")


func test_pointing_at_an_enemy_but_hitting_friends_is_rejected() -> void:
	var skill := PBSkill.new()
	skill.target = PBSkill.Target.ENEMY
	skill.affects = PBSkill.Party.ALLIES
	assert_ne(PBSkillRules.validate(skill), "", "ENEMY 却打自己人该被拦下来")


func test_only_the_ground_tier_may_carry_a_cast_delay() -> void:
	# 施法延迟存在的全部理由是地面档的预判窗口（[PBSkill] 顶部）。
	# 锁定目标的技能没有预判可言：目标跟着走，落点也跟着走。
	for target: PBSkill.Target in [
		PBSkill.Target.NONE, PBSkill.Target.ALLY, PBSkill.Target.ENEMY
	]:
		var skill := PBSkill.new()
		skill.target = target
		skill.affects = (
			PBSkill.Party.ALLIES
			if target == PBSkill.Target.ALLY
			else PBSkill.Party.ENEMIES
		)
		skill.delay_ticks = 6
		assert_ne(PBSkillRules.validate(skill), "", "第 %d 档不该配得上延迟" % target)
		skill.delay_ticks = 0
		assert_eq(PBSkillRules.validate(skill), "", "延迟归零就该放行")

	var ground := PBSkill.new()
	ground.delay_ticks = 6
	assert_eq(PBSkillRules.validate(ground), "", "地面档配延迟才是它该有的样子")


func test_a_plain_skill_is_a_ground_skill() -> void:
	# **默认值就是 M7-b 之前那一种大招。** 既有的每一发都没碰过这两个字段，
	# 默认取错的话它们会集体换一种落地方式，而那不报错。
	var skill := PBSkill.new()
	assert_eq(skill.target, PBSkill.Target.GROUND, "不填就是点一块地")
	assert_eq(skill.affects, PBSkill.Party.ENEMIES, "不填就是打敌人")
	assert_eq(PBSkillRules.validate(skill), "", "而且它天然合法")


# ── 锁定队友（医疗忍术那一档）──────────────────────────────────


func test_a_heal_reaches_the_one_who_was_pointed_at() -> void:
	var medic := _ally(0)
	var hurt := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	skill.on_hit = [_heal(120.0)]
	var squad: Array[PBAttacker] = [medic, hurt]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	# 开波会 revive（满血），所以掉血放在那之后。
	hurt.hp = 100.0
	medic.hp = 100.0
	assert_true(sim.cast_ultimate_on(medic, hurt), "点了队友就该放得出")
	sim.step()
	assert_almost_eq(hurt.hp, 220.0, 0.001, "被点的那个该回血")
	assert_almost_eq(medic.hp, 100.0, 0.001, "没被点的施法者自己不该跟着回")


func test_a_target_that_dies_before_impact_is_a_dud_not_a_crash() -> void:
	# **下达和落地之间隔着一个 tick**，那一 tick 里目标可能被打死。
	# 正确的行为是什么都不做 —— 改打别人的话，玩家点的那个人
	# 和实际受益的人不是同一个，而他不会知道。
	var medic := _ally(0)
	var doomed := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	skill.on_hit = [_heal(120.0)]
	var squad: Array[PBAttacker] = [medic, doomed]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	assert_true(sim.cast_ultimate_on(medic, doomed), "先放出去")
	doomed.alive = false
	doomed.hp = 0.0
	sim.step()
	assert_eq(doomed.hp, 0.0, "死人不该被治起来")
	assert_false(medic.ultimate.is_pending(), "那一发照样落完地，不会卡在手上")
	sim.step()
	assert_true(true, "而且战斗照常往下跑")


func test_a_dead_friend_cannot_be_pointed_at_in_the_first_place() -> void:
	var medic := _ally(0)
	var corpse := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	skill.on_hit = [_heal(120.0)]
	var squad: Array[PBAttacker] = [medic, corpse]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	corpse.alive = false
	assert_false(sim.cast_ultimate_on(medic, corpse), "死人身上放不了")
	assert_true(sim.can_cast(medic), "而且冷却一点都没动")


## 一个 [param level] 级的医疗兵治一个残血队友，返回队友治完剩多少血。
func _heal_at_level(level: int) -> float:
	var medic := _ally(0)
	var patient := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES, level)
	skill.on_hit = [_heal(80.0, 14.0)]
	var squad: Array[PBAttacker] = [medic, patient]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	patient.hp = 100.0
	sim.cast_ultimate_on(medic, patient)
	sim.step()
	return patient.hp


func test_the_heal_grows_with_the_casters_level() -> void:
	# 决策 7 走通到落地那一刻：同一份效果，10 级的人放出来更厚。
	assert_almost_eq(_heal_at_level(1), 180.0, 0.001, "1 级取基数")
	assert_almost_eq(_heal_at_level(10), 100.0 + 80.0 + 14.0 * 9.0, 0.001, "10 级每级加一份")


func test_a_skill_edited_after_it_was_wrapped_still_takes_effect() -> void:
	# **建好之后还会被改**：[method PBBondFunctionRules.apply_to_skill]
	# 就是在 [PBSkillCast] 之外改同一份 [PBSkill]。所以效果数值只能
	# **用的时候现算**；提前算好一份存起来的话，后改的那一下不会跟着更新，
	# 而它不报错 —— 表现是「这个羁绊功能好像没生效」。
	var medic := _ally(0)
	var patient := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	var squad: Array[PBAttacker] = [medic, patient]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	# 包完之后才往技能上装效果 —— 顺序反过来也必须一样。
	skill.on_hit = [_heal(70.0)]
	patient.hp = 100.0
	sim.cast_ultimate_on(medic, patient)
	sim.step()
	assert_almost_eq(patient.hp, 170.0, 0.001, "后装上去的效果照样要生效")


# ── 不用挑目标那一档 ────────────────────────────────────────────


func test_a_self_buff_lands_the_moment_it_is_ordered() -> void:
	# 人已经把技能交出去了，自增益却要等落地才生效的话，
	# 玩家看到的是「按下去没反应」。
	var caster := _ally(0)
	var skill := _give(caster, PBSkill.Target.NONE, PBSkill.Party.ALLIES)
	skill.on_self = [_heal(90.0)]
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	caster.hp = 100.0
	assert_true(sim.cast_ultimate_now(caster), "不用挑目标，按下去就该放得出")
	assert_almost_eq(caster.hp, 190.0, 0.001, "**下达那一刻**就该回上，不用等下一 tick")


func test_a_field_wide_strike_reaches_everyone_regardless_of_distance() -> void:
	# 打全场和地面档的区别只有一条：那一个按半径圈人，这一个不圈。
	var caster := _ally(0)
	var skill := _give(caster, PBSkill.Target.NONE, PBSkill.Party.ENEMIES)
	var wave := _wave()
	skill.damage = wave.hp_each * 2.0
	# 半径留 0：地面档这么配一个人都打不到，而打全场压根不看它。
	skill.radius = 0.0
	var squad: Array[PBAttacker] = [caster]
	var sim := PBBattleSim.new(wave, 0.0, 0.0, _cfg, squad)
	assert_true(sim.cast_ultimate_now(caster), "该放得出")
	sim.step()
	assert_eq(sim.result().kills, wave.count, "整波都该吃到，半径一点都不管用")


# ── 入口对不上就不放，而且不吞冷却 ──────────────────────────────


func test_each_entry_only_takes_the_shape_it_is_for() -> void:
	# 拿错入口时**不能进冷却** —— 吞掉一次冷却的表现是
	# 「我明明还没放，怎么就要等 20 秒」（M4-e 那条已经付过一次账）。
	var caster := _ally(0)
	var mate := _ally(1)
	_give(caster, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	var squad: Array[PBAttacker] = [caster, mate]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	assert_false(sim.cast_ultimate(caster, Vector2(0.5, 0.1)), "锁定档不吃落点")
	assert_false(sim.cast_ultimate_now(caster), "也不吃「不挑目标」那条")
	assert_true(sim.can_cast(caster), "两次都被拒之后冷却该一点没动")
	assert_true(sim.cast_ultimate_on(caster, mate), "对的那条照样放得出")


func test_the_automatic_policy_never_fires_a_targeted_skill() -> void:
	# 自动档答的是「往哪块地放」，它不知道该治谁 ——
	# 所以锁定档只有手动入口，而 §6 那条「批量扫描不吃技能」正是这个意思。
	_cfg.aim_policy = PBAimRules.Policy.AUTO
	var medic := _ally(0)
	var hurt := _ally(1)
	var skill := _give(medic, PBSkill.Target.ALLY, PBSkill.Party.ALLIES)
	skill.on_hit = [_heal(120.0)]
	var squad: Array[PBAttacker] = [medic, hurt]
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, squad)
	hurt.hp = 100.0
	for _i: int in 40:
		sim.step()
	assert_almost_eq(hurt.hp, 100.0, 0.001, "没人下令就一发都不该出去")
	assert_true(sim.can_cast(medic), "冷却也该还在原地")
