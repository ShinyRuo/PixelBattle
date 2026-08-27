class_name PBUnit
extends RefCounted
## M-1 的「一张卡」抽象。
##
## **这不是 §09 的 [code]PBCharacter[/code]。** 真角色表是 `data/` 下的 `.tres`，
## 带 id、name_key、技能列表、羁绊归属。M-1 刻意不碰那些 ——
## 路线图规定这一阶段「不需要真的实现羁绊/装备，用一条成长曲线代替」。
##
## 所以这里一张卡只剩三个决定战力的维度：**稀有度、属性、星级**。
## 换句话说 M-1 里「火系 SSR」就是一张卡，不区分是谁 ——
## 这正好也符合 §14 的铁律「代码里不出现角色名字符串」，只是走得更极端。
##
## 星级来自 §08 的重复卡规则：同卡 3 张升 1 星。这里用 [member copies] 记张数，
## 星级是它的派生量，不单独存 —— 存两份迟早对不上。

## 稀有度。§08 的四档。数组下标直接对应 [member PBSimConfig.rarity_power]。
enum Rarity { R, SR, SSR, USR }

## 这张卡的输出属性。可以是 PHYSICAL —— 物理位是 §03 的保底补丁。
##
## 注意 §03 的铁律：真正的 `element` 是挂在伤害事件上的，不是挂在单位上。
## M-1 里一张卡只有一个技能，两者恰好重合，所以这里能简化成单位属性。
## M0 接真技能表时必须拆开，否则「迪达拉本体土属性但 Q 是火系」这类角色做不出来。
var element: PBElement.Type = PBElement.Type.PHYSICAL

var rarity: Rarity = Rarity.R

## 已持有的张数。第 1 张即 1 星，之后每 3 张升 1 星。
var copies: int = 1

## 同一（稀有度, 属性）格子里的第几号角色。
##
## **这个字段是必需的，不是凑数。** 没有它，一张卡的身份就只剩「稀有度 + 属性」，
## 全游戏只有 4×6 = 24 张卡，「火系 SSR」全世界仅此一张 ——
## 于是玩家永远凑不出四个克制系单位上场，§03 的换人策略在模型里被人为掐死。
##
## §09 说 PC 首发要 40+ 角色、五系分摊下来每系七八个。
## 见 [member PBSimConfig.characters_per_bucket]。
var variant: int = 0


func _init(
	unit_element: PBElement.Type = PBElement.Type.PHYSICAL,
	unit_rarity: Rarity = Rarity.R,
	unit_variant: int = 0
):
	element = unit_element
	rarity = unit_rarity
	variant = unit_variant


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
## 跟物理的 1.05 几乎没区别 —— M-1 的策略脚本必须模拟换人，否则会得出
## 「属性系统没用」的错误结论，而那是模型的错不是设计的错。
func effective_power(wave_element: PBElement.Type, cfg: PBSimConfig) -> float:
	var rel := PBElement.relation(element, wave_element)
	return power(cfg) * cfg.damage_multiplier(rel)


## 这张卡的唯一身份。M-1 用它把「同一张卡」认出来做升星。
##
## 真游戏里这里是 §09 的 `id: StringName`。M-1 用整数是因为它要当字典键
## 被查几千万次，但含义完全一致 —— 代码里不出现角色名，只认 id（§14）。
func key() -> int:
	return (int(rarity) * 8 + int(element)) * 64 + variant
