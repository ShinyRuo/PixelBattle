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

## 任务栏一共几个槽（M5-7）。**等于 [constant QUEST_TABLE] 里最大的那个人数。**
##
## ## 它是「能塞几个」，不是「要几个」
##
## 界面上那四个槽是**固定的**：本波只要 2 个人时另外两个槽照样收得下人，
## 而塞多了就是 [member PBWavePlan.quest_accepted] 判不通过。
## 「要几个」永远走 [method quest_cost_units]，两个数不能混 ——
## 拿 `quest_cost_units` 当上限的话玩家**塞不进第三个**，
## 于是「人数不符」这条判定在界面上根本触发不了。
const QUEST_SLOTS: int = 4

## §07 的五条收入流。顺序即报表列序。
##
## 分开记账不是为了好看：§07 的验收「纯战力开局在 20 波左右因缺钱停滞」
## 实测跑到 39.5 波（均衡的 96%），也就是**不投经济几乎没有代价**。
## 只看总收入分不出两种解释 —— 是金币科技本身没用，
## 还是它有用但被别的流盖过去了。分了流才看得出该动哪一条。
const GOLD_SOURCES: Array[StringName] = [
	&"wave", &"passive", &"kill_drop", &"economy_slot", &"quest"
]


## 金币科技的被动收入：战斗阶段每 0.5 秒一跳。
##
## **只在战斗阶段计时。** 准备阶段是不限时的（§01），让它在准备阶段产出
## 等于给玩家无限金币 —— 挂机一小时再开波就通关了。
static func passive_income(battle_seconds: float, tech_level: int, cfg: PBSimConfig) -> int:
	var ticks: float = battle_seconds * 2.0
	var per_tick: float = cfg.gold_tick_base * (1.0 + cfg.gold_tick_rate * float(tech_level))
	return int(floor(ticks * per_tick))


## 击杀掉落：按击杀数掷骰。§07 的期望是 +13/击杀，但刻意保留看得见的负收益。
##
## §07 明确写了「原版保留不动，别去修」—— 它稳赚却包装成会扣钱的老虎机，
## 用体感波动换玩家的注意力投入。M-1 照掷，因为「打不动就断粮」这条
## 反馈回路正是 §07「经济位 = 战力空位」硬下限的来源。
##
## ## [param gold_floor]（§09 木叶三忍的功能档，M3-f）
##
## 「负收益不再触发，且金币收益提升」。这不是在**修**上面那台老虎机 ——
## §07 说了别修。它是把「关掉波动」做成一个要凑齐一组羁绊、还要把载体
## 排进出战席才拿得到的选项，两条设计同时在场，玩家自己选。
##
## **掷骰照掷，只改结果。** 少掷一次会让 `combat` 流错位，
## 于是「带不带这组羁绊」会改变之后每一波的敌人和掉落 —— 那不是一个功能档
## 该有的影响半径，而且它会让同种子的对拍失效（铁律 3）。
static func kill_drop_income(
	kills: int, cfg: PBSimConfig, rng: RandomNumberGenerator, gold_floor: bool = false
) -> int:
	var gain: int = cfg.kill_drop_gain
	if gold_floor:
		gain = int(round(float(gain) * cfg.bond_gold_gain_scale))
	var total: int = 0
	for _i: int in kills:
		var roll: float = rng.randf()
		if roll < 0.50:
			total += gain
		elif roll < 0.80 and not gold_floor:
			total += cfg.kill_drop_loss
	return total


## 经济位：每波结算的回合收入。第 k 个的系数是 `k^−1.5`，递减比原版的减半更陡。
##
## §07 的改动：经济位取消输出能力，纯经济卡。原版它兼任雷系 AOE 第二，
## 一个位置交付两份价值 —— 那是原版流派单一的直接原因。
##
## **收益随波次走**（`economy_slot_base + economy_slot_rate × n`），和波次奖金、任务奖励
## 同一个形状。初版是常数 85，实测的后果是它恒为微亏、**没有任何流派会选它** ——
## 详见 [member PBSimConfig.economy_slot_rate]。
static func economy_slot_income(count: int, wave_index: int, cfg: PBSimConfig) -> int:
	var per_unit: float = cfg.economy_slot_base + cfg.economy_slot_rate * float(wave_index)
	var total: float = 0.0
	for k: int in range(1, count + 1):
		total += per_unit * pow(float(k), cfg.economy_slot_falloff)
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


## 抽一张卡：**先掷稀有度（§08 的分段概率表），再在该稀有度的角色里等概率取一个。**
##
## [param pity] 是连续未出 SSR 及以上的次数，由调用方维护。
##
## ## 为什么是这个次序（M2-a2 改的）
##
## 之前是「掷属性 → 掷变体 → 掷稀有度」，因为那时卡池是
## 4 稀有度 × 6 属性 × 2 变体 的**满格网格**，随便掷都落得到人。
##
## 真角色表不是网格：30 个角色摊到 24 格上，大部分格子只有 1 个或 0 个
## （比如没有水系 USR）。照旧掷法会不停撞空格走退化路径，
## **实际的属性分布会被那条退化路径悄悄改写**，而估值那边算的是别的分布。
##
## 现在这个次序和 [method PBValuation.expected_surplus] 的口径完全一致：
## 单张卡的概率 = 稀有度概率 ÷ 该稀有度的角色数。
##
## 属性因此**不再是等概率的** —— 它由角色表决定。那正是想要的：
## 「哪一系深、哪一系浅」变成了可以在 `data/` 里调的设计，而不是写死的 1/6。
## 一次抽卡掷出的**一组候选**，玩家从中挑一张（§08，M3.5-e）。
##
## ## 为什么是三选一而不是抽三次
##
## 它把抽卡**从随机变成一个决策**：补羁绊缺的那个人、补空缺的克制系、
## 还是单纯战力更高的那张 —— 那是 §09 和 §03 在准备阶段唯一的交汇点。
##
## ## 保底只保第一张
##
## 三张一起视为**一次**抽卡：保底触发时第一张钦定 SSR，另外两张照常掷。
## 三张各保各的话，保底会变成刷 SSR 的最优路径 —— 那正是
## [method roll_gacha] 里「保底只保到 SSR、不直接给 USR」防的同一件事。
##
## **消耗 `gacha` 流的次数从 1 变成 `count`。** 铁律 3 说三条流的状态进存档，
## 次数变了老存档的续跑序列就对不上 —— 这是一次破坏性改动，记在 §08。
static func roll_gacha_offer(
	wave_index: int, pity: int, cfg: PBSimConfig, rng: RandomNumberGenerator, count: int = 3
) -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for i: int in maxi(count, 1):
		# 保底只作用在第一张上，后面两张按普通概率掷。
		var effective_pity: int = pity if i == 0 else 0
		var unit := roll_gacha(wave_index, effective_pity, cfg, rng)
		if unit != null:
			out.append(unit)
	return out


## 一组候选里最高的稀有度。保底计数看它 —— **三张里有一张 SSR 就算命中**。
static func best_rarity(offer: Array[PBUnit]) -> int:
	var best: int = -1
	for unit: PBUnit in offer:
		best = maxi(best, int(unit.rarity))
	return best


## 重刷任务要多少钱（§06：`50 + 5n`，每波不限次数）。
static func quest_reroll_cost(wave_index: int, cfg: PBSimConfig) -> int:
	return int(cfg.quest_reroll_base + cfg.quest_reroll_rate * float(wave_index))


## 把一个忍者从 [param level] 级升到下一级要多少钱。已满级返回 -1。
##
## **曲线是占位值**，§07 的科技树给了四条价格曲线但没给忍者等级 ——
## 等级是 §03A 才引入的。形状抄科技树（`base × mult^Lv`），
## 因为它和科技抢的是同一笔钱，同形状才比得出来该先买哪个。
static func unit_level_cost(level: int, cfg: PBSimConfig) -> int:
	return _cost_or_capped(level, cfg.unit_level_max, cfg.unit_level_cost, cfg.unit_level_mult)


static func roll_gacha(
	wave_index: int, pity: int, cfg: PBSimConfig, rng: RandomNumberGenerator
) -> PBUnit:
	# 保底只保到 SSR，不直接给 USR —— 否则保底会变成刷 USR 的最优路径。
	if pity >= cfg.gacha_pity:
		return _draw(cfg, PBUnit.Rarity.SSR, rng)

	var row: Array = _gacha_row(wave_index)
	var roll: float = rng.randf() * 100.0
	var acc: float = 0.0
	for i: int in range(1, 5):
		acc += float(row[i])
		if roll < acc:
			return _draw(cfg, (i - 1) as PBUnit.Rarity, rng)
	return _draw(cfg, PBUnit.Rarity.R, rng)


## 在某个稀有度的角色里等概率取一个。
##
## 那一档一个角色都没有时**不能静默返回 null** —— 空卡会在几百局之后
## 表现为「某些局莫名少几张卡」，极难反推。退回相邻档（先往下找，再往上找）。
static func _draw(cfg: PBSimConfig, rarity: PBUnit.Rarity, rng: RandomNumberGenerator) -> PBUnit:
	var pool := cfg.characters.of_rarity(rarity)
	if pool.is_empty():
		pool = _nearest_pool(cfg, rarity)
	if pool.is_empty():
		push_error("角色表是空的，抽不出卡")
		return null
	return PBUnit.new(pool[rng.randi_range(0, pool.size() - 1)])


## 找离 [param rarity] 最近的非空稀有度档。先降后升 —— 降档比升档安全，
## 升档等于白送玩家一张更好的卡。
static func _nearest_pool(cfg: PBSimConfig, rarity: PBUnit.Rarity) -> Array[PBCharacter]:
	for step: int in range(1, PBUnit.Rarity.size()):
		var lower: int = int(rarity) - step
		if lower >= 0 and not cfg.characters.of_rarity(lower as PBUnit.Rarity).is_empty():
			return cfg.characters.of_rarity(lower as PBUnit.Rarity)
		var higher: int = int(rarity) + step
		if (
			higher < PBUnit.Rarity.size()
			and not cfg.characters.of_rarity(higher as PBUnit.Rarity).is_empty()
		):
			return cfg.characters.of_rarity(higher as PBUnit.Rarity)
	return [] as Array[PBCharacter]


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


## 该任务需要派出几名忍者。派遣期间他们不上场、羁绊也不生效（§06）。
static func quest_cost_units(grade: int) -> int:
	return int(QUEST_TABLE[grade][1])


static func _cost_or_capped(level: int, max_level: int, base: float, mult: float) -> int:
	if level >= max_level:
		return -1
	return int(floor(base * pow(mult, float(level))))


static func _gacha_row(wave_index: int) -> Array:
	for row: Array in GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return GACHA_TABLE[GACHA_TABLE.size() - 1]
