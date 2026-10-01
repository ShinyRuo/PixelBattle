class_name PBRunState
extends RefCounted
## 一局游戏的全部可变状态。字段名刻意与 §12 的存档 JSON 键对齐，序列化时是一层平铺映射。

## 当前波次，从 1 开始。
var wave_index: int = 1

var gold: int = 0

## 基地剩余血量。归零即本局结束，卡在的那一波就是玩家的成绩。
var base_hp: float = 0.0

## 已持有的卡。键是 [method PBUnit.key]，值是那张卡。
## 重复抽到的是另一张卡（键 `id`、`id#1`）。**认角色要走 `unit.character.id`**，不是这个键。
var roster: Dictionary = {}

## 经济那三条科技的等级（§07）。
var tech_gold: int = 0
var tech_pop: int = 0
var tech_def: int = 0

## 训练科技的等级，`{线: 等级}`，线是 [constant PBTechRules.BRANCHES] 里的一条。**空 = 一级都没升。**
## 效果不在这里算，见 [method PBCombatRules.unit_mods]。
var training: Dictionary = {}

## 上场的经济位数量。纯经济卡，占出战位但不产生任何输出（§07 的改动）。
var economy_slot_count: int = 0

## 已经掏了钱、还没挑的那一组抽卡候选（§08 的三选一）。
## **钱在掷之前就扣了**，所以必须存进状态：真人会在这里停下来想，中间可能存档、可能关掉游戏。
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

## 玩家**钦定**派谁去做任务，元素是角色 id（§06）。**空 = 按末尾规则自动派**，脚本流派一个字都不填。
##
## **只在长度刚好等于要派的人数时才算数**，否则退回末尾规则（见 [method dispatch_picks]）：
## 估值那一路会临时把 [member dispatched] 改成别的数再问一遍羁绊，它只知道「派几个」不知道「派谁」。
var dispatch_manual: Array[StringName] = []

## 本波带在场上的卡，元素是卡的键。**在场就是出战席**，由流派/玩家在准备阶段挑
## （[method PBStrategy.bring_to_field]）。
##
## 空表示还没挑过，那时按仓库顺序取 —— 现造局面的测试因此不必每次先挑一遍人。
var field: Array[StringName] = []

## 玩家**手动钦定**的出战席，元素是卡的键。**空表示「按有效战力自动排」。**
##
## 「带谁」同时决定输出、站位、装备吃不吃得下和羁绊档位，一个标量排序表达不了，所以交给玩家。
## 名单里的人**优先进在场名单**（[method PBStrategy.bring_to_field]），否则会「点上场了但羁绊不算他」。
var lineup: Array[StringName] = []

## 出战席是不是玩家手排的。**和「[member lineup] 是不是空的」是两件事。**
##
## 一开始这里没有这个字段，「空名单」直接当成「交回自动排」——
## 于是玩家把人**全部拖下场**之后，下一次刷新就把整队又自动填了回去，
## 看起来像编队页在跟人作对。空的手排名单是玩家真能到达的状态，
## 必须表示得出来。
var lineup_manual: bool = false

## 玩家**亲手**动过这份名单没有。
##
## **和 [member lineup_manual] 是两件事**：那个答「上场按名单还是按自动挑」，这个答「还要不要替他维护名单」。
## 合成一个的话只有两个都不对的选项 —— 每次刷新都按战力重排（抽到强卡时场上的人被换回仓库），
## 或者钉一次就不管（仓库从 0 人攒起，后面抽到的人进不了队）。
##
## 界面每次刷新都把名单重钉一遍，`bring_to_field` 只往空位里补人，新卡顶不掉站着的人；
## 玩家一旦自己拖过（[PBCardMoves]），这里变 true，自动维护停手。脚本流派碰不到这个字段。
var lineup_by_hand: bool = false

## 仓库里的装备配件，`{配件 id: 数量}`（§10）。
## **一个吃得下任意金币的深坑**：抽卡在卡池抽满后就没有边际价值了，装备没有那个天花板。
var equip_parts: Dictionary = {}

## 玩家**手动挂上去**的成品装备，`{卡的键: [成品 id, …]}`（§10）。**空 = 全自动分配。**
##
## **手动挂的先占位，剩下的空位仍然由贪心补满** —— 挂一件的意思是「这件给他」，
## 不是「其余的别管了」。
##
## **挂不上的条目分配时跳过，不清理**：清掉的话玩家一时凑不齐配件，之前挂的位置就永久没了。
var equipped: Dictionary = {}

## 玩家**拖出来的开战位置**，`{卡的键: Vector2}`（§02）。**空 = 按射程档自动站位。**
##
## **按键存，不按出战席下标**：换人、派任务会让后面所有人的下标挪一位，阵型整体错位一格。
## 摆到界限之外的**夹回来，不拒绝**（[method PBFormationRules.place]）—— 拒绝的话松手什么都没发生。
var formation: Dictionary = {}

## 这一局带的尾兽（§11），存 [member PBBeast.id]，**开局选定，全程不变**。
## **空表示不带**：§11 正式规则是必选一只，「不带」只是扫描时的对照组。
var beast_id: StringName = &""

## 尾兽等级（§11：`400 × 1.6^Lv` 升级，上限 10）。**从 1 起**，
## 也就是 `.tres` 里写的数就是 1 级的效果。
var beast_level: int = 1

## 尾兽大招**还欠多少 tick 的冷却**。跨波保留，进存档（§12）。
##
## 这个字段存在的全部理由是 §11 的 75 秒冷却比单波（约 16 秒）长四五倍。
## 冷却每波清零的话尾兽每波都放得出来，「在哪一波交底牌」这个决策就没了 ——
## 而那是 §11 整节的核心。详见 [member PBSkill.carry_over_ticks]。
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


## 收一张卡进仓库。**重复抽到的是另一个人**，立刻能上场。
##
## 找的是**第一个空着的序号**，不是「已有几张」：中间那格可能空出来，按张数算会撞上还在仓库里的
## 那一张，新卡直接覆盖掉旧的（字典同键）。
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
## **出任务的人不占人口**：人口是「这一波能打的人有几个」。
## 和 [method open_slots] 分开：那一个答「几个人在打」（羁绊、估值、脚本流派读它），
## 这一个答「还能不能再拖一个上去」。只数钦定的名单（[member dispatch_manual]），脚本流派不受影响。
func field_slots(cfg: PBSimConfig) -> int:
	return open_slots(cfg) + dispatch_manual.size()


## 某一条训练科技现在几级。不认识的线是 0。
func training_level(branch: StringName) -> int:
	return int(training.get(branch, 0))


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
	# 出任务的那几个不占人口，见 [method field_slots]。
	var capacity: int = field_slots(cfg)
	var out: Array[PBUnit] = []
	# **手排的空名单是空的，不是「还没挑过」**：玩家可以把人全拖下场，照旧兜底的话羁绊会按
	# 仓库前 N 个人算，而场上一个人都没有。
	if field.is_empty() and not lineup_manual:
		var pool := all_units()
		return pool.slice(0, mini(pool.size(), capacity))
	for key: StringName in field:
		var unit := roster.get(key, null) as PBUnit
		if unit != null and out.size() < capacity:
			out.append(unit)
	return out


## 现在有哪些卡在给羁绊计数（§09）：**在场的人全额生效，派出去做任务的暂时失效**（§06）。
## 后一条缺了的话「这一波我要羁绊，还是要钱」就没有代价。
## 没钦定时派出去的是出战席末尾那几个 —— 派人一定要少一个打手。
func bonded_units(cfg: PBSimConfig, preview: bool = false) -> Array[PBUnit]:
	var pool := field_units(cfg)
	# 手动准备名单还未锁入 dispatched；预览按任务栏人数算，不能借用上一波人数。
	var count: int = dispatch_manual.size() if preview else dispatched
	# 没人钦定就是纯末尾规则，走一刀切片 —— 这条路在扫描里一局要跑上万次。
	if dispatch_manual.is_empty():
		return pool.slice(0, maxi(pool.size() - count, 0))
	var away := dispatch_picks(cfg, count)
	var out: Array[PBUnit] = []
	for unit: PBUnit in pool:
		if not away.has(unit):
			out.append(unit)
	return out


## 现在会被派出去的是哪几个 —— 也就是 [method bonded_units] 拿掉的那几个。
##
## **一处算出、另一处取补集**：各写一份的话「谁失效了」和「界面上显示谁在做任务」迟早对不上。
## [param count] 是「假设派这么多人」，负数表示按 [member dispatched] 算（准备阶段预览用）。
## 钦定名单只在长度刚好等于要派的人数时算数；里面已经不在场的人跳过，凑不满就整份作废。
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


## 现在有几个人**派得出去**做任务 —— 就是在场人数，派出去的每一个都少一个打手。
##
## 公式只能有一份（界面层要问同一个问题）。**不留下限**：全队都派出去是合法（且很糟）的选择，
## 任务卡上已经写着后果，系统替玩家拦下来的话他永远不知道那条线在哪。
func dispatch_available(cfg: PBSimConfig) -> int:
	return field_units(cfg).size()


## 装备的计算全部在 [PBEquipRules] 里，本类只存 [member equip_parts] 这份仓库。


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
