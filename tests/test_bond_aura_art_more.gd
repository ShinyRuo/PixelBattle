extends GutTest


func test_byakugou_seal_aura_only_tracks_tsunade_and_sakura() -> void:
	var cfg := PBGameData.config()
	var tsunade := PBUnit.new(cfg.characters.by_id(&"tsunade"))
	var sakura := PBUnit.new(cfg.characters.by_id(&"sakura"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [tsunade, naruto]
	var full: Array[PBUnit] = [tsunade, sakura, naruto]
	var id := &"bond_byakugou_seal_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"tsunade", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"tsunade", []) as Array).has(id))
	assert_true((assigned.get(&"sakura", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_joint_training_aura_only_tracks_naruto_and_killer_bee() -> void:
	var cfg := PBGameData.config()
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var bee := PBUnit.new(cfg.characters.by_id(&"killer_bee"))
	var gaara := PBUnit.new(cfg.characters.by_id(&"gaara"))
	var partial: Array[PBUnit] = [naruto, gaara]
	var full: Array[PBUnit] = [naruto, bee, gaara]
	var id := &"bond_joint_training_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"naruto", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"naruto", []) as Array).has(id))
	assert_true((assigned.get(&"killer_bee", []) as Array).has(id))
	assert_false((assigned.get(&"gaara", []) as Array).has(id))
