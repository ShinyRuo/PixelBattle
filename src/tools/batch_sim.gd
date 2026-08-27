extends SceneTree
## M-1 批量模拟入口。扫 `GROWTH` × 流派，每格跑 N 局，出 CSV。
##
## 跑法（命令行一律用 godot_console.exe，godot.exe 的 stdout 不回传终端）：
##
## [codeblock]
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . \
##     --script res://src/tools/batch_sim.gd -- --runs 200 --growth-min 1.10
## [/codeblock]
##
## `--` 之后的参数由 [method OS.get_cmdline_user_args] 取到，不会被引擎自己吃掉。
##
## 产出两份 CSV：
##
## - `m1_runs.csv` —— 每局一行的原始数据，想换个统计口径时不用重跑
## - `m1_summary.csv` —— 每个（growth, strategy）格子一行，含 p50 / p90

const OUT_DIR := "res://build"

var _growth_min: float = 1.10
var _growth_max: float = 1.15
var _growth_step: float = 0.005
var _runs: int = 200
var _seed_base: int = 20260827

## 稀有度阶梯的斜率：每高一档战力乘多少。0 表示用 [PBSimConfig] 的默认值。
##
## 加这个开关是为了验一个具体怀疑：默认阶梯是 100/185/340/620，每档 ×1.84，
## 而 §03 的克制倍率是 ×2.0 —— 两者几乎相等，意味着「升一档稀有度」
## 和「吃一次克制」等价，换人策略会被稀有度阶梯整个吃掉。
## 把斜率压平再跑一次，如果换人的收益立刻放大，这个怀疑就坐实了。
var _rarity_slope: float = 0.0


func _initialize() -> void:
	_parse_args()
	var started := Time.get_ticks_msec()

	var runs: Array[PBRunResult] = []
	for growth: float in _growth_values():
		for strategy_id: StringName in PBStrategyRegistry.IDS:
			runs.append_array(_run_cell(growth, strategy_id))

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	_ensure_out_dir()
	_write_runs_csv(runs)
	var summary := _summarize(runs)
	_write_summary_csv(summary)
	_print_report(summary, runs.size(), elapsed)
	quit()


## 跑一个（growth, strategy）格子的全部局数。
func _run_cell(growth: float, strategy_id: StringName) -> Array[PBRunResult]:
	var cfg := PBSimConfig.new()
	cfg.growth = growth
	if _rarity_slope > 0.0:
		var base: float = cfg.rarity_power[0]
		cfg.rarity_power = [
			base,
			base * _rarity_slope,
			base * pow(_rarity_slope, 2.0),
			base * pow(_rarity_slope, 3.0),
		]
	var out: Array[PBRunResult] = []
	for i: int in _runs:
		# 同一个 i 在所有格子上用同一个种子：不同流派面对**同一串**波型与抽卡运气，
		# 流派之间的差值因此不含运气成分。这是配对比较，比各跑各的省一个数量级的样本量。
		var strategy := PBStrategyRegistry.make(strategy_id)
		out.append(PBRunSim.run(cfg, strategy, _seed_base + i))
	return out


func _growth_values() -> Array[float]:
	var out: Array[float] = []
	var value := _growth_min
	while value <= _growth_max + 1e-9:
		out.append(snappedf(value, 0.0001))
		value += _growth_step
	return out


## 把每局结果按（growth, strategy）归并成统计行。
func _summarize(runs: Array[PBRunResult]) -> Array[Dictionary]:
	var buckets := {}
	for run: PBRunResult in runs:
		var key := "%.4f|%s" % [run.growth, run.strategy_id]
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(run)

	var out: Array[Dictionary] = []
	for key: String in buckets:
		var cell: Array = buckets[key]
		var waves: Array[int] = []
		var capped: int = 0
		var seconds_sum: float = 0.0
		var duration_hits: float = 0.0
		for run: PBRunResult in cell:
			waves.append(run.wave_reached)
			if run.hit_wave_cap:
				capped += 1
			seconds_sum += run.mean_battle_seconds()
			duration_hits += run.duration_hit_rate()
		waves.sort()
		var first: PBRunResult = cell[0]
		var row := {
			"growth": first.growth,
			"strategy": first.strategy_id,
			"runs": cell.size(),
			"p50": _percentile(waves, 0.50),
			"p90": _percentile(waves, 0.90),
			"mean_wave": _mean(waves),
			"cap_rate": float(capped) / float(cell.size()),
			"mean_battle_seconds": seconds_sum / float(cell.size()),
			"duration_hit_rate": duration_hits / float(cell.size()),
		}
		out.append(row)
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if a["growth"] != b["growth"]:
				return a["growth"] < b["growth"]
			return String(a["strategy"]) < String(b["strategy"])
	)
	return out


func _percentile(sorted_values: Array[int], q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx := clampi(int(round(q * float(sorted_values.size() - 1))), 0, sorted_values.size() - 1)
	return float(sorted_values[idx])


func _mean(values: Array[int]) -> float:
	if values.is_empty():
		return 0.0
	var total: int = 0
	for v: int in values:
		total += v
	return float(total) / float(values.size())


func _write_runs_csv(runs: Array[PBRunResult]) -> void:
	var lines := PackedStringArray()
	lines.append(
		(
			"growth,strategy,seed,wave_reached,hit_wave_cap,kills,leaked,"
			+ "gold_earned,pulls,quests,roster,tech_gold,tech_pop,tech_atk,mean_battle_seconds"
		)
	)
	for run: PBRunResult in runs:
		var line := (
			"%.4f,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f"
			% [
				run.growth,
				run.strategy_id,
				run.run_seed,
				run.wave_reached,
				1 if run.hit_wave_cap else 0,
				run.total_kills,
				run.total_leaked,
				run.gold_earned,
				run.gacha_pulls,
				run.quests_taken,
				run.final_roster_size,
				run.final_tech_gold,
				run.final_tech_pop,
				run.final_tech_atk,
				run.mean_battle_seconds(),
			]
		)
		lines.append(line)
	_write_file("%s/m1_runs.csv" % OUT_DIR, lines)


func _write_summary_csv(summary: Array[Dictionary]) -> void:
	var lines := PackedStringArray()
	lines.append(
		"growth,strategy,runs,p50,p90,mean_wave,cap_rate,mean_battle_seconds,duration_hit_rate"
	)
	for row: Dictionary in summary:
		var line := (
			"%.4f,%s,%d,%.1f,%.1f,%.2f,%.3f,%.2f,%.3f"
			% [
				row["growth"],
				row["strategy"],
				row["runs"],
				row["p50"],
				row["p90"],
				row["mean_wave"],
				row["cap_rate"],
				row["mean_battle_seconds"],
				row["duration_hit_rate"],
			]
		)
		lines.append(line)
	_write_file("%s/m1_summary.csv" % OUT_DIR, lines)


## 把关键结论直接打在终端上。CSV 是给后续分析用的，
## 但「这次跑出来到底怎么样」应该看一眼就知道，不用先开表格软件。
func _print_report(summary: Array[Dictionary], total_runs: int, elapsed: float) -> void:
	print("")
	print("M-1 批量模拟完成：%d 局，耗时 %.1f 秒" % [total_runs, elapsed])
	print("CSV 输出到 %s/" % OUT_DIR)
	print("")
	print("growth  strategy         p50    p90   mean  cap%%  单波秒数")
	print("──────  ───────────────  ─────  ─────  ─────  ────  ────────")
	for row: Dictionary in summary:
		var line := (
			"%.3f   %-15s  %5.1f  %5.1f  %5.1f  %3.0f%%  %6.1f"
			% [
				row["growth"],
				row["strategy"],
				row["p50"],
				row["p90"],
				row["mean_wave"],
				row["cap_rate"] * 100.0,
				row["mean_battle_seconds"],
			]
		)
		print(line)


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# 目录里放一个空的 .gdignore，让引擎整个跳过它。
	#
	# 不放的话，Godot 会把这里的 .csv 当成**本地化翻译表**去导入 ——
	# 每个 CSV 旁边生成一堆 .translation 和 .import，而且此后每次 --import
	# 都要重新扫这些几 MB 的文件，check.ps1 会越跑越慢。
	# build/ 本身是 gitignore 的，所以这个文件只能由工具自己补，不能靠提交。
	var marker: String = "%s/.gdignore" % OUT_DIR
	if not FileAccess.file_exists(marker):
		var file := FileAccess.open(marker, FileAccess.WRITE)
		if file != null:
			file.close()


func _write_file(path: String, lines: PackedStringArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("写不了 %s：%s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i: int in args.size():
		if i + 1 >= args.size():
			continue
		var value: String = args[i + 1]
		match args[i]:
			"--runs":
				_runs = maxi(value.to_int(), 1)
			"--growth-min":
				_growth_min = value.to_float()
			"--growth-max":
				_growth_max = value.to_float()
			"--growth-step":
				_growth_step = maxf(value.to_float(), 0.0001)
			"--seed":
				_seed_base = value.to_int()
			"--rarity-slope":
				_rarity_slope = maxf(value.to_float(), 0.0)
