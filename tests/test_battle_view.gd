extends GutTest
## [PBBattleView] 的冒烟测试。M0-b。
##
## 这一层不测数值 —— 数值归 `src/core/` 的那几个测试文件管，
## 渲染层重复测一遍只会让两处一起腐化。
##
## 这里只测**接线对不对**：场景能起、逻辑在推进、倍速不改结果、
## 以及最要紧的那条 —— 渲染层不许回写 sim 的状态。

const BATTLE_SCENE := "res://scenes/battle.tscn"

## 固定种子，让每条用例都跑同一局。0 会走系统时间，那样测试不可复现。
const FIXED_SEED: int = 20260827


## [param auto] 决定开局是自动推进还是停在准备阶段等玩家。
##
## **这里默认 true，而画面本身的默认是 false**（M3-e 改的：开局第一眼
## 该看到准备阶段，不是一场自己打起来的第一波）。这个文件里多数用例
## 要的是「已经在打的那一局」，每条各写一行开自动纯属噪声。
## 画面的默认值由 `test_auto_play_advances_without_any_input` 单独守着。
func _spawn_battle(seed_value: int = FIXED_SEED, auto: bool = true) -> Node2D:
	var scene: PackedScene = load(BATTLE_SCENE)
	var root: Node2D = scene.instantiate()
	root.run_seed = seed_value
	root.auto_play = auto
	add_child_autofree(root)
	return root


func test_battle_scene_loads() -> void:
	assert_not_null(load(BATTLE_SCENE), "battle.tscn 应该能被加载")


func test_the_running_game_uses_the_real_character_table() -> void:
	# **这条守的是一个静默失效**：`PBSimConfig.new()` 默认装的是给对拍用的
	# 合成卡池（4×6×2 的假牌）。游戏入口忘了调 PBCharacterLoader.config()
	# 不会报任何错，只表现为「玩到的和扫描结论对不上」。
	#
	# 两张表大小不同（30 vs 48），拿这个当指纹。
	var root := _spawn_battle()
	var cfg: PBSimConfig = root.get("_cfg")
	assert_not_null(cfg, "战斗画面应该有一份配置")
	assert_eq(
		cfg.characters.size(), PBCharacterLoader.table().size(), "主场景应该装的是 data/ 里的真角色表，不是合成表"
	)
	for character: PBCharacter in cfg.characters.all():
		assert_false(String(character.id).begins_with("syn_"), "混进了合成表的卡：%s" % character.id)


func test_scene_has_the_nodes_the_script_expects() -> void:
	# @onready 取不到节点会在 _ready 里炸，而 .tscn 是手写的、
	# 节点名很容易和脚本对不上。这条把两边钉在一起。
	var root := _spawn_battle()
	for path: String in ["Enemies", "Deployed", "Base", "HUD/Info"]:
		assert_not_null(root.get_node_or_null(path), "场景里应该有 %s 节点" % path)


func test_logic_advances_over_physics_frames() -> void:
	# 定帧 20 tick/s，物理帧 60Hz，所以每 3 个物理帧推进 1 个 tick。
	var root := _spawn_battle()
	await wait_physics_frames(30)
	var enemies_seen: int = 0
	for child: Node in root.get_node("Enemies").get_children():
		if (child as Polygon2D).visible:
			enemies_seen += 1
	assert_gt(enemies_seen, 0, "跑了 30 个物理帧之后场上应该有敌人出场了")


func test_enemy_pool_is_preallocated_and_never_grows() -> void:
	# §14 要求战斗中零新建节点。池子在 _ready 一次建满，之后只改 visible。
	#
	# 每个槽位是两层：本体 + 克制亮边（§02 的第三层视觉编码），
	# 所以节点数是 COUNT_CAP 的两倍。**「永不增长」才是这条测试的真意** ——
	# 战斗中冒出新节点就说明有人在热路径上 .new() 了。
	var root := _spawn_battle()
	var pool := root.get_node("Enemies")
	var count_at_start: int = pool.get_child_count()
	assert_eq(count_at_start, PBSimConfig.new().count_cap * 2, "池子应按 COUNT_CAP 建满两层")
	await wait_physics_frames(60)
	assert_eq(pool.get_child_count(), count_at_start, "战斗中不该新建任何敌人节点")


func test_deployed_slots_are_preallocated_too() -> void:
	# 头像格也走预分配那条规矩：按上限一次建满，之后只改内容（§14）。
	#
	# **三排头像先后搬走了**：仓库那一排去了常驻的 [PBRosterBay]（M5-3），
	# 出任务那一排去了任务栏 [PBQuestCard]（M5-6）。[PBFieldSlots]
	# 现在一个忍者格都不剩 —— 它只管尾兽和大本营那两个形象。
	var root := _spawn_battle()
	var slots := (root.get_node("HUD/Quest") as PBQuestCard).find_children(
		"", "PBUnitTile", true, false
	)
	assert_eq(slots.size(), PBQuestCard.SLOT_COUNT, "任务栏按 SSS 任务的 4 人建满")
	assert_eq(
		(root.get_node("HUD/Slots") as PBFieldSlots).find_children("", "PBUnitTile", true, false),
		[],
		"C/D 那两个形象上不该再挂忍者格"
	)
	var bay := (root.get_node("HUD/Stash") as PBRosterBay).find_children(
		"", "PBUnitTile", true, false
	)
	assert_eq(bay.size(), PBRosterBay.CAP, "仓库按卡池上限一次建满，滚动只是挪位置")


func test_pause_stops_the_logic() -> void:
	# 暂停要真的停住 tick。§02 要求暂停状态下仍能下大招，
	# 前提是暂停只冻结推进、不冻结交互。
	var root := _spawn_battle()
	await wait_physics_frames(20)
	root._paused = true
	var tick_at_pause: int = root._battle.current_tick()
	await wait_physics_frames(30)
	assert_eq(root._battle.current_tick(), tick_at_pause, "暂停期间 tick 不该推进")


func test_speed_multiplier_only_changes_how_many_ticks_per_frame() -> void:
	# §14 的铁律：倍速绝不引入数值差异。它只改「每次触发步进几个 tick」，
	# tick 本身的时长不变，所以 3 倍速跑出来的 tick 序列和 1 倍速逐 tick 相同，
	# 只是走得快。这里验的是「3 倍速确实快约 3 倍」。
	var slow := _spawn_battle()
	var fast := _spawn_battle()
	fast._speed = 3
	await wait_physics_frames(30)
	assert_gt(fast._battle.current_tick(), slow._battle.current_tick(), "3 倍速应该推进得更快")


func test_view_never_writes_back_to_sim_state() -> void:
	# **本文件最要紧的一条。** 渲染层只读 sim，改状态只能走 PBRunSim 的
	# begin_wave / lock_plan / settle_wave —— 那是批量模拟走的同一条路。
	# 渲染层偷偷改一笔，画面和批量结论就会分叉，而且不报任何错。
	var root := _spawn_battle()
	# 先让准备阶段过去：M1 起「花钱」发生在 _ready 之后的第一个物理帧
	# （§01 的准备阶段是显式的一段），在那之前取快照会把合法的花钱当成回写。
	await wait_physics_frames(3)
	var gold_before: int = root._state.gold
	var wave_before: int = root._state.wave_index
	var hp_before: float = root._state.base_hp
	# **暂停之后再等**（M4-d）：一次全刷之后单波短得多，四十几帧足够打完一波，
	# 于是「金币变了」量到的是正常结算而不是回写。暂停期间 `_sync_visuals`
	# 照样每帧跑 —— 而那正是这条要盯的东西。
	root._paused = true
	await wait_physics_frames(45)
	assert_eq(root._state.gold, gold_before, "一波没打完，金币不该变")
	assert_eq(root._state.wave_index, wave_before, "一波没打完，波次不该变")
	assert_eq(root._state.base_hp, hp_before, "没漏怪时基地血不该变")


func test_wave_preview_has_no_side_effects() -> void:
	# **§04 要求波型提前公示，这条守着它的实现前提。**
	#
	# 波次生成必须是 (种子, 波次) 的纯函数。要是从顺序流里掷，
	# 「预告了下一波」就会改变后续所有随机数的次序 ——
	# 于是玩家看不看预告会影响后面抽到什么卡。那显然不行。
	var cfg := PBSimConfig.new()
	var rng := PBRngStreams.new(999)
	var first := PBRunSim.preview_wave(7, cfg, rng)
	# 中间预告一堆别的波次，然后再看第 7 波
	for i: int in range(1, 20):
		PBRunSim.preview_wave(i, cfg, rng)
	var again := PBRunSim.preview_wave(7, cfg, rng)
	assert_eq(first.element, again.element, "反复预告不该改变第 7 波的属性")
	assert_eq(first.shape, again.shape, "反复预告不该改变第 7 波的波型")
	assert_eq(first.count, again.count, "反复预告不该改变第 7 波的数量")


func test_coverage_counts_what_the_roster_can_counter() -> void:
	# §03：「当前阵容对下一波的克制覆盖：2/5，风系空缺」
	var cfg := PBSimConfig.new()
	var state := PBRunState.new()
	assert_eq(state.missing_counters().size(), 5, "空卡池应该五系全缺")

	# 火克风，所以持有火系就能覆盖「风」那一波。
	state.add_unit(PBUnit.of(cfg, PBElement.Type.FIRE, PBUnit.Rarity.R))
	assert_eq(state.missing_counters().size(), 4, "有火系之后应该只缺四系")
	assert_true(state.can_counter(PBElement.Type.WIND), "火克风")
	assert_false(state.can_counter(PBElement.Type.FIRE), "火不克火")

	for element: int in PBElement.RING:
		state.add_unit(PBUnit.of(cfg, element as PBElement.Type, PBUnit.Rarity.R))
	assert_eq(state.missing_counters().size(), 0, "五系齐了应该零空缺")


func test_physical_units_never_count_as_coverage() -> void:
	# 物理不参与克制环（§03），堆再多也覆盖不了任何一系。
	# 这正是「纯物理阵容极限波次 < 五系的 70%」那条验收的由来。
	var cfg := PBSimConfig.new()
	var state := PBRunState.new()
	for variant: int in 2:
		for rarity: int in 4:
			state.add_unit(
				PBUnit.of(cfg, PBElement.Type.PHYSICAL, rarity as PBUnit.Rarity, variant)
			)
	assert_eq(state.missing_counters().size(), 5, "纯物理卡池应该五系全缺")


func test_same_seed_reproduces_the_same_wave() -> void:
	# §12 的确定性延伸到画面：同种子的两局，第一波必须一模一样。
	var a := _spawn_battle(4242)
	var b := _spawn_battle(4242)
	assert_eq(a._plan.wave.index, b._plan.wave.index, "同种子的波次序号应一致")
	assert_eq(a._plan.wave.element, b._plan.wave.element, "同种子的敌方属性应一致")
	assert_eq(a._plan.wave.count, b._plan.wave.count, "同种子的敌人数量应一致")
	assert_eq(a._plan.wave.shape, b._plan.wave.shape, "同种子的波型应一致")


func test_preparation_is_its_own_phase_and_waits_for_the_player() -> void:
	# **M1-a 的核心。** §01 说准备阶段不限时，所以它必须是一个会**停下来**的
	# 状态，而不是像 M0 那样在一帧里被 plan_wave 做完。
	#
	# 关掉自动推进之后，画面应当停在准备阶段：波次已生成（有东西可看），
	# 但战斗还没开始（没有敌人在动），而且怎么等都不会自己开打。
	var root := _spawn_battle()
	root.auto_play = false
	root._enter_prepare()
	assert_eq(root._phase, PBBattleView.Phase.PREPARE, "关掉自动后应停在准备阶段")
	assert_not_null(root._plan.wave, "准备阶段就该知道这一波长什么样（§04 要求提前公示）")
	await wait_physics_frames(30)
	assert_eq(root._phase, PBBattleView.Phase.PREPARE, "不限时意味着等多久都不会自己开打")

	# 手动模式下不花钱就没有卡、DPS 为零 —— 这是诚实的后果，
	# 开局金币（§07 的 starting_gold）存在的理由就是让第一波买得起人。
	assert_eq(root._state.roster.size(), 0, "手动模式下不该有人替玩家花钱")
	# M3.5-f 起抽卡是**两步**（§08 的三选一）：先摆三张，再挑一张。
	# 摆完就直接进仓库的话，「挑哪张」这个决策又被界面替玩家做掉了。
	root._on_command(&"gacha")
	assert_eq(root._state.pending_offer.size(), 3, "点抽卡应该摆出三张候选")
	assert_eq(root._state.roster.size(), 0, "还没挑，仓库里不该有人")
	root._on_offer_picked(0)
	assert_eq(root._state.roster.size(), 1, "挑完那一张才进仓库")

	root._finish_prepare()
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "锁定名单后应进入战斗")
	assert_gt(root._plan.dps, 0.0, "锁定之后才有有效 DPS")


func test_auto_play_advances_without_any_input() -> void:
	# §01 点名要自动推进（「PC：开自动推进，一次坐 30~60 分钟」）。
	# 它同时是 M1 的回归工具：开着的时候决策序列与批量模拟完全一致。
	#
	# **画面的默认是关的**（M3-e 改的）：开局第一眼该看到准备阶段，
	# 而不是一场自己打起来的第一波。所以先验默认值，再显式打开验行为。
	var fresh: Node2D = (load(BATTLE_SCENE) as PackedScene).instantiate()
	assert_false(fresh.auto_play, "默认应停在准备阶段等玩家（M3-e）")
	fresh.free()

	var root := _spawn_battle()
	await wait_physics_frames(10)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "自动模式下不该停在准备阶段")


func test_the_shop_spends_through_the_shared_primitives() -> void:
	# **界面绝不自己扣钱。** 钱要走 PBStrategy 的原语 —— 那是批量模拟走的
	# 同一批函数，里面还维护着 §08 的保底计数等状态。
	# 界面自己扣的话不报错，只表现为「玩到的和扫描结论对不上」。
	var root := _spawn_battle()
	root.auto_play = false
	root._enter_prepare()
	var cfg := PBSimConfig.new()
	# 这条测的是接线，不是预算。开局金币只够 3 抽（§07 有意如此），
	# 不给够钱的话失败原因会变成「买不起」，掩盖真正要验的东西。
	root._state.gold = 9999

	var gold_before: int = root._state.gold
	root._on_command(&"gacha")
	assert_eq(root._state.gold, gold_before - cfg.gacha_cost, "抽卡应扣掉单抽的钱")
	assert_eq(root._state.gacha_pulls, 1, "抽卡次数要计数 —— 保底靠它")

	root._on_command(&"equip")
	assert_eq(PBEquipRules.part_total(root._state.equip_parts), 1, "买配件应真的进仓库")

	root._on_command(&"tech_atk")
	assert_eq(root._state.tech_atk, 1, "升攻击科技应真的升级")


func test_the_shop_only_reacts_during_preparation() -> void:
	# 战斗中点到按钮不该生效 —— §01 只允许在准备阶段花钱，
	# 而且战斗中改 DPS 会让已经开打的这一波结果和名单对不上。
	var root := _spawn_battle()
	await wait_physics_frames(10)
	assert_eq(root._phase, PBBattleView.Phase.BATTLE, "这时候应该已经在打了")
	var gold_before: int = root._state.gold
	root._on_command(&"gacha")
	assert_eq(root._state.gold, gold_before, "战斗阶段的购买请求应被忽略")


func test_the_shop_labels_carry_the_numbers_a_decision_needs() -> void:
	# §03 说原版最大的短板是信息不透明：克制关系要点开技能说明才看得到。
	# 这一层的存在理由就是把账摆在按钮上，所以按钮文字里必须真的有数。
	var cfg := PBSimConfig.new()
	var state := PBRunSim.new_state(cfg)
	state.add_unit(PBUnit.of(cfg, PBElement.Type.FIRE, PBUnit.Rarity.SR))
	# M3.5-e 起格子上写短的、悬停时提示条上写长的（指令卡的格子放不下整句），
	# 但两截出自同一处（[PBShopLabels]），所以这一条改为直接查那一层。
	for kind: StringName in PBShopLabels.KINDS:
		var short: String = PBShopLabels.short_of(kind, state, cfg)
		var detail: String = PBShopLabels.detail_of(kind, state, cfg)
		var cost: int = PBShopLabels.cost_of(kind, state, cfg)
		assert_ne(short, "", "%s 格子应该有文字" % kind)
		if cost >= 0:
			assert_true(short.contains(str(cost)), "%s 的格子上必须写着它要多少钱：%s" % [kind, short])
			assert_true(detail.contains(str(cost)), "%s 的提示里也要有价格：%s" % [kind, detail])

	# 每一类的「收益」口径不同，各自都得写出来，不能只写价格。
	var gacha_text: String = PBShopLabels.detail_of(&"gacha", state, cfg)
	assert_true(gacha_text.contains("战力"), "抽卡要写期望战力增幅：%s" % gacha_text)
	var gold_text: String = PBShopLabels.detail_of(&"tech_gold", state, cfg)
	assert_true(gold_text.contains("金"), "金币科技的收益是金币不是战力：%s" % gold_text)
	var economy_slot_text: String = PBShopLabels.detail_of(&"economy_slot", state, cfg)
	assert_true(
		economy_slot_text.contains("战力") and economy_slot_text.contains("每波"),
		"经济位必须同时写明战力代价与金币收益 —— 那个取舍就是 §07 本身：%s" % economy_slot_text
	)
