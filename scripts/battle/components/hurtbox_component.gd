class_name HurtboxComponent
extends Area2D
## 受击判定区。谁能被打中，谁就挂一个 Hurtbox。
##
## 铁律：hitbox 与 hurtbox 分离（DESIGN.md 第 10.2 节）。
## 攻击方只关心"我的 hitbox 碰到了谁的 hurtbox"，不关心对方是什么单位。

## 受伤回调，由宿主单位设置。参数是伤害对象。
var damage_receiver: Callable = Callable()


func _ready() -> void:
	# hurtbox 必须可被检测
	monitorable = true
	monitoring = false  # 受击方不需要主动扫描别人


func setup(p_layer: int, p_receiver: Callable) -> void:
	collision_layer = p_layer
	collision_mask = 0
	damage_receiver = p_receiver


## 由攻击方调用（或由 Area2D 交叠时调用）
func receive(damage: Damage) -> void:
	if damage_receiver.is_valid():
		damage_receiver.call(damage)
