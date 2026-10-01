extends GutTest


func test_puppet_masters_aura_only_tracks_chiyo_and_kankuro() -> void:
	var cfg := PBGameData.config()
	var chiyo := PBUnit.new(cfg.characters.by_id(&"chiyo"))
	var kankuro := PBUnit.new(cfg.characters.by_id(&"kankuro"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [chiyo, naruto]
	var full: Array[PBUnit] = [chiyo, kankuro, naruto]
	var id := &"bond_puppet_masters_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"chiyo", []) as Array).has(id))
	assert_true((assigned.get(&"kankuro", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_inner_love_aura_only_tracks_chiyo_and_sasori() -> void:
	var cfg := PBGameData.config()
	var chiyo := PBUnit.new(cfg.characters.by_id(&"chiyo"))
	var sasori := PBUnit.new(cfg.characters.by_id(&"sasori"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [chiyo, naruto]
	var full: Array[PBUnit] = [chiyo, sasori, naruto]
	var id := &"bond_inner_love_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"chiyo", []) as Array).has(id))
	assert_true((assigned.get(&"sasori", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_hero_family_aura_waits_for_all_three_members() -> void:
	var cfg := PBGameData.config()
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var kushina := PBUnit.new(cfg.characters.by_id(&"kushina"))
	var minato := PBUnit.new(cfg.characters.by_id(&"minato"))
	var gaara := PBUnit.new(cfg.characters.by_id(&"gaara"))
	var partial: Array[PBUnit] = [naruto, kushina, gaara]
	var full: Array[PBUnit] = [naruto, kushina, minato, gaara]
	var id := &"bond_hero_family_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"naruto", &"kushina", &"minato"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"gaara", []) as Array).has(id))


func test_leaf_and_root_aura_only_tracks_hiruzen_and_danzo() -> void:
	var cfg := PBGameData.config()
	var hiruzen := PBUnit.new(cfg.characters.by_id(&"hiruzen"))
	var danzo := PBUnit.new(cfg.characters.by_id(&"danzo"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [hiruzen, naruto]
	var full: Array[PBUnit] = [hiruzen, danzo, naruto]
	var id := &"bond_leaf_and_root_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"hiruzen", []) as Array).has(id))
	assert_true((assigned.get(&"danzo", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_strategist_couple_aura_only_tracks_temari_and_shikamaru() -> void:
	var cfg := PBGameData.config()
	var temari := PBUnit.new(cfg.characters.by_id(&"temari"))
	var shikamaru := PBUnit.new(cfg.characters.by_id(&"shikamaru"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [temari, naruto]
	var full: Array[PBUnit] = [temari, shikamaru, naruto]
	var id := &"bond_strategist_couple_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"temari", []) as Array).has(id))
	assert_true((assigned.get(&"shikamaru", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_tsuchikage_guard_aura_only_tracks_onoki_and_kurotsuchi() -> void:
	var cfg := PBGameData.config()
	var onoki := PBUnit.new(cfg.characters.by_id(&"onoki"))
	var kurotsuchi := PBUnit.new(cfg.characters.by_id(&"kurotsuchi"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [onoki, naruto]
	var full: Array[PBUnit] = [onoki, kurotsuchi, naruto]
	var id := &"bond_tsuchikage_guard_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"onoki", []) as Array).has(id))
	assert_true((assigned.get(&"kurotsuchi", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_crimson_dusk_aura_only_tracks_asuma_and_kurenai() -> void:
	var cfg := PBGameData.config()
	var asuma := PBUnit.new(cfg.characters.by_id(&"asuma"))
	var kurenai := PBUnit.new(cfg.characters.by_id(&"kurenai"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [asuma, naruto]
	var full: Array[PBUnit] = [asuma, kurenai, naruto]
	var id := &"bond_crimson_dusk_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"asuma", []) as Array).has(id))
	assert_true((assigned.get(&"kurenai", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_master_and_pupil_aura_only_tracks_orochimaru_and_hiruzen() -> void:
	var cfg := PBGameData.config()
	var orochimaru := PBUnit.new(cfg.characters.by_id(&"orochimaru"))
	var hiruzen := PBUnit.new(cfg.characters.by_id(&"hiruzen"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [orochimaru, naruto]
	var full: Array[PBUnit] = [orochimaru, hiruzen, naruto]
	var id := &"bond_master_and_pupil_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"orochimaru", []) as Array).has(id))
	assert_true((assigned.get(&"hiruzen", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_shadow_and_blade_aura_only_tracks_asuma_and_shikamaru() -> void:
	var cfg := PBGameData.config()
	var asuma := PBUnit.new(cfg.characters.by_id(&"asuma"))
	var shikamaru := PBUnit.new(cfg.characters.by_id(&"shikamaru"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [asuma, naruto]
	var full: Array[PBUnit] = [asuma, shikamaru, naruto]
	var id := &"bond_shadow_and_blade_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"asuma", []) as Array).has(id))
	assert_true((assigned.get(&"shikamaru", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_truest_friends_aura_only_tracks_itachi_and_shisui() -> void:
	var cfg := PBGameData.config()
	var itachi := PBUnit.new(cfg.characters.by_id(&"itachi"))
	var shisui := PBUnit.new(cfg.characters.by_id(&"shisui"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [itachi, naruto]
	var full: Array[PBUnit] = [itachi, shisui, naruto]
	var id := &"bond_truest_friends_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"itachi", []) as Array).has(id))
	assert_true((assigned.get(&"shisui", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_mizukage_guard_aura_only_tracks_mei_and_chojuro() -> void:
	var cfg := PBGameData.config()
	var mei := PBUnit.new(cfg.characters.by_id(&"mei"))
	var chojuro := PBUnit.new(cfg.characters.by_id(&"chojuro"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [mei, naruto]
	var full: Array[PBUnit] = [mei, chojuro, naruto]
	var id := &"bond_mizukage_guard_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"mei", []) as Array).has(id))
	assert_true((assigned.get(&"chojuro", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_eternal_rivals_aura_only_tracks_guy_and_kakashi() -> void:
	var cfg := PBGameData.config()
	var guy := PBUnit.new(cfg.characters.by_id(&"might_guy"))
	var kakashi := PBUnit.new(cfg.characters.by_id(&"kakashi"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [guy, naruto]
	var full: Array[PBUnit] = [guy, kakashi, naruto]
	var id := &"bond_eternal_rivals_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"might_guy", []) as Array).has(id))
	assert_true((assigned.get(&"kakashi", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_power_of_youth_aura_only_tracks_guy_and_rock_lee() -> void:
	var cfg := PBGameData.config()
	var guy := PBUnit.new(cfg.characters.by_id(&"might_guy"))
	var lee := PBUnit.new(cfg.characters.by_id(&"rock_lee"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [guy, naruto]
	var full: Array[PBUnit] = [guy, lee, naruto]
	var id := &"bond_power_of_youth_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"might_guy", []) as Array).has(id))
	assert_true((assigned.get(&"rock_lee", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_child_of_prophecy_aura_only_tracks_naruto_and_jiraiya() -> void:
	var cfg := PBGameData.config()
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var jiraiya := PBUnit.new(cfg.characters.by_id(&"jiraiya"))
	var gaara := PBUnit.new(cfg.characters.by_id(&"gaara"))
	var partial: Array[PBUnit] = [naruto, gaara]
	var full: Array[PBUnit] = [naruto, jiraiya, gaara]
	var id := &"bond_child_of_prophecy_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	assert_true(PBBondAuraArt.active_member_auras(partial, full, cfg.bonds).is_empty())
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"naruto", []) as Array).has(id))
	assert_true((assigned.get(&"jiraiya", []) as Array).has(id))
	assert_false((assigned.get(&"gaara", []) as Array).has(id))


func test_three_of_them_aura_waits_for_obito_kakashi_and_rin() -> void:
	var cfg := PBGameData.config()
	var obito := PBUnit.new(cfg.characters.by_id(&"obito"))
	var kakashi := PBUnit.new(cfg.characters.by_id(&"kakashi"))
	var rin := PBUnit.new(cfg.characters.by_id(&"rin_nohara"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [obito, kakashi, naruto]
	var full: Array[PBUnit] = [obito, kakashi, rin, naruto]
	var id := &"bond_three_of_them_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"obito", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"obito", &"kakashi", &"rin_nohara"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_team_eight_aura_waits_for_all_four_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"kurenai", &"hinata", &"shino", &"kiba"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var id := &"bond_team_eight_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"kurenai", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"kurenai", &"hinata", &"shino", &"kiba"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_uchiha_clan_aura_waits_for_all_five_members() -> void:
	var cfg := PBGameData.config()
	var members: Array[PBUnit] = []
	for member_id: StringName in [&"madara", &"obito", &"itachi", &"sasuke", &"shisui"]:
		members.append(PBUnit.new(cfg.characters.by_id(member_id)))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [members[0], members[1], members[2], members[3], naruto]
	var full: Array[PBUnit] = [members[0], members[1], members[2], members[3], members[4], naruto]
	var id := &"bond_uchiha_clan_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"madara", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	for member_id: StringName in [&"madara", &"obito", &"itachi", &"sasuke", &"shisui"]:
		assert_true((assigned.get(member_id, []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_destined_couple_aura_only_tracks_sage_naruto_and_hinata() -> void:
	var cfg := PBGameData.config()
	var sage := PBUnit.new(cfg.characters.by_id(&"naruto_sage"))
	var hinata := PBUnit.new(cfg.characters.by_id(&"hinata"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [sage, naruto]
	var full: Array[PBUnit] = [sage, hinata, naruto]
	var id := &"bond_destined_couple_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"naruto_sage", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"naruto_sage", []) as Array).has(id))
	assert_true((assigned.get(&"hinata", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_art_duo_aura_only_tracks_sasori_and_deidara() -> void:
	var cfg := PBGameData.config()
	var sasori := PBUnit.new(cfg.characters.by_id(&"sasori"))
	var deidara := PBUnit.new(cfg.characters.by_id(&"deidara"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [sasori, naruto]
	var full: Array[PBUnit] = [sasori, deidara, naruto]
	var id := &"bond_art_duo_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"sasori", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"sasori", []) as Array).has(id))
	assert_true((assigned.get(&"deidara", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))


func test_peace_wish_aura_only_tracks_tendo_and_sage_naruto() -> void:
	var cfg := PBGameData.config()
	var tendo := PBUnit.new(cfg.characters.by_id(&"tendo"))
	var sage := PBUnit.new(cfg.characters.by_id(&"naruto_sage"))
	var naruto := PBUnit.new(cfg.characters.by_id(&"naruto"))
	var partial: Array[PBUnit] = [tendo, naruto]
	var full: Array[PBUnit] = [tendo, sage, naruto]
	var id := &"bond_peace_wish_aura"
	var skin := PBBuffGlow.skin_for(id)
	assert_not_null(skin)
	if skin == null:
		return
	assert_eq(skin.back_frames.size(), 6)
	var partial_auras := PBBondAuraArt.active_member_auras(partial, full, cfg.bonds)
	assert_false((partial_auras.get(&"tendo", []) as Array).has(id))
	var assigned := PBBondAuraArt.active_member_auras(full, full, cfg.bonds)
	assert_true((assigned.get(&"tendo", []) as Array).has(id))
	assert_true((assigned.get(&"naruto_sage", []) as Array).has(id))
	assert_false((assigned.get(&"naruto", []) as Array).has(id))
