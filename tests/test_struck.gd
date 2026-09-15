extends GutTest
## 受击触发（蜉蝣、神威、沙之守护、妩媚）与它带进来的两个效果键（临时闪避、敌人攻速）。
##
## 这里错了都不报错：减益挂到了自己身上；冷却不走，一波里每下都触发；
## 自身掉血也被当成「受攻击」；敌人攻速倍率在出手判定里读、被定住时冷却偷跑。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _buff(id: StringName, friendly: bool, seconds: float, mods: Dictionary) -> PBBuff:
	var out := PBBuff.new()
	out.id = id
	out.kind = PBBuff.Kind.DURATION
	out.friendly = friendly
	out.duration_seconds = seconds
	out.mods = mods
	return out


func _ninja(buffs: Array[PBBuff], cd: float) -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 100000.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	one.struck_buffs = buffs
	one.struck_cd = cd
	one.revive()
	return one


func _enemy() -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100000.0
	out.hp = out.max_hp
	out.attack_interval = 20
	return out


func _hit(one: PBAttacker, source: PBEnemy, tick: int) -> void:
	PBStrikeRules.hurt_ally(
		one, source, 10.0, PBElement.Type.PHYSICAL, _cfg, tick, null, null, PBCombatOutcome.new()
	)


func test_a_friendly_buff_goes_on_self_and_waits_for_its_cooldown() -> void:
	var guard := _buff(&"probe_guard", true, 1.0, {&"defence": 100.0})
	var one := _ninja([guard], 5.0)
	var enemy := _enemy()
	_hit(one, enemy, 1)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 100.0, "挨一下，自己挂上了")
	assert_eq(enemy.buffs.count(1), 0, "增益不挂到敌人身上")
	one.buffs.clear()
	_hit(one, enemy, 2)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 2), 0.0, "冷却里不再触发")
	_hit(one, enemy, 1 + 5 * _cfg.tick_rate)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1 + 5 * _cfg.tick_rate), 100.0, "冷却过了又触发")
	one.buffs.clear()
	one.revive()
	_hit(one, enemy, 3)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 3), 100.0, "开波冷却清零")


func test_a_hostile_buff_goes_on_the_enemy_that_struck() -> void:
	var charm := _buff(&"probe_charm", false, 3.0, {&"enemy_attack_speed_scale": 0.35})
	var one := _ninja([charm], 0.0)
	var enemy := _enemy()
	_hit(one, enemy, 1)
	assert_eq(one.buffs.count(1), 0, "减益不挂自己")
	var pace: float = enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 1)
	assert_almost_eq(pace, 0.35, 0.0001, "挂在出手的敌人身上")


func test_a_slowed_enemy_waits_longer_before_its_next_shot() -> void:
	var enemy := _enemy()
	enemy.on_fired(0)
	var normal: int = enemy.next_shot_at
	var charm := _buff(&"probe_charm", false, 3.0, {&"enemy_attack_speed_scale": 0.5})
	PBSkillRules.apply_one_enemy(enemy, charm, charm.mods, _cfg, 0)
	enemy.on_fired(0)
	assert_eq(enemy.next_shot_at, normal * 2, "攻速减半，间隔翻倍")


func test_a_self_drain_is_not_being_struck() -> void:
	# 只有敌人的攻击算「受攻击」：自身掉血走 `wound_ally`，不经过 `hurt_ally`。
	var guard := _buff(&"probe_guard", true, 1.0, {&"defence": 100.0})
	var one := _ninja([guard], 0.0)
	PBStrikeRules.wound_ally(one, 10.0, _cfg, 1, null, null, PBCombatOutcome.new())
	assert_eq(one.buffs.count(1), 0, "自己掉血不触发")


func test_a_temporary_dodge_really_dodges() -> void:
	var one := _ninja([] as Array[PBBuff], 0.0)
	var blur := _buff(&"probe_blur", true, 2.0, {&"dodge": 1.0})
	PBSkillRules.apply_one(one, blur, blur.mods, _cfg, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var before: float = one.hp
	assert_false(one.take_damage(500.0, 1, rng), "临时闪避 100%，这一下闪掉")
	assert_eq(one.hp, before, "一点血都不掉")
	assert_false(PBPassiveRules.dodges(one, rng, 2 * _cfg.tick_rate + 1), "过期就不闪")


func _at(one: PBAttacker, slot: int, x: float) -> PBAttacker:
	one.slot = slot
	one.pos = Vector2(x, 0.0)
	one.home = one.pos
	return one


func _team_hit(one: PBAttacker, source: PBEnemy, team: Array[PBAttacker], tick: int) -> void:
	PBStrikeRules.hurt_ally(
		one, source, 10.0, PBElement.Type.PHYSICAL, _cfg, tick, null, null, PBCombatOutcome.new(), team
	)


func test_an_aura_carrier_triggers_for_allies_standing_in_its_circle() -> void:
	var guard := _buff(&"probe_guard", true, 4.0, {&"defence": 100.0})
	var carrier := _at(_ninja([guard], 999.0), 0, 0.30)
	carrier.struck_aura = 400.0
	var near := _at(_ninja([] as Array[PBBuff], 0.0), 1, 0.40)
	var far := _at(_ninja([] as Array[PBBuff], 0.0), 2, 0.80)
	var team: Array[PBAttacker] = [carrier, near, far]
	var enemy := _enemy()
	_team_hit(near, enemy, team, 1)
	_team_hit(far, enemy, team, 1)
	assert_eq(near.buffs.amount(PBBuffRules.DEFENCE, 1), 100.0, "圈里的队友挨打，挂上带光环那个人的效果")
	assert_eq(far.buffs.amount(PBBuffRules.DEFENCE, 1), 0.0, "圈外的没有")
	assert_eq(carrier.buffs.count(1), 0, "带光环的人自己没挨打，不挂")
	near.buffs.clear()
	_team_hit(near, enemy, team, 2)
	assert_eq(near.buffs.amount(PBBuffRules.DEFENCE, 2), 0.0, "冷却按这个队友算，一波一次")
	var third := _at(_ninja([] as Array[PBBuff], 0.0), 3, 0.35)
	team.append(third)
	_team_hit(third, enemy, team, 2)
	assert_eq(third.buffs.amount(PBBuffRules.DEFENCE, 2), 100.0, "另一个队友各算各的")
	carrier.alive = false
	near.revive()
	carrier.aura_ready_at.clear()
	_team_hit(near, enemy, team, 3)
	assert_eq(near.buffs.amount(PBBuffRules.DEFENCE, 3), 0.0, "带光环的人死了光环就没了")


func test_an_aura_debuff_still_lands_on_the_enemy_that_struck() -> void:
	var charm := _buff(&"probe_charm", false, 3.0, {&"enemy_attack_speed_scale": 0.35})
	var carrier := _at(_ninja([charm], 0.0), 0, 0.30)
	carrier.struck_aura = 450.0
	var near := _at(_ninja([] as Array[PBBuff], 0.0), 1, 0.35)
	var enemy := _enemy()
	_team_hit(near, enemy, [carrier, near] as Array[PBAttacker], 1)
	var pace: float = enemy.buffs.amount(PBBuffRules.ENEMY_ATTACK_SPEED_SCALE, 1)
	assert_almost_eq(pace, 0.35, 0.0001, "打队友的那个敌人被减攻速")
	assert_eq(near.buffs.count(1), 0, "减益不挂队友")


func test_the_boost_scales_amounts_but_not_rates() -> void:
	var mods := PBBuffRules.scale_amounts({&"defence": 100.0, &"enemy_attack_speed_scale": 0.35}, 1.5)
	assert_almost_eq(float(mods[&"defence"]), 150.0, 0.001, "防御 100 → 150")
	assert_almost_eq(float(mods[&"enemy_attack_speed_scale"]), 0.35, 0.0001, "率型不乘")
	var guard := _buff(&"probe_guard", true, 4.0, {&"defence": 100.0})
	var one := _ninja([guard], 0.0)
	one.struck_boost = 0.5
	_hit(one, _enemy(), 1)
	assert_eq(one.buffs.amount(PBBuffRules.DEFENCE, 1), 150.0, "自己那一路也吃加成")


func _summoner(chance: float) -> PBAttacker:
	var one := _at(_ninja([] as Array[PBBuff], 3.0), 0, 0.30)
	var clones := PBSkill.new()
	clones.id = &"probe_clones"
	clones.summon_count = 3
	clones.summon_power = 0.4
	clones.summon_hp_share = 0.2
	clones.summon_seconds = 10.0
	one.skills = [PBSkillCast.new(clones, 1)] as Array[PBSkillCast]
	one.struck_summon = chance
	return one


func _empty_seat(slot: int) -> PBAttacker:
	var seat := PBAttacker.new()
	seat.slot = slot
	seat.summoned = true
	PBSummonRules.dismiss(seat)
	return seat


func _struck_by(
	one: PBAttacker, enemy: PBEnemy, tick: int, rng: RandomNumberGenerator, team: Array[PBAttacker]
) -> void:
	PBStrikeRules.hurt_ally(
		one, enemy, 1.0, PBElement.Type.PHYSICAL, _cfg, tick, rng, null, PBCombatOutcome.new(), team
	)


func test_being_struck_can_raise_one_clone_and_waits_for_its_cooldown() -> void:
	# 〔共同修行〕「受攻击时 15% 几率出一个影分身，内置 CD 3 秒」。几率拉到 1 量机制。
	var one := _summoner(1.0)
	var team: Array[PBAttacker] = [one, _empty_seat(1), _empty_seat(2)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var enemy := _enemy()
	_struck_by(one, enemy, 1, rng, team)
	assert_true(team[1].alive, "召出来一个")
	assert_false(team[2].alive, "只召一个，不是技能那一整发")
	_struck_by(one, enemy, 2, rng, team)
	assert_false(team[2].alive, "冷却里不再召")
	var none := _summoner(0.0)
	var quiet := RandomNumberGenerator.new()
	quiet.seed = 3
	var before: int = quiet.state
	_struck_by(none, enemy, 1, quiet, [none] as Array[PBAttacker])
	assert_eq(quiet.state, before, "没配就一次骰子都不掷")


func test_an_opening_low_hp_buff_is_on_from_the_first_tick() -> void:
	# 〔共同修行〕「尾兽外衣开局即可开启」：开波就挂上，之后掉血不再挂第二次。
	var one := _ninja([] as Array[PBBuff], 0.0)
	one.low_hp_at = 0.75
	one.low_hp_buffs = [_buff(&"probe_cloak", true, 999.0, {&"damage_scale": 1.25})]
	one.open_low_hp = 1.0
	var squad: Array[PBAttacker] = [one]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sim := PBBattleSim.new(PBWaveRules.build(1, _cfg, rng), 0.0, 0.0, _cfg, squad)
	assert_almost_eq(one.buffs.amount(PBBuffRules.DAMAGE_SCALE, 0), 1.25, 0.0001, "开波就挂上了")
	assert_true(one.low_hp_fired, "记成这一波触发过了")
	assert_not_null(sim, "前提：战斗建得起来")


func test_every_struck_buff_on_the_roster_is_a_real_effect() -> void:
	var seen: int = 0
	for character: PBCharacter in _cfg.characters.all():
		for buff: PBBuff in character.struck_buffs:
			assert_eq(PBBuffRules.validate(buff), "", "%s 的受击效果不合法" % character.id)
			seen += 1
		if character.passives.has(PBPassiveRules.STRUCK_CD):
			assert_false(character.struck_buffs.is_empty(), "%s 写了冷却却没有受击效果" % character.id)
	assert_gt(seen, 0, "前提：名册里有受击触发")
