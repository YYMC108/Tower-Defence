class_name WaveData
extends Resource
## 一个波次的配置。要改敌人构成，改这里的 spawn_entries，不改代码。

@export var id: StringName = &""
@export var display_name: String = ""
@export var is_boss_wave: bool = false

## 生成指令列表。注意：用无类型 Array，因为 Godot 检查器导出的数组
## 赋值给 Array[WaveSpawnEntry] 会在运行时抛类型错误（常见坑，刻意避开）。
@export var spawn_entries: Array = []


## 本波预计总敌人数。用于 HUD 显示"剩余敌人"。
func total_enemy_count() -> int:
	var total: int = 0
	for entry: WaveSpawnEntry in spawn_entries:
		if entry != null:
			total += entry.count
	return total
