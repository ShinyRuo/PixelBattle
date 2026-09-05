class_name PBSkillTable
extends RefCounted
## 全部逐角色的技能（M7-g）。[member PBCharacter.skill_ids] 按 id 查这张表。
##
## 和 [PBCharacterTable] / [PBBondTable] / [PBEquipTable] 同一个套路：
## 真表由 core 外面的加载器（[PBSkillLoader]）从 `data/skills/*.tres` 装进来，
## core 只认这个类型，不知道数据从哪儿来（§14 铁律 1：`ResourceLoader`
## 被纯度检查挡着）。
##
## ## 为什么没有对应的「合成表」
##
## 那三张都带一份 [code]synthetic()[/code]，因为它们各自是**某条曲线的替身**：
## 换真数据那一步的数值变化要能和引入结构那一步分开看。
##
## 技能表没有这个问题 —— **它的默认值就是「空」，而空表是一个真状态**
## （没有任何角色配技能，也就是 M7-g 之前的每一天）。
## 造一张假技能表反而会凭空多出一批没人要的数值。
##
## ## 也没有「buff 表」
##
## [member PBSkill.on_hit] 存的是**直接引用**（`.tres` 里的 `ext_resource`
## 指向 `data/buffs/*.tres`），那就是 Godot 原生的外键 ——
## 再套一层 id 查表等于自己发明一遍资源系统。
## 所以 buff 跟着技能一起被装进来，校验也在 [PBSkillLoader] 里一起做。

## id → [PBSkill]。
var _by_id: Dictionary = {}


## 收一份。id 空或重复就拒收（返回 false），由加载器报错并指出是哪个文件。
func add(skill: PBSkill) -> bool:
	if skill == null or skill.id == &"" or _by_id.has(skill.id):
		return false
	_by_id[skill.id] = skill
	return true


## 按 id 取。没有就返回 null —— **调用方必须判**，
## 拿一份空技能顶上去的话，玩家看到的是一个点了没反应的格子。
func by_id(id: StringName) -> PBSkill:
	return _by_id.get(id, null) as PBSkill


func has(id: StringName) -> bool:
	return _by_id.has(id)


## 一共几份。测试拿它确认表真的装上了。
func size() -> int:
	return _by_id.size()


## 全部 id，**排过序**。顺序不参与任何结算，排序纯粹是为了让
## 报错信息和调试输出稳定（同 [PBBondLoader] 顶上那段）。
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _by_id:
		out.append(id)
	out.sort()
	return out
