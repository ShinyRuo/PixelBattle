class_name PBFormationRules
extends RefCounted
## 开战位置：谁站在哪（§02）。全部 static，零引擎依赖。
##
## **不进 [method PBCombatRules.build_attackers]**：建攻击者是把卡摊成场上的样子，
## 摆位是玩家的一次输入，覆盖在那个结果上。空 [member PBRunState.formation] 时
## [method apply] 什么都不做，没摆过的人照旧按射程档站。


## 把玩家摆的位置盖到已经建好的攻击者上。[param attackers] 会被就地改。
##
## [param deployed] 与攻击者的 `slot` 对应（[method PBCombatRules.build_attackers]）。
## 尾兽那一个（`slot < 0`）跳过：它没有本体，位置恒为 0。
##
## **`pos` 和 `home` 一起写。** 只写 `home` 的话开波第一 tick 会从旧位置
## 走过去（[method PBAttacker.revive] 只在会动的单位上重置 `pos`），
## 玩家看到的是「我摆的位置不对，他自己跑了」。
static func apply(
	attackers: Array[PBAttacker], deployed: Array[PBUnit], formation: Dictionary, cfg: PBSimConfig
) -> void:
	if formation.is_empty():
		return
	for attacker: PBAttacker in attackers:
		if attacker.slot < 0 or attacker.slot >= deployed.size():
			continue
		var key: StringName = deployed[attacker.slot].key()
		if not formation.has(key):
			continue
		attacker.home = clamp_spot(formation[key] as Vector2, cfg)
		attacker.pos = attacker.home


## 把一个位置夹进合法范围：x 在 `[0, deploy_limit_x]`，y 在 `[0, field_height]`。
##
## **夹而不是拒绝** —— 拒绝的话玩家拖到界限外松手就什么都没发生，
## 他不知道是没拖动还是不让摆。夹回来至少把「最远只能到这」演示了一遍。
static func clamp_spot(at: Vector2, cfg: PBSimConfig) -> Vector2:
	return Vector2(
		clampf(at.x, 0.0, cfg.deploy_limit_x), clampf(at.y, 0.0, cfg.field_height)
	)


## 玩家把 [param unit] 摆到了 [param at]。**界面只走这一条路。**
##
## 和花钱、排名单同一个理由（见 [PBShopRules] 顶部）：状态只由规则层改，
## 界面自己往 [member PBRunState.formation] 里塞 Vector2 迟早漏掉夹取，
## 而一个摆在战场之外的忍者不报错 —— 他只是画在屏幕外面，然后一发都打不着。
static func place(state: PBRunState, unit: PBUnit, at: Vector2, cfg: PBSimConfig) -> void:
	if unit == null:
		return
	state.formation[unit.key()] = clamp_spot(at, cfg)


## 把某个人的摆位撤掉，交回按射程档自动站位。
static func reset(state: PBRunState, unit: PBUnit) -> void:
	if unit != null:
		state.formation.erase(unit.key())


## 出战席第 [param index] 个人（共 [param count] 个）现在站在哪。
##
## 摆过就用摆的，没摆过就按射程档算 —— **和 [method PBCombatRules.build_attackers]
## 里那两行必须给出同一个答案**。准备阶段画在战场上的那个方块靠它定位，
## 两处分叉的表现是「我摆好的阵型，一开打就跳了一下」。
static func spot_of(
	unit: PBUnit, index: int, count: int, formation: Dictionary, cfg: PBSimConfig
) -> Vector2:
	var key: StringName = unit.key()
	if formation.has(key):
		return clamp_spot(formation[key] as Vector2, cfg)
	return Vector2(cfg.reach_column(unit.character.reach_tier()), cfg.ally_lane(index, count))


## 整队现在站在哪，与 [param units] 同序。画面和命中测试共用这一份 ——
## 各算各的话「画在哪」和「点得到哪」会差开，而那表现为「点不中我看见的那个人」。
static func spots_of(
	units: Array[PBUnit], formation: Dictionary, cfg: PBSimConfig
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in units.size():
		out.append(spot_of(units[i], i, units.size(), formation, cfg))
	return out
