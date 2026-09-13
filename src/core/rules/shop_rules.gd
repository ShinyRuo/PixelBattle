class_name PBShopRules
extends RefCounted
## 准备阶段花钱的原语（§08 / §03A）。全部 static，零引擎依赖。
##
## 这里只放**规则**（花多少、掷什么、进不进得了仓库），不放决定 ——
## 「挑第几张」「升谁」留在 [PBStrategy]。界面手上只有 state 和 cfg，直接调这些。


## 掏钱摆出一组抽卡候选（§08 的三选一）。买不起、或手上还有没挑完的一组，
## 都返回 false。
##
## ## 为什么拆成「摆出来」和「挑一张」两步
##
## 和 [method PBRunSim.begin_wave] / [method PBRunSim.lock_plan] 拆开是同一个理由：
## **真人要在中间停下来想**，而脚本玩家是同步的。两步之间可能存档、可能关游戏，
## 所以那一组候选必须落在状态里（[member PBRunState.pending_offer]）——
## 存在返回值里的话，那笔钱就白花了。
##
## 保底计数在**摆出来**这一步就结算，看的是三张里最高的那一张 ——
## 挑哪张不影响保底，否则玩家会为了刷保底去挑差的。
static func open_offer(
	state: PBRunState, wave: PBWave, cfg: PBSimConfig, rng: PBRngStreams
) -> bool:
	# 没挑完不许再抽：允许的话玩家可以连点几次把候选覆盖掉，
	# 前几笔钱凭空消失，而账面上只是「金币怎么少了」。
	if not state.pending_offer.is_empty():
		return false
	if not state.spend(cfg.gacha_cost):
		return false
	state.pending_offer = PBEconomyRules.roll_gacha_offer(
		wave.index, state.gacha_pity, cfg, rng.gacha, cfg.gacha_offer_size
	)
	state.gacha_pulls += 1
	# **门槛走 [method PBEconomyRules.pity_rarity]，不在这里写死一档** ——
	# 它必须和保底发放的那一档是同一个数，见那个函数顶上。
	if PBEconomyRules.best_rarity(state.pending_offer) >= int(PBEconomyRules.pity_rarity()):
		state.gacha_pity = 0
	else:
		state.gacha_pity += 1
	return true


## 从摆出来的那一组里挑第 [param index] 张收进仓库，其余丢弃。
##
## **弃掉的不进任何池子、不返金币。** 给补偿的话「选哪张」的代价被抹平，
## 决策又没了 —— 那正是三选一存在的全部理由。
static func take_offer(state: PBRunState, index: int) -> bool:
	if index < 0 or index >= state.pending_offer.size():
		return false
	state.add_unit(state.pending_offer[index])
	state.pending_offer.clear()
	return true


## 把一个人加进/移出本波的派遣名单（§06）。改动了返回 true。
##
## 派谁必须是玩家能点的：代价大小完全取决于派的是谁，自动按末尾派等于系统替他做了决策。
## **手上任何一张卡都派得出去** —— 出任务不占人口（[method PBRunState.field_slots]），
## 只拦在场的人的话，人口满时是一次静默失败，而其余情形两下就能绕过。
##
## 「派出去的人必须也在 `field` 名单里」这条不变量归 [PBCardMoves] 守，
## 所以界面走 [method PBCardMoves.toggle_quest]，不直接调这里。
##
## [param capacity] 是**任务栏一共几个槽**（[constant PBEconomyRules.QUEST_SLOTS]），
## 不是本波要几个人 —— 栏位要能装下比要求更多的人，「人数不符 = 失败」才判得出来。
static func toggle_dispatch(
	state: PBRunState, unit: PBUnit, capacity: int, _cfg: PBSimConfig
) -> bool:
	if unit == null:
		return false
	var key: StringName = unit.key()
	if state.dispatch_manual.has(key):
		state.dispatch_manual.erase(key)
		return true
	if state.dispatch_manual.size() >= capacity or not state.roster.has(key):
		return false
	state.dispatch_manual.append(key)
	return true


## 开局定下这一局带哪只尾兽（§11：**开局选定，全程不变**）。
##
## 已经选过就返回 false —— 换尾兽不是一个可玩的操作。§11 把「选哪只」
## 定成整局唯一一次的决策，允许中途换的话它就退化成「哪一波用哪只」，
## 而那正好抹掉这个决策：不用取舍，全都能用上。
##
## 表里没有这个 id 也返回 false。静默按「不带」跑总好过静默按「随便哪只」跑，
## 理由见 [method PBStrategy.choose_beast]。
static func choose_beast(state: PBRunState, beast_id: StringName, cfg: PBSimConfig) -> bool:
	if state.beast_id != &"" or beast_id == &"":
		return false
	if cfg.beasts == null or cfg.beasts.by_id(beast_id) == null:
		return false
	state.beast_id = beast_id
	state.beast_level = 1
	return true


## 花金币把尾兽升一级（§11：`400 × 1.6^Lv`）。买不起或满级返回 false。
##
## 脚本流派走的是 [method PBStrategy.upgrade_beast]（一路升到目标等级），
## 界面要的是「点一下升一级」—— 两者共用的那半就是这里。
static func upgrade_beast(state: PBRunState, cfg: PBSimConfig) -> bool:
	if state.beast_id == &"":
		return false
	var cost := PBBeastRules.upgrade_cost(state.beast_level, cfg)
	if cost < 0 or not state.spend(cost):
		return false
	state.beast_level += 1
	return true


## 花金币把一个忍者升一级（§03A）。买不起或满级返回 false。
##
## **脚本流派不调它**：让扫描流派买等级会改动全部配平数字，归数值回归决定。
static func level_up(state: PBRunState, unit: PBUnit, cfg: PBSimConfig) -> bool:
	if unit == null or unit.level >= cfg.unit_level_max:
		return false
	var cost := PBEconomyRules.unit_level_cost(unit.level, cfg)
	if cost < 0 or not state.spend(cost):
		return false
	unit.level += 1
	return true
