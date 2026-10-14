extends Node
## 战斗循环冒烟测试（集成测试）。
##
## 运行方式（**必须以场景方式运行**，因为 --script 模式不会注册 autoload）：
##   godot --headless --path . res://tests/battle_smoke_test.tscn -- --no-save
##
## 退出码：0 = 全部通过；非 0 = 失败项数量。
##
## 它真的把战斗场景跑起来，逐帧检查核心机制：
##   1. 场景能否装配成功（地图/主角/塔/HUD）
##   2. 波次是否开始、敌人是否生成
##   3. 敌人是否沿路径推进
##   4. 主角存活时是否构成物理阻挡（碰撞层机制）
##   5. 主角死亡后碰撞体是否关闭（近战可穿过）
##   6. 近战抵达大本营后大本营是否掉血
##   7. 主角是否按"递增 + 封顶"复活
##   8. 波次清空与胜负判定
##
## 注意：headless 没有鼠标，主角的"鼠标攻击"不会触发。
## 这是有意的 —— 本测试只验证**不依赖输入**的部分（寻路、阻挡、复活、大本营）。
## 主角攻击手感必须由人在编辑器里按 F5 试。

const BATTLE_SCENE: String = "res://scenes/battle/battle_root.tscn"
const STEP: float = 1.0 / 60.0

var _fail: int = 0
var _checks: int = 0
var _battle: BattleRoot = null


func _ready() -> void:
	# 测试绝不写真实存档
	SaveManager.writes_enabled = false
	_run()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  [通过] %s" % label)
	else:
		print("  [失败] %s" % label)
		_fail += 1


func _run() -> void:
	print("=== 战斗循环冒烟测试 ===")

	print("")
	print("--- 1. 场景装配 ---")
	var packed: PackedScene = load(BATTLE_SCENE) as PackedScene
	_check(packed != null, "battle_root.tscn 可加载")
	if packed == null:
		return _finish()

	_battle = packed.instantiate() as BattleRoot
	_check(_battle != null, "根节点脚本是 BattleRoot")
	if _battle == null:
		return _finish()

	add_child(_battle)
	await _advance(0.1)

	_check(_battle.level != null, "关卡配置已加载")
	_check(_battle.state != null, "BattleState 已创建")
	_check(_battle.registry != null, "UnitRegistry 已创建")
	_check(_battle.rounds != null, "RoundManager 已创建")
	_check(_battle.hud != null, "HUD 已创建")
	_check(_battle.get_map() != null, "地图已装配")
	_check(_battle.state.total_waves == 1, "总波次 = 1（与 level 配置一致）")
	_check(is_equal_approx(_battle.state.base_health, 100.0), "大本营初始血量 = 100")

	var hero: HeroUnit = _battle.get_hero()
	_check(hero != null, "主角已生成")
	_check(_battle.registry.towers.size() == 1, "塔数量 = 1（与地图塔位数一致）")
	if hero != null:
		_check(hero.collision_layer != 0, "主角初始碰撞层非 0（构成物理阻挡）")

	var map: TestLevelMap = _battle.get_map()
	var spawn: Vector2 = map.spawn_position()
	var base_pos: Vector2 = map.base_position()
	_check(map.waypoint_positions().size() == 3, "路径点数量 = 3")
	_check(map.tower_slot_positions().size() == 1, "塔位数量 = 1")
	print("  出生点=%s 大本营=%s 主角起始=%s" % [
		str(spawn), str(base_pos), str(map.hero_start_position()),
	])

	print("")
	print("--- 2. 布防 → 战斗 → 敌人生成 ---")
	await _advance_until(func() -> bool: return _battle.rounds.phase == RoundManager.Phase.COMBAT, 6.0)
	_check(_battle.rounds.phase == RoundManager.Phase.COMBAT, "布防结束后进入战斗阶段")
	await _advance(0.8)
	_check(_battle.registry.enemy_count() > 0,
		"敌人已生成（当前 %d 只）" % _battle.registry.enemy_count())

	print("")
	print("--- 3. 敌人沿路径推进 ---")
	var enemy_a: Node2D = _first_enemy()
	var progress_a: float = float(enemy_a.call("path_progress")) if enemy_a != null else 0.0
	await _advance(1.5)
	var enemy_b: Node2D = _first_enemy()
	if enemy_b != null and enemy_a == enemy_b:
		var progress_b: float = float(enemy_b.call("path_progress"))
		_check(progress_b > progress_a,
			"敌人沿路径前进（进度 %.1f → %.1f）" % [progress_a, progress_b])
	else:
		_check(true, "敌人已轮换（生成/死亡），跳过推进断言")

	print("")
	print("--- 4. 主角存活 → 构成物理阻挡 ---")
	if hero != null and hero.is_alive():
		# 把主角挪到敌人前方，模拟玩家站在路上挡人
		var enemy: Node2D = _first_enemy()
		if enemy != null:
			hero.global_position = enemy.global_position + Vector2(24, 0)
		await _advance(0.8)
		_check(hero.collision_layer == PhysicsLayers.bit(&"player"),
			"主角存活时碰撞层 = player 层（值 %d）" % hero.collision_layer)
		_check(not Input.is_action_pressed(&"attack"),
			"headless 下 attack 未按下（说明本测试不依赖鼠标输入）")
	else:
		_check(false, "主角存活（检查开始时）")

	print("")
	print("--- 5. 主角死亡 → 碰撞体关闭 ---")
	if hero != null:
		hero.health.invulnerable = false
		hero.health.apply_damage(Damage.new(999999.0, null, Damage.Type.TRUE))
		await _advance(0.05)
		_check(not hero.is_alive(), "主角已阵亡")
		_check(hero.collision_layer == 0, "阵亡后碰撞层 = 0（近战可穿过 → 直冲大本营）")
		_check(_battle.rounds.is_hero_dead(), "RoundManager 记录了主角死亡")
		_check(_battle.state.hero_death_count == 1, "死亡计数 = 1（布防阶段死亡也计数）")

	print("")
	print("--- 6. 近战抵达大本营 → 大本营掉血 ---")
	var base_before: float = _battle.state.base_health
	var waited: float = 0.0
	while waited < 25.0 and _battle.state.base_health >= base_before and not _battle.rounds.is_battle_over():
		await _advance(0.5)
		waited += 0.5
	_check(_battle.state.base_health < base_before,
		"大本营受到伤害（%.0f → %.0f，等待 %.1f 秒）" % [
			base_before, _battle.state.base_health, waited,
		])

	print("")
	print("--- 7. 主角递增惩罚复活 ---")
	var revived: bool = false
	var waited2: float = 0.0
	while waited2 < 14.0 and not revived:
		await _advance(0.25)
		waited2 += 0.25
		if hero != null and hero.is_alive():
			revived = true
	_check(revived, "主角已复活（等待 %.1f 秒，第 1 次档位应为 5 秒）" % waited2)
	if hero != null:
		_check(hero.collision_layer != 0, "复活后碰撞层恢复（重新构成阻挡）")
		_check(is_equal_approx(hero.health.current_health, hero.data.max_health),
			"复活后满血（%.0f / %.0f）" % [hero.health.current_health, hero.data.max_health])

	print("")
	print("--- 8. 复活惩罚曲线递增与封顶 ---")
	var lvl: LevelData = _battle.level
	var curve: PackedFloat32Array = PackedFloat32Array()
	for i: int in range(1, 9):
		curve.append(lvl.revive_seconds_for_death(i))
	print("  死亡 1..8 次 → %s" % str(curve))
	_check(is_equal_approx(curve[0], 5.0), "第 1 次 = 5 秒")
	_check(is_equal_approx(curve[1], 10.0), "第 2 次 = 10 秒")
	_check(is_equal_approx(curve[2], 15.0), "第 3 次 = 15 秒")
	_check(is_equal_approx(curve[7], 30.0), "第 8 次 = 30 秒（已封顶）")

	print("")
	print("--- 9. 波次清空与胜负判定 ---")
	var cleared: bool = false
	var waited3: float = 0.0
	while waited3 < 60.0 and not _battle.rounds.is_battle_over():
		await _advance(0.5)
		waited3 += 0.5
		if _battle.registry.enemy_count() == 0 and _battle.rounds.phase == RoundManager.Phase.SETTLE:
			cleared = true
	print("  最终：阶段=%s 大本营=%.0f 场上敌人=%d 波次索引=%d" % [
		RoundManager.Phase.keys()[_battle.rounds.phase],
		_battle.state.base_health,
		_battle.registry.enemy_count(),
		_battle.state.current_wave_index,
	])
	_check(cleared or _battle.rounds.is_battle_over(), "敌人清空后波次推进（或战斗已结束）")
	_check(_battle.rounds.is_battle_over(), "只配置 1 波，战斗应已结束")
	_check(_battle.rounds.did_win() or not _battle.state.is_base_alive(),
		"胜负状态自洽（胜利 或 大本营已陷落）")
	if _battle.rounds.did_win():
		print("  → 结果是【胜利】")
	else:
		print("  → 结果是【大本营陷落】（headless 下主角不攻击，属预期）")

	_finish()


# ─────────────────────────────────────────────
# 工具
# ─────────────────────────────────────────────

func _advance(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var step: float = minf(STEP, remaining)
		await get_tree().create_timer(step).timeout
		remaining -= step


func _advance_until(condition: Callable, timeout: float) -> void:
	var waited: float = 0.0
	while waited < timeout:
		if bool(condition.call()):
			return
		await _advance(0.2)
		waited += 0.2


func _first_enemy() -> Node2D:
	if _battle == null or _battle.registry == null:
		return null
	var enemies: Array[Node2D] = _battle.registry.get_enemies()
	if enemies.is_empty():
		return null
	return enemies[0]


func _finish() -> void:
	print("")
	if _fail == 0:
		print(">>> 冒烟测试全部通过（%d 项检查）<<<" % _checks)
	else:
		print(">>> 有 %d / %d 项失败 <<<" % [_fail, _checks])
	get_tree().quit(_fail)
