extends GutTest


func test_missing_ultimate_keeps_normal_skill_index_and_click_target() -> void:
	var cfg := PBGameData.config()
	var unit := PBUnit.new(cfg.characters.by_id(&"onoki"))
	var state := PBRunState.new()
	state.add_unit(unit)
	var one := PBAttacker.new()
	one.max_hp = 10000.0
	one.ultimate = null
	one.max_mp = 1000.0
	one.skills = [PBSkillCast.new(cfg.skills.by_id(&"dust_release").clone(), 10)]
	var sim := PBBattleSim.new(PBWave.new(), 0.0, 0.0, cfg, [one])
	var card := PBCommandCard.new()
	add_child_autofree(card)
	var picker := PBFieldPicker.new()
	PBSkillBar.show_on(card, sim, one, picker)
	card.refresh(PBSelection.of_unit(unit.key()), state, cfg, PBWavePlan.new(), [unit])
	assert_eq(card.skill_definitions().size(), 2)
	assert_null(card.skill_definitions()[0])
	assert_eq(card.skill_definitions()[1].id, &"dust_release")
	assert_eq(card.command_at(2), PBCommandCard.CMD_SKILL_1)
	assert_true(card.enabled_at(2))
	PBSkillBar.begin(sim, picker, one, card.command_at(2))
	assert_eq(picker.aim_skill, 1)
	assert_eq(picker.aim_mode, PBFieldPicker.Aim.SKILL)
