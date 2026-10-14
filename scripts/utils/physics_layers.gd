class_name PhysicsLayers
extends RefCounted
## 物理层工具。
##
## 铁律（DESIGN.md 第 10.2 节）：脚本里一律用**层名**查层，禁止硬编码层号。
## 层名定义在 project.godot 的 [layer_names] 段，改动只发生在一处。
##
## 实现说明（这里踩过坑）：Godot 把层名存成**扁平键**——
##   layer_names/2d_physics/layer_1 = "terrain"
## 而不是一个嵌套字典，所以不能读 "layer_names/2d_physics" 再遍历。
## 必须逐个拼键去查。

const LAYER_COUNT: int = 32
const SECTION: String = "layer_names/2d_physics"

## 层名 -> 位掩码 的缓存，避免每次都遍历 32 个键
static var _bit_cache: Dictionary = {}
static var _name_cache: Dictionary = {}
static var _scanned: bool = false


static func _scan() -> void:
	_bit_cache.clear()
	_name_cache.clear()
	for i: int in range(1, LAYER_COUNT + 1):
		var key: String = "%s/layer_%d" % [SECTION, i]
		var value: Variant = ProjectSettings.get_setting(key, "")
		var layer_name: String = str(value)
		if layer_name.is_empty():
			continue
		_name_cache[layer_name] = i
		_bit_cache[StringName(layer_name)] = 1 << (i - 1)
	_scanned = true


static func bit(layer_name: StringName) -> int:
	if not _scanned:
		_scan()
	var cached: Variant = _bit_cache.get(layer_name, null)
	if cached != null:
		return int(cached)
	push_error("未找到物理层: %s（检查 project.godot 的 [layer_names]）" % layer_name)
	return 0


## 层名对应的层号（1-based），用于在编辑器里对照
static func layer_number(layer_name: StringName) -> int:
	if not _scanned:
		_scan()
	var cached: Variant = _name_cache.get(String(layer_name), null)
	return int(cached) if cached != null else -1


## 多个层名合成一个掩码
static func mask(layer_names: Array) -> int:
	var result: int = 0
	for n: Variant in layer_names:
		result |= bit(StringName(str(n)))
	return result


## 供测试用：列出所有已命名的层
static func all_layers() -> Dictionary:
	if not _scanned:
		_scan()
	return _name_cache.duplicate()


static func clear_cache() -> void:
	_bit_cache.clear()
	_name_cache.clear()
	_scanned = false
