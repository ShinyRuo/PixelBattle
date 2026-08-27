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
## 3. **攻击科技与抽卡比价。** 谁便宜先买谁 —— 攻击科技是确定的 +6%，
##    抽卡是期望更高但方差大的一发。前期科技便宜，后期抽卡相对更划算，
##    这个交叉点自己会浮现，不用写死。

## 金币科技升到几级就停。
var gold_tech_target: int = 6

## 攻击科技的上限。
var atk_tech_target: int = 15


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


## 仓库里的卡多到出战席加待命台都坐不下时，才值得开位置。
func _buy_population(state: PBRunState, cfg: PBSimConfig) -> void:
	while state.roster.size() > state.deploy_capacity(cfg) + state.standby_capacity(cfg):
		if not buy_tech(state, &"pop", cfg):
			return


## 剩下的钱在「攻击科技」和「抽卡」之间比价，一直花到买不动为止。
func _buy_power(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
	while true:
		var atk_cost := PBEconomyRules.tech_cost(&"atk", state.tech_atk, cfg)
		var tech_is_cheaper: bool = (
			atk_cost >= 0 and atk_cost <= cfg.gacha_cost and state.tech_atk < atk_tech_target
		)
		if tech_is_cheaper:
			if not buy_tech(state, &"atk", cfg):
				return
		elif not pull_once(state, wave, cfg, rng):
			return
