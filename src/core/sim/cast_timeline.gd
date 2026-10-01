class_name PBCastTimeline
extends RefCounted
## 主动技能的六帧动作：固定 0.6 秒，第 4 帧起点释放；不读取攻击速度。
## 只保存技能引用，不反向持有施法者。落地清理、二次技能切换不改变当前动作。

const SECONDS: float = 0.6
const FRAMES: int = 6
const CHANNEL_RECOVERY_SECONDS: float = 0.2

var started_at: int = -1
var releases_at: int = -1
var ends_at: int = -1
var skill_id: StringName = &""
var released: bool = false
var channel_action: bool = false
var recovery_started_at: int = -1
var _cast: PBSkillCast = null
var _paid: float = 0.0


static func interrupted(unit: PBAttacker, tick: int) -> bool:
	return (
		not unit.alive
		or unit.buffs.amount(PBBuffRules.STUN, tick) > 0.0
		or unit.buffs.amount(PBBuffRules.SILENCE, tick) > 0.0
	)


func begin(unit: PBAttacker, cast: PBSkillCast, cfg: PBSimConfig, tick: int) -> void:
	started_at = tick
	ends_at = tick + maxi(roundi(SECONDS * cfg.tick_rate), 2)
	releases_at = tick + maxi(roundi(SECONDS * 0.5 * cfg.tick_rate), 1)
	skill_id = cast.skill.id
	released = false
	channel_action = cast.skill.channel_control or cast.skill.mind_control
	recovery_started_at = -1
	_cast = cast
	_paid = PBSkillCostRules.mana(cast.skill, cast.caster_level)
	unit.pay(_paid)
	unit.swinging = false
	unit.attack_ends_at = -1
	cast.release_at = releases_at
	cast.lands_at = releases_at + cast.skill.delay_ticks
	cast.origin = unit.pos


func active(tick: int) -> bool:
	if started_at < 0 or tick < started_at:
		return false
	return channel_action or tick < ends_at


func frame_at(tick: int) -> int:
	if channel_action:
		if tick < releases_at:
			return clampi(
				int(float(tick - started_at) * 3.0 / maxi(releases_at - started_at, 1)), 0, 2
			)
		if recovery_started_at < 0:
			return 3
		var recovery_ticks := maxi(ends_at - recovery_started_at, 2)
		return 4 if tick - recovery_started_at < recovery_ticks / 2 else 5
	return clampi(int(float(tick - started_at) * FRAMES / maxi(ends_at - started_at, 1)), 0, 5)


func advance(unit: PBAttacker, cfg: PBSimConfig, tick: int, book: PBBattleLog) -> void:
	if started_at < 0:
		return
	if interrupted(unit, tick):
		cancel(unit)
		return
	if not released and tick >= releases_at:
		released = true
		PBSkillOrders.issue(unit, _cast, cfg, tick, book)
	if channel_action and released:
		if _cast != null and _cast.is_pending():
			return
		if unit.channel != null and unit.channel.valid_now(tick):
			return
		if recovery_started_at < 0:
			recovery_started_at = tick
			ends_at = tick + maxi(roundi(CHANNEL_RECOVERY_SECONDS * cfg.tick_rate), 2)
	if tick >= ends_at:
		reset()


## 释放前退还预扣查克拉，不触发冷却、首次机会或二次技能；释放后只终止收招。
func cancel(unit: PBAttacker) -> void:
	if _cast != null and not released:
		unit.restore_mana(_paid)
		_cast.cancel()
	reset()


func reset() -> void:
	started_at = -1
	releases_at = -1
	ends_at = -1
	skill_id = &""
	released = false
	channel_action = false
	recovery_started_at = -1
	_cast = null
	_paid = 0.0
