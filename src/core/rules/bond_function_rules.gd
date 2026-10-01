class_name PBBondFunctionRules
extends RefCounted
## 羁绊功能档的词汇表与结算（§09）。全部 static，无状态，零引擎依赖。
##
## ## 高手的优势放在机制里，不放在倍率里
##
## 「兜底」的定义是不用会玩也能拿到，「技能阶梯」的定义是会玩才拿得到 ——
## 只有倍率一种货币时两者对拉。聚拢、定身、减速不会自动发生：
## 要把载体排上场、在对的时候把大招放在对的地方。
##
## ## 词汇表落在 [PBSkill] 已有的字段上
##
## `gather` / `slow_scale` / `team_damage_scale` / `radius` 是机制型尾兽用的同一批字段，
## 没有第二套落点判定、第二套减速计时 —— 多一套的话「羁绊的定身」和「尾兽的定身」
## 迟早在半径或时序上对不上。

## 一个功能兑现在哪儿（[method landing_of]）。
## 「每个在场成员各拿自己那一份」的效果不在这里，走 [member PBBond.member_functions]。
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

## 全队暴击率光环。
##
## 光环**不随人数放大**（凑满给的就是一个定值），所以不受「一组只出一个载体」约束；
## 但载体仍然必须在场（[method PBBondRules.active_functions] 那道门槛）。
##
## 落点是 [member PBAttacker.crit_chance]，不是效果袋 —— 袋子同 id 整份覆盖，
## 两组羁绊各挂一份会静默吃掉一份。见 [PBCritRules]。
const CRIT_CHANCE: StringName = PBPassiveRules.CRIT_CHANCE

## 全队暴击伤害光环。落点是 [member PBAttacker.crit_bonus]，理由同 [constant CRIT_CHANCE]。
const CRIT_DAMAGE: StringName = PBPassiveRules.CRIT_DAMAGE

# ── 触发型 ──────────────────────────────────────────────────────
#
# 「他站在场上就一直在发生的事」。每个在场成员各拿各的，写在
# [member PBBond.member_functions] 里；键留在这里是因为羁绊表的 `功能键` 列
# 仍然可以点它们，量与映射都在 [PBPassiveRules]。

## 命中之后短时提暴击。落点是 [member PBAttacker.crit_on_hit]。
## 「打中了才有、停手就没」是玩家能感知、能主动利用的机制，而不是更大的百分比。
const CRIT_ON_HIT: StringName = PBPassiveRules.CRIT_ON_HIT

## 普攻附带范围伤害（§7 的 B15 神赐予的伤痛）。
## 落点是 [member PBAttacker.splash_damage]。
const SPLASH: StringName = PBPassiveRules.SPLASH

# ── 功能档的量 ──────────────────────────────────────────────────
#
# 这几个数是把 §09 的文字描述落成可跑的量，**不是配平出来的** ——
# 功能的价值取决于一次能拖到多少人，要等 `attack_shape` 分配之后才量得出来。
#
# 放在这里不放 [PBSimConfig]：它们不进批量扫描。真要扫的那天搬回去，
# **别搬成嵌套对象** —— [method PBSimConfig.clone] 反射逐字段拷贝，嵌套那份会按引用共享。

## [constant PULL] 把大招半径放大几倍。
##
## 吸附强化的是**够得着多远**，不是伤害 —— 它的产出是给别人创造命中数。
const PULL_RADIUS_SCALE: float = 2.0

## [constant ROOT] 定住多少秒。
##
## **短是有依据的**：长时间的全屏定身会把行军队列压扁成一堆，解除那一刻整群同时
## 涌进交战区，抵消掉「射程梯度把敌人分批处理」的收益。定身是攒一波集火窗口的短操作。
const ROOT_SECONDS: float = 2.0

## 定身期间全队普攻的伤害倍率。§09 猪鹿蝶：「井野控制期间敌人受伤 +30%」。
const ROOT_DAMAGE_SCALE: float = 1.3

## [constant SLOW_FIELD] 把敌人速度压到几成。
const SLOW_SCALE: float = 0.5

## 减速力场持续多少秒。比定身长得多 —— 它换的是「晚到多久」而不是集火窗口。
const SLOW_SECONDS: float = 6.0

## [constant GOLD_FLOOR] 把击杀掉落的正收益放大几倍。
const GOLD_GAIN_SCALE: float = 1.25

## 对血还很多的敌人额外多打一笔（§7 的 B05 日向兄妹）。
## 落点是 [member PBAttacker.heavy_bonus]。
const HEAVY_HIT: StringName = PBPassiveRules.HEAVY_HIT

## 阵亡时原地重生一次（§7 的 B02 不死二人组）。
## 落点是 [member PBAttacker.revives_max]。
##
## **判据在 [method PBAttacker.take_damage] 里面，不在调用方** ——
## 己方阵亡有两个落点（近战那一记、敌人的子弹命中），各判一次的表现是
## 「被子弹打死就复活不了」，而它不报错。
const REVIVE: StringName = PBPassiveRules.REVIVE

## 全部合法的功能键。[PBBondTable] 用它拦下拼错的键 ——
## 拼错了不会报错，只会静默地什么都不发生，而那种 bug 从现象反推不出来。
const ALL: Array[StringName] = [
	GATHER,
	PULL,
	ROOT,
	SLOW_FIELD,
	GOLD_FLOOR,
	CRIT_CHANCE,
	CRIT_DAMAGE,
	CRIT_ON_HIT,
	SPLASH,
	HEAVY_HIT,
	REVIVE,
]

## 羁绊表 `功能键` 那一列点到这几个时各发多少。
## **量在这里，映射在 [PBPassiveRules]** —— 两处各写映射的话，羁绊给的和角色自带的会不一样大。
const CARRIER_AMOUNTS := {
	CRIT_ON_HIT: PBStrikeRules.BOND_CRIT_ON_HIT,
	SPLASH: PBStrikeRules.BOND_SPLASH,
	HEAVY_HIT: PBStrikeRules.BOND_HEAVY_BONUS,
	REVIVE: float(PBStrikeRules.BOND_REVIVES),
}


## 这个键认不认得。
static func is_known(key: StringName) -> bool:
	return ALL.has(key)


## 这个功能兑现在哪儿。
##
## 它守着一条断言：**落在大招上的键不许被两组羁绊共用** —— 一个大招只有一份，
## 两组配同一个就少了一个机制。落在全队的光环是加法叠加的，可以共用。
## `test_bond_function.gd` 按这个分类收窄。
static func landing_of(key: StringName) -> Landing:
	if key == GOLD_FLOOR:
		return Landing.ECONOMY
	if key == CRIT_CHANCE or key == CRIT_DAMAGE:
		return Landing.TEAM
	return Landing.SKILL


## 把一个功能装到载体的大招（0 号技能）上。返回 false 表示这个键不归它管。
##
## 改的是**已经建好的** [PBSkill]：建造那一步（[method PBCombatRules._build_skill]）
## 管伤害与冷却，混进队伍构成的话大招的基础属性会依赖队伍，之后谁都不敢改。
static func apply_to_skill(skill: PBSkill, key: StringName, cfg: PBSimConfig) -> bool:
	if skill == null:
		return false
	match key:
		GATHER:
			skill.gather = true
		PULL:
			skill.gather = true
			skill.radius *= PULL_RADIUS_SCALE
		ROOT:
			skill.slow_scale = 0.0
			skill.slow_ticks = _to_ticks(ROOT_SECONDS, cfg)
			skill.team_damage_scale = ROOT_DAMAGE_SCALE
			# 增伤窗口 = 定身窗口。§09 的原话是「控制期间」，不是「另算一段」。
			skill.buff_ticks = skill.slow_ticks
		SLOW_FIELD:
			skill.slow_scale = SLOW_SCALE
			skill.slow_ticks = _to_ticks(SLOW_SECONDS, cfg)
		_:
			return false
	return true


## 把 [enum Landing] 为 `TEAM` 的功能发给**全队每一个人**。
##
## [param functions] 是 [method PBBondRules.active_functions] 的结果，载体门槛已经过了。
## **建完整队再发一趟**，不在建人循环里顺手做 —— 否则载体之前建的人拿不到光环。
static func apply_to_team(attackers: Array[PBAttacker], functions: Dictionary) -> void:
	for keys: Array in functions.values():
		for key: StringName in keys:
			match key:
				CRIT_CHANCE:
					for one: PBAttacker in attackers:
						PBPassiveRules.grant(one, key, PBCritRules.BOND_CRIT_CHANCE)
				CRIT_DAMAGE:
					for one: PBAttacker in attackers:
						PBPassiveRules.grant(one, key, PBCritRules.BOND_CRIT_DAMAGE)


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
