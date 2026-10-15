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
		frames.set_animation_speed(sheet.animation_name, sheet.fps)

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


func current_animation_name() -> StringName:
	return _current


func _on_animation_finished() -> void:
	if on_animation_finished.is_valid():
		on_animation_finished.call(_current)
