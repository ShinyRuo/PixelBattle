extends GutTest
## 角色自带的常驻被动（M12-c2）。

## ## 这个文件守的是什么
##
## 原版 56 张卡里有 10 个是「攻击时 X% 触发 Y」这种东西 ——
## **没有施法、没有冷却、没有蓝，玩家按不出来**，所以它们不是技能。
## M12-c1 只有技能表一条路，于是佩恩的轮回眼（纯被动）被落成了一个
## 30 秒 CD 的按钮。c2 给了它们该走的那条路。
##
## 三条：
##
## 1. **一份映射，两个来源** —— 羁绊和角色自带走同一个 [method PBPassiveRules.grant]
## 2. **词汇表里的键 = 已经接上读点的键**（同 [PBBuffRules] 顶上那条，M7-a）
## 3. **不认识的键在装表那一刻报错**，不静默跳过

const SHOT_PATH := "res://src/core/rules/shot_rules.gd"
const SIM_PATH := "res://src/core/sim/battle_sim.gd"

var _cfg: PBSimConfig
var _characters: PBCharacterTable
var _skills: PBSkillTable
var _rng: RandomNumberGenerator


func before_all() -> void:
	_characters = PBCharacterLoader.load_from(PBCharacterLoader.DIR)
	_skills = PBSkillLoader.table()


func before_each() -> void:
	_cfg = PBGameData.config()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260912


# ── 一份映射，两个来源 ────────────────────────────────────────


func test_the_bond_route_and_the_character_route_write_the_same_field() -> void:
	# **这是被动通道存在的理由。** M10-d 那四个键当时只有羁绊一个来源，
	# 映射因此写在 `PBBondFunctionRules` 里；c2 来了第二个来源（角色自带），
	# d1 又把羁绊那一路也改成了走成员表 —— 三条路，**一份映射**。
	# 分开写的话「羁绊给的溅射」和「他自带的溅射」迟早不一样大，
	# 而那不报错 —— 屏幕上照样溅射。
	for key: StringName in PBBondFunctionRules.CARRIER_AMOUNTS:
		var amount: float = PBBondFunctionRules.CARRIER_AMOUNTS[key]
		var by_bond := PBAttacker.new()
		PBPassiveRules.grant_all(by_bond, {key: amount})
		var by_self := PBAttacker.new()
		PBPassiveRules.grant(by_self, key, amount)
		assert_eq(
			_snapshot(by_bond), _snapshot(by_self), "「%s」两条路写出来的必须一样" % key
		)


func test_two_sources_stack_instead_of_overwriting() -> void:
	# 一个人可以既是某组羁绊的载体、又自带一个同名被动。
	# `=` 而不是 `+=` 的表现是「后装的那一份把先装的吃掉了」，
	# 屏幕上照样有效果，只是少了一份。
	var attacker := PBAttacker.new()
	PBPassiveRules.grant(attacker, PBPassiveRules.SPLASH, 0.2)
	PBPassiveRules.grant(attacker, PBPassiveRules.SPLASH, 0.3)
	assert_almost_eq(attacker.splash_damage, 0.5, 0.0001, "两份该加起来")


func test_every_key_in_the_vocabulary_actually_moves_something() -> void:
	# 词汇表里的键 = 已经接上读点的键（M7-a）。拼对了却没人读的键
	# 比拼错更难查：数据、界面、日志全部正常，只有伤害数字不对。
	for key: StringName in PBPassiveRules.ALL:
		var attacker := PBAttacker.new()
		var before := _snapshot(attacker)
		assert_true(PBPassiveRules.grant(attacker, key, 1.0), "「%s」该装得上" % key)
		assert_ne(_snapshot(attacker), before, "「%s」装上了却什么都没改" % key)


func test_the_rate_keys_only_take_effect_once_equip_folds_them() -> void:
	# `hp_bonus` / `move_speed_bonus` 是**累加器**：`grant` 只往累加器上加，
	# 真正生效要折进 `max_hp` / `move_speed`。
	# 把折算留给调用方的话，「忘了折」的表现是**那一组羁绊配了不生效** ——
	# 数据、界面、日志全部正常，只有血条不对。所以折算在 `equip` 里面。
	var attacker := PBAttacker.new()
	attacker.max_hp = 1000.0
	attacker.move_speed = 0.010
	attacker.defence = 12.0
	PBPassiveRules.grant(attacker, PBPassiveRules.HP_BONUS, 0.5)
	assert_almost_eq(attacker.max_hp, 1000.0, 0.0001, "光 grant 还不该动血上限")

	var folded := PBAttacker.new()
	folded.max_hp = 1000.0
	folded.move_speed = 0.010
	folded.defence = 12.0
	PBPassiveRules.equip(
		folded,
		[
			{PBPassiveRules.HP_BONUS: 0.5},
			{PBPassiveRules.MOVE_SPEED_BONUS: 0.2, PBPassiveRules.DEFENCE: 30.0},
		]
	)
	assert_almost_eq(folded.max_hp, 1500.0, 0.0001, "折算之后血上限该抬起来")
	assert_almost_eq(folded.move_speed, 0.012, 0.000001, "移速同理")
	# **裸名是量型：防御直接加点数**，不走折算那一条（原版写的就是点数，
	# 而 M12-b 之后我们的护甲和它同一把刻度）。
	assert_almost_eq(folded.defence, 42.0, 0.0001, "防御是直接加上去的点数")


func test_two_rate_sources_add_up_instead_of_compounding() -> void:
	# 两组各给 +50% 生命该是 **+100%**，不是 1.5 x 1.5 = 2.25。
	# 边加边折就是连乘，而那不是人会预期的叠加方式 —— 同 `damage_bonus` 那条。
	var attacker := PBAttacker.new()
	attacker.max_hp = 1000.0
	PBPassiveRules.equip(
		attacker, [{PBPassiveRules.HP_BONUS: 0.5}, {PBPassiveRules.HP_BONUS: 0.5}]
	)
	assert_almost_eq(attacker.max_hp, 2000.0, 0.0001, "两份 +50% 该相加成 +100%")


func test_a_key_nobody_knows_is_refused_not_silently_dropped() -> void:
	var attacker := PBAttacker.new()
	assert_false(PBPassiveRules.is_known(&"no_such_key"), "这个键不该认得")
	assert_false(PBPassiveRules.grant(attacker, &"no_such_key", 1.0), "不认得就该退回 false")
	assert_eq(PBPassiveRules.grant_all(attacker, {&"no_such_key": 1.0}), 0, "一个都没装上")


# ── 接进战斗 ──────────────────────────────────────────────────


func test_a_character_passive_reaches_the_attacker_it_belongs_to() -> void:
	# 落点在建人那个循环**里面** —— 只有那里知道这个攻击者是哪个角色
	# （[PBAttacker] 上没有也不该有角色 id，铁律 5）。
	# 搬到循环外面就要再造一份对照表，而那份表和出战席顺序对不上的
	# 表现是「被动发到了别人身上」。
	var with_passive := _character({PBPassiveRules.CRIT_CHANCE: 0.25})
	var plain := _character({})
	var built := _build([plain, with_passive, plain])
	assert_almost_eq(built[1].crit_chance, 0.25, 0.0001, "他自己那一份该到他身上")
	assert_almost_eq(built[0].crit_chance, 0.0, 0.0001, "前面那个不该沾上")
	assert_almost_eq(built[2].crit_chance, 0.0, 0.0001, "后面那个也不该")


func test_an_empty_passive_table_changes_absolutely_nothing() -> void:
	# 同 M3.5-f 装备那条「空着 = 一字不差」：没人填被动时全部既有配平
	# 数字一位都不许动。**填上了就不是了** —— 被动是他站着就一直在
	# 发生的事，批量扫描吃得到，那是 M12 头一次真的动了自动模拟的输出。
	#
	# **防御那一格要单独交代**（M12-e2）：`defence` 是词汇表里唯一一个
	# 写在**三围算出来的基数**上的键（裸名 = 量型，见 [PBPassiveRules] 顶上），
	# 所以建人那一刻它本来就不是 0 —— 拿它和一个裸 [PBAttacker] 比
	# 只会量出「这个角色有几点护甲」，和被动一点关系都没有。
	# 基线里因此照抄它，这一格在这条断言下是空的；
	# 真正钉住 `defence` 有没有接上读点的是
	# [method test_every_key_in_the_vocabulary_actually_moves_something]。
	var built := _build([_character({}), _character({})])
	for one: PBAttacker in built:
		var bare := PBAttacker.new()
		bare.defence = one.defence
		assert_eq(_snapshot(one), _snapshot(bare), "没填就该和裸的一模一样")


# ── 名册那张表 ────────────────────────────────────────────────


func test_every_passive_on_every_character_is_a_key_we_know() -> void:
	# 生成器读表那一刻就拦（退出码 1），这条是第二道 —— 盘上的 `.tres`
	# 也可能是手改的。不认识的键静默躺在数据里的表现是「配了不生效」。
	var seen: int = 0
	for character: PBCharacter in _characters.all():
		for key: StringName in character.passives:
			assert_true(PBPassiveRules.is_known(key), "「%s」这个键没人认得" % key)
			seen += 1
	assert_gt(seen, 0, "名册里一个被动都没有的话，上面那一圈什么都没量")


func test_nobody_carries_a_passive_and_a_skill_that_do_the_same_thing() -> void:
	# 轮回眼 c1 落成了一个 30 秒 CD 的自增益（`on_self` 挂一份加暴击率的
	# buff），c2 把它改成被动之后**那一版必须撤掉** ——
	# 两版都留着的话他会拿到两份，而屏幕上只看得见一个格子。
	var carriers: int = 0
	for character: PBCharacter in _characters.all():
		if not character.passives.has(PBPassiveRules.CRIT_CHANCE):
			continue
		carriers += 1
		for skill_id: StringName in character.skill_ids:
			var skill: PBSkill = _skills.by_id(skill_id)
			if skill == null:
				continue
			for buff: PBBuff in skill.on_self:
				assert_false(
					buff.mods.has(PBBuffRules.CRIT_CHANCE),
					"「%s」既有常驻暴击被动、又有一个加暴击率的自增益" % character.id
				)
	# **分母得先量准。** 不量的话，「没人带暴击被动」和
	# 「带了而且都对」在报告里长得一模一样（都是绿的）——
	# 同 `test_actor_lab` 那条被接素材弄红的。
	assert_gt(carriers, 0, "名册里一个带常驻暴击被动的都没有，上面什么都没拦")


func _snapshot(one: PBAttacker) -> Array:
	return [
		one.crit_chance,
		one.crit_bonus,
		one.crit_on_hit,
		one.splash_damage,
		one.heavy_bonus,
		one.revives_max,
		one.dodge,
		one.bite_current,
		one.bite_lost,
		one.reflect,
		one.damage_bonus,
		one.defence,
		one.hp_bonus,
		one.move_speed_bonus,
		one.attack_speed_bonus,
	]


func _character(passives: Dictionary) -> PBCharacter:
	var character := PBCharacter.new()
	character.id = &"probe"
	character.passives = passives
	return character


func _build(characters: Array) -> Array[PBAttacker]:
	var units: Array[PBUnit] = []
	for character: PBCharacter in characters:
		units.append(PBUnit.new(character))
	return PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, 1.0, PackedFloat64Array(), _cfg
	)


# ── 被动也能挂一份效果（M12-c2）────────────────────────────────


## 一个出得了手的人。**和 `tests/test_bite.gd` 里那一份是两份夹具**
## （M12-e2 拆文件时留下的）：两边问的是不同的事，
## 合并成一处共享的话，一边改夹具会静默动到另一边的结论。
func _striker() -> PBAttacker:
	var one := PBAttacker.new()
	one.slot = 0
	one.dps = 100.0
	one.max_hp = 500.0
	one.attack_speed = 1.0
	one.reach = 1.0
	one.prime(_cfg.tick_rate)
	one.revive()
	return one


## 一个满血、打不死的敌人。量的是「挂上了什么」，不是「死没死」。
func _pack(count: int) -> Array[PBEnemy]:
	var wave := PBWaveRules.build(3, _cfg, _rng)
	var out: Array[PBEnemy] = []
	for i: int in count:
		var enemy := PBEnemy.new()
		enemy.spawn(wave, 0.0, _cfg.field_length - float(i) * 0.5, 0, 0.0)
		enemy.slot = i
		enemy.max_hp = 100000.0
		enemy.hp = enemy.max_hp
		out.append(enemy)
	return out




func test_a_telling_blow_hangs_the_passives_own_effect_on_the_target() -> void:
	# **这是被动通道从「只带得了数」长出来的那一半。** 原版有一批被动是
	# 「攻击时 X% 几率给目标上一份效果」（带土的扭曲攻击晕眩 0.7 秒），
	# 而在它之前那一批只能降格成一个要玩家手动按的技能。
	var attacker := _striker()
	attacker.on_hit_buffs = [_stun()]
	var enemies := _pack(1)
	var out := PBCombatOutcome.new()
	PBStrikeRules.land(attacker, enemies[0], 10.0, true, enemies, _cfg, 0, null, out)
	assert_gt(
		enemies[0].buffs.amount(PBBuffRules.STUN, 0), 0.0, "打出要害就该把效果挂上去"
	)


func test_an_ordinary_hit_hangs_nothing() -> void:
	# 它骑在暴击那个掷点上（同按生命百分比那一笔），所以 `crit` 为 false 时什么都不做。
	var attacker := _striker()
	attacker.on_hit_buffs = [_stun()]
	var enemies := _pack(1)
	var out := PBCombatOutcome.new()
	PBStrikeRules.land(attacker, enemies[0], 10.0, false, enemies, _cfg, 0, null, out)
	assert_eq(enemies[0].buffs.amount(PBBuffRules.STUN, 0), 0.0, "没打出要害就不挂")


func test_nothing_gets_hung_on_a_corpse() -> void:
	# 同 M7-d 那条：给一具尸体挂减速没有意义，而且会让
	# 「这一发定住了几个」虚高。
	var attacker := _striker()
	attacker.on_hit_buffs = [_stun()]
	var enemies := _pack(1)
	enemies[0].max_hp = 1.0
	enemies[0].hp = 1.0
	var out := PBCombatOutcome.new()
	PBStrikeRules.land(attacker, enemies[0], 100.0, true, enemies, _cfg, 0, null, out)
	assert_false(enemies[0].alive, "这一下该打死他")
	assert_eq(enemies[0].buffs.amount(PBBuffRules.STUN, 0), 0.0, "死了就不该再挂")


func test_a_passive_effect_reaches_the_attacker_it_belongs_to() -> void:
	var with_buff := _character({})
	with_buff.on_hit_buffs = [_stun()]
	var built := _build([_character({}), with_buff])
	assert_eq(built[1].on_hit_buffs.size(), 1, "他自己那一份该到他身上")
	assert_eq(built[0].on_hit_buffs.size(), 0, "别人不该沾上")


func test_the_real_table_hangs_what_it_says_it_hangs() -> void:
	# 名册那一列写的是效果**键**，而它要被解析成一份真资源。解析不出来的话
	# 生成器会退出码 1，但盘上的 `.tres` 也可能是手改的 ——
	# 挂着一个空数组的表现是「配了不生效」。
	var carriers: int = 0
	for character: PBCharacter in _characters.all():
		for buff: PBBuff in character.on_hit_buffs:
			assert_not_null(buff, "「%s」的被动挂着一个空效果" % character.id)
			assert_ne(buff.id, &"", "「%s」挂的那份效果没有 id" % character.id)
			carriers += 1
	assert_gt(carriers, 0, "名册里一个带效果的被动都没有，上面什么都没量")


## 一份定住敌人的效果。
func _stun() -> PBBuff:
	var buff := PBBuff.new()
	buff.id = &"probe_stun"
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = false
	buff.duration_seconds = 2.0
	buff.mods = {PBBuffRules.STUN: 1.0}
	return buff


# ── 常驻增伤与尾兽光环（M12-e）──────────────────────────────


func test_a_lasting_damage_bonus_really_multiplies_the_swing() -> void:
	# 存「额外多打几成」而不是倍数，所以中性值是 0.0 —— 两份 +40% 相加是
	# +80% 而不是被连乘成 +96%。同 [member PBAttacker.crit_bonus] 那条。
	var one := PBAttacker.new()
	one.dps = 100.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	var plain: float = one.strike_for(0)
	one.damage_bonus = 0.4
	assert_almost_eq(one.strike_for(0), plain * 1.4, 0.0001, "该多打四成")
	PBPassiveRules.grant(one, PBPassiveRules.DAMAGE_BONUS, 0.4)
	assert_almost_eq(one.strike_for(0), plain * 1.8, 0.0001, "两份该相加不是连乘")


func test_the_lasting_and_the_temporary_halves_multiply() -> void:
	# 效果袋里那一份是**临时**的（技能挂上去、过期就没），字段这一份是常驻的。
	# 两者相乘 —— 同暴击那一对在 [method PBCritRules.chance_of] 相加。
	var one := PBAttacker.new()
	one.dps = 100.0
	one.attack_speed = 1.0
	one.prime(_cfg.tick_rate)
	one.damage_bonus = 1.0
	var buff := PBBuff.new()
	buff.id = &"probe_scale"
	buff.kind = PBBuff.Kind.DURATION
	buff.duration_seconds = 5.0
	buff.mods = {PBBuffRules.DAMAGE_SCALE: 1.5}
	one.buffs.add(buff, PBBuffRules.resolve(buff, 1), 0, buff.duration_ticks(_cfg), 0)
	# 每发 = dps × 间隔 ÷ tick 率 = 100，再乘常驻的 2 和临时的 1.5。
	assert_almost_eq(one.strike_for(0), 100.0 * 2.0 * 1.5, 0.001, "常驻 ×2、临时 ×1.5，两者相乘")
