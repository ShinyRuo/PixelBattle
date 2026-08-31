extends GutTest
## `data/equipment/` 的真装备表校验（§10 的三级树）。M3-c2。
##
## 和 `test_equip_rules.gd` 分开：那边测**合成与分配的规则**，
## 这边测**数据本身**。两者的失效模式不同 ——
## 规则写错是「所有配置一起错」，数据写错是「某一件装备悄悄合不出来」。

var _cfg: PBSimConfig
var _table: PBEquipTable


func before_each() -> void:
	_cfg = PBGameData.config()
	_table = _cfg.equipment


func test_the_data_directory_actually_loads() -> void:
	assert_gt(_table.items.size(), 0, "装备目录应该装得出东西来")
	assert_false(_table.is_synthetic(), "装进来的应该是真表，不是那条替身曲线")


func test_every_recipe_costs_exactly_one_item_worth_of_parts() -> void:
	# §10：配件 → 成品需要 3 个。配方长度不等于它的话，
	# 「每 1% 战力多少钱」那张定价表的分母就错了，而定价是经济系统的支点。
	for item: PBEquipItem in _table.items:
		assert_eq(
			item.recipe.size(),
			_cfg.equip_parts_per_item,
			"%s 的配方应该正好要 %d 个配件" % [item.id, _cfg.equip_parts_per_item]
		)


func test_the_spec_still_defines_seven_parts() -> void:
	# §10 明写 7 种配件。全部配方（含当前无效的那两件）加起来应该正好用满。
	var seen: Dictionary = {}
	for item: PBEquipItem in _table.items:
		for part_id: StringName in item.recipe:
			seen[part_id] = true
	assert_eq(seen.size(), PBEquipLoader.SPEC_PARTS, "整份数据里应出现 §10 说的那么多种配件")


func test_the_box_never_sells_a_part_nothing_can_use() -> void:
	# **忍具箱是等概率出货的，所以货架上每混进一种废配件，
	# 期望产出就被稀释一份。** 真树刚接上时七种里有三种只喂 0 收益的配方，
	# 实测足以让会算账的玩家整局买 0 个配件 —— §10 的金币坑当场不成立。
	#
	# 规则因此是「箱子不卖你用不上的东西」，而且是自愈的：
	# 那两件成品的 power 一变正，它们的配件自动回到货架上。
	var live: Dictionary = {}
	for item: PBEquipItem in _table.items:
		if item.power <= 0.0:
			continue
		for part_id: StringName in item.recipe:
			live[part_id] = true
	for part_id: StringName in _table.parts:
		assert_true(live.has(part_id), "配件 %s 喂不到任何有效成品，不该出现在箱子里" % part_id)
	assert_eq(_table.parts.size(), live.size(), "货架上应该正好是那些有用的配件")
	assert_eq(_table.parts.size(), PBEquipLoader.LIVE_PARTS, "当前有效配件种类数")


func test_all_three_categories_exist() -> void:
	# §10 的物理 / 法术 / 坦克三分类。少一类，秘卷箱的「指定分类」就少一个选项。
	var seen: Dictionary = {}
	for item: PBEquipItem in _table.items:
		seen[item.category] = true
	assert_eq(seen.size(), 3, "三个分类都该有成品")


func test_physical_and_magic_items_never_fit_the_same_unit() -> void:
	# 分类匹配是这次改造的实质内容：法术装挂不上物理角色。
	# 这条不成立的话，装备又变回那条「对谁都一样有用」的全队倍率，
	# §03 的属性系统会重新被它稀释。
	for item: PBEquipItem in _table.items:
		if item.category == PBEquipItem.Category.PHYSICAL:
			assert_true(item.fits(PBElement.Type.PHYSICAL), "%s 该挂在物理角色身上" % item.id)
			assert_false(item.fits(PBElement.Type.FIRE), "%s 不该挂在五系角色身上" % item.id)
		elif item.category == PBEquipItem.Category.MAGIC:
			assert_false(item.fits(PBElement.Type.PHYSICAL), "%s 不该挂在物理角色身上" % item.id)
			assert_true(item.fits(PBElement.Type.FIRE), "%s 该挂在五系角色身上" % item.id)


func test_the_defensive_items_are_honestly_worth_zero() -> void:
	# **这条钉的是一个已知的模型缺口，不是一个愿望。**
	#
	# §10 的吸血刀（造成伤害 15% 吸血）和火影风衣（50% 概率格挡 260 伤害）
	# 在当前战斗模型下不产生任何伤害：**敌人不还手，己方单位也不会死**。
	# 数据里照实填 0，不把防御效果折算成伤害 —— 折算了就等于凭空发明一份收益，
	# 而调参的人会拿着那份收益去定价。
	#
	# 等 [PBBattleSim] 有了「敌人还手」，改的是 `.tres` 里的数，这条断言跟着改。
	var zero: int = 0
	for item: PBEquipItem in _table.items:
		if item.power <= 0.0:
			zero += 1
	assert_eq(zero, 2, "当前应恰好有两件成品的战力加成为 0（吸血刀、火影风衣）")


func test_the_dead_recipes_still_cost_the_shelf_three_part_types() -> void:
	# 上一条的另一半：那两件无效成品**确实**独占了几种配件。
	# 它们没有被从数据里删掉（§10 的配方表照原样留着），只是暂时下架。
	#
	# 这条量的是「敌人还手」这个缺口现在有多贵：
	# 补上它，货架从 4 种回到 7 种，忍具箱的定价才能按 §10 原来的口径谈。
	var shelved: int = PBEquipLoader.SPEC_PARTS - _table.parts.size()
	assert_eq(shelved, 3, "当前应有三种配件因为专属成品无效而下架")


func test_no_equipment_name_leaks_into_src() -> void:
	# §14 铁律 5：代码里不出现装备名，一律走 id + name_key。
	var names: Array[String] = ["双刀", "钝刀", "吸血刀", "雷牙", "暗部面具", "火影风衣"]
	for path: String in _gd_files("res://src"):
		var text := FileAccess.get_file_as_string(path)
		for name: String in names:
			assert_false(text.contains(name), "%s 里出现了装备名「%s」" % [path, name])


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		out.append_array(_gd_files("%s/%s" % [root, sub]))
	for file_name: String in dir.get_files():
		if file_name.ends_with(".gd"):
			out.append("%s/%s" % [root, file_name])
	return out
