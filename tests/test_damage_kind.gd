extends GutTest
## 伤害分体术 / 忍术（M12-c4 批十五，玩家定的，见 [PBDamageKind]）。
##
## 这里错了都不报错：忍术被护甲减了、体术被忍术抗性减了；忍术暴击率拿去掷了普攻；
## 没人配忍术暴击率时技能也掷了骰子（拨动那条流，整局对拍漂移）；
## 技能子弹走了普攻的落点，吃护甲还触发了施法者的吸血和溅射。

const PHYS := PBDamageKind.Type.PHYSICAL
const NIN := PBDamageKind.Type.NINJUTSU

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


func _enemy(armor: float, resist: float, at: float = 0.3) -> PBEnemy:
	var out := PBEnemy.new()
	out.alive = true
	out.max_hp = 100000.0
	out.hp = out.max_hp
	out.armor = armor
	out.ninjutsu_resist = resist
	out.distance = at
	return out


func _ninja() -> PBAttacker:
	var one := PBAttacker.new()
	one.max_hp = 1000.0
	one.attack = 100.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


func _lost(enemy: PBEnemy) -> float:
	return enemy.max_hp - enemy.hp


func test_resist_grows_like_armor_and_stops_at_the_cap() -> void:
	for wave: int in [1, 30]:
		var minion: float = _cfg.enemy_resist(PBWave.Shape.NORMAL, wave)
		assert_gt(_cfg.enemy_resist(PBWave.Shape.ELITE, wave), minion, "精英比小怪高")
		assert_gt(
			_cfg.enemy_resist(PBWave.Shape.BOSS, wave),
			_cfg.enemy_resist(PBWave.Shape.ELITE, wave),
			"BOSS 比精英高"
		)
	assert_eq(_cfg.enemy_resist(PBWave.Shape.BOSS, 100000), _cfg.enemy_resist_cap, "封顶")
	assert_lt(_cfg.enemy_resist_cap, 1.0, "封顶必须小于 1")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var wave := PBWaveRules.build(30, _cfg, rng)
	var enemy := PBEnemy.new()
	enemy.spawn(wave, 0.01, 1.0, 0)
	assert_eq(enemy.ninjutsu_resist, _cfg.enemy_resist(wave.shape, 30), "出生时带上")


func test_each_kind_is_cut_only_by_its_own_defence() -> void:
	var enemy := _enemy(20.0, 0.4)
	var ninja := _ninja()
	var by_armor: float = 100.0 * (1.0 - PBStatRules.damage_reduction(20.0, _cfg))
	var body: float = PBStrikeRules.mitigated(ninja, enemy, 100.0, PHYS, _cfg, 0)
	assert_almost_eq(body, by_armor, 0.001, "体术吃护甲")
	assert_almost_eq(PBStrikeRules.mitigated(ninja, enemy, 100.0, NIN, _cfg, 0), 60.0, 0.001, "忍术吃抗性")
	ninja.ninjutsu_pen = 0.5
	assert_almost_eq(PBStrikeRules.mitigated(ninja, enemy, 100.0, NIN, _cfg, 0), 80.0, 0.001, "穿透一半")
	var shred := PBBuff.new()
	shred.id = &"probe_resist_down"
	shred.kind = PBBuff.Kind.DURATION
	shred.duration_seconds = 5.0
	PBSkillRules.apply_one_enemy(enemy, shred, {PBBuffRules.ENEMY_RESIST: -1.0}, _cfg, 0)
	assert_eq(PBStrikeRules.mitigated(null, enemy, 100.0, NIN, _cfg, 0), 100.0, "降到负数也只是不减")


func test_ninjutsu_crit_is_its_own_chance_and_rolls_no_dice_when_zero() -> void:
	var ninja := _ninja()
	ninja.crit_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var before: int = rng.state
	var jutsu := PBCritRules.hit(ninja, 100.0, NIN, 0, rng)
	assert_false(jutsu[PBCritRules.CRIT], "体术暴击率不管忍术")
	assert_eq(rng.state, before, "忍术暴击率是 0 就一次都不掷")
	ninja.ninjutsu_crit_chance = 1.0
	ninja.ninjutsu_bonus = 0.25
	jutsu = PBCritRules.hit(ninja, 100.0, NIN, 0, rng)
	assert_true(jutsu[PBCritRules.CRIT], "忍术暴击率拉满就暴")
	var expected: float = 100.0 * 1.25 * (1.0 + PBCritRules.NINJUTSU_CRIT_BASE)
	assert_almost_eq(jutsu[PBCritRules.DAMAGE], expected, 0.001, "先乘忍术增伤，再乘忍术暴击倍数")
	var body := PBCritRules.hit(ninja, 100.0, PHYS, 0, null)
	assert_almost_eq(body[PBCritRules.DAMAGE], 100.0, 0.001, "体术技能不吃忍术增伤")


func test_a_ninjutsu_attacker_uses_the_ninjutsu_side_for_normal_attacks() -> void:
	# 万花筒写轮眼「普攻变为忍术伤害，并提升 15% 的忍术暴击率」。
	var ninja := _ninja()
	ninja.attack_ninjutsu = 1.0
	ninja.crit_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var swing := PBCritRules.strike(ninja, 0, rng)
	assert_eq(swing[PBCritRules.KIND], NIN, "普攻算忍术")
	assert_false(swing[PBCritRules.CRIT], "体术暴击率不再管他的普攻")
	var enemy := _enemy(50.0, 0.5)
	var enemies: Array[PBEnemy] = [enemy]
	PBStrikeRules.land(ninja, enemy, 100.0, false, enemies, _cfg, 0, null, PBCombatOutcome.new())
	assert_almost_eq(_lost(enemy), 50.0, 0.001, "打在身上吃抗性，不吃护甲")


func test_physical_crit_is_double_by_default() -> void:
	# 原版「英雄的普攻暴击默认是 2 倍暴击」。
	assert_almost_eq(PBCritRules.multiplier_of(_ninja(), 0, PHYS), 2.0, 0.0001, "体术暴击 2 倍")
	assert_almost_eq(PBCritRules.multiplier_of(_ninja(), 0, NIN), 2.0, 0.0001, "忍术暴击 2 倍")


func test_a_skill_landing_uses_the_skill_kind() -> void:
	for kind: PBDamageKind.Type in [PHYS, NIN]:
		var skill := PBSkill.new()
		skill.id = &"probe_blast"
		skill.target = PBSkill.Target.GROUND
		skill.radius = 0.1
		skill.kind = kind
		skill.damage = 100.0
		var cast := PBSkillCast.new(skill, 1)
		cast.spot = Vector2(0.3, 0.0)
		var enemy := _enemy(20.0, 0.5)
		var enemies: Array[PBEnemy] = [enemy]
		PBSkillRules.land(cast, enemies, 0, _cfg, 1, _ninja(), 100.0)
		var expected: float = PBStrikeRules.mitigated(null, _enemy(20.0, 0.5), 100.0, kind, _cfg, 1)
		assert_almost_eq(_lost(enemy), expected, 0.001, "技能按自己的类型减伤")


func test_a_skill_bullet_is_not_a_normal_attack() -> void:
	# 技能子弹曾经走普攻的落点：吃护甲，还触发施法者的吸血、溅射。
	var caster := _ninja()
	caster.slot = 0
	caster.lifesteal = 1.0
	caster.splash_damage = 1.0
	caster.hp = 500.0
	var skill := PBSkill.new()
	skill.id = &"probe_bolt"
	skill.target = PBSkill.Target.ENEMY
	skill.kind = NIN
	var target := _enemy(50.0, 0.0, 0.3)
	var beside := _enemy(0.0, 0.0, 0.31)
	target.slot = 0
	beside.slot = 1
	var enemies: Array[PBEnemy] = [target, beside]
	var attackers: Array[PBAttacker] = [caster]
	var shot := PBProjectile.new()
	shot.launch(Vector2.ZERO, 0, 100.0, 1.0, false, PBElement.Type.FIRE, 0, skill, 1)
	var shots: Array[PBProjectile] = [shot]
	PBShotRules.advance(shots, enemies, attackers, _cfg, 1, null, PBCombatOutcome.new())
	assert_almost_eq(_lost(target), 100.0, 0.001, "忍术子弹不吃护甲")
	assert_eq(caster.hp, 500.0, "不触发普攻吸血")
	assert_eq(_lost(beside), 0.0, "不触发普攻溅射")


func test_instant_harm_is_ninjutsu() -> void:
	var enemy := _enemy(50.0, 0.5)
	var hit := PBBuff.new()
	hit.id = &"probe_hit"
	hit.kind = PBBuff.Kind.INSTANT
	PBSkillRules.apply_one_enemy(enemy, hit, {PBBuffRules.HARM: 100.0}, _cfg, 0)
	assert_almost_eq(_lost(enemy), 50.0, 0.001, "吃忍术抗性，不吃护甲")
