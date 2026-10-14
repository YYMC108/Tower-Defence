class_name WaveSpawner
extends Node
## 波次生成器。按 WaveData 在出生点生成敌人。
##
## 职责边界（DESIGN.md 第 12 节）：
##   ✅ 生成敌人、管理出生间隔、维护"生成队列是否已空"
##   ❌ 判断波次是否结束 —— 那是 RoundManager 的事
##
## 设计细节：先把整波敌人的"出生时刻表"算成数组，
## 这样生成逻辑是纯粹的时间比较，不存在"延迟被卡住"的边界 bug。

signal enemy_spawned(enemy: Node2D)
signal spawn_queue_finished()

var _queue: Array[Dictionary] = []
var _elapsed: float = 0.0
var _next_index: int = 0
var _running: bool = false
var _spawn_point: Vector2 = Vector2.ZERO
var _parent: Node = null

## 生成出来的敌人交给谁处理（BattleRoot 会把它登记进 UnitRegistry）
var on_enemy_created: Callable = Callable()


## 开始一波。wave 为空或没有敌人时，队列立即视为空。
func start_wave(wave: WaveData, spawn_point: Vector2, parent: Node) -> void:
	_queue.clear()
	_elapsed = 0.0
	_next_index = 0
	_spawn_point = spawn_point
	_parent = parent

	if wave != null:
		var cursor: float = 0.0
		for entry: WaveSpawnEntry in wave.spawn_entries:
			if entry == null or entry.enemy_data == null or entry.count <= 0:
				continue
			cursor += entry.delay_before
			for i: int in range(entry.count):
				_queue.append({"time": cursor, "data": entry.enemy_data})
				cursor += entry.spawn_interval
		# 让队列按时间排序（防止策划把 entries 顺序写乱）
		_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["time"]) < float(b["time"]))

	_running = true
	if _queue.is_empty():
		_running = false
		spawn_queue_finished.emit.call_deferred()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	while _next_index < _queue.size() and float(_queue[_next_index]["time"]) <= _elapsed:
		_spawn_enemy(_queue[_next_index]["data"])
		_next_index += 1
	if _next_index >= _queue.size():
		_running = false
		spawn_queue_finished.emit()


func _spawn_enemy(data: EnemyData) -> void:
	if _parent == null or data == null:
		return
	var enemy: Node2D = EnemyUnit.create(data, _spawn_point)
	_parent.add_child(enemy)
	enemy_spawned.emit(enemy)
	if on_enemy_created.is_valid():
		on_enemy_created.call(enemy)


## 生成队列是否已经全部生成完
func is_queue_finished() -> bool:
	return _next_index >= _queue.size()


func total_to_spawn() -> int:
	return _queue.size()


func spawned_count() -> int:
	return _next_index


func stop() -> void:
	_running = false
	_queue.clear()
	_next_index = 0
	_elapsed = 0.0
