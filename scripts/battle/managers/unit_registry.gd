class_name UnitRegistry
extends Node
## 单位注册表。让塔能高效找到敌人，避免 get_nodes_in_group 满天飞。
##
## 性能说明（DESIGN.md 第 9 节）：
## 本期就是朴素线性遍历。一百来个敌人的距离判断是纳秒级的事，够用。
## 但**接口留好了**——将来换空间网格，只需要改 query_enemies_in_radius。

signal enemy_registered(enemy: Node2D)
signal enemy_unregistered(enemy: Node2D)

var enemies: Array[Node2D] = []
var towers: Array[Node2D] = []
var heroes: Array[Node2D] = []


func register_enemy(enemy: Node2D) -> void:
	if enemy == null or enemies.has(enemy):
		return
	enemies.append(enemy)
	enemy_registered.emit(enemy)


func unregister_enemy(enemy: Node2D) -> void:
	if enemy == null:
		return
	enemies.erase(enemy)
	enemy_unregistered.emit(enemy)


func register_tower(tower: Node2D) -> void:
	if tower != null and not towers.has(tower):
		towers.append(tower)


func unregister_tower(tower: Node2D) -> void:
	if tower != null:
		towers.erase(tower)


func register_hero(hero: Node2D) -> void:
	if hero != null and not heroes.has(hero):
		heroes.append(hero)


func unregister_hero(hero: Node2D) -> void:
	if hero != null:
		heroes.erase(hero)


func enemy_count() -> int:
	return enemies.size()


## 当前所有活着的敌人
func get_enemies() -> Array[Node2D]:
	return enemies


## 射程内的敌人。将来换空间网格只改这里。
func query_enemies_in_radius(origin: Vector2, radius: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var radius_sq: float = radius * radius
	for enemy: Node2D in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if origin.distance_squared_to(enemy.global_position) <= radius_sq:
			result.append(enemy)
	return result


## 取离某点最近的敌人（敌人索敌主角之外的用途）
func nearest_enemy_to(origin: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for enemy: Node2D in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		var d: float = origin.distance_squared_to(enemy.global_position)
		if d < best_d:
			best_d = d
			best = enemy
	return best


func clear() -> void:
	enemies.clear()
	towers.clear()
	heroes.clear()
