@tool
extends SceneTree
## 一次性生成美术配置资源（.tres）。
##
## 为什么用脚本生成而不是手写 .tres：
## 手写内联子资源时极易把 script 指向错的资源类（之前踩过：
## WaveSpawnEntry 写成了 WaveData，属性静默丢失）。用 ResourceSaver
## 生成可以保证类型与格式完全正确。
##
## 用法：godot --headless --path . --script res://tools/gen_art_resources.gd
##
## ⚠️⚠️ 这是**一次性引导脚本**，不是常规工具。⚠️⚠️
## 重跑它会**覆盖** resources/ 下这些 .tres 里的手工调整。
##
## 所以：
##   - 只想调动画快慢/帧数？**直接改 .tres**（在 Godot 检查器里点开就能改），
##     不要重跑本脚本。
##   - 确实要重跑本脚本（例如新增角色）？先把 .tres 里的调整同步回这里，
##     否则会被打回原样。
##
## 动画速度在哪调：每个 _spriteset_*.tres 里 SpriteSheetDef 的 `fps` 字段。
## 注意 sprite_animator.gd 把 animation_speed 固定为 1.0，速度**只**由 fps
## （即逐帧 duration = 1/fps）决定，改 fps 就是改快慢。

const SPRITES := "res://assets/sprites/"
const CHARACTERS := "res://resources/characters/"
const ENEMIES := "res://resources/enemies/"


func _init() -> void:
	print("=== 生成美术配置资源 ===")
	var written: int = 0

	# ── 主角 ninja ──────────────────────────────
	var ninja_set := UnitSpriteSet.new()
	ninja_set.sheets = [
		_sheet(&"idle", SPRITES + "hero/ninja_idle.png", 0, 8.0, true),
		_sheet(&"run", SPRITES + "hero/ninja_run.png", 0, 11.1, true),
		# attack 不填 frame_count：由 2048÷128 自动推断为 16 帧。
		# 美术文档写的是 8 帧、实际 16 帧；自动推断正好绕过这个文档错误。
		_sheet(&"attack", SPRITES + "hero/ninja_attack.png", 0, 10.0, false),
	]
	written += _save(ninja_set, "res://resources/characters/_spriteset_hero_ninja.tres")

	var hero := CharacterData.new()
	hero.id = &"hero_ninja"
	hero.display_name = "赛博忍者"
	hero.description = "主输出，玩家操控。同时是近战通往大本营的唯一物理阻挡。"
	hero.role = CharacterData.Role.HERO
	hero.tower_kind = CharacterData.TowerKind.NONE
	# ↓ 数值保持 M1 原样（用户已实测手感不错），仅替换美术
	hero.max_health = 140.0
	hero.move_speed = 92.0
	hero.attack_damage = 14.0
	hero.attack_interval = 0.42
	hero.attack_range = 54.0
	hero.damage_type = Damage.Type.PHYSICAL
	hero.targeting_strategy = &"nearest"
	hero.sprite_set = ninja_set
	hero.sprite_scale = 0.25   # 128px 画布 -> 游戏内 32px
	hero.copy_limit = 1
	hero.unlocked_by_default = true
	written += _save(hero, CHARACTERS + "hero_ninja.tres")

	# ── 输出塔 ──────────────────────────────────
	var archer_set := UnitSpriteSet.new()
	archer_set.sheets = [_sheet(&"idle", SPRITES + "towers/tower_archer_idle.png", 0, 5.0, true)]
	written += _save(archer_set, "res://resources/characters/_spriteset_tower_archer.tres")

	var tower_archer := CharacterData.new()
	tower_archer.id = &"tower_archer"
	tower_archer.display_name = "弓箭手塔"
	tower_archer.description = "输出塔。自动索敌攻击。主角死亡时它是唯一还能守住防线的东西。"
	tower_archer.role = CharacterData.Role.TOWER
	tower_archer.tower_kind = CharacterData.TowerKind.DPS
	tower_archer.max_health = 60.0
	tower_archer.attack_damage = 9.0
	tower_archer.attack_interval = 0.95
	tower_archer.attack_range = 96.0
	tower_archer.damage_type = Damage.Type.PHYSICAL
	tower_archer.targeting_strategy = &"nearest"
	tower_archer.sprite_set = archer_set
	tower_archer.sprite_scale = 0.5   # 64px 画布 -> 游戏内 32px
	tower_archer.copy_limit = 1
	tower_archer.unlocked_by_default = true
	written += _save(tower_archer, CHARACTERS + "tower_archer.tres")

	# ── 治疗塔 ──────────────────────────────────
	var healer_set := UnitSpriteSet.new()
	healer_set.sheets = [_sheet(&"idle", SPRITES + "towers/tower_healer_idle.png", 0, 5.0, true)]
	written += _save(healer_set, "res://resources/characters/_spriteset_tower_healer.tres")

	var tower_healer := CharacterData.new()
	tower_healer.id = &"tower_healer"
	tower_healer.display_name = "治疗塔"
	tower_healer.description = "治疗塔。主角唯一的回血手段，让治疗塔成为构筑必需。"
	tower_healer.role = CharacterData.Role.TOWER
	tower_healer.tower_kind = CharacterData.TowerKind.HEAL
	tower_healer.max_health = 50.0
	tower_healer.attack_range = 110.0
	tower_healer.heal_amount = 6.0
	tower_healer.heal_interval = 1.6
	tower_healer.targeting_strategy = &"nearest"
	tower_healer.sprite_set = healer_set
	tower_healer.sprite_scale = 0.5
	tower_healer.copy_limit = 1
	tower_healer.unlocked_by_default = true
	written += _save(tower_healer, CHARACTERS + "tower_healer.tres")

	# ── 近战小兵 ────────────────────────────────
	var grunt_set := UnitSpriteSet.new()
	grunt_set.sheets = [
		_sheet(&"idle", SPRITES + "enemies/melee_grunt_idle.png", 0, 5.0, true),
		_sheet(&"run", SPRITES + "enemies/melee_grunt_run.png", 0, 10.0, true),
	]
	written += _save(grunt_set, "res://resources/enemies/_spriteset_melee_grunt.tres")

	var grunt := EnemyData.new()
	grunt.id = &"melee_grunt"
	grunt.display_name = "近战小兵"
	grunt.placeholder_color = Color(0.85, 0.25, 0.25)
	grunt.can_damage_hero = true
	grunt.can_damage_tower = false   # 近战免疫塔
	grunt.can_damage_base = true
	grunt.attack_mode = EnemyData.AttackMode.MELEE
	grunt.attack_damage = 7.0
	grunt.attack_interval = 1.0
	grunt.attack_range = 26.0
	grunt.building_attack_range = 26.0
	grunt.max_health = 34.0
	grunt.move_speed = 36.0
	grunt.waypoint_reach_radius = 4.0
	grunt.hero_detect_radius = 76.0
	grunt.reward_battle_currency = 1
	grunt.sprite_set = grunt_set
	grunt.sprite_scale = 1.0          # 32px 画布 -> 游戏内 32px
	written += _save(grunt, ENEMIES + "melee_grunt.tres")

	# ── 远程弓手 ────────────────────────────────
	var archer_enemy_set := UnitSpriteSet.new()
	archer_enemy_set.sheets = [
		_sheet(&"idle", SPRITES + "enemies/ranged_archer_idle.png", 0, 5.0, true),
		_sheet(&"run", SPRITES + "enemies/ranged_archer_run.png", 0, 20.0, true),
	]
	written += _save(archer_enemy_set, "res://resources/enemies/_spriteset_ranged_archer.tres")

	var ranged := EnemyData.new()
	ranged.id = &"ranged_archer"
	ranged.display_name = "远程弓手"
	ranged.placeholder_color = Color(0.95, 0.55, 0.15)
	ranged.can_damage_hero = true
	ranged.can_damage_tower = true   # 远程是唯一能拆塔的敌人
	ranged.can_damage_base = false
	ranged.attack_mode = EnemyData.AttackMode.RANGED
	ranged.attack_damage = 6.0
	ranged.attack_interval = 1.5
	ranged.attack_range = 108.0
	ranged.building_attack_range = 26.0
	ranged.max_health = 26.0
	ranged.move_speed = 30.0
	ranged.waypoint_reach_radius = 4.0
	ranged.hero_detect_radius = 90.0
	ranged.reward_battle_currency = 1
	ranged.sprite_set = archer_enemy_set
	ranged.sprite_scale = 1.0
	written += _save(ranged, ENEMIES + "ranged_archer.tres")

	# ── 近战重装（暂无素材，保持占位方块）────────
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
	brute.attack_range = 28.0
	brute.building_attack_range = 28.0
	brute.max_health = 90.0
	brute.move_speed = 26.0
	brute.waypoint_reach_radius = 4.0
	brute.hero_detect_radius = 80.0
	brute.reward_battle_currency = 2
	# 美术尚未交付 melee_brute，留空 sprite_set → 自动回退占位方块
	brute.sprite_scale = 1.0
	written += _save(brute, ENEMIES + "melee_brute.tres")

	print("")
	print("共写出 %d 个资源文件" % written)
	print(">>> 生成完毕 <<<")
	quit(0)


func _sheet(anim: StringName, path: String, count: int, fps: float, loop: bool) -> SpriteSheetDef:
	var s := SpriteSheetDef.new()
	s.animation_name = anim
	s.texture_path = path
	s.frame_count = count
	s.fps = fps
	s.loop = loop
	return s


func _save(res: Resource, path: String) -> int:
	res.take_over_path(path)
	var err: int = ResourceSaver.save(res, path)
	if err != OK:
		push_error("保存失败 (%d): %s" % [err, path])
		return 0
	print("  已写入 %s" % path)
	return 1
