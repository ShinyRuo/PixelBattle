extends GutTest
## 致命伤与阵亡那一刻（死司凭血、伊邪那岐、阵亡时放的技能），以及「落在一圈队友身上」的技能。
##
## 这里错了都不报错：光环技能按了扣蓝进冷却、谁身上都没有效果；致命伤抵挡花掉了重生；
## 阵亡技能打死的怪不进账；羁绊发的阵亡技能跑进了指令卡。

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260914


func _buff(id: StringName, kind: PBBuff.Kind, seconds: float, mods: Dictionary) -> PBBuff:
	var out := PBBuff.new()
	out.id = id
	out.kind = kind
	out.duration_seconds = seconds
	out.mods = mods
	return out


func _fighter(at: Vector2, hp: float = 1000.0) -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = hp
	one.attack = 10.0
	one.attack_speed = 1.0
	one.reach = 0.05
	one.pos = at
	one.home = at
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


func _cast(skill: PBSkill) -> PBSkillCast:
	return PBSkillCast.new(skill, 1)


# ── 落在一圈队友身上 ────────────────────────────────────────────


func test_an_ally_aura_skill_lands_on_everyone_in_its_radius() -> void:
	var skill := PBSkill.new()
	skill.id = &"probe_aura"
	skill.target = PBSkill.Target.NONE
	skill.affects = PBSkill.Party.ALLIES
	skill.radius = 0.1
	skill.on_hit = [_buff(&"probe_boost", PBBuff.Kind.DURATION, 5.0, {&"damage_scale": 1.5})]
	var me := _fighter(Vector2(0.2, 0.0))
	var near := _fighter(Vector2(0.25, 0.0))
	var far := _fighter(Vector2(0.6, 0.0))
	var squad: Array[PBAttacker] = [me, near, far]
	PBSkillRules.land_around_allies(_cast(skill), me.pos, squad, _cfg, 1)
	assert_eq(me.buffs.amount(PBBuffRules.DAMAGE_SCALE, 1), 1.5, "施法者自己也在圈里")
	assert_eq(near.buffs.amount(PBBuffRules.DAMAGE_SCALE, 1), 1.5, "圈里的队友挂上了")
	assert_eq(far.buffs.amount(PBBuffRules.DAMAGE_SCALE, 1), 1.0, "圈外的没有")


func test_every_ally_skill_on_the_roster_really_lands_in_a_battle() -> void:
	# 真表上的「不用点 / 点地面 + 落在我方 + 挂效果」每一个都按一次，施法者自己身上必须多出东西。
	# 这一条抓的正是那个 bug：`_land_skill` 里「不用点」只处理打敌人，落在我方的直接跳过。
	var seen: int = 0
	for character: PBCharacter in _cfg.characters.all():
		for i: int in character.skill_ids.size():
			var skill: PBSkill = _cfg.skills.by_id(character.skill_ids[i])
			if skill == null or skill.affects != PBSkill.Party.ALLIES:
				continue
			if skill.target != PBSkill.Target.NONE or skill.on_hit.is_empty():
				continue
			var units: Array[PBUnit] = [PBUnit.new(character)]
			var squad := PBCombatRules.build_attackers(
				units, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), _cfg
			)
			squad[0].ultimate = null
			var sim := PBBattleSim.new(PBWaveRules.build(20, _cfg, _rng), 0.0, 0.0, _cfg, squad)
			sim.step()
			squad[0].mp = squad[0].max_mp
			assert_true(sim.cast_skill_now(squad[0], i + 1), "%s 该放得出" % skill.id)
			PBCastTestClock.release(sim, squad[0])
			sim.step()
			assert_gt(squad[0].buffs.count(sim.current_tick()), 0, "%s 放完身上该有效果" % skill.id)
			seen += 1
	assert_gt(seen, 0, "前提：真表里有这种技能")


# ── 致命伤 ──────────────────────────────────────────────────────


func test_a_lethal_blow_is_blocked_once_a_wave_and_hangs_the_buffs() -> void:
	var one := _fighter(Vector2(0.2, 0.0))
	one.lethal_buffs = [_buff(&"probe_mend", PBBuff.Kind.INSTANT, 0.0, {&"heal_max": 0.5})]
	one.revive()
	var out := PBCombatOutcome.new()
	assert_false(PBStrikeRules.wound_ally(one, 5000.0, _cfg, 1, null, null, out), "第一下挡住了")
	assert_true(one.alive, "还站着")
	assert_almost_eq(one.hp, 1.0 + 500.0, 0.001, "血停在 1，再回 50% 最大生命")
	assert_true(PBStrikeRules.wound_ally(one, 5000.0, _cfg, 2, null, null, out), "一波只挡一次")
	one.revive()
	assert_false(PBStrikeRules.wound_ally(one, 5000.0, _cfg, 3, null, null, out), "开波重新待命")


func test_blocking_a_lethal_blow_does_not_spend_a_revive() -> void:
	var one := _fighter(Vector2(0.2, 0.0))
	one.lethal_buffs = [_buff(&"probe_mend", PBBuff.Kind.INSTANT, 0.0, {&"heal_max": 0.5})]
	one.revives_max = 1
	one.revive()
	PBStrikeRules.wound_ally(one, 5000.0, _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(one.revives, 1, "挡得住就不该花掉重生")


func test_undying_keeps_him_up_until_it_runs_out() -> void:
	var one := _fighter(Vector2(0.2, 0.0))
	var hold := _buff(&"probe_hold", PBBuff.Kind.DURATION, 1.0, {&"undying": 1.0})
	PBSkillRules.apply_one(one, hold, hold.mods, _cfg, 0)
	var out := PBCombatOutcome.new()
	PBStrikeRules.wound_ally(one, 5000.0, _cfg, 5, null, null, out)
	PBStrikeRules.wound_ally(one, 5000.0, _cfg, 10, null, null, out)
	assert_true(one.alive, "不死期间怎么打都停在 1")
	assert_eq(one.hp, 1.0, "血停在 1")
	var late: int = _cfg.tick_rate + 1
	assert_true(PBStrikeRules.wound_ally(one, 5000.0, _cfg, late, null, null, out), "过期就倒")


func test_the_end_of_undying_heals_once_if_still_standing() -> void:
	# 〔不死二人组〕「死司凭血持续时间结束后能够恢复 20% 的生命值」。
	var one := _fighter(Vector2(0.2, 0.0))
	one.undying_end_heal = 0.2
	var hold := _buff(&"probe_hold", PBBuff.Kind.DURATION, 1.0, {&"undying": 1.0})
	PBSkillRules.apply_one(one, hold, hold.mods, _cfg, 0)
	PBStrikeRules.wound_ally(one, 5000.0, _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(one.hp, 1.0, "前提：不死期间血停在 1")
	for tick: int in range(1, _cfg.tick_rate + 1):
		PBBuffRules.advance_ally(one, tick, _cfg.tick_rate)
	assert_eq(one.hp, 1.0, "没到期不回")
	for tick: int in range(_cfg.tick_rate + 1, _cfg.tick_rate * 3):
		PBBuffRules.advance_ally(one, tick, _cfg.tick_rate)
	assert_almost_eq(one.hp, 1.0 + 200.0, 0.001, "到期那一刻回 20% 最大生命，只回一次")
	var plain := _fighter(Vector2(0.2, 0.0))
	plain.hp = 1.0
	PBSkillRules.apply_one(plain, hold, hold.mods, _cfg, 0)
	for tick: int in range(0, _cfg.tick_rate * 3):
		PBBuffRules.advance_ally(plain, tick, _cfg.tick_rate)
	assert_eq(plain.hp, 1.0, "没配这个键就不回")


# ── 阵亡时放 ────────────────────────────────────────────────────


func _burst(affects: PBSkill.Party) -> PBSkill:
	var skill := PBSkill.new()
	skill.id = &"probe_burst"
	skill.target = PBSkill.Target.GROUND
	skill.affects = affects
	skill.radius = 10.0
	skill.fires_on_death = true
	return skill


func test_a_death_cast_hits_the_enemies_and_the_kills_are_booked() -> void:
	var one := _fighter(Vector2(0.2, 0.0), 1.0e9)
	var burst := _burst(PBSkill.Party.ENEMIES)
	burst.damage = 1.0e9
	var squad: Array[PBAttacker] = [one]
	var sim := PBBattleSim.new(PBWaveRules.build(20, _cfg, _rng), 0.0, 0.0, _cfg, squad)
	one.death_casts = [_cast(burst)]
	for _i: int in 40:
		sim.step()
	var before: int = sim.result().kills
	PBStrikeRules.wound_ally(one, 1.0e10, _cfg, sim.current_tick(), null, null, sim.result())
	assert_false(one.alive, "前提：他倒下了")
	sim.step()
	assert_gt(sim.result().kills, before, "阵亡技能打死的怪要进账")
	assert_false(one.death_pending, "放过就清")


func test_a_death_cast_can_heal_the_allies_around_the_body() -> void:
	var one := _fighter(Vector2(0.2, 0.0))
	var mate := _fighter(Vector2(0.3, 0.0), 1.0e9)
	var burst := _burst(PBSkill.Party.ALLIES)
	burst.on_hit = [_buff(&"probe_mend", PBBuff.Kind.INSTANT, 0.0, {&"heal_max": 0.1})]
	var squad: Array[PBAttacker] = [one, mate]
	var sim := PBBattleSim.new(PBWaveRules.build(20, _cfg, _rng), 0.0, 0.0, _cfg, squad)
	one.death_casts = [_cast(burst)]
	mate.hp = mate.max_hp * 0.5
	PBStrikeRules.wound_ally(one, 1.0e10, _cfg, sim.current_tick(), null, null, sim.result())
	sim.step()
	assert_gt(mate.hp, mate.max_hp * 0.55, "尸体周围的队友回了一截")


func test_a_bond_patch_hands_out_a_death_cast_that_never_reaches_the_command_card() -> void:
	# 真表：凡是 `on_death` 补丁点到的技能，满档时进 `death_casts`、不进 `skills`，
	# 而且技能表里它没有主（角色键 `-`），否则没有羁绊也会出现在指令卡上。
	var seen: int = 0
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_skill_patches:
			for id: StringName in bond.member_skill_patches[who]:
				var patch: Dictionary = bond.member_skill_patches[who][id]
				if not patch.has(PBSkillPatchRules.ON_DEATH):
					continue
				seen += 1
				for character: PBCharacter in _cfg.characters.all():
					assert_false(character.skill_ids.has(id), "%s 进了 %s 的指令卡" % [id, character.id])
				var units: Array[PBUnit] = [PBUnit.new(_cfg.characters.by_id(who))]
				var squad := PBCombatRules.build_attackers(
					units,
					PBElement.Type.FIRE,
					1.0,
					PackedFloat64Array(),
					_cfg,
					null,
					1,
					0,
					{},
					{},
					{who: {id: patch}}
				)
				assert_eq(squad[0].death_casts.size(), 1, "%s 该装进阵亡技能" % id)
	assert_gt(seen, 0, "前提：真表里有阵亡技能")


func test_every_lethal_buff_on_the_roster_is_a_real_effect() -> void:
	for character: PBCharacter in _cfg.characters.all():
		for buff: PBBuff in character.lethal_buffs:
			assert_eq(PBBuffRules.validate(buff), "", "%s 的致命伤效果不合法" % character.id)
