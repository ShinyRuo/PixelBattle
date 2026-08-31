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
## 下面这几个键全部落在 [PBUltimate] 已有的字段上（`gather` / `slow_scale` /
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
## 和定身是同一个机制的两个极端（[member PBUltimate.slow_scale] 取 0 或取 0.5），
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

## 全部合法的功能键。[PBBondTable] 用它拦下拼错的键 ——
## 拼错了不会报错，只会静默地什么都不发生，而那种 bug 从现象反推不出来。
const ALL: Array[StringName] = [GATHER, PULL, ROOT, SLOW_FIELD, GOLD_FLOOR]


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 这个键是不是落在大招上的（其余的落在别处，目前只有 [constant GOLD_FLOOR]）。
static func is_combat(key: StringName) -> bool:
	return key != GOLD_FLOOR and is_known(key)


## 把一个功能装到载体的大招上。返回 false 表示这个键不归大招管。
##
## 改的是**已经建好的** [PBUltimate]，而不是在建造时分支：
## 建造那一步（[method PBCombatRules._build_ultimate]）管的是伤害与冷却，
## 和「这个人恰好在一组凑满的羁绊里」是两件独立的事，
## 混在一起写会让大招的基础属性依赖队伍构成，之后谁都不敢改其中一边。
static func apply_to_ultimate(ult: PBUltimate, key: StringName, cfg: PBSimConfig) -> bool:
	if ult == null:
		return false
	match key:
		GATHER:
			ult.gather = true
		PULL:
			ult.gather = true
			ult.radius *= cfg.bond_pull_radius_scale
		ROOT:
			ult.slow_scale = 0.0
			ult.slow_ticks = _to_ticks(cfg.bond_root_seconds, cfg)
			ult.team_damage_scale = cfg.bond_root_damage_scale
			# 增伤窗口 = 定身窗口。§09 的原话是「控制期间」，不是「另算一段」。
			ult.buff_ticks = ult.slow_ticks
		SLOW_FIELD:
			ult.slow_scale = cfg.bond_slow_scale
			ult.slow_ticks = _to_ticks(cfg.bond_slow_seconds, cfg)
		_:
			return false
	return true


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
