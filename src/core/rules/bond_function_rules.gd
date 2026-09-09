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
	CARRIER,  ## 开波只给载体本人乘死一份（触发型：重生 / 溅射 / 命中后提暴击）
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

# ── 触发型（M10-d）─────────────────────────────────────────────
#
# 这四个是 [enum Landing] 的 `CARRIER` 档：**只发给载体本人**，
# 不像暴击光环那样发给全队。M3-f 那条「一组羁绊只出一个载体」因此
# 原样成立，而且这一档比大招那一档更贴近它 —— 前五个至少还要玩家
# 手动放一发大招才兑现，这四个是他站在场上就一直在发生的事。
#
# **§7 那 15 组没有功能键的羁绊里，只有这四组做得出来。** 其余的机制
# 是「强化某个角色的某个技能」（豪火球附带天照、月读控两个目标……），
# 而 49 个角色里配了技能的是 2 个 —— 卡的不是缺一个键，
# 是被强化的对象根本不存在。见《开发路线图》M10-d 那一节。

## 命中之后短时提暴击（§7 的 B10 绝牛雷犁热刀）。
## 落点是 [member PBAttacker.crit_on_hit]。
##
## **它是暴击系统真正有意思的那一半**：M10-c 那三组给的是常驻光环，
## 而常驻光环本质上仍然是「更大的百分比」—— §09 要的是机制，
## 而「打中了才有、停手就没」才是一个玩家能感知、也能主动利用的东西。
const CRIT_ON_HIT: StringName = &"crit_on_hit"

## 普攻附带范围伤害（§7 的 B15 神赐予的伤痛）。
## 落点是 [member PBAttacker.splash_damage]。
const SPLASH: StringName = &"splash"

# ── 功能档的量（M3-f 定的数，M12-a 从 [PBSimConfig] 搬过来）───────
#
# 这几个数**不是配平出来的**，是把 §09 的文字描述落成可跑的量。
# 现在调它们没有依据：功能的价值取决于「一次能拖到多少人」，
# 而那要等 `attack_shape` 分配之后才量得出来（见路线图那条共同下游）。
#
# **为什么从配置里搬出来。** [PBSimConfig] 顶上写着自己装的是
# 「批量扫描每局一份副本」要改的参数，而这六个从 M3-f 落地至今
# 一条扫描都没改过，只有三处读点；而那个文件当时正卡在 1000 行上限。
# 同 M10-c 把暴击那三个数放在 [PBCritRules] 上。
# 真要扫它们的那天再搬回去，**但别搬成嵌套对象** ——
# [method PBSimConfig.clone] 是反射逐字段拷贝的，嵌套那份会按引用共享。

## [constant PULL] 把大招半径放大几倍。
##
## 吸附强化的是**够得着多远**，不是伤害 —— 它的产出是给别人创造命中数。
const PULL_RADIUS_SCALE: float = 2.0

## [constant ROOT] 定住多少秒。
##
## **短是有依据的。** M3-d 实测：每波一发的全屏定身会把行军队列压扁成一堆，
## 解除的那一刻整群同时涌进交战区，恰好抵消掉 M3-a「射程梯度把敌人分批处理」
## 的收益 —— 一尾、五尾因此测出来比不带尾兽还差。定身在这里是一个
## 「攒一波集火窗口」的短操作，不是「让敌人别动」的长控场。
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
const HEAVY_HIT: StringName = &"heavy_hit"

## 阵亡时原地重生一次（§7 的 B02 不死二人组）。
## 落点是 [member PBAttacker.revives_max]。
##
## **判据在 [method PBAttacker.take_damage] 里面，不在调用方** ——
## 己方阵亡有两个落点（近战那一记、敌人的子弹命中），各判一次的表现是
## 「被子弹打死就复活不了」，而它不报错。
const REVIVE: StringName = &"revive"

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

## [enum Landing] 为 `CARRIER` 的那几个。见 [method apply_to_carrier]。
const CARRIER_KEYS: Array[StringName] = [CRIT_ON_HIT, SPLASH, HEAVY_HIT, REVIVE]

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
	if CARRIER_KEYS.has(key):
		return Landing.CARRIER
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


## 把一个 [enum Landing] 为 `CARRIER` 的功能装到**载体本人**身上（M10-d）。
## 返回 false 表示这个键不归它管。
##
## ## 为什么它要在建人的循环**里面**，而全队光环在循环外面
##
## 两者的判据不同：光环是「这一组羁绊给的」，跟具体哪个人无关；
## 而这一档要认人 —— 而**只有那个循环里才知道这个攻击者对应哪个角色 id**
## （[PBAttacker] 上没有、也不该有角色 id，铁律 5）。
## 搬到循环外面就要再造一份「攻击者 ↔ 角色」的对照表，
## 而那份表和出战席顺序对不上的表现是「羁绊的机制发到了别人身上」。
##
## 和 [method apply_to_skill] 同一条：改的是**已经建好的**攻击者。
static func apply_to_carrier(attacker: PBAttacker, key: StringName) -> bool:
	if attacker == null:
		return false
	match key:
		CRIT_ON_HIT:
			attacker.crit_on_hit += PBStrikeRules.BOND_CRIT_ON_HIT
		SPLASH:
			attacker.splash_damage += PBStrikeRules.BOND_SPLASH
		HEAVY_HIT:
			attacker.heavy_bonus += PBStrikeRules.BOND_HEAVY_BONUS
		REVIVE:
			attacker.revives_max += PBStrikeRules.BOND_REVIVES
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
