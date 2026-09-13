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


## 名单里第一个**技能真的打伤害**的角色。治疗那一类不算 ——
## 上面那两条量的是伤害，而 `power_mult` 为 0 的技能量不出比值。
func _skill_carrier() -> PBCharacter:
	for character: PBCharacter in _carriers():
		var skill: PBSkill = _cfg.skills.by_id(character.skill_ids[0])
		if skill != null and skill.power_mult > 0.0:
			return character
	fail_test("该有一个技能打伤害的角色")
	return null


## 一队人在指定队伍倍率下的攻击者。
func _skilled_squad(units: Array[PBUnit], mult: float) -> Array[PBAttacker]:
	return PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, mult, PackedFloat64Array(), _cfg
	)


## 一个波次属性，使得 [param mine] 打它是 [param want] 那种关系。
func _wave_where(mine: PBElement.Type, want: PBElement.Relation) -> PBElement.Type:
	for one: int in PBElement.RING:
		if PBElement.relation(mine, one as PBElement.Type) == want:
			return one as PBElement.Type
	fail_test("克制环上该有这么一波")
	return PBElement.Type.PHYSICAL


## 这个角色的第一个技能，打在 [param wave] 那一波上是多少伤害。
func _damage_against(character: PBCharacter, wave: PBElement.Type) -> float:
	var squad := PBCombatRules.build_attackers(
		[_unit_of(character)] as Array[PBUnit],
		wave,
		1.0,
		PackedFloat64Array(),
		_cfg
	)
	return squad[0].skills[0].skill.damage


func _squad(units: Array[PBUnit], with_skills: bool) -> Array[PBAttacker]:
	var cfg: PBSimConfig = _cfg
	if not with_skills:
		# 同一份配置，只把技能表摘掉 —— 摘掉就是 M7-g 之前的每一天。
		cfg = PBGameData.config()
		cfg.field_height = 0.0
		cfg.spawn_window = 0.0
		cfg.skills = null
	return PBCombatRules.build_attackers(
		units, PBElement.Type.FIRE, 1.0, PackedFloat64Array(), cfg
	)


# ── 伤害是派生量（M11-a）────────────────────────────────────────


func test_a_character_skill_eats_the_element_matchup_like_the_ultimate_does() -> void:
	# **M11-a 之前它不吃。** 角色技能的伤害是 `.tres` 里的字面量，
	# 而大招走 `战力 × 克制 × 队伍倍率 × 系数` —— 于是「配了 element = 火」
	# 在这条路上是一句空话，§03 铁律 4 只对大招成立。
	#
	# 判据是两波的比值，不是绝对值：绝对值会跟着占位数值一起变，
	# 而这条断的是「克制这一乘有没有发生」。
	var carrier := _skill_carrier()
	var skill: PBSkill = _cfg.skills.by_id(carrier.skill_ids[0])
	# **按关系找那两波，不用 `counter_of`** —— 那个函数答的是「谁克制 x」，
	# 而这里要的是两个方向各一波，写反了断言仍然会红但红得没道理。
	var strong := _damage_against(carrier, _wave_where(skill.element, PBElement.Relation.COUNTER))
	var weak := _damage_against(carrier, _wave_where(skill.element, PBElement.Relation.WEAK))
	assert_gt(strong, 0.0, "前提：这个技能真的打伤害")
	assert_gt(strong, weak, "打克制的那一波该更疼")
	assert_almost_eq(
		strong / weak,
		_cfg.mult_counter / _cfg.mult_weak,
		0.001,
		"两波的比值该正好是那两个克制倍率的比"
	)


func test_a_character_skill_eats_the_team_multiplier_too() -> void:
	# 攻击科技、羁绊、装备三样都乘在同一个 `mult` 上。M11-a 之前
	# 那一乘对角色技能不发生 —— 也就是「装备加的攻对技能无效」，不报错。
	var carrier := _skill_carrier()
	var plain := _skilled_squad([_unit_of(carrier)], 1.0)
	var buffed := _skilled_squad([_unit_of(carrier)], 2.0)
	assert_almost_eq(
		buffed[0].skills[0].skill.damage,
		plain[0].skills[0].skill.damage * 2.0,
		0.001,
		"队伍倍率翻倍，技能伤害也该翻倍"
	)


func test_writing_damage_into_a_tres_is_refused_instead_of_ignored() -> void:
	# 那个数会在建人时被 `power_mult` 算出来的值覆盖 —— 写了也不生效，
	# 而这个项目最贵的 bug 就是这个形状。
	var skill := PBSkill.new()
	skill.id = &"probe"
	skill.power_mult = 1.0
	assert_eq(PBSkillLoader.check(skill), "", "只配倍率是合法的")
	skill.damage = 160.0
	assert_ne(PBSkillLoader.check(skill), "", "直接写 damage 该被拒收")


func test_an_empty_skill_that_does_nothing_at_all_is_refused() -> void:
	# 既不打伤害也不挂效果的技能，指令卡上有一格、按下去屏幕上什么都不发生。
	var skill := PBSkill.new()
	skill.id = &"probe"
	assert_ne(PBSkillLoader.check(skill), "", "什么都不做的技能该被拒收")


func test_cloning_carries_every_field_without_anyone_listing_them() -> void:
	# `clone()` M11-a 之前是 21 行手抄，而这个类正好有 21 个 `@export` ——
	# **加一个字段忘了抄一行不报错**，表现是「探测时那个技能少了一个效果」。
	# 现在走反射，这条断言因此也是反射的：以后加字段两边都不用改。
	var skill := PBSkill.new()
	skill.id = &"probe"
	skill.power_mult = 2.5
	skill.damage = 999.0
	skill.radius = 0.3
	skill.gather = true
	skill.slow_scale = 0.5
	skill.mp_cost = 12.0
	var copy := skill.clone()
	var seen: int = 0
	for prop: Dictionary in skill.get_property_list():
		if not (prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		assert_eq(copy.get(prop["name"]), skill.get(prop["name"]), "字段 %s 没跟过来" % prop["name"])
		seen += 1
	assert_gt(seen, 15, "该扫到这个类全部的导出字段")


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


func test_every_skill_in_the_table_has_an_owner() -> void:
	# **反过来那一条**（M12-c1）。上面那条拦的是「角色点了一个不存在的技能」，
	# 这条拦的是「技能躺在表里没人点」——
	# 两个方向都会因为一个拼错的键出现，而只有一个方向今天有人查。
	#
	# 同 `test_portrait_data.gd` 那条「每一张头像都要有主」：
	# 它换到的是**接内容全程成立**，而「每个角色都有技能」那种断言
	# 在内容永远落后于名册时等于断言「配完了没有」。
	var owned: Dictionary = {}
	for character: PBCharacter in PBCharacterLoader.table().all():
		for id: StringName in character.skill_ids:
			owned[id] = character.id
	var table := PBSkillLoader.table()
	for id: StringName in table.ids():
		assert_true(owned.has(id), "技能 %s 没有主 —— 哪一边拼错了？" % id)


func test_every_buff_in_the_folder_is_reachable_from_some_skill() -> void:
	# 同上，只是往下一层：`data/buffs/` 里的一份效果如果没有任何技能引用它，
	# 它这辈子不会生效，**而没有任何地方会说这件事**。
	var used: Dictionary = {}
	var table := PBSkillLoader.table()
	for id: StringName in table.ids():
		var skill: PBSkill = table.by_id(id)
		for buff: PBBuff in skill.on_hit:
			used[buff.id] = true
		for buff: PBBuff in skill.on_self:
			used[buff.id] = true
	# **技能不再是唯一的引用方**（M12-c2）：角色自带的被动也挂效果
	# （[member PBCharacter.on_hit_buffs]）。不数这一路的话，带土那份晕眩
	# 会被当成孤儿报出来 —— 而它实际上正在生效。
	for character: PBCharacter in PBCharacterLoader.table().all():
		for buff: PBBuff in character.on_hit_buffs:
			used[buff.id] = true
	var dir := DirAccess.open("res://data/buffs")
	assert_not_null(dir, "buffs 目录该在")
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		assert_true(used.has(StringName(file_name.get_basename())), "效果 %s 没人引用" % file_name)


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
