class_name PBEnemyAbility
extends Resource
## 敌方主动单体直伤技能定义；冷却存于每个敌人，资源只读。
## 首批仅支持即时命中，不隐含普攻、范围、弹道或控制效果。

@export var id: StringName = &""
@export var kind: PBDamageKind.Type = PBDamageKind.Type.NINJUTSU
@export var element: PBElement.Type = PBElement.Type.FIRE
@export var damage_base: float = 0.0
@export var attack_scale: float = 0.0
@export var intellect_scale: float = 1.0
@export var reach: float = 0.3
@export var cooldown_ticks: int = 100


func validate() -> String:
	if id == &"" or cooldown_ticks < 1:
		return "敌方主动技能必须有 ID 与正冷却"
	if kind not in [PBDamageKind.Type.TAIJUTSU, PBDamageKind.Type.NINJUTSU]:
		return "敌方主动技能伤害类型无效"
	if not PBElement.Type.values().has(element):
		return "敌方主动技能属性无效"
	for value: float in [damage_base, attack_scale, intellect_scale, reach]:
		if not is_finite(value) or value < 0.0:
			return "敌方主动技能参数必须为非负有限数"
	return ""
