class_name PBValuation
extends RefCounted
## 「这一笔钱值多少战力」—— 花钱决策的估值。全部 static，无状态，零引擎依赖。
##
## ## 为什么它在 core/ 而不是在流派里
##
## 它有两个调用方，而且**两边必须给出同一个数**：
##
## - [PBStratRational]（模拟玩家）拿它比价，决定这一笔买什么
## - 准备阶段界面拿它告诉真人玩家「这一笔买下去战力涨多少」
##
## 抄成两份的话，界面上显示的数字会和批量扫描得出结论时用的口径慢慢分叉 ——
## 玩家按界面上的数做决定，而策划按扫描结论调参，两边越走越远且不报任何错。
##
## ## 口径上的两处讲究
##
## 1. **按一个轮转周期估值，不按当前这一波。** 敌方属性五波一轮（§04），
##    一张火系卡只在其中一波吃到 2.0 倍。只看当前波会系统性低估抽卡、
##    高估装备（装备是无属性加成）。
## 2. **确定性支出用「改一下、量一次、改回来」**，不推公式。
##    人口科技会同时影响上场人数和羁绊，手推的公式漏掉任何一项
##    都不会报错，只会让估值悄悄失准。


## 队伍 DPS，按五波轮转取均值。**所有估值都以它为基准。**
static func mean_dps(state: PBRunState, cfg: PBSimConfig) -> float:
	var total: float = 0.0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		var deployed := deployed_for(state, element, cfg)
		total += PBCombatRules.team_dps(
			deployed,
			element,
			state.bond_mult(cfg),
			PBCombatRules.unit_multipliers(deployed, state, cfg),
			cfg,
			PBCombatRules.unit_mods(deployed, state, cfg)
		)
	return total / float(PBWaveRules.WAVE_ELEMENTS.size())


## 面对 [param element] 这一波会派谁上场。与 [method PBStrategy.pick_by_effect] 同义，
## 只是不需要为了取属性而造一个 [PBWave]。
static func deployed_for(
	state: PBRunState, element: PBElement.Type, cfg: PBSimConfig
) -> Array[PBUnit]:
	var pool := available_units(state, cfg)
	pool.sort_custom(
		func(a: PBUnit, b: PBUnit) -> bool:
			return a.effective_power(element, cfg) > b.effective_power(element, cfg)
	)
	return pool.slice(0, state.open_slots(cfg))


## 现在还能被排上场的卡：**全仓，减掉派出去做任务的**。
##
## 候选是全仓而不是在场名单：换人是从仓库里换，从在场名单里挑等于从自己里面挑自己，
## [method deployed_for] 和 [method deployed_by_raw_power] 会返回同一批人，
## §03 属性系统的估值就此归零。
##
## 要减掉派遣：派的是在场的人，他这一波真的不打。不减的话「派了掉多少战力」
## 只量到羁绊那一半，卡面上的数系统性偏乐观。
static func available_units(state: PBRunState, cfg: PBSimConfig) -> Array[PBUnit]:
	var away := state.dispatch_picks(cfg)
	if away.is_empty():
		return state.all_units()
	var out: Array[PBUnit] = []
	for unit: PBUnit in state.all_units():
		if not away.has(unit):
			out.append(unit)
	return out


## **不换人**会派谁上场 —— 按裸战力排，完全不看属性。
## 它和 [method deployed_for] 的差值就是 §03 属性系统在数值上值多少。
static func deployed_by_raw_power(state: PBRunState, cfg: PBSimConfig) -> Array[PBUnit]:
	var pool := available_units(state, cfg)
	pool.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return pool.slice(0, state.open_slots(cfg))


## 一份名单对 [param element] 这一波打出多少 DPS。科技、羁绊、装备都计入。
static func dps_of(
	units: Array[PBUnit], element: PBElement.Type, state: PBRunState, cfg: PBSimConfig
) -> float:
	return PBCombatRules.team_dps(
		units,
		element,
		state.bond_mult(cfg),
		PBCombatRules.unit_multipliers(units, state, cfg),
		cfg,
		PBCombatRules.unit_mods(units, state, cfg)
	)


## 升一级 [param branch] 科技能让队伍 DPS 涨百分之几。
##
## [param base] 传当前的 [method mean_dps]，避免同一轮比价里重复算。
static func tech_gain(
	state: PBRunState, cfg: PBSimConfig, branch: StringName, base: float
) -> float:
	if base <= 0.0:
		return 0.0
	# 只有训练与人口影响 DPS；金币和基地防御要另外的口径（见 [PBStratRational]）。
	# 训练里**只有加攻击力 / 攻速的那两条量得出来** —— 训练防御与训练生命
	# 在这把尺子上恒为 0，归数值回归（同 [member PBAttacker.dps] 看不见防守）。
	if PBTechRules.is_branch(branch):
		var level: int = state.training_level(branch)
		state.training[branch] = level + 1
		var trained: float = mean_dps(state, cfg)
		# 改回去要**逐位还原**：0 级是「没有这个键」，留一个 0 在字典里
		# 会让「有没有升过科技」的快路径（[method PBCombatRules.unit_mods]）失效。
		if level == 0:
			state.training.erase(branch)
		else:
			state.training[branch] = level
		return trained / base - 1.0
	if branch == &"pop":
		state.tech_pop += 1
		var after_pop: float = mean_dps(state, cfg)
		state.tech_pop -= 1
		return after_pop / base - 1.0
	return 0.0


## 买**一个忍具箱**能让队伍 DPS 涨百分之几（期望值）。
##
## 不能直接问「多三个配件值多少」：忍具箱随机出货而配方点名要哪几种，
## 而且梯度是台阶状的 —— 多一个配件十有八九什么也合不出，直接量的收益是 0，
## 会算账的玩家于是永远不买装备。
##
## 所以算期望：先看差最少的那件成品还差几个配件，每个指定种类平均要开 `种类数`
## 个箱子才出一个，「一箱的价值 = 那件成品的收益 ÷ 期望箱数」。平滑，看得见坡度。
static func equip_box_gain(state: PBRunState, cfg: PBSimConfig, base: float) -> float:
	if base <= 0.0 or cfg.equipment == null:
		return 0.0
	var target := _next_equip_item(state, cfg)
	if target == null:
		return 0.0

	# 已经凑齐时按 1 算：这一箱的价值是「立刻多一件成品」，不是无穷大。
	var missing: int = maxi(_missing_parts(state, target), 1)
	var boxes: float = float(missing) * float(maxi(cfg.equipment.parts.size(), 1))
	if boxes <= 0.0:
		return 0.0

	# 把这件成品的配方直接塞进仓库，量一次，再原样退回来。
	# 「改一下、量一次、改回来」是本文件的既定口径：人口科技那类
	# 牵连多处的效果手推公式一定会漏项，而漏了不报错。
	for part_id: StringName in target.recipe:
		PBEquipRules.add_part(state.equip_parts, part_id)
	var after: float = mean_dps(state, cfg)
	for part_id: StringName in target.recipe:
		state.equip_parts[part_id] = int(state.equip_parts[part_id]) - 1
	return (after / base - 1.0) / boxes


## 还差几个配件才能合出 [param target]。
static func _missing_parts(state: PBRunState, target: PBEquipItem) -> int:
	var counted: Dictionary = {}
	var missing: int = 0
	for part_id: StringName in target.recipe:
		if counted.has(part_id):
			continue
		counted[part_id] = true
		missing += maxi(target.needs(part_id) - int(state.equip_parts.get(part_id, 0)), 0)
	return missing


## 下一件值得凑的成品：**在有人吃得下的那些里面，挑差得最少的**。
##
## 「有人吃得下」这一条是分类匹配的直接后果 —— 一队全是火系的阵容
## 去凑物理装，凑出来也挂不上，那笔钱等于扔了。
static func _next_equip_item(state: PBRunState, cfg: PBSimConfig) -> PBEquipItem:
	var deployed := deployed_by_raw_power(state, cfg)
	var synthetic: bool = cfg.equipment.is_synthetic()
	var best: PBEquipItem = null
	var best_missing: int = 0
	for entry: PBEquipItem in cfg.equipment.items:
		if entry.power <= 0.0:
			continue
		if not synthetic and not _anyone_fits(deployed, entry):
			continue
		var missing: int = _missing_parts(state, entry)
		if best == null or missing < best_missing:
			best = entry
			best_missing = missing
	return best


static func _anyone_fits(deployed: Array[PBUnit], entry: PBEquipItem) -> bool:
	for unit: PBUnit in deployed:
		if entry.fits(unit.element):
			return true
	return false


## 上一个经济位会让队伍 DPS 掉百分之几 —— 它占掉一个出战位（§07）。
##
## 返回的是**纯代价**，正数表示损失。收益那一半是金币，币种不同，
## 换算由调用方做：模拟玩家用「当前每金币战力增幅」当汇率，界面直接把两个数并列显示。
static func economy_slot_loss(state: PBRunState, cfg: PBSimConfig, base: float) -> float:
	if base <= 0.0 or state.open_slots(cfg) <= 1:
		return 1.0
	state.economy_slot_count += 1
	var after: float = mean_dps(state, cfg)
	state.economy_slot_count -= 1
	return 1.0 - after / base


## 派 [param units] 个人出去做任务，队伍 DPS 掉百分之几（§06）。
##
## 代价两截：派出去的人羁绊失效，而且他这一波不上场。两截都由 [method deployed_for]
## 兑现，这里只「把 `dispatched` 改一下、量一次、改回来」。
##
## 返回**纯代价**，正数表示损失。收益是金币，币种不同，不在这里换算（见 [PBQuestCard]）。
static func dispatch_loss(state: PBRunState, cfg: PBSimConfig, base: float, units: int) -> float:
	if base <= 0.0 or units <= 0:
		return 0.0
	var before: int = state.dispatched
	state.dispatched = before + units
	var after: float = mean_dps(state, cfg)
	state.dispatched = before
	return 1.0 - after / base


## 派 [param units] 个人出去之后，这一波还剩多少 DPS。零副作用。
##
## **走 [method PBRunState.dispatch_picks] 问「派的是谁」，和
## [method PBRunSim.lock_plan] 同一条规则。** 早先这里只改 `dispatched`
## （也就是只算羁绊那一截），注释里还挂着「它只知道派几个不知道派谁」
## 那条免责声明 —— 那在待命台还在的时候无害，因为派走的人本来就不上场。
## 现在派走的人真的从战场上消失，少那一份输出才是大头。
static func dps_if_dispatched(
	state: PBRunState, wave: PBWave, deployed: Array[PBUnit], units: int, cfg: PBSimConfig
) -> float:
	var before: int = state.dispatched
	state.dispatched = units
	var away := state.dispatch_picks(cfg, units)
	var fighting: Array[PBUnit] = []
	for unit: PBUnit in deployed:
		if not away.has(unit):
			fighting.append(unit)
	var dps: float = dps_of(fighting, wave.element, state, cfg)
	state.dispatched = before
	return dps


## 这一波的**悬崖**：DPS 低到多少就开始漏怪。
##
## **离线量具，不要接进界面**：传了 [param attackers] 的那一路要二分 32 次、
## 每次跑完一整场仗（约半秒），准备阶段每次点击都会重刷面板。
## 二分到第 9 次左右就收敛，之后在噪声里翻 —— 离散出手让「战斗对 dps 单调」
## 在那个精度上不成立。要用它做在线判断，先加收敛判据。
##
## 用「离悬崖多远」度量代价而不是「基地掉多少血」：后者在悬崖前恒为 0、
## 悬崖后一步到底，没有分辨率。二分依赖的单调性由
## `test_more_dps_never_produces_more_leaks` 锁着。
##
## 给了 [param attackers] 就按真实战斗模型二分（整队按比例缩放，站位不变）；
## 不给就退回解析式排队模型的闭式解。两者在有射程之后给出不同的悬崖。
static func leak_threshold_dps(
	wave: PBWave, def_reduction: float, cfg: PBSimConfig, attackers: Array[PBAttacker] = []
) -> float:
	# 探测要反复改 dps，所以复制一份 —— 直接改真正上场的那批会污染本波的计划。
	var squad: Array[PBAttacker] = []
	var share := PackedFloat64Array()
	# 一发多重也按同一个分母记份额：`Σ attack_i × 攻速_i` 恰好等于 `squad_dps`。
	var attack_share := PackedFloat64Array()
	var ult_share := PackedFloat64Array()
	var squad_dps: float = PBCombatRules.total_dps(attackers)
	if squad_dps > 0.0:
		for attacker: PBAttacker in attackers:
			squad.append(attacker.clone())
			share.append(attacker.dps / squad_dps)
			attack_share.append(attacker.attack / squad_dps)
			# 大招也要跟着等比例缩。只缩普攻的话，队伍缩得越弱大招占比越高，
			# 缩到最后是一发大招定生死 —— 那量出来的是另一支队伍的悬崖。
			ult_share.append(attacker.ultimate_damage() / squad_dps)

	var high: float = maxf(wave.hp_each, 1.0)
	var guard: int = 0
	while (
		guard < 64
		and _leaks_at(wave, high, def_reduction, cfg, squad, share, attack_share, ult_share)
	):
		high *= 2.0
		guard += 1
	if guard >= 64:
		return high
	var low: float = 0.0
	for _i: int in 32:
		var mid: float = (low + high) * 0.5
		if _leaks_at(wave, mid, def_reduction, cfg, squad, share, attack_share, ult_share):
			low = mid
		else:
			high = mid
	return high


## 队伍总输出是 [param total] 时，这一波漏不漏怪。
##
## [param squad] 为空走解析式排队模型；否则把整队缩放到 [param total]
## 再跑真战斗模型 —— [param share] 是每个攻击者原本占总输出的比例，
## **按比例缩放而不是均分**，否则缩放本身就改变了阵容结构，量出来的不是同一支队伍。
static func _leaks_at(
	wave: PBWave,
	total: float,
	def_reduction: float,
	cfg: PBSimConfig,
	squad: Array[PBAttacker],
	share: PackedFloat64Array,
	attack_share: PackedFloat64Array,
	ult_share: PackedFloat64Array
) -> bool:
	if squad.is_empty():
		return PBCombatRules.resolve(wave, total, def_reduction, cfg).leaked > 0
	for i: int in squad.size():
		# 一发多重也要跟着缩：战斗读的是 `attack`，只缩 dps 的话二分会收敛到上界，悬崖是假数。
		squad[i].attack = total * attack_share[i]
		squad[i].dps = total * share[i]
		if squad[i].ultimate != null:
			squad[i].ultimate.skill.damage = total * ult_share[i]
	return PBBattleSim.new(wave, total, def_reduction, cfg, squad).run_to_end().leaked > 0


## 抽一张卡的**期望**增幅。抽卡是随机的，量不出来，只能算。
##
## 拆成两项相乘：
##
## - **输出**：新卡只有挤掉当前上场阵容里最弱的那个才有价值。
##   对轮转里的每一波各算一次门槛，再对（稀有度 × 属性）求期望。
##   `max(新卡 − 门槛, 0)` 这个形式是精确的 —— 上场名单就是按有效战力取前 N，
##   加一张卡要么挤掉最弱的那个，要么完全不上场。
## - **羁绊**：板凳没坐满时，多一张卡本身就是加成（§09 的替身曲线）。
##
## 已知的一处简化：**不算保底**。快到保底时抽卡的真实期望比这里高一点。
static func gacha_gain(state: PBRunState, cfg: PBSimConfig) -> float:
	var slots: int = state.open_slots(cfg)
	if slots <= 0:
		return 0.0

	var power_gain: float = 0.0
	var counted: int = 0
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		var element := wave_element as PBElement.Type
		var deployed := deployed_for(state, element, cfg)
		var total: float = 0.0
		for unit: PBUnit in deployed:
			total += unit.effective_power(element, cfg)
		if total <= 0.0:
			# 一张卡都没有：第一张的相对增幅是无穷大，直接判定抽卡最优。
			return 1.0
		# 名单没坐满时门槛是 0 —— 新卡直接填空位，不用挤谁。
		var cutoff: float = 0.0
		if deployed.size() >= slots:
			cutoff = deployed[deployed.size() - 1].effective_power(element, cfg)
		power_gain += expected_surplus(element, cutoff, state, cfg) / total
		counted += 1
	power_gain /= float(maxi(counted, 1))

	return (1.0 + power_gain) * (1.0 + expected_bond_gain(state, cfg)) - 1.0


## 再抽一张卡对**羁绊**的期望增益（§09）。
##
## 按角色表求期望，和 [method expected_surplus] 同一套路：对每个**还没有的**角色，
## 问「多这一个成员，各组羁绊各涨多少」，按抽到它的概率加权。
##
## **分子分母必须同一个口径**（都是真羁绊表）。混用替身曲线和真羁绊的话会算出
## 「再抽一张涨 32% 战力」这种数，会算账的玩家把钱全砸进抽卡。
##
## **在场席位满了就返回 0**：新卡挤不挤得进在场名单取决于「挤掉谁」，
## 这里取 0 是低估而不是高估。
static func expected_bond_gain(state: PBRunState, cfg: PBSimConfig) -> float:
	var units := state.bonded_units(cfg)
	if units.size() >= state.open_slots(cfg):
		return 0.0
	var base: float = 1.0 + PBBondRules.power_bonus(units, cfg.bonds)
	if base <= 0.0:
		return 0.0

	var counts := PBBondRules.counts_of(units, cfg.bonds)
	var owned: Dictionary = {}
	for unit: PBUnit in state.roster.values():
		owned[unit.character.id] = true
	var row: Array = gacha_row(state.wave_index)
	var gain: float = 0.0
	for rarity: int in cfg.rarity_power.size():
		var chance: float = float(row[rarity + 1]) / 100.0
		var pool := cfg.characters.of_rarity(rarity as PBUnit.Rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		var per_card: float = chance / float(pool.size())
		for character: PBCharacter in pool:
			# 已经有这个角色了就不算：羁绊按角色数不按卡数（[method PBBondRules.active_count]）。
			if owned.has(character.id):
				continue
			gain += per_card * PBBondRules.marginal_bonus(counts, cfg.bonds, character)
	return gain / base


## 面对 [param wave_element] 这一波，抽一张卡能给上场阵容多加多少输出（期望值）。
##
## 重复抽到的是另一张卡（[method PBUnit.key]），作为战力和新卡一样；
## 它差的那一份在羁绊那一侧（[method expected_bond_gain]）。
##
## **概率按角色表算，不按「属性等概率」硬编码** —— 真角色表的属性分布不均匀，
## 硬编码会让估值和抽卡的实际分布悄悄对不上。
static func expected_surplus(
	wave_element: PBElement.Type, cutoff: float, state: PBRunState, cfg: PBSimConfig
) -> float:
	var row: Array = gacha_row(state.wave_index)
	var surplus: float = 0.0
	for rarity: int in cfg.rarity_power.size():
		var chance: float = float(row[rarity + 1]) / 100.0
		var pool := cfg.characters.of_rarity(rarity as PBUnit.Rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		var per_card: float = chance / float(pool.size())
		for character: PBCharacter in pool:
			var fresh: float = (
				cfg.rarity_power[rarity] * _multiplier(int(character.element), wave_element, cfg)
			)
			surplus += per_card * maxf(fresh - cutoff, 0.0)
	return surplus


## §08 概率表在当前波次的那一行。表在 [PBEconomyRules]，这里只是查。
static func gacha_row(wave_index: int) -> Array:
	for row: Array in PBEconomyRules.GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return PBEconomyRules.GACHA_TABLE[PBEconomyRules.GACHA_TABLE.size() - 1]


static func _multiplier(element: int, wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	return cfg.damage_multiplier(PBElement.relation(element as PBElement.Type, wave_element))
