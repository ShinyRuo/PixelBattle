class_name PBSkillTable
extends RefCounted
## 全部逐角色的技能。[member PBCharacter.skill_ids] 按 id 查这张表。
##
## 真表由 core 外的 [PBSkillLoader] 从 `data/skills/*.tres` 装进来（铁律 1）。
##
## **没有合成表**：它的默认值就是空，空表是一个真状态。
## **也没有 buff 表**：[member PBSkill.on_hit] 存的是直接引用（`ext_resource`），
## 那就是 Godot 原生的外键；buff 跟着技能一起装进来，校验也在 [PBSkillLoader] 里。

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
