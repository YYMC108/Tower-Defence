class_name BaseUnit
extends Node2D
## 大本营。
##
## 之前它只是 test_level_map.gd 里画的一个调试方框，**没有实体节点**，
## 美术的大本营素材无处可挂、也无法做受击反馈。这个类补上。
##
## 职责边界（DESIGN.md 第 12 节）：
##   大本营**血量**存在 BattleState 里（战斗级状态，不是实体的 hp），
##   本节点只负责**表现**：显示精灵、受击闪白、损毁状态切换。
##
## 素材接入：
##   - sprite_set 为空时画调试方框（当前状态），有素材就自动改用精灵
##   - 可选动画名：idle（必需）/ damaged（受损）/ critical（濒危）
##     美术若只交 idle 也能跑；交了 damaged/critical 会在血量跨过阈值时自动切换

signal destroyed()

## 受击闪白时长（秒）
const HIT_FLASH_TIME: float = 0.12
## 血量比例低于此值切到 damaged（若素材提供该动画）
const DAMAGED_RATIO: float = 0.6
## 血量比例低于此值切到 critical（若素材提供该动画）
const CRITICAL_RATIO: float = 0.3

const DEBUG_COLOR: Color = Color(0.95, 0.85, 0.35)

var sprite_set: UnitSpriteSet
var sprite_scale: float = 0.5
## 无素材时的调试方框尺寸（游戏像素）
var display_size: Vector2 = Vector2(48, 48)

var animator: SpriteAnimator

var _hit_flash: float = 0.0
var _state: BattleState = null
var _current_anim: StringName = &"idle"


static func create(p_sprite_set: UnitSpriteSet, p_scale: float, p_size: Vector2) -> BaseUnit:
	var base := BaseUnit.new()
	base.name = "BaseUnit"
	base.sprite_set = p_sprite_set
	base.sprite_scale = p_scale
	base.display_size = p_size
	return base


func _ready() -> void:
	animator = SpriteAnimator.attach(self, sprite_set, sprite_scale)
	if animator != null:
		_current_anim = _animation_for_health_ratio(1.0)
		animator.play_animation(_current_anim)
	queue_redraw()


## 绑定战斗状态，用于受击闪白与损毁状态切换
func bind_state(state: BattleState) -> void:
	_state = state
	if _state != null:
		_state.base_health_changed.connect(_on_base_health_changed)


func has_sprite() -> bool:
	return animator != null


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
		if animator != null:
			animator.set_flash(_hit_flash / HIT_FLASH_TIME)
		queue_redraw()


func _on_base_health_changed(_current: float, _maximum: float) -> void:
	# 受击闪白
	_hit_flash = HIT_FLASH_TIME
	if animator != null:
		animator.set_flash(1.0)
	# 损毁状态切换（素材没有对应动画时保持 idle）
	_refresh_damage_animation()
	queue_redraw()
	if _state != null and not _state.is_base_alive():
		destroyed.emit()


func _refresh_damage_animation() -> void:
	if animator == null or _state == null:
		return
	var want: StringName = _animation_for_health_ratio(_state.base_ratio())
	if want == _current_anim:
		return
	_current_anim = want
	animator.play_animation(want)


## 按血量比例挑动画；素材缺哪个就退回 idle
func _animation_for_health_ratio(ratio: float) -> StringName:
	if animator == null:
		return &"idle"
	var want: StringName = &"idle"
	if ratio <= CRITICAL_RATIO:
		want = &"critical"
	elif ratio <= DAMAGED_RATIO:
		want = &"damaged"
	if animator.sprite_frames.has_animation(want):
		return want
	if animator.sprite_frames.has_animation(&"idle"):
		return &"idle"
	return animator.sprite_frames.get_animation_names()[0]


## 无素材时的调试绘制：方框 + 四角标记
func _draw() -> void:
	if has_sprite():
		return
	var half: Vector2 = display_size * 0.5
	var rect := Rect2(-half, display_size)
	var col: Color = DEBUG_COLOR
	if _hit_flash > 0.0:
		col = col.lerp(Color.WHITE, 0.8)
	draw_rect(rect, Color(col, 0.18), true)
	draw_rect(rect, col, false, 2.0)
	draw_line(-half, half, col, 1.0)
	draw_line(Vector2(-half.x, half.y), Vector2(half.x, -half.y), col, 1.0)
