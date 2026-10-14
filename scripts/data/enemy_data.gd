class_name EnemyData
extends Resource
## 敌人数值配置。
##
## 核心设计：伤害矩阵用三个布尔标志位数据化（见 DESIGN.md 第 3 节）。
## 要加"飞行敌人""自爆敌人""只打塔的敌人"，只需要新建一份 .tres，不改代码。

enum AttackMode {
	MELEE,   ## 近战：贴身攻击
	RANGED,  ## 远程：在射程内停下攻击
}

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""
@export var placeholder_color: Color = Color(0.85, 0.25, 0.25)

@export_group("伤害矩阵（DESIGN.md 第 3 节，最易实现错的地方）")
## 近战 = (true, false, true)：打主角、免疫塔、打大本营
## 远程 = (true, true, false)：打主角、打塔、不打大本营
@export var can_damage_hero: bool = true
@export var can_damage_tower: bool = true
@export var can_damage_base: bool = false

@export_group("攻击")
@export var attack_mode: AttackMode = AttackMode.RANGED
@export var attack_damage: float = 8.0
@export var attack_interval: float = 1.2
@export var attack_range: float = 80.0
## 对"建筑类"目标（塔 / 大本营）的额外射程。避免敌人必须完全重叠才能攻击大本营。
@export var building_attack_range: float = 26.0

@export_group("移动")
@export var max_health: float = 40.0
@export var move_speed: float = 34.0
## 抵达路径点后判定"到达"的半径
@export var waypoint_reach_radius: float = 4.0
## 检测主角的仇恨半径。主角进入这个范围就转为攻击主角。
@export var hero_detect_radius: float = 72.0

@export_group("奖励")
@export var reward_battle_currency: int = 1
