class_name PBRunState
extends RefCounted
## 一局游戏的全部可变状态。字段与 §12 的存档结构一一对应。
##
## M-1 不实现存档（那是 M4），但字段名刻意跟存档 JSON 的键对齐 ——
## 到 M4 写序列化时就是一层平铺映射，不用先做一次结构重构。

## 当前波次，从 1 开始。
var wave_index: int = 1

var gold: int = 0

## 基地剩余血量。归零即本局结束，卡在的那一波就是玩家的成绩。
var base_hp: float = 0.0

## 已持有的卡。键是 [method PBUnit.key]，值是那张卡。
##
## **重复抽到的是另一个人**（M5-9），不再并成星级 —— 两张同名卡各占一格，
## 键分别是 `id` 和 `id#1`。认角色要走 `unit.character.id`，不是这个键。
var roster: Dictionary = {}

## 四条科技分支的等级（§07）。
var tech_gold: int = 0
var tech_pop: int = 0
var tech_atk: int = 0
var tech_def: int = 0

## 上场的经济位数量。纯经济卡，占出战位但不产生任何输出（§07 的改动）。
var economy_slot_count: int = 0

## 已经掏了钱、还没挑的那一组抽卡候选（§08 的三选一，M3.5-e）。
##
## **钱在掷之前就扣了**，所以这一组必须存进状态而不是当成一次函数调用的返回值：
## 真人玩家会在这里停下来想，中间可能存档、可能关掉游戏。
## 存在返回值里的话，那笔钱就白花了。
var pending_offer: Array[PBUnit] = []

## 本波派出去做任务的人数。派遣期间羁绊不生效（§06），波次结算后归零。
var dispatched: int = 0

## 本波派出去的**是哪几个**，元素是角色 id（§02 的战场直接操作要显示他们）。
##
## ## 这是派生记录，不是第二份真相
##
## 「谁被派出去」仍然由 [method dispatch_picks] 的末尾规则算，本字段只是
## 把那个结果记下来给界面用。**不要反过来让它决定谁失效** ——
## 那样就有两份真相了，而估值那一路（[method PBValuation.dps_if_dispatched]）
## 只知道「派几个」不知道「派谁」，它临时改 [member dispatched] 时
## 这份名单跟不上，两边会静默分叉。
var dispatched_ids: Array[StringName] = []

## 玩家**钦定**派谁去做任务，元素是角色 id（§06，M3.5-g）。**一波一份，结算时清空。**
##
## 空 = 按末尾规则自动派（板凳末尾），也就是 M2 到 M3.5-f 的行为。
## 脚本流派一个字都不填，所以全部既有配平数字不动。
##
## ## 为什么它只在「人数刚好对上」时才算数
##
## [method PBValuation.dps_if_dispatched] 那一路是**临时把 [member dispatched]
## 改成别的数**再问一遍羁绊 —— 它只知道「派几个」，不知道「派谁」。
## 这份名单要是无条件生效，那条估值路径就会拿着一份人数对不上的名单去算，
## 而结果只是「卡面上的数字略微不对」，不报错。
##
## 所以规则定成：**名单长度等于要派的人数时才用它，否则退回末尾规则。**
## 见 [method dispatch_picks]。
var dispatch_manual: Array[StringName] = []

## 本波带在场上的卡，元素是角色 id。M2-c。
##
## **M3.5-i 起「在场」就是出战席本身。** 在那之前还有一层待命台
## （不参战但羁绊全额生效，§05），于是「在场」比「上场」多一截板凳。
## 删掉它是因为战场改成直接摆位之后，屏幕上再没有一个位置能表达
## 「他在队里但不在场上」—— 而一个看不见的编制会让羁绊倍率
## 凭空多出一截来路不明的加成。
##
## **由流派/玩家在准备阶段挑**，见 [method PBStrategy.bring_to_field]。
## M2-b 之前这不是个决策 —— 在场名单按仓库顺序取前 N，也就是
## 「你先抽到谁就带谁」，于是会玩的和不会玩的拿到的羁绊一样多，
## §01 那条技能阶梯永远量不出来。
##
## 空表示还没挑过，那时仍按仓库顺序取 —— 现造局面的测试
## 因此不必每次都先挑一遍人。
var field: Array[StringName] = []

## 玩家**手动钦定**的出战席，元素是角色 id。M3-e。
##
## **空表示「按有效战力自动排」**，也就是 M1 到 M3-d 的行为。
##
## ## 为什么现在才有这个字段
##
## M1 那会儿阵容面板只展示不让选，理由是当时的伤害公式是
## `Σ(有效战力) × 科技 × 羁绊 × 装备`，后三个乘数都不依赖「上了谁」，
## 所以「按有效战力取前 N」在数学上**严格最优，没有例外** ——
## 那时开放选人不是决策，是给玩家一个犯错的机会。
##
## **M3 之后这个前提全没了**：射程与站位挂在角色上（§02，M3-a）、
## 装备逐人分配且分类匹配（§10，M3-c）、羁绊按组合而不是人头（§09，M2-b）。
## 「带谁」现在同时决定输出、站位、装备吃不吃得下和羁绊档位，
## 一个标量排序表达不了 —— 于是它成了真决策，该交给玩家。
##
## 手动名单里的人**优先进在场名单**（见 [method PBStrategy.bring_to_field]），
## 否则会出现「点上场了但羁绊不算他」这种不报错的怪事。
var lineup: Array[StringName] = []

## 出战席是不是玩家手排的。**和「[member lineup] 是不是空的」是两件事。**
##
## 一开始这里没有这个字段，「空名单」直接当成「交回自动排」——
## 于是玩家把人**全部拖下场**之后，下一次刷新就把整队又自动填了回去，
## 看起来像编队页在跟人作对。空的手排名单是玩家真能到达的状态，
## 必须表示得出来。
var lineup_manual: bool = false

## 仓库里的装备配件，`{配件 id: 数量}`（§10，M3-c）。
##
## **M3-c 之前这里是一个整数**，因为 M-1 的替身曲线不区分种类：
## 任意 `equip_parts_per_item` 个配件换一件对谁都生效的成品。
## 那条曲线丢掉了两处真实损耗 —— **忍具箱随机出货，而配方点名要哪几种**，
## 于是一定会囤下用不上的配件；以及分类不匹配的成品挂不上去。
## 两处都让装备被系统性高估，而 §10 已经把「装备定价」当成经济系统的支点。
##
## 保留的经济学身份没变：**一个吃得下任意金币的深坑**。
## 抽卡在卡池抽满后就没有边际价值了，装备没有那个天花板。
var equip_parts: Dictionary = {}

## 玩家**手动挂上去**的成品装备，`{角色 id: [成品 id, …]}`（§10，M3.5-f）。
##
## **空 = 全自动分配**，也就是 M3-c 到 M3.5-e 的行为：
## [method PBEquipRules.assign] 按加成从高到低贪心发给吃得下的人。
## 所以这个字段是**纯加法**的 —— 一个字都不填时全部既有配平数字不变，
## 而那正是它敢在数值回归之前进来的理由。
##
## ## 为什么手动的那份不是「第二套分配」
##
## 手动挂的先占位，**剩下的空位仍然由贪心补满**。分成「手动模式/自动模式」
## 两条路的话，玩家挂了一件就等于放弃了其余全部自动分配 ——
## 而他挂那一件的意思只是「这件给他」，不是「其余的别管了」。
##
## ## 挂不上的条目自动失效，不清理
##
## 配件被合成别的东西、成品数量不够、分类不匹配（法术装挂物理角色）——
## 三种情况都在分配时**直接跳过**，字段本身留着。清理掉的话，
## 玩家一时凑不齐配件，之前挂的位置就永久没了，而他并不知道发生过什么。
var equipped: Dictionary = {}

## 玩家**拖出来的开战位置**，`{角色 id: Vector2}`（§02，M4-f）。
##
## **空 = 按射程档自动站位**，也就是 M3-a 到 M4-e 的行为：
## 近战前排、远程中排、超远程后排（[method PBSimConfig.reach_column]），
## 泳道按出战席序号均分。所以这个字段是**纯加法**的 ——
## 一个人都没拖时全部既有配平数字不变，而那正是它敢在数值回归之前进来的理由。
##
## ## 为什么按 id 存，不按出战席下标
##
## 下标会变：换一个人上场、派一个人去做任务，后面所有人的下标都往前挪一位，
## 于是玩家精心摆的阵型会**整体错位一格**。而那不报错，
## 玩家只会觉得「位置怎么自己动了」。
##
## ## 摆到界限之外的会被夹回来，不是被拒绝
##
## 拒绝的话玩家拖到一半松手就什么都没发生，他不知道是没拖动还是不让摆。
## 夹回来至少把「最远只能到这」演示了一遍。见 [method PBFormationRules.place]。
var formation: Dictionary = {}

## 这一局带的尾兽（§11，M3-d）。存 [member PBBeast.id]，**开局选定，全程不变**。
##
## **空表示不带**。§11 的正式规则是开局从 9 只里必选 1，所以「不带」不是
## 一个可玩的选项 —— 它是扫描时的对照组，「选了尾兽比不选强多少」的分母。
## 默认留空是刻意的：接上尾兽这一步不该顺手改动所有既有的配平数字，
## 那样「尾兽值多少」和「配平漂了多少」就分不开了。见 [PBBeastTable] 顶部。
var beast_id: StringName = &""

## 尾兽等级（§11：`400 × 1.6^Lv` 升级，上限 10）。**从 1 起**，
## 也就是 `.tres` 里写的数就是 1 级的效果。
var beast_level: int = 1

## 尾兽大招**还欠多少 tick 的冷却**。跨波保留，进存档（§12）。
##
## 这个字段存在的全部理由是 §11 的 75 秒冷却比单波（约 16 秒）长四五倍。
## 冷却每波清零的话尾兽每波都放得出来，「在哪一波交底牌」这个决策就没了 ——
## 而那是 §11 整节的核心。详见 [member PBUltimate.carry_over_ticks]。
##
## **角色大招不需要这一份**：20 秒的冷却和单波时长同量级，
## 每波清零与不清零结果一样，而 §02 要的正是「每波每人一发」。
var beast_cooldown_ticks: int = 0

## 连续未出 SSR 及以上的抽数，用于 §08 的保底。跨波保留，本局内有效。
var gacha_pity: int = 0

# ── 统计，只写不读，供 CSV 输出 ──────────────────────────────────
var total_kills: int = 0
var total_leaked: int = 0
var gold_earned: int = 0
var gold_spent: int = 0
var gacha_pulls: int = 0
var elapsed_seconds: float = 0.0

## 每条收入流各自赚了多少。键是 [constant PBEconomyRules.GOLD_SOURCES] 里的名字。
var gold_by_source: Dictionary = {}


## 收一张卡进仓库。**重复抽到的是另一个人**（M5-9）。
##
## ## 为什么不再并成星级
##
## §08 原来的规则是「同卡 3 张升 1 星」，于是**抽到重复的等于白抽** ——
## 一张卡什么都不变（要三张才跳一次），而界面上没有任何地方显示张数，
## 玩家看到的就是「这一抽没了」。现在他多一个能上场的人，立刻用得上。
##
## 找的是**第一个空着的序号**，不是「已有几张」：卖卡、换阵容之后
## 中间那格可能空出来，按张数算会撞上还在仓库里的那一张，
## 而撞上的后果是**新抽到的卡直接覆盖掉旧的**（字典同键）。
func add_unit(unit: PBUnit) -> void:
	while roster.has(unit.key()):
		unit.serial += 1
	roster[unit.key()] = unit


func all_units() -> Array[PBUnit]:
	var out: Array[PBUnit] = []
	for unit: PBUnit in roster.values():
		out.append(unit)
	return out


## 全部卡按战力从高到低排序。
func sorted_by_power(cfg: PBSimConfig) -> Array[PBUnit]:
	var out := all_units()
	out.sort_custom(func(a: PBUnit, b: PBUnit) -> bool: return a.power(cfg) > b.power(cfg))
	return out


## 出战席容量。§05：初始 4，人口科技每级 +1，上限 10。
func deploy_capacity(cfg: PBSimConfig) -> int:
	return mini(cfg.deploy_slots_base + tech_pop, cfg.deploy_slots_max)


## 出战席里还剩几个位置能放输出 —— 经济位占着位却不产出任何伤害（§07）。
func open_slots(cfg: PBSimConfig) -> int:
	return maxi(deploy_capacity(cfg) - economy_slot_count, 0)


## 战场那块地方最多摆几个人 = 人口 + 这一波出任务的那几个。
##
## **出任务的人不占人口**（M5-9）：人口是「这一波能打的人有几个」，
## 而出任务的那几个这一波压根不在场上。占位的话，派两个人出去就等于
## **这一波少两个打手且补不上**，而玩家仓库里明明还站着人 ——
## 他看到的是「人口 4，场上只有 2 个，还加不进去」。
##
## 和 [method open_slots] 分成两个函数：那一个回答「几个人在打」
## （羁绊、估值、脚本流派挑名单全读它），这一个回答「还能不能再拖一个上去」。
## 合成一个的话，「出任务的算不算人口」这个问题会在两种语境下各要一个答案，
## 而答错的表现是**拖不上去也不报错**。
##
## 只数玩家钦定的那份名单（[member dispatch_manual]）：脚本流派恒定走
## [member dispatched] 的末尾规则，那一路一个字节都不动，
## 全部既有配平数字不变。
func field_slots(cfg: PBSimConfig) -> int:
	return open_slots(cfg) + dispatch_manual.size()


## 攻击科技的全局倍率。§07：+6%/级。
func atk_mult(cfg: PBSimConfig) -> float:
	return 1.0 + cfg.tech_atk_per_level * float(tech_atk)


## 基地减伤比例。§07 的防御科技（+4%/级）加上 §11 的尾兽光环。
##
## 尾兽那一份**当前恒为 0** —— 唯一带「全体防御」的是一尾，而己方单位
## 不会被打死，那条光环在当前模型下没有作用对象（见
## [member PBBeast.aura_def_reduction]）。接在这里而不是等以后再接，
## 是因为等敌人会还手之后它就有值了，那时改的是 `.tres` 里的数。
func def_reduction(cfg: PBSimConfig) -> float:
	var tech: float = cfg.tech_def_per_level * float(tech_def)
	var beast := PBBeastRules.beast_of(self, cfg)
	return tech + PBBeastRules.def_reduction_bonus(beast, beast_level, cfg)


## 记下这一波带上场的名单。只存 id，不存引用 —— §12 的存档要序列化这个。
func set_field(units: Array[PBUnit]) -> void:
	field.clear()
	for unit: PBUnit in units:
		field.append(unit.key())


## 在场名单对应的卡。没挑过就按仓库顺序取前 N（见 [member field]）。
func field_units(cfg: PBSimConfig) -> Array[PBUnit]:
	# **出任务的那几个不占人口**（M5-9），见 [method field_slots]。
	# `dispatch_manual` 空着时它就等于 `open_slots`，脚本流派那一路不受影响。
	var capacity: int = field_slots(cfg)
	var out: Array[PBUnit] = []
	if field.is_empty():
		var pool := all_units()
		return pool.slice(0, mini(pool.size(), capacity))
	for key: StringName in field:
		var unit := roster.get(key, null) as PBUnit
		if unit != null and out.size() < capacity:
			out.append(unit)
	return out


## 现在有哪些卡在给羁绊计数（§09）。
##
## §09 的生效规则：**在场的人全额生效、无衰减**，
## 但**派出去做任务的人羁绊暂时失效**（§06 新增）。这两条缺一不可，
## 否则 §06 那句「这一波我要羁绊，还是要钱」在模型里就没有代价，
## 派遣策略的对比（路线图第 4 个问题）会得出「派满永远最优」的假结论。
##
## **派出去的是哪几个，按末尾取。** 待命台还在的时候末尾正是板凳，
## 派遣因此不掉输出；M3.5-i 删掉板凳之后末尾就是出战席的最后一个 ——
## **派人从此一定要少一个打手**，那正是 §06 想要的那个取舍。
func bonded_units(cfg: PBSimConfig) -> Array[PBUnit]:
	var pool := field_units(cfg)
	# 没人钦定就是纯末尾规则，走原来那一刀 —— 这条路在扫描里一局要跑上万次，
	# 多一次数组遍历是实打实的开销。
	if dispatch_manual.is_empty():
		return pool.slice(0, maxi(pool.size() - dispatched, 0))
	var away := dispatch_picks(cfg)
	var out: Array[PBUnit] = []
	for unit: PBUnit in pool:
		if not away.has(unit):
			out.append(unit)
	return out


## 现在会被派出去的是哪几个 —— 也就是 [method bonded_units] 拿掉的那几个。
##
## 和 `bonded_units` 是同一条规则的两半，**故意由一处算出、另一处取补集**：
## 各写一份判断的话，「谁失效了」和「界面上显示谁在做任务」迟早对不上，
## 而那种不一致玩家一眼看得出（头像亮着但羁绊没掉），代码里却不报错。
##
## [param count] 是「假设派这么多人」，负数表示按 [member dispatched] 算。
## 准备阶段还没锁（`dispatched` 仍是 0），界面靠它预览「接了会派谁」。
##
## 玩家钦定的名单（[member dispatch_manual]）**只在长度刚好等于要派的人数时
## 才算数**，理由见那个字段。名单里已经不在场的人（换了阵容、卖了卡）
## 一律跳过，凑不满就整份作废退回末尾规则 —— 半份名单比没有名单更难解释。
func dispatch_picks(cfg: PBSimConfig, count: int = -1) -> Array[PBUnit]:
	var pool := field_units(cfg)
	var need: int = dispatched if count < 0 else count
	if need <= 0:
		return [] as Array[PBUnit]
	if dispatch_manual.size() == need:
		var picked: Array[PBUnit] = []
		for key: StringName in dispatch_manual:
			var unit := roster.get(key, null) as PBUnit
			if unit != null and pool.has(unit):
				picked.append(unit)
		if picked.size() == need:
			return picked
	# 没钦定就按在场名单的末尾取。待命台还在的时候那是板凳，
	# 现在那是出战席上排最后的那几个（见本方法与 [method bonded_units] 顶部）。
	return pool.slice(maxi(pool.size() - need, 0), pool.size())


## 羁绊加成倍率（§09）。
func bond_mult(cfg: PBSimConfig) -> float:
	return 1.0 + PBBondRules.power_bonus(bonded_units(cfg), cfg.bonds)


## 假如仓库里有 [param roster_size] 张卡，羁绊倍率会是多少。
##
## 存在的理由是**比价**：会算账的玩家要问「再抽一张值多少」，
## 而新卡的价值有一部分来自羁绊，不只是它自己的输出。
##
## **这条口径 M2-b2 要换掉。** 它按人头算，而真羁绊问的是「多的那张卡是谁」——
## 一张能补上某组羁绊满档的卡，和一张谁都不搭的卡，价值差一个数量级。
## 换成按角色表求期望（和 [method PBValuation.expected_surplus] 同一套路）是那一步的事。
## 现在留着，是因为合成羁绊表上它和 [method bond_mult] 恒等，
## `test_bond_prediction_matches_the_real_formula` 锁着这条 ——
## **那条测试在 M2-b2 会红，那正是它的用处。**
func bond_mult_for(roster_size: int, cfg: PBSimConfig) -> float:
	return 1.0 + cfg.bond_power_per_unit * float(bonded_count_for(roster_size, dispatched, cfg))


## 有几个人在给羁绊计数 —— 羁绊倍率就是拿这个数乘出来的。
##
## 单独暴露出来是给准备阶段的任务卡用：§06 的验收原话是
## 「派了羁绊掉几档，准备阶段能一眼看出」，**「档」指的就是这个计数**。
## 只显示倍率不显示档数的话，玩家看不出自己离 [member PBSimConfig.bond_unit_cap]
## 还有多远 —— 而卡池够大的时候派遣是**完全免费**的（掉的档被上限吃掉了），
## 那是这个决策里最反直觉、也最值钱的一格信息。
func bonded_count_for(roster_size: int, dispatch: int, cfg: PBSimConfig) -> int:
	var on_field: int = mini(roster_size, open_slots(cfg))
	return mini(maxi(on_field - dispatch, 0), cfg.bond_unit_cap)


## 现在有几个人**派得出去**做任务。任务卡靠它判断「派不派得出」。
##
## ## 待命台删掉之后这个数换了含义
##
## 旧口径是 `卡池 − 出战席空位`，也就是「溢出到板凳上的那几个」——
## 派遣因此从来不掉输出。现在派的一定是**在场的人**，所以这个数就是在场人数，
## 而派出去的每一个都少一个打手。§06 那句「这一波我要羁绊，还是要钱」
## 从「几乎白捡」变成了真取舍。
##
## 实现在这里而不是在 [PBStrategy] —— 界面层要问同一个问题，
## 而公式只能有一份。和 [method open_slots] 当初挪过来是同一个理由。
##
## **不留下限。** 全队都派出去是一个合法（且很糟）的选择，
## 任务卡那一行「接了 0 DPS —— 不够！会漏」已经把后果写在脸上了；
## 系统替玩家拦下来的话，他永远不知道那条线在哪。
func dispatch_available(cfg: PBSimConfig) -> int:
	return field_units(cfg).size()


## 装备的计算全部在 [PBEquipRules] 里，本类只存 [member equip_parts] 这份仓库。
##
## **M3-c 起装备是逐人的，不再是一条全队倍率**（分类匹配只有逐人才表达得出来），
## 而逐人分配要同时知道上场名单、配方表和分类规则 —— 那是规则层的事。
## 本类留成纯状态，也正好把它压回 gdlint 的公开方法数上限之内。


## 卡池里有没有能克制 [param wave_element] 的单位。
##
## §02 的第三层视觉编码「可被当前阵容克制的敌人加一圈亮边」算的就是这个 ——
## 那是玩家在战斗中最需要的即时信息。
func can_counter(wave_element: PBElement.Type) -> bool:
	var needed := PBElement.counter_of(wave_element)
	for unit: PBUnit in roster.values():
		if unit.element == needed:
			return true
	return false


## 卡池覆盖不了的输出属性 —— 即「未来一个轮转周期里，哪几波你没有克星」。
##
## §03 要求准备阶段显示「当前阵容对下一波的克制覆盖：2/5，风系空缺」。
## 这是原版最大的短板：克制关系要点开技能说明才看得到，玩家全靠背。
## 自动算出来摆在 HUD 上，是本案投入产出比最高的一处改进。
func missing_counters() -> Array[int]:
	var missing: Array[int] = []
	for wave_element: int in PBWaveRules.WAVE_ELEMENTS:
		if not can_counter(wave_element as PBElement.Type):
			missing.append(int(PBElement.counter_of(wave_element as PBElement.Type)))
	return missing


## 花钱。钱不够返回 false 且不扣款。
func spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_spent += amount
	return true


## 进账。[param source] 是 [constant PBEconomyRules.GOLD_SOURCES] 里的一条流。
##
## 分流记账是为了回答 §07 的那个失败验收：不投经济几乎没有代价，
## 但只看总收入分不出「金币科技没用」和「金币科技有用但被别的流盖过」。
func earn(amount: int, source: StringName = &"other") -> void:
	gold += amount
	if amount > 0:
		gold_earned += amount
	# 击杀掉落会掉负数，照实累计净额 —— 抹掉负值会让它看起来比实际稳。
	gold_by_source[source] = int(gold_by_source.get(source, 0)) + amount
