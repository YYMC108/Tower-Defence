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
## 占位方块与碰撞体尺寸。随世界尺度 ×4（原 20）：精灵显示 128px，主体约占 80px 宽。
const PLACEHOLDER_SIZE: float = 80.0
## 受击闪白持续时长（秒）
const HIT_FLASH_TIME: float = 0.12

## 是否播放攻击动画。
##
## 曾经因为两个问题被临时关闭，现已修好并重新开启：
##   1. 美术给的攻击逐帧节奏 1.1/0.7/0.6/0.8/0.5/0.7/0.9/1.6 被按「秒」理解，
##      攻击动画总长变成 6.90 秒 —— 已按相对权重归一化到 0.80 秒。
##   2. 动画（0.80 秒）比攻击间隔（0.42 秒）长 —— 每 0.42 秒就被重头播放，
##      连第一帧都播不完，角色卡在攻击姿势上（"攻击停顿感"）。
##      **现在改成按攻击间隔动态调整播放速度**（见 _play_attack_animation），
##      一次出手正好播完一遍，既看得见动画、又不卡顿。
##
## 若将来要临时关掉，把本开关改成 false 即可 —— 关闭时攻击不改变移动动画，
## 手感等同于没有攻击动画的版本。
const USE_ATTACK_ANIMATION: bool = true

## 三段连招：连点三次鼠标，依次播放 attack_1 → attack_2 → attack_3。
## 超过 COMBO_RESET_SECONDS 没有再次出手，连招回到第一段。
const COMBO_LENGTH: int = 3
const COMBO_RESET_SECONDS: float = 1.2
## 连招动画名前缀（attack_1 / attack_2 / attack_3）
const COMBO_ANIM_PREFIX: String = "attack_"
## 空挥时挥击特效放在身前多远（攻击射程的比例）。
## 取 0.55：既在角色身体之外（精灵 128px，半身约 64px），又不超过实际打击距离。
const WHIFF_DISTANCE_RATIO: float = 0.55

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
## 当前（移动/待机）动画名
var _current_anim: StringName = &"idle"

## 一次性动画（攻击段 / 受击）——播放期间不允许移动动画覆盖它。
##
## 用一套机制同时管攻击与受击，是因为两者是同一类问题：
## "播一段不循环的动画，播完回到 run/idle，期间别被打断"。
## 早先只有攻击用专门的 _attack_anim_timer，加入受击动画后必须统一，
## 否则两个计时器会互相覆盖。
var _oneshot_anim: StringName = &""
var _oneshot_timer: float = 0.0

## 连招进度：0..COMBO_LENGTH-1，下一段播放 attack_{_combo_step + 1}
var _combo_step: int = 0
var _combo_timer: float = 0.0


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
	# 一次性动画（攻击段 / 受击）计时。超时或被 animation_finished 提前清掉都算结束。
	if _oneshot_timer > 0.0:
		_oneshot_timer = maxf(0.0, _oneshot_timer - delta)
		if _oneshot_timer <= 0.0:
			_end_oneshot()
	# 连招衔接窗口：太久没出手就回到第一段
	if _combo_timer > 0.0:
		_combo_timer = maxf(0.0, _combo_timer - delta)
		if _combo_timer <= 0.0:
			_combo_step = 0
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		# 精灵的受击闪白（占位方块走 _draw，精灵走 shader 材质）
		if animator != null:
			animator.set_flash(_hit_flash / HIT_FLASH_TIME)
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
	# 只在非一次性动画状态下切换跑/待机与朝向。
	# 朝向用**移动方向**（WASD），而不是鼠标方向 —— 跑动时应该面朝跑的方向；
	# 攻击/受击时的朝向由那段动画自己负责，不受移动方向干扰。
	if not is_oneshot_active():
		var moving: bool = input_dir.length_squared() > 0.01
		_set_animation(&"run" if moving else &"idle")
		if moving and animator != null:
			animator.set_facing(input_dir.x)


## 是否有一次性动画（攻击段 / 受击）正在播放
func is_oneshot_active() -> bool:
	return USE_ATTACK_ANIMATION and _oneshot_timer > 0.0


func _handle_attack(_delta: float) -> void:
	# **连点触发**：每点一次鼠标 = 一次出手，依次播放 attack_1/2/3。
	# 这里用 just_pressed 而不是 pressed —— 三段连招的语义是"连点三次"，
	# 按住不放只算一次（若要恢复"按住连续攻击"，改回 pressed 并去掉连招推进即可）。
	if not Input.is_action_just_pressed(&"attack"):
		return
	# 朝向鼠标
	var mouse_pos: Vector2 = get_global_mouse_position()
	var to_mouse: Vector2 = mouse_pos - global_position
	if to_mouse.length_squared() > 0.01:
		_facing = to_mouse.normalized()
		queue_redraw()
	_try_attack()


## 出手。**无论有没有目标都会出招** —— 空地挥砍也播动画、也炸特效。
##
## 为什么必须这样：早先"没有敌人就 return"，导致空地上连点鼠标毫无反应，
## 玩家根本没法体感三段连招（也看不到攻击动画）。
## 出招节奏（= 连招节奏）仍由冷却控制，所以空挥与打中目标的节奏完全一致，
## 可以放心用它来练手/试手感。
func _try_attack() -> void:
	if _attack_cooldown > 0.0:
		return
	# 判定与动画都按冷却走，动画再长也不会削 DPS
	_attack_cooldown = data.attack_interval

	var target: Node2D = _pick_attack_target()
	if target != null:
		# 有目标就朝目标出手（否则沿用鼠标方向）
		_facing = (target.global_position - global_position).normalized()
	queue_redraw()
	_play_combo_animation()

	if target == null:
		_play_whiff_slash()
		return

	var health_comp: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if health_comp != null:
		health_comp.apply_damage(Damage.new(data.attack_damage, self, data.damage_type))
	# 命中特效炸在**受击点**（目标身上），朝攻击方向
	HitEffectSpawner.spawn_at(target.global_position, _facing.x)


## 按射程挑一个攻击目标；没敌人或没有 registry 时返回 null（= 空挥）
func _pick_attack_target() -> Node2D:
	if _registry == null:
		return null
	var candidates: Array[Node2D] = _registry.query_enemies_in_radius(global_position, data.attack_range)
	if candidates.is_empty():
		return null
	return targeting.pick_target(global_position, data.attack_range, candidates)


## 空挥特效：把挥击火花放在**身前**（而不是目标身上），
## 这样没有敌人时也能看清每一次挥砍与三段连招的衔接。
func _play_whiff_slash() -> void:
	var dist: float = maxf(data.attack_range * WHIFF_DISTANCE_RATIO, PLACEHOLDER_SIZE)
	HitEffectSpawner.spawn_at(global_position + _facing * dist, _facing.x)


# ─────────────────────────────────────────────
# 动画
# ─────────────────────────────────────────────

func _set_animation(animation_name: StringName) -> void:
	_current_anim = animation_name
	if animator != null:
		# 移动/待机用原始速度（一次性动画会临时改 speed_scale，这里复位）
		animator.speed_scale = 1.0
		animator.play_animation(animation_name)


## 播放第 _combo_step 段攻击动画，并推进连招。
##
## 三段是三个**独立动画**（attack_1/2/3），段与段之间不回中立姿势 ——
## 连续点击时看起来就是一气呵成的三连。
func _play_combo_animation() -> void:
	var anim_name := StringName(COMBO_ANIM_PREFIX + str(_combo_step + 1))
	# 推进连招（超过窗口会在 _tick_timers 里归零）
	_combo_step = (_combo_step + 1) % COMBO_LENGTH
	_combo_timer = COMBO_RESET_SECONDS
	if not USE_ATTACK_ANIMATION:
		return
	_play_oneshot(anim_name, data.attack_interval)


## 播放一段一次性动画。
##
## target_seconds > 0：按比例调整播放速度，让这段动画**正好铺满** target_seconds
##   （攻击段用这个 —— 动画比攻击间隔长的话会被反复重头播放，看起来像卡住）
## target_seconds <= 0：用素材自己的原始速度（受击用这个 —— 它是被动反馈，
##   不应该被拉长到某个固定时长）
func _play_oneshot(anim_name: StringName, target_seconds: float) -> void:
	if animator == null or not animator.sprite_frames.has_animation(anim_name):
		return
	var playback: float = 0.0
	if target_seconds > 0.0:
		playback = animator.fit_animation_to(anim_name, target_seconds)
	else:
		animator.speed_scale = 1.0
		playback = animator.animation_total_duration(anim_name)
	_oneshot_anim = anim_name
	_oneshot_timer = maxf(playback, 0.05)
	# 一次性动画的朝向按当前 _facing（攻击=瞄准方向）
	animator.set_facing(_facing.x)
	animator.play_animation(anim_name, true)


func _end_oneshot() -> void:
	_oneshot_anim = &""
	_oneshot_timer = 0.0
	if animator != null:
		animator.speed_scale = 1.0
	_refresh_locomotion_animation()


func _on_anim_finished(finished: StringName) -> void:
	# 只理会当前这段一次性动画的结束信号（旧动画的延迟信号不应打断新动画）
	if _oneshot_timer > 0.0 and finished == _oneshot_anim:
		_end_oneshot()


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
	# 受击表现是**两层叠加**（按策划决定）：
	#   1. shader 闪白 —— 即时、任何姿态都生效、不需要素材
	#   2. hurt 动画 —— 姿态变化，更有"被打到"的感觉
	# 所以即使某个单位没有 hurt 素材，闪白仍然给出完整反馈。
	_hit_flash = HIT_FLASH_TIME
	if animator != null:
		animator.set_flash(1.0)
	# 原始速度播放，不拉伸（受击是被动反馈，不该被固定成某个时长）
	_play_oneshot(&"hurt", 0.0)
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
	# 复活时清掉所有一次性动画与连招进度，从干净状态开始
	_oneshot_anim = &""
	_oneshot_timer = 0.0
	_combo_step = 0
	_combo_timer = 0.0
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
