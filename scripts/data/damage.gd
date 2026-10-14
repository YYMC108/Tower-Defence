class_name Damage
extends RefCounted
## 统一的伤害对象。
##
## 铁律：严禁在业务代码里写 `enemy.hp -= 10`。
## 所有伤害都必须构造成 Damage 再交给 HealthComponent 处理。
##
## 这样将来加护甲、暴击、减伤、吸血、伤害统计时，只需要改一处。
## 详见 DESIGN.md 第 10.1 节。

enum Type {
	PHYSICAL,  ## 物理：受护甲减免
	MAGIC,     ## 魔法：受抗性减免
	TRUE,      ## 真实：无视一切减免
}

var amount: float = 0.0
var type: Type = Type.PHYSICAL
## 伤害来源。用于击杀归属、嘲讽判定、以及"谁打死了我"的调试。
var source: Node = null
## 是否暴击（本期只做展示，不做额外倍率）
var is_crit: bool = false
## 来源单位是否免疫自己造成的伤害（防止自杀）
var allow_self_damage: bool = false


func _init(p_amount: float = 0.0, p_source: Node = null, p_type: Type = Type.PHYSICAL) -> void:
	amount = p_amount
	source = p_source
	type = p_type


func _to_string() -> String:
	return "Damage(%.1f, %s, src=%s)" % [amount, Type.keys()[type], source.name if source else "null"]
