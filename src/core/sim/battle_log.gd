class_name PBBattleLog
extends RefCounted
## 一局的战斗播报（§02）。零引擎依赖 —— 它只是一个环形数组。
##
## **记下标和数字，不记句子**：铁律 5 不许代码里出现角色名，翻译是渲染层的事
## （[method PBBattleLogPanel.line_of]），顺带省掉热路径上的字符串拼接。
##
## **在 sim 里记，不像 [PBDamageWatch] 那样逐帧比血量**：播报要的是「谁打的」，
## 那是事件，从画面上只能猜，而猜错不报错。开关是 [member PBBattleSim.log_to]，
## 默认 null，批量扫描一条都不记。
##
## **上限是环形的**，丢最老的：记满就停的话日志会停在第一波。

## 一条播报是哪一种。**怪物死亡不在里面**（玩家定的）：
## 一波死几十只，每只一行的话另外五种全被冲掉。
enum Kind {
	NOTE,  ## 界面塞进来的整句（开波的生效羁绊）
	HIT_ENEMY,  ## 忍者打了敌人
	HIT_ALLY,  ## 敌人打了忍者
	ALLY_DOWN,  ## 忍者倒下
	BASE_HIT,  ## 基地挨了一下（漏怪）
	ULTIMATE,  ## 谁放了忍术
}

## 最多留多少条（约等于往回翻二十秒）。
const CAP: int = 200

## 一条条播报，**最老的在前**。元素是
## `{kind, tick, source, target, amount, text}`，缺的字段各有默认值。
var entries: Array[Dictionary] = []

## 这一局**一共记过多少条**（含已经被挤掉的）。只增不减。
##
## **渲染层的游标必须比它，不能比 [member entries] 的长度**：写满之后长度恒等于 [constant CAP]，
## 拿长度当游标的话「消化到第几条」和「一共几条」永远相等，施法回音与命中火花从此不再触发，
## 而日志面板一切正常。
var total: int = 0


## 界面塞一句整话进来（开波的生效羁绊）。**只有这一种带字符串** ——
## 它本来就是界面组好的，sim 一个字都不认识。
func note(at_tick: int, text: String) -> void:
	_add({"kind": Kind.NOTE, "tick": at_tick, "text": text})


## 一次命中。[param to_ally] 区分方向：忍者打敌人还是敌人打忍者。
## 两个下标各自是 [member PBAttacker.slot] 和 [member PBEnemy.slot]。
##
## [param crit] 是这一下暴没暴。**只有播报说得准** —— 血量里混着暴击和易伤，
## 还会把几帧的小伤害攒成一个数，结构上分不出哪一下是暴击。
func hit(
	at_tick: int, source: int, target: int, amount: float, to_ally: bool, crit: bool = false
) -> void:
	_add({
		"kind": Kind.HIT_ALLY if to_ally else Kind.HIT_ENEMY,
		"tick": at_tick,
		"source": source,
		"target": target,
		"amount": amount,
		"crit": crit,
	})


## 一个忍者倒下了。**怪物死亡不记**，见 [enum Kind]。
func ally_down(at_tick: int, slot: int) -> void:
	_add({"kind": Kind.ALLY_DOWN, "tick": at_tick, "source": slot})


## 一只敌人摸到基地了，扣了这么多血。
func base_hit(at_tick: int, amount: float) -> void:
	_add({"kind": Kind.BASE_HIT, "tick": at_tick, "amount": amount})


## 谁下达了忍术（**下达那一刻，不是落地那一刻** —— 点下去就该看见回音）。
##
## [param to_ally] 是这一发落在自己人身上还是敌人身上。记在这里而不是让渲染层回头去问技能：
## 一个人有好几格，回头只问得到第 0 格，第 1 格的治疗会被画成打人的颜色。
func ultimate(at_tick: int, slot: int, to_ally: bool = false) -> void:
	_add({"kind": Kind.ULTIMATE, "tick": at_tick, "source": slot, "to_ally": to_ally})


## 整局清空。**只在重开一局时调**（玩家定的：日志只保留一局）——
## 每波清的话，「上一波是怎么崩的」在结算那一眼就没了。
func clear() -> void:
	entries.clear()
	total = 0


## 从「消化到第 [param seen] 条」算起，还没消化的那几条。
##
## **返回的是 [member entries] 里的起始下标**，已经把被挤掉的那些算进去了 ——
## 各家渲染层自己减的话，那道减法会被抄成好几份，而抄漏一处的表现是
## 「某一种特效在长局里会消失」。见 [member total]。
func fresh_from(seen: int) -> int:
	return entries.size() - clampi(total - seen, 0, entries.size())


func _add(entry: Dictionary) -> void:
	entries.append(entry)
	total += 1
	if entries.size() > CAP:
		entries.remove_at(0)
