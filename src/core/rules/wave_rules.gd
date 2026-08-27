class_name PBWaveRules
extends RefCounted
## 波次生成规则。施工策划案 §04。
##
## 输入波次序号 + 配置 + 一条 RNG 流，输出一个 [PBWave]。全部 static，无状态。
##
## 唯一的随机来源是波型，走 `quest` 流（§12 把「任务刷新与波型」划给同一条流）。
## 属性轮转、成长曲线、奖金都是波次序号的纯函数 —— 这是刻意的：
## 玩家必须能提前规划五系覆盖，属性要是随机的，§03 的整套克制策略就无从谈起。

## 敌方属性轮转顺序，无限循环。沿用原版，§04 声明不可改。
## 每 5 波一个完整周期，逼玩家长期维持五系覆盖 —— 这是阻止阵容固化的唯一机制。
const WAVE_ELEMENTS: Array[int] = [
	PBElement.Type.FIRE,
	PBElement.Type.THUNDER,
	PBElement.Type.WATER,
	PBElement.Type.EARTH,
	PBElement.Type.WIND,
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
