class_name PBEconomyRules
extends RefCounted
## 经济、科技、抽卡、任务的结算规则。施工策划案 §06 / §07 / §08。
##
## 全部 static、无状态。金币的四条收入流在这里各自成一个函数，
## 好让 M-1 能单独关掉某一条看差异 —— §07 的核心论断「经济位 = 战力空位」
## 只有在能分别度量的时候才验得了。

## §08 抽卡概率表。每行 `[波次上限, R, SR, SSR, USR]`，概率是百分比。
## 最后一行的波次上限用一个大数兜住 51+ 段。
const GACHA_TABLE := [
	[10, 70.0, 27.0, 3.0, 0.0],
	[20, 55.0, 36.0, 8.5, 0.5],
	[30, 40.0, 42.0, 16.0, 2.0],
	[50, 25.0, 45.0, 25.0, 5.0],
	[999999, 12.0, 43.0, 33.0, 12.0],
]

## §06 任务表。`[权重, 需派遣人数, 金币基数, 金币每波增量]`。
## 附加掉落（配件、卷轴）M-1 不建模 —— 装备合成树是 M3，
## 现在把掉落折进金币会让「羁绊 ↔ 金币」这条张力轴的度量失真。
const QUEST_TABLE := [
	[40, 2, 60, 8],
	[27, 2, 100, 14],
	[18, 3, 160, 22],
	[10, 3, 250, 35],
	[5, 4, 400, 55],
]

## 任务等级的显示名，只用于 CSV 输出。
const QUEST_GRADES: Array[StringName] = [&"C", &"B", &"A", &"S", &"SSS"]


## 金币科技的被动收入：战斗阶段每 0.5 秒一跳。
##
## **只在战斗阶段计时。** 准备阶段是不限时的（§01），让它在准备阶段产出
## 等于给玩家无限金币 —— 挂机一小时再开波就通关了。
static func passive_income(battle_seconds: float, tech_level: int, cfg: PBSimConfig) -> int:
	var ticks: float = battle_seconds * 2.0
	var per_tick: float = cfg.gold_tick_base * (1.0 + cfg.gold_tick_rate * float(tech_level))
	return int(floor(ticks * per_tick))


## 纲手：按击杀数掷骰。§07 的期望是 +13/击杀，但刻意保留看得见的负收益。
##
## §07 明确写了「原版保留不动，别去修」—— 它稳赚却包装成会扣钱的老虎机，
## 用体感波动换玩家的注意力投入。M-1 照掷，因为「打不动就断粮」这条
## 反馈回路正是 §07「经济位 = 战力空位」硬下限的来源。
static func tsunade_income(kills: int, cfg: PBSimConfig, rng: RandomNumberGenerator) -> int:
	var total: int = 0
	for _i: int in kills:
		var roll: float = rng.randf()
		if roll < 0.50:
			total += cfg.tsunade_gain
		elif roll < 0.80:
			total += cfg.tsunade_loss
	return total


## 角都：每波结算的回合收入。第 k 个的系数是 `k^−1.5`，递减比原版的减半更陡。
##
## §07 的改动：角都取消输出能力，纯经济卡。原版它兼任雷系 AOE 第二，
## 一个位置交付两份价值 —— 那是原版流派单一的直接原因。
static func kakuzu_income(count: int, cfg: PBSimConfig) -> int:
	var total: float = 0.0
	for k: int in range(1, count + 1):
		total += cfg.kakuzu_base * pow(float(k), cfg.kakuzu_falloff)
	return int(floor(total))


## 科技升到下一级要多少钱。已满级返回 -1。
static func tech_cost(branch: StringName, level: int, cfg: PBSimConfig) -> int:
	match branch:
		&"gold":
			return _cost_or_capped(level, cfg.tech_gold_max, cfg.tech_gold_cost, cfg.tech_gold_mult)
		&"pop":
			return _cost_or_capped(level, cfg.tech_pop_max, cfg.tech_pop_cost, cfg.tech_pop_mult)
		&"atk":
			return _cost_or_capped(level, cfg.tech_atk_max, cfg.tech_atk_cost, cfg.tech_atk_mult)
		&"def":
			return _cost_or_capped(level, cfg.tech_def_max, cfg.tech_def_cost, cfg.tech_def_mult)
		_:
			return -1


## 抽一张卡。属性在六种里等概率（含物理），稀有度查 §08 的分段概率表。
##
## [param pity] 是连续未出 SSR 及以上的次数，由调用方维护。
static func roll_gacha(
	wave_index: int, pity: int, cfg: PBSimConfig, rng: RandomNumberGenerator
) -> PBUnit:
	var element := _roll_element(rng)
	var variant: int = rng.randi_range(0, maxi(cfg.characters_per_bucket - 1, 0))
	if pity >= cfg.gacha_pity:
		# 保底只保到 SSR，不直接给 USR —— 否则保底会变成刷 USR 的最优路径。
		return PBUnit.new(element, PBUnit.Rarity.SSR, variant)

	var row: Array = _gacha_row(wave_index)
	var roll: float = rng.randf() * 100.0
	var acc: float = 0.0
	for i: int in range(1, 5):
		acc += float(row[i])
		if roll < acc:
			return PBUnit.new(element, (i - 1) as PBUnit.Rarity, variant)
	return PBUnit.new(element, PBUnit.Rarity.R, variant)


## 刷新本波的任务，返回它在 [constant QUEST_TABLE] 里的行号。
static func roll_quest(rng: RandomNumberGenerator) -> int:
	var total: int = 0
	for row: Array in QUEST_TABLE:
		total += int(row[0])
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for i: int in QUEST_TABLE.size():
		acc += int(QUEST_TABLE[i][0])
		if roll <= acc:
			return i
	return 0


## 完成 [param grade] 号任务在第 [param wave_index] 波能拿多少金币。
static func quest_reward(grade: int, wave_index: int) -> int:
	var row: Array = QUEST_TABLE[grade]
	return int(row[2]) + int(row[3]) * wave_index


## 该任务需要派出几名待命忍者。派遣期间他们的羁绊不生效（§06）。
static func quest_cost_units(grade: int) -> int:
	return int(QUEST_TABLE[grade][1])


static func _cost_or_capped(level: int, max_level: int, base: float, mult: float) -> int:
	if level >= max_level:
		return -1
	return int(floor(base * pow(mult, float(level))))


## 属性在六种里等概率。真实角色池当然不是均匀的，但 M-1 不该在这里引入
## 一个自己拍的分布 —— 那会让「五系覆盖有多难」这个结论变成拍脑袋的产物。
static func _roll_element(rng: RandomNumberGenerator) -> PBElement.Type:
	return rng.randi_range(0, 5) as PBElement.Type


static func _gacha_row(wave_index: int) -> Array:
	for row: Array in GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return GACHA_TABLE[GACHA_TABLE.size() - 1]
