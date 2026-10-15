@tool
extends SceneTree
## 美术精灵切片回归测试。
##
## 运行方式：
##   godot --headless --path . --script res://tests/art_sprite_test.gd
##
## 退出码：0 = 全部通过；非 0 = 失败项数量。
##
## 为什么需要它：
##   曾经因为假设「帧是正方形的，所以 帧数 = 宽 ÷ 高」，
##   把 2048×128 的攻击图（每帧 256×128，共 8 帧）算成了 16 帧，
##   于是每帧被从中间切成两半 —— 表现为**角色只剩半个身体**，
##   而且只在攻击时出现。逻辑测试完全查不到这类问题。
##
##   本测试直接断言**每一帧的实际像素尺寸**，任何切片错误都会立刻暴露。

const CHARACTER_SET_DIR: String = "res://resources/characters/"
const ENEMY_SET_DIR: String = "res://resources/enemies/"

## 期望表：spriteset 文件 -> { 动画名: [帧数, 帧宽, 帧高] }
## 数据来源：ART_HANDOVER.md（已实测校验过，与素材实际像素一致）
const EXPECTED: Dictionary = {
	"characters/_spriteset_hero_ninja.tres": {
		"idle": [4, 128, 128],
		"run": [8, 128, 128],
		"attack": [8, 256, 128],   # ← 非正方形帧，就是这里出过 bug
	},
	"characters/_spriteset_tower_archer.tres": {"idle": [1, 64, 64]},
	"characters/_spriteset_tower_healer.tres": {"idle": [1, 64, 64]},
	"enemies/_spriteset_melee_grunt.tres": {
		"idle": [1, 32, 32],
		"run": [5, 32, 32],
	},
	"enemies/_spriteset_ranged_archer.tres": {
		"idle": [1, 32, 32],
		"run": [16, 32, 32],
	},
}

var _fail: int = 0
var _checks: int = 0


func _init() -> void:
	print("=== 美术精灵切片回归测试 ===")
	print("")

	for rel_path: String in EXPECTED.keys():
		var expect: Dictionary = EXPECTED[rel_path]
		var full_path: String = "res://resources/" + rel_path
		if rel_path.begins_with("characters/"):
			full_path = CHARACTER_SET_DIR + rel_path.trim_prefix("characters/")
		else:
			full_path = ENEMY_SET_DIR + rel_path.trim_prefix("enemies/")

		print("--- %s ---" % rel_path.trim_prefix("characters/").trim_prefix("enemies/"))
		var sprite_set: UnitSpriteSet = load(full_path) as UnitSpriteSet
		if sprite_set == null:
			print("  [失败] 无法加载 %s" % full_path)
			_fail += 1
			continue
		if sprite_set.sheets.is_empty():
			print("  [失败] sprite_set 里没有动画（素材可能未合并到当前分支）")
			_fail += 1
			continue

		var animator := SpriteAnimator.new()
		var frames: SpriteFrames = animator.build_sprite_frames(sprite_set)
		animator.free()
		if frames == null:
			print("  [失败] build_sprite_frames 返回 null")
			_fail += 1
			continue

		for anim_name: String in expect.keys():
			var spec: Array = expect[anim_name]
			var want_count: int = int(spec[0])
			var want_w: int = int(spec[1])
			var want_h: int = int(spec[2])
			_check_animation(frames, StringName(anim_name), want_count, want_w, want_h)
		print("")

	print("=== 附加检查 ===")
	_check_animation_speed_is_one()
	_check_flip_exists()
	_check_durations_sane()

	print("")
	if _fail == 0:
		print(">>> 精灵切片测试全部通过（%d 项检查）<<<" % _checks)
	else:
		print(">>> 有 %d / %d 项失败 <<<" % [_fail, _checks])
	quit(_fail)


func _check_animation(frames: SpriteFrames, anim: StringName, want_count: int,
		want_w: int, want_h: int) -> void:
	_checks += 1
	if not frames.has_animation(anim):
		print("  [失败] 缺少动画 %s" % anim)
		_fail += 1
		return

	var got_count: int = frames.get_frame_count(anim)
	if got_count != want_count:
		print("  [失败] %s 帧数 期望 %d 实际 %d" % [anim, want_count, got_count])
		_fail += 1
		return

	# 逐帧检查像素尺寸 —— 切片错误会在这里被抓住
	for i: int in range(got_count):
		var tex: Texture2D = frames.get_frame_texture(anim, i)
		if tex == null:
			print("  [失败] %s 第 %d 帧无贴图" % [anim, i])
			_fail += 1
			return
		if tex.get_width() != want_w or tex.get_height() != want_h:
			print("  [失败] %s 第 %d 帧尺寸 期望 %dx%d 实际 %dx%d" % [
				anim, i, want_w, want_h, tex.get_width(), tex.get_height(),
			])
			_fail += 1
			return

	# 额外确认：若帧宽 != 帧高，说明是非正方形帧，必须与期望一致
	var non_square: bool = want_w != want_h
	print("  [通过] %-7s %2d 帧 × %dx%d%s" % [
		anim, got_count, want_w, want_h, "  (非正方形帧)" if non_square else "",
	])


func _check_animation_speed_is_one() -> void:
	_checks += 1
	var sprite_set: UnitSpriteSet = load(CHARACTER_SET_DIR + "_spriteset_hero_ninja.tres") as UnitSpriteSet
	if sprite_set == null:
		print("  [失败] 无法加载主角 spriteset")
		_fail += 1
		return
	var animator := SpriteAnimator.new()
	var frames: SpriteFrames = animator.build_sprite_frames(sprite_set)
	animator.free()
	# animation_speed 必须为 1.0：否则会与逐帧 duration 叠加，速度被平方
	for anim: StringName in frames.get_animation_names():
		if not is_equal_approx(frames.get_animation_speed(anim), 1.0):
			print("  [失败] %s 的 animation_speed 应为 1.0（否则速度被平方），实际 %.2f" % [
				anim, frames.get_animation_speed(anim),
			])
			_fail += 1
			return
	print("  [通过] 所有动画的 animation_speed 均为 1.0（速度只由逐帧 duration 决定）")


func _check_flip_exists() -> void:
	_checks += 1
	var animator := SpriteAnimator.new()
	var has_method: bool = animator.has_method("set_facing")
	animator.free()
	if not has_method:
		print("  [失败] SpriteAnimator 缺少 set_facing()，左右朝向无法翻转")
		_fail += 1
		return
	print("  [通过] SpriteAnimator.set_facing() 存在（左右朝向翻转）")


## 检查动画总时长是否合理。
##
## 这条能拦住一次真实事故：美术给的攻击逐帧节奏被按「秒」理解，
## 攻击动画总长变成 6.90 秒，而攻击间隔只有 0.42 秒 ——
## 动画每 0.42 秒被重头播放，连第一帧都播不完，
## 角色永远卡在攻击姿势上（"攻击停顿感"）。
const MAX_SANE_ANIMATION_SECONDS: float = 2.0


func _check_durations_sane() -> void:
	_checks += 1
	var rel_paths: Array[String] = [
		CHARACTER_SET_DIR + "_spriteset_hero_ninja.tres",
		CHARACTER_SET_DIR + "_spriteset_tower_archer.tres",
		CHARACTER_SET_DIR + "_spriteset_tower_healer.tres",
		ENEMY_SET_DIR + "_spriteset_melee_grunt.tres",
		ENEMY_SET_DIR + "_spriteset_ranged_archer.tres",
	]
	var too_long: PackedStringArray = PackedStringArray()
	var summary: PackedStringArray = PackedStringArray()

	for path: String in rel_paths:
		var sprite_set: UnitSpriteSet = load(path) as UnitSpriteSet
		if sprite_set == null:
			continue
		var animator := SpriteAnimator.new()
		var frames: SpriteFrames = animator.build_sprite_frames(sprite_set)
		animator.free()
		if frames == null:
			continue
		var file: String = path.get_file()
		for anim: StringName in frames.get_animation_names():
			var total: float = 0.0
			for i: int in range(frames.get_frame_count(anim)):
				total += frames.get_frame_duration(anim, i)
			summary.append("%s/%s=%.2fs" % [file.trim_prefix("_spriteset_").trim_suffix(".tres"), anim, total])
			if total > MAX_SANE_ANIMATION_SECONDS:
				too_long.append("%s 的 %s 总长 %.2f 秒" % [file, anim, total])

	if too_long.is_empty():
		print("  [通过] 所有动画总时长均 ≤ %.1f 秒" % MAX_SANE_ANIMATION_SECONDS)
		print("        %s" % ", ".join(summary))
	else:
		print("  [失败] 以下动画总时长异常长（逐帧时长单位可能理解错了）：")
		for s: String in too_long:
			print("        %s" % s)
		print("        提示：逐帧时长很可能不是「秒」，而是相对权重或其它单位。")
		_fail += 1
