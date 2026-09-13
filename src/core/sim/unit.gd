class_name PBUnit
extends RefCounted
## 玩家手上的**一张卡**：某个 [PBCharacter] 加上这一局的等级与星级。
##
## [PBCharacter] 是角色本身（不可变、全局一份、存在 `data/`），本类是这一局里玩家持有的那张卡。

## 稀有度三档（R / SR / SSR，同原版）。
## 某一档空了会让抽卡走退化路径，悄悄改掉实际的稀有度分布（`test_every_rarity_has_someone` 拦着）。
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

## 星级，乘在基础属性上（[method PBStatRules.of]）。**重复抽到的是另一张卡**，不并进星级；
## 字段留着是因为「怎么升星」是一条会换的规则。
var star_level: int = 1

## 同一个角色的第几份（0 起）。**只用来把两张同名卡区分开**，
## 不参与任何数值 —— 见 [method key]。
var serial: int = 0

## 等级（§03A）。花金币升，不打怪掉经验 ——
## 掉经验的话「谁站前排」会决定「谁升得快」，把站位和成长两个系统绑在一起。
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


## 这张卡的每秒基础伤害（`攻击力 × 攻速`），未计属性克制与队伍倍率。**统计口径**。
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


## 在 [param wave_element] 这一波**一发普攻**打多少，已计入属性克制。
##
## 和 [method effective_power] 是同一个克制倍率的两种口径（「一下多少」vs「每秒多少」），
## **克制只在一处算**（[method PBElement.relation]），否则面板上的战力和战场上的伤害迟早脱节。
func effective_attack(
	wave_element: PBElement.Type, cfg: PBSimConfig, mods: Dictionary = {}
) -> float:
	var rel := PBElement.relation(element, wave_element)
	return stats(cfg, mods).atk * cfg.damage_multiplier(rel)


## 这张卡的唯一身份：仓库字典的键，也是存档里记「我有哪些卡」的值。
##
## **不等于角色 id**：重复抽到的忍者是另一个人，在场名单、摆位、装备、派遣四份状态存的都是这个键，
## 共用一个键的话「给这个人挂一件装备」会同时挂到另一个身上。
## 第一张是光秃秃的角色 id，重复的带 `#1`、`#2`。
##
## **认角色要用 `character.id`**：羁绊按角色算（[method PBBondRules.active_count]），
## 拿这个键去比的表现是「重复卡刷满羁绊」。
func key() -> StringName:
	return character.id if serial <= 0 else StringName("%s#%d" % [character.id, serial])
