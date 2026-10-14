class_name TargetingComponent
extends Node
## 索敌组件。策略可替换，塔和主角共用。
##
## 本期策略：nearest（射程内最近）、lowest_health、furthest_along_path。
## 将来要加"只打飞行""优先打治疗单位"，只需要加一个策略类，
## 不用改任何单位代码。详见 DESIGN.md 第 9 节。

## 索敌策略实现（TargetingStrategy 子类实例）
var _strategy: TargetingStrategy = null


static func create_strategy(strategy_name: StringName) -> TargetingStrategy:
	match strategy_name:
		&"lowest_health":
			return LowestHealthTargeting.new()
		&"furthest_along_path":
			return FurthestAlongPathTargeting.new()
		&"farthest":
			return FarthestTargeting.new()
		_:
			return NearestTargeting.new()


func setup(strategy_name: StringName) -> void:
	_strategy = create_strategy(strategy_name)


## 在候选列表里挑一个目标。origin 是攻击者位置，attack_range 是射程。
func pick_target(origin: Vector2, attack_range: float, candidates: Array[Node2D]) -> Node2D:
	if _strategy == null:
		_strategy = NearestTargeting.new()
	return _strategy.pick(origin, attack_range, candidates)
