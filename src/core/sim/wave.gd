class_name PBWave
extends RefCounted
## 一波敌人的参数快照。由 [PBWaveRules] 构造出来之后就只读。
##
## 这里是「这一波长什么样」的全部信息 —— 属性、波型、数量、单体血量攻击、奖金。
## 战斗结算器拿它当输入，UI 拿它做 §03 要求的下一波预告。
##
## 之所以做成快照而不是每次现算：§01 要求提前 1 波公示属性与波型，
## 意味着第 n 波准备阶段就得把第 n+1 波构造出来。既然要提前构造，就得能存着。

## 波型。§04 用它把 AOE 与单体输出的价值分开，避免构筑收敛。
enum Shape {
	NORMAL,  ## 常规波，约 60%
	SWARM,  ## 潮水波，约 25%：数量多血量薄，AOE 与聚拢大招的高光
	ELITE,  ## 精英波，约 15%：数量少血量厚，单体爆发的高光
	BOSS,  ## 每 10 波
	MEGA_BOSS,  ## 每 50 波，属性在阶段间切换
}

## 波次序号，从 1 开始。
var index: int = 1

## 本波敌人的属性。按 [constant PBWaveRules.WAVE_ELEMENTS] 固定轮转，与波型无关。
var element: PBElement.Type = PBElement.Type.FIRE

var shape: Shape = Shape.NORMAL

## 敌人数量，已经受过波型倍率和 `count_cap` 的钳制。
var count: int = 0

## 单个敌人血量 / 攻击。注意血量吃波型倍率，攻击不吃 —— 精英波是更肉不是更痛。
var hp_each: float = 0.0
var atk_each: float = 0.0

## 单个敌人的护甲。按波型与波次定（[method PBSimConfig.enemy_armor]），只减普攻。
var armor_each: float = 0.0

## 单个敌人的忍术抗性（成数）。按波型与波次定（[method PBSimConfig.enemy_resist]），只减忍术。
var resist_each: float = 0.0

## 清完本波的基础奖金。§04 特意让它走线性，不跟血量的指数曲线走 ——
## 跟着走的话后期金币会溢出到抽卡不再是决策。
var reward_gold: int = 0

## §04「50 波后机制化加压」的词条位（治疗减半 / 大招 CD +50% / …）。
## 还没有内容。字段先占住是因为它会进存档结构，后加要做存档迁移。
var modifiers: Array[StringName] = []


## 本波敌人的血量总和 —— 战斗结算最常用的一个量。
func total_hp() -> float:
	return hp_each * count


func is_boss() -> bool:
	return shape == Shape.BOSS or shape == Shape.MEGA_BOSS
