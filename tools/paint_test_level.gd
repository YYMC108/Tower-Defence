@tool
extends SceneTree
## 重建实验关卡的 TileSet 与地形。
##
## 用法：godot --headless --path . --script res://tools/paint_test_level.gd
##
## 做两件事：
##   1. 确保 TileSet 的 tile_size = 64（源生素材也是 64，即 1:1，不缩放最锐利）
##   2. 按 24x15 格重铺地形（= 1536x960，正好等于视口，一屏放下整张地图）
##
## 世界尺度（见 DESIGN.md 15.11 与 project.godot）：
##   单位显示 128px、瓦片 64px —— 一个单位正好占 2x2 格，与改造前比例一致。
##
## 注意：TileMapLayer 设 z_index = -10，否则会盖住 test_level_map.gd 画的调试线
## （父节点的 _draw 在子节点之下）。

const MAP_SCENE: String = "res://scenes/battle/map/test_level.tscn"
const TILESET: String = "res://resources/tilesets/test_level_tileset.tres"
const TILE_SRC_DIR: String = "res://assets/tilesets/"

## 图块源顺序（必须与 _build_tileset() 里添加的顺序一致）
const SRC_GRASS_A: int = 0
const SRC_GRASS_B: int = 1
const SRC_GRASS_C: int = 2
const SRC_PATH: int = 3
const SRC_CONCRETE: int = 4
const SRC_CONCRETE_CRACKED: int = 5
const SRC_GRATE: int = 6

const TILE: int = 64
const MAP_W: int = 24
const MAP_H: int = 15
## 敌人走廊所在行（tile 行号）
const PATH_ROW: int = 7


func _init() -> void:
	print("=== 重建实验关卡（%dx%d 格 @ %dpx = %dx%d）===" % [
		MAP_W, MAP_H, TILE, MAP_W * TILE, MAP_H * TILE,
	])

	# ── 1. TileSet ──
	var ts: TileSet = _build_tileset()
	if ts == null:
		quit(1)
		return
	var err: int = ResourceSaver.save(ts, TILESET)
	if err != OK:
		push_error("TileSet 保存失败: %d" % err)
		quit(1)
		return
	print("  TileSet 已保存（tile_size = %s）" % str(ts.tile_size))

	# ── 2. 地图 ──
	var packed: PackedScene = load(MAP_SCENE) as PackedScene
	if packed == null:
		push_error("地图场景加载失败: %s" % MAP_SCENE)
		quit(1)
		return
	var root: Node = packed.instantiate()

	var layer: TileMapLayer = root.get_node_or_null("Ground") as TileMapLayer
	if layer == null:
		layer = TileMapLayer.new()
		layer.name = "Ground"
		layer.z_index = -10
		root.add_child(layer)
		# ⚠️ pack() 只序列化 owner 指向根节点的子节点，漏了这句会被静默丢弃
		layer.owner = root
		root.move_child(layer, 0)
	layer.tile_set = ts
	layer.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015

	var n_grass: int = 0
	var n_path: int = 0
	var n_concrete: int = 0

	for y: int in range(MAP_H):
		for x: int in range(MAP_W):
			var cell := Vector2i(x, y)

			# 据点周围铺水泥（据点在右侧走廊行上）
			if x >= 17 and y >= 5 and y <= 9:
				var src: int = SRC_CONCRETE_CRACKED if rng.randf() < 0.28 else SRC_CONCRETE
				layer.set_cell(cell, src, Vector2i.ZERO)
				n_concrete += 1
				continue

			# 敌人走廊：石砖路（走廊行上下各一格，共 3 格宽）
			if absi(y - PATH_ROW) <= 1 and x >= 1 and x <= 21:
				layer.set_cell(cell, SRC_PATH, Vector2i.ZERO)
				n_path += 1
				continue

			# 其余草地（三色随机）
			var r: float = rng.randf()
			var g: int = SRC_GRASS_A
			if r < 0.20:
				g = SRC_GRASS_B
			elif r < 0.30:
				g = SRC_GRASS_C
			layer.set_cell(cell, g, Vector2i.ZERO)
			n_grass += 1

	# 走廊上点缀格栅
	layer.set_cell(Vector2i(4, PATH_ROW), SRC_GRATE, Vector2i.ZERO)
	layer.set_cell(Vector2i(14, PATH_ROW), SRC_GRATE, Vector2i.ZERO)

	print("  草地 %d / 石路 %d / 水泥 %d 格" % [n_grass, n_path, n_concrete])

	var new_packed := PackedScene.new()
	err = new_packed.pack(root)
	if err != OK:
		push_error("pack 失败: %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(new_packed, MAP_SCENE)
	if err != OK:
		push_error("地图保存失败: %d" % err)
		quit(1)
		return
	print("  地图已写回 %s" % MAP_SCENE)
	# 释放临时实例，否则退出时报一堆 RID/ObjectDB 泄漏，容易让人误以为出错
	root.free()

	print("")
	print(">>> 关卡重建完毕 <<<")
	quit(0)


## 按 7 张地形图重建 TileSet（tile_size = TILE，源区域 = 源图尺寸，1:1 无缩放）
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var names: Array[String] = [
		"tile_grass_01", "tile_grass_02", "tile_grass_03",
		"tile_path_01", "tile_concrete_01", "tile_concrete_04", "tile_grate_01",
	]
	for n: String in names:
		var path: String = TILE_SRC_DIR + n + ".png"
		if not ResourceLoader.exists(path, "Texture2D"):
			push_error("地形素材缺失: %s" % path)
			return null
		var tex: Texture2D = load(path) as Texture2D
		var source := TileSetAtlasSource.new()
		source.texture = tex
		source.texture_region_size = Vector2i(tex.get_width(), tex.get_height())
		source.create_tile(Vector2i.ZERO)
		ts.add_source(source)
	return ts
