class_name FarthestTargeting
extends TargetingStrategy
## 射程内最远的目标。


func pick(origin: Vector2, attack_range: float, candidates: Array[Node2D]) -> Node2D:
	var in_range: Array[Node2D] = _filter_in_range(origin, attack_range, candidates)
	var best: Node2D = null
	var best_dist: float = -1.0
	for unit: Node2D in in_range:
		var d: float = origin.distance_squared_to(unit.global_position)
		if d > best_dist:
			best_dist = d
			best = unit
	return best
