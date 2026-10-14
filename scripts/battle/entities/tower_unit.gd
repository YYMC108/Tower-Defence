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
const PLACEHOLDER_SIZE: float = 12.0

var data: CharacterData
## 所在塔位索引，供重建 / 合成系统使用
var slot_index: int = -1

var health: HealthComponent
var targeting: TargetingComponent

var _attack_cooldown: float = 0.0
var _registry: UnitRegistry = null
var _current_target: Node2D = null
var _hit_flash: float = 0.0


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


func bind_registry(registry: UnitRegistry) -> void:
	_registry = registry
	if registry != null:
		registry.register_tower(self)


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
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
	queue_redraw()

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
	queue_redraw()


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
# 绘制（占位美术：纯色方块）
# ─────────────────────────────────────────────

func _draw() -> void:
	var half: float = PLACEHOLDER_SIZE * 0.5
	var body_color: Color = PLACEHOLDER_COLOR
	if data != null and data.tower_kind == CharacterData.TowerKind.HEAL:
		body_color = Color(0.45, 0.90, 0.70)
	if _hit_flash > 0.0:
		body_color = body_color.lerp(Color.WHITE, 0.7)

	# 射程提示（淡淡的圈）
	if data != null:
		draw_arc(Vector2.ZERO, data.attack_range, 0.0, TAU, 48, Color(body_color, 0.16), 1.0)

	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color, true)
	draw_rect(Rect2(Vector2(-half, -half), Vector2(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE)), body_color.darkened(0.5), false, 1.0)

	# 攻击目标指示线
	if _current_target != null and is_instance_valid(_current_target) and _current_target.is_inside_tree():
		draw_line(Vector2.ZERO, to_local(_current_target.global_position), Color(body_color, 0.55), 1.0)
