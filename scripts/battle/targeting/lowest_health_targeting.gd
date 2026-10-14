class_name LowestHealthTargeting
extends TargetingStrategy
## 射程内血量绝对值最低的目标。适合"补刀"型塔。


func pick(origin: Vector2, attack_range: float, candidates: Array[Node2D]) -> Node2D:
	var in_range: Array[Node2D] = _filter_in_range(origin, attack_range, candidates)
	var best: Node2D = null
	var best_hp: float = INF
	for unit: Node2D in in_range:
		var hp: float = _read_health(unit)
		if hp < best_hp:
			best_hp = hp
			best = unit
	return best


func _read_health(unit: Node2D) -> float:
	var health: HealthComponent = unit.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return INF
	return health.current_health
