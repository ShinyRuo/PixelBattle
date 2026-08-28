extends SceneTree
## M0 单波节奏诊断：把一整局逐波拆开，看每一波到底花了多少秒、场上有几个人。
##
## 跑法：
##
## [codeblock]
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . \
##     --script res://src/tools/wave_pacing.gd -- --seed 20260827
## [/codeblock]
##
## 存在的理由：§01 要求单波 30–45 秒，M0-c 的截图里却看到战场经常是空的。
## 「时长不够」和「战场没人」听起来是两回事，但两者都由同一组量决定：
##
## - **出怪窗口** `spawn_window` —— 最后一个怪最早什么时候出场
## - **行军时间** `march_seconds` —— 出场到抵达基地的路程
## - **清怪时间** `total_hp / dps` —— 玩家把这一波打完需要多久
##
## 单波时长约等于 `max(出怪窗口, 清怪时间) + 尾巴`；场上人数则取决于
## 清怪时间占行军时间的比例。所以这份诊断把这三个量并排打出来，
## 好判断到底该动哪一个 —— 光看总时长是分不出来的。
##
## [b]这是诊断工具，不参与游戏运行。[/b]

## 表格里最多打多少波，再多终端就刷屏了。
const MAX_ROWS: int = 40

const ELEMENT_NAMES := {
	PBElement.Type.FIRE: "火",
	PBElement.Type.WIND: "风",
	PBElement.Type.THUNDER: "雷",
	PBElement.Type.EARTH: "土",
	PBElement.Type.WATER: "水",
	PBElement.Type.PHYSICAL: "物",
}

const SHAPE_NAMES := {
	PBWave.Shape.NORMAL: "常规",
	PBWave.Shape.SWARM: "潮水",
	PBWave.Shape.ELITE: "精英",
	PBWave.Shape.BOSS: "BOSS",
	PBWave.Shape.MEGA_BOSS: "大BOSS",
}

var _seed: int = 20260827
var _strategy_id: StringName = &"balanced"
var _spawn_window: float = 0.0
var _march_seconds: float = 0.0
var _hp_base: float = 0.0


func _initialize() -> void:
	_parse_args()
	var cfg := PBCharacterLoader.config()
	cfg.use_tick_battle = true
	if _spawn_window > 0.0:
		cfg.spawn_window = _spawn_window
	if _march_seconds > 0.0:
		cfg.march_seconds = _march_seconds
	if _hp_base > 0.0:
		cfg.hp_base = _hp_base

	var rows := _play(cfg)
	_print_table(rows, cfg)
	quit()


## 跑一整局，每波记一行。战斗逐 tick 推进，好在推进过程中采样场上人数 ——
## [method PBBattleSim.run_to_end] 只给结果，采不到过程。
func _play(cfg: PBSimConfig) -> Array[Dictionary]:
	var rng := PBRngStreams.new(_seed)
	var state := PBRunSim.new_state(cfg)
	var strategy := PBStrategyRegistry.make(_strategy_id)
	var rows: Array[Dictionary] = []

	while state.wave_index <= cfg.max_wave:
		var plan := PBRunSim.plan_wave(state, strategy, cfg, rng)
		var battle := PBBattleSim.new(plan.wave, plan.dps, state.def_reduction(cfg), cfg)
		var peak: int = 0
		var alive_sum: int = 0
		while not battle.is_finished() and battle.current_tick() < PBBattleSim.MAX_TICKS:
			battle.step()
			var alive: int = _count_on_field(battle)
			peak = maxi(peak, alive)
			alive_sum += alive
		var outcome := battle.result()
		rows.append(_row(plan, outcome, peak, alive_sum, cfg))
		PBRunSim.settle_wave(state, plan, outcome, cfg, rng)
		if state.base_hp <= 0.0:
			break
		state.wave_index += 1
	return rows


## 这一 tick 场上有几个敌人 —— 已出场、还活着的。
func _count_on_field(battle: PBBattleSim) -> int:
	var tick: int = battle.current_tick()
	var count: int = 0
	for enemy: PBEnemy in battle.enemies():
		if enemy.is_active(tick):
			count += 1
	return count


func _row(
	plan: PBWavePlan, outcome: PBCombatOutcome, peak: int, alive_sum: int, cfg: PBSimConfig
) -> Dictionary:
	var wave: PBWave = plan.wave
	# 理论清怪时间：整波血量除以每秒输出。它和实际时长的差就是「等出怪」的时间。
	var kill_seconds: float = INF
	if plan.dps > 0.0:
		kill_seconds = wave.total_hp() / plan.dps
	var ticks: int = maxi(outcome.ticks, 1)
	return {
		"index": wave.index,
		"element": ELEMENT_NAMES.get(wave.element, "?"),
		"shape": SHAPE_NAMES.get(wave.shape, "?"),
		"count": wave.count,
		"total_hp": wave.total_hp(),
		"dps": plan.dps,
		"kill_seconds": kill_seconds,
		"seconds": outcome.battle_seconds,
		"leaked": outcome.leaked,
		"peak": peak,
		"mean_on_field": float(alive_sum) / float(ticks),
		# 单体承伤时间占行军时间的比例。接近 0 = 一出场就被秒，战场必然是空的。
		"ttk_ratio": (kill_seconds / float(wave.count)) / cfg.march_seconds,
	}


func _print_table(rows: Array[Dictionary], cfg: PBSimConfig) -> void:
	print("")
	print(
		(
			"单波节奏诊断　种子 %d　流派 %s　spawn_window=%.1fs　march=%.1fs"
			% [_seed, _strategy_id, cfg.spawn_window, cfg.march_seconds]
		)
	)
	print("")
	print("波次 属性 波型   数量  整波血量      DPS  清怪秒  实际秒  漏  峰值  均在场  单体/行军")
	print("──── ──── ────── ────  ────────  ───────  ──────  ──────  ──  ────  ──────  ─────────")
	for row: Dictionary in rows:
		if int(row["index"]) > MAX_ROWS:
			break
		print(
			(
				"%4d  %s   %-6s %3d  %8.0f  %7.0f  %6.2f  %6.2f  %2d  %4d  %6.2f  %8.3f"
				% [
					row["index"],
					row["element"],
					row["shape"],
					row["count"],
					row["total_hp"],
					row["dps"],
					row["kill_seconds"],
					row["seconds"],
					row["leaked"],
					row["peak"],
					row["mean_on_field"],
					row["ttk_ratio"],
				]
			)
		)
	_print_summary(rows)


func _print_summary(rows: Array[Dictionary]) -> void:
	if rows.is_empty():
		return
	var seconds_sum: float = 0.0
	var on_field_sum: float = 0.0
	var in_target: int = 0
	for row: Dictionary in rows:
		seconds_sum += float(row["seconds"])
		on_field_sum += float(row["mean_on_field"])
		var seconds: float = float(row["seconds"])
		if seconds >= PBRunSim.TARGET_DURATION_MIN and seconds <= PBRunSim.TARGET_DURATION_MAX:
			in_target += 1
	var n: float = float(rows.size())
	print("")
	print("打到第 %d 波" % rows.size())
	print("单波平均 %.1f 秒（§01 要求 30–45）" % (seconds_sum / n))
	print("落在 30–45 秒区间的波次：%d / %d" % [in_target, rows.size()])
	print("场上平均同时有 %.1f 个敌人" % (on_field_sum / n))


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if i + 1 >= args.size():
			continue
		var value: String = args[i + 1]
		match args[i]:
			"--seed":
				_seed = value.to_int()
			"--strategy":
				_strategy_id = StringName(value)
			"--spawn-window":
				_spawn_window = maxf(value.to_float(), 0.0)
			"--march":
				_march_seconds = maxf(value.to_float(), 0.0)
			"--hp-base":
				_hp_base = maxf(value.to_float(), 0.0)
