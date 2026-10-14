class_name TestLevelMap
extends Node2D
## 实验关卡地图。
##
## 【地图契约】任何地图场景只要满足下面这套节点约定，就能直接被 battle_root 使用。
## 代码通过**节点组**查找要素，所以关卡设计者增删塔位/路径点完全是编辑器操作，
## 不需要改一行代码。详见 DESIGN.md 第 14 节。
##
## 必需节点（用组标记）：
##   组 "map_base"      : Marker2D  —— 大本营位置
##   组 "map_hero_start": Marker2D  —— 主角出生点
##   组 "map_spawn"     : Marker2D  —— 敌人出生点
##   组 "map_waypoint"  : Marker2D  —— 路径点（可多个，按子节点顺序连成路径）
##   组 "map_tower_slot": Marker2D  —— 塔位（可多个，数量 = 可部署塔数）
##
## 改"1 塔位 1 波"为"2 塔位 2 波"的完整步骤：
##   1. 复制一个 TowerSlots/TowerSlot 节点 → 塔位变 2
##   2. 在 resources/levels/test_level.tres 的 waves 数组加一个 WaveData → 波次变 2
##   3. 完成，不需要碰任何代码。

const GROUP_BASE: StringName = &"map_base"
const GROUP_HERO_START: StringName = &"map_hero_start"
const GROUP_SPAWN: StringName = &"map_spawn"
const GROUP_WAYPOINT: StringName = &"map_waypoint"
const GROUP_TOWER_SLOT: StringName = &"map_tower_slot"

## 路径线颜色（调试可视化）
const PATH_DEBUG_COLOR: Color = Color(0.9, 0.8, 0.4, 0.35)
const SLOT_DEBUG_COLOR: Color = Color(0.5, 0.9, 1.0, 0.55)
const BASE_DEBUG_COLOR: Color = Color(0.95, 0.85, 0.35, 0.9)


func _ready() -> void:
	queue_redraw()


func base_position() -> Vector2:
	var m: Node2D = _first_in_group(GROUP_BASE)
	if m != null:
		return m.global_position
	push_warning("地图缺少 map_base 标记，大本营位置回退到原点")
	return Vector2.ZERO


func hero_start_position() -> Vector2:
	var m: Node2D = _first_in_group(GROUP_HERO_START)
	if m != null:
		return m.global_position
	# 没标记就退到出生点附近，避免直接崩
	push_warning("地图缺少 map_hero_start 标记")
	return spawn_position() + Vector2(0, 0)


func spawn_position() -> Vector2:
	var m: Node2D = _first_in_group(GROUP_SPAWN)
	if m != null:
		return m.global_position
	push_warning("地图缺少 map_spawn 标记，敌人将从原点生成")
	return Vector2.ZERO


func tower_slot_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	# 按节点树顺序取，保证塔位索引稳定
	var slots: Array[Node] = get_tree().get_nodes_in_group(GROUP_TOWER_SLOT)
	for node: Node in slots:
		if node is Node2D and is_ancestor_of(node):
			result.append((node as Node2D).global_position)
	return result


func waypoint_positions() -> PackedVector2Array:
	var viewport_waypoints: Array[Node] = get_tree().get_nodes_in_group(GROUP_WAYPOINT)
	var points: PackedVector2Array = PackedVector2Array()
	# 只取本地图内的，并按节点在树中的先后顺序排列
	var ordered: Array[Node2D] = []
	for node: Node in viewport_waypoints:
		if node is Node2D and is_ancestor_of(node):
			ordered.append(node as Node2D)
	ordered.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.get_index() < b.get_index())
	for node2d: Node2D in ordered:
		points.append(node2d.global_position)
	return points


func _first_in_group(group: StringName) -> Node2D:
	for node: Node in get_tree().get_nodes_in_group(group):
		if node is Node2D and is_ancestor_of(node):
			return node as Node2D
	return null


func slot_count() -> int:
	return tower_slot_positions().size()


# ─────────────────────────────────────────────
# 调试绘制：把路径、塔位、大本营画出来，方便没有美术时看清布局
# ─────────────────────────────────────────────

func _draw() -> void:
	var points: PackedVector2Array = waypoint_positions()
	if points.size() >= 2:
		for i: int in range(points.size() - 1):
			draw_line(to_local(points[i]), to_local(points[i + 1]), PATH_DEBUG_COLOR, 3.0, true)
		for i: int in range(points.size()):
			draw_circle(to_local(points[i]), 2.5, PATH_DEBUG_COLOR)

	# 最后一段：从最后一个路径点到大本营
	if points.size() >= 1:
		draw_line(to_local(points[points.size() - 1]), to_local(base_position()), PATH_DEBUG_COLOR, 3.0, true)

	for slot: Vector2 in tower_slot_positions():
		var p: Vector2 = to_local(slot)
		draw_arc(p, 9.0, 0.0, TAU, 20, SLOT_DEBUG_COLOR, 1.0)
		draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), SLOT_DEBUG_COLOR, 1.0)
		draw_line(p + Vector2(0, -4), p + Vector2(0, 4), SLOT_DEBUG_COLOR, 1.0)

	var bp: Vector2 = to_local(base_position())
	draw_rect(Rect2(bp + Vector2(-14, -14), Vector2(28, 28)), BASE_DEBUG_COLOR, false, 2.0)
	draw_line(bp + Vector2(-14, -14), bp + Vector2(14, 14), BASE_DEBUG_COLOR, 1.0)
	draw_line(bp + Vector2(14, -14), bp + Vector2(-14, 14), BASE_DEBUG_COLOR, 1.0)
