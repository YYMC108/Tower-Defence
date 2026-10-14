class_name WaveSpawnEntry
extends Resource
## 一条生成指令：生成什么敌人、生成几只、间隔多久。

@export var enemy_data: EnemyData
@export var count: int = 3
## 同一批内两只敌人之间的间隔（秒）
@export var spawn_interval: float = 0.8
## 本条指令开始前的延迟（相对上一条指令结束）
@export var delay_before: float = 0.0


func total_duration() -> float:
	if count <= 1:
		return 0.0
	return float(count - 1) * spawn_interval
