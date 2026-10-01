@tool
class_name PBCastGlow
extends PBBuffGlow
## 起手光不占 BUFF 槽。两层同用模拟时钟，释放、打断、阵亡时撤下。

const ELEMENT_STARTS := {
	PBElement.Type.FIRE: &"cast_fire",
	PBElement.Type.WIND: &"cast_wind",
	PBElement.Type.THUNDER: &"cast_thunder",
	PBElement.Type.EARTH: &"cast_earth",
	PBElement.Type.WATER: &"cast_water",
	PBElement.Type.SAGE: &"cast_sage",
}

static var _starts: Dictionary = {}


static func clear_cache() -> void:
	_starts.clear()


static func start_for(
	id: StringName, element: PBElement.Type = PBElement.Type.PHYSICAL
) -> PBBuffSkin:
	if _starts.has(id):
		return _starts[id] as PBBuffSkin
	var element_cache := StringName("%s@%d" % [id, element])
	if _starts.has(element_cache):
		return _starts[element_cache] as PBBuffSkin
	var path := "res://data/skill_art/%s.tres" % id
	var skin: PBBuffSkin = null
	var explicitly_bound := false
	if ResourceLoader.exists(path):
		var binding := (
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PBSkillStartArt
		)
		if binding != null and binding.start_key != &"":
			var art := "res://data/cast_art/%s.tres" % binding.start_key
			if ResourceLoader.exists(art):
				skin = ResourceLoader.load(art, "", ResourceLoader.CACHE_MODE_IGNORE) as PBBuffSkin
				explicitly_bound = skin != null
	if skin != null and skin.problem() != "":
		skin = null
	if skin == null and ELEMENT_STARTS.has(element):
		var element_key: StringName = ELEMENT_STARTS[element]
		var element_path := "res://data/cast_art/%s.tres" % element_key
		if ResourceLoader.exists(element_path):
			skin = (
				ResourceLoader.load(element_path, "", ResourceLoader.CACHE_MODE_IGNORE)
				as PBBuffSkin
			)
			if skin != null and skin.problem() != "":
				skin = null
	_starts[id if explicitly_bound else element_cache] = skin
	return skin


func sync_cast(unit: PBAttacker, tick: int, rate: int) -> void:
	var action := unit.casting
	if (
		not action.active(tick)
		or action.released
		or tick >= action.releases_at
		or PBCastTimeline.interrupted(unit, tick)
	):
		clear()
		return
	preview_once(start_for(action.skill_id, unit.attack_element), tick - action.started_at, rate)
