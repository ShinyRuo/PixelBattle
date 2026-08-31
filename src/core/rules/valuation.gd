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
			state.atk_mult(cfg),
			state.bond_mult(cfg),
			PBCombatRules.unit_multipliers(deployed, state, cfg),
			cfg
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
## ## 为什么候选是全仓而不是在场名单
##
## M2-c 到 M3.5-h 这里读的是 [method PBRunState.field_units]，因为那时
## 在场名单（出战席 + 待命台）比出战席大一截，「每波换克制系」是在那截
## 板凳里换的。**M3.5-i 删掉待命台之后在场就是出战席** ——
## 再从在场名单里挑等于从自己里面挑自己，[method deployed_for] 和
## [method deployed_by_raw_power] 会返回同一批人，
## 「换人多赚多少」恒等于 0，而 §03 整套属性系统的估值就此归零。
## 换人从此是**从仓库里换**，这里跟着改。
##
## ## 为什么要减掉派遣
##
## 待命台还在的时候派的是不上场的板凳，上场名单不受影响；
## 现在派的是在场的人，他这一波真的不打了。不减的话
## 「派了掉多少战力」只量到羁绊那一半，而少掉的那个打手才是大头 ——
## 卡面上的数会系统性偏乐观，且不报错。
static func available_units(state: PBRunState, cfg: PBSimConfig) -> Array[PBUnit]:
	var away := state.dispatch_picks(cfg)
	if away.is_empty():
		return state.all_units()
	var out: Array[PBUnit] = []
	for unit: PBUnit in state.all_units():
		if not away.has(unit):
			out.append(unit)
	return out


## 面对 [param element] 这一波，**不换人**会派谁上场 —— 按裸战力排，完全不看属性。
##
## 它和 [method deployed_for] 的差值就是 §03 整套属性系统在数值上真正值多少。
## M-1 扫描出来是 1.41 倍（`GROWTH` = 1.10），而那个数字以前只存在于扫描报告里，
## 玩家看不到。阵容面板把两条并排显示，是为了让「每波换克制系」这件事
## **在玩的时候就能感觉到**，而不是只能从策划那儿听说。
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
		state.atk_mult(cfg),
		state.bond_mult(cfg),
		PBCombatRules.unit_multipliers(units, state, cfg),
		cfg
	)


## 升一级 [param branch] 科技能让队伍 DPS 涨百分之几。
##
## [param base] 传当前的 [method mean_dps]，避免同一轮比价里重复算。
static func tech_gain(
	state: PBRunState, cfg: PBSimConfig, branch: StringName, base: float
) -> float:
	if base <= 0.0:
		return 0.0
	# 只有攻击和人口影响 DPS；金币和防御要另外的口径（见 [PBStratRational]）。
	if branch == &"atk":
		state.tech_atk += 1
		var after: float = mean_dps(state, cfg)
		state.tech_atk -= 1
		return after / base - 1.0
	if branch == &"pop":
		state.tech_pop += 1
		var after_pop: float = mean_dps(state, cfg)
		state.tech_pop -= 1
		return after_pop / base - 1.0
	return 0.0


## 买**一个忍具箱**能让队伍 DPS 涨百分之几（期望值）。
##
## ## 为什么不能直接问「多三个配件值多少」
##
## M3-c 之前配件不分种类，「凑够 N 个 = 一件成品」，所以加 N 个配件再量一次
## 就是答案。真合成树上来之后这个问法坏掉了，坏在两处：
##
## 1. **忍具箱随机出货，配方却点名要哪几种。** 加三个「配件」这件事不再有定义
## 2. **梯度是台阶状的。** 多买一个配件，十有八九什么也合不出来，
##    直接量的话收益是 0 —— 会算账的玩家于是永远不买装备，
##    而这恰恰是 §10 最怕的那个结论（「一个都不买」= 金币坑不存在）
##
## 所以改成算期望：**先看差最少的那件成品还差几个配件**，
## 每个**指定**种类的配件平均要开 `种类数` 个箱子才出一个，
## 于是「一箱的价值 = 那件成品的收益 ÷ 期望箱数」。
## 这个估计是平滑的，玩家因此能看见坡度而不是台阶。
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
## 代价有**两截**：派出去的人羁绊失效（整队一起降），而且他这一波不上场
## （少一份输出）。M3.5-i 删掉待命台之前只有前一截 —— 那时派的是板凳，
## 本来就不上场。两截都由 [method deployed_for] 一处兑现，这里只负责
## 「把 `dispatched` 改一下、量一次、改回来」。
##
## 返回的是**纯代价**，正数表示损失。收益那一半是金币，币种不同 ——
## 换算不在这里做，见 [PBQuestCard] 为什么它把两边并排显示而不合成一个数。
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
## ## 它是离线量具，不要接进界面
##
## 传了 [param attackers] 的那一路要**二分 32 次、每次跑完一整场仗**，
## 实测 457 毫秒（第 3 波 / 3 人）。`src/tools/pressure_curve.gd`
## 一局跑几十次无所谓，界面上不行 —— 准备阶段每一次点击都会重刷面板。
##
## [PBQuestCard] 曾经拿它写「本波打空要 x DPS」，代价是点一下等半秒。
## **那不是算得慢，是准备阶段去算了战斗。**
##
## 顺带记一条实测：二分到第 9 次就已经收敛，剩下 23 次在小数点后第六位上
## 反复翻 `漏 / 不漏` —— 离散出手和大招定点落地让「战斗对 dps 单调」
## 这条前提在那个精度上不成立，那 23 次量的是噪声。要再用它做在线判断，
## 先加收敛判据。
##
## ## 为什么代价要用「离悬崖多远」度量，而不是「基地掉多少血」
##
## 任务卡最初写的是「不接 基地 −0 / 接了 基地 −128」——
## **实测下来那一行在几乎每一波都读作两个相同的 0**：
## 种子 20260827 那局打到第 40 波（最后一波活着的）两边仍然都是 0，
## 第 41 波直接团灭。
##
## 根因是 M0 已经查明的：这是个**单服务器排队**，ρ<1 一个不漏、ρ>1 全线崩，
## 中间没有稳定段（路线图 §01 那条缺口，要等 M3 的射程与多目标分配）。
## 所以基地伤害这个量在悬崖前恒为 0、悬崖后一步到底，**没有分辨率**。
##
## 富余倍数有分辨率，而且它正是玩家看不见的那个东西 ——
## 不给的话整局读起来是「好好好、死」。
##
## 二分靠的是战斗结算对 dps 单调，
## 那条性质由 `test_more_dps_never_produces_more_leaks` 锁着。
##
## ## [param attackers] 决定用哪套战斗规则量这个悬崖（M3-a）
##
## 给了在场的那批攻击者，就**按真实战斗模型**二分：整队按比例缩放，
## 射程与站位结构保持不变，看缩到哪一档开始漏怪。
##
## 不给就退回解析式排队模型 —— 那是「满射程 · 单体 · 集火」下的闭式解。
## **两者在有射程之后会给出不同的悬崖**，因为射程决定了敌人在被打之前
## 要先走多远。所以凡是拿这个数去做判断的地方都该把攻击者传进来，
## 否则界面上那句「离打不动还差多远」说的是另一套战斗规则里的事。
static func leak_threshold_dps(
	wave: PBWave, def_reduction: float, cfg: PBSimConfig, attackers: Array[PBAttacker] = []
) -> float:
	# 探测要反复改 dps，所以复制一份 —— 直接改真正上场的那批会污染本波的计划。
	var squad: Array[PBAttacker] = []
	var share := PackedFloat64Array()
	var ult_share := PackedFloat64Array()
	var squad_dps: float = PBCombatRules.total_dps(attackers)
	if squad_dps > 0.0:
		for attacker: PBAttacker in attackers:
			squad.append(attacker.clone())
			share.append(attacker.dps / squad_dps)
			# 大招也要跟着等比例缩。只缩普攻的话，队伍缩得越弱大招占比越高，
			# 缩到最后是一发大招定生死 —— 那量出来的是另一支队伍的悬崖。
			ult_share.append(attacker.ultimate_damage() / squad_dps)

	var high: float = maxf(wave.hp_each, 1.0)
	var guard: int = 0
	while guard < 64 and _leaks_at(wave, high, def_reduction, cfg, squad, share, ult_share):
		high *= 2.0
		guard += 1
	if guard >= 64:
		return high
	var low: float = 0.0
	for _i: int in 32:
		var mid: float = (low + high) * 0.5
		if _leaks_at(wave, mid, def_reduction, cfg, squad, share, ult_share):
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
	ult_share: PackedFloat64Array
) -> bool:
	if squad.is_empty():
		return PBCombatRules.resolve(wave, total, def_reduction, cfg).leaked > 0
	for i: int in squad.size():
		squad[i].dps = total * share[i]
		if squad[i].ultimate != null:
			squad[i].ultimate.damage = total * ult_share[i]
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
## ## 这里踩过一个量纲错误，值得记着
##
## M2-b2 换上真羁绊表之后，这一段原本写的是
## `bond_mult_for(roster.size() + 1) / bond_mult() - 1`——
## **分子来自替身曲线（按人头），分母来自真羁绊（按组合）。**
## 两个口径相除，算出来是「再抽一张涨 32% 战力」这种数，
## 于是会算账的玩家把钱全砸进抽卡，科技和装备一概不买。
##
## 实测代价：`rational` 从 44.4 波掉到 26.3 波，反而打不过写死优先级的
## `balanced`（38.5）。而同一批扫描里每个**不用估值**的流派只掉 1–8%，
## 那个差异正是把原因锁死在这里的证据 —— 曲线下移会一起下移，
## 只有一个流派塌下去就是估值坏了。
##
## ## 现在的算法
##
## 按角色表求期望，和 [method expected_surplus] 同一套路：
## 对每个**还没有的**角色，问「多这一个成员，各组羁绊各涨多少」，
## 按抽到它的概率加权。已有的角色跳过 —— 重复卡只加星，不增加成员数。
##
## ## 一处刻意保守的近似
##
## **在场席位满了就返回 0。** 新卡挤不挤得进在场名单，取决于「谁上场」
## 这个决策，而那个决策现在还不存在（[method PBRunState.bonded_units]
## 按仓库顺序取前 N）。M2-c 开放选人之后这里要跟着换成「挤掉谁」。
## 现在取 0 是**低估**而不是高估 —— 宁可让玩家少抽一点，
## 也不要重蹈上面那个高估的覆辙。
static func expected_bond_gain(state: PBRunState, cfg: PBSimConfig) -> float:
	var units := state.bonded_units(cfg)
	if units.size() >= state.open_slots(cfg):
		return 0.0
	var base: float = 1.0 + PBBondRules.power_bonus(units, cfg.bonds)
	if base <= 0.0:
		return 0.0

	var counts := PBBondRules.counts_of(units, cfg.bonds)
	var row: Array = gacha_row(state.wave_index)
	var gain: float = 0.0
	for rarity: int in cfg.rarity_power.size():
		var chance: float = float(row[rarity + 1]) / 100.0
		var pool := cfg.characters.of_rarity(rarity as PBUnit.Rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		var per_card: float = chance / float(pool.size())
		for character: PBCharacter in pool:
			if state.roster.has(character.id):
				continue
			gain += per_card * PBBondRules.marginal_bonus(counts, cfg.bonds, character)
	return gain / base


## 面对 [param wave_element] 这一波，抽一张卡能给上场阵容多加多少输出（期望值）。
##
## **重复卡必须单独算。** 卡池只有 48 张（§08），后期手上三十几张，
## 四分之三的抽卡都是重复卡，只能加星（同卡 3 张升 1 星），收益低一个数量级。
## 把每一抽都当新卡会系统性高估后期抽卡 —— 而后期正是「该继续抽还是该转装备」
## 的分界区，偏差刚好落在结论上。
##
## 算法分两步：
##
## 1. 先按「全是新卡」把整个卡池的期望算出来
## 2. 再遍历已有的卡，把它们那一格从「新卡」换成「重复卡」
##
## **概率口径按角色表算，不按「六个属性等概率」硬编码**（M2-a）。
## 合成表上两者恒等（每个稀有度下六系均分），但真角色表的属性分布是不均匀的 ——
## 硬编码 1/6 会让估值和抽卡的实际分布悄悄对不上，且不报错。
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

	for unit: PBUnit in state.roster.values():
		var chance: float = float(row[int(unit.rarity) + 1]) / 100.0
		var pool := cfg.characters.of_rarity(unit.rarity)
		if chance <= 0.0 or pool.is_empty():
			continue
		# 抽到**这一个角色**的概率：稀有度概率 ÷ 该稀有度下的角色数。
		var p_cell: float = chance / float(pool.size())
		var mult: float = _multiplier(int(unit.element), wave_element, cfg)
		# 撤掉上一段里把这张卡当新卡算的那份。
		surplus -= p_cell * maxf(cfg.rarity_power[int(unit.rarity)] * mult - cutoff, 0.0)
		# 换成重复卡该给的：只有凑够 3 张跨过星级边界的那一抽才涨战力。
		var before: float = unit.effective_power(wave_element, cfg)
		var step: float = 0.0
		if unit.copies % 3 == 0:
			step = cfg.rarity_power[int(unit.rarity)] * cfg.star_power_mult * mult
		surplus += p_cell * (maxf(before + step - cutoff, 0.0) - maxf(before - cutoff, 0.0))
	return surplus


## §08 概率表在当前波次的那一行。表在 [PBEconomyRules]，这里只是查。
static func gacha_row(wave_index: int) -> Array:
	for row: Array in PBEconomyRules.GACHA_TABLE:
		if wave_index <= int(row[0]):
			return row
	return PBEconomyRules.GACHA_TABLE[PBEconomyRules.GACHA_TABLE.size() - 1]


static func _multiplier(element: int, wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	return cfg.damage_multiplier(PBElement.relation(element as PBElement.Type, wave_element))
