class_name PBTechRules
extends RefCounted
## 训练科技：原版「近战 / 远程分开加」的四条属性线。
##
## ## 只产出词条，不自己往攻击者身上加
##
## 词条走装备那同一条路（[method PBCombatRules.unit_mods]），那一路已经接到全部折叠点
## （战斗、估值两处、任务卡预览）。另开一条的话，漏掉的那一处科技不生效，且不报错。
##
## ## 表里只许出现属性层的键
##
## [method PBStatRules.collect] 只收它认识的键，行为键写进来会被**静默丢掉** ——
## `tests/test_tech.gd` 钉着每个键都要 [method PBStatRules.is_known]。
##
## ## 降级记账
##
## - 训练防御原版还给 `+10 移速`：我们的移速是全队一个数，不在点数刻度上。
## - 训练精准原版还给 `+2% 命中率`：己方的攻击不会打空，没有读点。
## - **训练射程不上架**（原版远程 `+60 攻击距离`）：射程按档取
##   （[method PBSimConfig.reach_distance]），上架就是一个买了什么都不发生的按钮。
## - 原版没写价格，沿用 `200 × 1.4^Lv`。

const TRAIN_ATTACK: StringName = &"train_attack"
const TRAIN_DEFENCE: StringName = &"train_defence"
const TRAIN_HP: StringName = &"train_hp"
const TRAIN_AIM: StringName = &"train_aim"

## 顺序即指令卡二级页的排列顺序。
const BRANCHES: Array[StringName] = [TRAIN_ATTACK, TRAIN_DEFENCE, TRAIN_HP, TRAIN_AIM]

## 原版四条都是 5 级满。
const MAX_LEVEL: int = 5

## 每一级给的词条（原版 §9）。**写每级的量**，发的时候乘等级 ——
## 同 [member PBBeast.aura_passives] 那条「写死总量的话升级就没有意义了」。
const PER_LEVEL := {
	TRAIN_ATTACK: {PBStatRules.ATTACK: 50.0, PBStatRules.ATTACK_SPEED: 0.05},
	TRAIN_DEFENCE: {PBStatRules.DEFENCE: 4.0},
	TRAIN_HP: {PBStatRules.HP_BONUS: 0.03},
	TRAIN_AIM: {PBStatRules.ATTACK: 30.0},
}

## 这一条加给近战（true）还是远程（false）。
##
## **判据是 [method PBCharacter.reach_tier]**，和站位、出不出子弹是同一个函数 ——
## 另写一份「谁算近战」的话，一个站在前排、不发子弹的人可能吃不到近战科技，
## 而那不报错。超远程（[constant PBCharacter.Reach.LONG]）算远程。
const FOR_MELEE := {
	TRAIN_ATTACK: true,
	TRAIN_DEFENCE: true,
	TRAIN_HP: true,
	TRAIN_AIM: false,
}

## 价格曲线 `COST_BASE × COST_MULT^Lv`。放在这里不放 [PBSimConfig]：
## 那个文件停在 999 行，而这两个数今天不进任何扫描（同 [PBCritRules]）。
const COST_BASE: float = 200.0
const COST_MULT: float = 1.4


static func is_branch(branch: StringName) -> bool:
	return PER_LEVEL.has(branch)


## 这一条训练对这个人生效吗。
static func applies_to(branch: StringName, unit: PBUnit) -> bool:
	if not is_branch(branch) or unit == null or unit.character == null:
		return false
	var melee: bool = unit.character.reach_tier() == PBCharacter.Reach.MELEE
	return bool(FOR_MELEE[branch]) == melee


## 这个人从 [param levels]（`{线: 等级}`，即 [member PBRunState.training]）
## 吃到的全部词条。**同键相加**：两条线都给攻击力时两份都算。
static func unit_mods(unit: PBUnit, levels: Dictionary) -> Dictionary:
	var out := {}
	for branch: StringName in BRANCHES:
		var level: int = int(levels.get(branch, 0))
		if level <= 0 or not applies_to(branch, unit):
			continue
		var words: Dictionary = PER_LEVEL[branch]
		for key: StringName in words:
			out[key] = float(out.get(key, 0.0)) + float(words[key]) * float(level)
	return out
