class_name SpriteSheetDef
extends Resource
## 一张横排 spritesheet 的定义。
##
## 设计要点：**帧数不硬编码在代码里，而是写进 .tres**。
## 美术改帧数只需要改配置，程序不用动。
##
## 这也正好覆盖美术交接文档里的两处问题：
##   - ninja_attack 实际 16 帧（文档写 8）→ 配置里填 16 即可，代码不在乎
##   - genji_attack 的逐帧节奏（不是固定帧率）→ 用 frame_durations 表达

@export var animation_name: StringName = &"idle"
@export_file("*.png") var texture_path: String = ""
## 帧数。填 0 表示"由图片宽度自动推断"（宽度 ÷ 高度）。
@export var frame_count: int = 0
## 默认帧率。若设置了 frame_durations，本字段被忽略。
@export var fps: float = 8.0
## 是否循环播放。攻击/受击这类一次性动画填 false。
@export var loop: bool = true
## 逐帧时长（秒）。留空则所有帧按 1/fps 等速播放。
## 用于表达"蓄力慢、出手快"这类节奏，例如美术给的 1.1/0.7/0.6/0.8。
@export var frame_durations: PackedFloat32Array = PackedFloat32Array()


## 实际帧数：显式配置优先，否则从图片推断
func resolve_frame_count(texture: Texture2D) -> int:
	if frame_count > 0:
		return frame_count
	if texture == null:
		return 0
	var h: int = texture.get_height()
	if h <= 0:
		return 0
	return int(texture.get_width() / h)


## 第 index 帧的时长（秒）
func duration_for_frame(index: int) -> float:
	if frame_durations.size() > index and frame_durations[index] > 0.0:
		return frame_durations[index]
	if fps > 0.0:
		return 1.0 / fps
	return 0.1
