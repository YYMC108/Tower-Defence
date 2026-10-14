class_name HealthComponent
extends Node
## 血量组件。主角、塔、敌人**共用这一个组件**。
##
## 设计要点（DESIGN.md 第 12 节）：组件只管"我的血量和死亡"，
## 不管"死了之后怎么办"。重生策略由外部（RoundManager）决定。
## 塔和主角的差别只是外部怎么调度，不是两套血条逻辑。

signal health_changed(current: float, maximum: float)
signal damaged(damage: Damage)
signal died(damage: Damage)

@export var max_health: float = 100.0

var current_health: float = 0.0
var is_dead: bool = false

## 无敌帧标记。复活后的短暂保护期用。
var invulnerable: bool = false


func _ready() -> void:
	current_health = max_health
	# 延后一帧发射，避免监听者还没连上信号就收到
	health_changed.emit.call_deferred(current_health, max_health)


func setup(p_max_health: float) -> void:
	max_health = p_max_health
	current_health = max_health
	is_dead = false
	invulnerable = false
	health_changed.emit(current_health, max_health)


## 统一的受伤入口。所有伤害必须经过这里。
func apply_damage(damage: Damage) -> void:
	if is_dead or invulnerable or damage == null:
		return
	if damage.amount <= 0.0:
		return
	# 防止自杀（除非明确允许）
	if damage.source != null and damage.source == owner and not damage.allow_self_damage:
		return

	current_health = maxf(0.0, current_health - damage.amount)
	damaged.emit(damage)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		is_dead = true
		died.emit(damage)


## 治疗。治疗塔与"复活回满血"都走这里。
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	var before: float = current_health
	current_health = minf(max_health, current_health + amount)
	if not is_equal_approx(before, current_health):
		health_changed.emit(current_health, max_health)


func revive_full() -> void:
	current_health = max_health
	is_dead = false
	invulnerable = false
	health_changed.emit(current_health, max_health)


func health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health
