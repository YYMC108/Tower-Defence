class_name TowerUnit
extends Node2D
## 塔角色。放在塔位上，自动索敌攻击。
##
## 输出 / 治疗 / 控制三类**共用这一套代码**，靠 CharacterData.tower_kind 区分
## （DESIGN.md 第 4.2 节）。本期只实现 DPS 与 HEAL 两种，CONTROL 留给状态效果系统。
##
## 生存（DESIGN.md 第 3 节）：塔的唯一威胁是远程敌人。本期 M1 没有远程敌人，
## 所以塔不会被摧毁；塔被摧毁 → 局内资源重建的流程留到 M2。

signal died()

const PLACEHOLDER_COLOR: Color = Color(0.35, 0.62, 0.95)
## 塔的精灵画布 64px、显示 32px。占位方块按显示尺寸画。
const PLACEHOLDER_SIZE: float = 26.0

## 攻击特效：不做新素材，纯程序绘制。
## 塔目前只有 1 帧 idle（美术尚未交付攻击动画），如果什么都不做，
## 打架时塔是完全静止的，玩家感知不到它在输出。
const ATTACK_FLASH_TIME: float = 0.16
const ATTACK_FLASH_COLOR: Color = Color(1.0, 0.92, 0.55)
const HEAL_FLASH_COLOR: Color = Color(0.55, 1.0, 0.70)
## 开火瞬间的"后坐"缩放（1.0 -> 1.1 -> 1.0）
const ATTACK_PUNCH: float = 0.10

var data: CharacterData
## 所在塔位索引，供重建 / 合成系统使用
var slot_index: int = -1

var health: HealthComponent
var targeting: TargetingComponent
var animator: SpriteAnimator

var _attack_cooldown: float = 0.0
var _registry: UnitRegistry = null
var _current_target: Node2D = null
var _hit_flash: float = 0.0

# 攻击特效状态
var _attack_flash: float = 0.0
var _flash_to: Vector2 = Vector2.ZERO
var _flash_color: Color = ATTACK_FLASH_COLOR


static func create(p_data: CharacterData, p_slot_index: int = -1) -> TowerUnit:
	var tower := TowerUnit.new()
	tower.name = "TowerUnit"
	tower.data = p_data
	tower.slot_index = p_slot_index
	return tower


func _ready() -> void:
	_build_nodes()
	set_process(true)
	queue_redraw()


func _build_nodes() -> void:
	if data == null:
		push_error("TowerUnit 缺少 CharacterData")
		return

	# 塔不加物理碰撞体：近战本就无视塔（DESIGN.md 第 3 节规则 3），
	# 加了反而可能意外阻挡敌人寻路。
	# 注意 TowerUnit 继承 Node2D，本身没有 collision_layer 属性，
	# 将来若需要受击判定，改成 Area2D 或加 HurtboxComponent 子节点。

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
		# 塔目前只有 idle 动画（美术侧尚未交付攻击动画，见 ART_HANDOVER.md 第八节）。
		# 所以攻击时不切动画；等攻击动画到位再接。
		animator.play_animation(&"idle")


func has_sprite() -> bool:
	return animator != null


func bind_registry(registry: UnitRegistry) -> void:
	_registry = registry
	if registry != null:
		registry.register_tower(self)


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		queue_redraw()

	if _attack_flash > 0.0:
		_attack_flash = maxf(0.0, _attack_flash - delta)
		_apply_punch()
		queue_redraw()

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
		return

	match data.tower_kind:
		CharacterData.TowerKind.HEAL:
			_try_heal()
		CharacterData.TowerKind.CONTROL:
			pass  # 需要状态效果系统，本期不做
		_:
			_try_attack()


## 开火瞬间把精灵短暂放大一点，制造"后坐"感。
## 基准缩放始终从 data.sprite_scale 重算，避免多次叠加后漂移。
func _apply_punch() -> void:
	if animator == null or data == null:
		return
	var t: float = _attack_flash / ATTACK_FLASH_TIME
	var punch: float = 1.0 + ATTACK_PUNCH * t
	animator.scale = Vector2.ONE * (data.sprite_scale * punch)


## 触发攻击特效。target_position 用世界坐标。
func _play_attack_effect(target_position: Vector2, color: Color) -> void:
	_attack_flash = ATTACK_FLASH_TIME
	_flash_to = target_position
	_flash_color = color
	_apply_punch()
	queue_redraw()


# ─────────────────────────────────────────────
# 输出塔
# ─────────────────────────────────────────────

func _try_attack() -> void:
	if _registry == null:
		return
	var candidates: Array[Node2D] = _registry.query_enemies_in_radius(global_position, data.attack_range)
	if candidates.is_empty():
		_current_target = null
		return
	var target: Node2D = targeting.pick_target(global_position, data.attack_range, candidates)
	if target == null:
		return
	_current_target = target
	_attack_cooldown = data.attack_interval
	_play_attack_effect(target.global_position, ATTACK_FLASH_COLOR)

	var target_health: HealthComponent = target.get_node_or_null("HealthComponent") as HealthComponent
	if target_health != null:
		target_health.apply_damage(Damage.new(data.attack_damage, self, data.damage_type))


# ─────────────────────────────────────────────
# 治疗塔（主角唯一的回血手段，DESIGN.md 第 4.2 节）
# ─────────────────────────────────────────────

func _try_heal() -> void:
	if _registry == null:
		return
	var patient: HeroUnit = _pick_lowest_health_hero()
	if patient == null:
		return
	_attack_cooldown = data.heal_interval
	patient.health.heal(data.heal_amount)
	_current_target = patient
	_play_attack_effect(patient.global_position, HEAL_FLASH_COLOR)


func _pick_lowest_health_hero() -> HeroUnit:
	var best: HeroUnit = null
	var best_ratio: float = 1.0
	for candidate: Node2D in _registry.heroes:
		if candidate is HeroUnit:
			var hero: HeroUnit = candidate as HeroUnit
			if not hero.is_alive() or hero.health == null:
				continue
			var ratio: float = hero.health.health_ratio()
			if ratio < best_ratio:
				best_ratio = ratio
				best = hero
	return best


# ─────────────────────────────────────────────
# 受击
# ─────────────────────────────────────────────

func _on_damaged(_damage: Damage) -> void:
	_hit_flash = 0.12
	queue_redraw()


func _on_died(_damage: Damage) -> void:
	set_process(false)
	visible = false
	died.emit()


# ─────────────────────────────────────────────
# 绘制
#   射程光圈：一直画（调试可视，方便看防守覆盖），画得淡以免盖住精灵
#   占位方块 + 目标线：仅在**没有素材**时画（有精灵就交给精灵表现）
#   攻击特效：一直画（有无素材都画；否则有美术后塔打架会完全没有反馈）
# ─────────────────────────────────────────────

func _draw() -> void:
	var has_art: bool = has_sprite()
	var half: float = PLACEHOLDER_SIZE * 0.5
	var body_color: Color = PLACEHOLDER_COLOR
	if data != null and data.tower_kind == CharacterData.TowerKind.HEAL:
		body_color = Color(0.45, 0.90, 0.70)
	if _hit_flash > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.7)

	if data != null:
		var arc_alpha: float = 0.10 if has_art else 0.16
		draw_arc(Vector2.ZERO, data.attack_range, 0.0, TAU, 48, Color(body_color, arc_alpha), 1.0)

	# 攻击特效画在精灵之上，所以在占位分支之前处理
	_draw_attack_effect()

	# 占位方块与攻击目标线仅在无素材时画
	if has_art:
		return

	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color, true)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color.darkened(0.5), false, 1.0)

	if _current_target != null and is_instance_valid(_current_target) and _current_target.is_inside_tree():
		draw_line(Vector2.ZERO, to_local(_current_target.global_position), Color(body_color, 0.55), 1.0)


## 画开火/治疗特效：枪口闪光 + 曳光弹道 + 命中点。
## 全部程序绘制，不需要美术出图；将来塔有了攻击动画，这套特效依然适用。
func _draw_attack_effect() -> void:
	if _attack_flash <= 0.0:
		return
	var t: float = _attack_flash / ATTACK_FLASH_TIME   # 1.0 -> 0.0
	var fade: float = t
	var local_to: Vector2 = to_local(_flash_to)

	# 曳光弹道
	draw_line(Vector2.ZERO, local_to, Color(_flash_color, fade * 0.85), 2.0, true)
	draw_line(Vector2.ZERO, local_to, Color(1, 1, 1, fade * 0.45), 1.0, true)

	# 枪口闪光
	draw_circle(Vector2.ZERO, 3.0 + 3.0 * t, Color(_flash_color, fade * 0.9))

	# 命中点：圆点 + 扩散的环
	draw_circle(local_to, 2.0 + 2.5 * t, Color(_flash_color, fade))
	draw_arc(local_to, 4.0 + 5.0 * (1.0 - t), 0.0, TAU, 16, Color(_flash_color, fade * 0.7), 1.0)
