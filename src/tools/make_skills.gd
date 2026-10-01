extends SceneTree
## 按 `data/buffs.tsv` + `data/skills.tsv` 重铺技能与效果。
##
## ```powershell
## F:\Godot_PJ\_engine\4.7.2\godot_console.exe --headless --path . -s src/tools/make_skills.gd
## ```
##
## 手写一百多个 `.tres` 等于抄一百多遍样板，少一个字段就是取默认值，表现是「这个技能好像没什么用」。
## 和 `make_roster.gd` / `make_bonds.gd` 同一套：表在 `data/`，生成器只认列号，名字不进 `src/`（铁律 5）。
##
## **它是「谁有哪几个技能」的唯一来源**：表里的角色键反写进 `data/characters/<键>.tres` 的 `skill_ids`，
## **表里没有的角色会被清空** —— 只写不清的话，删掉的技能格子还在，按下去查一个不存在的 id。
##
## **不认识的额外键直接 `quit(1)`**：跳过的表现正是「配了不生效」。

const BUFFS := "res://data/buffs.tsv"
const SKILLS := "res://data/skills.tsv"
const BUFF_DIR := "res://data/buffs"
const SKILL_DIR := "res://data/skills"
const CHAR_DIR := "res://data/characters"

const BUFF_COLUMNS: int = 7
const B_KEY: int = 0
const B_NAME: int = 1
const B_KIND: int = 2
const B_SIDE: int = 3
const B_DURATION: int = 4
const B_PERIOD: int = 5
const B_MODS: int = 6

const SKILL_COLUMNS: int = 11
const S_KEY: int = 0
const S_OWNER: int = 1
const S_NAME: int = 2
const S_ELEMENT: int = 3
const S_TARGET: int = 4
const S_AFFECTS: int = 5
const S_POWER: int = 6
const S_RADIUS: int = 7
const S_COOLDOWN: int = 8
const S_MANA: int = 9
const S_EXTRA: int = 10

const KINDS := {
	"瞬间": PBBuff.Kind.INSTANT,
	"持续": PBBuff.Kind.DURATION,
	"周期": PBBuff.Kind.PERIODIC,
}

const SIDES := {"增益": true, "减益": false}

const TARGETS := {
	"不用点": PBSkill.Target.NONE,
	"点队友": PBSkill.Target.ALLY,
	"点敌人": PBSkill.Target.ENEMY,
	"点地面": PBSkill.Target.GROUND,
}

const AFFECTS := {"我方": PBSkill.Party.ALLIES, "敌方": PBSkill.Party.ENEMIES}

const ELEMENTS := {
	"火": PBElement.Type.FIRE,
	"风": PBElement.Type.WIND,
	"雷": PBElement.Type.THUNDER,
	"土": PBElement.Type.EARTH,
	"水": PBElement.Type.WATER,
	"物理": PBElement.Type.PHYSICAL,
	"仙": PBElement.Type.SAGE,
}

## `额外` 那一列认得的键。**改这里要连着表头的注释一起改。**
const EXTRA_KEYS: Array[String] = [
	"heal_aura_flat",
	"heal_aura_growth",
	"heal_aura_max",
	"heal_aura_period",
	"heal_aura_hit_chance",
	"heal_aura_lost",
	"enemy_aura_radius",
	"enemy_aura_effects",
	"attack_chance",
	"attack_chain_count",
	"attack_repeat_count",
	"attack_chain_step",
	"self_attack_bonus",
	"self_attack_bonus_growth",
	"on_primary",
	"variant_first",
	"target_current_hp",
	"target_nonhero_only",
	"area_refresh",
	"pulse_delay",
	"hit_levels",
	"on_rescue",
	"on_start_area",
	"variant",
	"zone_outer_radius",
	"zone_outer_count",
	"zone_ring_effects",
	"zone_seconds",
	"zone_radius",
	"zone_ring_radius",
	"zone_ring_count",
	"zone_effects",
	"cost_levels",
	"target_hp",
	"center_scale",
	"damage_cap",
	"death_move",
	"on_hit",
	"on_target",
	"on_start_target",
	"on_self",
	"delay",
	"fly",
	"shot",
	"targets",
	"gather",
	"knockback",
	"line_length",
	"blink",
	"channel_control",
	"mind_control",
	"extra_from_caster",
	"sacrifice_transfer",
	"transfer_buff",
	"ranged_attack_aura",
	"attack_speed_aura",
	"attack_speed_aura_growth",
	"move_speed_aura",
	"followup",
	"radius_growth",
	"travel_step",
	"waves",
	"wave_interval",
	"fan_spread",
	"fan_steps",
	"slow",
	"slow_secs",
	"carry",
	"summon",
	"summon_power",
	"summon_growth",
	"summon_focus",
	"summon_hp",
	"summon_secs",
	"summon_lifesteal",
	"base",
	"growth",
	"stat",
	"stat_floor",
	"hp",
	"scatter_steps",
	"volley_size",
	"hits",
	"interval",
	"control_radius",
	"hit_radius",
	"pulse_radius_step",
	"pulse_damage_step",
	"phantom_count",
	"phantom_element",
]

const BUFF_LINK_KEYS: Array[String] = [
	"transfer_buff",
	"enemy_aura_effects",
	"on_primary",
	"on_hit",
	"on_self",
	"on_target",
	"on_start_target",
	"on_rescue",
	"on_start_area",
	"zone_effects",
	"zone_ring_effects"
]

var _buffs: Dictionary = {}


func _init() -> void:
	var buff_rows := _read(BUFFS, BUFF_COLUMNS)
	var skill_rows := _read(SKILLS, SKILL_COLUMNS)
	if buff_rows.is_empty() or skill_rows.is_empty():
		printerr("表是空的，检查 %s / %s" % [BUFFS, SKILLS])
		quit(1)
		return
	for row: PackedStringArray in buff_rows:
		var err := _write_buff(row)
		if err != "":
			printerr(err)
			quit(1)
			return
	var owned: Dictionary = {}
	for row: PackedStringArray in skill_rows:
		var err := _write_skill(row, owned)
		if err != "":
			printerr(err)
			quit(1)
			return
	print("写好 ", buff_rows.size(), " 份效果、", skill_rows.size(), " 个技能")
	var linked := PBSkillLoader.load_from(SKILL_DIR)
	for row: PackedStringArray in skill_rows:
		if not linked.has(StringName(row[S_KEY])):
			printerr("技能外键校验失败：", row[S_KEY])
			quit(1)
			return
	_sweep(BUFF_DIR, _keys(buff_rows))
	_sweep(SKILL_DIR, _keys(skill_rows))
	_attach(owned)
	quit(0)


## 读一张表。空行和 `#` 开头的行跳过，列数不够整行不要。
func _read(path: String, columns: int) -> Array:
	var text := FileAccess.get_file_as_string(path)
	var out: Array = []
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed == "" or trimmed.begins_with("#"):
			continue
		var cells: PackedStringArray = trimmed.split("\t")
		for i: int in cells.size():
			cells[i] = cells[i].strip_edges()
		if cells.size() < columns:
			printerr("这一行少了列（要 %d，实际 %d）：%s" % [columns, cells.size(), trimmed])
			continue
		out.append(cells)
	return out


func _keys(rows: Array) -> Dictionary:
	var out: Dictionary = {}
	for row: PackedStringArray in rows:
		out[row[0]] = true
	return out


## `键=基数` 或 `键=基数+成长`，`;` 隔开。返回 `[基数表, 成长表]`。
func _parse_mods(text: String) -> Array:
	var base: Dictionary = {}
	var growth: Dictionary = {}
	for piece: String in text.split(";"):
		var one: String = piece.strip_edges()
		if one == "":
			continue
		var halves: PackedStringArray = one.split("=")
		if halves.size() != 2:
			return []
		var key := StringName(halves[0].strip_edges())
		var value: String = halves[1].strip_edges()
		var parts: PackedStringArray = value.split("+")
		base[key] = float(parts[0])
		if parts.size() > 1:
			growth[key] = float(parts[1])
	return [base, growth]


func _write_buff(row: PackedStringArray) -> String:
	var key: String = row[B_KEY]
	if not KINDS.has(row[B_KIND]):
		return "%s 的档不认识：%s" % [key, row[B_KIND]]
	if not SIDES.has(row[B_SIDE]):
		return "%s 的善恶不认识：%s" % [key, row[B_SIDE]]
	var parsed := _parse_mods(row[B_MODS])
	if parsed.is_empty():
		return "%s 的效果写歪了：%s" % [key, row[B_MODS]]

	var buff := PBBuff.new()
	buff.id = StringName(key)
	buff.name_key = "buff.%s" % key
	buff.icon_key = "buff.%s" % key
	buff.kind = KINDS[row[B_KIND]]
	buff.friendly = SIDES[row[B_SIDE]]
	buff.duration_seconds = float(row[B_DURATION])
	buff.period_seconds = float(row[B_PERIOD])
	buff.mods = parsed[0]
	buff.mods_growth = parsed[1]

	# **词汇表那一关走 `PBBuffRules.validate`，不在这里另写一份。**
	# 两处各判各的话，「这个键认不认」迟早分叉，而分叉的那一侧静默生效。
	var bad := _buff_extra(buff, row)
	if bad == "":
		bad = PBBuffRules.validate(buff)
	if bad != "":
		return "%s：%s" % [key, bad]

	var err := ResourceSaver.save(buff, "%s/%s.tres" % [BUFF_DIR, key])
	if err != OK:
		return "%s 存不下来（%d）" % [key, err]
	_buffs[key] = buff
	return ""


## 三个枚举列一起查。收在一处是为了让 `_write_skill` 待在 gdlint
## 的 6 个 return 上限内 —— 那条上限指的地方是对的：一串平铺的
## 「不认识就返回」本来就是同一件事。
func _buff_extra(buff: PBBuff, row: PackedStringArray) -> String:
	if row.size() <= BUFF_COLUMNS or row[BUFF_COLUMNS] == "-":
		return ""
	for piece: String in row[BUFF_COLUMNS].split(";"):
		var pair: PackedStringArray = piece.split("=")
		if (
			pair.size() != 2
			or (pair[0] in ["stacks", "wave", "source"] and pair[1] not in ["0", "1"])
		):
			return "效果额外字段应为 键=值：%s" % piece
		match pair[0]:
			"wave":
				buff.until_wave_end = pair[1] == "1"
			"source":
				buff.per_source = pair[1] == "1"
			"stacks":
				buff.independent_stacks = pair[1] == "1"
			"harm_stat":
				buff.harm_stat = StringName(pair[1])
			"harm_mult":
				if not pair[1].is_valid_float():
					return "效果属性系数不是数字：%s" % pair[1]
				buff.harm_mult = float(pair[1])
			"durations":
				for value: String in pair[1].split(","):
					if not value.is_valid_float():
						return "效果分级时长不是数字：%s" % value
					buff.duration_levels.append(float(value))
			_:
				var why := _buff_level_values(buff, pair[0], pair[1])
				if why != "":
					return why
	return ""


func _buff_level_values(buff: PBBuff, key: String, text: String) -> String:
	if not key.begins_with("levels_"):
		return "不认识的效果额外键：%s" % key
	var values := PackedFloat32Array()
	for value: String in text.split(","):
		if not value.is_valid_float():
			return "分级效果不是数值：%s" % value
		values.append(float(value))
	buff.mods_levels[StringName(key.trim_prefix("levels_"))] = values
	return ""


func _check_enums(row: PackedStringArray) -> String:
	var checks: Array = [
		[ELEMENTS, row[S_ELEMENT], "属性"],
		[TARGETS, row[S_TARGET], "「点什么」"],
		[AFFECTS, row[S_AFFECTS], "「落在谁」"],
	]
	for one: Array in checks:
		var table: Dictionary = one[0]
		if not table.has(one[1]):
			return "的%s不认识：%s" % [one[2], one[1]]
	return ""


func _write_skill(row: PackedStringArray, owned: Dictionary) -> String:
	var key: String = row[S_KEY]
	var bad := _check_enums(row)
	if bad != "":
		return "%s %s" % [key, bad]

	var skill := PBSkill.new()
	skill.id = StringName(key)
	skill.name_key = "skill.%s" % key
	skill.element = ELEMENTS[row[S_ELEMENT]]
	var owner_path: String = "%s/%s.tres" % [CHAR_DIR, row[S_OWNER]]
	var owner: PBCharacter = load(owner_path) as PBCharacter if row[S_OWNER] != "-" else null
	skill.kind = PBDamageKind.skill_kind(skill.element if owner == null else owner.element)
	skill.target = TARGETS[row[S_TARGET]]
	skill.affects = AFFECTS[row[S_AFFECTS]]
	skill.power_mult = float(row[S_POWER])
	skill.radius = float(row[S_RADIUS])
	skill.cooldown_ticks = _ticks(float(row[S_COOLDOWN]))
	skill.mp_cost = float(row[S_MANA])

	bad = _apply_extra(skill, row[S_EXTRA])
	if bad != "":
		return "%s 的额外那一列：%s" % [key, bad]

	# 校验走加载器那一份（它拦「写了 damage」和「什么都不做的技能」两条）。
	bad = PBSkillLoader.check(skill)
	if bad != "":
		return "%s：%s" % [key, bad]

	var err := ResourceSaver.save(skill, "%s/%s.tres" % [SKILL_DIR, key])
	if err != OK:
		return "%s 存不下来（%d）" % [key, err]
	var owner_key: String = row[S_OWNER]
	# `-` = 不进任何人的指令卡：阵亡时放的那几个，由羁绊补丁 `on_death` 发给成员。
	if owner_key == "-":
		return ""
	if not owned.has(owner_key):
		owned[owner_key] = PackedStringArray()
	owned[owner_key].append(key)
	return ""


## `键=值;键=值`。**不认识的键返回错误，不跳过。**
func _apply_extra(skill: PBSkill, text: String) -> String:
	for piece: String in text.split(";"):
		var one: String = piece.strip_edges()
		if one == "":
			continue
		var halves: PackedStringArray = one.split("=")
		if halves.size() != 2:
			return "写歪了：%s" % one
		var name: String = halves[0].strip_edges()
		var value: String = halves[1].strip_edges()
		if not EXTRA_KEYS.has(name):
			return "不认识的键：%s（认得的：%s）" % [name, ", ".join(EXTRA_KEYS)]
		var value_error := _extra_value_error(name, value)
		if value_error != "":
			return value_error
		if name in BUFF_LINK_KEYS:
			var error := _set_effects(skill, name, value)
			if error != "":
				return error
			continue
		match name:
			"heal_aura_flat", "heal_aura_growth", "heal_aura_max", "heal_aura_hit_chance", "heal_aura_lost":
				skill.set(name, float(value))
			"heal_aura_period":
				skill.heal_aura_period_ticks = _ticks(float(value))
			"variant_first", "target_nonhero_only":
				skill.set(name, value == "1")
			"target_current_hp":
				skill.target_current_hp = float(value)
			"area_refresh":
				for seconds: String in value.split(","):
					if not seconds.is_valid_float() or not is_finite(float(seconds)):
						return "范围控制时刻必须为有限数值"
					skill.area_refresh_ticks.append(_ticks(float(seconds)))
			"pulse_delay":
				skill.pulse_delay_ticks = _ticks(float(value))
			"hit_levels":
				for count: String in value.split(","):
					skill.hit_count_levels.append(int(count))
			"variant":
				skill.variant_id = StringName(value)
			"zone_seconds", "zone_radius", "zone_ring_radius", "zone_outer_radius", "enemy_aura_radius":
				skill.set(name, float(value))
			"zone_ring_count", "zone_outer_count", "attack_chain_count", "attack_repeat_count":
				skill.set(name, int(value))
			"cost_levels":
				for cost: String in value.split(","):
					skill.mp_cost_levels.append(float(cost))
			"phantom_count":
				skill.phantom_count = int(value)
			"phantom_element":
				skill.phantom_element = ELEMENTS[value]
			"delay":
				skill.delay_ticks = _ticks(float(value))
			"fly":
				skill.shot_cross_seconds = float(value)
			"shot":
				skill.shot_key = StringName(value)
			"targets":
				skill.max_targets = int(value)
			"gather":
				skill.gather = value != "0"
			"knockback":
				skill.knockback = float(value)
			"blink":
				skill.blink_to_target = value == "1"
			"mind_control":
				skill.mind_control = value == "1"
			"channel_control":
				skill.channel_control = value == "1"
			"extra_from_caster":
				skill.extra_target_from_caster = value == "1"
			"sacrifice_transfer":
				skill.sacrifice_transfer = value == "1"
			"ranged_attack_aura":
				skill.ranged_attack_aura = float(value)
			"attack_chance":
				skill.attack_trigger_chance = float(value)
			"attack_chain_step", "self_attack_bonus", "self_attack_bonus_growth":
				skill.set(name, float(value))
			"followup":
				skill.followup_id = StringName(value)
			"radius_growth":
				skill.radius_growth = float(value)
			"travel_step":
				skill.travel_step = float(value)
			"waves":
				skill.wave_count = int(value)
			"wave_interval":
				skill.wave_interval_ticks = _ticks(float(value))
			"fan_spread":
				skill.fan_spread_degrees = float(value)
			"fan_steps":
				skill.fan_steps = int(value)
			"attack_speed_aura", "attack_speed_aura_growth", "move_speed_aura":
				skill.set(name, float(value))
			"slow":
				skill.slow_scale = float(value)
			"slow_secs":
				skill.slow_ticks = _ticks(float(value))
			"summon":
				skill.summon_count = int(value)
			"summon_power":
				skill.summon_power = float(value)
			"summon_growth":
				skill.summon_power_growth = float(value)
			"summon_focus":
				skill.summon_focus = value == "1"
			"summon_hp":
				skill.summon_hp_share = float(value)
			"summon_secs":
				skill.summon_seconds = float(value)
			"summon_lifesteal":
				skill.summon_lifesteal = float(value)
			"carry":
				skill.carry_over_ticks = _ticks(float(value))
			"base":
				skill.damage_base = float(value)
			"growth":
				skill.damage_growth = float(value)
			"stat":
				skill.damage_stat = StringName(value)
			"stat_floor":
				skill.damage_stat_floor = value == "1"
			"hp":
				skill.damage_hp = float(value)
			"death_move":
				skill.death_move_ticks = _ticks(float(value))
			"target_hp", "center_scale", "damage_cap", "line_length":
				skill.set(name, float(value))
			"pulse_radius_step", "pulse_damage_step":
				skill.set(name, float(value))
			"scatter_steps", "volley_size":
				skill.set(name, int(value))
			"hits":
				skill.hit_count = int(value)
			"control_radius":
				skill.control_radius = float(value)
			"interval", "hit_radius":
				if name == "interval":
					skill.hit_interval_ticks = _ticks(float(value))
				else:
					skill.hit_radius = float(value)
	return _shot_usage_error(skill)


func _shot_usage_error(skill: PBSkill) -> String:
	if skill.shot_key != &"" and not PBArtBindings.can_bind_shot(skill):
		return "shot 需要真实弹道或带延迟的地面技能"
	return ""


func _set_effects(skill: PBSkill, name: String, value: String) -> String:
	var list: Array[PBBuff] = []
	for one_key: String in value.split(","):
		var buff_key: String = one_key.strip_edges()
		if not _buffs.has(buff_key):
			return "查不到效果：%s" % buff_key
		list.append(_buffs[buff_key])
	if name == "transfer_buff":
		if list.size() != 1:
			return "赠予 BUFF 必须恰好指定一份"
		skill.transfer_buff = list[0]
	else:
		skill.set(name, list)
	return ""


func _level_list_error(name: String, value: String) -> String:
	if name == "shot":
		if PBShotForge.key_error(value) != "":
			return "子弹键不合法：%s" % value
		var path := "res://data/shots/%s.tres" % value
		if not ResourceLoader.exists(path) or not load(path) is PBShotSkin:
			return "子弹资源不存在或类型错误：%s" % value
	if name == "hit_levels":
		for count: String in value.split(","):
			if not count.is_valid_int() or int(count) < 2:
				return "分级连击次数须为至少两段的整数"
	if name == "cost_levels":
		for cost: String in value.split(","):
			if not cost.is_valid_float() or not is_finite(float(cost)) or float(cost) < 0.0:
				return "各级耗蓝必须用逗号分隔有限非负数"
	return ""


## 有格式约束的扩展字段先校验，再由解析分派写值。
func _extra_value_error(name: String, value: String) -> String:
	var level_error := _level_list_error(name, value)
	if level_error != "":
		return level_error
	if (
		(
			name
			in [
				"scatter_steps",
				"volley_size",
				"hits",
				"phantom_count",
				"waves",
				"fan_steps",
				"zone_ring_count",
				"zone_outer_count",
				"attack_chain_count",
				"attack_repeat_count"
			]
		)
		and not value.is_valid_int()
	):
		return "%s 必须是整数" % name
	if name == "phantom_element" and not ELEMENTS.has(value):
		return "幻影攻击属性不合法：%s" % value
	if (
		(
			name
			in [
				"summon_focus",
				"variant_first",
				"target_nonhero_only",
				"blink",
				"stat_floor",
				"channel_control",
				"mind_control",
				"extra_from_caster",
				"sacrifice_transfer"
			]
		)
		and value != "0"
		and value != "1"
	):
		return "%s 必须是 0 或 1" % name
	if (
		name
		in [
			"summon_growth",
			"heal_aura_flat",
			"heal_aura_growth",
			"heal_aura_max",
			"heal_aura_period",
			"heal_aura_hit_chance",
			"heal_aura_lost",
			"enemy_aura_radius",
			"attack_chance",
			"attack_chain_step",
			"self_attack_bonus",
			"self_attack_bonus_growth",
			"zone_seconds",
			"zone_radius",
			"zone_ring_radius",
			"zone_outer_radius",
			"pulse_delay",
			"target_current_hp",
			"ranged_attack_aura",
			"attack_speed_aura",
			"attack_speed_aura_growth",
			"move_speed_aura",
			"radius_growth",
			"travel_step",
			"wave_interval",
			"fan_spread",
			"interval",
			"control_radius",
			"hit_radius",
			"target_hp",
			"center_scale",
			"damage_cap",
			"death_move",
			"line_length",
			"pulse_radius_step",
			"pulse_damage_step"
		]
	):
		if not value.is_valid_float() or not is_finite(float(value)) or float(value) < 0.0:
			return "%s 必须是有限非负数" % name
	return ""


## 秒换 tick。**至少 1** —— 0 tick 的窗口等于没有这一段。
func _ticks(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	return maxi(int(round(seconds * float(PBSimConfig.new().tick_rate))), 1)


## 把「谁有哪几个技能」写回角色表。**表里没有的角色一律清空。**
func _attach(owned: Dictionary) -> void:
	var dir := DirAccess.open(CHAR_DIR)
	if dir == null:
		printerr("打不开 %s" % CHAR_DIR)
		return
	var touched: int = 0
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var key: String = file_name.get_basename()
		var path: String = "%s/%s" % [CHAR_DIR, file_name]
		var character: PBCharacter = ResourceLoader.load(path) as PBCharacter
		if character == null:
			continue
		var want: Array[StringName] = []
		for one: String in owned.get(key, PackedStringArray()):
			want.append(StringName(one))
		if character.skill_ids == want:
			continue
		character.skill_ids = want
		ResourceSaver.save(character, path)
		touched += 1
	print("角色表更新了 ", touched, " 个的 skill_ids")


## 表里没有的 `.tres` 一律删掉，否则拿走的技能文件会一直被加载器扫进来。
func _sweep(folder: String, wanted: Dictionary) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		if wanted.has(file_name.get_basename()):
			continue
		dir.remove(file_name)
		print("删掉表上没有的：", file_name.get_basename())
