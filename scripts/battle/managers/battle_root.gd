class_name BattleRoot
extends Node2D
## 战斗总装配。只负责**组装**子场景与系统，不写具体规则。
##
## 系统的职责划分见 DESIGN.md 第 12 节：
##   BattleRoot   装配、持有 BattleState、启动/结束战斗
##   RoundManager 阶段状态机、波次推进、复活调度
##   WaveSpawner  生成敌人
##   UnitRegistry 单位注册与查询
##   BattleState  战斗级数据（大本营血量、波次、惩罚档位、局内资源）

const DEFAULT_LEVEL_PATH: String = "res://resources/levels/test_level.tres"
const ENTITIES_CONTAINER: StringName = &"Entities"

## 战斗结束（无论胜负）。上层（选关/结算界面）订阅它来写入局外进度。
signal battle_finished(level: LevelData, won: bool)
## 仅胜利，供 UI 做表现
signal battle_won_for_ui()

var level: LevelData
var state: BattleState
var registry: UnitRegistry
var economy: BattleEconomy
var spawner: WaveSpawner
var rounds: RoundManager
var hud: BattleHUD

var _map: TestLevelMap
var _entities: Node2D
var _hero: HeroUnit
var _base: BaseUnit
var _towers: Array[TowerUnit] = []
var _base_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_setup()


## 从头再来：**就地重建**一场全新战斗（不重载场景）。
##
## 【为什么不直接用 get_tree().reload_current_scene()】
##   那个只在"本节点恰好就是当前场景根"时才有效。将来战斗由选关界面实例化
##   （关卡间的"重试"按钮）时，reload_current_scene() 会去重载选关界面甚至出错。
##   就地重建在任何宿主下都成立，而且**自动化测试可以直接调用它验证**。
##
## 排掉的东西：单位、地图、据点、HUD、命中特效生成器（全是子节点，整棵清掉），
## 以及 BattleState / UnitRegistry / BattleEconomy / WaveSpawner / RoundManager
## 这五个管理器实例（下一轮 _build_managers() 会重新创建）。
func restart() -> void:
	_teardown()
	_setup()


func _setup() -> void:
	_load_level()
	if level == null:
		push_error("没有可用的关卡配置，战斗无法开始")
		return

	_build_managers()
	_build_map()
	_build_entities_container()
	_spawn_base()
	_spawn_hero()
	_spawn_towers()
	_build_hud()
	_wire_round_manager()
	rounds.begin()


## 拆掉这一场战斗的全部运行时对象，回到"刚 new 出来"的干净状态。
func _teardown() -> void:
	# 先清空缓存引用，避免拆除过程中有回调又读到半死不活的对象
	_towers.clear()
	_hero = null
	_base = null
	_entities = null
	_map = null
	hud = null
	state = null
	registry = null
	economy = null
	spawner = null
	rounds = null
	_base_position = Vector2.ZERO

	# remove_child 立即把它从树上摘掉（于是 HitEffectSpawner 的静态实例引用
	# 会在 _exit_tree 里被清掉），queue_free 只负责回收内存。
	# 先摘后释放，这样紧接着的 _setup() 不会看到任何残留节点。
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


# ─────────────────────────────────────────────
# 装配
# ─────────────────────────────────────────────

func _load_level() -> void:
	# 本期主场景直接就是战斗场景，所以没有"选关"传来的关卡，
	# 回退到默认的实验关卡配置。
	level = ResourceLoader.load(DEFAULT_LEVEL_PATH) as LevelData
	if level == null:
		push_error("无法加载关卡配置: %s" % DEFAULT_LEVEL_PATH)


func _build_managers() -> void:
	state = BattleState.new()
	state.setup(level.base_max_health, level.wave_count(), level.starting_battle_currency)

	registry = UnitRegistry.new()
	registry.name = "UnitRegistry"
	registry.add_to_group(&"unit_registry")
	add_child(registry)

	economy = BattleEconomy.new()
	economy.name = "BattleEconomy"
	bind_economy_state()
	add_child(economy)

	spawner = WaveSpawner.new()
	spawner.name = "WaveSpawner"
	spawner.on_enemy_created = _on_enemy_created
	spawner.spawn_queue_finished.connect(_on_spawn_queue_finished)
	add_child(spawner)

	rounds = RoundManager.new()
	rounds.name = "RoundManager"
	rounds.bind(state, level, registry)
	add_child(rounds)


func bind_economy_state() -> void:
	if economy != null and state != null:
		economy.bind_state(state)


func _build_map() -> void:
	var map_path: String = level.map_scene_path
	if map_path.is_empty():
		map_path = "res://scenes/battle/map/test_level.tscn"
	var packed: PackedScene = load(map_path) as PackedScene
	if packed == null:
		push_error("无法加载地图场景: %s" % map_path)
		return
	var map_node: Node = packed.instantiate()
	_map = map_node as TestLevelMap
	if _map == null:
		push_error("地图场景根节点必须挂 test_level_map.gd 脚本: %s" % map_path)
		map_node.queue_free()
		return
	add_child(_map)
	_base_position = _map.base_position()


func _build_entities_container() -> void:
	_entities = Node2D.new()
	_entities.name = ENTITIES_CONTAINER
	add_child(_entities)

	# 命中特效生成器。单位侧用 HitEffectSpawner.spawn_at() 静态调用，
	# 不需要沿攻击链条层层传引用。素材缺失时它自己静默降级。
	_entities.add_child(HitEffectSpawner.new())


func _spawn_hero() -> void:
	var hero_data: CharacterData = CharacterRegistry.find_hero()
	if hero_data == null:
		push_error("找不到主角配置（需要一个 role=HERO 的 CharacterData）")
		return
	_hero = HeroUnit.create(hero_data)
	_entities.add_child(_hero)
	_hero.global_position = _map.hero_start_position()
	_hero.bind_registry(registry)
	_hero.died.connect(_on_hero_died)


## 大本营。它之前只是地图脚本画的一个调试方框，没有实体节点，
## 美术素材无处可挂。这里创建真正的节点并绑定战斗状态做受击反馈。
func _spawn_base() -> void:
	_base = BaseUnit.create(level.base_sprite_set, level.base_sprite_scale, level.base_display_size)
	_entities.add_child(_base)
	_base.global_position = _base_position
	_base.bind_state(state)
	_base.destroyed.connect(_on_base_visual_destroyed)


func _spawn_towers() -> void:
	var slots: Array[Vector2] = _map.tower_slot_positions()
	if slots.is_empty():
		push_warning("地图里没有塔位（map_tower_slot 组），本次战斗将没有塔")
		return

	# M1 取第一个塔角色配置；将来由选人界面决定放哪些
	var tower_data: CharacterData = _find_first_tower()
	if tower_data == null:
		push_warning("找不到塔角色配置，本次战斗将没有塔")
		return

	# 每个塔位都放一座（实验关卡通常只有 1~2 个塔位）
	for i: int in range(slots.size()):
		var tower: TowerUnit = TowerUnit.create(tower_data, i)
		_entities.add_child(tower)
		tower.global_position = slots[i]
		tower.bind_registry(registry)
		_towers.append(tower)


func _find_first_tower() -> CharacterData:
	for data: CharacterData in CharacterRegistry.all_characters():
		if data.role == CharacterData.Role.TOWER:
			return data
	return null


func _build_hud() -> void:
	hud = BattleHUD.new()
	hud.name = "BattleHUD"
	add_child(hud)
	hud.bind(state, rounds)


func _wire_round_manager() -> void:
	rounds.on_enter_prepare = _on_enter_prepare
	rounds.on_enter_combat = _on_enter_combat
	rounds.on_enter_settle = _on_enter_settle
	rounds.on_hero_respawn = _on_hero_respawn
	rounds.battle_won.connect(_on_battle_won)
	rounds.battle_lost.connect(_on_battle_lost)
	state.base_destroyed.connect(_on_base_destroyed)


# ─────────────────────────────────────────────
# 阶段回调
# ─────────────────────────────────────────────

func _on_enter_prepare(_wave_index: int) -> void:
	if hud != null:
		hud.refresh()


func _on_enter_combat(_wave_index: int, wave: WaveData) -> void:
	# 这里就是 COMBAT 双重退出条件的关键编排：
	# 必须在 start_wave 之前把 _spawn_finished 置为 false，
	# 否则第一帧就会误判"生成队列已空 → 波次已清"。
	rounds.notify_wave_started_spawning()
	spawner.start_wave(wave, _map.spawn_position(), _entities)
	if hud != null:
		hud.refresh()


func _on_enter_settle(_wave_index: int) -> void:
	# 结算：塔重生
	for tower: TowerUnit in _towers:
		if tower == null or not is_instance_valid(tower):
			continue
		if tower.health != null and tower.health.is_dead:
			tower.health.revive_full()
			tower.visible = true
			tower.set_process(true)
	# 注意：大本营血量**跨波次不恢复**（DESIGN.md 第 6 节）。这里刻意什么都不做。
	if hud != null:
		hud.refresh()


func _on_hero_respawn() -> void:
	if _hero != null and is_instance_valid(_hero):
		_hero.revive()
	if hud != null:
		hud.refresh()


# ─────────────────────────────────────────────
# 事件
# ─────────────────────────────────────────────

func _on_enemy_created(enemy: Node2D) -> void:
	var unit: EnemyUnit = enemy as EnemyUnit
	if unit == null:
		return
	unit.bind_registry(registry)
	unit.bind_economy(economy)
	unit.bind_base_damage(_on_base_take_damage)
	unit.setup_path(_map.waypoint_positions(), _base_position, self)
	if hud != null:
		hud.refresh()


func _on_spawn_queue_finished() -> void:
	rounds.notify_spawn_queue_finished()


func _on_base_take_damage(amount: float) -> void:
	state.damage_base(amount)


func _on_base_destroyed() -> void:
	# RoundManager 已连接 base_destroyed，这里只做表现
	if hud != null:
		hud.refresh()


## 大本营节点的表现层收到"归零"通知（只做表现，胜负由 RoundManager 判定）
func _on_base_visual_destroyed() -> void:
	if hud != null:
		hud.refresh()


func _on_hero_died() -> void:
	rounds.notify_hero_died()
	if hud != null:
		hud.refresh()


func _on_battle_won() -> void:
	# 注意：这里**不直接调用 GameState**。
	# 战斗层只负责"报告结果"，局外进度由订阅 battle_finished 的上层处理
	# （将来是选关界面 / 关卡结算界面）。这样战斗场景不依赖 autoload，
	# 自动化测试也能直接实例化它。
	battle_finished.emit(level, true)
	battle_won_for_ui.emit()


func _on_battle_lost() -> void:
	battle_finished.emit(level, false)


## 供测试与上层访问地图（塔位/路径/大本营都在里面）
func get_map() -> TestLevelMap:
	return _map


## 供测试与上层访问主角
func get_hero() -> HeroUnit:
	return _hero


# ─────────────────────────────────────────────
# 杂项
# ─────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return   # 按住不放会持续产生 echo，否则会疯狂触发
	# 回车：开始当前波次。布防阶段随时可用（即使这关配了自动开始也能提前开战）。
	if event.is_action_pressed(&"start_wave"):
		if rounds != null:
			rounds.request_start_wave()
		return
	# 重开 / 认输。两者是同一个动作：战斗中按下 = 认输重开，
	# 打完之后按下 = 直接再来一遍（免得为了重测又去按 F5）。
	if event.is_action_pressed(&"restart") or event.is_action_pressed(&"surrender"):
		restart()
	elif event.is_action_pressed(&"pause"):
		get_tree().quit()
