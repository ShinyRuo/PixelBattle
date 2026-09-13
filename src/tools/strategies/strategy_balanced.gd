class_name PBStratBalanced
extends PBStrategy
## 均衡流派：经济打底、战力跟上、每波换克制系。也是其余几个流派的花钱基线。
##
## 花钱顺序是有理由的，不是随手排的：
##
## 1. **金币科技先升到一个档位就停。** §07 要求「第一个金币科技 3–4 波回本」，
##    价格曲线 `120 × 1.35^Lv` 越往后越贵、回本越慢。无脑升满会饿死战力，
##    正是 §07 说的「纯经济开局在 8–12 波必然崩盘」。
## 2. **人口科技只在坐不下的时候买。** 位置空着买位置是纯亏。
## 3. **训练科技与抽卡比价。** 谁便宜先买谁 —— 训练是确定的词条，
##    抽卡是期望更高但方差大的一发。前期科技便宜，后期抽卡相对更划算，
##    这个交叉点自己会浮现，不用写死。

## 金币科技升到几级就停。
var gold_tech_target: int = 6

## 每条训练科技升到几级就停。
var training_target: int = PBTechRules.MAX_LEVEL


func _init() -> void:
	id = &"balanced"
	dispatch_policy = Dispatch.SMART


func prepare(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
	_buy_economy(state, cfg)
	_buy_population(state, cfg)
	_buy_power(state, wave, cfg, rng)


## 金币科技升到 [member gold_tech_target] 就收手。
func _buy_economy(state: PBRunState, cfg: PBSimConfig) -> void:
	while state.tech_gold < gold_tech_target:
		if not buy_tech(state, &"gold", cfg):
			return


## 仓库里的卡多到出战席都坐不下时，才值得开位置。
func _buy_population(state: PBRunState, cfg: PBSimConfig) -> void:
	while state.roster.size() > state.deploy_capacity(cfg):
		if not buy_tech(state, &"pop", cfg):
			return


## 剩下的钱换战力。逻辑在基类，`pure_power` 用的是同一套 ——
## 这样两者的差别只剩「升不升金币科技」这一个变量。
func _buy_power(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
	spend_on_power(state, wave, cfg, rng, training_target)
