extends GutTest
## `data/skills/` 与 `data/buffs/`，以及它们接进战斗的那一段（M7-g）。
##
## ## 这个文件的正题只有一条：**填上了也一字不差**
##
## 技能只有玩家**手动**放得出（自动档只挑地面落点，`PBAimRules` 不知道
## 该治谁；§6 那条「批量扫描不吃技能」就是这个意思）。所以给一个角色
## 填上 `skill_ids` **不该改变任何自动跑出来的数字** ——
## 批量扫描、悬崖二分、配平回归全都碰不到它。
##
## 这和 M3.5-f 装备那条「空着 = 和之前一字不差」同形，但更强：
## **这一次连「填上了」也一字不差。** 一条测试直接对拍两局。
##
## ## 另一条是「拼错要报错，不要静默」
##
## [method PBBuffRules.validate] 拦的两条（不认识的键、只写成长不写基数）
## **全部静默生效** —— 数据、界面、日志都正常，只有数字不对。
## 装表那一刻不拦，就只剩「这个技能好像没用」这一个现象可查。

const FIXED_SEED: int = 20260908

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	_cfg = PBGameData.config()
	_cfg.field_height = 0.0
	_cfg.spawn_window = 0.0
	_rng = RandomNumberGenerator.new()
	_rng.seed = FIXED_SEED


## 手上有这个技能的那些角色。**不写角色名**（铁律 5：`test_character_data.gd`
## 扫整个 `src/`，而 `tests/` 里同样没有必要写）。
func _carriers() -> Array[PBCharacter]:
	var out: Array[PBCharacter] = []
	for character: PBCharacter in _cfg.characters.all():
		if not character.skill_ids.is_empty():
			out.append(character)
	return out


func _unit_of(character: PBCharacter) -> PBUnit:
	return PBUnit.new(character)


func _squad(units: Array[PBUnit], with_skills: bool) -> Array[PBAttacker]:
	var cfg: PBSimConfig = _cfg
	if not with_skills:
		# 同一份配置，只把技能表摘掉 —— 摘掉就是 M7-g 之前的每一天。
		cfg = PBGameData.config()
		cfg.field_height = 0.0
		cfg.spawn_window = 0.0
		cfg.skills = null
	return PBCombatRules.build_attackers(
		units, PBElement.Type.FIRE, 1.0, 1.0, PackedFloat64Array(), cfg
	)


# ── 表本身 ──────────────────────────────────────────────────────


func test_the_folder_loads_and_every_skill_is_legal() -> void:
	var table := PBSkillLoader.table()
	assert_gt(table.size(), 0, "技能目录该装进来至少一份")
	for id: StringName in table.ids():
		assert_eq(PBSkillLoader.check(table.by_id(id)), "", "这份技能该合法：%s" % id)


func test_a_missing_folder_is_not_an_error() -> void:
	# 和 [PBActorLibrary] 同一条：没有目录时正确的行为是「一个技能都没有」，
	# 而那正是 M7-g 之前的每一天。角色表打不开才该报错。
	var table := PBSkillLoader.load_from("res://data/no_such_folder")
	assert_eq(table.size(), 0, "目录不在就是一份空表，不该崩也不该报错")


func test_a_misspelled_effect_key_is_refused_at_load_time() -> void:
	# **静默生效的那两条必须在装表那一刻拦下来。**
	var bad := PBBuff.new()
	bad.id = &"typo"
	bad.mods = {&"damge_scale": 1.5}
	var skill := PBSkill.new()
	skill.id = &"probe"
	skill.on_hit = [bad]
	assert_ne(PBSkillLoader.check(skill), "", "不认识的效果键该在这里就被拦住")


func test_a_growth_without_a_base_is_refused_too() -> void:
	var bad := PBBuff.new()
	bad.id = &"typo"
	bad.mods_growth = {PBBuffRules.HEAL: 5.0}
	var skill := PBSkill.new()
	skill.id = &"probe"
	skill.on_hit = [bad]
	assert_ne(PBSkillLoader.check(skill), "", "只写成长不写基数会静默变成「1 级时是 0」")


func test_a_skill_name_really_comes_from_the_locale_table() -> void:
	# 铁律 5：`src/` 里一个技能名都没有，格子上那几个字全靠这张表。
	var table := PBSkillLoader.table()
	for id: StringName in table.ids():
		var skill := table.by_id(id)
		assert_ne(PBLocale.of_skill(skill), String(skill.id), "这份技能该有翻译：%s" % id)


# ── 角色表那一侧 ────────────────────────────────────────────────


func test_at_least_one_character_actually_carries_a_skill() -> void:
	# 没有这一条的话，下面几条会在一个空集合上全绿而什么都没测。
	assert_gt(_carriers().size(), 0, "该有角色配上了技能，否则这一步等于没做")


func test_nobody_carries_more_than_two_skills() -> void:
	# 决策 6。指令卡那一行只画得下两格（[constant PBCommandCard.SKILL_COMMANDS]）——
	# 配了却放不出比没配更难查。
	for character: PBCharacter in _carriers():
		assert_lte(
			character.skill_ids.size(),
			PBCharacter.MAX_SKILLS,
			"这个角色配多了：%s" % character.id
		)


func test_every_skill_id_on_a_character_can_actually_be_found() -> void:
	# 拼错一个 id 的表现是「这个角色少了一格」，而那和「他本来就只有一个技能」
	# 长得一模一样。和 `test_actor_data.gd` 那条 `actor_key` 是同一个形状。
	var table := PBSkillLoader.table()
	for character: PBCharacter in _carriers():
		for id: StringName in character.skill_ids:
			assert_true(table.has(id), "角色表点了一个不存在的技能：%s → %s" % [character.id, id])


# ── 接进战斗 ────────────────────────────────────────────────────


func test_the_carrier_really_gets_the_skill_wired_onto_him() -> void:
	var character: PBCharacter = _carriers()[0]
	var units: Array[PBUnit] = [_unit_of(character)]
	var squad := _squad(units, true)
	assert_eq(squad[0].skills.size(), character.skill_ids.size(), "配了几个就该挂上几个")
	var cast := PBSkillRules.cast_at(squad[0], 1)
	assert_not_null(cast, "第 1 格该有东西")
	assert_eq(cast.skill.id, character.skill_ids[0], "而且是角色表点的那一个")
	assert_eq(PBSkillRules.cast_count(squad[0]), 2, "大招那一格还在，没被挤掉")


func test_two_copies_of_the_same_character_do_not_share_one_cooldown() -> void:
	# [PBSkillCast] 记冷却与落点，共享的话两个人的冷却是同一个 ——
	# 而 [method PBSkill.clone] 顶上还有更硬的一条：悬崖二分要能就地改伤害。
	var character: PBCharacter = _carriers()[0]
	var units: Array[PBUnit] = [_unit_of(character), _unit_of(character)]
	var squad := _squad(units, true)
	var one := PBSkillRules.cast_at(squad[0], 1)
	var two := PBSkillRules.cast_at(squad[1], 1)
	assert_ne(one, two, "两个人不该共用同一份状态")
	one.ready_at = 999
	assert_eq(two.ready_at, 0, "改一个不该动到另一个")
	one.skill.damage = 1.0
	assert_ne(two.skill.damage, 1.0, "技能定义也要各自一份")


func test_a_wave_runs_bit_identically_with_and_without_the_skill_table() -> void:
	# **本文件的正题。** 技能只有玩家手动放得出，所以填上 `skill_ids`
	# 不该改变任何自动跑出来的数字。这一条直接对拍两局。
	var character: PBCharacter = _carriers()[0]
	var units: Array[PBUnit] = [_unit_of(character)]
	var wave := PBWaveRules.build(7, _cfg, _rng)

	var with_table := PBBattleSim.new(wave, 0.0, 0.0, _cfg, _squad(units, true))
	var without := PBBattleSim.new(wave, 0.0, 0.0, _cfg, _squad(units, false))
	var a := with_table.run_to_end()
	var b := without.run_to_end()

	assert_eq(a.ticks, b.ticks, "打了多少 tick 要一样")
	assert_eq(a.kills, b.kills, "杀敌数要一样")
	assert_eq(a.leaked, b.leaked, "漏怪数要一样")
	assert_eq(a.allies_lost, b.allies_lost, "阵亡数要一样")
	assert_eq(a.base_damage, b.base_damage, "基地掉的血要**逐位**一样")
	assert_eq(a.cleared, b.cleared, "清没清场也要一样")


func test_the_skill_only_goes_off_when_a_player_orders_it() -> void:
	# 上一条对拍的前提。这一条把前提本身钉住：**没有人下令就一发都不出去。**
	var character: PBCharacter = _carriers()[0]
	var units: Array[PBUnit] = [_unit_of(character)]
	var squad := _squad(units, true)
	var sim := PBBattleSim.new(PBWaveRules.build(7, _cfg, _rng), 0.0, 0.0, _cfg, squad)
	var cast := PBSkillRules.cast_at(squad[0], 1)

	for _i: int in 200:
		sim.step()
	assert_eq(cast.ready_at, 0, "自动档一次都没碰过它 —— 冷却还是开波那个数")
	assert_false(cast.is_pending(), "也没有一发被自动放出去")

	# 后半句换一场新的来验：上面那 200 tick 很可能已经把这一波打完了，
	# 而打完的战斗 [method PBBattleSim.step] 什么都不做 —— 连指令队列也不放。
	var live := PBBattleSim.new(PBWaveRules.build(7, _cfg, _rng), 0.0, 0.0, _cfg, squad)
	live.step()
	assert_true(live.cast_skill_on(squad[0], squad[0], 1), "而玩家下令时它必须放得出")
	# **令先攒着，下一个 tick 才出手**（M7-h，见 [PBSkillOrders]）。
	assert_eq(live.order_of(squad[0]), 1, "这一刻是攒在手上")
	assert_eq(cast.ready_at, 0, "而且冷却还没开始走 —— 它从落地算起")
	live.step()
	assert_gt(cast.ready_at, 0, "推进一个 tick，这一发真的放出去了")
	assert_false(live.can_cast(squad[0], 1), "放过之后这一格就该是灰的")
