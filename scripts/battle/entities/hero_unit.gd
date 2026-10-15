class_name HeroUnit
extends CharacterBody2D
## 主角。玩家操控、主输出，同时是**近战通往大本营的唯一物理阻挡**。
##
## 关键机制（DESIGN.md 第 3 节）：
##   主角存活 → collision_layer 含 player 层 → 近战被挡住，只能攻击主角
##   主角死亡 → 关闭 collision_layer    → 近战直接穿过冲进大本营
## 所以"主角死亡的惩罚"不需要额外脚本，是碰撞规则自然长出来的。
##
## 表现层：有 sprite_set 时用精灵动画，否则回退纯色方块占位。
## **动画不阻塞攻击判定** —— 动画长短不会影响 DPS（攻击按冷却走）。

signal died()
signal health_depleted()

const PLACEHOLDER_COLOR: Color = Color(0.30, 0.85, 0.40)
## 占位方块与碰撞体尺寸。基于精灵实际渲染尺寸定（美术画布 32px，角色主体约 20px 宽）
const PLACEHOLDER_SIZE: float = 20.0
## 攻击动画播放期间仍按此节奏判定，与 attack_interval 解耦
const ATTACK_ANIM_TIMEOUT: float = 2.0

## 是否用攻击动画打断移动动画。
##
## ⚠️ 本期**刻意关闭**，原因是踩过一次坑：
##   美术给的攻击逐帧节奏 1.1/0.7/0.6/0.8/0.5/0.7/0.9/1.6 被按「秒」理解，
##   于是攻击动画总长 **6.90 秒**，而攻击间隔只有 **0.42 秒**。
##   攻击时每 0.42 秒就 play(restart=true) 重播一次 —— 连第一帧（1.1 秒）
##   都播不完，角色**永远卡在攻击姿势第一帧**，表现为明显的「攻击停顿感」。
##
## 关闭后：攻击不改变角色的移动/待机动画与朝向，手感与接入美术前一致
##（攻击判定本来就独立于动画，DPS 从未受影响）。
##
## 重新开启前需要先定两件事：
##   1. 那组 duration 的单位到底是什么（秒？相对权重？还是 1/10 秒？）
##   2. 攻击动画时长必须 ≤ 攻击间隔，否则永远播不完
##      （按 10 fps 算 8 帧 = 0.8 秒，仍大于 0.42 秒的间隔）
## 攻击动画数据与配置都已保留，定好之后把本开关改成 true 即可。
const USE_ATTACK_ANIMATION: bool = false

var data: CharacterData

var health: HealthComponent
var targeting: TargetingComponent
var animator: SpriteAnimator

var _attack_cooldown: float = 0.0
var _facing: Vector2 = Vector2.RIGHT
var _is_dead: bool = false
var _registry: UnitRegistry = null

## 绘制用：受击闪白计时
var _hit_flash: float = 0.0
## 当前动画与切换计时
var _current_anim: StringName = &"idle"
var _attack_anim_timer: float = 0.0


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

	# 有素材就用精灵，否则 _draw() 画占位方块
	animator = SpriteAnimator.attach(self, data.sprite_set, data.sprite_scale)
	if animator != null:
		animator.on_animation_finished = _on_anim_finished
		_set_animation(&"idle")


func has_sprite() -> bool:
	return animator != null


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
	if _attack_anim_timer > 0.0:
		_attack_anim_timer = maxf(0.0, _attack_anim_timer - delta)
		if _attack_anim_timer <= 0.0:
			_refresh_locomotion_animation()
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
	# 只在非攻击状态下切换跑/待机与朝向（USE_ATTACK_ANIMATION 关闭时
	# _attack_anim_timer 恒为 0，所以这里等价于"每帧都刷新"，手感与接入美术前一致）。
	# 朝向用**移动方向**（WASD），而不是鼠标方向 —— 跑动时应该面朝跑的方向。
	if not _is_attack_animation_active():
		var moving: bool = input_dir.length_squared() > 0.01
		_set_animation(&"run" if moving else &"idle")
		if moving and animator != null:
			animator.set_facing(input_dir.x)


func _is_attack_animation_active() -> bool:
	return USE_ATTACK_ANIMATION and _attack_anim_timer > 0.0


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

	# 判定照常按冷却走，动画只是表现 —— 动画再长也不会削 DPS
	_attack_cooldown = data.attack_interval
	_facing = (target.global_position - global_position).normalized()
	queue_redraw()
	_play_attack_animation()

	var health_comp: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_comp != null:
		health_comp.apply_damage(Damage.new(data.attack_damage, self, data.damage_type))


# ─────────────────────────────────────────────
# 动画
# ─────────────────────────────────────────────

func _set_animation(animation_name: StringName) -> void:
	_current_anim = animation_name
	if animator != null:
		animator.play_animation(animation_name)


func _play_attack_animation() -> void:
	# 本期关闭（见 USE_ATTACK_ANIMATION 的说明）：不打断移动动画。
	# 攻击判定不受影响 —— 它本来就独立于动画，DPS 与手感保持接入美术前的状态。
	if not USE_ATTACK_ANIMATION:
		return
	if animator == null or not animator.sprite_frames.has_animation(&"attack"):
		return
	_attack_anim_timer = ATTACK_ANIM_TIMEOUT
	# 攻击时朝向**瞄准方向**（鼠标），与跑动的朝向来源不同
	animator.set_facing(_facing.x)
	animator.play_animation(&"attack", true)


func _on_anim_finished(finished: StringName) -> void:
	if finished == &"attack":
		_attack_anim_timer = 0.0
		_refresh_locomotion_animation()


func _refresh_locomotion_animation() -> void:
	if _is_dead:
		return
	var moving: bool = Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_up", &"move_down")
	).length_squared() > 0.01
	_set_animation(&"run" if moving else &"idle")


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
	_attack_anim_timer = 0.0
	_set_animation(&"idle")
	set_physics_process(true)
	queue_redraw()


func is_alive() -> bool:
	return not _is_dead


## 无素材时才绘制占位方块与朝向线
func _draw() -> void:
	if _is_dead or has_sprite():
		return
	var half: float = PLACEHOLDER_SIZE * 0.5
	var body_color: Color = PLACEHOLDER_COLOR
	if _hit_flash > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.7)

	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color, true)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color.darkened(0.5), false, 1.0)
	draw_line(Vector2.ZERO, _facing * (half + 5.0), Color.WHITE, 1.0)
