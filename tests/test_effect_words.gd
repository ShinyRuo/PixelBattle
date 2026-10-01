extends GutTest
## 说明卡上的字（[PBEffectWords]）：技能名、技能效果、buff 详情、羁绊效果，以及三处悬停入口。
##
## 这里错了全都不报错：技能格上写着角色的英文键、效果词条显示成 `buff_fx.stun`、
## 灰着的技能格悬停没反应 —— 屏幕上都有字，只是字不对。

const BATTLE_SCENE := "res://scenes/battle.tscn"
const FIXED_SEED: int = 20260914


func _prepared() -> Node2D:
	var root: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	root.run_seed = FIXED_SEED
	root.auto_play = false
	add_child_autofree(root)
	root._enter_prepare()
	return root


## 表里第一个配了技能的角色。
func _caster(cfg: PBSimConfig) -> PBCharacter:
	for character: PBCharacter in cfg.characters.all():
		if not character.skill_ids.is_empty():
			return character
	return null


# ── 名字与词条表 ────────────────────────────────────────────────


func test_skill_names_come_from_the_display_name_column() -> void:
	# 语言表曾经把技能表第 2 列（角色键）当成了显示名，指令卡上的技能格写着角色的英文键。
	var rows := 0
	for line: String in FileAccess.get_file_as_string("res://data/skills.tsv").split("\n"):
		var cells: PackedStringArray = line.strip_edges().split("\t")
		if line.begins_with("#") or cells.size() < 3:
			continue
		assert_eq(PBLocale.text("skill.%s" % cells[0]), cells[2], "技能 %s 的显示名" % cells[0])
		rows += 1
	assert_gt(rows, 0, "前提：技能表读得到")


func test_every_effect_key_has_words() -> void:
	# 词条缺一条的表现是说明卡上出现 `buff_fx.xxx` 这样的键名。
	for key: StringName in PBBuffRules.ALL:
		assert_ne(PBLocale.text("buff_fx.%s" % key), "buff_fx.%s" % key, "效果键 %s 缺词条" % key)
	for key: StringName in PBSkillPatchRules.ALL:
		assert_ne(PBLocale.text("patch.%s" % key), "patch.%s" % key, "技能补丁键 %s 缺词条" % key)
	for key: StringName in PBPassiveRules.ALL:
		assert_ne(PBLocale.text("mod.%s" % key), "mod.%s" % key, "被动键 %s 缺词条" % key)


func test_buff_words_spell_out_the_special_cases() -> void:
	var words := PBEffectWords.buff_words(
		{&"enemy_speed_scale": 0.0, &"stun": 1.0, &"crit_chance": 0.1, &"damage_scale": 1.35}
	)
	var text := "、".join(words)
	assert_true(text.contains("定身"), "移速 ×0 写成定身：%s" % text)
	assert_true(text.contains("晕眩"), "晕眩没有数字：%s" % text)
	assert_true(text.contains("暴击率 +10%"), "成数乘 100：%s" % text)
	assert_true(text.contains("×1.35"), "倍率照写：%s" % text)


# ── 三种说明卡的正文 ────────────────────────────────────────────


func test_a_skill_card_names_what_it_hangs_on_the_target() -> void:
	var root := _prepared()
	var picked: PBSkill = null
	for id: StringName in root._cfg.skills.ids():
		var skill: PBSkill = root._cfg.skills.by_id(id)
		if not skill.on_hit.is_empty():
			picked = skill
			break
	assert_not_null(picked, "前提：有技能带命中效果")
	var body := PBEffectWords.skill_body(picked, root._cfg)
	assert_true(body.contains("冷却"), "要写冷却：%s" % body)
	assert_true(body.contains(PBLocale.text(picked.on_hit[0].name_key)), "要写附带的效果：%s" % body)
	assert_false(body.contains("buff_fx."), "不能漏出键名：%s" % body)
	assert_true(PBEffectWords.skill_title(picked).begins_with(PBLocale.of_skill(picked)), "标题是技能名")


func test_a_bond_card_lists_what_the_full_tier_gives() -> void:
	var root := _prepared()
	var with_function: PBBond = null
	var with_patch: PBBond = null
	for bond: PBBond in root._cfg.bonds.all():
		if with_function == null and bond.function_at(bond.full_tier_count()) != &"":
			with_function = bond
		if with_patch == null and not bond.member_skill_patches.is_empty():
			with_patch = bond
	assert_not_null(with_function, "前提：有羁绊带功能")
	var text := "\n".join(PBEffectWords.bond_effects(with_function, root._cfg))
	var full: int = with_function.full_tier_count()
	var function := PBLocale.of_bond_function(with_function.function_at(full))
	assert_true(text.contains(function), "要写功能名：%s" % text)
	var body: String = root._unit_info._bond_body(with_function)
	assert_true(body.contains("满档效果"), "悬停卡里要有效果段：%s" % body)
	if with_patch != null:
		var patched := "\n".join(PBEffectWords.bond_effects(with_patch, root._cfg))
		assert_false(patched.contains("patch."), "补丁不能漏出键名：%s" % patched)


func test_the_buff_strip_asks_for_the_card_of_the_cell_under_the_mouse() -> void:
	var cfg := PBSimConfig.new()
	var buff := PBBuff.new()
	buff.id = &"probe_slow"
	buff.name_key = "buff.haku_chill"
	buff.kind = PBBuff.Kind.DURATION
	buff.friendly = false
	buff.duration_seconds = 5.0
	buff.mods = {&"enemy_speed_scale": 0.7}
	var bag := PBBuffBag.new()
	bag.add(buff, buff.mods, 0, buff.duration_ticks(cfg), 0)
	var strip := PBBuffStrip.new()
	add_child_autofree(strip)
	strip.show_bag(bag, 0, cfg)
	watch_signals(strip)

	strip._hover_at(Vector2(2.0, 2.0))
	assert_signal_emitted(strip, "hint_requested", "停在第一格上要一张卡")
	var args: Array = get_signal_parameters(strip, "hint_requested")
	assert_string_contains(args[1], PBLocale.text("buff.haku_chill"), "标题是效果名")
	assert_string_contains(args[2], "×0.70", "正文写效果")
	assert_string_contains(args[2], "还剩 5 秒", "正文写还剩多久")

	strip._hover_at(Vector2(float(PBBuffStrip.PITCH) * 2.0 + 1.0, 2.0))
	assert_signal_emitted(strip, "hint_closed", "挪到空格上就收卡")


# ── 准备阶段的技能格 ────────────────────────────────────────────


func test_prepare_shows_skill_cells_greyed_out_but_hoverable() -> void:
	# 玩家定的：准备阶段也摆技能格，和战斗中同一个位置，按不下去，只用来看说明。
	var root := _prepared()
	var character := _caster(root._cfg)
	assert_not_null(character, "前提：名册里有人配了技能")
	var unit := PBUnit.new(character)
	root._state.add_unit(unit)
	root._select(PBSelection.Kind.UNIT, unit.key())
	var card: PBCommandCard = root._command
	assert_eq(card.command_at(2), PBCommandCard.CMD_SKILL_1, "第 2 格是第一个技能，和战斗中同位置")
	assert_false(card.enabled_at(2), "准备阶段按不下去")
	assert_eq(
		card._slots[2].text,
		PBLocale.of_skill(root._cfg.skills.by_id(character.skill_ids[0])),
		"格子上写真实的技能名"
	)
	assert_eq(card.command_at(PBCommandCard.DISPATCH_SLOT), PBCommandCard.CMD_DISPATCH, "派任务让到后面")

	watch_signals(card)
	card._on_slot_hovered(2)
	assert_signal_emitted(card, "hint_requested", "灰着的格子悬停照样要说明卡")
	card._on_slot_pressed(2)
	assert_eq(root._phase, root.Phase.PREPARE, "按了也不会发出施放指令")
