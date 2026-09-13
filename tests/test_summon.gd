extends GutTest
## 召唤物（M12-c3）。

## ## 这个文件守的是什么
##
## 召唤物是 M12 里第一个动战斗结构的东西：它让己方那个数组第一次装着
## **不是卡的人**。四条：
##
## 1. **没有召唤技能的队伍一个位子也不留** —— 全部既有配平数字一位不动
## 2. **位子是开波预留的**，跑动中不变长（`_orders` 铺一次、渲染池建一次）
## 3. **`slot` 从此不保证对应一张卡** —— 三处反查的地方都得受得住
## 4. **召唤物没了不算折了一个**（玩家定的）

var _cfg: PBSimConfig
var _rng: RandomNumberGenerator


func before_each() -> void:
	# **拿一份自己的配置和自己的技能表。**
	# [method PBGameData.config] 返回的是**共享的那一份**，
	# 往它的技能表里塞探针技能会漏进别的测试文件 ——
	# 而那不报错，只会让某一条在单跑时绿、合跑时红。
	_cfg = PBGameData.config().clone()
	_cfg.skills = PBSkillTable.new()
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260912


# ── 空着 = 一字不差 ──────────────────────────────────────────


func test_a_team_without_summoners_reserves_nothing_at_all() -> void:
	# **这是它敢在数值回归之前落地的全部理由**，同 M3.5-f 装备那条。
	# 留一个空位也会让 `_orders` 多铺一格、渲染池多建一个节点，
	# 而那两样都是按人数一次铺好的。
	assert_eq(PBSummonRules.reserve([] as Array[PBUnit], _cfg), 0, "空队伍不留")
	var plain := _units([_plain()])
	assert_eq(PBSummonRules.reserve(plain, _cfg), 0, "不会召唤的人也不留")
	assert_eq(_build(plain).size(), 1, "出战席多大，数组就多大")


func test_the_table_really_carries_summon_skills() -> void:
	# 分母先量准：真表里一个召唤技能都没有的话，下面几条全是空转。
	var table := PBSkillLoader.table()
	var found: int = 0
	for id: StringName in table.ids():
		if table.by_id(id).summon_count > 0:
			found += 1
	assert_gt(found, 0, "技能表里该有召唤技能")


# ── 位子是开波留的 ────────────────────────────────────────────


func test_the_slots_are_reserved_up_front_and_start_empty() -> void:
	var squad := _units([_summoner(3)])
	var built := _build(squad)
	assert_eq(built.size(), 4, "一张卡 + 三个预留位")
	assert_false(built[1].alive, "预留位开波是空着的")
	assert_true(built[1].summoned, "它是给召唤物留的，不是一张卡")
	assert_eq(built[1].expires_at, PBSummonRules.GONE, "空着就是 GONE")


func test_the_reserved_slots_keep_counting_up_from_the_cards() -> void:
	# `slot` 仍然等于数组下标 —— 三处拿它反查卡的地方靠
	# 「下标 >= 卡数就跳过」活着（尾兽那条 `slot = -1` 先示范过同一件事）。
	var built := _build(_units([_summoner(2), _plain()]))
	for i: int in built.size():
		assert_eq(built[i].slot, i, "第 %d 个的 slot 该等于下标" % i)


func test_two_summoners_each_get_their_own_slots() -> void:
	# 拍一个上限的话，第二个人放技能时会凭空少几个位子，**而它不报错** ——
	# 表现是「有时候只召出来一半」。
	assert_eq(PBSummonRules.reserve(_units([_summoner(3), _summoner(2)]), _cfg), 5, "各留各的")


# ── 召出来、散回去 ────────────────────────────────────────────


func test_casting_stands_them_up_next_to_the_caster() -> void:
	var built := _build(_units([_summoner(2)]))
	var caster: PBAttacker = built[0]
	caster.revive()
	var made := PBSummonRules.raise_from(built, caster, _summon_skill(2), 100, _cfg)
	assert_eq(made, 2, "该召出两个")
	assert_true(built[1].alive and built[2].alive, "两个都该站着")
	assert_eq(built[1].pos, caster.pos, "站在本体身边")
	assert_almost_eq(built[1].dps, caster.dps * 0.5, 0.001, "输出是本体的一半")
	assert_almost_eq(built[1].max_hp, caster.max_hp * 0.25, 0.001, "血是本体的四分之一")


func test_they_borrow_the_casters_reach_not_a_separate_one() -> void:
	# 原版：「乌鸦射程与自身一样」。另配一套的话召唤物会在「够不够得着」
	# 上和本体分叉，而那表现为「召出来的东西站着不动」。
	var built := _build(_units([_summoner(1)]))
	var caster: PBAttacker = built[0]
	caster.revive()
	PBSummonRules.raise_from(built, caster, _summon_skill(1), 0, _cfg)
	assert_eq(built[1].reach, caster.reach, "射程抄本体")
	assert_eq(built[1].def_element, caster.def_element, "护甲属性也抄")


func test_they_go_away_when_their_time_is_up() -> void:
	var built := _build(_units([_summoner(1)]))
	built[0].revive()
	PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg)
	var until: int = built[1].expires_at
	assert_eq(PBSummonRules.expire(built, until - 1), 0, "没到点不散")
	assert_true(built[1].alive, "还站着")
	assert_eq(PBSummonRules.expire(built, until), 1, "到点就散")
	assert_false(built[1].alive, "散了")
	assert_eq(built[1].expires_at, PBSummonRules.GONE, "位子空回来了")


func test_a_freed_slot_can_be_used_again() -> void:
	# 散场排在技能落地之前，所以本体可以在同一 tick 再召一批。
	var built := _build(_units([_summoner(1)]))
	built[0].revive()
	PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg)
	PBSummonRules.expire(built, built[1].expires_at)
	assert_eq(PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg), 1, "位子能重用")


func test_a_full_bench_just_summons_fewer_instead_of_crashing() -> void:
	var built := _build(_units([_summoner(1)]))
	built[0].revive()
	PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg)
	assert_eq(PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg), 0, "位子满了就少召")


func test_a_new_wave_wipes_them_off_the_field() -> void:
	# 攻击者对象跨波复用。不清的话上一波召出来的东西会满血站在下一波的开场，
	# **而本体这一波一次技能都还没放** —— 同「上一场的残血漏进这一场」。
	var built := _build(_units([_summoner(1)]))
	built[0].revive()
	PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg)
	var sim := PBBattleSim.new(_wave(), 0.0, 0.0, _cfg, built)
	assert_false(built[1].alive, "开波该是空着的")
	assert_eq(built[1].expires_at, PBSummonRules.GONE, "位子也该空回来")
	assert_not_null(sim, "这一局建得起来")


# ── 没了不算折了一个 ──────────────────────────────────────────


func test_a_summon_going_down_is_not_a_ninja_lost() -> void:
	# 玩家定的：`allies_lost` 是他要心疼的那个数，而影分身本来就是拿来炸的。
	var built := _build(_units([_summoner(1)]))
	built[0].revive()
	PBSummonRules.raise_from(built, built[0], _summon_skill(1), 0, _cfg)
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(
		built[1], null, built[1].max_hp * 100.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_false(built[1].alive, "这一下该把它打没")
	assert_eq(out.allies_lost, 0, "召唤物没了不记账")


func test_a_real_ninja_going_down_still_counts() -> void:
	# 上面那条的对照。两条一起才说明「不记」是认人不是关掉了。
	var built := _build(_units([_plain()]))
	built[0].revive()
	var out := PBCombatOutcome.new()
	PBStrikeRules.hurt_ally(
		built[0], null, built[0].max_hp * 100.0, PBElement.Type.PHYSICAL, _cfg, 0, null, null, out
	)
	assert_eq(out.allies_lost, 1, "真忍者倒下要记")


func _wave() -> PBWave:
	return PBWaveRules.build(3, _cfg, _rng)


func _plain() -> PBCharacter:
	var one := PBCharacter.new()
	one.id = &"probe_plain"
	return one


## 一个带着召唤技能的角色。技能装进 `cfg.skills`，因为
## [method PBSummonRules.reserve] 是按 id 去那张表里查的。
func _summoner(count: int) -> PBCharacter:
	var one := PBCharacter.new()
	# **召几个就是一份不同的技能。** 共用一个 id 的话，
	# 两个召唤师会拿到先注册的那一份，“各留各的”那条就量不准。
	one.id = StringName("probe_summoner_%d" % count)
	one.skill_ids = [_probe_id(count)] as Array[StringName]
	if not _cfg.skills.has(_probe_id(count)):
		_cfg.skills.add(_summon_skill(count))
	return one


## 探针技能的 id，按“召几个”分开。
func _probe_id(count: int) -> StringName:
	return StringName("probe_summon_%d" % count)


func _summon_skill(count: int) -> PBSkill:
	var skill := PBSkill.new()
	skill.id = _probe_id(count)
	skill.target = PBSkill.Target.NONE
	skill.affects = PBSkill.Party.ALLIES
	skill.summon_count = count
	skill.summon_power = 0.5
	skill.summon_hp_share = 0.25
	skill.summon_seconds = 5.0
	return skill


func _units(characters: Array) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for character: PBCharacter in characters:
		out.append(PBUnit.new(character))
	return out


func _build(units: Array[PBUnit]) -> Array[PBAttacker]:
	return PBCombatRules.build_attackers(
		units, PBElement.Type.PHYSICAL, 1.0, PackedFloat64Array(), _cfg
	)
