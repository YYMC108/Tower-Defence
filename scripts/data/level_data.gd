class_name LevelData
extends Resource
## 关卡配置。这是"实验关卡"能做到不改代码就换配置的关键。
##
## 改波次数量 = 改 waves 数组；改塔位数量 = 改地图场景里的 TowerSlots 子节点。
## 详见 DESIGN.md 第 14 节。

@export_group("标识")
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("地图")
## 地图场景路径。塔位、路径点、大本营、出生点都在这个场景里定义。
@export_file("*.tscn") var map_scene_path: String = ""

@export_group("波次")
## 波次顺序（用无类型 Array 避开检查器类型坑）
@export var waves: Array = []

@export_group("大本营")
@export var base_max_health: float = 100.0
## 本关开局给的局内资源（用于重建被摧毁的塔，本期只做展示）
@export var starting_battle_currency: int = 10

@export_group("主角复活惩罚（递增 + 封顶，见 DESIGN.md 第 6 节）")
## 第 1 次死亡的复活时间
@export var hero_revive_base_seconds: float = 5.0
## 每次死亡递增的秒数
@export var hero_revive_increment: float = 5.0
## 封顶。超出后不再递增（防止后期死亡螺旋必输）
@export var hero_revive_max_seconds: float = 30.0

@export_group("奖励（本期不做结算，先占位）")
@export var reward_stars: int = 1
@export var reward_gold: int = 0


func wave_count() -> int:
	return waves.size()


## 按当前死亡次数算复活时间。death_count 从 1 开始计（第几次死亡）。
func revive_seconds_for_death(death_count: int) -> float:
	if death_count < 1:
		death_count = 1
	var seconds: float = hero_revive_base_seconds + float(death_count - 1) * hero_revive_increment
	return minf(seconds, hero_revive_max_seconds)
