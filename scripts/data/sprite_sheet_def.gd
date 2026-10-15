class_name SpriteSheetDef
extends Resource
## 一张横排 spritesheet 的定义。
##
## 设计要点：**帧数不硬编码在代码里，而是写进 .tres**。
## 美术改帧数只需要改配置，程序不用动。
##
## ⚠️【重要教训，别再踩】帧**不一定**是正方形的。
## ninja_attack.png 是 2048×128，但每帧是 **256×128**（挥刀会横向拉宽），
## 共 8 帧。如果按"帧数 = 宽 ÷ 高"去推断，会算成 16 帧，
## 于是每帧被从中间切成两半 —— 表现为**角色只剩半个身体**。
##
## 所以：**frame_count 必须显式填写**。留 0 只作为最后退路，且会发出警告。

@export var animation_name: StringName = &"idle"
@export_file("*.png") var texture_path: String = ""
## 帧数。**应当显式填写**。
## 留 0 会退化成"按正方形假设推断（宽 ÷ 高）"并发出警告 ——
## 非正方形帧（如 256×128 的攻击图）会被切错，切勿依赖。
@export var frame_count: int = 0
## 默认帧率。若设置了 frame_durations，本字段被忽略。
@export var fps: float = 8.0
## 是否循环播放。攻击/受击这类一次性动画填 false。
@export var loop: bool = true
## 逐帧时长（秒）。留空则所有帧按 1/fps 等速播放。
## 用于表达"蓄力慢、出手快"这类节奏，例如美术给的 1.1/0.7/0.6/0.8。
@export var frame_durations: PackedFloat32Array = PackedFloat32Array()


## 实际帧数：显式配置优先，否则退化成正方形假设并警告
func resolve_frame_count(texture: Texture2D) -> int:
	if frame_count > 0:
		return frame_count
	if texture == null:
		return 0
	var h: int = texture.get_height()
	if h <= 0:
		return 0
	var inferred: int = int(texture.get_width() / h)
	push_warning(
		"SpriteSheetDef(%s) 未显式配置 frame_count，已按正方形假设推断为 %d 帧。" % [
			texture_path, inferred,
		]
		+ " 若该素材是非正方形帧（例如 2048x128 的 256x128 攻击图），"
		+ "这样会切错并导致角色只剩半个身体。请在 .tres 里显式填写 frame_count。"
	)
	return inferred


## 第 index 帧的时长（秒）
func duration_for_frame(index: int) -> float:
	if frame_durations.size() > index and frame_durations[index] > 0.0:
		return frame_durations[index]
	if fps > 0.0:
		return 1.0 / fps
	return 0.1
