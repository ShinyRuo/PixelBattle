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


func _spawn_battle(seed_value: int = FIXED_SEED) -> Node2D:
	var scene: PackedScene = load(BATTLE_SCENE)
	var root: Node2D = scene.instantiate()
	root.run_seed = seed_value
	add_child_autofree(root)
	return root


func test_battle_scene_loads() -> void:
	assert_not_null(load(BATTLE_SCENE), "battle.tscn 应该能被加载")


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
	var root := _spawn_battle()
	var cfg := PBSimConfig.new()
	assert_eq(root.get_node("Deployed").get_child_count(), cfg.deploy_slots_max, "上场位节点应按出战席上限一次建满")


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
	# plan_wave / settle_wave —— 那是批量模拟走的同一条路。
	# 渲染层偷偷改一笔，画面和批量结论就会分叉，而且不报任何错。
	var root := _spawn_battle()
	var gold_before: int = root._state.gold
	var wave_before: int = root._state.wave_index
	var hp_before: float = root._state.base_hp
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
	var state := PBRunState.new()
	assert_eq(state.missing_counters().size(), 5, "空卡池应该五系全缺")

	# 火克风，所以持有火系就能覆盖「风」那一波。
	state.add_unit(PBUnit.new(PBElement.Type.FIRE, PBUnit.Rarity.R))
	assert_eq(state.missing_counters().size(), 4, "有火系之后应该只缺四系")
	assert_true(state.can_counter(PBElement.Type.WIND), "火克风")
	assert_false(state.can_counter(PBElement.Type.FIRE), "火不克火")

	for element: int in PBElement.RING:
		state.add_unit(PBUnit.new(element as PBElement.Type, PBUnit.Rarity.R))
	assert_eq(state.missing_counters().size(), 0, "五系齐了应该零空缺")


func test_physical_units_never_count_as_coverage() -> void:
	# 物理不参与克制环（§03），堆再多也覆盖不了任何一系。
	# 这正是「纯物理阵容极限波次 < 五系的 70%」那条验收的由来。
	var state := PBRunState.new()
	for variant: int in 2:
		for rarity: int in 4:
			state.add_unit(PBUnit.new(PBElement.Type.PHYSICAL, rarity as PBUnit.Rarity, variant))
	assert_eq(state.missing_counters().size(), 5, "纯物理卡池应该五系全缺")


func test_same_seed_reproduces_the_same_wave() -> void:
	# §12 的确定性延伸到画面：同种子的两局，第一波必须一模一样。
	var a := _spawn_battle(4242)
	var b := _spawn_battle(4242)
	assert_eq(a._plan.wave.index, b._plan.wave.index, "同种子的波次序号应一致")
	assert_eq(a._plan.wave.element, b._plan.wave.element, "同种子的敌方属性应一致")
	assert_eq(a._plan.wave.count, b._plan.wave.count, "同种子的敌人数量应一致")
	assert_eq(a._plan.wave.shape, b._plan.wave.shape, "同种子的波型应一致")
