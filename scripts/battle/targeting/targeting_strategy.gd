class_name TargetingStrategy
extends RefCounted
## 索敌策略基类。
##
## 子类只需要实现 pick()。这样"换一种打法"是加一个类，
## 而不是在塔的代码里写一堆 if。

## 返回选中的目标，没有合适目标则返回 null。
func pick(_origin: Vector2, _attack_range: float, _candidates: Array[Node2D]) -> Node2D:
	return null


## 通用过滤：存活、在射程内、不是自己。
func _filter_in_range(origin: Vector2, attack_range: float, candidates: Array[Node2D]) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for unit: Node2D in candidates:
		if unit == null or not is_instance_valid(unit) or not unit.is_inside_tree():
			continue
		if unit.global_position.distance_to(origin) <= attack_range:
			result.append(unit)
	return result
