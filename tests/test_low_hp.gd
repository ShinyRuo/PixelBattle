extends GutTest
## 血量阈值触发（百豪之术、尾兽外衣、地之咒印）与它带进来的三个效果键。
##
## 这里错了都不报错：阈值只判在一条路上的话，另一条路掉血掉过线时不触发；
## 一波触发不止一次的话百豪之术能被奶回来反复刷；自身掉血不走记账的话掉死了没人算。

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _buff(id: StringName, kind: PBBuff.Kind, seconds: float, mods: Dictionary) -> PBBuff:
	var out := PBBuff.new()
	out.id = id
	out.kind = kind
	out.duration_seconds = seconds
	out.period_seconds = 1.0 if kind == PBBuff.Kind.PERIODIC else 0.0
	out.mods = mods
	return out


## 一个 1000 血、阈值 [param at]、掉线时给自己挂一份加防御的人。
func _guarded(at: float) -> PBAttacker:
	var one := PBAttacker.new()
	one.slot = 0
	one.max_hp = 1000.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	one.low_hp_at = at
	one.low_hp_buffs = [_buff(&"probe_guard", PBBuff.Kind.DURATION, 999.0, {&"defence": 50.0})]
	one.revive()
	return one


func _defence_of(one: PBAttacker, tick: int) -> float:
	return one.buffs.amount(PBBuffRules.DEFENCE, tick)


func test_it_fires_only_once_the_hp_drops_below_the_line() -> void:
	var one := _guarded(0.5)
	var out := PBCombatOutcome.new()
	PBStrikeRules.wound_ally(one, 400.0, _cfg, 1, null, null, out)
	assert_eq(_defence_of(one, 1), 0.0, "还剩 60%，没到线")
	PBStrikeRules.wound_ally(one, 200.0, _cfg, 2, null, null, out)
	assert_eq(_defence_of(one, 2), 50.0, "掉到 40%，挂上了")
	assert_true(one.low_hp_fired, "并且记下这一波触发过了")


func test_it_fires_once_a_wave_and_the_next_wave_rearms_it() -> void:
	var one := _guarded(0.5)
	var out := PBCombatOutcome.new()
	PBStrikeRules.wound_ally(one, 600.0, _cfg, 1, null, null, out)
	one.buffs.clear()
	one.heal(1000.0)
	PBStrikeRules.wound_ally(one, 600.0, _cfg, 2, null, null, out)
	assert_eq(_defence_of(one, 2), 0.0, "奶回来再掉下去不再触发（玩家定的：一波一次）")
	one.revive()
	PBStrikeRules.wound_ally(one, 600.0, _cfg, 3, null, null, out)
	assert_eq(_defence_of(one, 3), 50.0, "开波之后重新待命")


func test_the_enemy_attack_path_triggers_it_and_reads_the_new_defence() -> void:
	# 近战和子弹都走 `hurt_ally`；它要经过阈值那一处，挂上的防御也要在下一下里真的减伤。
	var one := _guarded(0.95)
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(one, null, 100.0, PBElement.Type.PHYSICAL, _cfg, 1, null, null, out)
	assert_eq(_defence_of(one, 1), 50.0, "敌人打过线就触发")
	var before: float = one.hp
	PBStrikeRules.hurt_ally(one, null, 100.0, PBElement.Type.PHYSICAL, _cfg, 2, null, null, out)
	var bare := PBStatRules.strike_damage(100.0, PBElement.Type.PHYSICAL, 0.0, one.def_element, _cfg)
	assert_lt(before - one.hp, bare - 0.001, "临时防御要在折算护甲那一句里算进去")


func test_nothing_fires_without_a_threshold_or_after_death() -> void:
	var none := _guarded(0.0)
	var out := PBCombatOutcome.new()
	PBStrikeRules.wound_ally(none, 900.0, _cfg, 1, null, null, out)
	assert_false(none.low_hp_fired, "没配阈值就不触发")
	var dead := _guarded(0.5)
	assert_true(PBStrikeRules.wound_ally(dead, 5000.0, _cfg, 1, null, null, out), "一下打死")
	assert_false(dead.low_hp_fired, "死人不挂效果")
	assert_eq(out.allies_lost, 1, "倒下照样记账")


func test_the_threshold_takes_the_larger_of_two_sources() -> void:
	# 〔吾之牢笼〕把 75% 改成 90%：相加的话是 165%，开波第一下就触发。
	var one := PBAttacker.new()
	PBPassiveRules.grant(one, PBPassiveRules.LOW_HP, 0.75)
	PBPassiveRules.grant(one, PBPassiveRules.LOW_HP, 0.90)
	assert_almost_eq(one.low_hp_at, 0.90, 0.0001, "取大")


func test_heal_max_heals_a_share_of_max_hp_each_pulse() -> void:
	var one := _guarded(0.0)
	one.hp = 100.0
	var mend := _buff(&"probe_mend", PBBuff.Kind.PERIODIC, 5.0, {&"heal_max": 0.10})
	PBSkillRules.apply_one(one, mend, mend.mods, _cfg, 0)
	for tick: int in range(0, _cfg.tick_rate * 5 + 1):
		PBBuffRules.advance_ally(one, tick)
	assert_almost_eq(one.hp, 600.0, 0.001, "5 秒 5 跳、每跳 10% 最大生命")


func test_drain_goes_through_the_bookkeeping_and_can_be_cut() -> void:
	var one := _guarded(0.0)
	var curse := _buff(&"probe_curse", PBBuff.Kind.PERIODIC, 999.0, {&"drain_max": 0.02})
	PBSkillRules.apply_one(one, curse, curse.mods, _cfg, 0)
	var drain: float = 0.0
	for tick: int in range(0, _cfg.tick_rate + 1):
		drain += PBBuffRules.advance_ally(one, tick)
	assert_almost_eq(drain, 20.0, 0.001, "一秒一跳、每跳 2% 最大生命")
	assert_eq(one.hp, 1000.0, "规则层只算不扣 —— 扣血和记账归 wound_ally")
	one.drain_cut = 1.0
	var cut: float = 0.0
	for tick: int in range(_cfg.tick_rate + 1, _cfg.tick_rate * 3 + 1):
		cut += PBBuffRules.advance_ally(one, tick)
	assert_eq(cut, 0.0, "抵掉十成就一点不掉（〔吾之牢笼〕）")


func test_a_drain_can_kill_and_is_counted_in_a_real_battle() -> void:
	# 掉血掉死的人要进 `allies_lost`：规则层当场扣血的话，这一个死人没人记。
	var one := _guarded(0.0)
	one.max_hp = 10.0
	one.revive()
	var squad: Array[PBAttacker] = [one]
	var sim := PBBattleSim.new(PBWaveRules.build(1, _cfg, _rng()), 0.0, 0.0, _cfg, squad)
	# 开战那一刻会清效果袋（开波），所以建好战斗之后再挂。
	var curse := _buff(&"probe_curse", PBBuff.Kind.PERIODIC, 999.0, {&"drain_max": 0.6})
	PBSkillRules.apply_one(one, curse, curse.mods, _cfg, 0)
	for _i: int in _cfg.tick_rate * 3:
		sim.step()
	assert_false(one.alive, "两跳就掉死了")
	assert_eq(sim.result().allies_lost, 1, "并且记了账")


func test_every_threshold_on_the_roster_has_something_to_hang() -> void:
	# 只写阈值不写效果（或反过来），那一半这辈子不生效。生成器拦着，这是第二道。
	for character: PBCharacter in PBCharacterLoader.table().all():
		var has_line: bool = character.passives.has(PBPassiveRules.LOW_HP)
		assert_eq(
			has_line,
			not character.low_hp_buffs.is_empty(),
			"%s 的 low_hp 与 on_low_hp 要成对" % character.id
		)


func test_nobody_but_wound_ally_takes_hp_off_a_ninja() -> void:
	# 阈值判在 `wound_ally` 里。别处直接调忍者的 `take_damage` 的话，那条路掉过线不触发、
	# 掉死了不记账 —— 而那条路在上面几条测试里根本走不到。
	var callers: Array[String] = []
	for path: String in _gd_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		for word: String in ["target.take_damage(", "attacker.take_damage(", "unit.take_damage("]:
			if text.contains(word):
				callers.append("%s: %s" % [path.get_file(), word])
	assert_eq(callers, ["strike_rules.gd: target.take_damage("], "忍者掉血只走 wound_ally")


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append("%s/%s" % [root, file_name])
	for sub: String in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [root, sub]))
	return out


func _rng() -> RandomNumberGenerator:
	var out := RandomNumberGenerator.new()
	out.seed = 20260914
	return out
