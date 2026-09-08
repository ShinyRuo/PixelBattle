class_name PBWaveRules
extends RefCounted
## 波次生成规则。施工策划案 §04。
##
## 输入波次序号 + 配置 + 一条 RNG 流，输出一个 [PBWave]。全部 static，无状态。
##
## 唯一的随机来源是波型，走 `quest` 流（§12 把「任务刷新与波型」划给同一条流）。
## 属性轮转、成长曲线、奖金都是波次序号的纯函数 —— 这是刻意的：
## 玩家必须能提前规划五系覆盖，属性要是随机的，§03 的整套克制策略就无从谈起。

## 敌方属性轮转顺序，无限循环。前五个沿用原版（§04），**物理是 M9-f 加的**。
## 每 6 波一个完整周期，逼玩家长期维持五系覆盖 —— 这是阻止阵容固化的唯一机制。
##
## ## 物理为什么在这里（玩家定的）
##
## 怪物按「5 属性 + 物理」分成 6 大类（M9-c），而在这之前
## **物理波在模型里根本不存在** —— 轮转只有五系，[member PBWave.element]
## 因此永远不是 [constant PBElement.Type.PHYSICAL]，那 5 张物理怪的皮
## 一只都刷不出来。而它不报错：[method PBEnemyPool.skin_key] 照样拼得出键，
## 只是那个键这辈子没人查。
##
## ## 追加在末尾，不插在中间
##
## 这样前 5 波（火雷水土风）**一字不差**，第 6 波起才开始移位。
## 插在中间的话第 1 波就变了，而那是全部既有配平数字的锚点。
##
## ## 物理波是克制系统的空档，这是它的定义不是缺陷
##
## [method PBElement.relation] 里 `defender == PHYSICAL` 恒为 `NEUTRAL` ——
## 也就是**这一波谁都不吃克制、谁也不被废**，属性忍者全按 1.0 算，
## 物理忍者按 `MULT_PHYSICAL` 算。物理系第一次有了自己的主场，
## 代价是 §03 的换人策略每 6 波空一次。1.05 够不够归数值回归。
##
## > **⚠ 顺带把 BOSS 的属性换了一批。** BOSS 每 [constant BOSS_EVERY] 波，
## > 而 `(10k − 1) mod 6` 恒落在 {1, 3, 5} —— **只有三格轮得到 BOSS**，
## > 且与本数组怎么排序无关（`gcd(10, 6) = 2` 决定的）。
## > 加物理之前更糟：周期是 5，10 是它的倍数，于是**每一个 BOSS 波都是风系**。
## > 要六种 BOSS 都见得到，得把 [constant BOSS_EVERY] 换成和 6 互质的数（11 最近），
## > 那是另一条决策。
const WAVE_ELEMENTS: Array[int] = [
	PBElement.Type.FIRE,
	PBElement.Type.THUNDER,
	PBElement.Type.WATER,
	PBElement.Type.EARTH,
	PBElement.Type.WIND,
	PBElement.Type.PHYSICAL,
]

## BOSS 波周期。清空后是存档点也是收工点（§01）。
const BOSS_EVERY: int = 10

## 大 BOSS 周期。多阶段，属性在阶段间切换，强制备齐多系。
const MEGA_BOSS_EVERY: int = 50


## 第 [param wave_index] 波敌人的属性。波次从 1 开始。
static func element_of(wave_index: int) -> PBElement.Type:
	var slot: int = (wave_index - 1) % WAVE_ELEMENTS.size()
	return WAVE_ELEMENTS[slot] as PBElement.Type


## 打第 [param wave_index] 波该带什么属性 —— §03 的「覆盖度」算的就是这个。
##
## **物理波答的是「物理」**（[method PBElement.counter_of] 的兜底分支）：
## 没有任何属性克制得了它，而物理忍者在那一波是全场唯一不吃 1.0 的人。
static func counter_element_of(wave_index: int) -> PBElement.Type:
	return PBElement.counter_of(element_of(wave_index))


## 掷本波波型。BOSS 波不掷骰，由波次序号直接决定。
static func roll_shape(
	wave_index: int, cfg: PBSimConfig, rng: RandomNumberGenerator
) -> PBWave.Shape:
	if wave_index % MEGA_BOSS_EVERY == 0:
		return PBWave.Shape.MEGA_BOSS
	if wave_index % BOSS_EVERY == 0:
		return PBWave.Shape.BOSS
	var total: int = cfg.shape_weight_normal + cfg.shape_weight_swarm + cfg.shape_weight_elite
	var roll: int = rng.randi_range(1, total)
	if roll <= cfg.shape_weight_normal:
		return PBWave.Shape.NORMAL
	if roll <= cfg.shape_weight_normal + cfg.shape_weight_swarm:
		return PBWave.Shape.SWARM
	return PBWave.Shape.ELITE


## 构造第 [param wave_index] 波的完整参数。
static func build(wave_index: int, cfg: PBSimConfig, rng: RandomNumberGenerator) -> PBWave:
	var wave := PBWave.new()
	wave.index = wave_index
	wave.element = element_of(wave_index)
	wave.shape = roll_shape(wave_index, cfg, rng)

	# 血量与攻击共用同一条指数曲线；波型倍率只作用在血量上。
	var scale: float = growth_scale(wave_index, cfg)
	wave.hp_each = cfg.hp_base * scale * cfg.shape_hp_mult(wave.shape)
	wave.atk_each = cfg.atk_base * scale
	wave.count = count_of(wave_index, cfg, wave.shape)
	wave.reward_gold = cfg.gold_base + cfg.gold_rate * wave_index
	return wave


## 第 [param wave_index] 波的成长倍数 `GROWTH^(n-1)`。第 1 波恒为 1.0。
static func growth_scale(wave_index: int, cfg: PBSimConfig) -> float:
	return pow(cfg.growth, wave_index - 1)


## 本波敌人数量，已叠加波型倍率并被 `count_cap` 钳死。
static func count_of(wave_index: int, cfg: PBSimConfig, shape: PBWave.Shape) -> int:
	if shape == PBWave.Shape.MEGA_BOSS:
		return cfg.mega_boss_count
	if shape == PBWave.Shape.BOSS:
		return cfg.boss_count
	var raw: float = (cfg.count_base + wave_index * cfg.count_rate) * cfg.shape_count_mult(shape)
	# 至少 1 个：精英波 ×0.3 在低波次会算出不到 1 的数，取整后变成空波。
	return clampi(int(floor(raw)), 1, cfg.count_cap)
