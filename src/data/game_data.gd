class_name PBGameData
extends RefCounted
## `data/` 下全部数据表的**唯一装载入口**。
##
## 几个入口（主场景、批量模拟、单波节奏、压力曲线）各自记「装哪几张表」的话，漏装一张不报错，
## 只会静默退回合成表。**新表只在本文件里接一次**。`test_battle_view.gd` 守着主场景确实走了这里。


## 新建一份装好全部真数据的配置。**游戏入口用这个，别直接 `PBSimConfig.new()`。**
static func config() -> PBSimConfig:
	return install(PBSimConfig.new())


## 把全部真数据表装进一份配置。返回同一个 [param cfg]，方便串写。
static func install(cfg: PBSimConfig) -> PBSimConfig:
	PBCharacterLoader.install(cfg)
	PBBondLoader.install(cfg)
	PBEquipLoader.install(cfg)
	PBBeastLoader.install(cfg)
	PBSkillLoader.install(cfg)
	return cfg
