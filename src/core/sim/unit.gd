class_name PBUnit
extends RefCounted
## 玩家手上的**一张卡**：某个 [PBCharacter] 加上「抽到了几张」。
##
## ## 和 [PBCharacter] 的分工
##
## [PBCharacter] 是角色本身 —— 不可变、全局唯一一份、存在 `data/` 的 `.tres` 里。
## 本类是**这一局里玩家持有的那张卡**，带张数与派生的星级，一局一份。
##
## M-1 到 M1 之间这里是一张 `(属性, 稀有度, 变体)` 的合成卡，没有身份。
## **M2 换成引用角色，因为羁绊是按成员 id 定义的** —— 没有身份就没有羁绊。
##
## 星级来自 §08 的重复卡规则：同卡 3 张升 1 星。这里用 [member copies] 记张数，
## 星级是它的派生量，不单独存 —— 存两份迟早对不上。

## 稀有度。§08 的四档。数组下标直接对应 [member PBSimConfig.rarity_power]。
##
## 枚举住在这里而不是 [PBCharacter]，纯粹是因为调用点都写着 `PBUnit.Rarity`。
## §09 的规格里它叫 `PBRarity.Type`，改名是零行为变化的搬迁，等有必要时再做。
## 稀有度三档。**M10-a 从四档砍成三档**（玩家定的）：原版只有 R / SR / SSR，
## 而第四档 `USR` 是我们自己加的，照抄原版名册时它一个人都摊不到 ——
## 而 `test_every_rarity_has_someone` 拦的正是「某一档空了」（空档会让抽卡
## 走退化路径，把实际的稀有度分布悄悄改掉）。
enum Rarity { R, SR, SSR }

## 这张卡是谁。**唯一的身份来源**，下面两个字段都是从它复制来的。
var character: PBCharacter

## 输出属性。**从 [member character] 复制，别单独改。**
##
## 缓存而不是每次穿透到角色，是因为 [method effective_power] 在批量扫描里
## 一局要被调几十万次，属性访问要走 getter 的话代价是实打实的。
## 角色本身不可变，所以缓存安全。
var element: PBElement.Type = PBElement.Type.PHYSICAL

## 稀有度。同样从 [member character] 复制，理由同上。
var rarity: Rarity = Rarity.R

## 防元素（§03A）。别人打它时按哪一系算克制。同样从 [member character] 复制。
var def_element: PBElement.Type = PBElement.Type.PHYSICAL

## 星级。§08 原本是「同卡 3 张升 1 星」，**M5-9 之后重复卡不再并进来** ——
## 抽到重复的忍者是**另一个人**，各自上场、各自升级、各自带装备。
##
## 字段留着是因为星级仍然乘在基础属性上（[method PBStatRules.of]），
## 而「怎么升星」是一条会换的规则；升星那条路重开时改的是**谁写它**，
## 不是整套属性计算。
var star_level: int = 1

## 同一个角色的第几份（0 起）。**只用来把两张同名卡区分开**，
## 不参与任何数值 —— 见 [method key]。
var serial: int = 0

## 等级（§03A，M3.5-a）。花金币升，不打怪掉经验 ——
## 掉经验的话「谁站前排」会顺带决定「谁升得快」，
## 而站位是射程的派生量（§02），那条链路会把两个本该独立的系统绑在一起。
var level: int = 1


func _init(unit_character: PBCharacter) -> void:
	character = unit_character
	element = unit_character.element
	def_element = unit_character.def_element
	rarity = unit_character.rarity


## 从角色表里按（属性, 稀有度, 变体）取一张卡。表里没有这一格返回 null。
##
## 抽卡和测试都走这里。**测试自己拼角色的话，会造出表里不存在的卡** ——
## 那种卡在羁绊系统眼里不属于任何一组，测出来的结论对不上实际卡池。
static func of(
	cfg: PBSimConfig, unit_element: PBElement.Type, unit_rarity: Rarity, variant: int = 0
) -> PBUnit:
	var character := cfg.characters.pick(unit_element, unit_rarity, variant)
	if character == null:
		return null
	return PBUnit.new(character)


## 当前星级，从 1 起。见 [member star_level]。
func star() -> int:
	return maxi(star_level, 1)


## 这张卡此刻的全部属性（§03A）。等级与星级都算进去了。
##
## **每次调用都重算，不缓存。** 等级会变、星级会变、以后装备和光环也会 ——
## 缓存就要处理失效，而失效漏一处的表现是「升了级战力没涨」，从现象反推不出来。
## 真成为热点时再在调用方那一层缓存，那里知道什么时候该失效。
## [param mods] 是装备、羁绊、尾兽给的**属性词条**（[PBStatRules] 那张表）。
## 空的时候每一个数逐位不变 —— 面板那几处就是这么调的。
func stats(cfg: PBSimConfig, mods: Dictionary = {}) -> PBStats:
	return PBStatRules.of(character, level, star(), cfg, mods)


## 这张卡的每秒基础伤害，未计属性克制、科技、羁绊。
##
## ## M3.5-a 起它是属性表的派生量
##
## 以前是 `rarity_power[稀有度] × 星级倍率` 一条阶梯。现在等于
## **攻击力 × 攻速**，而那两个数由 §03A 的二级属性算出来。
##
## 保留这个函数、保留「每秒伤害」这个口径，是为了让这一步成为
## **可对拍的重构**：战斗层、估值、四块面板读到的仍是同一种量，
## 换模型带来的数值变化因此可以和接线错误分开看 ——
## 本案已经这么做过四次（角色表、羁绊、装备、尾兽）。
func power(cfg: PBSimConfig, mods: Dictionary = {}) -> float:
	return stats(cfg, mods).dps()


## 在 [param wave_element] 这一波的实际每秒伤害 —— 已计入属性克制。
##
## 这个函数是 §03 整套设计成立与否的支点：克制系打出 2.0，物理恒定 1.05。
## 两者差 1.9 倍，但**只有玩家真的每波换上克制系才吃得到**。
## 全员固定上场的话，五系阵容的平均倍率是 (2.0+0.5+1.0×3)/5 = 1.10，
## 跟物理的 1.05 几乎没区别 —— 模拟玩家必须模拟换人，否则会得出
## 「属性系统没用」的错误结论，而那是模型的错不是设计的错。
func effective_power(
	wave_element: PBElement.Type, cfg: PBSimConfig, mods: Dictionary = {}
) -> float:
	var rel := PBElement.relation(element, wave_element)
	return power(cfg, mods) * cfg.damage_multiplier(rel)


## 在 [param wave_element] 这一波**一发普攻**打多少 —— 已计入属性克制（M12-c5）。
##
## 和 [method effective_power] 是同一个克制倍率的两种口径：
## 那一条是「每秒多少」（统计量），这一条是「一下多少」（战斗真正用的）。
## **克制仍然只在一处算**（[method PBElement.relation]）——
## 两处各算一遍的话，「每秒」和「一下」迟早对不上，
## 而那不报错，只表现为面板上的战力和战场上的伤害脱节。
func effective_attack(
	wave_element: PBElement.Type, cfg: PBSimConfig, mods: Dictionary = {}
) -> float:
	var rel := PBElement.relation(element, wave_element)
	return stats(cfg, mods).atk * cfg.damage_multiplier(rel)


## 这张卡的唯一身份。仓库字典的键，也是 §12 存档里记「我有哪些卡」的那个值。
##
## ## 为什么它不再等于角色 id（M5-9）
##
## **抽到重复的忍者现在是另一个人**：两个鸣人各自上场、各自升级、
## 各自带装备、各自摆位。而在场名单、摆位、装备、派遣四份状态
## 存的都是这个键 —— 两张卡共用一个键的话，「给这个鸣人挂一件装备」
## 会同时挂到另一个身上，**而且不报错**。
##
## ## 第一张仍然是光秃秃的角色 id
##
## 那让「一个角色一张卡」这个既有情形下的存档、名单、摆位一字不差 ——
## 本项目每次换身份层都这么做（角色表、羁绊、装备、尾兽四次）。
## 重复的那几张才带 `#1`、`#2`。
##
## **认角色要用 `character.id`，不是这个。** 羁绊按角色算档
## （[method PBBondRules.active_count]）、尾兽光环按角色点名
## （[member PBBeast.aura_member_ids]）—— 那些地方拿这个键去比，
## 表现是「重复卡刷满羁绊」或者「光环认不出他」。
func key() -> StringName:
	return character.id if serial <= 0 else StringName("%s#%d" % [character.id, serial])
