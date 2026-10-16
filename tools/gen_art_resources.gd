@tool
extends SceneTree
## 一次性生成美术配置资源（.tres）。
##
## 用法：godot --headless --path . --script res://tools/gen_art_resources.gd
##
## ⚠️⚠️ 这是**一次性引导脚本**，重跑会**覆盖** resources/ 下这些 .tres 里的手工调整。
##   - 只想调动画快慢/帧数？**直接改 .tres**，不要重跑本脚本。
##   - 确实要重跑（例如新增角色）？先把 .tres 里的调整同步回这里。
##
## ─────────────────────────────────────────────────────────────
## 世界尺度：单位显示 128px、瓦片 64px、视口 1536x960
##
## 与改造前的比例关系（改造前：单位 32px、瓦片 16px、视口 480x320）：
##   - 单位与瓦片都是 ×4，所以「一个单位占 2x2 格」这个比例不变 → 玩法不变
##   - 视口 480x320 → 1536x960，所以同屏可见 24x15 格（原本 30x20）
##   - **距离与速度全部 ×4**；体力/伤害/时间**不缩放**（它们是抽象值，不是空间量）
##
## 因此的 sprite_scale（源生画布 → 128px 显示）：
##   主角 128px 画布 → 1.0      塔 64px → 2.0     敌人 32px → 4.0
##   据点 256px → 1.0           特效 32px → 4.0   UI 128px → 1.0
##
## ⚠️ frame_count 必须显式填写：帧不一定是正方形的
##   （主角三段攻击是 384x256、重装敌人 run/attack 是 64x32）
## ─────────────────────────────────────────────────────────────

const SPRITES := "res://assets/sprites/"
const CHARACTERS := "res://resources/characters/"
const ENEMIES := "res://resources/enemies/"
const LEVELS := "res://resources/levels/"

## 世界尺度：所有「空间量」（距离/速度/半径）都乘这个数
const S: float = 4.0


func _init() -> void:
	print("=== 生成美术配置资源（世界尺度 x%.0f）===" % S)
	var written: int = 0

	# ═══════════ 主角 ninja ═══════════
	var ninja_set := UnitSpriteSet.new()
	ninja_set.sheets = [
		_sheet(&"idle", SPRITES + "hero/ninja_idle.png", 4, 8.0, true),
		_sheet(&"run", SPRITES + "hero/ninja_run.png", 8, 11.11, true),
		# 三段连招：三个独立动画，按「连点三次鼠标」依次播放
		_sheet(&"attack_1", SPRITES + "hero/ninja_attack_1.png", 4, 12.0, false),
		_sheet(&"attack_2", SPRITES + "hero/ninja_attack_2.png", 4, 12.0, false),
		_sheet(&"attack_3", SPRITES + "hero/ninja_attack_3.png", 5, 12.0, false),
		_sheet(&"hurt", SPRITES + "hero/ninja_hurt.png", 2, 12.0, false),
	]
	written += _save(ninja_set, CHARACTERS + "_spriteset_hero_ninja.tres")

	var ninja := CharacterData.new()
	ninja.id = &"hero_ninja"
	ninja.display_name = "赛博忍者"
	ninja.description = "主角。主输出，同时是近战通往大本营的唯一物理阻挡。"
	ninja.role = CharacterData.Role.HERO
	ninja.tower_kind = CharacterData.TowerKind.NONE
	ninja.max_health = 140.0
	ninja.move_speed = 92.0 * S              # 368
	ninja.attack_damage = 14.0
	ninja.attack_interval = 0.42
	ninja.attack_range = 54.0 * S            # 216
	ninja.damage_type = Damage.Type.PHYSICAL
	ninja.targeting_strategy = &"nearest"
	ninja.sprite_set = ninja_set
	ninja.sprite_scale = 1.0                 # 128px 画布 -> 128px 显示（1:1，细节全可见）
	ninja.copy_limit = 1
	ninja.unlocked_by_default = true
	written += _save(ninja, CHARACTERS + "hero_ninja.tres")

	# ═══════════ 主角 st（持盾，第二个主角）═══════════
	var st_set := UnitSpriteSet.new()
	st_set.sheets = [
		_sheet(&"idle", SPRITES + "hero/st_idle.png", 4, 8.0, true),
		_sheet(&"run", SPRITES + "hero/st_run.png", 14, 10.0, true),
		_sheet(&"attack_1", SPRITES + "hero/st_attack_1.png", 12, 12.0, false),
		_sheet(&"attack_2", SPRITES + "hero/st_attack_2.png", 6, 12.0, false),
		_sheet(&"attack_3", SPRITES + "hero/st_attack_3.png", 12, 12.0, false),
		_sheet(&"hurt", SPRITES + "hero/st_hurt.png", 2, 12.0, false),
		_sheet(&"recover", SPRITES + "hero/st_recover.png", 4, 12.0, false),
	]
	written += _save(st_set, CHARACTERS + "_spriteset_hero_st.tres")

	var st := CharacterData.new()
	st.id = &"hero_st"
	st.display_name = "重装持盾"
	st.description = "第二个主角。偏坦：移动慢、伤害低，但很能扛。具体数值待策划定。"
	st.role = CharacterData.Role.HERO
	st.tower_kind = CharacterData.TowerKind.NONE
	# ⚠️ 以下数值是**占位**：策划尚未定 st 的定位，先给一组「偏坦」的合理值
	st.max_health = 260.0
	st.move_speed = 70.0 * S                 # 280（比 ninja 慢）
	st.attack_damage = 9.0
	st.attack_interval = 0.55
	st.attack_range = 44.0 * S               # 176（比 ninja 短）
	st.damage_type = Damage.Type.PHYSICAL
	st.targeting_strategy = &"nearest"
	st.sprite_set = st_set
	st.sprite_scale = 1.0
	st.copy_limit = 1
	# 暂未解锁：等选人界面（M4）做好再开放，避免与 ninja 争「默认主角」
	st.unlocked_by_default = false
	written += _save(st, CHARACTERS + "hero_st.tres")

	# ═══════════ 输出塔 ═══════════
	var archer_set := UnitSpriteSet.new()
	archer_set.sheets = [
		_sheet(&"idle", SPRITES + "towers/tower_archer_idle.png", 4, 6.0, true),
	]
	written += _save(archer_set, CHARACTERS + "_spriteset_tower_archer.tres")

	var tower_archer := CharacterData.new()
	tower_archer.id = &"tower_archer"
	tower_archer.display_name = "弓箭手塔"
	tower_archer.description = "输出塔。自动索敌攻击。主角死亡时它是唯一还能守住防线的东西。"
	tower_archer.role = CharacterData.Role.TOWER
	tower_archer.tower_kind = CharacterData.TowerKind.DPS
	tower_archer.max_health = 60.0
	tower_archer.attack_damage = 9.0
	tower_archer.attack_interval = 0.95
	tower_archer.attack_range = 96.0 * S     # 384
	tower_archer.damage_type = Damage.Type.PHYSICAL
	tower_archer.targeting_strategy = &"nearest"
	tower_archer.sprite_set = archer_set
	tower_archer.sprite_scale = 2.0          # 64px 画布 -> 128px 显示
	tower_archer.copy_limit = 1
	tower_archer.unlocked_by_default = true
	written += _save(tower_archer, CHARACTERS + "tower_archer.tres")

	# ═══════════ 治疗塔 ═══════════
	var healer_set := UnitSpriteSet.new()
	healer_set.sheets = [
		_sheet(&"idle", SPRITES + "towers/tower_healer_idle.png", 4, 6.0, true),
	]
	written += _save(healer_set, CHARACTERS + "_spriteset_tower_healer.tres")

	var tower_healer := CharacterData.new()
	tower_healer.id = &"tower_healer"
	tower_healer.display_name = "治疗塔"
	tower_healer.description = "治疗塔。主角唯一的回血手段，让治疗塔成为构筑必需。"
	tower_healer.role = CharacterData.Role.TOWER
	tower_healer.tower_kind = CharacterData.TowerKind.HEAL
	tower_healer.max_health = 50.0
	tower_healer.attack_range = 110.0 * S    # 440
	tower_healer.heal_amount = 6.0
	tower_healer.heal_interval = 1.6
	tower_healer.targeting_strategy = &"nearest"
	tower_healer.sprite_set = healer_set
	tower_healer.sprite_scale = 2.0
	tower_healer.copy_limit = 1
	tower_healer.unlocked_by_default = true
	written += _save(tower_healer, CHARACTERS + "tower_healer.tres")

	# ═══════════ 近战小兵 ═══════════
	var grunt_set := UnitSpriteSet.new()
	grunt_set.sheets = [
		_sheet(&"idle", SPRITES + "enemies/melee_grunt_idle.png", 1, 5.0, true),
		_sheet(&"run", SPRITES + "enemies/melee_grunt_run.png", 5, 10.0, true),
		_sheet(&"attack", SPRITES + "enemies/melee_grunt_attack.png", 5, 12.0, false),
		_sheet(&"hurt", SPRITES + "enemies/melee_grunt_hurt.png", 2, 12.0, false),
	]
	written += _save(grunt_set, ENEMIES + "_spriteset_melee_grunt.tres")

	var grunt := EnemyData.new()
	grunt.id = &"melee_grunt"
	grunt.display_name = "近战小兵"
	grunt.placeholder_color = Color(0.85, 0.25, 0.25)
	grunt.can_damage_hero = true
	grunt.can_damage_tower = false           # 近战免疫塔
	grunt.can_damage_base = true
	grunt.attack_mode = EnemyData.AttackMode.MELEE
	grunt.attack_damage = 7.0
	grunt.attack_interval = 1.0
	grunt.attack_range = 26.0 * S            # 104
	grunt.building_attack_range = 26.0 * S   # 104
	grunt.max_health = 34.0
	grunt.move_speed = 36.0 * S              # 144
	grunt.waypoint_reach_radius = 4.0 * S    # 16
	grunt.hero_detect_radius = 76.0 * S      # 304
	grunt.reward_battle_currency = 1
	grunt.sprite_set = grunt_set
	grunt.sprite_scale = 4.0                 # 32px 画布 -> 128px 显示
	written += _save(grunt, ENEMIES + "melee_grunt.tres")

	# ═══════════ 近战重装（批次二新增；run/attack 是 64x32 非正方形帧）═══════════
	var brute_set := UnitSpriteSet.new()
	brute_set.sheets = [
		_sheet(&"idle", SPRITES + "enemies/melee_brute_idle.png", 1, 5.0, true),
		_sheet(&"run", SPRITES + "enemies/melee_brute_run.png", 7, 8.0, true),
		_sheet(&"attack", SPRITES + "enemies/melee_brute_attack.png", 13, 10.0, false),
		_sheet(&"hurt", SPRITES + "enemies/melee_brute_hurt.png", 2, 12.0, false),
	]
	written += _save(brute_set, ENEMIES + "_spriteset_melee_brute.tres")

	var brute := EnemyData.new()
	brute.id = &"melee_brute"
	brute.display_name = "近战重装"
	brute.placeholder_color = Color(0.6, 0.16, 0.16)
	brute.can_damage_hero = true
	brute.can_damage_tower = false
	brute.can_damage_base = true
	brute.attack_mode = EnemyData.AttackMode.MELEE
	brute.attack_damage = 14.0
	brute.attack_interval = 1.4
	brute.attack_range = 28.0 * S            # 112
	brute.building_attack_range = 28.0 * S   # 112
	brute.max_health = 90.0
	brute.move_speed = 26.0 * S              # 104
	brute.waypoint_reach_radius = 4.0 * S    # 16
	brute.hero_detect_radius = 80.0 * S      # 320
	brute.reward_battle_currency = 2
	brute.sprite_set = brute_set
	brute.sprite_scale = 4.0
	written += _save(brute, ENEMIES + "melee_brute.tres")

	# ═══════════ 远程弓手 ═══════════
	var archer_enemy_set := UnitSpriteSet.new()
	archer_enemy_set.sheets = [
		_sheet(&"idle", SPRITES + "enemies/ranged_archer_idle.png", 1, 5.0, true),
		_sheet(&"run", SPRITES + "enemies/ranged_archer_run.png", 16, 20.0, true),
		_sheet(&"attack", SPRITES + "enemies/ranged_archer_attack.png", 7, 12.0, false),
		# reload：美术新增动作，本期接在 attack 之后一起播（打完一梭子换弹）
		_sheet(&"reload", SPRITES + "enemies/ranged_archer_reload.png", 7, 10.0, false),
		_sheet(&"hurt", SPRITES + "enemies/ranged_archer_hurt.png", 2, 12.0, false),
	]
	written += _save(archer_enemy_set, ENEMIES + "_spriteset_ranged_archer.tres")

	var ranged := EnemyData.new()
	ranged.id = &"ranged_archer"
	ranged.display_name = "远程弓手"
	ranged.placeholder_color = Color(0.95, 0.55, 0.15)
	ranged.can_damage_hero = true
	ranged.can_damage_tower = true           # 远程是唯一能拆塔的敌人
	ranged.can_damage_base = false
	ranged.attack_mode = EnemyData.AttackMode.RANGED
	ranged.attack_damage = 6.0
	ranged.attack_interval = 1.5
	ranged.attack_range = 108.0 * S          # 432
	ranged.building_attack_range = 26.0 * S  # 104
	ranged.max_health = 26.0
	ranged.move_speed = 30.0 * S             # 120
	ranged.waypoint_reach_radius = 4.0 * S   # 16
	ranged.hero_detect_radius = 90.0 * S     # 360
	ranged.reward_battle_currency = 1
	ranged.sprite_set = archer_enemy_set
	ranged.sprite_scale = 4.0
	written += _save(ranged, ENEMIES + "ranged_archer.tres")

	# ═══════════ 关卡（含据点三态）═══════════
	var base_set := UnitSpriteSet.new()
	base_set.sheets = [
		_sheet(&"idle", SPRITES + "base/base_idle.png", 1, 5.0, true),
		_sheet(&"damaged", SPRITES + "base/base_damaged.png", 1, 5.0, true),
		_sheet(&"critical", SPRITES + "base/base_critical.png", 1, 5.0, true),
	]
	written += _save(base_set, LEVELS + "_spriteset_base.tres")

	var level := LevelData.new()
	level.id = &"level_test_01"
	level.display_name = "实验关卡 01"
	level.description = "M1 实验田。1 个塔位、1 波近战敌人。改 waves 数组可加波次，改地图 TowerSlots 可加塔位，都不需要改代码。"
	level.map_scene_path = "res://scenes/battle/map/test_level.tscn"
	level.base_max_health = 100.0
	level.starting_battle_currency = 10
	level.hero_revive_base_seconds = 5.0
	level.hero_revive_increment = 5.0
	level.hero_revive_max_seconds = 30.0
	level.reward_stars = 1
	level.reward_gold = 10
	# 据点三态（阈值在 base_unit.gd：DAMAGED_RATIO=0.6 / CRITICAL_RATIO=0.3）
	level.base_sprite_set = base_set
	level.base_sprite_scale = 1.0                 # 256px 画布 -> 256px 显示
	level.base_display_size = Vector2(192, 192)   # 无素材时的调试方框（3x3 格）

	# 波次：1 波 × 4 只近战小兵（与改造前一致，只改了空间尺度）
	var wave := WaveData.new()
	wave.id = &"wave_test_01"
	wave.display_name = "测试波次 1"
	wave.is_boss_wave = false
	var entry := WaveSpawnEntry.new()
	entry.enemy_data = grunt
	entry.count = 4
	entry.spawn_interval = 1.1
	entry.delay_before = 0.0
	wave.spawn_entries = [entry]
	level.waves = [wave]
	written += _save(level, LEVELS + "test_level.tres")

	print("")
	print("共写出 %d 个资源文件" % written)
	print(">>> 生成完毕 <<<")
	quit(0)


func _sheet(anim: StringName, path: String, count: int, fps: float, loop: bool) -> SpriteSheetDef:
	var s := SpriteSheetDef.new()
	s.animation_name = anim
	s.texture_path = path
	s.frame_count = count   # 显式填写，不依赖推断（帧不一定是正方形）
	s.fps = fps
	s.loop = loop
	return s


func _save(res: Resource, path: String) -> int:
	if res == null:
		push_error("要保存的资源为 null: %s" % path)
		return 0
	res.take_over_path(path)
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		push_error("保存失败 (%d): %s" % [err, path])
		return 0
	print("  已写入 %s" % path)
	return 1
