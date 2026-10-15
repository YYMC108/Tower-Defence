@tool
extends SceneTree
## 一次性把 TileMapLayer 加进实验关卡地图并铺好地形。
##
## 用法：godot --headless --path . --script res://tools/paint_test_level.gd
##
## 铺法：
##   - 全图草地（三种草地随机变化，避免单调）
##   - 沿敌人路径铺一条石砖路走廊
##   - 大本营周围铺水泥
##
## 注意：TileMapLayer 设 z_index = -1，否则会盖住 test_level_map.gd
## 画的调试线（父节点 _draw 在子节点之下）。

const MAP_SCENE: String = "res://scenes/battle/map/test_level.tscn"
const TILESET: String = "res://resources/tilesets/test_level_tileset.tres"

## source_id -> 图块含义（与 gen 顺序一致）
const SRC_GRASS_A: int = 0
const SRC_GRASS_B: int = 1
const SRC_GRASS_C: int = 2
const SRC_PATH: int = 3
const SRC_CONCRETE: int = 4
const SRC_CONCRETE_CRACKED: int = 5
const SRC_GRATE: int = 6

const TILE: int = 16
const MAP_W: int = 30
const MAP_H: int = 20


func _init() -> void:
	print("=== 铺实验关卡地形 ===")

	var packed: PackedScene = load(MAP_SCENE) as PackedScene
	if packed == null:
		push_error("地图场景加载失败: %s" % MAP_SCENE)
		quit(1)
		return
	var root: Node = packed.instantiate()

	# 复用已有的 TileMapLayer，没有就新建
	var layer: TileMapLayer = root.get_node_or_null("Ground") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "Ground"
		# 放在最底层，避免盖住调试线与单位
		layer.z_index = -10
		root.add_child(layer)
		# ⚠️ 关键：pack() 只序列化 owner 指向根节点的子节点。
		#    新建节点不会自动设置 owner，漏了这一步它会被静默丢弃。
		layer.owner = root
		# 移到第一个子节点位置，保证层级清晰
		root.move_child(layer, 0)

	var ts: TileSet = load(TILESET) as TileSet
	if ts == null:
		push_error("TileSet 加载失败: %s" % TILESET)
		quit(1)
		return
	layer.tile_set = ts

	# ── 铺图 ──
	layer.clear()

	# 敌人路径与站位（像素 -> 瓦片行）
	var ground_row: int = 160 / TILE          # = 10
	var path_rows: Array[int] = [ground_row - 1, ground_row, ground_row + 1]

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015   # 固定种子，保证每次铺出来一样

	var painted_path: int = 0
	var painted_grass: int = 0
	var painted_concrete: int = 0

	for y: int in range(MAP_H):
		for x: int in range(MAP_W):
			var cell := Vector2i(x, y)
			var px: int = x * TILE + TILE / 2
			var py: int = y * TILE + TILE / 2

			# 大本营周围：水泥
			if px >= 400 and py >= 100 and py <= 220:
				var src: int = SRC_CONCRETE_CRACKED if rng.randf() < 0.3 else SRC_CONCRETE
				layer.set_cell(cell, src, Vector2i.ZERO)
				painted_concrete += 1
				continue

			# 敌人走廊：石砖路
			if path_rows.has(y) and px >= 16 and px <= 440:
				layer.set_cell(cell, SRC_PATH, Vector2i.ZERO)
				painted_path += 1
				continue

			# 其余：草地，三种随机
			var r: float = rng.randf()
			var grass_src: int = SRC_GRASS_A
			if r < 0.22:
				grass_src = SRC_GRASS_B
			elif r < 0.32:
				grass_src = SRC_GRASS_C
			layer.set_cell(cell, grass_src, Vector2i.ZERO)
			painted_grass += 1

	# 路径上点缀几块格栅
	layer.set_cell(Vector2i(9, ground_row), SRC_GRATE, Vector2i.ZERO)
	layer.set_cell(Vector2i(18, ground_row), SRC_GRATE, Vector2i.ZERO)

	print("  草地 %d 格 / 石路 %d 格 / 水泥 %d 格" % [painted_grass, painted_path, painted_concrete])

	# ── 存回场景 ──
	var new_packed := PackedScene.new()
	var err: int = new_packed.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(new_packed, MAP_SCENE)
	if err != OK:
		push_error("保存场景失败: %d" % err)
		quit(1)
		return

	print("  已写回 %s" % MAP_SCENE)
	# 释放临时实例，否则退出时会报一堆 RID/ObjectDB 泄漏，容易让人误以为出错
	root.free()
	print("")
	print(">>> 地形铺设完毕 <<<")
	quit(0)
