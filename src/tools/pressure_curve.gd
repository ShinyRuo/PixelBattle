extends SceneTree
## 压力曲线：**逐波**量「离打不动还差多远」。M1 验收用。
##
## [codeblock]
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . \
##     --script res://src/tools/pressure_curve.gd -- --runs 50 --strategy balanced
## [/codeblock]
##
## ## 为什么要单开一个仪器
##
## [PBBatchSim] 出的是整局汇总（活到第几波、总收入、抽了多少张）。
## 那组数回答得了「这个流派强不强」，**回答不了「玩起来是什么形状」**。
##
## M1 的验收问的是后者：压力曲线单不单调。一局 40 波，如果富余倍数
## 前 35 波都是 20×、最后 3 波掉到 1×，那它在数值上完全「正常」——
## p50 漂亮、单波时长达标 —— 玩起来却是「好好好、死」，
## 玩家从头到尾没有任何信号该转经济。这种失败只有逐波看才看得见。
##
## ## 量的是什么
##
## 每波两个数：队伍对本波的有效 DPS，和这一波的**悬崖**
## （[method PBValuation.leak_threshold_dps]，低于它就开始漏怪）。
## 两者的比值就是富余倍数 —— 和任务卡上给玩家看的是同一个数、同一份计算。
##
## 顺带按波型和「有没有克星」各切一刀：如果形状主要由波型决定而不是波次，
## 那玩家感觉到的就不是难度曲线，是抽签。

const OUT_DIR := "res://build"

## 每个波次段落的宽度（波）。汇总表按这个分组。
const BAND: int = 5

var _runs: int = 50
var _seed_base: int = 20260827
var _strategy_id: StringName = &"balanced"
var _growth: float = 0.0
var _dispatch: StringName = &""

## 逐波样本。每项 `[波次, 波型, 富余倍数, 有没有克星, 接没接任务, 金币]`。
var _samples: Array = []

## 每局的最后一波（打不过去的那一波）在 [member _samples] 里的下标。
var _deaths: Array[int] = []


func _initialize() -> void:
	_parse_args()
	var cfg := PBGameData.config()
	if _growth > 0.0:
		cfg.growth = _growth

	var started := Time.get_ticks_msec()
	for i: int in _runs:
		_run_once(cfg, _seed_base + i)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	_ensure_out_dir()
	_write_csv()
	_report(cfg, elapsed)
	quit()


## 跑一局，逐波取样。
##
## 这里手抄了 [method PBRunSim.run] 的循环而不是调它 —— 那个函数只回一份
## 整局汇总，中间状态跑完就没了。**顺序必须和它逐字一致**，
## 差一步 RNG 就分叉，量出来的曲线和实际玩到的不是同一局。
func _run_once(cfg: PBSimConfig, run_seed: int) -> void:
	var rng := PBRngStreams.new(run_seed)
	var state := PBRunSim.new_state(cfg)
	var strategy := PBStrategyRegistry.make(_strategy_id)
	_apply_dispatch(strategy)

	while state.wave_index <= cfg.max_wave:
		var plan := PBRunSim.plan_wave(state, strategy, cfg, rng)
		var cliff: float = PBValuation.leak_threshold_dps(plan.wave, state.def_reduction(cfg), cfg)
		(
			_samples
			. append(
				[
					plan.wave.index,
					int(plan.wave.shape),
					plan.dps / maxf(cliff, 1e-9),
					state.can_counter(plan.wave.element),
					plan.quest_accepted,
					state.gold,
				]
			)
		)
		var outcome := PBCombatRules.resolve(plan.wave, plan.dps, state.def_reduction(cfg), cfg)
		PBRunSim.settle_wave(state, plan, outcome, cfg, rng)
		if state.base_hp <= 0.0:
			_deaths.append(_samples.size() - 1)
			return
		state.wave_index += 1


func _apply_dispatch(strategy: PBStrategy) -> void:
	match _dispatch:
		&"never":
			strategy.dispatch_policy = PBStrategy.Dispatch.NEVER
		&"always":
			strategy.dispatch_policy = PBStrategy.Dispatch.ALWAYS
		&"smart":
			strategy.dispatch_policy = PBStrategy.Dispatch.SMART


func _report(cfg: PBSimConfig, elapsed: float) -> void:
	print("")
	print(
		(
			"压力曲线　流派 %s　GROWTH %.3f　%d 局　%d 波样本　耗时 %.1f 秒"
			% [_strategy_id, cfg.growth, _runs, _samples.size(), elapsed]
		)
	)
	print("CSV 输出到 %s/pressure_curve.csv" % OUT_DIR)
	_report_bands()
	_report_shapes()
	_report_coverage()
	_report_death()
	_report_monotonicity()


## 按波次分段看富余倍数。**曲线的形状主要看这张表。**
func _report_bands() -> void:
	print("")
	print("按波次段落（富余倍数 = 队伍 DPS ÷ 开始漏怪的 DPS）")
	print("波次段    样本   富余 p50   富余均值   最低    最高   还活着的局数")
	print("───────  ─────  ────────  ────────  ─────  ──────  ────────────")
	var band: int = 1
	while band * BAND <= 200:
		var low: int = (band - 1) * BAND + 1
		var ratios := _ratios_where(
			func(s: Array) -> bool: return s[0] >= low and s[0] < low + BAND
		)
		if ratios.is_empty():
			break
		var alive: int = 0
		for death: int in _deaths:
			if int(_samples[death][0]) >= low:
				alive += 1
		print(
			(
				"%3d–%-3d  %5d  %8.2f  %8.2f  %5.2f  %6.1f  %12d"
				% [
					low,
					low + BAND - 1,
					ratios.size(),
					_percentile(ratios, 0.5),
					_mean(ratios),
					ratios[0],
					ratios[ratios.size() - 1],
					alive,
				]
			)
		)
		band += 1


## 按波型切。**如果波型的影响盖过波次，玩家感觉到的就不是曲线，是抽签。**
func _report_shapes() -> void:
	print("")
	print("按波型（§04 的五种形状）")
	print("波型      样本   富余 p50   富余均值   低于 1.5× 的比例")
	print("───────  ─────  ────────  ────────  ────────────────")
	for shape: int in PBWave.Shape.size():
		var ratios := _ratios_where(func(s: Array) -> bool: return int(s[1]) == shape)
		if ratios.is_empty():
			continue
		print(
			(
				"%-7s  %5d  %8.2f  %8.2f  %15.0f%%"
				% [
					_shape_name(shape as PBWave.Shape),
					ratios.size(),
					_percentile(ratios, 0.5),
					_mean(ratios),
					_share_below(ratios, 1.5) * 100.0,
				]
			)
		)


## 有没有克星切一刀。§03 的整套属性系统在压力上值多少，就是这两行的差。
func _report_coverage() -> void:
	print("")
	print("按「卡池有没有本波的克星」（§03）")
	print("覆盖      样本   富余 p50   富余均值")
	print("───────  ─────  ────────  ────────")
	for covered: bool in [true, false]:
		var ratios := _ratios_where(func(s: Array) -> bool: return bool(s[3]) == covered)
		if ratios.is_empty():
			continue
		print(
			(
				"%-7s  %5d  %8.2f  %8.2f"
				% [
					"有克星" if covered else "没克星",
					ratios.size(),
					_percentile(ratios, 0.5),
					_mean(ratios),
				]
			)
		)


## 死之前那几波长什么样。**「好好好、死」就是在这张表上现形的。**
##
## 如果倒数第 5 波的富余还有十几倍、倒数第 1 波只有 0.9 倍，
## 那玩家在死前一波之内都没有任何可行动的信号。
func _report_death() -> void:
	print("")
	print("死亡前的几波（倒数第 N 波的富余倍数）")
	print("倒数    样本   富余 p50   富余均值")
	print("─────  ─────  ────────  ────────")
	for back: int in range(0, 6):
		var ratios: Array[float] = []
		for death: int in _deaths:
			var idx: int = death - back
			# 别越过上一局的边界 —— 样本是所有局首尾相接存的。
			if idx < 0 or int(_samples[idx][0]) != int(_samples[death][0]) - back:
				continue
			ratios.append(float(_samples[idx][2]))
		if ratios.is_empty():
			continue
		ratios.sort()
		print(
			(
				"%5d  %5d  %8.2f  %8.2f"
				% [back + 1, ratios.size(), _percentile(ratios, 0.5), _mean(ratios)]
			)
		)


## 相邻两波之间压力是不是在稳定上升。
##
## 「单调」不该按字面要求 100% —— 波型是随机的，一波精英接一波潮水
## 本来就该有起伏。要盯的是**这个比例有多接近抛硬币**：
## 接近 50% 就说明波次根本没在决定难度，玩家读到的是噪声。
func _report_monotonicity() -> void:
	var rising: int = 0
	var pairs: int = 0
	var jumps: int = 0
	for i: int in range(1, _samples.size()):
		if int(_samples[i][0]) != int(_samples[i - 1][0]) + 1:
			continue
		pairs += 1
		var before: float = float(_samples[i - 1][2])
		var after: float = float(_samples[i][2])
		if after < before:
			rising += 1
		if before > 0.0 and (after / before < 0.5 or after / before > 2.0):
			jumps += 1
	if pairs == 0:
		return
	print("")
	print("相邻波次（共 %d 对）" % pairs)
	print("  压力上升（富余比上一波低）：%.0f%%" % (float(rising) / float(pairs) * 100.0))
	print("  跳变超过 2 倍：%.0f%%" % (float(jumps) / float(pairs) * 100.0))


func _ratios_where(pred: Callable) -> Array[float]:
	var out: Array[float] = []
	for sample: Array in _samples:
		if pred.call(sample):
			out.append(float(sample[2]))
	out.sort()
	return out


func _share_below(sorted_ratios: Array[float], limit: float) -> float:
	var count: int = 0
	for value: float in sorted_ratios:
		if value < limit:
			count += 1
	return float(count) / float(maxi(sorted_ratios.size(), 1))


func _percentile(sorted_values: Array[float], q: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var idx := clampi(int(round(q * float(sorted_values.size() - 1))), 0, sorted_values.size() - 1)
	return sorted_values[idx]


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _shape_name(shape: PBWave.Shape) -> String:
	match shape:
		PBWave.Shape.SWARM:
			return "潮水"
		PBWave.Shape.ELITE:
			return "精英"
		PBWave.Shape.BOSS:
			return "BOSS"
		PBWave.Shape.MEGA_BOSS:
			return "大BOSS"
		_:
			return "常规"


func _write_csv() -> void:
	var lines := PackedStringArray()
	lines.append("wave,shape,headroom,covered,quest,gold")
	for sample: Array in _samples:
		(
			lines
			. append(
				(
					"%d,%d,%.4f,%d,%d,%d"
					% [
						int(sample[0]),
						int(sample[1]),
						float(sample[2]),
						1 if bool(sample[3]) else 0,
						1 if bool(sample[4]) else 0,
						int(sample[5]),
					]
				)
			)
		)
	var path: String = "%s/pressure_curve.csv" % OUT_DIR
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("写不了 %s：%s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var marker: String = "%s/.gdignore" % OUT_DIR
	if not FileAccess.file_exists(marker):
		var file := FileAccess.open(marker, FileAccess.WRITE)
		if file != null:
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
			"--seed":
				_seed_base = value.to_int()
			"--strategy":
				_strategy_id = StringName(value)
			"--growth":
				_growth = maxf(value.to_float(), 0.0)
			"--dispatch":
				_dispatch = StringName(value)
