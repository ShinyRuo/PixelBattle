extends GutTest
## [PBRngStreams] 的确定性测试。对应施工策划案 §12。
##
## 这一组测的是三条能力的地基：存档回滚、每日种子挑战、战报回放。
## 三者全部建立在「同种子 → 同序列」和「三条流互不污染」之上，
## 而这两条一旦破了，症状都不是崩溃，而是「玩家发现退出重进能刷好卡」。


func _draw(rng: RandomNumberGenerator, times: int = 10) -> Array[int]:
	var out: Array[int] = []
	for _i: int in times:
		out.append(rng.randi_range(1, 1000))
	return out


func test_same_seed_produces_identical_sequences() -> void:
	var a := PBRngStreams.new(2024)
	var b := PBRngStreams.new(2024)
	assert_eq(_draw(a.gacha), _draw(b.gacha), "同种子的抽卡流应完全一致")
	assert_eq(_draw(a.quest), _draw(b.quest), "同种子的任务流应完全一致")
	assert_eq(_draw(a.combat), _draw(b.combat), "同种子的战斗流应完全一致")


func test_streams_are_independent_of_each_other() -> void:
	# 核心断言：把 combat 流抽爆，gacha 流的输出必须一个字都不变。
	# 这正是「改一次战斗掉落逻辑不会让旧存档的抽卡序列全变」的机器验证。
	var untouched := PBRngStreams.new(77)
	var meddled := PBRngStreams.new(77)
	_draw(meddled.combat, 500)
	_draw(meddled.quest, 500)
	assert_eq(_draw(untouched.gacha), _draw(meddled.gacha), "战斗流与任务流不应污染抽卡流")


func test_different_streams_do_not_share_a_sequence() -> void:
	# 三条流若不慎用了同一个种子，会输出同一串数 —— 表面上一切正常，
	# 实际是「抽到 SSR 的那一波必定掉落暴击」这类隐蔽的相关性。
	var streams := PBRngStreams.new(5)
	var gacha := _draw(streams.gacha, 20)
	var quest := _draw(streams.quest, 20)
	var combat := _draw(streams.combat, 20)
	assert_ne(gacha, quest, "抽卡流与任务流不应是同一串序列")
	assert_ne(gacha, combat, "抽卡流与战斗流不应是同一串序列")
	assert_ne(quest, combat, "任务流与战斗流不应是同一串序列")


func test_adjacent_seeds_diverge() -> void:
	# 每日种子挑战里「昨天 vs 今天」必然是两个相近的种子。
	# 种子直接相加派生的话，相邻种子的前几个输出可能高度相关。
	var today := PBRngStreams.new(20260827)
	var tomorrow := PBRngStreams.new(20260828)
	assert_ne(_draw(today.gacha), _draw(tomorrow.gacha), "相邻种子应产生不相关的序列")


func test_state_round_trip_reproduces_the_next_draws() -> void:
	# §12 验收项：读档后连续抽卡 10 次的结果，与不读档时完全一致。
	var live := PBRngStreams.new(31337)
	_draw(live.gacha, 7)  # 先玩几波，让状态离开初始值
	_draw(live.quest, 3)
	var snapshot := live.to_state()
	var expected := _draw(live.gacha, 10)

	var restored := PBRngStreams.new(0)
	restored.from_state(snapshot)
	assert_eq(_draw(restored.gacha, 10), expected, "读档后的抽卡序列应与不读档完全一致")
	assert_eq(restored.base_seed, live.base_seed, "基准种子也应随存档恢复")


func test_state_survives_a_json_round_trip() -> void:
	# 真正的坑在这里：state 是 uint64，JSON 的数字是双精度浮点，
	# 超过 2^53 的部分会被静默截断 —— 不报错，只是序列悄悄对不上。
	# to_state 存字符串就是为了绕开这一点，这条测试守着它。
	var live := PBRngStreams.new(424242)
	_draw(live.gacha, 5)
	# 快照必须在取 expected 之前 —— 顺序反了就变成拿「快照点之后的第 11~20 个」
	# 去比「第 1~10 个」，测试会红，但红的是测试不是代码。
	var text := JSON.stringify(live.to_state())
	var expected := _draw(live.gacha, 10)
	var parsed: Variant = JSON.parse_string(text)
	assert_not_null(parsed, "存档应能被 JSON 解析回来")

	var restored := PBRngStreams.new(0)
	restored.from_state(parsed as Dictionary)
	assert_eq(_draw(restored.gacha, 10), expected, "经过 JSON 往返后序列仍应完全一致")


func test_from_state_tolerates_missing_streams() -> void:
	# 版本迁移场景：旧存档可能没有某条流。缺字段应保持现状，不该崩也不该清零。
	var streams := PBRngStreams.new(11)
	var before := streams.quest.state
	streams.from_state({"gacha": "12345"})
	assert_eq(streams.quest.state, before, "存档里缺失的流应保持当前状态")
	assert_eq(streams.gacha.state, 12345, "存档里给出的流应被正确写入")


func test_clone_forks_without_sharing_state() -> void:
	# 批量模拟要「从此刻分叉，跑几种不同决策看哪个好」，分叉后两边不能互相影响。
	var origin := PBRngStreams.new(808)
	_draw(origin.gacha, 4)
	var fork := origin.clone()
	var from_origin := _draw(origin.gacha, 10)
	var from_fork := _draw(fork.gacha, 10)
	assert_eq(from_origin, from_fork, "分叉点之后两条流应给出相同序列")

	_draw(fork.gacha, 50)
	assert_eq(origin.base_seed, fork.base_seed, "分叉不应改变基准种子")
