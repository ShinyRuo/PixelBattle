extends GutTest
## 羁绊改一个成员的某个技能（M12-d2）。

## ## 这个文件守的是什么
##
## **原版羁绊的主形状就是这个**：118 条效果里 80 条是「强化本人的某个具名技能」
## （涉及 38 组），而「全队 +X%」只有 12 条。M10-d 当时卡住不是缺一个键，
## 是被强化的对象根本不存在 —— 那时 49 个角色里配了技能的是 2 个。
##
## 三条：
##
## 1. **补丁打在复制品上** —— 打在 `.tres` 那一份上的话，这一波的加成会
##    漏进下一波、漏进别的角色、漏进悬崖二分，**而它不报错**
## 2. **排在伤害换算之前** —— `power_scale` 改的就是换算要用的那个倍率
## 3. **不认识的键不许静默跳过**

const RATE: int = 20

var _cfg: PBSimConfig


func before_each() -> void:
	_cfg = PBGameData.config()


# ── 补丁本身 ─────────────────────────────────────────────────


func test_each_key_moves_the_field_it_says_it_moves() -> void:
	# 词汇表里的键 = 已经接上读点的键（同 [constant PBBuffRules.ALL] 顶上那条）。
	# 拼对了却什么都不改的键比拼错更难查。
	for key: StringName in PBSkillPatchRules.ALL:
		var skill := _skill()
		var before := _snapshot(skill)
		assert_eq(PBSkillPatchRules.apply(skill, {key: 2.0}, RATE), 1, "「%s」该打得上" % key)
		assert_ne(_snapshot(skill), before, "「%s」打上了却什么都没改" % key)


func test_the_suffix_says_whether_it_adds_scales_or_sets() -> void:
	# 原版三种语义都有。统一成一种的话读表的人得记住哪个字段是哪种 ——
	# 而记错**不报错**，只是那一组的强度差一截。
	var skill := _skill()
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.POWER_SCALE: 1.4}, RATE)
	assert_almost_eq(skill.power_mult, 2.8, 0.0001, "_scale 是乘")
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.TARGETS_ADD: 1.0}, RATE)
	assert_eq(skill.max_targets, 4, "_add 是加")
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.RADIUS_SET: 0.25}, RATE)
	assert_almost_eq(skill.radius, 0.25, 0.0001, "_set 是设")


func test_seconds_become_ticks_at_the_rate_we_are_told() -> void:
	# 表里写秒（和别处一样），而 [PBSkill] 存 tick。换算写死 20 的话，
	# 改一次 `tick_rate` 这一档就会静默错一个倍数。
	var skill := _skill()
	PBSkillPatchRules.apply(skill, {PBSkillPatchRules.SLOW_SECS_SET: 2.0}, RATE)
	assert_eq(skill.slow_ticks, 2 * RATE, "两秒该是 40 tick")


func test_a_key_nobody_knows_is_refused_not_silently_applied() -> void:
	var skill := _skill()
	var before := _snapshot(skill)
	assert_false(PBSkillPatchRules.is_known(&"no_such_key"), "这个键不该认得")
	assert_eq(PBSkillPatchRules.apply(skill, {&"no_such_key": 3.0}, RATE), 0, "一条都没打上")
	assert_eq(_snapshot(skill), before, "什么都不许改")


# ── 接进战斗 ─────────────────────────────────────────────────


func test_the_patch_lands_on_the_copy_not_on_the_file_on_disk() -> void:
	# **这一条是这一步最要紧的。** [method PBCombatRules._equip_skills] 每一波
	# 按 [method PBSkill.clone] 现造一份，所以改它是安全的 —— 而 `clone()`
	# 到 M12-d2 才真的安全：在那之前 `on_hit` 那个数组是**同一个对象**。
	var table := PBSkillLoader.table()
	var id: StringName = table.ids()[0]
	var shared: PBSkill = table.by_id(id)
	var before: float = shared.power_mult
	var copy := shared.clone()
	PBSkillPatchRules.apply(copy, {PBSkillPatchRules.POWER_SCALE: 9.0}, RATE)
	assert_almost_eq(shared.power_mult, before, 0.0001, "盘上那一份一个数都不许动")


func test_cloning_gives_the_copy_its_own_effect_list() -> void:
	# 反射拷贝给的是同一个数组对象。往里追加等于改写 `data/skills/*.tres`，
	# **于是这一波挂上去的效果会漏进下一波**，而它不报错。
	var skill := _skill()
	skill.on_hit = [PBBuff.new()] as Array[PBBuff]
	var copy := skill.clone()
	copy.on_hit.append(PBBuff.new())
	assert_eq(skill.on_hit.size(), 1, "原件的效果表不许被追加")
	assert_eq(copy.on_hit.size(), 2, "复制品自己那份该变长")


func test_the_real_table_only_names_skills_their_owner_actually_has() -> void:
	# 点一个他没配的技能，那一条补丁永远打不上 —— **而它不报错**，
	# 表现是「那一组羁绊好像没什么用」。
	var characters := PBCharacterLoader.table()
	var seen: int = 0
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_skill_patches:
			var character := characters.by_id(who)
			assert_not_null(character, "「%s」不在名册里" % who)
			for skill_id: StringName in bond.member_skill_patches[who]:
				assert_true(
					character.skill_ids.has(skill_id),
					"「%s」身上没有技能「%s」，%s 那条补丁打不上" % [who, skill_id, bond.id]
				)
				seen += 1
	assert_gt(seen, 0, "真表里一条技能补丁都没有，上面什么都没量")


func test_every_patch_key_in_the_real_table_is_one_we_know() -> void:
	for bond: PBBond in _cfg.bonds.all():
		for who: StringName in bond.member_skill_patches:
			for skill_id: StringName in bond.member_skill_patches[who]:
				for key: StringName in bond.member_skill_patches[who][skill_id]:
					assert_true(PBSkillPatchRules.is_known(key), "「%s」这个键没人认得" % key)


func _skill() -> PBSkill:
	var skill := PBSkill.new()
	skill.id = &"probe_skill"
	skill.power_mult = 2.0
	skill.radius = 0.1
	skill.cooldown_ticks = 100
	skill.max_targets = 3
	skill.summon_count = 1
	skill.slow_scale = 1.0
	skill.slow_ticks = 0
	return skill


func _snapshot(skill: PBSkill) -> Array:
	return [
		skill.power_mult,
		skill.radius,
		skill.cooldown_ticks,
		skill.max_targets,
		skill.summon_count,
		skill.slow_scale,
		skill.slow_ticks,
	]
