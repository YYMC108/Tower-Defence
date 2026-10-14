class_name BattleState
extends RefCounted
## 战斗级状态。**这是战斗状态的唯一权威来源。**
##
## 为什么不用节点：大本营血量、当前波次、复活惩罚档位这些是"战斗级"状态，
## 不属于任何单个单位。主角死亡时节点会被隐藏甚至禁用，
## 状态放在节点上会跟着一起消失。
##
## 详见 DESIGN.md 第 5 / 6 节。

signal base_health_changed(current: float, maximum: float)
signal base_destroyed()
signal battle_currency_changed(current: int)

## 大本营血量（跨波次不恢复）
var base_health: float = 100.0
var base_max_health: float = 100.0

## 当前波次索引（0-based）。等于 wave_count 表示已打完。
var current_wave_index: int = 0
var total_waves: int = 0

## 复活惩罚档位：已经死过几次。布防阶段死亡也计数。
var hero_death_count: int = 0

## 局内资源（用于重建被摧毁的塔；与局外金币严格分离）
var battle_currency: int = 0

## 被摧毁的塔位记录：slot_index -> true 表示该塔位本波空置
var destroyed_tower_slots: Dictionary = {}


func setup(p_base_max_health: float, p_total_waves: int, p_starting_currency: int) -> void:
	base_max_health = p_base_max_health
	base_health = p_base_max_health
	total_waves = p_total_waves
	current_wave_index = 0
	hero_death_count = 0
	battle_currency = p_starting_currency
	destroyed_tower_slots.clear()


func damage_base(amount: float) -> void:
	if base_health <= 0.0:
		return
	base_health = maxf(0.0, base_health - amount)
	base_health_changed.emit(base_health, base_max_health)
	if base_health <= 0.0:
		base_destroyed.emit()


func is_base_alive() -> bool:
	return base_health > 0.0


func base_ratio() -> float:
	if base_max_health <= 0.0:
		return 0.0
	return base_health / base_max_health


## 还剩几波（含当前正在进行/尚未开始的这一波）
func waves_remaining() -> int:
	return maxi(0, total_waves - current_wave_index)


func advance_wave() -> void:
	current_wave_index += 1


func is_final_wave() -> bool:
	return current_wave_index >= total_waves - 1


func add_currency(amount: int) -> void:
	battle_currency = maxi(0, battle_currency + amount)
	battle_currency_changed.emit(battle_currency)


func spend_currency(amount: int) -> bool:
	if amount <= 0:
		return true
	if battle_currency < amount:
		return false
	battle_currency -= amount
	battle_currency_changed.emit(battle_currency)
	return true
