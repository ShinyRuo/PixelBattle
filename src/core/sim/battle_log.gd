class_name PBBattleLog
extends RefCounted
## 一局的战斗播报（§02，M6-j）。零引擎依赖 —— 它只是一个环形数组。
##
## ## 为什么它记的是**下标和数字**，不是句子
##
## 铁律 5：代码里不出现角色名。这一层记的是「第 2 个攻击者对第 17 个敌人
## 打了 34.2」，翻成「阿斯玛 → 火忍 34」是渲染层的事
## （[method PBBattleLogPanel.line_of]）—— 那边才有名单和语言表。
##
## 顺带省掉了每 tick 的字符串拼接：一波几百条，而这一层在
## `_physics_process` 的热路径上。
##
## ## 为什么在 sim 里记，不像 [PBDamageWatch] 那样逐帧比对
##
## 那一套（命中白闪、飘字、顿帧）比的是**血量**，而血量是状态；
## 播报要的是「**谁**打的」，那是事件，diff 不出来 ——
## 从画面上反推的话只能猜（谁瞄着他、谁离得近），而猜错不报错。
##
## 代价用一个开关挡住：[member PBBattleSim.log_to] **默认 null**，
## 批量扫描一局跑几万 tick，一条都不记。只有画面那一路塞得进来。
##
## ## 上限是环形的，不是「记满就不记了」
##
## 播报只有最新的几十行有人看，而一局能打上百波。丢的是最老的那几条 ——
## 反过来（记满就停）会让日志停在第一波，而那一格屏幕从此再不更新。

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

## 最多留多少条。60 帧的面板一屏看得见十来行，留 200 条约等于
## 「往回翻得到二十秒之前」，而这一局的全部记录一直留着没有意义。
const CAP: int = 200

## 一条条播报，**最老的在前**。元素是
## `{kind, tick, source, target, amount, text}`，缺的字段各有默认值。
var entries: Array[Dictionary] = []

## 这一局**一共记过多少条**（含已经被挤掉的那些）。只增不减。
##
## ## 为什么渲染层的游标必须比它，不能比 [member entries] 的长度
##
## 上限是环形的：满了之后 `entries.size()` **恒等于** [constant CAP]，
## 而新条目从尾部进、老条目从头部走。拿长度当游标的话，
## 「消化到第几条」和「一共有几条」在写满的那一刻起就永远相等 ——
## 于是**特效从此再也不触发**（[method PBSkillFxPool.echo] 的施法回音、
## [method PBShotPool.sync_shots] 的命中火花），而日志面板一切正常。
##
## 这一条是 M8-a 顺带查出来的：M7-f 那个回音在一局打到第 200 条播报之后
## 就静默停了，而 200 条大概是三四波的量。
var total: int = 0


## 界面塞一句整话进来（开波的生效羁绊）。**只有这一种带字符串** ——
## 它本来就是界面组好的，sim 一个字都不认识。
func note(at_tick: int, text: String) -> void:
	_add({"kind": Kind.NOTE, "tick": at_tick, "text": text})


## 一次命中。[param to_ally] 区分方向：忍者打敌人还是敌人打忍者。
## 两个下标各自是 [member PBAttacker.slot] 和 [member PBEnemy.slot]。
func hit(at_tick: int, source: int, target: int, amount: float, to_ally: bool) -> void:
	_add({
		"kind": Kind.HIT_ALLY if to_ally else Kind.HIT_ENEMY,
		"tick": at_tick,
		"source": source,
		"target": target,
		"amount": amount,
	})


## 一个忍者倒下了。**怪物死亡不记**，见 [enum Kind]。
func ally_down(at_tick: int, slot: int) -> void:
	_add({"kind": Kind.ALLY_DOWN, "tick": at_tick, "source": slot})


## 一只敌人摸到基地了，扣了这么多血。
func base_hit(at_tick: int, amount: float) -> void:
	_add({"kind": Kind.BASE_HIT, "tick": at_tick, "amount": amount})


## 谁下达了忍术（**下达那一刻，不是落地那一刻**）——
## 玩家点下去就该看见回音，而落地还要等施法延迟。
##
## [param to_ally] 是这一发落在自己人身上（治疗、增益）还是敌人身上。
## **记在这里而不是让渲染层回头去问那个技能**（M7-f）：一个人现在有好几格
## （[method PBSkillRules.cast_at]），而这条播报只记了「谁放的」——
## 回头去问的话只能问到第 0 格，于是第 1 格的治疗会被画成打人的颜色。
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
