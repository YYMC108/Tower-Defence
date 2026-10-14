class_name HeroUnit
extends CharacterBody2D
## 主角。玩家操控、主输出，同时是**近战通往大本营的唯一物理阻挡**。
##
## 关键机制（DESIGN.md 第 3 节）：
##   主角存活 → collision_layer 含 player 层 → 近战被挡住，只能攻击主角
##   主角死亡 → 关闭 collision_layer    → 近战直接穿过冲进大本营
## 所以"主角死亡的惩罚"不需要额外脚本，是碰撞规则自然长出来的。

signal died()
signal health_depleted()

const PLACEHOLDER_COLOR: Color = Color(0.30, 0.85, 0.40)
const PLACEHOLDER_SIZE: float = 14.0

var data: CharacterData

var health: HealthComponent
var targeting: TargetingComponent

var _attack_cooldown: float = 0.0
var _facing: Vector2 = Vector2.RIGHT
var _is_dead: bool = false
var _registry: UnitRegistry = null

## 绘制用：受击闪白计时
var _hit_flash: float = 0.0


static func create(p_data: CharacterData) -> HeroUnit:
	var hero := HeroUnit.new()
	hero.name = "HeroUnit"
	hero.data = p_data
	return hero


func _ready() -> void:
	_build_nodes()
	set_physics_process(true)
	queue_redraw()


func _build_nodes() -> void:
	if data == null:
		push_error("HeroUnit 缺少 CharacterData")
		return

	# 物理身体：阻挡近战的关键。layer 用 player 层。
	collision_layer = PhysicsLayers.bit(&"player")
	collision_mask = PhysicsLayers.bit(&"terrain")

	var shape := CollisionShape2D.new()
	shape.name = "BodyShape"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)
	shape.shape = rect
	add_child(shape)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = data.max_health
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	targeting = TargetingComponent.new()
	targeting.name = "TargetingComponent"
	add_child(targeting)
	targeting.setup(data.targeting_strategy)


func bind_registry(registry: UnitRegistry) -> void:
	_registry = registry
	if registry != null:
		registry.register_hero(self)


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_tick_timers(delta)
	_handle_movement(delta)
	_handle_attack(delta)


func _tick_timers(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()


func _handle_movement(_delta: float) -> void:
	var input_dir := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_up", &"move_down")
	)
	if input_dir.length_squared() > 1.0:
		input_dir = input_dir.normalized()
	velocity = input_dir * data.move_speed
	move_and_slide()


func _handle_attack(_delta: float) -> void:
	if not Input.is_action_pressed(&"attack"):
		return
	# 朝向鼠标
	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse_pos - global_position
	if to_mouse.length_squared() > 0.01:
		_facing = to_mouse.normalized()
		queue_redraw()
	_try_attack()


func _try_attack() -> void:
	if _attack_cooldown > 0.0 or _registry == null:
		return
	var candidates: Array[Node2D] = _registry.query_enemies_in_radius(global_position, data.attack_range)
	if candidates.is_empty():
		return
	var target: Node2D = targeting.pick_target(global_position, data.attack_range, candidates)
	if target == null:
		return
	_attack_cooldown = data.attack_interval
	_facing = (target.global_position - global_position).normalized()
	queue_redraw()

	var health_comp: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_comp != null:
		health_comp.apply_damage(Damage.new(data.attack_damage, self, data.damage_type))


func _on_damaged(_damage: Damage) -> void:
	_hit_flash = 0.12
	queue_redraw()


func _on_died(_damage: Damage) -> void:
	if _is_dead:
		return
	_is_dead = true
	# 关键：关闭碰撞层，近战从此可以穿过
	collision_layer = 0
	visible = false
	set_physics_process(false)
	health_depleted.emit()
	died.emit()


## 由 RoundManager 在复活时调用
func revive() -> void:
	_is_dead = false
	visible = true
	collision_layer = PhysicsLayers.bit(&"player")
	health.revive_full()
	set_physics_process(true)
	queue_redraw()


func is_alive() -> bool:
	return not _is_dead


func _draw() -> void:
	if _is_dead:
		return
	var half: float = PLACEHOLDER_SIZE * 0.5
	var body_color: Color = PLACEHOLDER_COLOR
	if _hit_flash > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.7)

	# 主体方块（占位美术）
	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color, true)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color.darkened(0.5), false, 1.0)

	# 朝向指示（一条短线，方便看出面向哪边）
	draw_line(Vector2.ZERO, _facing * (half + 5.0), Color.WHITE, 1.0)
