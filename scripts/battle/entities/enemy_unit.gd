class_name EnemyUnit
extends CharacterBody2D
## 敌人。近战与远程**共用这一套代码**，靠 EnemyData 的三个伤害标志位区分
## （DESIGN.md 第 3 / 4.3 节）。要加新敌人类型，只需要新建一份 .tres。
##
## 行为优先级（伤害矩阵的直接实现）：
##   近战 (can_damage_tower=false)：主角在仇恨范围内 → 打主角（被挡住）
##                                  否则             → 冲向大本营并攻击
##   远程 (can_damage_base=false) ：射程内有目标     → 停下攻击（主角/塔）
##                                  无目标           → 沿路径推进
##
## ⚠️ M1 已知缺口：寻路是"直线走向下一个路径点"，没有避障。
##    如果将来地图有障碍物，必须接入寻路（AStarGrid2D），
##    否则敌人会卡在障碍后面 —— 而玩家和塔都打不到射程外的目标。
##    见 DESIGN.md 第 9 节。

signal died(enemy: EnemyUnit)

const PLACEHOLDER_SIZE: float = 11.0

## 远程索敌的重扫间隔（秒）。索敌是 N×M 扫描，不能每帧做。
const RETARGET_INTERVAL: float = 0.15

var data: EnemyData

var health: HealthComponent
var _detect_area: Area2D

## 路径点序列（世界坐标）
var _path: PackedVector2Array = PackedVector2Array()
var _waypoint_index: int = 0
## 已走过的总距离，用于"路径进度最远"索敌策略
var _travelled: float = 0.0

var _base_position: Vector2 = Vector2.ZERO
var _base_target: Node = null
var _hero_target: HeroUnit = null
var _cached_target: Node2D = null
var _retarget_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _hit_flash: float = 0.0
var _is_dead: bool = false
var _registry: UnitRegistry = null
var _economy: BattleEconomy = null
var _on_base_damage: Callable = Callable()


static func create(p_data: EnemyData, p_spawn_position: Vector2) -> EnemyUnit:
	var enemy := EnemyUnit.new()
	enemy.name = "EnemyUnit"
	enemy.data = p_data
	# 此时节点还没入树，只设相对坐标；入树后由 BattleRoot 定位到出生点
	enemy.position = p_spawn_position
	return enemy


func _ready() -> void:
	_build_nodes()


func _build_nodes() -> void:
	if data == null:
		push_error("EnemyUnit 缺少 EnemyData")
		return

	collision_layer = PhysicsLayers.bit(&"enemy")
	# 只与地形和其他敌人碰撞：敌人之间互不重叠，避免挤成一坨
	collision_mask = PhysicsLayers.mask([&"terrain", &"enemy"])

	var shape := CollisionShape2D.new()
	shape.name = "BodyShape"
	var circle := CircleShape2D.new()
	circle.radius = PLACEHOLDER_SIZE * 0.5
	shape.shape = circle
	add_child(shape)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = data.max_health
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	_build_detect_area()
	queue_redraw()


## 主角检测区。近战靠它判断"主角是否在仇恨范围内"。
func _build_detect_area() -> void:
	_detect_area = Area2D.new()
	_detect_area.name = "DetectArea"
	_detect_area.collision_layer = 0
	_detect_area.collision_mask = PhysicsLayers.bit(&"player")
	_detect_area.monitoring = true
	_detect_area.monitorable = false

	var detect_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.hero_detect_radius
	detect_shape.shape = circle
	_detect_area.add_child(detect_shape)
	add_child(_detect_area)

	_detect_area.area_entered.connect(_on_detect_area_entered)


func _on_detect_area_entered(area: Area2D) -> void:
	# 本期主角没有独立的 hurtbox Area2D，检测暂不依赖这个信号。
	# 保留结构以便 M2 接入 hurtbox 后自动生效。
	pass


## 由 BattleRoot 注入寻路与依赖
func setup_path(path: PackedVector2Array, p_base_position: Vector2, p_base_target: Node) -> void:
	_path = path
	_waypoint_index = 0
	_travelled = 0.0
	_base_position = p_base_position
	_base_target = p_base_target


func bind_registry(registry: UnitRegistry) -> void:
	_registry = registry
	if registry != null:
		registry.register_enemy(self)


func bind_economy(economy: BattleEconomy) -> void:
	_economy = economy


## 由 BattleRoot 注入"攻击大本营"的回调（大本营血量存在 BattleState 里，
## 不是一个物理节点的 hp，所以这里回调出去而不是直接改）
func bind_base_damage(callback: Callable) -> void:
	_on_base_damage = callback


# ─────────────────────────────────────────────
# 每帧行为
# ─────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _is_dead:
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()

	if data.attack_mode == EnemyData.AttackMode.MELEE:
		_tick_melee()
	else:
		_tick_ranged(delta)


## 近战：主角优先，否则冲家
func _tick_melee() -> void:
	var hero: HeroUnit = _find_live_hero()
	if hero != null and data.can_damage_hero:
		var dist: float = global_position.distance_to(hero.global_position)
		if dist <= data.attack_range:
			velocity = Vector2.ZERO
			move_and_slide()
			_attack_hero(hero)
			return
		# 主角在仇恨范围内 → 追上去
		if dist <= data.hero_detect_radius:
			_move_towards(hero.global_position)
			return

	# 冲向大本营
	if not data.can_damage_base:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var base_dist: float = global_position.distance_to(_base_position)
	if base_dist <= data.building_attack_range:
		velocity = Vector2.ZERO
		move_and_slide()
		_attack_base()
		return
	_follow_path()


## 远程：射程内有目标就停下打，否则推进
func _tick_ranged(delta: float) -> void:
	var target: Node2D = _acquire_ranged_target(delta)
	if target != null and _attack_cooldown <= 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_fire_at(target)
		return

	if target != null:
		# 有目标但还在冷却：站着别动
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# 无目标 → 推进（打不到大本营的远程就原地待命，避免堆在末端）
	if not data.can_damage_base:
		if _path.size() > 0:
			_follow_path_with_delta(delta)
		else:
			velocity = Vector2.ZERO
			move_and_slide()
		return
	_follow_path_with_delta(delta)


## 索敌是 N×M 的扫描（敌人 × 塔），不能每帧做。
## 这里节流到每 RETARGET_INTERVAL 秒重扫一次；当前目标失效时立即重扫。
func _acquire_ranged_target(delta: float) -> Node2D:
	_retarget_timer -= delta
	if _cached_target != null and not is_instance_valid(_cached_target):
		_cached_target = null
		_retarget_timer = 0.0

	if _retarget_timer > 0.0:
		return _cached_target

	_retarget_timer = RETARGET_INTERVAL
	_cached_target = _scan_ranged_target()
	return _cached_target


func _scan_ranged_target() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF

	if data.can_damage_hero:
		var hero: HeroUnit = _find_live_hero()
		if hero != null:
			var d: float = global_position.distance_to(hero.global_position)
			if d <= data.attack_range:
				best = hero
				best_dist = d

	if data.can_damage_tower and _registry != null:
		for tower: Node2D in _registry.towers:
			if tower == null or not is_instance_valid(tower):
				continue
			var d: float = global_position.distance_to(tower.global_position)
			if d <= data.attack_range and d < best_dist:
				best = tower
				best_dist = d

	return best


# ─────────────────────────────────────────────
# 移动
# ─────────────────────────────────────────────

func _follow_path() -> void:
	_follow_path_with_delta(1.0)


func _follow_path_with_delta(_delta: float) -> void:
	if _path.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _waypoint_index >= _path.size():
		_move_towards(_base_position)
		return

	var target_point: Vector2 = _path[_waypoint_index]
	var to_target: Vector2 = target_point - global_position
	if to_target.length() <= data.waypoint_reach_radius:
		_waypoint_index += 1
		return
	_move_towards(target_point)


func _move_towards(point: Vector2) -> void:
	var direction: Vector2 = (point - global_position)
	if direction.length_squared() > 0.0001:
		direction = direction.normalized()
	velocity = direction * data.move_speed
	var before: Vector2 = global_position
	move_and_slide()
	_travelled += before.distance_to(global_position)


# ─────────────────────────────────────────────
# 攻击
# ─────────────────────────────────────────────

func _attack_hero(hero: HeroUnit) -> void:
	if _attack_cooldown > 0.0 or hero.health == null:
		return
	_attack_cooldown = data.attack_interval
	hero.health.apply_damage(Damage.new(data.attack_damage, self))


func _attack_base() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = data.attack_interval
	if _on_base_damage.is_valid():
		_on_base_damage.call(data.attack_damage)


func _fire_at(target: Node2D) -> void:
	_attack_cooldown = data.attack_interval
	var target_health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if target_health != null:
		target_health.apply_damage(Damage.new(data.attack_damage, self))


func _find_live_hero() -> HeroUnit:
	if _hero_target != null and is_instance_valid(_hero_target) and _hero_target.is_alive():
		return _hero_target
	if _registry == null:
		return null
	for candidate: Node2D in _registry.heroes:
		if candidate is HeroUnit:
			var hero: HeroUnit = candidate as HeroUnit
			if hero.is_alive():
				_hero_target = hero
				return hero
	return null


# ─────────────────────────────────────────────
# 受击与死亡
# ─────────────────────────────────────────────

func _on_damaged(_damage: Damage) -> void:
	_hit_flash = 0.12
	queue_redraw()


func _on_died(_damage: Damage) -> void:
	if _is_dead:
		return
	_is_dead = true
	set_physics_process(false)
	if _registry != null:
		_registry.unregister_enemy(self)
	if _economy != null:
		_economy.enemy_killed(data)
	died.emit(self)
	queue_redraw()
	# 死亡动画占位：立刻消失。有美术后改成播放死亡动画再 queue_free。
	queue_free()


func is_alive() -> bool:
	return not _is_dead


## 供"路径进度最远"索敌策略使用
func path_progress() -> float:
	return _travelled


# ─────────────────────────────────────────────
# 绘制（占位美术：纯色方块）
# ─────────────────────────────────────────────

func _draw() -> void:
	var half: float = PLACEHOLDER_SIZE * 0.5
	var body_color: Color = Color(0.85, 0.25, 0.25)
	if data != null:
		body_color = data.placeholder_color
	if _hit_flash > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.8)

	# 近战画方形，远程画菱形 —— 一眼区分两类敌人
	if data != null and data.attack_mode == EnemyData.AttackMode.MELEE:
		draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color, true)
	else:
		var points := PackedVector2Array([
			Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0),
		])
		draw_colored_polygon(points, body_color)
