class_name CharacterData
extends Resource
## 角色数值配置。主角与塔角色共用这一个资源类型，靠 role 区分。
##
## 调平衡请改 resources/characters/ 下的 .tres 文件，不要改代码。
## 详见 DESIGN.md 第 13 节。

enum Role {
	HERO,   ## 主角：玩家操控，主输出，同时是近战的物理阻挡物
	TOWER,  ## 塔角色：放在塔位上，提供输出 / 治疗 / 控制
}

enum TowerKind {
	NONE,     ## HERO 用
	DPS,      ## 输出塔
	HEAL,     ## 治疗塔（主角唯一的回血手段）
	CONTROL,  ## 控制塔（依赖状态效果系统，本期不做实现）
}

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var role: Role = Role.TOWER
@export var tower_kind: TowerKind = TowerKind.NONE

@export_group("基础属性")
@export var max_health: float = 100.0
@export var move_speed: float = 90.0

@export_group("攻击")
@export var attack_damage: float = 10.0
@export var attack_interval: float = 0.8
@export var attack_range: float = 90.0
@export var damage_type: Damage.Type = Damage.Type.PHYSICAL
## 索敌策略文件名，对应 scripts/battle/targeting/ 下的策略。
## 可选：nearest / furthest_along_path / lowest_health / farthest
@export var targeting_strategy: StringName = &"nearest"

@export_group("治疗（仅治疗塔）")
@export var heal_amount: float = 0.0
@export var heal_interval: float = 2.0

@export_group("合成系统占位（本期不使用）")
## 可携带副本上限。合成升星系统的前置条件，本期一律填 1。
## 详见 DESIGN.md 第 7 节。
@export var copy_limit: int = 1

@export_group("表现")
## 精灵动画定义。留空则单位回退到纯色方块占位绘制。
@export var sprite_set: UnitSpriteSet
## 精灵显示缩放。美术按源生画布交付，这里缩到游戏内尺寸：
##   主角 128px 画布 -> 0.25 -> 游戏内 32px
##   塔   64px 画布 -> 0.5  -> 游戏内 32px
## 见 DESIGN.md 第 15.12 节（美术接入尺度约定）。
@export var sprite_scale: float = 1.0

@export_group("解锁（局外）")
@export var unlock_condition: String = ""
@export var unlocked_by_default: bool = false
