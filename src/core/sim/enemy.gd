class_name PBEnemy
extends RefCounted
## 战场上的一个敌人。M0 起，战斗从解析式排队模型换成逐 tick 推进，
## 敌人因此需要有身份和位置 —— 排队模型里它们只是一个计数。
##
## **这个类会被对象池复用，不要在战斗中 `.new()`。** §14 的要求：
## GDScript 每 tick 创建大量临时对象会触发频繁的引用计数开销，
## 48 单位 × 20 tick/s 的规模下这笔开销很实在。
## 复用的入口是 [method spawn]，它把所有字段重置成出生状态。

## 还活着（没被打死、也没走到基地）。
var alive: bool = false

var hp: float = 0.0
var max_hp: float = 0.0

## 本波的属性。同一波内所有敌人属性相同（§04），存在个体上是为了
## 将来的「混合属性波」（§04 的 50 波后机制）不用改结构。
var element: PBElement.Type = PBElement.Type.FIRE

## 攻击力。只在漏进基地时用得上 —— M0 的敌人不还手，见 [PBBattleSim]。
var atk: float = 0.0

## 距离基地还有多远。出生时等于战场长度，走到 0 就是漏怪。
##
## 一维就够了：§02 的「前中后三列」映射到屏幕的右中左，敌人自右向左推进，
## 整条战线本来就是一维的。纵深要配合技能射程才有意义，那是 M3。
var distance: float = 0.0

## 每 tick 前进多少。由 `march_seconds` 反推，不是新拍的参数。
var speed: float = 0.0

## 这个敌人第几个 tick 出场。没到就不激活、不能被打也不移动。
var spawn_tick: int = 0

## 渲染层用来认人的槽位号，等于它在对象池里的下标。
## view 层靠它把节点和逻辑敌人对上，不用每帧重新匹配。
var slot: int = 0


## 把这个实例重置成一个刚出生的敌人。对象池复用走这里，不要 `.new()`。
func spawn(wave: PBWave, enemy_speed: float, field_length: float, at_tick: int) -> void:
	alive = true
	max_hp = wave.hp_each
	hp = max_hp
	element = wave.element
	atk = wave.atk_each
	distance = field_length
	speed = enemy_speed
	spawn_tick = at_tick


## 是否已经出场。没出场的敌人不参与移动、不能被选为目标。
func is_active(current_tick: int) -> bool:
	return alive and current_tick >= spawn_tick


## 扣血。返回这次是否把它打死了。
##
## 返回值而不是让调用方比较 hp，是为了让「溢出伤害」有个明确的结算点：
## 打死之后剩下的伤害要接着打下一个，漏掉这个判断会让高 DPS 白白浪费。
func take_damage(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false


## 前进一个 tick。返回是否在这一 tick 走到了基地。
func advance() -> bool:
	distance -= speed
	if distance <= 0.0:
		distance = 0.0
		return true
	return false


## 渲染用的进度：0 = 刚出生，1 = 抵达基地。
func progress(field_length: float) -> float:
	if field_length <= 0.0:
		return 1.0
	return clampf(1.0 - distance / field_length, 0.0, 1.0)
