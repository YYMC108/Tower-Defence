class_name BattleEconomy
extends Node
## 局内经济。只管本关有效的资源，与局外金币**严格分离**。
##
## 局内资源的用途（本期只有第一个）：
##   1. 重建被摧毁的塔（塔被摧毁的代价，DESIGN.md 第 4.2 节）
##   2. 合成升星（架构预留，本期冻结）
##
## 这两个出口互相竞争同一份资源 —— 这是设计里有意的张力。

signal rebuild_requested(slot_index: int, cost: int)
signal rebuild_failed(slot_index: int, cost: int)

## 重建一座塔的消耗
@export var tower_rebuild_cost: int = 3

var _state: BattleState = null


func bind_state(state: BattleState) -> void:
	_state = state


func can_afford_rebuild() -> bool:
	if _state == null:
		return false
	return _state.battle_currency >= tower_rebuild_cost


func try_rebuild_tower(slot_index: int) -> bool:
	if _state == null:
		return false
	if not _state.spend_currency(tower_rebuild_cost):
		rebuild_failed.emit(slot_index, tower_rebuild_cost)
		return false
	_state.destroyed_tower_slots.erase(slot_index)
	rebuild_requested.emit(slot_index, tower_rebuild_cost)
	return true


func enemy_killed(data: EnemyData) -> void:
	if _state == null or data == null:
		return
	_state.add_currency(data.reward_battle_currency)
