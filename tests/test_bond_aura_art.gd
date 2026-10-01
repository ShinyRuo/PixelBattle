extends GutTest


func test_real_bond_aura_is_only_assigned_to_active_members() -> void:
	var cfg := PBGameData.config()
	var haku := PBUnit.new(cfg.characters.by_id(&"haku"))
	var zabuza := PBUnit.new(cfg.characters.by_id(&"zabuza"))
	var stranger := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var whole: Array[PBUnit] = [haku, zabuza, stranger]
	var without_partner: Array[PBUnit] = [haku, stranger]
	var id := &"bond_haku_and_zabuza_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(without_partner, whole, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(whole, whole, cfg.bonds)
	assert_true((assigned.get(&"haku", []) as Array).has(id))
	assert_true((assigned.get(&"zabuza", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_bond_aura_retracts_when_member_dies() -> void:
	var skin := PBBuffGlow.skin_for(&"bond_haku_and_zabuza_aura")
	assert_not_null(skin)
	if skin == null:
		return
	var glow := PBBuffGlow.new()
	add_child_autofree(glow)
	var ids: Array[StringName] = [&"bond_haku_and_zabuza_aura"]
	glow.sync_bag(PBBuffBag.new(), 0, 20, true, ids)
	assert_eq(glow._drawings.size(), 1)
	glow.sync_bag(PBBuffBag.new(), 1, 20, false, ids)
	assert_true(glow._drawings.is_empty())


func test_immortal_pair_aura_only_tracks_kakuzu_and_hidan() -> void:
	var cfg := PBGameData.config()
	var kakuzu := PBUnit.new(cfg.characters.by_id(&"kakuzu"))
	var hidan := PBUnit.new(cfg.characters.by_id(&"hidan"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [kakuzu, hidan, naruto]
	var no_hidan: Array[PBUnit] = [kakuzu, naruto]
	var id := &"bond_immortal_pair_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(no_hidan, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"kakuzu", []) as Array).has(id))
	assert_true((assigned.get(&"hidan", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_akatsuki_four_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"itachi", &"deidara", &"konan", &"zetsu"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var id := &"bond_akatsuki_four_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"itachi", &"deidara", &"konan", &"zetsu"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_kai_squad_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"might_guy", &"rock_lee", &"tenten", &"neji_hyuga"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var id := &"bond_kai_squad_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"might_guy", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"might_guy", &"rock_lee", &"tenten", &"neji_hyuga"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_hyuga_pair_aura_only_tracks_neji_and_hinata() -> void:
	var cfg := PBGameData.config()
	var neji := PBUnit.new(cfg.characters.by_id(&"neji_hyuga"))
	var hinata := PBUnit.new(cfg.characters.by_id(&"hinata"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [neji, hinata, naruto]
	var partial: Array[PBUnit] = [neji, naruto]
	var id := &"bond_hyuga_pair_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"neji_hyuga", []) as Array).has(id))
	assert_true((assigned.get(&"hinata", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_sand_siblings_aura_waits_for_all_three_members() -> void:
	var cfg := PBGameData.config()
	var gaara := PBUnit.new(cfg.characters.by_id(&"gaara"))
	var temari := PBUnit.new(cfg.characters.by_id(&"temari"))
	var kankuro := PBUnit.new(cfg.characters.by_id(&"kankuro"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [gaara, temari, kankuro, naruto]
	var partial: Array[PBUnit] = [gaara, temari, naruto]
	var id := &"bond_sand_siblings_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_almost_eq(skin.tint.a, 0.35, 0.001)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"gaara", &"temari", &"kankuro"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_earth_curse_aura_only_tracks_kimimaro_and_orochimaru() -> void:
	var cfg := PBGameData.config()
	var kimimaro := PBUnit.new(cfg.characters.by_id(&"kimimaro"))
	var orochimaru := PBUnit.new(cfg.characters.by_id(&"orochimaru"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [kimimaro, orochimaru, naruto]
	var partial: Array[PBUnit] = [kimimaro, naruto]
	var id := &"bond_earth_curse_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"kimimaro", []) as Array).has(id))
	assert_true((assigned.get(&"orochimaru", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_my_cage_aura_only_tracks_kimimaro_and_jugo() -> void:
	var cfg := PBGameData.config()
	var kimimaro := PBUnit.new(cfg.characters.by_id(&"kimimaro"))
	var jugo := PBUnit.new(cfg.characters.by_id(&"jugo"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [kimimaro, jugo, naruto]
	var partial: Array[PBUnit] = [kimimaro, naruto]
	var id := &"bond_my_cage_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"kimimaro", []) as Array).has(id))
	assert_true((assigned.get(&"jugo", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_five_kage_aura_waits_for_all_five_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"tsunade", &"gaara", &"mei", &"raikage", &"onoki"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var full: Array[PBUnit] = [
		members[0], members[1], members[2], members[3], members[4], naruto
	]
	var id := &"bond_five_kage_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"tsunade", &"gaara", &"mei", &"raikage", &"onoki"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_lightning_blades_aura_only_tracks_raikage_and_bee() -> void:
	var cfg := PBGameData.config()
	var raikage := PBUnit.new(cfg.characters.by_id(&"raikage"))
	var bee := PBUnit.new(cfg.characters.by_id(&"killer_bee"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [raikage, bee, naruto]
	var partial: Array[PBUnit] = [raikage, naruto]
	var id := &"bond_lightning_blades_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"raikage", []) as Array).has(id))
	assert_true((assigned.get(&"killer_bee", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_senju_brothers_aura_only_tracks_hashirama_and_tobirama() -> void:
	var cfg := PBGameData.config()
	var hashirama := PBUnit.new(cfg.characters.by_id(&"hashirama"))
	var tobirama := PBUnit.new(cfg.characters.by_id(&"tobirama"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [hashirama, tobirama, naruto]
	var partial: Array[PBUnit] = [hashirama, naruto]
	var id := &"bond_senju_brothers_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"hashirama", []) as Array).has(id))
	assert_true((assigned.get(&"tobirama", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_brothers_bond_aura_only_tracks_itachi_and_sasuke() -> void:
	var cfg := PBGameData.config()
	var itachi := PBUnit.new(cfg.characters.by_id(&"itachi"))
	var sasuke := PBUnit.new(cfg.characters.by_id(&"sasuke"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [itachi, sasuke, naruto]
	var partial: Array[PBUnit] = [itachi, naruto]
	var id := &"bond_brothers_bond_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"itachi", []) as Array).has(id))
	assert_true((assigned.get(&"sasuke", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_vermilion_pair_aura_only_tracks_itachi_and_kisame() -> void:
	var cfg := PBGameData.config()
	var itachi := PBUnit.new(cfg.characters.by_id(&"itachi"))
	var kisame := PBUnit.new(cfg.characters.by_id(&"kisame"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [itachi, kisame, naruto]
	var partial: Array[PBUnit] = [itachi, naruto]
	var id := &"bond_vermilion_pair_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"itachi", []) as Array).has(id))
	assert_true((assigned.get(&"kisame", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_divine_wound_aura_only_tracks_konan_and_tendo() -> void:
	var cfg := PBGameData.config()
	var konan := PBUnit.new(cfg.characters.by_id(&"konan"))
	var tendo := PBUnit.new(cfg.characters.by_id(&"tendo"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var full: Array[PBUnit] = [konan, tendo, naruto]
	var partial: Array[PBUnit] = [konan, naruto]
	var id := &"bond_divine_wound_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"konan", []) as Array).has(id))
	assert_true((assigned.get(&"tendo", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_masterminds_aura_waits_for_all_five_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"madara", &"obito", &"kabuto", &"tendo", &"zetsu"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var full: Array[PBUnit] = [
		members[0], members[1], members[2], members[3], members[4], naruto
	]
	var id := &"bond_masterminds_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"madara", &"obito", &"kabuto", &"tendo", &"zetsu"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_team_seven_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"naruto", &"sasuke", &"sakura", &"kakashi"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var gaara := PBUnit.new(cfg.characters.by_id(&"gaara"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], gaara]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], gaara]
	var id := &"bond_team_seven_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"naruto", &"sasuke", &"sakura", &"kakashi"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"gaara", []) as Array).has(id))


func test_ino_shika_cho_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"shikamaru", &"choji", &"ino", &"asuma"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var id := &"bond_ino_shika_cho_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"shikamaru", &"choji", &"ino", &"asuma"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_sannin_aura_waits_for_all_three_members() -> void:
	var cfg := PBGameData.config()
	var jiraiya := PBUnit.new(cfg.characters.by_id(&"jiraiya"))
	var orochimaru := PBUnit.new(cfg.characters.by_id(&"orochimaru"))
	var tsunade := PBUnit.new(cfg.characters.by_id(&"tsunade"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [jiraiya, orochimaru, naruto]
	var full: Array[PBUnit] = [jiraiya, orochimaru, tsunade, naruto]
	var id := &"bond_sannin_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"jiraiya", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"jiraiya", &"orochimaru", &"tsunade"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_taka_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"sasuke", &"suigetsu", &"jugo", &"karin"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var id := &"bond_taka_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"sasuke", &"suigetsu", &"jugo", &"karin"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))
