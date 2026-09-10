extends GutTest
## 子弹技能：飞到了才出伤害、才上 buff（M8-b）。
##
## ## 玩家的原话就是判据
##
## 「锁定档也分瞬发技能和子弹技能 —— 医疗忍术就是瞬发，直接给对方上 buff；
## 火球术就是子弹技能，飞到了才出伤。」
##
## 所以这个文件守两件事：**瞬发那一档一个字没变**（M7-c 到 M8-a 的每一天），
## 以及**子弹那一档在飞到之前什么都不发生**。
##
## ## 分界线是 [member PBSkill.shot_cross_seconds]，不是 [member PBSkill.delay_ticks]
##
## 后者是地面档的预判窗口：落点在下达时定死，时间与距离无关。
## 子弹反过来 —— 追着会动的目标，飞多久由距离决定。两件事挤进一个字段的话，
## 「延迟 20 tick」在两档下会是两个意思。

const FIXED_SEED: int = 20260909

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBSimConfig.new()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_cfg.aim_policy = PBAimRules.Policy.NONE
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


## 一个不出手的忍者：这个文件只量技能，普攻会把敌人打光、结论就混了。
func _idle(slot: int = 0) -> PBAttacker:
	var out := PBAttacker.new()
	out.slot = slot
	out.dps = 0.0
	out.attack_speed = 0.0
	out.pos = Vector2(0.2, 0.0)
	out.reach = 0.0
	out.max_hp = 1.0e9
	out.hp = out.max_hp
	out.max_mp = 1000.0
	out.mp = 1000.0
	return out


## 一发中毒/灼烧那一类的周期掉血。
func _burn(per_tick: float) -> PBBuff:
	var buff := PBBuff.new()
	buff.id = &"burn"
	buff.kind = PBBuff.Kind.PERIODIC
	buff.duration_seconds = 2.0
	buff.period_seconds = 1.0
	buff.mods = {PBBuffRules.HARM: per_tick}
	return buff


## 一发打敌人的技能。[param cross] 不为 0 时它是**子弹技能**。
func _fire(damage: float, cross: float) -> PBSkill:
	var skill := PBSkill.new()
	skill.id = &"probe_fire"
	skill.target = PBSkill.Target.ENEMY
	skill.affects = PBSkill.Party.ENEMIES
	skill.damage = damage
	skill.cooldown_ticks = 200
	skill.shot_cross_seconds = cross
	skill.on_hit = [_burn(20.0)]
	return skill


func _armed(squad: Array[PBAttacker], skill: PBSkill) -> PBBattleSim:
	var sim := PBBattleSim.new(PBWaveRules.build(6, _cfg, _rng), 0.0, 0.0, _cfg, squad)
	squad[0].skills.append(PBSkillCast.new(skill))
	squad[0].skills[0].reset()
	return sim


## 第一个已经出场、还活着的敌人。
func _mark(sim: PBBattleSim) -> PBEnemy:
	for enemy: PBEnemy in sim.enemies():
		if enemy.is_active(sim.current_tick()):
			return enemy
	return null


# ── 数据校验：三条都是静默生效的错 ──────────────────────────────


func test_only_a_locked_tier_may_carry_a_flight_speed() -> void:
	# 地面档的飞行时间是 `delay_ticks`（预判窗口），再来一个就是两把尺子；
	# 不挑目标的那一档没有目标可飞，那一发不知道往哪去。
	for tier: PBSkill.Target in [PBSkill.Target.GROUND, PBSkill.Target.NONE]:
		var skill := PBSkill.new()
		skill.target = tier
		skill.affects = PBSkill.Party.ENEMIES
		skill.shot_cross_seconds = 0.4
		assert_ne(PBSkillRules.validate(skill), "", "这一档不该收飞行速度")
	assert_eq(PBSkillRules.validate(_fire(10.0, 0.4)), "", "点敌人那一档配得")


func test_a_bullet_skill_may_not_carry_the_field_wide_words() -> void:
	# 那五个字段是 §11 尾兽与 §09 功能档的词汇，全部挂在地面档的大招上。
	# 子弹这一发只结算「打中的那一个」，配了**不会生效** ——
	# 而「配了不生效」比「配不了」难查得多。
	var pull := _fire(10.0, 0.4)
	pull.gather = true
	assert_ne(PBSkillRules.validate(pull), "", "聚拢该被拦下来")

	var slow := _fire(10.0, 0.4)
	slow.slow_ticks = 40
	slow.slow_scale = 0.5
	assert_ne(PBSkillRules.validate(slow), "", "全场减速也是")

	var boost := _fire(10.0, 0.4)
	boost.buff_ticks = 40
	boost.team_damage_scale = 1.2
	assert_ne(PBSkillRules.validate(boost), "", "全队增伤也是")


# ── 飞到了才出伤 ────────────────────────────────────────────────


func test_the_damage_waits_for_the_bullet_to_arrive() -> void:
	# **正题。** 出膛那一刻目标一点血都不该掉。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(500.0, 0.6))
	sim.step()
	var mark := _mark(sim)
	var full: float = mark.hp

	assert_true(sim.cast_skill_at(squad[0], mark, 1), "点了敌人就该下得了令")
	sim.step()
	assert_almost_eq(mark.hp, full, 1e-9, "出膛那一刻一点血都不掉")
	assert_gt(_flying(sim), 0, "而是有一发真的在飞")

	for _i: int in 40:
		sim.step()
		if mark.hp < full:
			break
	assert_lt(mark.hp, full, "飞到了才掉血")
	assert_eq(_flying(sim), 0, "而且那一发到此为止，不会接着飞")


func test_the_buff_waits_for_the_bullet_too() -> void:
	# 挂在出膛那一刻的话，一发飞了半秒的火球会在目标还没挨到时就把他点燃。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(1.0, 0.6))
	sim.step()
	var mark := _mark(sim)

	sim.cast_skill_at(squad[0], mark, 1)
	sim.step()
	assert_almost_eq(
		mark.buffs.amount(PBBuffRules.HARM, sim.current_tick()), 0.0, 1e-9, "还在飞，没上身"
	)

	for _i: int in 40:
		sim.step()
		if mark.buffs.amount(PBBuffRules.HARM, sim.current_tick()) > 0.0:
			break
	assert_gt(
		mark.buffs.amount(PBBuffRules.HARM, sim.current_tick()), 0.0, "飞到了才上 buff"
	)


func test_an_instant_locked_skill_still_lands_the_moment_it_goes_off() -> void:
	# **瞬发那一档一个字没变**（医疗忍术走的就是它）：
	# 加一个字段不该把已经在跑的那一档改掉。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(500.0, 0.0))
	sim.step()
	var mark := _mark(sim)
	var full: float = mark.hp

	sim.cast_skill_at(squad[0], mark, 1)
	sim.step()
	assert_lt(mark.hp, full, "瞬发的当场就结算，不发子弹")
	assert_eq(_flying(sim), 0, "屏幕上也不该有东西在飞")


func test_the_cooldown_starts_when_the_bullet_leaves() -> void:
	# `is_pending` 那个状态的全部意义是「落点已定、还没结算」——
	# 也就是地面档的预判窗口。子弹追着目标走，没有预判可言，
	# 所以出膛就是这一发结束的时刻。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(10.0, 0.6))
	sim.step()
	var cast := PBSkillRules.cast_at(squad[0], 1)
	sim.cast_skill_at(squad[0], _mark(sim), 1)
	sim.step()

	assert_false(cast.is_pending(), "手上没有待落地的东西了 —— 它已经飞出去了")
	assert_gt(cast.ready_at, 0, "冷却从出膛算起")
	assert_false(sim.can_cast(squad[0], 1), "所以这一格立刻转灰")


func test_a_bullet_whose_target_dies_mid_flight_just_vanishes() -> void:
	# 「目标死了子弹就消失，不改打别人」—— 同 [PBProjectile] 顶上那条。
	# 改打别人的话，一发子弹等于永远不会浪费。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(500.0, 0.9))
	sim.step()
	var mark := _mark(sim)
	sim.cast_skill_at(squad[0], mark, 1)
	sim.step()
	assert_gt(_flying(sim), 0, "前提：有一发在飞")

	mark.alive = false
	var before: int = sim.result().kills
	for _i: int in 40:
		sim.step()
	assert_eq(_flying(sim), 0, "那一发消失了")
	assert_eq(sim.result().kills, before, "而且没有转头打死别人")


func test_a_dead_caster_cannot_get_one_off() -> void:
	# 门槛在放出去那一刻重新过一遍（M7-h 的指令队列）——
	# 施法者死了，攒着的那条就该丢掉。
	var squad: Array[PBAttacker] = [_idle()]
	var sim := _armed(squad, _fire(500.0, 0.6))
	sim.step()
	sim.cast_skill_at(squad[0], _mark(sim), 1)
	squad[0].alive = false
	sim.step()
	assert_eq(_flying(sim), 0, "死人的那一条令不放出去")


# ── 数据那一侧 ──────────────────────────────────────────────────


func test_the_table_has_a_real_bullet_skill() -> void:
	# **按形状找，不按 id 找**（M12-c1 改的）。
	#
	# 这两条原来点名 `fireball` 与 `medical_ninjutsu` —— 那是 M7-g/M8-b
	# 手写的两个样本，而 `data/skills.tsv` 一接管，表里装的就是原版那 113 个，
	# 两个样本当场没了。红的是「名册换了人」，不是「子弹技能坏了」。
	#
	# 它们要问的本来就是**表里两种都有**：分界线
	# （[member PBSkill.shot_cross_seconds]）是数据的事，不是代码的事。
	var table := PBSkillLoader.table()
	var bullets: Array[PBSkill] = []
	for id: StringName in table.ids():
		var skill: PBSkill = table.by_id(id)
		if skill.target == PBSkill.Target.ENEMY and skill.shot_cross_seconds > 0.0:
			bullets.append(skill)
	assert_false(bullets.is_empty(), "表里该有点敌人的子弹技能")
	for skill: PBSkill in bullets:
		assert_eq(PBSkillRules.validate(skill), "", "%s 该合法" % skill.id)
		assert_false(
			skill.on_hit.is_empty(), "%s 飞到了得干点什么 —— 子弹档的伤害或效果都挂在命中上" % skill.id
		)


func test_the_medic_stays_instant() -> void:
	# 同一张表里两种都有，才说明那条分界线是数据的事、不是代码的事。
	var table := PBSkillLoader.table()
	var medics: Array[PBSkill] = []
	for id: StringName in table.ids():
		var skill: PBSkill = table.by_id(id)
		if skill.target == PBSkill.Target.ALLY:
			medics.append(skill)
	assert_false(medics.is_empty(), "表里该有点队友的技能")
	for skill: PBSkill in medics:
		assert_eq(skill.shot_cross_seconds, 0.0, "%s 点的是队友，该瞬发直接上 buff" % skill.id)


## 现在有几发子弹在飞。
func _flying(sim: PBBattleSim) -> int:
	var count: int = 0
	for shot: PBProjectile in sim.shots():
		if shot.alive:
			count += 1
	return count
