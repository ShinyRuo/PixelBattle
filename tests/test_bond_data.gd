extends GutTest
## `data/bonds/*.tres` 这张**真羁绊表**本身的测试。M2-b2。
##
## 和 `test_bond.gd` 的分工：那边测**机制**（档位怎么查、多组怎么叠、
## 成员怎么判），用现造的表；这边测 `data/` 里那 11 份**内容**。
## 两者失效方式完全不同 —— 机制坏了会崩，内容写歪了只会让数值悄悄偏掉。
##
## ## 这里守的失效全都是「不报错」的那一类
##
## 羁绊数据有一种特别恶劣的错法：**成员 id 打错一个字母**。
## 那组羁绊会永远凑不满，玩家和策划都只会觉得「这组好像没什么用」，
## 没有任何报错、没有任何崩溃，而扫描结论会照着一个残废的羁绊表得出。
## 角色表里不存在这种错（id 就是它自己），所以这条只能在羁绊这一层拦。

var _bonds: PBBondTable
var _characters: PBCharacterTable
var _cfg: PBSimConfig


func before_all() -> void:
	_bonds = PBBondLoader.load_from(PBBondLoader.DIR)
	_characters = PBCharacterLoader.table()
	_cfg = PBGameData.config()


func _named() -> Array[PBBond]:
	var out: Array[PBBond] = []
	for bond: PBBond in _bonds.all():
		if bond.match_mode == PBBond.Match.MEMBERS:
			out.append(bond)
	return out


func test_the_data_directory_actually_loads() -> void:
	assert_gt(_bonds.size(), 0, "data/bonds/ 里应该装得出羁绊")
	# **拿表和目录对，不写死一个数**（M12-d2）。写死的本意是「表是照抄的，
	# 少一组就是漏抄了一行」—— 而它守不住那件事：漏抄一行的时候两边**一起**少，
	# 只有「有人手改了 `data/bonds/`」才对不上，而那正是这条该拦的。
	# 写死还有个副作用：加一组新羁绊（内容变多）会让它变红。
	var rows: int = 0
	for line: String in FileAccess.get_file_as_string("res://data/bonds.tsv").split("\n"):
		if line.strip_edges() != "" and not line.begins_with("#"):
			rows += 1
	assert_gt(rows, 0, "读得到 data/bonds.tsv")
	assert_eq(_named().size(), rows, "目录里的组数该和表里的行数一样")
	assert_eq(_bonds.size(), _named().size(), "M10-b 起没有兜底羁绊，每一组都是点名的")


func test_every_named_member_actually_exists() -> void:
	# **本文件最要紧的一条。** 成员 id 打错一个字母，那组羁绊永远凑不满，
	# 而且不报任何错 —— 只表现为「这组好像没什么用」。
	var missing := PackedStringArray()
	for bond: PBBond in _named():
		for member_id: StringName in bond.member_ids:
			if _characters.by_id(member_id) == null:
				missing.append("%s→%s" % [bond.id, member_id])
	assert_eq(String(", ").join(missing), "", "这些羁绊成员在角色表里不存在，那组羁绊永远凑不满")


func test_every_named_bond_can_actually_be_completed() -> void:
	# 成员都存在还不够：满档人数不能超过成员总数，否则最高档够不着。
	# §09 的硬性规范是「最高档必须解锁一个机制」，一个够不着的档等于没有。
	for bond: PBBond in _named():
		assert_gte(
			bond.member_ids.size(),
			bond.full_tier_count(),
			"%s 满档要 %d 人但只有 %d 个成员" % [bond.id, bond.full_tier_count(), bond.member_ids.size()]
		)


func test_no_bond_is_out_of_reach_of_the_field() -> void:
	# **羁绊只算在场的人**（`PBRunState.bonded_units` → `field_units`），
	# 而在场上限是 [member PBSimConfig.deploy_slots_max]。满档人数超过它的
	# 那一组**结构上永远凑不齐** —— 而它不报错：表装得进来、界面照样列它，
	# 现象只是「这一组我怎么凑不出来」。
	#
	# 原版的「木叶十二小强」正是 12 人，原版能要 12 是因为**待命台也算羁绊**，
	# 而待命台 M3.5-i 已经删了（玩家复核过不恢复）。所以 `data/bonds.tsv`
	# 里那一组的满档写的是 10，不是 12。
	for bond: PBBond in _bonds.all():
		assert_lte(
			bond.full_tier_count(),
			_cfg.deploy_slots_max,
			"%s 满档要 %d 人，而在场最多 %d 个" % [bond.id, bond.full_tier_count(), _cfg.deploy_slots_max]
		)


func test_every_bond_is_all_or_nothing() -> void:
	# **M6-j 起每组羁绊只有一档：不凑齐就是不生效**（玩家定的，见 [PBBond]）。
	#
	# 这条测试原来叫 `test_the_top_tier_is_a_real_jump`，断的是
	# 「满档那一跳是这组里最大的一跳」—— 那在分档的时候是对的：
	# M2 只有数值一种货币，最高档那一跳是 §09「解锁一个机制」的替身。
	# 不分档之后那句话没有内容了（只有一跳，当然是最大的），
	# 而**要守的东西换了一个**：数据里不许再出现第二档。
	#
	# 留着旧断言的话它会一直绿着却什么都不测；删掉的话，
	# 哪天有人往 `.tres` 里加回一档，界面上「凑齐才生效」那句话就成了谎话。
	for bond: PBBond in _cfg.bonds.all():
		assert_eq(
			bond.tier_counts.size(), 1, "%s 该只有一档 —— 不凑齐就是不生效" % bond.id
		)
		assert_eq(bond.tier_power.size(), 1, "%s 的加成表要和档位表等长" % bond.id)
		assert_gt(bond.tier_power[0], 0.0, "%s 凑齐了却一分钱都不给" % bond.id)


func test_the_reachable_ceiling_stays_in_a_sane_band() -> void:
	# **配平护栏。** 旧替身曲线最多给 1.72×（每人 6%、封顶 12 人）。
	# 真羁绊表把它换掉之后，上限往上走是**预期内的**（那正是要给玩家的
	# 乘法级杠杆），但不能走到让 GROWTH 1.10 的锚点、装备 300 的定价、
	# 经济位曲线一起失效 —— 那三样是 M-1 和 M1 两轮扫描的产出。
	#
	# ## 量的必须是「够得着的」上限
	#
	# 把 11 组的满档加成直接相加会得到 2.50，但那需要同时凑齐 16 个命名成员
	# **加**每系 4 人 = 24 人在场，而在场上限是 出战 10 + 待命 6 = 16。
	# **那个数根本够不着**，拿它当护栏量的是个不存在的局面。
	#
	# ## 够得着的上限由**在场席位**卡着，不是由羁绊组数卡着
	#
	# M10-b 之前是「五组命名羁绊的成员合起来正好 16 人」——那个 16 是
	# 「出战 10 + 待命 6」，而待命台 M3.5-i 就删了，这句话早就不成立了，
	# 只是当时的 5 组恰好凑出 16 张卡，断言一直绿着。
	#
	# 现在 23 组的成员合起来 40 多人，而**在场只有 10 个位置** ——
	# 所以护栏要量的是「10 个位置最多能同时激活几组」。下面这一队是
	# 手挑的一个高重叠局面（咒印那三组两两共享成员，鹰小队再蹭一个），
	# 7 个人吃到 5 组。**手挑不是取巧**：真正的最优要在 49 选 10 里搜，
	# 而护栏要的是一个够得着、可复现、看得懂的下界。
	var state := PBRunSim.new_state(_cfg)
	state.tech_pop = _cfg.tech_pop_max
	var squad: Array[StringName] = _squad()
	for member_id: StringName in squad:
		var character := _characters.by_id(member_id)
		assert_not_null(character, "护栏用的这一队里有个人不在名册上：%s" % member_id)
		state.add_unit(PBUnit.new(character))
	assert_lte(squad.size(), _cfg.deploy_slots_max, "这一队得真的站得下")

	var best: float = state.bond_mult(_cfg)
	assert_gt(best, 1.0, "这一队该激活好几组羁绊，一组都没激活说明夹具挑错了人")
	var old_ceiling: float = 1.0 + _cfg.bond_power_per_unit * float(_cfg.bond_unit_cap)
	assert_gt(best, old_ceiling, "凑满五组还不如旧替身曲线的话，羁绊就白做了")
	assert_lt(best, old_ceiling * 2.0, "够得着的上限 %.2f× 相对旧的 %.2f× 涨得太狠" % [best, old_ceiling])


func test_the_gacha_valuation_stays_in_the_same_currency_as_the_real_bonds() -> void:
	# **这条守的是 M2-b2 踩过的一个量纲错误。**
	#
	# `gacha_gain` 里的羁绊项原本写成「替身曲线(n+1) ÷ 真羁绊(n)」，
	# 分子分母来自两个不同口径，算出「再抽一张涨 32% 战力」，
	# 于是会算账的玩家把钱全砸进抽卡 —— `rational` 从 44.4 波掉到 26.3 波。
	#
	# 判据：一张卡最多补上某一组羁绊的一档，量级在个位数百分比。
	# 大到两位数就说明分子分母又不是同一种货币了。
	var state := PBRunSim.new_state(_cfg)
	for bond: PBBond in _named().slice(0, 2):
		for member_id: StringName in bond.member_ids:
			state.add_unit(PBUnit.new(_characters.by_id(member_id)))

	var gain: float = PBValuation.expected_bond_gain(state, _cfg)
	assert_gte(gain, 0.0, "羁绊增益不该是负的")
	assert_lt(gain, 0.15, "再抽一张的羁绊增益 %.3f 大得不像一档，检查分子分母是不是同一个口径" % gain)


func test_a_full_roster_stops_valuing_bonds_from_new_cards() -> void:
	# 在场席位满了，新卡上不了场，对羁绊就没有贡献。
	# 这是刻意的**低估**（见 [method PBValuation.expected_bond_gain]）——
	# M2-c 开放选人之后要换成「挤掉谁」。
	var state := PBRunSim.new_state(_cfg)
	for character: PBCharacter in _characters.all():
		state.add_unit(PBUnit.new(character))
	assert_gt(state.roster.size(), state.open_slots(_cfg), "这批卡应该多到坐不下")
	assert_eq(PBValuation.expected_bond_gain(state, _cfg), 0.0, "坐不下的时候新卡不该再算羁绊收益")


func test_the_running_game_installs_the_real_bond_table() -> void:
	# 装载器忘了装表的话，羁绊会静默退回合成表 —— 那是给对拍用的替身曲线。
	assert_eq(_cfg.bonds.size(), _bonds.size(), "配置里装的应该是 data/ 里的真羁绊表")
	assert_null(_cfg.bonds.by_id(PBBondTable.SYNTHETIC_ID), "真表里不该有合成羁绊")


func test_no_bond_id_leaks_into_src() -> void:
	# §14 铁律 5 的执行，和角色 id 同理：换皮 = 改表，`src/` 一行不动。
	var offenders := PackedStringArray()
	for bond: PBBond in _bonds.all():
		if _scan_dir("res://src", String(bond.id)):
			offenders.append(String(bond.id))
	assert_eq(String(", ").join(offenders), "", "这些羁绊 id 出现在了 src/ 里")


## 一个够得着的高重叠阵容：按满档人数从小到大收羁绊，站得下就收。
##
## **不写死名字**：写死的话这个夹具会在名册改名的那天红，而红的是夹具
## 不是护栏。
##
## ## 贪的是「重叠」不是「人少」
##
## 第一版按满档人数从小到大收，结果收进来的是五组**互不相干**的两人组
## （10 个位置摊在 5 组上），只有 1.70× —— 比旧替身曲线的 1.72× 还低。
## 那不是「羁绊白做了」，是这个夹具挑了一个最稀疏的局面。
##
## 每一轮改成挑**新增人数最少**的那一组，重叠就被优先吃掉：
## 咒印那三组两两共享成员，鹰小队再蹭一个，7 个人能吃到 5 组。
## 平局按 id 排，不然结果会随字典遍历顺序漂。
func _squad() -> Array[StringName]:
	var left: Array[PBBond] = _named()
	var picked: Dictionary = {}
	while true:
		var best: PBBond = null
		var best_cost: int = 999
		for bond: PBBond in left:
			var cost: int = _newcomers(bond, picked)
			if picked.size() + cost > _cfg.deploy_slots_max:
				continue
			if cost < best_cost or (cost == best_cost and String(bond.id) < String(best.id)):
				best = bond
				best_cost = cost
		if best == null:
			break
		for member_id: StringName in best.member_ids:
			picked[member_id] = true
		left.erase(best)
	var out: Array[StringName] = []
	out.assign(picked.keys())
	return out


## 收下这一组还要再添几个人。
func _newcomers(bond: PBBond, picked: Dictionary) -> int:
	var count: int = 0
	for member_id: StringName in bond.member_ids:
		if not picked.has(member_id):
			count += 1
	return count


func _scan_dir(dir_path: String, needle: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	for sub: String in dir.get_directories():
		if _scan_dir("%s/%s" % [dir_path, sub], needle):
			return true
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var file := FileAccess.open("%s/%s" % [dir_path, file_name], FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		if text.contains(needle):
			return true
	return false
