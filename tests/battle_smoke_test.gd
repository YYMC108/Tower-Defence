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
##
## ⚠️ 排查提示：本测试如果**一行都不打印、进程也不退出**，那多半不是逻辑卡死，
##    而是脚本有**解析错误**：解析失败 → _ready() 从不执行 → 场景空转 → 永不 quit。
##    逐行等下去是查不到的，直接这样定位（只解析、不执行）：
##
##      godot --headless --path . --check-only --script res://tests/battle_smoke_test.gd
##
##    看有没有 `Parse Error`。若只看到
##    `Compile Error: Identifier not found: SaveManager` 那是**预期的**——
##    --script 模式不注册 autoload，本测试用场景模式跑，不受影响。
##
##    真实教训：一次改测试时重复声明了变量 base_pos，结果表现为"测试卡死"，
##    浪费了一轮排查。解析错误在这种场景下的症状是**静默挂起**，不是报错退出。

const BATTLE_SCENE: String = "res://scenes/battle/battle_root.tscn"
## 测试的**观察粒度**，不是物理步长 —— 物理始终按引擎自己的 60Hz 跑，
## 这个值只决定测试多久 yield 一次去查看状态。取 1/20 而不是 1/60：
## 视口放大到 1536x960 后 headless 帧率下降，await 次数太多会让测试极慢。
## 本测试的判定都不依赖 1/60 级精度（最短的攻击间隔也有 1 秒）。
const STEP: float = 1.0 / 20.0

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
	print("--- 4. 敌人攻击大本营 → 大本营掉血（确定性验证）---")
	# 不依赖「敌人自己走过去」：塔可能提前把它们打死，波次提前清空而胜利 ——
	# 那是合法结果，但会让断言变得不确定。这里直接把一个敌人放到大本营的
	# 攻击距离之内：该处已在塔的射程之外，结果确定，专门验证「敌人→大本营」通路。
	var base_before: float = _battle.state.base_health
	var probe: EnemyUnit = _first_enemy() as EnemyUnit
	if probe == null:
		_check(false, "没有敌人可用于验证大本营伤害")
	else:
		# 复用第 1 步已取到的 base_pos（重复声明会解析错误）
		probe.global_position = base_pos - Vector2(60.0, 0.0)
		await _advance(3.0)
		_check(_battle.state.base_health < base_before,
			"敌人攻击大本营造成伤害（%.0f → %.0f）" % [
				base_before, _battle.state.base_health,
			])
		# 验证完就让这个探针敌人退场，否则它会一直啃大本营，
		# 使后面的波次永远清不掉（剩下的断言就失去意义了）。
		if is_instance_valid(probe) and probe.is_alive():
			probe.health.invulnerable = false
			probe.health.apply_damage(Damage.new(999999.0, null, Damage.Type.TRUE))
		await _advance(0.1)

	print("")
	print("--- 5. 主角存活 → 构成物理阻挡 ---")
	if hero != null and hero.is_alive():
		# 把主角挪到敌人前方，模拟玩家站在路上挡人。
		# 偏移量 96 = 单位显示尺寸 128 的 3/4（世界尺度 ×4 后的值，原为 24）。
		var enemy: Node2D = _first_enemy()
		if enemy != null:
			hero.global_position = enemy.global_position + Vector2(96, 0)
		await _advance(0.8)
		_check(hero.collision_layer == PhysicsLayers.bit(&"player"),
			"主角存活时碰撞层 = player 层（值 %d）" % hero.collision_layer)
		_check(not Input.is_action_pressed(&"attack"),
			"headless 下 attack 未按下（说明本测试不依赖鼠标输入）")
	else:
		_check(false, "主角存活（检查开始时）")

	print("")
	print("--- 6. 主角死亡 → 碰撞体关闭 ---")
	if hero != null:
		hero.health.invulnerable = false
		hero.health.apply_damage(Damage.new(999999.0, null, Damage.Type.TRUE))
		await _advance(0.05)
		_check(not hero.is_alive(), "主角已阵亡")
		_check(hero.collision_layer == 0, "阵亡后碰撞层 = 0（近战可穿过 → 直冲大本营）")
		_check(_battle.rounds.is_hero_dead(), "RoundManager 记录了主角死亡")
		_check(_battle.state.hero_death_count == 1, "死亡计数 = 1（布防阶段死亡也计数）")

	print("")
	print("--- 7. 主角递增惩罚复活 ---")
	# 用 0.05 秒粒度轮询，在复活那一刻取血量。
	#
	# 两个坑：
	#   1. 不能最后再查 —— 敌人仇恨半径 304，主角一复活就可能立刻挨打，
	#      事后读到的不是复活时的血量。
	#   2. 不能用「逐帧」轮询（STEP=1/60）—— 视口放大到 1536x960 后 headless
	#      帧率下降，逐帧轮询会让模拟时间推进远慢于真实时间，测试变得极慢。
	#      敌人攻击间隔 ≥ 1 秒，0.05 秒粒度足够精确。
	const REVIVE_POLL_STEP: float = 0.05
	var revived: bool = false
	var health_at_revive: float = -1.0
	var waited2: float = 0.0
	while waited2 < 14.0 and not revived:
		await _advance(REVIVE_POLL_STEP)
		waited2 += REVIVE_POLL_STEP
		if hero != null and hero.is_alive():
			revived = true
			health_at_revive = hero.health.current_health
	_check(revived, "主角已复活（等待 %.1f 秒，第 1 次档位应为 5 秒）" % waited2)
	if hero != null:
		_check(hero.collision_layer != 0, "复活后碰撞层恢复（重新构成阻挡）")
		_check(is_equal_approx(health_at_revive, hero.data.max_health),
			"复活瞬间满血（%.0f / %.0f）" % [health_at_revive, hero.data.max_health])

	print("")
	print("--- 8. 三段连招与受击动画叠加 ---")
	if hero != null and hero.animator != null:
		# 连点四次：应依次 attack_1 → attack_2 → attack_3 → 回到 attack_1
		# （直接调播放函数，避开 headless 下无法模拟鼠标点击的限制；
		#   输入层用 is_action_just_pressed，因此"每次点击 = 一次出手"）
		var played: PackedStringArray = PackedStringArray()
		for i: int in range(4):
			hero.call("_play_combo_animation")
			played.append(String(hero.animator.get_animation()))
		print("  连点四次 → %s" % " / ".join(played))
		_check(played.size() == 4
				and played[0] == "attack_1" and played[1] == "attack_2"
				and played[2] == "attack_3" and played[3] == "attack_1",
			"连点依次播放 attack_1 → attack_2 → attack_3 → 回到 attack_1")

		# 受击动画叠加：闪白 + hurt 动画同时生效
		hero.call("_on_damaged", Damage.new(1.0, null, Damage.Type.TRUE))
		var flash_val: float = float(
			(hero.animator.material as ShaderMaterial).get_shader_parameter("flash"))
		_check(hero.animator.get_animation() == &"hurt",
			"受击时切到 hurt 动画（当前 %s）" % String(hero.animator.get_animation()))
		_check(flash_val > 0.5, "受击闪白同时生效（flash = %.2f）" % flash_val)
		_check(hero.call("is_oneshot_active") == true,
			"一次性动画锁生效（受击期间不被移动动画覆盖）")

		# 空挥：把主角挪到射程内没有敌人的地方，出手同样要播动画并炸特效。
		# 这条是策划实测时提出的需求 —— 空地上连点鼠标必须有反应，
		# 否则根本没法规察三段连招的手感。
		# 位置 (250,120) 远离敌人走廊（y=480），且距走廊 > 敌人仇恨半径 304。
		hero.global_position = Vector2(250, 120)
		hero.set("_attack_cooldown", 0.0)
		await _advance(0.05)
		var nearest: Array[Node2D] = _battle.registry.query_enemies_in_radius(
			hero.global_position, hero.data.attack_range)
		var fx_before: int = _hit_effect_count()
		hero.call("_try_attack")
		await get_tree().process_frame
		var anim_now: String = String(hero.animator.get_animation())
		_check(nearest.is_empty(), "空挥测试位置射程内确实没有敌人（%d 个）" % nearest.size())
		_check(anim_now.begins_with("attack_"),
			"空挥也播放攻击动画（当前 %s）" % anim_now)
		_check(_hit_effect_count() > fx_before,
			"空挥也生成挥击特效（%d → %d）" % [fx_before, _hit_effect_count()])
	else:
		_check(false, "主角或精灵动画不可用，无法验证连招")

	print("")
	print("--- 9. 攻击时定身（不能边跑边打）---")
	if hero != null:
		# 策划实测反馈：主角能一边移动一边攻击太强了，出手必须有代价。
		hero.global_position = Vector2(250, 120)
		hero.set("_attack_cooldown", 0.0)
		hero.call("_try_attack")
		_check(hero.call("is_attack_in_progress") == true,
			"出手后进入定身状态（当前动画 %s）" % String(hero.animator.get_animation()))

		# 定身期间按住移动键，位置不应变化
		var pos_locked: Vector2 = hero.global_position
		Input.action_press(&"move_right")
		await _advance(0.2)
		var moved_locked: float = pos_locked.distance_to(hero.global_position)
		Input.action_release(&"move_right")
		_check(moved_locked < 1.0,
			"定身期间按住移动键也不位移（移动了 %.1f px）" % moved_locked)

		# 攻击结束后应恢复移动
		await _advance(0.6)
		_check(hero.call("is_attack_in_progress") == false, "攻击结束后解除定身")
		var pos_free: Vector2 = hero.global_position
		Input.action_press(&"move_right")
		await _advance(0.2)
		var moved_free: float = pos_free.distance_to(hero.global_position)
		Input.action_release(&"move_right")
		_check(moved_free > 5.0,
			"解除定身后可以移动（移动了 %.1f px，速度 %.0f px/s）" % [
				moved_free, hero.data.move_speed,
			])

	print("")
	print("--- 10. 复活惩罚曲线递增与封顶 ---")
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
	print("--- 11. 波次清空与胜负判定 ---")
	# 35 秒足够：诊断实测整局在 ~18 秒内结束（塔会把近战清光）。
	var cleared: bool = false
	var waited3: float = 0.0
	while waited3 < 35.0 and not _battle.rounds.is_battle_over():
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

	print("")
	print("--- 12. HUD 文字控件必须落在视口内 ---")
	# 这条拦住一个真实 bug：底部操作提示用 PRESET_BOTTOM_WIDE 挂在零尺寸的
	# 新建 Control 上，矩形从 y=视口高 往下长 → 整行画到屏幕外、界面空白，
	# **但完全不报错**。只有断言控件矩形在视口内才能发现。
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var hud_fields: Array[String] = [
		"_base_label", "_wave_label", "_enemy_label", "_currency_label",
		"_phase_label", "_hint_label", "_center_label",
	]
	var off_screen: PackedStringArray = PackedStringArray()
	for field: String in hud_fields:
		var c: Control = _battle.hud.get(field) as Control
		if c == null:
			off_screen.append("%s 不存在" % field)
			continue
		var r: Rect2 = c.get_global_rect()
		var inside: bool = r.position.x >= -1.0 and r.position.y >= -1.0 \
			and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0 \
			and r.size.x > 0.0 and r.size.y > 0.0
		if not inside:
			off_screen.append("%s rect=(%.0f,%.0f %.0fx%.0f)" % [
				field, r.position.x, r.position.y, r.size.x, r.size.y,
			])
	_check(off_screen.is_empty(),
		"HUD 的 %d 个文字控件都落在视口 %s 内%s" % [
			hud_fields.size(), str(vp),
			"" if off_screen.is_empty() else "（越界：%s）" % ", ".join(off_screen),
		])

	print("")
	print("--- 13. 重开：不退出即可从头再来一遍 ---")
	# 策划需求：打完一波想再测一遍时，不用退出去按 F5。
	# 这里验证 BattleRoot.restart() 的**就地重建**是否真的把状态清干净 ——
	# 重建不彻底会留下"幽灵单位"，而那种 bug 在画面上很难看出来，必须靠断言查。
	#
	# 注意：本测试跑完时的局面**不固定** —— headless 下塔的击杀时机有抖动，
	# 有时塔把敌人清光（胜利、大本营剩 ~72），有时一只敌人冲到把家打爆（失败、0）。
	# 两种情况都合法，上面的断言对此不敏感；而重开必须能从**任何一种**状态
	# （包括"已经输了、大本营是 0"）干净地重置回初始态。
	# ⚠️ 变量名不要与前面的步骤重复（base_before 在第 4 步已用过）——
	# 重复声明是**解析错误**，而解析错误的表现是"测试静默挂起"而不是报错退出。
	var base_at_restart: float = _battle.state.base_health
	var enemies_at_restart: int = _battle.registry.enemy_count()
	var deaths_at_restart: int = _battle.state.hero_death_count
	var hero_old: HeroUnit = _battle.get_hero()   # 留一份旧引用，用来查"幽灵单位"
	print("  重开前：大本营=%.0f 死亡次数=%d 场上敌人=%d 阶段=%s" % [
		base_at_restart, deaths_at_restart, enemies_at_restart,
		RoundManager.Phase.keys()[_battle.rounds.phase],
	])
	_battle.restart()
	await _advance(0.3)   # 等 queue_free 真正生效

	var problems: PackedStringArray = PackedStringArray()
	if not is_equal_approx(_battle.state.base_health, 100.0):
		problems.append("大本营血量 %.0f（应 100）" % _battle.state.base_health)
	if _battle.state.hero_death_count != 0:
		problems.append("死亡次数 %d（应 0）" % _battle.state.hero_death_count)
	if _battle.state.current_wave_index != 0:
		problems.append("波次索引 %d（应 0）" % _battle.state.current_wave_index)
	if _battle.registry.enemy_count() != 0:
		problems.append("场上敌人 %d（应 0）" % _battle.registry.enemy_count())
	if _battle.rounds.phase != RoundManager.Phase.PREPARE:
		problems.append("阶段 %s（应 PREPARE）" % RoundManager.Phase.keys()[_battle.rounds.phase])
	if _battle.registry.towers.size() != 1:
		problems.append("塔数量 %d（应 1）" % _battle.registry.towers.size())
	if _battle.get_map() == null:
		problems.append("地图没重建")
	if _battle.hud == null:
		problems.append("HUD 没重建")
	var hero_new: HeroUnit = _battle.get_hero()
	if hero_new == null or not hero_new.is_alive():
		problems.append("新主角不可用")
	elif not is_equal_approx(hero_new.health.current_health, hero_new.data.max_health):
		problems.append("新主角不是满血（%.0f）" % hero_new.health.current_health)
	# 关键：旧对象必须真的被释放，否则就是在场景里堆垃圾
	if hero_old != null and is_instance_valid(hero_old):
		problems.append("旧主角没被释放（幽灵单位）")

	_check(problems.is_empty(),
		"重开后回到干净初始状态%s" % (
			"" if problems.is_empty() else "（问题：%s）" % ", ".join(problems)
		))

	print("  重开后：大本营=%.0f 死亡次数=%d 场上敌人=%d 阶段=%s 塔=%d" % [
		_battle.state.base_health, _battle.state.hero_death_count,
		_battle.registry.enemy_count(),
		RoundManager.Phase.keys()[_battle.rounds.phase],
		_battle.registry.towers.size(),
	])

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


## 场上现存的命中特效数量（用于断言"出手真的炸了特效"）
func _hit_effect_count() -> int:
	if HitEffectSpawner.instance == null or not is_instance_valid(HitEffectSpawner.instance):
		return 0
	var n: int = 0
	for c: Node in HitEffectSpawner.instance.get_children():
		if c is AnimatedSprite2D:
			n += 1
	return n


func _finish() -> void:
	print("")
	if _fail == 0:
		print(">>> 冒烟测试全部通过（%d 项检查）<<<" % _checks)
	else:
		print(">>> 有 %d / %d 项失败 <<<" % [_fail, _checks])
	get_tree().quit(_fail)
