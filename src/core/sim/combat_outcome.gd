class_name PBCombatOutcome
extends RefCounted
## 一波战斗的结算结果。[PBCombatRules.resolve] 的输出。

## 是否全部清完，没有一个漏到基地。
var cleared: bool = true

var kills: int = 0
var leaked: int = 0

## 漏怪对基地造成的总伤害，已计入防御科技减伤。
var base_damage: float = 0.0

## 本波战斗时长（秒），已对齐到整 tick。§01 要求它落在 30–45 秒。
var battle_seconds: float = 0.0

## 同上，以 tick 计。定帧 20 tick/s，见 [member PBSimConfig.tick_rate]。
var ticks: int = 0

## 本波倒下了几个己方单位（召唤物不算）。**下一波满血复活**，所以它是「这一波打得多险」的度量。
## 单独记：攻击者一波一份、打完就扔，结算之后没人还拿着那份名单。
var allies_lost: int = 0
