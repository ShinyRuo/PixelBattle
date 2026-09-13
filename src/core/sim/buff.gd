class_name PBBuff
extends Resource
## 一个效果的**定义**。对应 UE GAS 的 `GameplayEffect`。
##
## | 本案 | GAS | 是什么 |
## |---|---|---|
## | [PBBuff] | `GameplayEffect` | 定义，不可变，全局一份 |
## | [PBBuffState] | `ActiveGameplayEffect` | 一份正在生效的：到期 tick、谁给的 |
## | [PBBuffBag] | `AbilitySystemComponent` 里聚合那一半 | 一个单位身上的全部 |
##
## 定义和状态不混在一个类里：混在一起就需要「只带设定的 clone」加「reset」，
## 漏调一个就让上一场的状态漏进下一场。
##
## 是 Resource：存成 `data/buffs/` 下的 `.tres`，换皮只改数据（铁律 5）。
## `extends Resource` 不违反 core 纯度 —— 被挡住的是 `ResourceLoader`，加载在 `src/data/`。

## 瞬间 / 持续 / 周期。**这三档是三种机制，不是时长的三个取值** ——
## 持续回血写成「血上限 +X」的话，一过期血就掉回去，那是一个坏护盾。
enum Kind {
	## 当场改一次**量**（血、蓝），然后就没了。**不进 [PBBuffBag]。**
	INSTANT,
	## 在窗口内改**率**（倍率、加值）。进 bag，到期失效。
	DURATION,
	## 窗口内每 [member period_seconds] 触发一次 [constant INSTANT] 的载荷。
	## 进 bag。**持续回血走这一档，不是 [constant DURATION]。**
	PERIODIC,
}

## 全局唯一 id。**同一个 id 在一个单位身上只留一份**（决策 5：重复施放刷新时长），
## 所以它同时是 [PBBuffBag] 里的去重键。
@export var id: StringName = &""

## 查语言表用的键。显示名只在渲染层出现，`src/` 其余地方一个字都不该有。
@export var name_key: String = ""

## 查图标用的键。
@export var icon_key: String = ""

@export var kind: Kind = Kind.INSTANT

## 增益还是减益。**只影响渲染层**（信息栏图标的底色、战场上染冷染暖），
## 战斗结算一个字都不读它 —— 一个「-20% 攻」的 buff 在数值上就是 0.8，
## 好坏是给人看的判断，不是给公式看的。
@export var friendly: bool = true

## 持续多少秒。[constant Kind.INSTANT] 恒为 0。
@export var duration_seconds: float = 0.0

## 每隔多少秒触发一次。只有 [constant Kind.PERIODIC] 读它。
@export var period_seconds: float = 0.0

## 1 级的施法者放出来时，各个效果键是多少。键必须在
## [constant PBBuffRules.ALL] 里 —— [method PBBuffRules.validate] 拦着。
##
## 用 Dictionary 而不是像 [PBBond] 那样开两个平行数组：键是唯一的，
## 平行数组在这里只会多一处对不齐的地方。[member PBActorSkin.skill_anims]
## 已经是这个写法。
@export var mods: Dictionary = {}

## 每升一级，各个效果键加多少（决策 7）。**形状照抄 [PBCharacter] 的
## `strength` / `strength_growth`**，不是新发明的。
##
## 出现在这里的键**必须**也在 [member mods] 里；反过来不要求
## （「这一项不随等级长」是合法的，率型键通常都这样）。
@export var mods_growth: Dictionary = {}


## 进不进 [PBBuffBag]。瞬间的那一档当场结算完就没了，不占槽位。
func is_lasting() -> bool:
	return kind != Kind.INSTANT


## 每隔几 tick 触发一次。不是周期型就返回 0。
func period_ticks(cfg: PBSimConfig) -> int:
	if kind != Kind.PERIODIC:
		return 0
	return PBBuffRules.to_ticks(period_seconds, cfg)


## 持续多少 tick。瞬间的那一档返回 0。
func duration_ticks(cfg: PBSimConfig) -> int:
	if not is_lasting():
		return 0
	return PBBuffRules.to_ticks(duration_seconds, cfg)
