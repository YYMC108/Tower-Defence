class_name CharacterRegistry
extends RefCounted
## 角色配置注册表。
##
## 用 static 方法而不是 autoload：不需要实例，也不需要每帧存在，
## 这样可以少一个全局单例（DESIGN.md 第 11 节要求 autoload 数量克制）。
##
## 扫描 resources/characters/ 下所有 .tres，按 id 建索引。

const CHARACTER_DIR: String = "res://resources/characters/"

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func reload() -> void:
	_cache.clear()
	_loaded = true

	var dir: DirAccess = DirAccess.open(CHARACTER_DIR)
	if dir == null:
		push_warning("角色目录不存在: %s" % CHARACTER_DIR)
		return

	for file_name: String in dir.get_files():
		# 编辑器里未导入的资源会带 .remap 后缀，统一去掉
		var clean_name: String = file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres"):
			continue
		var res: Resource = ResourceLoader.load(CHARACTER_DIR + clean_name)
		if res is CharacterData:
			var data: CharacterData = res as CharacterData
			if data.id == &"":
				push_warning("角色缺少 id 字段: %s" % clean_name)
				continue
			_cache[data.id] = data


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


static func get_character(character_id: StringName) -> CharacterData:
	_ensure_loaded()
	var found: Variant = _cache.get(character_id, null)
	if found is CharacterData:
		return found as CharacterData
	push_error("找不到角色配置: %s" % character_id)
	return null


static func all_characters() -> Array[CharacterData]:
	_ensure_loaded()
	var result: Array[CharacterData] = []
	for value: Variant in _cache.values():
		if value is CharacterData:
			result.append(value as CharacterData)
	return result


## 取某一关要用的主角。本期先按 role 从全部角色里挑第一个 HERO。
static func find_hero() -> CharacterData:
	for data: CharacterData in all_characters():
		if data.role == CharacterData.Role.HERO:
			return data
	return null


static func count() -> int:
	_ensure_loaded()
	return _cache.size()
