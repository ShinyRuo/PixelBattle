class_name PBDebugRules
extends RefCounted
## 调试出战只跳过获取成本，名单仍走正常编队；不动抽卡随机流。


static func deploy(
	id: StringName, state: PBRunState, strategy: PBStrategy, plan: PBWavePlan, cfg: PBSimConfig
) -> Dictionary:
	var character := cfg.characters.by_id(id)
	if character == null:
		return {"error": "请选择有效忍者。"}
	if not state.pending_offer.is_empty():
		return {"error": "请先完成当前抽卡选择。"}
	var lineup := strategy.deploy(state, plan.wave, cfg)
	if lineup.size() >= state.field_slots(cfg):
		return {"error": "出战位置已满，请先把一名忍者移回仓库。"}
	var unit := PBUnit.new(character)
	state.add_unit(unit)
	lineup.append(unit)
	strategy.set_lineup(state, lineup)
	strategy.bring_to_field(state, cfg)
	return {"error": "", "unit": unit.key()}
