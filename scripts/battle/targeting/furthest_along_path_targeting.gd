class_name FurthestAlongPathTargeting
extends TargetingStrategy
## 沿路径进度最远的目标（即"最靠近大本营"的那个）。
##
## 塔防里通常这是最合理的策略：先打领头的，别让它溜过去。
## 依赖目标节点提供 path_progress() 方法（EnemyUnit 有）。


func pick(origin: Vector2, attack_range: float, candidates: Array[Node2D]) -> Node2D:
	var in_range: Array[Node2D] = _filter_in_range(origin, attack_range, candidates)
	var best: Node2D = null
	var best_progress: float = -1.0
	for unit: Node2D in in_range:
		var progress: float = _read_progress(unit)
		if progress > best_progress:
			best_progress = progress
			best = unit
	return best


func _read_progress(unit: Node2D) -> float:
	if unit.has_method("path_progress"):
		return float(unit.call("path_progress"))
	# 没有进度信息就退化为"离大本营近"，用 x 轴粗略代替
	return -unit.global_position.distance_to(Vector2.ZERO)
