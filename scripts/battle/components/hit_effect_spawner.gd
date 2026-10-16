class_name HitEffectSpawner
extends Node2D
## 命中特效生成器。
##
## 【为什么需要它】之前受击只有 shader 闪白，没有"火花"。美术交付了
## `fx_slash_red`（32×32 × 3 帧）后，需要一个地方在**受击点**把它炸出来。
##
## 【用法】BattleRoot 创建一份挂在实体容器下，单位侧这样调用：
##     HitEffectSpawner.spawn_at(受击点世界坐标, 朝向x)
## 没有生成器时（例如单元测试里没建战斗场景）静默跳过，不报错。
##
## 【为什么用 static var 而不是到处传引用】
## 特效是纯表现，让它沿着"攻击者 → 生成器"的链条层层传参会污染所有单位的签名。
## 这里用一份实例引用（_ready 注册、_exit_tree 注销），单位侧一次静态调用即可。
##
## 【与美术交付的"受击动画"不冲突】
## 三者可同时存在：shader 闪白（即时）+ hurt 动画（姿态）+ 本特效（火花）。

const DEFAULT_EFFECT_SET: String = "res://resources/effects/_spriteset_fx_slash_red.tres"
## 特效显示倍率。特效画布 32px，与世界尺度一致 ×4 → 128px。
const EFFECT_SCALE: float = 4.0
## 生成位置上浮的随机抖动（像素），避免连续命中时火花完全重叠
const JITTER: float = 10.0

static var instance: HitEffectSpawner

var _frames: SpriteFrames = null
var _anim_name: StringName = &""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	instance = self
	_rng.randomize()
	_load_effect()


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _load_effect() -> void:
	if not ResourceLoader.exists(DEFAULT_EFFECT_SET, "Resource"):
		# 素材未合并时静默跳过 —— 特效是纯表现，不该阻塞战斗
		return
	var set_res: UnitSpriteSet = load(DEFAULT_EFFECT_SET) as UnitSpriteSet
	if set_res == null or set_res.sheets.is_empty():
		return
	var helper := SpriteAnimator.new()
	_frames = helper.build_sprite_frames(set_res)
	helper.free()
	if _frames == null:
		return
	var names: PackedStringArray = _frames.get_animation_names()
	if not names.is_empty():
		_anim_name = names[0]


func has_effect() -> bool:
	return _frames != null and _anim_name != &""


## 在指定世界坐标炸一个特效。facing_x < 0 时水平翻转。
## 没有特效素材时什么都不做（安全）。
static func spawn_at(world_position: Vector2, facing_x: float = 0.0) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	instance._spawn(world_position, facing_x)


func _spawn(world_position: Vector2, facing_x: float) -> void:
	if not has_effect():
		return
	var fx := AnimatedSprite2D.new()
	fx.name = "HitEffect"
	fx.sprite_frames = _frames
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.scale = Vector2.ONE * EFFECT_SCALE
	fx.global_position = world_position + Vector2(
		_rng.randf_range(-JITTER, JITTER), _rng.randf_range(-JITTER, JITTER)
	)
	# 画在单位之上（单位精灵的 z_index 是 -1）
	fx.z_index = 5
	if absf(facing_x) > 0.01:
		fx.flip_h = facing_x < 0.0
	add_child(fx)
	fx.play(_anim_name)
	# 特效是一次性动画，播完自删，不需要对象池（每个只活 0.19 秒）
	fx.animation_finished.connect(fx.queue_free, CONNECT_ONE_SHOT)
