class_name PBDamageKind
extends RefCounted
## 一次伤害是**体术**（物理）还是**忍术**（魔法）。和属性（[PBElement]）一样挂在伤害事件上，不挂在单位上。
##
## 两套是独立的结算体系（玩家定的，对应 War3 的物理 / 魔法伤害）：
##
## | | 体术 | 忍术 |
## |---|---|---|
## | 减伤 | 敌人护甲（[member PBEnemy.armor]） | 敌人忍术抗性（[member PBEnemy.ninjutsu_resist]） |
## | 穿透 | [member PBAttacker.armor_pen] | [member PBAttacker.ninjutsu_pen] |
## | 暴击 | [member PBAttacker.crit_chance] | [member PBAttacker.ninjutsu_crit_chance] |
## | 增伤 | [member PBAttacker.damage_bonus]（只作用普攻） | [member PBAttacker.ninjutsu_bonus] |
##
## **普攻默认是体术**，配了 `attack_ninjutsu` 的人普攻算忍术（鼬的万花筒写轮眼）。
## **技能默认是忍术**，原版写明「物理伤害」的在技能表额外列写 `kind=体术`。持续伤害算忍术。
## 反弹、闪避反打不属于任何一类，不减不增（它们还的是已经折算过的数）。
##
## 按类型分开的判据全部收在 [PBCritRules]（暴击、增伤）与 [method PBStrikeRules.mitigated]（减伤）两处。

enum Type {
	PHYSICAL,  ## 体术 / 普攻
	NINJUTSU,  ## 忍术
}
