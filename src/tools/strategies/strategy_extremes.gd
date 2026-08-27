class_name PBStratExtremes
extends RefCounted
## 两个极端流派。§07 的配平目标直接点名了它们：
##
## > 纯经济开局在第 8–12 波必然崩盘，纯战力开局在 20 波左右因缺钱停滞。
##
## 这两条不是「希望如此」，是**验收标准**。如果模型跑出来纯经济能推到 30 波，
## 说明 §07 的「经济位 = 战力空位」硬下限根本没生效 —— 那是设计漏洞，
## 意味着最优解会收敛成「开局无脑铺经济」，整个前期决策消失。

## 上一个角都要花多少钱。
##
## §07 没给角都定价 —— 它是靠抽卡得到的角色，不是商店商品。
## M-1 折算成一次单抽的钱，因为「为了拿经济位而多抽的那几发」正是它的真实代价。
## 真正的代价其实是它占掉的那个出战位，而那一份模型里是照实算的。
const KAKUZU_COST_AS_PULLS: int = 1


## 纯经济：把钱全部投进金币科技和角都，几乎不抽卡。
##
## 预期在 8–12 波崩 —— 因为 §07 那条硬下限：低于某个清怪速度，
## 所有经济收益一起归零（打不死 → 纲手不产出 → 漏怪掉血 → 出局）。
## 经济曲线不自由，被「当前波次生存线」压着，而这条线随波次上升。
class PureEconomy:
	extends PBStrategy

	## 上几个角都就收手。再多，`k^−1.5` 的递减会让第四个几乎不产出。
	var kakuzu_target: int = 3

	## 仓库里至少留几张卡，否则真的一个人都没有，连第 1 波都过不去。
	var minimum_roster: int = 3

	func _init() -> void:
		id = &"pure_economy"
		dispatch_policy = Dispatch.ALWAYS

	func prepare(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
		# 先保证有人能上场，否则第 1 波就 DPS 为零。
		while state.roster.size() < minimum_roster:
			if not pull_once(state, wave, cfg, rng):
				return
		# 角都：占出战位换回合收入。这就是「经济位 = 战力空位」的字面实现。
		var room: int = maxi(state.deploy_capacity(cfg) - 1, 0)
		while state.kakuzu_count < mini(kakuzu_target, room):
			if not state.spend(cfg.gacha_cost * PBStratExtremes.KAKUZU_COST_AS_PULLS):
				return
			state.kakuzu_count += 1
		# 剩下的全部砸金币科技，一直升到满级。
		while true:
			if not buy_tech(state, &"gold", cfg):
				return


## 纯战力：一分钱不投经济，全部换成卡和攻击科技。
##
## 预期在 20 波左右因缺钱停滞 —— 波次奖金是线性的（`45 + 6n`），
## 而怪物血量是指数的，不升金币科技的话收入迟早追不上。
class PurePower:
	extends PBStrategy

	func _init() -> void:
		id = &"pure_power"
		dispatch_policy = Dispatch.ALWAYS

	func prepare(state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams) -> void:
		while state.roster.size() > state.deploy_capacity(cfg) + state.standby_capacity(cfg):
			if not buy_tech(state, &"pop", cfg):
				break
		# 和 balanced 用同一套花钱逻辑，唯一的差别就是上面一分钱没投金币科技。
		spend_on_power(state, wave, cfg, rng, cfg.tech_atk_max)
