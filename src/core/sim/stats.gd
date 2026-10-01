class_name PBStats
extends RefCounted
## 一个单位**此刻**的属性快照（§03A）。算它的是 [PBStatRules]，本类只负责装。
##
## - **基础属性**（血 / 蓝 / 攻 / 防 / 攻速）—— 战斗结算只读这五个
## - **二级属性**（力量 / 敏捷 / 智力）—— 通过系数影响基础属性，也可作为技能的显式伤害基数
##
## 只有一条链路，「加点力量」的后果才说得清。
##
## 是值包不是有行为的类：它是算出来的结果，等级、装备、羁绊任何一样变了都要重算；
## 「当前血量」是战斗层的东西，不许塞进来。

var hp: float = 0.0
var mp: float = 0.0
var atk: float = 0.0
var base_atk: float = 0.0
var def: float = 0.0

## 每秒攻击几次。
var attack_speed: float = 1.0

var strength: float = 0.0
var agility: float = 0.0
var intellect: float = 0.0


## 每秒伤害（`atk × attack_speed`）。**统计量**：面板、估值、解析模型读它，战斗每一发读攻击力。
func dps() -> float:
	return atk * attack_speed
