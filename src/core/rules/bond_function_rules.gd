class_name PBBondFunctionRules
extends RefCounted
## 羁绊功能档的词汇表与结算（§09，M3-f）。全部 static，无状态，零引擎依赖。
##
## ## 这一节要解决的是一条结构性冲突，不是「再加几个数」
##
## M2 量出来：属性型兜底羁绊按属性匹配，在场 16 张卡摊到六个属性，
## 平均每系 2.7 个，**大部分兜底档自动激活**。不会凑羁绊的玩家白拿 1.705×，
## 会凑的 2.393× —— 技能阶梯只有 1.27×，而 §01 要 2×。
##
## 根因不是数值没调好：**「兜底」的定义是「不用会玩也能拿到」，
## 「技能阶梯」的定义是「会玩才拿得到」**，在只有倍率一种货币时两者对拉。
## 削兜底伤可玩性，加满档会通胀，怎么调都是同一个池子。
##
## 出路是**换一种货币**：让高手的优势离开倍率、进入机制。
## 聚拢、定身、减速这些东西不会自动发生 —— 它们要玩家把载体排进出战席、
## 在对的时候把大招放在对的地方。不会玩的人凑满了档也吃不到，
## 而那正是「阶梯」的定义。
##
## ## 词汇表是从 M3-d 借来的，不是新造的
##
## 下面这几个键全部落在 [PBSkill] 已有的字段上（`gather` / `slow_scale` /
## `team_damage_scale` / `radius`）—— 那几个字段是 §11 的机制型尾兽在 M3-d
## 加的，当时就写着「**同时也是 §09 功能档要的那套词汇**」。
##
## 所以这里没有第二套落点判定、第二套减速计时。多一套的话，
## 「羁绊的定身」和「尾兽的定身」迟早在半径或时序上对不上，而那种分叉不报错。
##
## ## 一条 M3-d 实测到的教训，直接影响这里的取值
##
## 每波一发的**全屏定身**（一尾、五尾）会把行军队列压扁成一堆，
## 减速一结束整群同时涌进交战区 —— 恰好抵消掉 M3-a「射程梯度把敌人分批处理」
## 的收益，测出来比不带尾兽还差。所以 [member PBSimConfig.bond_root_seconds]
## 取的是 2 秒这种短窗口，**不是越长越好**。

## 一个功能兑现在哪儿。M10-c 之前只有其中两种，而且没人问过。
enum Landing {
	SKILL,  ## 装在载体的大招上（聚拢 / 吸附 / 定身 / 减速）
	TEAM,  ## 开波给全队每个人乘死一份（暴击光环）
	ECONOMY,  ## 不进战斗（金币不再倒扣）
}

## 聚拢：载体的大招落地时把半径内的敌人拖到落点（§02 的「拉拽」）。
const GATHER: StringName = &"gather"

## 单点吸附：聚拢 + 半径放大。§09 给第七班的 3 档，是聚拢的强化形态。
##
## 强化的是**够得着多远**而不是伤害 —— 吸附的价值全在「一次能拖多少人过来」，
## 那是给别人创造命中数，不是自己多打一点。
const PULL: StringName = &"pull"

## 定身：落地后全场停住一小会儿，**且定身期间全队增伤**。
##
## 一个键带两件事，是因为 §09 把它们写成同一条功能
## （「鹿丸大招定身，井野控制期间敌人受伤 +30%」）——
## 那个 +30% 的条件正是这段定身窗口，拆成两个键就要再发明一套
## 「谁的窗口」的对应关系，而它本来就只有一个窗口。
const ROOT: StringName = &"root"

## 减速力场：落地后全场减速，持续时间比 [constant ROOT] 长得多。
##
## 和定身是同一个机制的两个极端（[member PBSkill.slow_scale] 取 0 或取 0.5），
## 走同一个字段是有意的：它们在战斗层的差别只有「多狠」和「多久」。
const SLOW_FIELD: StringName = &"slow_field"

## 金币不再倒扣：击杀掉落的负收益档不再触发，且正收益提高。
##
## **这是唯一一个不落在大招上的功能**（§09 给木叶三忍那一档的原话是
## 「金币收益提升，且负收益不再触发」；带它的是哪个角色写在 `data/` 里，
## 不写进这里 —— 铁律 5）。
## §07 白纸黑字写着那台老虎机「原版保留不动，别去修」——
## 它稳赚却包装成会扣钱，用体感波动换注意力。本功能不是去修它，
## 而是**把「关掉波动」做成一个要凑齐羁绊才拿得到的选项**，
## 那条设计和它的解药同时在场，玩家自己选。
const GOLD_FLOOR: StringName = &"gold_floor"

## 全队暴击率光环（§7 的 B13 兄弟的爱恨 / B16 幕后黑手，M10-c）。
##
## **这是第一个不落在大招上的战斗功能。** 前面五个的规矩是
## 「一组羁绊只出一个载体」，理由是「发给全组就又变回乘以人数的倍率」——
## 而光环恰恰**不随人数放大**：凑满这一组给的就是那一个定值，
## 队里站 4 个还是 10 个一模一样。所以那条理由在这里不成立，
## 但另一条仍然要守：**载体必须真的在场**（[method PBBondRules.active_functions]
## 那道门槛一个字不改）——他是把光环带进场的人。
##
## 落点是 [member PBAttacker.crit_chance]，不是效果袋 —— 袋子是同 id
## 整份覆盖的，两组羁绊各挂一份会静默吃掉一份。见 [PBCritRules]。
const CRIT_CHANCE: StringName = &"crit_chance"

## 全队暴击伤害光环（§7 的 B21 晓组织全员，M10-c）。落点是
## [member PBAttacker.crit_bonus]，理由同 [constant CRIT_CHANCE]。
const CRIT_DAMAGE: StringName = &"crit_damage"

## 全部合法的功能键。[PBBondTable] 用它拦下拼错的键 ——
## 拼错了不会报错，只会静默地什么都不发生，而那种 bug 从现象反推不出来。
const ALL: Array[StringName] = [
	GATHER, PULL, ROOT, SLOW_FIELD, GOLD_FLOOR, CRIT_CHANCE, CRIT_DAMAGE
]

## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 这个功能兑现在哪儿。
##
## ## 它守着一条断言，不只是分类
##
## **落在大招上的键不许被两组羁绊共用**：一个大招只有一份，两组配同一个
## 就是少了一个机制，而 §09 要的正是「每组一个**不同**的机制」。
## 落在全队的光环反过来 —— 它是加法叠加的，B13 和 B16 各带一份
## 说得通。`test_bond_function.gd` 的那条断言按这个分类收窄。
##
## M10-c 之前这里是 `is_combat`，把「不是金币就是大招」写死了。
## 那个函数**一个调用者都没有**，所以它错着也没人知道。
static func landing_of(key: StringName) -> Landing:
	if key == GOLD_FLOOR:
		return Landing.ECONOMY
	if key == CRIT_CHANCE or key == CRIT_DAMAGE:
		return Landing.TEAM
	return Landing.SKILL


## 把一个功能装到载体的大招（0 号技能）上。返回 false 表示这个键不归它管。
##
## 改的是**已经建好的** [PBSkill]，而不是在建造时分支：
## 建造那一步（[method PBCombatRules._build_skill]）管的是伤害与冷却，
## 和「这个人恰好在一组凑满的羁绊里」是两件独立的事，
## 混在一起写会让大招的基础属性依赖队伍构成，之后谁都不敢改其中一边。
static func apply_to_skill(skill: PBSkill, key: StringName, cfg: PBSimConfig) -> bool:
	if skill == null:
		return false
	match key:
		GATHER:
			skill.gather = true
		PULL:
			skill.gather = true
			skill.radius *= cfg.bond_pull_radius_scale
		ROOT:
			skill.slow_scale = 0.0
			skill.slow_ticks = _to_ticks(cfg.bond_root_seconds, cfg)
			skill.team_damage_scale = cfg.bond_root_damage_scale
			# 增伤窗口 = 定身窗口。§09 的原话是「控制期间」，不是「另算一段」。
			skill.buff_ticks = skill.slow_ticks
		SLOW_FIELD:
			skill.slow_scale = cfg.bond_slow_scale
			skill.slow_ticks = _to_ticks(cfg.bond_slow_seconds, cfg)
		_:
			return false
	return true


## 把 [enum Landing] 为 `TEAM` 的那几个功能发给**全队每一个人**（M10-c）。
##
## [param functions] 是 [method PBBondRules.active_functions] 的结果，
## 所以「载体在不在场」那道门槛已经过了 —— 这里只管发。
##
## ## 为什么整队一趟，而不是在建人的循环里顺手做
##
## 光环是**这一组羁绊**给的，不是**这个人**给的。放进那个循环的话，
## 载体建好之前的人拿不到、建好之后的人拿得到 ——
## 而那只表现为「站在前排的忍者暴击率好像高一点」，不报任何错。
static func apply_to_team(attackers: Array[PBAttacker], functions: Dictionary) -> void:
	for keys: Array in functions.values():
		for key: StringName in keys:
			match key:
				CRIT_CHANCE:
					for one: PBAttacker in attackers:
						one.crit_chance += PBCritRules.BOND_CRIT_CHANCE
				CRIT_DAMAGE:
					for one: PBAttacker in attackers:
						one.crit_bonus += PBCritRules.BOND_CRIT_DAMAGE


## 这份功能表里有没有人带着 [constant GOLD_FLOOR]。
##
## [param functions] 是 [method PBBondRules.active_functions] 的结果。
## 单独给一个查询函数而不是让调用方自己遍历，是因为经济结算那一路
## （[method PBEconomyRules.kill_drop_income]）只关心这一个布尔值，
## 让它去认那个字典的形状等于把数据结构泄进第二个模块。
static func grants_gold_floor(functions: Dictionary) -> bool:
	for keys: Array in functions.values():
		if keys.has(GOLD_FLOOR):
			return true
	return false


static func _to_ticks(seconds: float, cfg: PBSimConfig) -> int:
	return maxi(int(round(seconds * float(cfg.tick_rate))), 1)
