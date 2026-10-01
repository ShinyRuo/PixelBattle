class_name PBSkillChannel
extends RefCounted
## 一次锁定控制的引导凭据。弱引用避免施法者 / 效果之间形成引用环。
## 失效后不可恢复；每次施法新建凭据，旧效果不会被下一次引导重新激活。

var active: bool = true
var caster_ref: WeakRef
var target_ref: WeakRef
var effect_ref: WeakRef


static func blocked(caster: PBAttacker, tick: int) -> bool:
	return (
		(caster.channel != null and caster.channel.is_live(tick))
		or caster.buffs.amount(PBBuffRules.CHANNEL, tick) > 0.0
	)


static func validate(skill: PBSkill) -> String:
	if not skill.channel_control:
		return ""
	if (
		skill.target != PBSkill.Target.ENEMY
		or skill.shot_cross_seconds <= 0.0
		or skill.radius > 0.0
		or skill.max_targets > 1
		or skill.on_hit.size() != 1
	):
		return "引导控制需要单体敌方弹道及一份持续控制效果"
	var buff: PBBuff = skill.on_hit[0]
	if buff.kind != PBBuff.Kind.DURATION or not buff.mods.has(PBBuffRules.STUN):
		return "引导控制的命中效果必须是持续禁锢"
	return ""


func is_live(tick: int) -> bool:
	active = valid_now(tick)
	return active


## 表现层只读查询；结算层通过 is_live 锁定中断，旧引导不会复活。
func valid_now(tick: int) -> bool:
	if not active:
		return false
	var live := true
	var caster: PBAttacker = null if caster_ref == null else caster_ref.get_ref()
	if caster == null or not caster.alive:
		live = false
	elif (
		caster.buffs.amount(PBBuffRules.STUN, tick) > 0.0
		or caster.buffs.amount(PBBuffRules.SILENCE, tick) > 0.0
	):
		live = false
	if target_ref != null:
		var target: PBEnemy = target_ref.get_ref()
		if target == null or not target.is_active(tick):
			live = false
	if effect_ref != null:
		var effect: PBBuffState = effect_ref.get_ref()
		if (
			effect == null
			or effect.channel != self
			or effect.buff == null
			or tick > effect.until_tick
		):
			live = false
	return live


func attach(enemy: PBEnemy, id: StringName, tick: int, primary: bool = false) -> void:
	for state: PBBuffState in enemy.buffs.states():
		if state.buff != null and state.buff.id == id and state.applied_at == tick:
			state.channel = self
			if primary:
				effect_ref = weakref(state)
