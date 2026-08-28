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
enum Rarity { R, SR, SSR, USR }

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

## 已持有的张数。第 1 张即 1 星，之后每 3 张升 1 星。
var copies: int = 1


func _init(unit_character: PBCharacter) -> void:
	character = unit_character
	element = unit_character.element
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


## 当前星级，从 1 起。§08：同卡 3 张升 1 星。
func star() -> int:
	return 1 + int(floor(float(copies - 1) / 3.0))


## 这张卡的每秒基础伤害，未计属性克制、科技、羁绊。
func power(cfg: PBSimConfig) -> float:
	var base: float = cfg.rarity_power[int(rarity)]
	return base * (1.0 + cfg.star_power_mult * float(star() - 1))


## 在 [param wave_element] 这一波的实际每秒伤害 —— 已计入属性克制。
##
## 这个函数是 §03 整套设计成立与否的支点：克制系打出 2.0，物理恒定 1.05。
## 两者差 1.9 倍，但**只有玩家真的每波换上克制系才吃得到**。
## 全员固定上场的话，五系阵容的平均倍率是 (2.0+0.5+1.0×3)/5 = 1.10，
## 跟物理的 1.05 几乎没区别 —— 模拟玩家必须模拟换人，否则会得出
## 「属性系统没用」的错误结论，而那是模型的错不是设计的错。
func effective_power(wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	var rel := PBElement.relation(element, wave_element)
	return power(cfg) * cfg.damage_multiplier(rel)


## 这张卡的唯一身份 —— 就是角色 id（§14 铁律 5）。
##
## 它是仓库字典的键，也是 §12 存档里记「我有哪些卡」的那个值。
func key() -> StringName:
	return character.id
