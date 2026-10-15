class_name SpriteAnimator
extends AnimatedSprite2D
## 从 UnitSpriteSet 构建动画并播放。
##
## 用法（单位脚本的 _build_nodes 里）：
##     var animator := SpriteAnimator.attach(self, data.sprite_set)
##     if animator != null:
##         animator.play_animation(&"idle")
##
## 若 sprite_set 为空，attach 返回 null，单位保持原来的纯色方块占位绘制。
## 这样美术可以逐个交付素材，不需要等齐。

## 受击闪白用的 shader。挂成材质后每帧设 flash 参数即可，
## 与美术交付的受击特效 spritesheet 不冲突（可叠加）。
const HIT_FLASH_SHADER: Shader = preload("res://scripts/battle/components/hit_flash.gdshader")

## 当前播放的动画名
var _current: StringName = &""

## 攻击这类一次性动画结束时回调（由单位设置）
var on_animation_finished: Callable = Callable()


## 贴图资源是否存在。
## 用途：美术素材还没合并到 main 时，单位应优雅回退到占位方块，
## 而不是报一堆 "cannot open file" 错误。这样代码与素材可以分别推进。
static func texture_available(path: String) -> bool:
	if path.is_empty():
		return false
	return ResourceLoader.exists(path, "Texture2D")


## 把精灵挂到宿主节点上。返回 null 表示没有可用素材。
## display_scale 来自 CharacterData/EnemyData 的 sprite_scale（唯一来源）。
static func attach(host: Node2D, sprite_set: UnitSpriteSet, display_scale: float = 1.0) -> SpriteAnimator:
	if sprite_set == null or sprite_set.sheets.is_empty():
		return null

	var animator := SpriteAnimator.new()
	animator.name = "SpriteAnimator"
	animator.scale = Vector2.ONE * (display_scale if display_scale > 0.0 else 1.0)
	animator.centered = true
	animator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	animator.z_index = -1

	# 受击闪白材质。每个单位一份实例，互不影响。
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = HIT_FLASH_SHADER
	flash_mat.set_shader_parameter("flash", 0.0)
	animator.material = flash_mat

	var frames: SpriteFrames = animator.build_sprite_frames(sprite_set)
	if frames == null or frames.get_animation_names().is_empty():
		animator.free()
		return null

	animator.sprite_frames = frames
	host.add_child(animator)
	animator.animation_finished.connect(animator._on_animation_finished)
	return animator


## 构建 SpriteFrames。公开出来是为了能被单测直接验证。
func build_sprite_frames(sprite_set: UnitSpriteSet) -> SpriteFrames:
	var frames := SpriteFrames.new()
	# SpriteFrames 默认自带一个 "default" 动画，先删掉避免残留
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for sheet: SpriteSheetDef in sprite_set.sheets:
		if sheet == null or sheet.texture_path.is_empty():
			continue
		if not texture_available(sheet.texture_path):
			# 素材未交付/未合并时不报错，静默跳过 → 单位回退到占位方块
			continue
		var texture: Texture2D = load(sheet.texture_path) as Texture2D
		if texture == null:
			push_warning("精灵贴图加载失败: %s" % sheet.texture_path)
			continue

		var total: int = sheet.resolve_frame_count(texture)
		if total <= 0:
			push_warning("无法确定帧数: %s" % sheet.texture_path)
			continue

		var frame_w: int = texture.get_width() / total
		var frame_h: int = texture.get_height()

		frames.add_animation(sheet.animation_name)
		frames.set_animation_loop(sheet.animation_name, sheet.loop)
		# ⚠️ 必须固定为 1.0，只用逐帧 duration 控制速度。
		#
		# Godot 的实际算法是「帧时长 = duration ÷ animation_speed」。
		# 如果这里再填 fps、同时又给每帧 duration = 1/fps，
		# 速度会被平方（实测 11.1 fps 的动画跑成了 123 帧/秒，
		# 看起来像抽搐/闪烁）。所以 animation_speed 恒为 1.0，
		# 快慢完全由 SpriteSheetDef.duration_for_frame() 决定。
		frames.set_animation_speed(sheet.animation_name, 1.0)

		for i: int in range(total):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
			frames.add_frame(sheet.animation_name, atlas, sheet.duration_for_frame(i))

	return frames


func play_animation(animation_name: StringName, restart: bool = false) -> void:
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return
	if _current == animation_name and not restart and is_playing():
		return
	_current = animation_name
	play(animation_name)


## 某个动画完整播一遍需要的秒数
func animation_total_duration(animation_name: StringName) -> float:
	if sprite_frames == null or not sprite_frames.has_animation(animation_name):
		return 0.0
	var total: float = 0.0
	for i: int in range(sprite_frames.get_frame_count(animation_name)):
		total += sprite_frames.get_frame_duration(animation_name, i)
	return total


## 让某动画的播放时长正好等于 target_seconds。
##
## 用途：攻击动画应该「一次出手播一遍」。如果动画比攻击间隔长，
## 就会每帧被重头播放、永远播不完，表现为角色卡在攻击姿势上；
## 比间隔短则会有空档。这里按比例调整播放速度，使两者对齐。
## 返回实际使用的播放时长（秒）。
func fit_animation_to(animation_name: StringName, target_seconds: float) -> float:
	var total: float = animation_total_duration(animation_name)
	if total <= 0.0 or target_seconds <= 0.0:
		speed_scale = 1.0
		return total
	# 播放速度 = 原时长 / 期望时长。上限 6 倍，避免极端攻速下快成闪烁。
	speed_scale = clampf(total / target_seconds, 0.1, 6.0)
	return total / speed_scale


## 按水平朝向翻转精灵（素材只交付单朝向，左右靠引擎翻转）。
## horizontal_direction 接近 0 时保持当前朝向 —— 避免纯上下移动时来回抖动。
func set_facing(horizontal_direction: float) -> void:
	if absf(horizontal_direction) < 0.01:
		return
	flip_h = horizontal_direction < 0.0


## 设置受击闪白强度（0 = 正常，1 = 全白）。
##
## 为什么需要它：接入精灵后，原来的占位方块闪白逻辑（改绘制颜色）
## 被 has_sprite() 短路了，导致「被打中」完全没有视觉反馈。
## 材质是 per-instance 的，各单位互不影响。
func set_flash(amount: float, color: Color = Color.WHITE) -> void:
	var mat: ShaderMaterial = material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("flash_color", Vector3(color.r, color.g, color.b))
	mat.set_shader_parameter("flash", clampf(amount, 0.0, 1.0))


func current_animation_name() -> StringName:
	return _current


func _on_animation_finished() -> void:
	if on_animation_finished.is_valid():
		on_animation_finished.call(_current)
