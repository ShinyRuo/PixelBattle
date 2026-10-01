class_name PBEffectWords
extends RefCounted
## 技能、效果、羁绊**写成人看得懂的几句话**。三张说明卡（指令卡的技能格、信息卡的 buff 格、羁绊行）共用这一处。
##
## **一处写，别处调**：同一份效果在技能卡里写「移速 ×0.70」、在 buff 卡里写「减速 30%」的话，
## 玩家会以为是两个东西，而它不报错。所以效果键 → 句子只有 [method buff_words] 这一条路。
##
## **只写真的进战斗的数**：一律从数据现生成，不另写一份描述文字 —— 手写的描述和数据迟早对不上。
## 句式在语言表里（`buff_fx.*` / `patch.*` / `mod.*`），每个键都有一条，`tests/test_effect_words.gd` 钉着。

const TARGET_WORDS := {
	PBSkill.Target.NONE: "直接施放",
	PBSkill.Target.ALLY: "点队友",
	PBSkill.Target.ENEMY: "点敌人",
	PBSkill.Target.GROUND: "点地面",
}

## 按成数记、显示时要乘 100 的效果键（句式里是 `%`）。
const PERCENT_KEYS: Array[StringName] = [
	PBBuffRules.STRENGTH_BONUS,
	PBBuffRules.ALL_STATS_BONUS,
	PBBuffRules.BASE_ATTACK_BONUS,
	PBBuffRules.CRIT_CHANCE,
	PBBuffRules.CRIT_DAMAGE,
	PBBuffRules.HEAL_MAX,
	PBBuffRules.DRAIN_MAX,
	PBBuffRules.DODGE,
	PBBuffRules.ENEMY_RESIST,
	PBBuffRules.NINJUTSU_RESIST,
	PBBuffRules.REFLECT,
]


## 技能卡的标题：`名字（属性）`。
static func skill_title(skill: PBSkill) -> String:
	return "%s（%s）" % [PBLocale.of_skill(skill), PBUnitTile.ELEMENT_NAMES.get(skill.element, "?")]


## 技能卡的正文。[param level] 是施法者等级（效果的量随它长，见 [method PBBuffRules.resolve]）。
##
## 战斗中传进来的是这一波打过羁绊补丁、算好伤害的那一份（[member PBSkill.damage] 非 0），
## 准备阶段传的是表里那一份，只写得出倍率。
static func skill_body(skill: PBSkill, cfg: PBSimConfig, level: int = 1) -> String:
	if PBHealingAuraRules.enabled(skill):
		return PBHealingAuraWords.body(skill, cfg, level)
	if skill.attack_chain_count > 0 or skill.attack_trigger_chance > 0.0:
		return PBOnAttackWords.body(skill, cfg, level)
	if PBMotionAuraRules.enabled(skill):
		var reach: String = "仅自身" if skill.radius <= 0.0 else "周围友军（含自身），范围 %.2f" % skill.radius
		return (
			"被动光环　%s\n攻击速度 +%.0f%%，移动速度 +%.0f%%\n同类取最高；离开范围或载体倒下即失效\n不耗蓝，无需施放"
			% [
				reach,
				(
					(skill.attack_speed_aura + skill.attack_speed_aura_growth * maxi(level - 1, 0))
					* 100.0
				),
				skill.move_speed_aura * 100.0
			]
		)
	if skill.ranged_attack_aura > 0.0:
		return (
			("被动光环　范围 %.2f\n周围远程单位基础攻击力 +%.0f%%（含自身）" + "\n同类取最高；离开范围或施法者倒下即失效\n不耗蓝，无需施放")
			% [skill.radius, skill.ranged_attack_aura * 100.0]
		)
	var lines := PackedStringArray()
	var head := PackedStringArray([TARGET_WORDS.get(skill.target, "?")])
	if skill.damage > 0.0:
		var label: String = "每段伤害 %.0f" if skill.hit_count > 1 else "伤害 %.0f"
		if skill.travel_step > 0.0:
			label = "每道伤害 %.0f"
		head.append(label % skill.damage)
	elif skill.power_mult > 0.0 or skill.damage_base > 0.0 or skill.damage_hp > 0.0:
		var labels: Dictionary = {
			&"attack": "攻击力",
			&"intellect": "智力",
			&"agility": "敏捷",
			&"strength": "力量",
			&"max_hp": "最大生命"
		}
		var fixed: float = skill.damage_base + skill.damage_growth * float(maxi(level - 1, 0))
		head.append(
			"基础 %.0f + %s × %.2f" % [fixed, labels[PBSkillDamage.stat_of(skill)], skill.power_mult]
		)
		if skill.damage_hp > 0.0:
			head.append("最大生命 × %.0f%%" % (skill.damage_hp * 100.0))
	if skill.affects == PBSkill.Party.ENEMIES:
		if _has_damage(skill):
			head.append("体术伤害" if skill.kind == PBDamageKind.Type.TAIJUTSU else "忍术伤害")
		else:
			head.append("无直接伤害")
	if skill.line_length > 0.0:
		head.append("前方直线长 %.2f、宽 %.2f" % [skill.line_length, skill.radius * 2.0])
	elif skill.radius > 0.0:
		head.append("范围 %.2f" % skill.radius)
	if skill.max_targets > 0:
		head.append("最多 %d 个目标" % skill.max_targets)
	lines.append("　".join(head))
	var rate: float = float(maxi(cfg.tick_rate, 1))
	lines.append(
		(
			"冷却 %.0f 秒　耗蓝 %.0f"
			% [float(skill.cooldown_ticks) / rate, PBSkillCostRules.mana(skill, level)]
		)
	)
	if skill.hit_count > 1:
		if skill.scatter_steps > 0:
			lines.append(
				(
					"共 %d 段，每 %.2f 秒同时 %d 段，共 %d 轮"
					% [
						skill.hit_count,
						skill.hit_interval_ticks / rate,
						skill.volley_size,
						skill.hit_count / skill.volley_size
					]
				)
			)
			lines.append("跟随当前位置随机落雷；源死亡后继续，交叠可重复命中")
		elif skill.travel_step > 0.0:
			lines.append(
				(
					"共 %d 道，每 %.2f 秒发射；向前扩散，每道对同一目标只命中一次"
					% [skill.wave_count, skill.wave_interval_ticks / rate]
				)
			)
		elif skill.pulse_radius_step > 0.0:
			lines.append(
				(
					("每 %.2f 秒扩圈一次，共 %d 次；每次只选最近的未命中目标" + "\n伤害从 %.0f%% 逐段增至 %.0f%%；空圈也消耗次数")
					% [
						skill.hit_interval_ticks / rate,
						skill.hit_count,
						(1.0 + skill.pulse_damage_step) * 100.0,
						(1.0 + skill.pulse_damage_step * skill.hit_count) * 100.0
					]
				)
			)
		else:
			lines.append(
				(
					"共 %d 段，每 %.2f 秒 1 段；各段独立判定命中"
					% [skill.hit_count, float(skill.hit_interval_ticks) / rate]
				)
			)
		if skill.hit_radius > 0.0:
			lines.append("区域内分散落点，每段半径 %.4f；单个目标不一定全中" % skill.hit_radius)
	if skill.rescue_radius > 0:
		lines.append("救援光环范围 %.2f：忍者实际受伤>5且生命≤50%%时，每波每人一次" % skill.rescue_radius)
		lines.append("双方最大生命须≥400；12秒恢复650×受益者等级，非瞬间治疗")
	if skill.control_radius > 0:
		lines.append("控制范围 %.4f，伤害范围 %.4f" % [skill.control_radius, skill.radius])
	lines.append_array(_skill_extras(skill, rate, level))
	if skill.recast != null:
		lines.append(
			(
				"本回合仅首次施放；之后恢复【%s】（%d 段）"
				% [PBLocale.of_skill(skill.recast), skill.recast.hits_at(level)]
			)
		)
	for buff: PBBuff in skill.on_start_area:
		lines.append("仅起手圈内目标：" + buff_line(buff, level))
	if skill.pulse_delay_ticks > 0:
		lines.append("固定落点；首段在 %.2f 秒后，后进入者不补挂起手控制" % (skill.pulse_delay_ticks / rate))
	if not skill.on_start_target.is_empty():
		for buff: PBBuff in skill.on_start_target:
			lines.append("起手主目标：" + buff_line(buff, level))
		lines.append("%.1f 秒后结算伤害与命中效果" % (skill.delay_ticks / rate))
	for buff: PBBuff in skill.on_hit:
		lines.append("命中附带：" + buff_line(buff, level))
	for buff: PBBuff in skill.on_self:
		lines.append("自身获得：" + buff_line(buff, level))
	for buff: PBBuff in skill.on_target:
		lines.append(("范围附带：" if skill.target_effect_area else "主目标附带：") + buff_line(buff, level))
	lines.append_array(_followup_words(skill, cfg, level))
	return "\n".join(lines)


static func _followup_words(skill: PBSkill, cfg: PBSimConfig, level: int) -> PackedStringArray:
	var lines := PackedStringArray()
	if not skill.followup_enabled:
		return lines
	var child: PBSkill = skill.followup
	if child == null and cfg.skills != null:
		child = cfg.skills.by_id(skill.followup_id)
	if child == null or child.followup_id != &"":
		return lines
	lines.append(
		"附加【%s】：%.1f 秒后开始" % [PBLocale.of_skill(child), float(child.delay_ticks) / cfg.tick_rate]
	)
	for line: String in skill_body(child, cfg, level).split("\n"):
		if not line.begins_with("冷却"):
			lines.append(line.trim_prefix("点地面　"))
	return lines


## 控制技能不能凭伤害类型字段就显示有伤害；周期效果也属于伤害来源。
static func _has_damage(skill: PBSkill) -> bool:
	if (
		skill.damage > 0.0
		or skill.damage_base > 0.0
		or skill.damage_growth > 0.0
		or skill.power_mult > 0.0
		or skill.damage_hp > 0.0
	):
		return true
	for buff: PBBuff in skill.on_hit:
		if buff.mods.has(PBBuffRules.HARM):
			return true
	return false


## 一份效果写成一行：`名字（N 秒）：词条、词条`。
static func buff_line(buff: PBBuff, level: int) -> String:
	var name: String = PBLocale.text(buff.name_key)
	var words := "、".join(buff_words(PBBuffRules.resolve(buff, level)))
	if buff.harm_stat != &"":
		var labels: Dictionary = {
			&"strength": "力量",
			&"agility": "敏捷",
			&"intellect": "智力",
			&"attack": "攻击力",
			&"max_hp": "最大生命"
		}
		words += "；每跳另加%s × %s" % [labels.get(buff.harm_stat, "?"), _secs(buff.harm_mult)]
	if buff.kind == PBBuff.Kind.INSTANT:
		return "%s：%s" % [name, words]
	if buff.until_wave_end:
		return "%s（本波有效，可撤销）：%s" % [name, words]
	if buff.kind == PBBuff.Kind.PERIODIC:
		if buff.independent_stacks:
			words += "；每次命中独立叠层，各层单独到期"
		return (
			"%s（%s 秒，每 %s 秒）：%s"
			% [name, _secs(buff.seconds_at(level)), _secs(buff.period_seconds), words]
		)
	return "%s（%s 秒）：%s" % [name, _secs(buff.seconds_at(level)), words]


## buff 格悬停卡的标题：`名字　增益/减益`。
static func buff_title(buff: PBBuff) -> String:
	return "%s　%s" % [PBLocale.text(buff.name_key), "增益" if buff.friendly else "减益"]


## buff 格悬停卡的正文：还剩多久、每几秒一跳、给了什么。量取**挂着的那一份**（[member PBBuffState.mods]），
## 不从表里重算 —— 施法者等级、叠加刷新都已经落在那一份上。
static func buff_body(state: PBBuffState, at_tick: int, cfg: PBSimConfig) -> String:
	var rate: float = float(maxi(cfg.tick_rate, 1))
	var lines := PackedStringArray(["还剩 %s 秒" % _secs(float(state.left(at_tick)) / rate)])
	if state.buff.until_wave_end:
		lines[0] = "本波有效；取消或被挤出即撤销"
	if state.buff.kind == PBBuff.Kind.PERIODIC:
		lines.append("每 %s 秒一次" % _secs(state.buff.period_seconds))
	var mods: Dictionary = state.mods if not state.mods.is_empty() else state.buff.mods
	lines.append_array(buff_words(mods))
	return "\n".join(lines)


## 一份效果键表写成几个词。**两个特例**：移速 ×0 写「定身」、受到伤害 ×0 写「无敌」——
## 写成「×0.00」读起来像是数据坏了。
static func buff_words(mods: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in mods:
		var value: float = float(mods[key])
		if key == PBBuffRules.ENEMY_SPEED_SCALE and is_zero_approx(value):
			out.append(PBLocale.text("buff_fx.rooted"))
		elif key == PBBuffRules.DAMAGE_TAKEN and is_zero_approx(value):
			out.append(PBLocale.text("buff_fx.invincible"))
		else:
			out.append(_fill("buff_fx.%s" % key, value * (100.0 if PERCENT_KEYS.has(key) else 1.0)))
	return out


## 羁绊满档给什么，一条一行：战力加成、功能（谁带）、每个成员自己的那一份、技能补丁。
static func bond_effects(bond: PBBond, cfg: PBSimConfig) -> PackedStringArray:
	var full: int = bond.full_tier_count()
	var out := PackedStringArray()
	var power: float = bond.bonus_at(full)
	if power > 0.0:
		out.append("战力 +%.0f%%" % (power * 100.0))
	var function: StringName = bond.function_at(full)
	if function != &"":
		var carrier := _name_of(bond.function_carrier_at(full), cfg)
		var who: String = "（由 %s 带）" % carrier if carrier != "" else ""
		out.append("%s%s" % [PBLocale.of_bond_function(function), who])
	for id: StringName in bond.member_functions:
		var words := PBShopLabels.mod_words(bond.member_functions[id])
		out.append("%s：%s" % [_name_of(id, cfg), "、".join(words)])
	for id: StringName in bond.member_buffs:
		for buff: PBBuff in bond.member_buffs[id]:
			out.append("%s 开场：%s" % [_name_of(id, cfg), buff_line(buff, 1)])
	for id: StringName in bond.member_skill_patches:
		var patches: Dictionary = bond.member_skill_patches[id]
		for skill_id: StringName in patches:
			var skill: PBSkill = cfg.skills.by_id(skill_id) if cfg.skills != null else null
			var skill_name: String = PBLocale.of_skill(skill) if skill != null else String(skill_id)
			out.append(
				(
					"%s 的 %s：%s"
					% [_name_of(id, cfg), skill_name, "、".join(patch_words(patches[skill_id]))]
				)
			)
			if skill != null and skill.attack_chain_count > 0:
				var description := skill.clone()
				description.kind = PBDamageKind.skill_kind(cfg.characters.by_id(id).element)
				out.append(PBOnAttackWords.details(description, cfg))
	return out


## 一份技能补丁写成几个词。
static func patch_words(patch: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for key: StringName in patch:
		var value: float = float(patch[key])
		if (
			key
			in [
				PBSkillPatchRules.RANGED_ATTACK_AURA_SET,
				PBSkillPatchRules.ON_ATTACK_CHANCE,
				PBSkillPatchRules.HEAL_AURA_MAX_SET,
				PBSkillPatchRules.HEAL_AURA_HIT_CHANCE,
				PBSkillPatchRules.HEAL_AURA_LOST
			]
		):
			value *= 100.0
		out.append(_fill("patch.%s" % key, value))
	return out


## 技能定义里那几项「顺带做的事」。
static func _skill_extras(skill: PBSkill, rate: float, level: int) -> PackedStringArray:
	var out := PackedStringArray()
	if skill.zone_seconds > 0.0:
		out.append("紫圈为伤害范围，浅绿边界为减益光环范围")
		out.append("固定地面区域，每段重新检查范围；离开伤害区后不再受伤")
		out.append("首段伤害在 %.2f 秒后" % ((skill.delay_ticks + skill.hit_interval_ticks) / rate))
		if skill.delay_ticks > 0:
			out.append("地面区域在 %.2f 秒后生效" % (skill.delay_ticks / rate))
		out.append(
			(
				"另有 %d 个减益光环，半径 %.3f，存在 %.1f 秒"
				% [
					skill.zone_ring_count + skill.zone_outer_count + 1,
					skill.zone_radius,
					skill.zone_seconds
				]
			)
		)
		for buff: PBBuff in skill.zone_effects:
			out.append(
				(
					"%s，离开光环后保留 %.1f 秒"
					% [
						"、".join(buff_words(PBBuffRules.resolve(buff, level))),
						buff.seconds_at(level)
					]
				)
			)
		for buff: PBBuff in skill.zone_ring_effects:
			out.append(
				(
					"外围光环：%s；离圈保留 %.1f 秒"
					% [
						"、".join(buff_words(PBBuffRules.resolve(buff, level))),
						buff.seconds_at(level)
					]
				)
			)
	if skill.rebate_delay_ticks > 0:
		out.append(
			(
				"落地 %.2f 秒后返还 %.0f 蓝，并将剩余冷却设为 %.1f 秒"
				% [
					skill.rebate_delay_ticks / rate,
					PBSkillCostRules.mana(skill, level) * skill.rebate_mana_scale,
					skill.rebate_cooldown_ticks / rate
				]
			)
		)
	if skill.radius_growth > 0.0:
		out.append(
			(
				"各段范围 %.4f → %.4f"
				% [skill.radius, skill.radius + skill.radius_growth * (skill.hit_count - 1)]
			)
		)
	if skill.phantom_count > 0:
		out.append(
			(
				("每次远程命中留下 %d 个无敌幻影，继承 %.0f%% 攻击与体术暴击率，持续 %.1f 秒" + "\n结束时若最后命中目标为远程，本体瞬移至其身边")
				% [skill.phantom_count, skill.summon_power * 100.0, skill.summon_seconds]
			)
		)
	if skill.gather:
		out.append("把敌人聚拢到落点")
	if skill.sacrifice_transfer:
		out.append("选择另一名忍者；召唤物不能接受三围转化")
		out.append(
			(
				"将自身三围的 99%% 按 %.0f%% 转化给队友（逐项取整），持续到战斗结束；自身 5 秒后死亡"
				% [(0.1 + 0.03 * level) * skill.transfer_scale * 100.0]
			)
		)
	if skill.channel_control:
		out.append("需要持续施法，期间不能移动或出手；中断时解除本次禁锢")
	if skill.mind_control:
		out.append("需要持续施法；主目标等级更低时临时转为友方，否则眩晕；中断时解除主目标控制")
		if skill.max_targets > 1:
			out.append("追加目标只眩晕，持续时间 ×%.1f，独立于主目标引导" % skill.extra_control_scale)
	if skill.impact_hold_radius > 0.0:
		out.append(
			"命中时禁锢目标周围 %.3f 范围内的其他敌人 %.1f 秒" % [skill.impact_hold_radius, skill.impact_hold_seconds]
		)
	if skill.extra_target_radius > 0.0 and skill.max_targets > 1:
		var center: String = "施法者" if skill.extra_target_from_caster else "主目标"
		out.append("优先主目标，再选%s周围 %.2f 范围内最近的目标" % [center, skill.extra_target_radius])
	if skill.hit_step > 0.0:
		out.append("向前蔓延 %d 次，每段前进 %.2f；出手后独立生效" % [skill.hit_count - 1, skill.hit_step])
	if skill.first_cast_attack > 0.0:
		out.append("每回合首次施放追加总攻击力 ×%.1f 伤害" % skill.first_cast_attack)
	if skill.target_hp > 0.0:
		out.append("另加目标最大生命 %.0f%%" % (skill.target_hp * 100.0))
	if skill.target_current_hp > 0.0:
		out.append(
			(
				"%s主伤害后，再造成剩余生命 %.1f%% 的伤害"
				% ["非英雄目标：" if skill.target_nonhero_only else "", skill.target_current_hp * 100.0]
			)
		)
	if skill.center_scale > 1.0:
		out.append("圆心伤害 ×%.1f，向边缘线性降至 ×1" % skill.center_scale)
	if skill.full_damage_radius > 0.0:
		out.append(
			(
				"内圈 %.0f 码全额伤害，新增外圈仅 %.0f%%"
				% [skill.full_damage_radius * 2000.0, skill.outer_damage_scale * 100.0]
			)
		)
	if skill.damage_cap > 0.0:
		out.append("原始公式上限 %.0f（增伤、暴击与减伤前）" % skill.damage_cap)
	if skill.death_move_ticks > 0:
		out.append("阵亡后向击杀来源移动 %s 秒再施放" % _secs(skill.death_move_ticks / rate))
	if skill.knockback > 0.0:
		out.append("击退敌人")
	if skill.blink_to_target:
		out.append("闪到目标后侧近身攻击")
	if skill.echo_delay_ticks > 0:
		out.append(
			(
				"施放 %.1f 秒后原地再造成一次伤害，范围 ×%.1f，不附带控制"
				% [skill.echo_delay_ticks / rate, skill.echo_radius_scale]
			)
		)
	if skill.slow_ticks > 0:
		out.append("全场减速 ×%.2f（%s 秒）" % [skill.slow_scale, _secs(float(skill.slow_ticks) / rate)])
	if skill.team_damage_scale > 1.0 and skill.buff_ticks > 0:
		out.append(
			"全队伤害 ×%.2f（%s 秒）" % [skill.team_damage_scale, _secs(float(skill.buff_ticks) / rate)]
		)
	if skill.reset_cooldowns:
		out.append("重置队友的技能冷却")
	if skill.summon_count > 0:
		out.append("召唤 %d 个（%s 秒）" % [skill.summon_count, _secs(skill.summon_seconds)])
		out.append("每个继承本体 %.0f%% 攻击力" % (skill.summon_power_at(level) * 100.0))
		if skill.summon_focus:
			out.append("优先追击施法目标；目标消失后自行索敌")
	return out


## 句式里有 `%` 才填数（「定身」「晕眩」那种没有）。直接 `%` 一个不带占位符的串会报错。
static func _fill(key: String, value: float) -> String:
	var pattern: String = PBLocale.text(key)
	return pattern % value if pattern.contains("%") else pattern


static func _name_of(id: StringName, cfg: PBSimConfig) -> String:
	if id == &"" or cfg.characters == null:
		return ""
	var character: PBCharacter = cfg.characters.by_id(id)
	return PBLocale.of_character(character) if character != null else String(id)


## 秒数：先取到一位小数，是整数就不带小数点（「5 秒」不写「5.0 秒」）。
## **先取整再判**：剩余 tick 除以帧率常常差一点点不是整数（101 / 20），直接判的话满屏都是「.0」。
static func _secs(value: float) -> String:
	var tenth: float = snappedf(value, 0.1)
	return "%d" % roundi(tenth) if is_equal_approx(tenth, roundf(tenth)) else "%.1f" % tenth
