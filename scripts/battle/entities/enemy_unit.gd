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

## 判定"在移动"的单帧位移阈值（像素）。
## 拥挤排队时敌人会被互相挤动零点几像素，阈值太低会导致 idle/run 动画闪烁。
## 正常移动是 36px/s ≈ 0.6px/帧，所以 0.25 能干净区分"真在走"与"被挤"。
const MOVE_ANIM_THRESHOLD: float = 0.25

## 受击闪白持续时长（秒）
const HIT_FLASH_TIME: float = 0.12

## 攻击反馈持续时长（秒）
const ATTACK_FLASH_TIME: float = 0.18
const ATTACK_COLOR_MELEE: Color = Color(1.0, 0.75, 0.45)
const ATTACK_COLOR_RANGED: Color = Color(1.0, 0.55, 0.35)

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

## 精灵动画（无素材时为 null，回退到占位绘制）
var animator: SpriteAnimator
var _current_anim: StringName = &"idle"

## 一次性动画队列（attack → 可选 reload / hurt）。
## 播放期间不允许移动动画覆盖它，否则敌人会"边走边打脸"——
## 之前 attack 一播放就被下一帧的 _set_animation(run) 顶掉，等于白播。
var _oneshot_queue: Array[StringName] = []
var _oneshot_anim: StringName = &""
var _oneshot_timer: float = 0.0

## 攻击反馈（程序绘制，与美术的攻击特效不冲突）
var _attack_flash: float = 0.0
var _flash_to: Vector2 = Vector2.ZERO


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
	# 与精灵实际渲染尺寸匹配。随世界尺度 ×4（原 12）：精灵显示 128px，主体约占 96px 宽。
	circle.radius = 48.0
	shape.shape = circle
	add_child(shape)

	health = HealthComponent.new()
	health.name = "HealthComponent"
	health.max_health = data.max_health
	add_child(health)
	health.died.connect(_on_died)
	health.damaged.connect(_on_damaged)

	_build_detect_area()

	# 有素材就用精灵，否则 _draw() 画占位方块/菱形
	animator = SpriteAnimator.attach(self, data.sprite_set, data.sprite_scale)
	if animator != null:
		animator.on_animation_finished = _on_anim_finished
		animator.play_animation(&"idle")
	queue_redraw()


func has_sprite() -> bool:
	return animator != null


## 根据是否在移动切换 idle / run。只在动画名变化时才调用，避免每帧重置。
## 一次性动画（攻击/换弹/受击）播放期间**不切换**，否则刚播的动画会被立刻顶掉。
func _set_animation(animation_name: StringName) -> void:
	if is_oneshot_active():
		return
	if _current_anim == animation_name:
		return
	_current_anim = animation_name
	if animator != null:
		animator.speed_scale = 1.0
		animator.play_animation(animation_name)


## 是否有一次性动画正在播放
func is_oneshot_active() -> bool:
	return _oneshot_timer > 0.0


## 依次播放一串一次性动画（例如 attack → reload）。用素材原始速度，不拉伸，
## 因为敌人的攻击间隔（1.0~1.5 秒）本身就比动画长，不需要压缩。
func _play_oneshot_queue(anims: Array[StringName]) -> void:
	_oneshot_queue = anims.duplicate()
	_advance_oneshot_queue()


func _advance_oneshot_queue() -> void:
	if animator == null:
		_oneshot_queue.clear()
		return
	# 跳过没有素材的动画（例如近战敌人没有 reload），继续找下一个能播的
	while not _oneshot_queue.is_empty():
		var next: StringName = _oneshot_queue.pop_front()
		if animator.sprite_frames.has_animation(next):
			animator.speed_scale = 1.0
			_oneshot_anim = next
			_oneshot_timer = maxf(animator.animation_total_duration(next), 0.05)
			animator.play_animation(next, true)
			return
	_end_oneshot()


func _end_oneshot() -> void:
	_oneshot_anim = &""
	_oneshot_timer = 0.0
	_oneshot_queue.clear()
	if animator != null:
		animator.speed_scale = 1.0
	# 回到移动动画（下一帧 _tick_movement_animation 也会刷新，这里先给个正确的姿态）
	_current_anim = &"idle"
	if animator != null and animator.sprite_frames.has_animation(&"idle"):
		animator.play_animation(&"idle")


## 一段一次性动画播完 → 播队列里的下一段，没有就结束
func _on_anim_finished(finished: StringName) -> void:
	if _oneshot_timer <= 0.0 or finished != _oneshot_anim:
		return   # 旧动画的延迟信号，忽略
	_oneshot_timer = 0.0
	_advance_oneshot_queue()


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
	# 一次性动画（攻击/换弹/受击）计时。animation_finished 会提前清掉它，
	# 这个计时器是兜底：万一信号没来（例如动画被切走），也不会永久卡住不出动画。
	if _oneshot_timer > 0.0:
		_oneshot_timer = maxf(0.0, _oneshot_timer - delta)
		if _oneshot_timer <= 0.0:
			_advance_oneshot_queue()
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		if animator != null:
			animator.set_flash(_hit_flash / HIT_FLASH_TIME)
		queue_redraw()

	if _attack_flash > 0.0:
		_attack_flash = maxf(0.0, _attack_flash - delta)
		queue_redraw()

	# 在一处按**真实位移**统一决定动画与路径进度。
	# 之前把动画切换写在 _move_towards() 里，覆盖不到"进入攻击距离后停下"
	# 的分支，导致站着打人的敌人还播着 run（视觉验证时发现）。
	var before: Vector2 = global_position
	if data.attack_mode == EnemyData.AttackMode.MELEE:
		_tick_melee()
	else:
		_tick_ranged(delta)
	var moved: float = before.distance_to(global_position)
	_travelled += moved
	_set_animation(&"run" if moved > MOVE_ANIM_THRESHOLD else &"idle")
	# 朝向按实际行进方向翻转（路径若拐弯也需要）
	if moved > MOVE_ANIM_THRESHOLD and animator != null:
		animator.set_facing((global_position - before).x)


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
	move_and_slide()
	# 路径进度与动画统一由 _physics_process 按真实位移处理（避免两处不一致）


# ─────────────────────────────────────────────
# 攻击
# ─────────────────────────────────────────────

func _attack_hero(hero: HeroUnit) -> void:
	if _attack_cooldown > 0.0 or hero.health == null:
		return
	_attack_cooldown = data.attack_interval
	_play_attack_feedback(hero.global_position)
	hero.health.apply_damage(Damage.new(data.attack_damage, self))


func _attack_base() -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = data.attack_interval
	_play_attack_feedback(_base_position)
	if _on_base_damage.is_valid():
		_on_base_damage.call(data.attack_damage)


func _fire_at(target: Node2D) -> void:
	_attack_cooldown = data.attack_interval
	_play_attack_feedback(target.global_position)
	var target_health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if target_health != null:
		target_health.apply_damage(Damage.new(data.attack_damage, self))


## 攻击反馈。分两层：
##   1. 若素材提供了 attack 动画就播它（远程再连播 reload —— 打完一枪接着换弹）
##   2. 程序绘制的反馈（近战=挥击弧，远程=弹道线），立即就有表现
## 两者可叠加，所以美术素材到位前后都有反馈。
func _play_attack_feedback(target_position: Vector2) -> void:
	_attack_flash = ATTACK_FLASH_TIME
	_flash_to = target_position
	# 攻击动画用**素材原始速度**：敌人攻击间隔 1.0~1.5 秒，比动画长，
	# 不需要像主角那样压缩。远程接一段 reload 构成完整射击循环
	# （attack 0.58s + reload 0.70s = 1.28s < 攻击间隔 1.5s，天然放得下）。
	var queue: Array[StringName] = [&"attack"]
	if data.attack_mode == EnemyData.AttackMode.RANGED:
		queue.append(&"reload")
	_play_oneshot_queue(queue)
	# 命中特效炸在受击点
	HitEffectSpawner.spawn_at(target_position, target_position.x - global_position.x)
	queue_redraw()


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
	# 受击表现两层叠加：shader 闪白 + hurt 动画（见 hero_unit.gd 同样说明）
	_hit_flash = HIT_FLASH_TIME
	if animator != null:
		animator.set_flash(1.0)
	# 受击动画优先于攻击动画：被打中会打断出手，这是常见做法
	if animator != null and animator.sprite_frames.has_animation(&"hurt"):
		_play_oneshot_queue([&"hurt"])
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
# 绘制
#   占位方块：仅在**没有素材**时画
#   攻击反馈：一直画（有无素材都画；美术的攻击特效到位后可叠加）
# ─────────────────────────────────────────────

func _draw() -> void:
	if not has_sprite():
		_draw_placeholder()
	_draw_attack_feedback()


func _draw_placeholder() -> void:
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


## 攻击反馈：
##   近战 —— 朝目标方向的挥击弧（读作"砍了一下"）
##   远程 —— 弹道线（读作"射了一发"）
func _draw_attack_feedback() -> void:
	if _attack_flash <= 0.0:
		return
	var t: float = _attack_flash / ATTACK_FLASH_TIME
	var to_target: Vector2 = _flash_to - global_position
	var is_melee: bool = data != null and data.attack_mode == EnemyData.AttackMode.MELEE

	if is_melee:
		var col: Color = ATTACK_COLOR_MELEE
		var dir: float = to_target.angle()
		var reach: float = minf(to_target.length(), data.attack_range + 8.0)
		# 挥击弧：从 -40° 扫到 +40°，随时间扩张并淡出
		var sweep: float = 0.7 + 0.6 * (1.0 - t)
		draw_arc(Vector2.ZERO, reach, dir - sweep, dir + sweep,
			14, Color(col, t * 0.9), 2.0, true)
		draw_arc(Vector2.ZERO, reach * 0.6, dir - sweep * 0.7, dir + sweep * 0.7,
			10, Color(1, 1, 1, t * 0.5), 1.0, true)
	else:
		var col2: Color = ATTACK_COLOR_RANGED
		draw_line(Vector2.ZERO, to_target, Color(col2, t * 0.8), 1.5, true)
		draw_circle(to_target, 2.0 + 2.5 * t, Color(col2, t * 0.9))
